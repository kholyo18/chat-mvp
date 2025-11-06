import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final GoogleSignIn _google = GoogleSignIn(
    serverClientId: '1094490827601-adssi21hp0dl9m1s52f4kmnvdbqbbu9d.apps.googleusercontent.com',
    scopes: <String>['email', 'profile'],
  );

  static const List<String> _googleScopeHint = <String>['email', 'profile'];
  static Future<void>? _googleInitialization;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;
  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  static Future<void> initializeGoogleSignIn() {
    _googleInitialization ??= _google.initialize();
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
      final Future<GoogleSignInAccount?>? lightweightAttempt =
          _google.attemptLightweightAuthentication();
      if (lightweightAttempt != null) {
        account = await lightweightAttempt;
      }
    } on GoogleSignInException catch (e) {
      if (!_isUserCancellationError(e)) {
        rethrow;
      }
    }

    if (account == null) {
      try {
        account = await _google.authenticate(scopeHint: _googleScopeHint);
      } on GoogleSignInException catch (e) {
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

    final String? accessToken = await _fetchAccessToken(account);

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
      final Future<GoogleSignInAccount?>? lightweightAttempt =
          _google.attemptLightweightAuthentication();
      if (lightweightAttempt != null) {
        account = await lightweightAttempt;
      }
    } on GoogleSignInException catch (e) {
      if (!_isUserCancellationError(e)) {
        rethrow;
      }
    }

    if (account == null) {
      try {
        account = await _google.authenticate(scopeHint: _googleScopeHint);
      } on GoogleSignInException catch (e) {
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

    final String? accessToken = await _fetchAccessToken(account);

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

  static bool _isUserCancellationError(GoogleSignInException exception) {
    const cancellationCodes = <GoogleSignInExceptionCode>{
      GoogleSignInExceptionCode.canceled,
      GoogleSignInExceptionCode.interrupted,
      GoogleSignInExceptionCode.uiUnavailable,
    };
    final GoogleSignInExceptionCode? code = exception.code;
    return code != null && cancellationCodes.contains(code);
  }

  static Future<String?> _fetchAccessToken(
    GoogleSignInAccount account,
  ) async {
    if (_googleScopeHint.isEmpty) {
      return null;
    }

    final GoogleSignInAuthorizationClient? client =
        account.authorizationClient;
    if (client == null) {
      return null;
    }

    try {
      GoogleSignInClientAuthorization? authorization =
          await client.authorizationForScopes(_googleScopeHint);
      authorization ??= await client.authorizeScopes(_googleScopeHint);
      return authorization?.accessToken;
    } on GoogleSignInException catch (e) {
      if (_isUserCancellationError(e)) {
        return null;
      }
      rethrow;
    }
  }
}
