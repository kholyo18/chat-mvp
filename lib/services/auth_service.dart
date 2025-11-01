import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _google = GoogleSignIn();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;
  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

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
    final GoogleSignInAccount? gUser = await _google.signIn();
    if (gUser == null) return null;
    final gAuth = await gUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: gAuth.idToken,
      accessToken: gAuth.accessToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    final user = userCred.user;
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
    await Future.wait([
      _google.signOut().catchError((_) {}),
      _auth.signOut(),
    ]);
  }

  static Future<void> linkWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No authenticated user to link with Google.',
      );
    }

    final GoogleSignInAccount? gUser = await _google.signIn();
    if (gUser == null) return;
    final gAuth = await gUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: gAuth.idToken,
      accessToken: gAuth.accessToken,
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
}
