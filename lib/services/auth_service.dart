import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _google = GoogleSignIn();

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? gUser = await _google.signIn();
    if (gUser == null) return null;
    final gAuth = await gUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: gAuth.idToken,
      accessToken: gAuth.accessToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    return userCred.user;
  }

  static Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
