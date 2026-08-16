// SmartSumbong — Duty status.
//
// Update Availability Status in the use case: On Duty, Break, Lunch,
// Offline. The smallest complete loop in the tanod app, and the one
// everything else rests on — proximity dispatch in 0005 only considers
// tanods whose is_dispatchable is true.
//
// No RPC for the status itself. duty_status is a column on public.users,
// users_self_update allows a tanod to change their own row, and
// sync_dispatchable derives is_dispatchable from it. Writing the column
// is the whole operation.
//
// ON LOCATION. Being dispatchable is not enough to be dispatched:
// nearest_available_tanod() ranks by distance and location_is_fresh()
// discards a stale fix, so a tanod with no position sits in the queue
// invisible to it. That failure is silent at every layer —
// update_my_location() only matches rows where duty_status is already
// 'on_duty', so calling it at the wrong moment updates nothing and
// raises nothing. Hence: the fix is pushed on load as well as on the
// transition, the write is read back rather than assumed, and the state
// is shown on screen. A tanod who believes they are available and is
// not is worse off than one who knows they are offline.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

/// Mirrors `public.duty_state` in 0001.
enum DutyState {
  onDuty('on_duty', 'On Duty', 'You can receive dispatch tickets.'),
  breakTime('break', 'Break', 'You will not be sent new tickets.'),
  lunch('lunch', 'Lunch', 'You will not be sent new tickets.'),
  offline('offline', 'Offline',
      'You are off duty and out of the dispatch queue.');

  const DutyState(this.wire, this.label, this.note);

  final String wire;
  final String label;
  final String note;

  static DutyState? parse(String? w) {
    for (final s in DutyState.values) {
      if (s.wire == w) return s;
    }
    return null;
  }
}

enum _Loc { unknown, sending, ok, denied, failed }

class DutyScreen extends StatefulWidget {
  const DutyScreen({super.key});

  @override
  State<DutyScreen> createState() => _DutyScreenState();
}

class _DutyScreenState extends State<DutyScreen> {
  DutyState? _status;
  String _name = '';
  DateTime? _locationAt;
  _Loc _loc = _Loc.unknown;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      final row = await client
          .from('users')
          .select('full_name, duty_status, last_location_at')
          .eq('id', uid)
          .single();

      if (!mounted) return;
      setState(() {
        _name = row['full_name'] as String? ?? '';
        _status = DutyState.parse(row['duty_status'] as String?);
        _locationAt =
            DateTime.tryParse(row['last_location_at'] as String? ?? '');
        _loading = false;
      });

      // Duty status outlives the session. Someone who went On Duty
      // yesterday opens the app already on duty, so no transition fires
      // and no fix would ever be sent.
      if (_status == DutyState.onDuty) await _pushLocation();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your duty status.';
      });
    }
  }

  Future<void> _set(DutyState next) async {
    if (_saving) return;

    // Re-tapping the current status is not a no-op any more: it is how a
    // tanod refreshes their position without going off duty.
    if (next == _status && next != DutyState.onDuty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

      if (next != _status) {
        await client
            .from('users')
            .update({'duty_status': next.wire}).eq('id', uid);
      }

      if (!mounted) return;
      setState(() {
        _status = next;
        _saving = false;
      });

      // After the column is written, never before: the RPC filters on
      // duty_status = 'on_duty' and would match nothing.
      if (next == DutyState.onDuty) {
        await _pushLocation();
      } else if (mounted) {
        setState(() => _loc = _Loc.unknown);
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() {
        _saving = false;
        _error = m.contains('duty_only_for_tanod')
            ? 'This account is not registered as a barangay tanod.'
            : 'Could not update your duty status. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not update your duty status. Please try again.';
      });
    }
  }

  Future<void> _pushLocation() async {
    if (!mounted) return;
    setState(() => _loc = _Loc.sending);

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loc = _Loc.denied);
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _loc = _Loc.denied);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));

      await Supabase.instance.client.rpc('update_my_location', params: {
        'p_lat': pos.latitude,
        'p_lon': pos.longitude,
      });

      // Read it back. The RPC returns void and filters on duty_status,
      // so a no-op is indistinguishable from a success at the call site.
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('users')
          .select('last_location_at')
          .eq('id', uid)
          .single();
      final at = DateTime.tryParse(row['last_location_at'] as String? ?? '');

      if (!mounted) return;
      setState(() {
        _locationAt = at;
        _loc = at == null ? _Loc.failed : _Loc.ok;
      });
    } catch (_) {
      if (mounted) setState(() => _loc = _Loc.failed);
    }
  }

  String get _locationLine => switch (_loc) {
        _Loc.sending => 'Sharing your location\u2026',
        _Loc.ok => 'Location shared. You can be sent nearby tickets.',
        _Loc.denied =>
          'Location is off. You are on duty but cannot be sent nearby '
              'tickets until you turn it on.',
        _Loc.failed =>
          'Could not share your location. Tap On Duty again to retry.',
        _Loc.unknown => _locationAt == null
            ? ''
            : 'Location last shared ${_ago(_locationAt!)}.',
      };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    return '${d.inDays} d ago';
  }

  Color get _locationColour => switch (_loc) {
        _Loc.ok => Tokens.navy,
        _Loc.denied || _Loc.failed => Tokens.hint,
        _ => Tokens.muted,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Text('Duty Status',
                        textAlign: TextAlign.center,
                        style: t.headlineLarge?.copyWith(fontSize: 26)),
                    const SizedBox(height: 4),
                    if (_name.isNotEmpty)
                      Text(_name,
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(fontSize: 13)),
                    const SizedBox(height: 24),

                    for (final s in DutyState.values) ...[
                      _DutyTile(
                        state: s,
                        selected: _status == s,
                        enabled: !_saving,
                        onTap: () => _set(s),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_locationLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_loc == _Loc.sending)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              _locationLine,
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: _locationColour),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, color: Tokens.hint)),
                    ],

                    const Spacer(),
                    if (_status == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Choose a status to join the dispatch queue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Tokens.muted),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DutyTile extends StatelessWidget {
  const _DutyTile({
    required this.state,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DutyState state;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (state == DutyState.onDuty ? Tokens.orange : Tokens.navy)
        : Tokens.field;
    final fg = selected
        ? (state == DutyState.onDuty ? Tokens.navy : Tokens.bg)
        : Tokens.navy;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              border: Border.all(color: Tokens.navy, width: selected ? 0 : 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(state.note,
                          style:
                              TextStyle(fontSize: 11, height: 1.3, color: fg)),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 22, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
