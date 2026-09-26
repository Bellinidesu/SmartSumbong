// SmartSumbong — duty status, app-wide.
//
// Branch B moved the status picker off Home into the middle of the nav
// bar, so it can be changed from any tab. What used to live in Home's
// state — the column, the save, and the location push — lives here now,
// in one place every tab shares.
//
// Location sharing follows. It used to run only while Home was open:
// location_is_fresh() (0005) discards a fix older than 15 minutes, so a
// tanod who sat on Reports or History — or locked the phone — dropped
// out of nearest_available_tanod's pool without any warning.
//
// Now, while on duty, a location stream runs as an Android foreground
// service (geolocator's own, with an ongoing "On duty" notification), so
// a fix reaches update_my_location() every 30 seconds whichever tab is
// showing, with the app in the background, or with the screen locked —
// the way real dispatch apps work. Going off duty, or signing out, stops
// it and clears the notification. Swiping the app away still ends it:
// that is the tanod saying "not now", and Android is right to honour it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors `public.duty_state` in 0001.
enum DutyState {
  onDuty('on_duty', 'On Duty'),
  breakTime('break', 'Break'),
  lunch('lunch', 'Lunch'),
  offline('offline', 'Offline');

  const DutyState(this.wire, this.label);

  final String wire;
  final String label;

  static DutyState? parse(String? w) {
    for (final s in DutyState.values) {
      if (s.wire == w) return s;
    }
    return null;
  }
}

/// What the last location push did, for the line under the picker.
enum LocationNote { sharing, shared, off, failed }

/// Why a status change was refused.
enum DutyError { notTanod, failed }

class DutyController extends ChangeNotifier {
  DutyController._();

  static final instance = DutyController._();

  DutyState? status;
  bool saving = false;
  LocationNote? note;

  String? _uid;
  Timer? _timer;

  /// The foreground-service location stream while on duty.
  StreamSubscription<Position>? _stream;
  DateTime? _lastPush;
  // One fix at a time. Indoors a fix can take the full 15-second timeout,
  // and the 30-second tick used to start a second GPS request and RPC on
  // top of one still running.
  bool _pushing = false;

  /// Reads the tanod's status. Safe to call from every tab: a second
  /// call for the same account only re-reads the column.
  Future<void> load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return reset();
    if (uid != _uid) {
      reset();
      _uid = uid;
    }
    try {
      final me = await client
          .from('users')
          .select('duty_status')
          .eq('id', uid)
          .single();
      status = DutyState.parse(me['duty_status'] as String?);
      notifyListeners();
      if (status == DutyState.onDuty) await pushLocation();
      _syncTimer();
    } catch (_) {
      // The picker still works; it just shows no current status.
    }
  }

  /// Writes the new status. Null on success.
  Future<DutyError?> submit(DutyState next) async {
    if (saving) return null;
    saving = true;
    notifyListeners();
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      await client
          .from('users')
          .update({'duty_status': next.wire}).eq('id', uid);
      status = next;
      saving = false;
      notifyListeners();

      // After the column is written, never before: update_my_location()
      // only matches rows where duty_status is already 'on_duty'.
      if (next == DutyState.onDuty) {
        await pushLocation();
      } else {
        note = null;
        notifyListeners();
      }
      _syncTimer();
      return null;
    } on PostgrestException catch (e) {
      saving = false;
      notifyListeners();
      return e.message.toLowerCase().contains('duty_only_for_tanod')
          ? DutyError.notTanod
          : DutyError.failed;
    } catch (_) {
      saving = false;
      notifyListeners();
      return DutyError.failed;
    }
  }

  /// Being on duty is not the same as being dispatchable.
  /// nearest_available_tanod() sorts by distance and location_is_fresh()
  /// discards a stale fix, so a tanod with no position sits in the queue
  /// invisible to it — said out loud in [note] rather than swallowed.
  ///
  /// [quiet] is for the 30-second timer: it skips the interim "Sharing
  /// your location…" line, which otherwise flickered every 30 seconds.
  Future<void> pushLocation({bool quiet = false}) async {
    if (_pushing) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return reset();
    _pushing = true;
    if (!quiet) {
      note = LocationNote.sharing;
      notifyListeners();
    }
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          !await Geolocator.isLocationServiceEnabled()) {
        note = LocationNote.off;
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));

      await client.rpc('update_my_location',
          params: {'p_lat': pos.latitude, 'p_lon': pos.longitude});

      // Read it back. The RPC returns void and filters on duty_status,
      // so a no-op is indistinguishable from a success at the call site.
      final row = await client
          .from('users')
          .select('last_location_at')
          .eq('id', uid)
          .single();
      note = (row['last_location_at'] as String?) != null
          ? LocationNote.shared
          : LocationNote.failed;
      _lastPush = DateTime.now();
    } catch (_) {
      note = LocationNote.failed;
    } finally {
      _pushing = false;
      notifyListeners();
    }
  }

  void _syncTimer() {
    if (status == DutyState.onDuty) {
      _startStream();
      // A safety net under the stream: if the platform goes quiet, a
      // fix is still asked for every 30 seconds while the app runs.
      _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        final last = _lastPush;
        if (last == null ||
            DateTime.now().difference(last) > const Duration(seconds: 45)) {
          pushLocation(quiet: true);
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _stopStream();
    }
  }

  void _startStream() {
    if (_stream != null) return;
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 30),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'SmartSumbong Tanod — On duty',
              notificationText:
                  'Sharing your location with Barangay 183 while you are on '
                  'duty. Go off duty in the app to stop.',
              notificationChannelName: 'On-duty location',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          );
    _stream = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onFix,
      onError: (_) {
        // Permission pulled or GPS switched off mid-shift: say so; the
        // timer keeps trying and the next Submit restarts the stream.
        note = LocationNote.off;
        notifyListeners();
        _stopStream();
      },
    );
  }

  void _stopStream() {
    _stream?.cancel();
    _stream = null;
  }

  /// One fix from the stream: sent at most every 25 seconds.
  Future<void> _onFix(Position pos) async {
    final last = _lastPush;
    if (_pushing ||
        (last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 25))) {
      return;
    }
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return reset();
    _pushing = true;
    try {
      await client.rpc('update_my_location',
          params: {'p_lat': pos.latitude, 'p_lon': pos.longitude});
      _lastPush = DateTime.now();
      if (note != LocationNote.shared) {
        note = LocationNote.shared;
        notifyListeners();
      }
    } catch (_) {
      // No signal for a moment; the next fix tries again.
    } finally {
      _pushing = false;
    }
  }

  /// Signed out, or a different account signed in: stop sharing and
  /// forget the old status.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _stopStream();
    _lastPush = null;
    _uid = null;
    status = null;
    note = null;
    saving = false;
    notifyListeners();
  }
}
