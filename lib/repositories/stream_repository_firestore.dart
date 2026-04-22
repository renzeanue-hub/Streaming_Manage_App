import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stream_category.dart';
import '../models/stream_event.dart';
import '../models/stream_status.dart';

class StreamRepositoryFirestore {
  StreamRepositoryFirestore(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('streams');

  Stream<List<StreamEvent>> watchAll() {
    return _col.orderBy('startAt').snapshots().map((snap) {
      return snap.docs.map((doc) {
        final j = doc.data();
        return StreamEvent(
          id: doc.id,
          streamerId: j['streamerId'] as String,
          streamerNameSnapshot: j['streamerNameSnapshot'] as String,
          title: j['title'] as String,
          startAt: (j['startAt'] as Timestamp).toDate(),
          endAt: j['endAt'] == null ? null : (j['endAt'] as Timestamp).toDate(),
          categories: ((j['categories'] as List?) ?? const [])
              .map((x) => StreamCategory.values.byName(x as String))
              .toList(),
          tags: ((j['tags'] as List?) ?? const []).map((x) => x.toString()).toList(),
          youtubeWatchUrl: j['youtubeWatchUrl'] as String?,
          archiveUrl: j['archiveUrl'] as String?,
          status: StreamStatus.values.byName(
            (j['status'] as String?) ?? StreamStatus.scheduled.name,
          ),
          note: j['note'] as String?,
        );
      }).toList();
    });
  }

  Future<void> add(StreamEvent e, {required String? uid}) async {
    await _col.add({
      'streamerId': e.streamerId,
      'streamerNameSnapshot': e.streamerNameSnapshot,
      'title': e.title,
      'startAt': Timestamp.fromDate(e.startAt),
      'endAt': e.endAt == null ? null : Timestamp.fromDate(e.endAt!),
      'categories': e.categories.map((c) => c.name).toList(),
      'tags': e.tags,
      'youtubeWatchUrl': e.youtubeWatchUrl,
      'archiveUrl': e.archiveUrl,
      'status': e.status.name,
      'note': e.note,
      'createdBy': uid,
      'updatedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update(
    String id, {
    required StreamEvent event,
    required String uid,
  }) async {
    final ref = _db.collection('streams').doc(id);

    await ref.update({
      'streamerId': event.streamerId,
      'streamerNameSnapshot': event.streamerNameSnapshot,
      'title': event.title,
      'startAt': Timestamp.fromDate(event.startAt),
      'endAt': event.endAt == null ? null : Timestamp.fromDate(event.endAt!),
      'categories': event.categories.map((c) => c.name).toList(),
      'tags': event.tags,
      'youtubeWatchUrl': event.youtubeWatchUrl,
      'archiveUrl': event.archiveUrl,
      'status': event.status.name,
      'note': event.note,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  Future<void> delete(
    String id, {
    required String uid,
  }) async {
    final ref = _db.collection('streams').doc(id);

    // 監査用に残したいなら update+delete の順でもいいけど、
    // ここは要件通り削除のみ。
    await ref.delete();
  }
}