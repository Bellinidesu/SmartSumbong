// SmartSumbong — Verification Pending.
//
// Figma node 2105:151.
//
// WHY POLLING AND NOT REALTIME.
//
// public.users is not in the supabase_realtime publication, and adding it
// would cost more than it returns:
//
//   * An UPDATE event carries only the primary key unless the table is set
//     to `replica identity full`. Doing that publishes every column of
//     every user row into the WAL on every update — including
//     id_image_url, selfie_url and mobile_number. RLS still filters
//     delivery, but that is a great deal of identity data moving through
//     the replication stream so that one screen can change one word.
//   * A pending applicant holds a session, so they would keep a websocket
//     open for up to two hours waiting on an admin. That is a concurrent
//     connection per pending signup, on the free tier, for a static screen.
//   * It is the wrong shape. The applicant is not watching a live feed;
//     they are waiting on a human decision that takes minutes to hours and
//     is a human decision that takes minutes to hours. Realtime is for the
//     admin map, where seconds matter.
//
// So: refresh when the app comes back to the foreground, plus a manual
// button. Survives the app being killed, which a socket does not.
//
// ON THE COUNTDOWN. The two hours is the barangay's service target, and
// sweep_overdue_verifications() notifies every admin when it passes. It is
// not a deadline after which anything happens to the applicant. A bare
// timer ticking to zero would read as a promise the barangay has not made,
// so the copy changes state at zero and says what is actually true: the
// barangay has been told it is late.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen>
    with WidgetsBindingObserver {
  /// Shortest gap between two status queries, however they are triggered.
  /// A tap inside the window is ignored rather than queued: the answer
  /// cannot have changed meaningfully in eight seconds, and an applicant
  /// tapping forty times should not send forty queries.
  static const _minGap = Duration(seconds: 8);

  /// How often the "1h 57m left" line is recomputed. The clock is display
  /// only — it never triggers a query.
  static const _tick = Duration(seconds: 30);

  VerificationSnapshot? _snapshot;
  DateTime? _lastChecked;
  Timer? _ticker;
  Timer? _cooldown;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh(userInitiated: false);
    _ticker = Timer.periodic(_tick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _cooldown?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Most applicants will background the app and come back rather than
    // sit watching. This is the check that actually matters.
    if (state == AppLifecycleState.resumed) {
      _refresh(userInitiated: false);
    }
  }

  Duration get _sinceLastCheck => _lastChecked == null
      ? _minGap
      : DateTime.now().difference(_lastChecked!);

  bool get _canRefresh => !_busy && _sinceLastCheck >= _minGap;

  Future<void> _refresh({required bool userInitiated}) async {
    if (_busy) return;
    if (_sinceLastCheck < _minGap) {
      // Inside the cooldown. Rearm a timer so the button re-enables on its
      // own rather than only when something else rebuilds the widget.
      _cooldown?.cancel();
      _cooldown = Timer(_minGap - _sinceLastCheck, () {
        if (mounted) setState(() {});
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final s = await widget.auth.verificationStatus();
      if (!mounted) return;
      setState(() {
        _snapshot = s;
        _lastChecked = DateTime.now();
      });

      if (s.status == VerificationState.verified) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }
      if (s.status == VerificationState.rejected) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/verification-rejected');
        return;
      }
    } on AuthRequiredException {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = userInitiated ? context.s.verificationCheckError : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _cooldown?.cancel();
      _cooldown = Timer(_minGap, () {
        if (mounted) setState(() {});
      });
    }
  }

  // ---------- copy -------------------------------------------

  /// What the applicant reads about timing. Three states, all true.
  String _windowLine() {
    final s = context.s;
    final due = _snapshot?.dueAt;
    if (due == null) return s.verificationWindowDefault;

    final left = due.difference(DateTime.now());
    if (left.isNegative) {
      // sweep_overdue_verifications() runs every ten minutes and notifies
      // every admin once an account passes its due time. This is a
      // statement of fact, not reassurance.
      return s.verificationOverdue;
    }
    if (left.inMinutes < 1) {
      return s.verificationAnyMoment;
    }
    final h = left.inHours;
    final m = left.inMinutes % 60;
    final pretty = h > 0 ? s.verificationLeftHM(h, m) : s.verificationLeftM(m);
    return s.verificationAboutLeft(pretty);
  }

  String _lastCheckedLine() {
    final s = context.s;
    if (_busy) return s.verificationChecking;
    if (_lastChecked == null) return '';
    final ago = DateTime.now().difference(_lastChecked!);
    if (ago.inSeconds < 30) return s.verificationCheckedJustNow;
    if (ago.inMinutes < 1) return s.verificationCheckedLessThanMinute;
    if (ago.inMinutes == 1) return s.verificationChecked1Minute;
    if (ago.inMinutes < 60) return s.verificationCheckedNMinutes(ago.inMinutes);
    return s.verificationCheckedOverHour;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    final submitted = _snapshot?.submittedAt;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.pagePad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),

              Text(s.verificationAlmostThere, style: t.titleMedium),
              const SizedBox(height: 6),
              Text(s.verificationTitle, style: t.headlineLarge),
              const SizedBox(height: 24),

              Text(
                s.verificationBody,
                style: TextStyle(fontSize: 14, color: context.colors.navy, height: 1.5),
              ),
              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.field,
                  border: Border.all(color: context.colors.navy),
                  borderRadius: BorderRadius.circular(Tokens.dropdownRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _windowLine(),
                      style: TextStyle(
                          fontSize: 14, color: context.colors.navy, height: 1.4),
                    ),
                    if (submitted != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        s.verificationSubmitted(_formatSubmitted(s, submitted)),
                        style: TextStyle(
                            fontSize: 12, color: context.colors.muted),
                      ),
                    ],
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: context.colors.hint, fontSize: 12)),
              ],

              const Spacer(flex: 3),

              FilledButton(
                onPressed: _canRefresh
                    ? () => _refresh(userInitiated: true)
                    : null,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.bg),
                      )
                    : Text(s.verificationCheckStatus),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _lastCheckedLine(),
                  style: TextStyle(fontSize: 12, color: context.colors.muted),
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.auth.signOut();
                          if (context.mounted) {
                            Navigator.of(context)
                                .pushReplacementNamed('/login');
                          }
                        },
                  child: Text(s.verificationSignOut),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSubmitted(Strings s, DateTime utc) {
    final d = utc.toLocal();
    final h24 = d.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 < 12 ? 'AM' : 'PM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${s.monthAbbr(d.month)} ${d.day}, ${d.year} \u2022 $h12:$mm $ampm';
  }
}
