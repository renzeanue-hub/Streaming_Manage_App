import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:flutter/services.dart';

import '../models/stream_event.dart';
import '../providers/auth_provider.dart';
import '../providers/streams_provider.dart';
import '../widgets/calendar_header.dart';
import 'add_stream_screen.dart';
import 'stream_detail_screen.dart';
import 'dart:convert';

enum _HomeMenuAction {
  signIn,
  copyUid,
  signOut,
  notificationSettings,
  wallpaperSettings,
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final CalendarController _controller = CalendarController()
    ..view = CalendarView.week;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        final filtered = _applyFilters(
          state.streams,
          state.selectedStreamerIds,
          state.selectedCategoryNames,
        );

        final dataSource = _StreamCalendarDataSource(
          filtered.map((e) => _toAppointment(e, state)).toList(),
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('VALISカレンダー'),
            actions: [
              IconButton(
                tooltip: '日',
                // FIX: setState 不要、controller に直接セット
                onPressed: () => _controller.view = CalendarView.day,
                icon: const Icon(Icons.view_day),
              ),
              IconButton(
                tooltip: '週',
                onPressed: () => _controller.view = CalendarView.week,
                icon: const Icon(Icons.view_week),
              ),
              IconButton(
                tooltip: '月',
                onPressed: () => _controller.view = CalendarView.month,
                icon: const Icon(Icons.calendar_month),
              ),
              IconButton(
                tooltip: '今日',
                onPressed: () => _controller.displayDate = DateTime.now(),
                icon: const Icon(Icons.today),
              ),
              PopupMenuButton<_HomeMenuAction>(
                tooltip: 'メニュー',
                onSelected: (action) async {
                  switch (action) {
                    case _HomeMenuAction.signIn:
                      try {
                        await ref
                            .read(authControllerProvider)
                            .signInWithGoogle();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ログイン失敗: $e')),
                        );
                      }

                    case _HomeMenuAction.copyUid:
                      final user =
                          ref.read(authStateProvider).requireValue;
                      if (user == null) return;
                      await Clipboard.setData(
                          ClipboardData(text: user.uid));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UIDをコピーした')),
                      );

                    case _HomeMenuAction.signOut:
                      await ref.read(authControllerProvider).signOut();

                    case _HomeMenuAction.notificationSettings:
                      // TODO: 通知設定画面へ push
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('通知設定は未実装')),
                      );

                    case _HomeMenuAction.wallpaperSettings:
                      // TODO: 壁紙設定画面へ push
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('壁紙設定は未実装')),
                      );
                  }
                },
                itemBuilder: (context) {
                  final user = ref.watch(authStateProvider).valueOrNull;
                  final items = <PopupMenuEntry<_HomeMenuAction>>[];

                  if (user == null) {
                    items.add(const PopupMenuItem(
                      value: _HomeMenuAction.signIn,
                      child: Text('Googleでログイン'),
                    ));
                  } else {
                    items.add(const PopupMenuItem(
                      value: _HomeMenuAction.copyUid,
                      child: Text('UIDをコピー'),
                    ));
                    items.add(const PopupMenuItem(
                      value: _HomeMenuAction.signOut,
                      child: Text('ログアウト'),
                    ));
                  }

                  items.add(const PopupMenuDivider());
                  items.add(const PopupMenuItem(
                    value: _HomeMenuAction.notificationSettings,
                    child: Text('通知設定'),
                  ));
                  items.add(const PopupMenuItem(
                    value: _HomeMenuAction.wallpaperSettings,
                    child: Text('カレンダー壁紙設定'),
                  ));

                  return items;
                },
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              final base = _controller.displayDate ?? DateTime.now();
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        AddStreamScreen(initialStartAt: base)),
              );
            },
            child: const Icon(Icons.add),
          ),
          body: Column(
            children: [
              CalendarHeader(
                streamers: state.streamers,
                selectedStreamerIds: state.selectedStreamerIds,
                selectedCategoryNames: state.selectedCategoryNames,
                onStreamerFilterChanged: (ids) => ref
                    .read(streamsProvider.notifier)
                    .setStreamerFilter(ids),
                onCategoryFilterChanged: (names) => ref
                    .read(streamsProvider.notifier)
                    .setCategoryFilter(names),
              ),
              const Divider(height: 1),
              Expanded(
                child: SfCalendar(
                  // FIX: key 削除 — controller で view 管理できるので不要
                  // ValueKey で毎回 rebuild & スクロールリセットされてた
                  controller: _controller,
                  firstDayOfWeek: 1,
                  timeRegionBuilder: null,
                  timeSlotViewSettings: const TimeSlotViewSettings(
                    startHour: 0,
                    endHour: 24,
                    timeIntervalHeight: 56,
                  ),
                  monthViewSettings: const MonthViewSettings(
                    appointmentDisplayMode:
                        MonthAppointmentDisplayMode.none,
                  ),
                  dataSource: dataSource,
                  onTap: (details) async {
                    // 月ビュー: セルタップ → その日の日表示に切り替え
                    // 配信詳細リンクは月ビューでは不要（バーで存在は示せてる）
                    if (_controller.view == CalendarView.month) {
                      final tapped = details.date;
                      if (tapped != null) {
                        _controller.displayDate = tapped;
                        _controller.view = CalendarView.day;
                      }
                      return;
                    }
                    // 週・日ビュー: 配信ブロックタップ → 詳細画面
                    final app =
                        details.appointments?.isNotEmpty == true
                            ? details.appointments!.first
                            : null;
                    final eventId = _eventIdFromNotes(app?.notes);
                    if (eventId != null) {
                      final ev = state.streams
                          .where((e) => e.id == eventId)
                          .firstOrNull;
                      if (ev != null) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  StreamDetailScreen(eventId: ev.id)),
                        );
                        return;
                      }
                    }
                    // 空きスロットタップ → 新規追加
                    final tapped = details.date;
                    if (tapped != null) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                AddStreamScreen(initialStartAt: tapped)),
                      );
                    }
                  },
                  onLongPress: (details) async {
                    final dt = details.date;
                    if (dt == null) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              AddStreamScreen(initialStartAt: dt)),
                    );
                  },
                  monthCellBuilder: (context, details) {
                    final day = DateTime(details.date.year,
                        details.date.month, details.date.day);
                    final dayStart = day;
                    final dayEnd = day.add(const Duration(days: 1));

                    final eventsForDay = filtered.where((e) {
                      final start = e.startAt;
                      final end = e.endAt ??
                          e.startAt.add(const Duration(hours: 2));
                      return start.isBefore(dayEnd) &&
                          end.isAfter(dayStart);
                    }).toList();

                    final uniqueStreamerIds = <String>{};
                    for (final e in eventsForDay) {
                      uniqueStreamerIds.add(e.streamerId);
                    }

                    Color colorFor(String streamerId) {
                      final s = state.streamers
                          .where((x) => x.id == streamerId)
                          .firstOrNull;
                      // FIX: withOpacity → withValues (Flutter 3.27+)
                      return (s?.color ?? Colors.grey)
                          .withValues(alpha: 0.95);
                    }

                    final ids = uniqueStreamerIds.toList()..sort();
                    const maxBars = 4;
                    final shown = ids.take(maxBars).toList();
                    final remaining = ids.length - shown.length;
                    final isToday = DateUtils.isSameDay(
                        details.date, DateTime.now());

                    return Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: isToday
                            ? Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${details.date.day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final streamerId in shown)
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              height: 7,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colorFor(streamerId),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          if (remaining > 0) ...[
                            const SizedBox(height: 2),
                            // FIX: Colors.black54 → Theme 対応色
                            Text(
                              '+$remaining',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                  appointmentBuilder: (context, details) {
                    final a =
                        details.appointments.first as Appointment;
                    final tags = _tagsFromNotes(a.notes);
                    return _AppointmentTile(
                        appointment: a, tags: tags);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String? _eventIdFromNotes(String? notes) {
    if (notes == null) return null;
    try {
      final m = jsonDecode(notes) as Map<String, dynamic>;
      final id = m['id'];
      return id is String ? id : null;
    } catch (_) {
      return notes;
    }
  }

  List<String> _tagsFromNotes(String? notes) {
    if (notes == null) return const [];
    try {
      final m = jsonDecode(notes) as Map<String, dynamic>;
      final raw = m['tags'];
      if (raw is List) {
        return raw
            .map((x) => x.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  List<StreamEvent> _applyFilters(
    List<StreamEvent> streams,
    Set<String> streamerIds,
    Set<String> categoryNames,
  ) {
    return streams.where((e) {
      final okStreamer =
          streamerIds.isEmpty || streamerIds.contains(e.streamerId);
      final okCategory = categoryNames.isEmpty ||
          e.categories.any((c) => categoryNames.contains(c.name));
      return okStreamer && okCategory;
    }).toList();
  }

  Appointment _toAppointment(StreamEvent e, StreamsState state) {
    final streamer =
        state.streamers.where((s) => s.id == e.streamerId).firstOrNull;
    final color = streamer?.color ?? Colors.grey;
    final end = e.endAt ?? e.startAt.add(const Duration(hours: 2));

    final notes = jsonEncode({
      'id': e.id,
      'tags': e.tags.take(3).toList(),
    });

    return Appointment(
      startTime: e.startAt,
      endTime: end,
      subject: '${e.streamerNameSnapshot}\n${e.title}',
      // FIX: withOpacity → withValues (Flutter 3.27+)
      color: color.withValues(alpha: 0.92),
      notes: notes,
      isAllDay: false,
    );
  }
}

class _StreamCalendarDataSource extends CalendarDataSource {
  _StreamCalendarDataSource(List<Appointment> source) {
    appointments = source;
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    this.tags = const [],
  });

  final Appointment appointment;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: appointment.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
            color: Colors.white, fontSize: 12, height: 1.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                appointment.subject,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final t in tags.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        // FIX: withOpacity → withValues (Flutter 3.27+)
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// FIX: Dart 2.18+ で Iterable に firstOrNull が標準搭載されたので削除
