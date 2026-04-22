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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum _CalendarViewChoice { day, week, month }

class _HomeScreenState extends ConsumerState<HomeScreen> {
  CalendarView _view = CalendarView.week;

  final CalendarController _controller = CalendarController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CalendarView _choiceToView(_CalendarViewChoice c) => switch (c) {
        _CalendarViewChoice.day => CalendarView.day,
        _CalendarViewChoice.week => CalendarView.week,
        _CalendarViewChoice.month => CalendarView.month,
      };

  String _viewLabel(CalendarView v) => switch (v) {
        CalendarView.day => '日',
        CalendarView.week => '週',
        CalendarView.month => '月',
        _ => '表示',
      };

  @override
  Widget build(BuildContext context) {
    final streamsAsync = ref.watch(streamsProvider);

    return streamsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Load failed: $e'))),
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
                tooltip: '今日',
                onPressed: () {
                  // Jump back to today; keep current view.
                  setState(() {
                    _controller.displayDate = DateTime.now();
                  });
                },
                icon: const Icon(Icons.today),
              ),
              PopupMenuButton<_CalendarViewChoice>(
                tooltip: '表示切替',
                onSelected: (c) {
                  setState(() {
                    _view = _choiceToView(c);
                  });
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _CalendarViewChoice.day, child: Text('日')),
                  PopupMenuItem(value: _CalendarViewChoice.week, child: Text('週')),
                  PopupMenuItem(value: _CalendarViewChoice.month, child: Text('月')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: Text(_viewLabel(_view))),
                ),
              ),
              _authAction(ref, context),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              // Default: open add screen with "current displayed date" if available,
              // falling back to now. Minutes will be rounded in AddStreamScreen.
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
                  key: ValueKey(_view), // critical: ensure reliable view switching
                  controller: _controller,
                  view: _view,
                  firstDayOfWeek: 1,
                  timeSlotViewSettings: const TimeSlotViewSettings(
                    startHour: 0,
                    endHour: 24,
                    timeIntervalHeight: 56,
                  ),
                  monthViewSettings: const MonthViewSettings(
                    showNavigationArrow: true,
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

    final end = e.endAt ?? e.startAt.add(const Duration(hours: 1));

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

Widget _authAction(WidgetRef ref, BuildContext context) {
  final authAsync = ref.watch(authStateProvider);
  final uid = ref.watch(currentUidProvider);

  return authAsync.when(
    loading: () => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
    error: (e, st) => IconButton(
      onPressed: null,
      icon: const Icon(Icons.error_outline),
      tooltip: 'Auth error: $e',
    ),
    data: (user) {
      if (user == null) {
        return TextButton(
          onPressed: () async {
            try {
              await ref.read(authControllerProvider).signInWithGoogle();
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('ログイン失敗: $e')),
              );
            }
          },
          child: const Text('Googleでログイン'),
        );
      }

      final uid = user.uid;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'UIDをコピー: $uid',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: uid));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('UIDをコピーした')),
              );
            },
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'ログアウト',
            onPressed: () async {
              await ref.read(authControllerProvider).signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      );
    },
  );
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