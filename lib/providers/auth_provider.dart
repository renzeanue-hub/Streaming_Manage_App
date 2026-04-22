import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: const ['email'],
  );
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});

class AuthController {
  AuthController(this._ref);
  final Ref _ref;

  FirebaseAuth get _auth => _ref.read(firebaseAuthProvider);
  GoogleSignIn get _google => _ref.read(googleSignInProvider);

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');

      await _auth.signInWithPopup(provider);
      await _upsertUserDoc();
      return;
    }

    final googleUser = await _google.signIn();
    if (googleUser == null) return;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await _auth.signInWithCredential(credential);
    await _upsertUserDoc();
  }

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  Future<void> _upsertUserDoc() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(usersRef);
      if (!snap.exists) {
        tx.set(usersRef, {
          'role': 'normal',
          'createdAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(usersRef, {'lastSeenAt': FieldValue.serverTimestamp()});
      }
    });
  }
}

final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(firebaseAuthProvider).currentUser?.uid;
});

final copyUidProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await Clipboard.setData(ClipboardData(text: uid));
  };
});