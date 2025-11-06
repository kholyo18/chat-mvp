import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _webClientId = 'REPLACE_WITH_YOUR_WEB_CLIENT_ID';
  static final GoogleSignIn _google = GoogleSignIn(
    scopes: <String>['email', 'profile'],
    serverClientId: _webClientId,
  );

  static Future<void>? _googleInitialization;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;
  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  static Future<void> initializeGoogleSignIn() {
    _googleInitialization ??= _google
        .signInSilently()
        .catchError((Object error) {
          if (_isUserCancellationError(error)) {
            return null;
          }
          throw error;
        })
        .then<void>((_) {});
    return _googleInitialization!;
  }

  static Future<void> _ensureGoogleInitialized() async {
    final Future<void>? initialization = _googleInitialization;
    if (initialization != null) {
      await initialization;
      return;
    }
    await initializeGoogleSignIn();
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  static Future<UserCredential> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(fullName);
      await user.reload();

      await _firestore.collection('users').doc(user.uid).set(
        {
          'displayName': fullName,
          'email': email,
          'photoUrl': null,
          'providers': ['password'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await user.sendEmailVerification();
    }

    return credential;
  }

  static Future<UserCredential> signInWithEmail(
      String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'displayName': user.displayName,
          'email': user.email,
          'photoUrl': user.photoURL,
          'providers':
              user.providerData.map((p) => p.providerId).toSet().toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    return credential;
  }

  static Future<User?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    GoogleSignInAccount? account;
    try {
      account = await _google.signInSilently();
    } on PlatformException catch (e) {
      if (!_isUserCancellationError(e)) {
        rethrow;
      }
    }

    if (account == null) {
      try {
        account = await _google.signIn();
      } on PlatformException catch (e) {
        if (_isUserCancellationError(e)) {
          return null;
        }
        rethrow;
      }
    }

    if (account == null) {
      return null;
    }

    final GoogleSignInAuthentication authentication =
        await account.authentication;
    final String? idToken = authentication.idToken;

    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Unable to retrieve Google ID token.',
      );
    }

    final String? accessToken =
        authentication.accessToken ?? await _fetchAccessToken(account);

    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );

    final UserCredential userCred = await _auth.signInWithCredential(credential);
    final User? user = userCred.user;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'displayName': user.displayName,
          'email': user.email,
          'photoUrl': user.photoURL,
          'providers':
              user.providerData.map((p) => p.providerId).toSet().toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    return user;
  }

  static Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    if (user.emailVerified) return;
    await user.sendEmailVerification();
  }

  static Future<void> signOut() async {
    await _ensureGoogleInitialized();
    await _auth.signOut();
    await _google.signOut();
  }

  static Future<void> signOutAll() async {
    await _ensureGoogleInitialized();
    await _auth.signOut();
    await _google.disconnect();
  }

  static Future<void> linkWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No authenticated user to link with Google.',
      );
    }

    await _ensureGoogleInitialized();

    GoogleSignInAccount? account;
    try {
      account = await _google.signInSilently();
    } on PlatformException catch (e) {
      if (!_isUserCancellationError(e)) {
        rethrow;
      }
    }

    if (account == null) {
      try {
        account = await _google.signIn();
      } on PlatformException catch (e) {
        if (_isUserCancellationError(e)) {
          return;
        }
        rethrow;
      }
    }

    if (account == null) {
      return;
    }

    final GoogleSignInAuthentication authentication =
        await account.authentication;
    final String? idToken = authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Unable to retrieve Google ID token for linking.',
      );
    }

    final String? accessToken =
        authentication.accessToken ?? await _fetchAccessToken(account);

    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );

    final linked = await user.linkWithCredential(credential);
    final linkedUser = linked.user;
    if (linkedUser != null) {
      await _firestore.collection('users').doc(linkedUser.uid).set(
        {
          'displayName': linkedUser.displayName,
          'email': linkedUser.email,
          'photoUrl': linkedUser.photoURL,
          'providers': linkedUser.providerData
              .map((p) => p.providerId)
              .toSet()
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  static Exception _mapAuthError(FirebaseAuthException e) {
    final code = e.code;
    String ar;
    switch (code) {
      case 'invalid-email':
        ar = 'بريد إلكتروني غير صالح.';
        break;
      case 'user-not-found':
        ar = 'لا يوجد حساب بهذا البريد.';
        break;
      case 'too-many-requests':
        ar = 'طلبات كثيرة جدًا. جرّب لاحقًا.';
        break;
      case 'network-request-failed':
        ar = 'مشكلة في الاتصال. تأكد من الإنترنت.';
        break;
      default:
        ar = 'حدث خطأ غير متوقع. حاول لاحقًا.';
        break;
    }
    return Exception(ar);
  }

  static bool _isUserCancellationError(Object exception) {
    if (exception is PlatformException) {
      const cancellationCodes = <String>{
        GoogleSignIn.kSignInCanceledError,
        GoogleSignIn.kSignInRequiredError,
        GoogleSignInAccount.kFailedToRecoverAuthError,
        GoogleSignInAccount.kUserRecoverableAuthError,
      };
      return cancellationCodes.contains(exception.code);
    }
    return false;
  }

  static Future<String?> _fetchAccessToken(
    GoogleSignInAccount account,
  ) async {
    try {
      final GoogleSignInTokenData response =
          await GoogleSignInPlatform.instance.getTokens(
        email: account.email,
        shouldRecoverAuth: true,
      );
      return response.accessToken;
    } on PlatformException catch (e) {
      if (_isUserCancellationError(e)) {
        return null;
      }
      rethrow;
    }
  }
}
