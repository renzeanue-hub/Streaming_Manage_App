import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/stream_event.dart';
import '../providers/streams_provider.dart';
import 'add_stream_screen.dart';

class StreamDetailScreen extends ConsumerWidget {
  const StreamDetailScreen({super.key, required this.event});

  final StreamEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = _shareText(event);

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
                  content: Text('「${event.title}」を削除します。よろしいですか？'),
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
                await ref.read(streamsProvider.notifier).deleteStream(event.id);
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
            Text(event.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('配信者: ${event.streamerNameSnapshot}'),
            const SizedBox(height: 6),
            Text('開始: ${event.startAt}'),
            const SizedBox(height: 12),
            if (event.youtubeWatchUrl != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('YouTube'),
                subtitle: Text(event.youtubeWatchUrl!),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.tryParse(event.youtubeWatchUrl!);
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            if (event.archiveUrl != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('アーカイブ'),
                subtitle: Text(event.archiveUrl!),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.tryParse(event.archiveUrl!);
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _shareText(StreamEvent e) {
    final lines = <String>[
      '${e.streamerNameSnapshot} 配信予定',
      e.title,
      '開始: ${e.startAt}',
      if (e.youtubeWatchUrl != null) e.youtubeWatchUrl!,
    ];
    return lines.join('\n');
  }
}