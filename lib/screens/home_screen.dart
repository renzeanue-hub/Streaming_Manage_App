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
  final CalendarController _controller = CalendarController()..view = CalendarView.week;

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
                onPressed: () => setState(() => _controller.view = CalendarView.day),
                icon: const Icon(Icons.view_day),
              ),
              IconButton(
                tooltip: '週',
                onPressed: () => setState(() => _controller.view = CalendarView.week),
                icon: const Icon(Icons.view_week),
              ),
              IconButton(
                tooltip: '月',
                onPressed: () => setState(() => _controller.view = CalendarView.month),
                icon: const Icon(Icons.calendar_month),
              ),
              IconButton(
                tooltip: '今日',
                onPressed: () => setState(() => _controller.displayDate = DateTime.now()),
                icon: const Icon(Icons.today),
              ),
              PopupMenuButton<_HomeMenuAction>(
                tooltip: 'メニュー',
                onSelected: (action) async {
                  switch (action) {
                    case _HomeMenuAction.signIn:
                      try {
                        await ref.read(authControllerProvider).signInWithGoogle();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ログイン失敗: $e')),
                        );
                      }
                      break;

                    case _HomeMenuAction.copyUid:
                      final user = ref.read(authStateProvider).requireValue;
                      if (user == null) return;
                      await Clipboard.setData(ClipboardData(text: user.uid));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UIDをコピーした')),
                      );
                      break;

                    case _HomeMenuAction.signOut:
                      await ref.read(authControllerProvider).signOut();
                      break;

                    case _HomeMenuAction.notificationSettings:
                      // TODO: 通知設定画面へ push
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('通知設定は未実装')),
                      );
                      break;

                    case _HomeMenuAction.wallpaperSettings:
                      // TODO: 壁紙設定画面へ push
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('壁紙設定は未実装')),
                      );
                      break;
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
                MaterialPageRoute(builder: (_) => AddStreamScreen(initialStartAt: base)),
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
                onStreamerFilterChanged: (ids) =>
                    ref.read(streamsProvider.notifier).setStreamerFilter(ids),
                onCategoryFilterChanged: (names) =>
                    ref.read(streamsProvider.notifier).setCategoryFilter(names),
              ),
              const Divider(height: 1),
              Expanded(
                child: SfCalendar(
                  key: ValueKey(_controller.view.toString()),
                  controller: _controller,
                  firstDayOfWeek: 1,
                  timeRegionBuilder: null,
                  timeSlotViewSettings: const TimeSlotViewSettings(
                    startHour: 0,
                    endHour: 24,
                    timeIntervalHeight: 56,
                  ),
                  monthViewSettings: const MonthViewSettings(
                    appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                  ),
                  dataSource: dataSource,
                  onTap: (details) async {
                    final app = details.appointments?.isNotEmpty == true
                        ? details.appointments!.first
                        : null;

                    // Appointment tap -> detail
                    if (app is Appointment && app.notes != null) {
                      final eventId = app.notes!;
                      final ev = state.streams.where((e) => e.id == eventId).firstOrNull;
                      if (ev != null) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => StreamDetailScreen(event: ev)),
                        );
                      }
                      return;
                    }

                    // Empty slot tap -> create new with tapped datetime
                    final tapped = details.date;
                    if (tapped != null) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AddStreamScreen(initialStartAt: tapped)),
                      );
                    }
                  },
                  appointmentBuilder: (context, details) {
                    final a = details.appointments.first as Appointment;
                    return _AppointmentTile(appointment: a);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<StreamEvent> _applyFilters(
    List<StreamEvent> streams,
    Set<String> streamerIds,
    Set<String> categoryNames,
  ) {
    return streams.where((e) {
      final okStreamer = streamerIds.isEmpty || streamerIds.contains(e.streamerId);
      final okCategory = categoryNames.isEmpty ||
          e.categories.any((c) => categoryNames.contains(c.name));
      return okStreamer && okCategory;
    }).toList();
  }

  Appointment _toAppointment(StreamEvent e, StreamsState state) {
    final streamer = state.streamers.where((s) => s.id == e.streamerId).firstOrNull;
    final color = streamer?.color ?? Colors.grey;

    final end = e.endAt ?? e.startAt.add(const Duration(hours: 2));

    return Appointment(
      startTime: e.startAt,
      endTime: end,
      subject: '${e.streamerNameSnapshot}\n${e.title}',
      color: color.withOpacity(0.92),
      notes: e.id,
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
  const _AppointmentTile({required this.appointment});

  final Appointment appointment;

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
        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
        child: Text(
          appointment.subject,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}