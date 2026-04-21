import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

final hiveBoxProvider = FutureProvider<Box>((ref) async {
  final box = await Hive.openBox('app_box');
  return box;
});