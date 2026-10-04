// SmartSumbong — duty status, app-wide.
//
// Branch B moved the status picker off Home into the middle of the nav
// bar, so it can be changed from any tab. What used to live in Home's
// state — the column, the save, and the location push — lives here now,
// in one place every tab shares.
//
// Location (branch B, 26 Sep 2026): one fix at the moments that matter,
// never a stream. It used to run as an Android foreground service,
// pushing a fix every 30 seconds for a whole shift — and a shift of that
// ate the tanod's battery. Now a single fix goes to update_my_location()
// when the tanod goes On Duty, when the app comes back to the foreground
// while on duty (at most every two minutes), and at each dispatch step
// (accept, reroute, field report — dispatch_order.dart calls
// [DutyController.keyMoment]). nearest_available_tanod (0067) no longer
// drops a tanod whose last fix is old; it ranks fresh fixes first and
// falls back to the last known spot, so dispatch keeps working on these
// occasional fixes.

import '../preview/demo.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
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

class DutyController extends ChangeNotifier with WidgetsBindingObserver {
  DutyController._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = DutyController._();

  DutyState? status;
  bool saving = false;
  LocationNote? note;

  String? _uid;
  DateTime? _lastPush;
  // One fix at a time. Indoors a fix can take the full 15-second timeout.
  bool _pushing = false;

  /// Back in the foreground while on duty: one fix, if the last one is
  /// more than two minutes old.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) keyMoment(minAge: const Duration(minutes: 2));
  }

  /// A dispatch step or a return to the app: one quiet fix while on duty.
  Future<void> keyMoment({Duration minAge = Duration.zero}) async {
    if (status != DutyState.onDuty) return;
    final last = _lastPush;
    if (last != null && DateTime.now().difference(last) < minAge) return;
    await pushLocation(quiet: true);
  }

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
  /// [quiet] is for the key moments: it skips the interim "Sharing your
  /// location…" line under the picker.
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
      // The Dart preview has no GPS: the location is shared by decree.
      if (kDemo) {
        note = LocationNote.shared;
        return;
      }
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

  /// Signed out, or a different account signed in: forget the old
  /// status.
  void reset() {
    _lastPush = null;
    _uid = null;
    status = null;
    note = null;
    saving = false;
    notifyListeners();
  }
}
