import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stream_category.dart';
import '../models/stream_event.dart';
import '../models/stream_status.dart';
import '../providers/streams_provider.dart';

class AddStreamScreen extends ConsumerStatefulWidget {
  const AddStreamScreen({super.key});

  @override
  ConsumerState<AddStreamScreen> createState() => _AddStreamScreenState();
}

class _AddStreamScreenState extends ConsumerState<AddStreamScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedStreamerId;
  StreamCategory _category = StreamCategory.game;

  final _titleController = TextEditingController();
  final _youtubeController = TextEditingController();

  DateTime _startAt = DateTime.now().add(const Duration(hours: 1));

  @override
  void dispose() {
    _titleController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(streamsProvider).requireValue;

    return Scaffold(
      appBar: AppBar(title: const Text('配信を追加')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '配信者'),
                items: [
                  for (final s in state.streamers)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedStreamerId = v),
                validator: (v) => v == null ? '配信者を選んでね' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '配信タイトル'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'タイトル入れてね' : null,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('開始時間'),
                subtitle: Text(_startAt.toString()),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    initialDate: _startAt,
                  );
                  if (date == null) return;

                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_startAt),
                  );
                  if (time == null) return;

                  setState(() {
                    _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StreamCategory>(
                decoration: const InputDecoration(labelText: 'カテゴリ'),
                value: _category,
                items: [
                  for (final c in StreamCategory.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.label),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _youtubeController,
                decoration: const InputDecoration(
                  labelText: 'YouTubeリンク（任意）',
                  hintText: 'https://www.youtube.com/watch?v=...',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;

                  try {
                    final streamer = state.streamers.firstWhere((s) => s.id == _selectedStreamerId);
                    final event = StreamEvent(
                      streamerId: streamer.id,
                      streamerNameSnapshot: streamer.name,
                      title: _titleController.text.trim(),
                      startAt: _startAt,
                      categories: [_category],
                      youtubeWatchUrl: _youtubeController.text.trim().isEmpty ? null : _youtubeController.text.trim(),
                      status: StreamStatus.scheduled,
                    );

                    await ref.read(streamsProvider.notifier).addStream(event);

                    if (mounted) Navigator.of(context).pop();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('登録失敗: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('登録'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}