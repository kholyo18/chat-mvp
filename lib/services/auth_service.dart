import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '1094490827601-adssi21hp0dl9m1s52f4kmnvdbqbbu9d.apps.googleusercontent.com',
  );

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'displayName': user.displayName,
          'email': user.email,
          'photoURL': user.photoURL,
          'providers': user.providerData.map((p) => p.providerId).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;
  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

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

  static Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    if (user.emailVerified) return;
    await user.sendEmailVerification();
  }

  static Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  static Future<void> signOutAll() async {
    await _auth.signOut();
    await _googleSignIn.disconnect();
  }

  static Future<void> linkWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No authenticated user to link with Google.',
      );
    }

    final GoogleSignInAccount? account = await _googleSignIn.signIn();
    if (account == null) {
      return;
    }

    final GoogleSignInAuthentication authentication =
        await account.authentication;

    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
      accessToken: authentication.accessToken,
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

}
