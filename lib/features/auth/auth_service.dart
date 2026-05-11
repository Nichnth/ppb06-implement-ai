import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFlowException(_authErrorMessage(error));
    }
  }

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      await credential.user?.updateDisplayName(fullName.trim());

      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFlowException('Could not create user account.');
      }

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'fullName': fullName.trim(),
        'email': email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (error) {
      throw AuthFlowException(_authErrorMessage(error));
    } on FirebaseException catch (_) {
      throw const AuthFlowException(
        'Account created, but profile setup failed. Please try again.',
      );
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }
}
