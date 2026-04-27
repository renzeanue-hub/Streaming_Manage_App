import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/stream_event.dart';
import '../providers/streams_provider.dart';
import 'add_stream_screen.dart';
import '../models/stream_category.dart';
import '../models/stream_status.dart';


class StreamDetailScreen extends ConsumerWidget {
  const StreamDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final event = ref.watch(
      streamsProvider.select((s) => s.valueOrNull?.streams
        .where((e) => e.id == eventId).firstOrNull)
    );
    if (event == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final text = _shareText(event);
    final status = event.status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('配信詳細'),
        actions: [
          IconButton(
            tooltip: '編集',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddStreamScreen(initialEvent: event),
                ),
              );
            },
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: '削除',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('削除する？'),
                  content:
                      Text('「${event.title}」を削除します。よろしいですか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('削除'),
                    ),
                  ],
                ),
              );

              if (ok != true) return;

              try {
                await ref
                    .read(streamsProvider.notifier)
                    .deleteStream(event.id);
                if (context.mounted) Navigator.of(context).pop();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('削除失敗: $e')),
                );
              }
            },
            icon: const Icon(Icons.delete),
          ),
          IconButton(
            tooltip: 'シェア',
            onPressed: () => Share.share(text),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // サムネイル
            _ThumbnailSection(videoId: _extractVideoId(event.youtubeWatchUrl)),
            const SizedBox(height: 12),

            // ステータスバッジ（既存）
            _StatusBadge(status: status),
            const SizedBox(height: 10),

            // タイトル
            Text(
              event.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),

            // 配信者
            Text(
              '配信者: ${event.streamerNameSnapshot}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            // 時刻情報
            _TimeInfoCard(event: event),
            const SizedBox(height: 12),

            // カテゴリ
            _chipsSection(
              title: 'カテゴリ',
              items: event.categories.map((c) => c.label).toList(),
            ),
            const SizedBox(height: 12),

            // タグ
            _chipsSection(
              title: 'タグ',
              items: event.tags,
            ),
            const SizedBox(height: 12),

            // YouTubeリンク（配信中・予定）
            // アーカイブと同じURLのときは1行だけ表示
            if (event.youtubeWatchUrl != null) ...[
              _LinkTile(
                icon: Icons.play_circle_outline,
                label: status == StreamStatus.ended
                    ? 'アーカイブを見る'
                    : 'YouTubeで見る',
                url: event.youtubeWatchUrl!,
              ),
            ],

            // アーカイブが別URLのときだけ追加表示
            if (event.archiveUrl != null &&
                event.archiveUrl != event.youtubeWatchUrl) ...[
              const SizedBox(height: 4),
              _LinkTile(
                icon: Icons.archive_outlined,
                label: 'アーカイブ',
                url: event.archiveUrl!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipsSection({
    required String title,
    required List<String> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in items)
              Chip(
                label: Text(s),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }

  String _shareText(StreamEvent e) {
    final lines = <String>[
      e.title,
      if (e.youtubeWatchUrl != null) e.youtubeWatchUrl!,
    ];
    return lines.join('\n');
  }
}

// ---- サムネイル ----
class _ThumbnailSection extends StatelessWidget {
  const _ThumbnailSection({required this.videoId});
  final String? videoId;

  @override
  Widget build(BuildContext context) {
    if (videoId == null) return const SizedBox.shrink();

    final maxresUrl =
        'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
    final fallbackUrl =
        'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          maxresUrl,
          fit: BoxFit.cover,
          // maxresdefault が存在しない動画はhqdefaultにフォールバック
          errorBuilder: (_, __, ___) => Image.network(
            fallbackUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: const Center(
                child: Icon(Icons.image_not_supported_outlined, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ---- ステータスバッジ ----
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final StreamStatus status; // ← StreamStatus に変更

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      StreamStatus.live => (
          'LIVE',
          const Color(0xFFFCEBEB),
          const Color(0xFFA32D2D),
        ),
      StreamStatus.scheduled => (
          '配信予定',
          const Color(0xFFEEEDFE),
          const Color(0xFF3C3489),
        ),
      StreamStatus.ended => (
          '配信終了',
          const Color(0xFFF0F0F0),
          const Color(0xFF6B6B6B),
        ),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---- 時刻情報カード ----
class _TimeInfoCard extends StatelessWidget {
  const _TimeInfoCard({required this.event});
  final StreamEvent event;

  @override
  Widget build(BuildContext context) {
    final start = _formatDateTime(event.startAt);
    final end = event.endAt != null ? _formatDateTime(event.endAt!) : null;
    final duration = event.endAt != null
        ? _formatDuration(event.endAt!.difference(event.startAt))
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            _Row(label: '開始', value: start),
            if (end != null) ...[
              const SizedBox(height: 6),
              _Row(label: '終了', value: end),
            ],
            if (duration != null) ...[
              const SizedBox(height: 6),
              _Row(label: '配信時間', value: duration),
            ],
            if (end == null) ...[
              const SizedBox(height: 6),
              _Row(label: '終了', value: '未定'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// ---- リンクタイル ----
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.url,
  });
  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
      ),
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

// ---- 日時フォーマット ----
// intl パッケージなしでシンプルに整形
String _formatDateTime(DateTime dt) {
  final y = dt.year;
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$y/$mo/$d $h:$mi';
}

// "2:30:00.000000" → "2時間30分"
String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '$m分';
  if (m == 0) return '$h時間';
  return '$h時間$m分';
}
// ---- YouTube videoId 抽出 ----
String? _extractVideoId(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  // https://www.youtube.com/watch?v=XXXXX
  if (uri.queryParameters.containsKey('v')) {
    return uri.queryParameters['v'];
  }
  // https://youtu.be/XXXXX
  if (uri.host == 'youtu.be') {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }
  return null;
}