import 'dart:convert';

import 'package:hive/hive.dart';
import '../models/stream_category.dart';
import '../models/stream_event.dart';
import '../models/stream_status.dart';

class StreamRepository {
  StreamRepository(this._box);

  final Box _box;

  static const _key = 'streams_v1';

  Future<List<StreamEvent>> loadAll() async {
    final raw = _box.get(_key);
    if (raw == null) return [];

    final list = (jsonDecode(raw as String) as List).cast<Map<String, dynamic>>();
    return list.map(_fromJson).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Future<void> saveAll(List<StreamEvent> streams) async {
    final list = streams.map(_toJson).toList();
    await _box.put(_key, jsonEncode(list));
  }

  Map<String, dynamic> _toJson(StreamEvent e) => {
        'id': e.id,
        'streamerId': e.streamerId,
        'streamerNameSnapshot': e.streamerNameSnapshot,
        'title': e.title,
        'startAt': e.startAt.toIso8601String(),
        'endAt': e.endAt?.toIso8601String(),
        'categories': e.categories.map((c) => c.name).toList(),
        'tags': e.tags,
        'youtubeWatchUrl': e.youtubeWatchUrl,
        'archiveUrl': e.archiveUrl,
        'status': e.status.name,
        'note': e.note,
      };

  StreamEvent _fromJson(Map<String, dynamic> j) => StreamEvent(
        id: j['id'] as String,
        streamerId: j['streamerId'] as String,
        streamerNameSnapshot: j['streamerNameSnapshot'] as String,
        title: j['title'] as String,
        startAt: DateTime.parse(j['startAt'] as String),
        endAt: j['endAt'] == null ? null : DateTime.parse(j['endAt'] as String),
        categories: (j['categories'] as List)
            .map((x) => StreamCategory.values.byName(x as String))
            .toList(),
        tags: (j['tags'] as List?)?.map((x) => x.toString()).toList() ?? const [],
        youtubeWatchUrl: j['youtubeWatchUrl'] as String?,
        archiveUrl: j['archiveUrl'] as String?,
        status: StreamStatus.values.byName(j['status'] as String),
        note: j['note'] as String?,
      );
}