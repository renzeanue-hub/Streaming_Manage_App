enum StreamStatus {
  scheduled,
  live,
  ended,
}

extension StreamStatusX on StreamStatus {
  String get label => switch (this) {
        StreamStatus.scheduled => '予定',
        StreamStatus.live => 'LIVE',
        StreamStatus.ended => '終了',
      };
}