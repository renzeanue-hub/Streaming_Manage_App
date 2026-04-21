import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/stream_status.dart';
import '../models/stream_event.dart';

class StreamDetailScreen extends StatelessWidget {
  const StreamDetailScreen({super.key, required this.event});

  final StreamEvent event;

  @override
  Widget build(BuildContext context) {
    final text = _shareText(event);

    return Scaffold(
      appBar: AppBar(
        title: const Text('配信詳細'),
        actions: [
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
            const SizedBox(height: 6),
            Text('ステータス: ${event.status.label}'),
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