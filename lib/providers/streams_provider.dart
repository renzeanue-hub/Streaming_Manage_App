import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stream_event.dart';
import '../models/streamer.dart';
import '../repositories/stream_repository_firestore.dart';
import '../repositories/streamer_repository.dart';
import 'auth_provider.dart';

class StreamsState {
  StreamsState({
    required this.streams,
    required this.streamers,
    this.selectedStreamerIds = const {},
    this.selectedCategoryNames = const {},
  });

  final List<StreamEvent> streams;
  final List<Streamer> streamers;

  final Set<String> selectedStreamerIds;
  final Set<String> selectedCategoryNames;

  StreamsState copyWith({
    List<StreamEvent>? streams,
    List<Streamer>? streamers,
    Set<String>? selectedStreamerIds,
    Set<String>? selectedCategoryNames,
  }) {
    return StreamsState(
      streams: streams ?? this.streams,
      streamers: streamers ?? this.streamers,
      selectedStreamerIds: selectedStreamerIds ?? this.selectedStreamerIds,
      selectedCategoryNames: selectedCategoryNames ?? this.selectedCategoryNames,
    );
  }
}

class StreamsController extends AsyncNotifier<StreamsState> {
  StreamSubscription<List<StreamEvent>>? _sub;

  @override
  Future<StreamsState> build() async {

    final streamers = const StreamerRepository().loadFixed();
    final repo = StreamRepositoryFirestore(FirebaseFirestore.instance);

    final completer = Completer<StreamsState>();

    _sub = repo.watchAll().listen((streams) {
      final current = state.valueOrNull;
      final next = (current == null)
          ? StreamsState(streams: streams, streamers: streamers)
          : current.copyWith(streams: streams, streamers: streamers);

      state = AsyncData(next);
      if (!completer.isCompleted) completer.complete(next);
    });

    ref.onDispose(() => _sub?.cancel());

    return completer.future;
  }

  Future<void> addStream(StreamEvent event) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final repo = StreamRepositoryFirestore(FirebaseFirestore.instance);
    if (uid == null) {
    throw Exception('追加するにはGoogleログインが必要です');
    }
    try {
      await repo.add(event, uid: uid);
    } on FirebaseException catch (e) {
      // permission-denied = bannedの想定
      if (e.code == 'permission-denied') {
        throw Exception('このアカウントは編集権限がありません');
      }
      rethrow;
    }
  }

  Future<void> setStreamerFilter(Set<String> ids) async {
    state = AsyncData(state.requireValue.copyWith(selectedStreamerIds: ids));
  }

  Future<void> setCategoryFilter(Set<String> categoryNames) async {
    state = AsyncData(state.requireValue.copyWith(selectedCategoryNames: categoryNames));
  }
}

final streamsProvider = AsyncNotifierProvider<StreamsController, StreamsState>(
  StreamsController.new,
);