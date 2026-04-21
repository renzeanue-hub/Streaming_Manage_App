import 'package:uuid/uuid.dart';
import 'stream_category.dart';
import 'stream_status.dart';

class StreamEvent {
  StreamEvent({
    String? id,
    required this.streamerId,
    required this.streamerNameSnapshot,
    required this.title,
    required this.startAt,
    this.endAt,
    required this.categories,
    this.tags = const [],
    this.youtubeWatchUrl,
    this.archiveUrl,
    this.status = StreamStatus.scheduled,
    this.note,
  }) : id = id ?? const Uuid().v4();

  final String id;

  final String streamerId;
  final String streamerNameSnapshot;

  final String title;
  final DateTime startAt;
  final DateTime? endAt;

  final List<StreamCategory> categories;
  final List<String> tags;

  final String? youtubeWatchUrl;
  final String? archiveUrl;

  final StreamStatus status;

  final String? note;

  StreamEvent copyWith({
    String? streamerId,
    String? streamerNameSnapshot,
    String? title,
    DateTime? startAt,
    DateTime? endAt,
    List<StreamCategory>? categories,
    List<String>? tags,
    String? youtubeWatchUrl,
    String? archiveUrl,
    StreamStatus? status,
    String? note,
  }) {
    return StreamEvent(
      id: id,
      streamerId: streamerId ?? this.streamerId,
      streamerNameSnapshot: streamerNameSnapshot ?? this.streamerNameSnapshot,
      title: title ?? this.title,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      youtubeWatchUrl: youtubeWatchUrl ?? this.youtubeWatchUrl,
      archiveUrl: archiveUrl ?? this.archiveUrl,
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }
}