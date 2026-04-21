import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final ensureAnonymousSignInProvider = FutureProvider<void>((ref) async {
  final auth = ref.watch(firebaseAuthProvider);

  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  }

  final uid = auth.currentUser!.uid;
  final users = FirebaseFirestore.instance.collection('users').doc(uid);

  // 初回だけ作成（roleはnormal）
  await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(users);
    if (!snap.exists) {
      tx.set(users, {
        'role': 'normal',
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } else {
      tx.update(users, {'lastSeenAt': FieldValue.serverTimestamp()});
    }
  });
});