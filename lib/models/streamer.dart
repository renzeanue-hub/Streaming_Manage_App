import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class Streamer {
  Streamer({
    String? id,
    required this.name,
    required this.colorValue,
    this.youtubeChannelUrl,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String name;
  final int colorValue;
  final String? youtubeChannelUrl;

  Color get color => Color(colorValue);

  Streamer copyWith({
    String? name,
    int? colorValue,
    String? youtubeChannelUrl,
  }) {
    return Streamer(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      youtubeChannelUrl: youtubeChannelUrl ?? this.youtubeChannelUrl,
    );
  }
}