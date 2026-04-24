import '../models/streamer.dart';

class StreamerRepository {
  const StreamerRepository();

  List<Streamer> loadFixed() {
    return [
      Streamer(id: 'chino', name: 'CHINO', colorValue: 0xFFE0E0E0),
      Streamer(id: 'neffy', name: 'NEFFY', colorValue: 0xFFdfacf6),
      Streamer(id: 'rara', name: 'RARA', colorValue: 0xFF2E8B57),
      Streamer(id: 'vitte', name: 'VITTE', colorValue: 0xFF4FC3F7),
    ];
  }
}