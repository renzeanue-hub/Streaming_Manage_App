import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stream_category.dart';
import '../models/stream_event.dart';
import '../models/stream_status.dart';
import '../providers/streams_provider.dart';

class AddStreamScreen extends ConsumerStatefulWidget {
  const AddStreamScreen({
    super.key,
    this.initialEvent,
    this.initialStartAt,
  });

  final StreamEvent? initialEvent;

  /// Opened from calendar empty-cell tap or FAB default.
  /// Ignored in edit mode.
  final DateTime? initialStartAt;

  bool get isEditMode => initialEvent != null;

  @override
  ConsumerState<AddStreamScreen> createState() => _AddStreamScreenState();
}

class _AddStreamScreenState extends ConsumerState<AddStreamScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedStreamerId;
  StreamCategory _category = StreamCategory.game;

  final _titleController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _tagController = TextEditingController();
  final List<String> _tags = [];
  String _tagQuery = '';

  late DateTime _startAt;

  DateTime _roundMinutesTo00(DateTime dt) => DateTime(dt.year, dt.month, dt.day, dt.hour, 0);

  @override
  void initState() {
    super.initState();

    final e = widget.initialEvent;
    if (e != null) {
      _tags
        ..clear()
        ..addAll(e.tags);
      _selectedStreamerId = e.streamerId;
      _titleController.text = e.title;
      _youtubeController.text = e.youtubeWatchUrl ?? '';
      _startAt = e.startAt;
      if (e.categories.isNotEmpty) {
        _category = e.categories.first;
      }
      return;
    }

    final base = widget.initialStartAt ?? DateTime.now();
    _startAt = _roundMinutesTo00(base);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _youtubeController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(streamsProvider).requireValue;

    final allTagCandidates = <String>{
      for (final ev in state.streams) ...ev.tags,
    }.toList()
      ..sort((a, b) => a.compareTo(b));

    List<String> suggestions() {
      final q = _tagQuery.trim();
      if (q.isEmpty) return const [];
      final lower = q.toLowerCase();

      final filtered = allTagCandidates
          .where((t) => !_tags.contains(t))
          .where((t) => t.toLowerCase().contains(lower))
          .take(10)
          .toList();

      // 入力中の文字が候補に無いなら「新規追加」枠として先頭に出す
      final exact = allTagCandidates.any((t) => t.toLowerCase() == lower) ||
          _tags.any((t) => t.toLowerCase() == lower);

      if (!exact) {
        filtered.insert(0, q); // 先頭に「q を追加」を出す
      }
      return filtered;
    }

    void addTag(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return;
      if (_tags.any((x) => x.toLowerCase() == t.toLowerCase())) return;

      setState(() {
        _tags.add(t);
        _tagController.clear();
        _tagQuery = '';
      });
    }

    void removeTag(String t) {
      setState(() => _tags.remove(t));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? '配信を編集' : '配信を追加'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '配信者'),
                value: _selectedStreamerId,
                items: [
                  for (final s in state.streamers)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name),
                    ),
                ],
                onChanged: widget.isEditMode ? null : (v) => setState(() => _selectedStreamerId = v),
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
            Text('タグ', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: () => removeTag(t),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'タグを追加',
                hintText: '例: マシュマロ読み / スト6 / 参加型',
              ),
              textInputAction: TextInputAction.done,
              onChanged: (v) => setState(() => _tagQuery = v),
              onSubmitted: (v) => addTag(v),
            ),
            Builder(
              builder: (context) {
                final items = suggestions();
                if (items.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    elevation: 1,
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = items[i];
                        final isNew = !allTagCandidates.contains(t);

                        return ListTile(
                          dense: true,
                          title: Text(isNew ? '追加: $t' : t),
                          trailing: const Icon(Icons.add),
                          onTap: () => addTag(t),
                        );
                      },
                    ),
                  ),
                );
              },
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

                    if (widget.isEditMode) {
                      final base = widget.initialEvent!;

                      final updated = base.copyWith(
                        streamerId: streamer.id,
                        streamerNameSnapshot: streamer.name,
                        title: _titleController.text.trim(),
                        startAt: _startAt,
                        categories: [_category],
                        tags: _tags,
                        youtubeWatchUrl: _youtubeController.text.trim().isEmpty
                            ? null
                            : _youtubeController.text.trim(),
                      );

                      await ref.read(streamsProvider.notifier).updateStream(updated.id, updated);
                    } else {
                      final created = StreamEvent(
                        streamerId: streamer.id,
                        streamerNameSnapshot: streamer.name,
                        title: _titleController.text.trim(),
                        startAt: _startAt,
                        categories: [_category],
                        tags: _tags,
                        youtubeWatchUrl: _youtubeController.text.trim().isEmpty
                            ? null
                            : _youtubeController.text.trim(),
                        status: StreamStatus.scheduled,
                      );

                      await ref.read(streamsProvider.notifier).addStream(created);
                    }

                    if (mounted) Navigator.of(context).pop();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(widget.isEditMode ? '更新失敗: $e' : '登録失敗: $e')),
                    );
                  }
                },
                icon: Icon(widget.isEditMode ? Icons.save_as : Icons.save),
                label: Text(widget.isEditMode ? '更新' : '登録'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}