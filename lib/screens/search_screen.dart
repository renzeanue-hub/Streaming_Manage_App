import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stream_event.dart';
import '../models/stream_category.dart';
import '../models/stream_status.dart';
import '../providers/streams_provider.dart';
import 'stream_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialTag});

  final String? initialTag;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  late final TextEditingController _searchController;
  late String _keyword;
  final Set<String> _selectedStreamerIds = {};
  final Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _keyword = widget.initialTag ?? '';
    _searchController = TextEditingController(text: _keyword);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // タグ一覧からタグをタップ → 検索タブにそのタグで飛ぶ
  void _searchByTag(String tag) {
    _searchController.text = tag;
    setState(() => _keyword = tag);
    _tabController.animateTo(0);
  }

  List<StreamEvent> _applyFilters(List<StreamEvent> streams) {
    return streams.where((e) {
      final kw = _keyword.trim().toLowerCase();
      final okKeyword = kw.isEmpty ||
          e.title.toLowerCase().contains(kw) ||
          e.streamerNameSnapshot.toLowerCase().contains(kw) ||
          e.tags.any((t) => t.toLowerCase().contains(kw));

      final okStreamer = _selectedStreamerIds.isEmpty ||
          _selectedStreamerIds.contains(e.streamerId);

      final okCategory = _selectedCategories.isEmpty ||
          e.categories.any((c) => _selectedCategories.contains(c.name));

      return okKeyword && okStreamer && okCategory;
    }).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
  }

  @override
  Widget build(BuildContext context) {
    final streamsAsync = ref.watch(streamsProvider);

    return streamsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(child: Text('Load failed: $e')),
      ),
      data: (state) {
        final filtered = _applyFilters(state.streams);

        // 全タグを集計（配信数も出す）
        final tagCount = <String, int>{};
        for (final e in state.streams) {
          for (final t in e.tags) {
            tagCount[t] = (tagCount[t] ?? 0) + 1;
          }
        }
        final sortedTags = tagCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)); // 件数降順

        return Scaffold(
          appBar: AppBar(
            title: const Text('検索'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '検索'),
                Tab(text: 'タグ一覧'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // ---- 検索タブ ----
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'タイトル・配信者名・タグで検索',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _keyword.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _keyword = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                      ),
                      onChanged: (v) => setState(() => _keyword = v),
                    ),
                  ),

                  // 配信者フィルター
                  if (state.streamers.isNotEmpty)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        children: state.streamers.map((s) {
                          final selected =
                              _selectedStreamerIds.contains(s.id);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(s.name),
                              selected: selected,
                              selectedColor:
                                  s.color.withValues(alpha: 0.25),
                              checkmarkColor: s.color,
                              side: BorderSide(
                                color: selected
                                    ? s.color
                                    : Colors.transparent,
                              ),
                              onSelected: (v) => setState(() {
                                if (v) {
                                  _selectedStreamerIds.add(s.id);
                                } else {
                                  _selectedStreamerIds.remove(s.id);
                                }
                              }),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // カテゴリフィルター
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      children: StreamCategory.values.map((c) {
                        final selected =
                            _selectedCategories.contains(c.name);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(c.label),
                            selected: selected,
                            onSelected: (v) => setState(() {
                              if (v) {
                                _selectedCategories.add(c.name);
                              } else {
                                _selectedCategories.remove(c.name);
                              }
                            }),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const Divider(height: 1),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length}件',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),

                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              '該当する配信がありません',
                              style:
                                  Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                12, 0, 12, 16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final ev = filtered[i];
                              final streamer = state.streamers
                                  .where((s) => s.id == ev.streamerId)
                                  .firstOrNull;
                              return _StreamResultCard(
                                event: ev,
                                streamerColor:
                                    streamer?.color ?? Colors.grey,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StreamDetailScreen(
                                        eventId: ev.id),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),

              // ---- タグ一覧タブ ----
              sortedTags.isEmpty
                  ? Center(
                      child: Text(
                        'タグがありません',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: sortedTags.length,
                      itemBuilder: (context, i) {
                        final tag = sortedTags[i].key;
                        final count = sortedTags[i].value;
                        return ListTile(
                          leading: const Icon(Icons.tag, size: 18),
                          title: Text(tag),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$count件',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ),
                          onTap: () => _searchByTag(tag),
                        );
                      },
                    ),
            ],
          ),
        );
      },
    );
  }
}

class _StreamResultCard extends StatelessWidget {
  const _StreamResultCard({
    required this.event,
    required this.streamerColor,
    required this.onTap,
  });

  final StreamEvent event;
  final Color streamerColor;
  final VoidCallback onTap;

  String _formatDateTime(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'
        ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel(StreamStatus status) {
    return switch (status) {
      StreamStatus.live => 'LIVE',
      StreamStatus.ended => '終了',
      StreamStatus.scheduled => '予定',
    };
  }

  Color _statusColor(StreamStatus status) {
    return switch (status) {
      StreamStatus.live => Colors.red,
      StreamStatus.ended => Colors.grey,
      StreamStatus.scheduled => Colors.blue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: streamerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          event.streamerNameSnapshot,
                          style: TextStyle(
                            fontSize: 12,
                            color: streamerColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDateTime(event.startAt),
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(event.status)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(event.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(event.status),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}