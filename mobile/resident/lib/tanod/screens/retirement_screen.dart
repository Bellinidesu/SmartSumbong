// SmartSumbong — Retirement (tanod).
//
// The barangay's own words: a tanod does not get to delete their own
// account — only retire, and retiring is two-pronged. Getting into
// Extra Administrative Services took a password (see that screen).
// Sending this request takes the password again, right before it goes
// out, via [_ConfirmPasswordDialog] below. Neither step ends the
// account by itself — request_retirement() (migration 0052) only ever
// queues an ask; an admin decides in the portal's Retirement Requests
// queue, through finalize_retirement().
//
// A tanod who is already retired never reaches this screen — the
// launch gate routes a retired account straight to account_status_
// screen.dart instead (see launch_gate.dart). What this screen does
// handle on repeat visits is a request already sitting with the admin
// (my_retirement_status() came back 'pending' — nothing to resubmit,
// just wait) and a request the admin turned down (came back 'denied' —
// shown with the reason, and the door to ask again left open, the same
// as a rejected registration can be filed again).

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../tanod_strings.dart';
import '../../theme.dart';
import '../../widgets/figma_ui.dart';

class RetirementScreen extends StatefulWidget {
  const RetirementScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<RetirementScreen> createState() => _RetirementScreenState();
}

enum _Status { none, pending, denied }

class _RetirementScreenState extends State<RetirementScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  _Status _status = _Status.none;
  DateTime? _requestedAt;
  String? _denialReason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows =
          await Supabase.instance.client.rpc('my_retirement_status') as List;
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() {
          _status = _Status.none;
          _loading = false;
        });
        return;
      }
      final row = rows.first as Map<String, dynamic>;
      final wire = row['status'] as String?;
      setState(() {
        _status = wire == 'pending'
            ? _Status.pending
            : wire == 'denied'
                ? _Status.denied
                : _Status.none;
        _requestedAt = _parseTs(row['requested_at']);
        _denialReason = row['denial_reason'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = context.ts.retirementLoadFailed;
        _loading = false;
      });
    }
  }

  DateTime? _parseTs(Object? v) =>
      v == null ? null : DateTime.tryParse(v as String);

  Future<void> _requestConfirm() async {
    final s = context.ts;
    final confirmed = await showFigmaDialog<bool>(
      context,
      builder: (dialogContext) =>
          _ConfirmPasswordDialog(auth: widget.auth, s: s),
    );
    if (confirmed != true || !mounted) return;
    await _submit();
  }

  Future<void> _submit() async {
    final s = context.ts;
    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc('request_retirement');
      if (!mounted) return;
      setState(() => _submitting = false);
      await showFigmaDialog<void>(
        context,
        builder: (dialogContext) => FigmaDialog(
          title: s.retirementSuccessTitle,
          body: s.retirementSuccessBody,
          primaryLabel: s.retirementSuccessContinue,
          onPrimary: () => Navigator.of(dialogContext).pop(),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.retirementSubmitFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final s = context.ts;

    // Branch D: the page colour and contour, back and the heading.
    return Scaffold(
      backgroundColor: context.d.bg,
      body: Stack(children: [
        const DContour(),
        SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerLeft, child: DBack()),
                    const SizedBox(height: 12),
                    DHeading(s.retirementTitle),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildBody(t, c, s),
                      ),
                    ),
                    if (_status != _Status.pending) ...[
                      const SizedBox(height: 12),
                      DButton(s.retirementRequestButton, expand: true, busy: _submitting, onTap: _submitting ? null : _requestConfirm),
                      const SizedBox(height: 10),
                    ],
                    DButton(s.retirementBack, kind: DButtonKind.ghost, expand: true, onTap: () => Navigator.of(context).pop()),
                    const SizedBox(height: 20),
                  ],
                ),
        ),
      ),
      ]),
    );
  }

  Widget _buildBody(TextTheme t, AppColors c, TanodStrings s) {
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(_loadError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.hint, fontSize: 13)),
      );
    }

    return switch (_status) {
      _Status.pending => _InfoCard(
          icon: Icons.hourglass_top_outlined,
          title: s.retirementPendingTitle,
          body: s.retirementPendingBody(_requestedAt != null
              ? _formatDate(context, _requestedAt!.toLocal())
              : ''),
          c: c,
        ),
      _Status.denied => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoCard(
              icon: Icons.info_outline,
              title: s.retirementDeniedTitle,
              body: s.retirementDeniedBody(_denialReason ?? ''),
              c: c,
            ),
            const SizedBox(height: 16),
            Text(s.retirementIntroBody,
                style: TextStyle(fontSize: 13, height: 1.5, color: c.navy)),
          ],
        ),
      _Status.none => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.retirementIntroTitle,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: c.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(s.retirementIntroBody,
                style: TextStyle(fontSize: 13, height: 1.5, color: c.navy)),
          ],
        ),
    };
  }

  static String _formatDate(BuildContext context, DateTime d) =>
      '${context.ts.monthFull(d.month)} ${d.day}, ${d.year}';
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.c,
  });

  final IconData icon;
  final String title;
  final String body;
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.field,
        border: Border.all(color: c.navy),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: c.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: TextStyle(fontSize: 13, height: 1.45, color: c.navy)),
        ],
      ),
    );
  }
}

/// Retirement's second password check, the one right before the request
/// actually sends — separate from whatever password unlocked Extra
/// Administrative Services on the way in. A StatefulBuilder rather than
/// its own StatefulWidget: this dialog's whole state (the typed
/// password, an inline error, a busy spinner) never needs to survive
/// past the dialog itself.
class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog({required this.auth, required this.s});

  final AuthService auth;
  final TanodStrings s;

  @override
  State<_ConfirmPasswordDialog> createState() =>
      _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _password = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    // verifyPassword only ever catches AuthException (a wrong password) —
    // anything else (offline, a timeout) propagates, and without this
    // try/catch _checking would stay true forever: the Confirm button
    // disables itself on _checking and there would be no path left to
    // flip it back, leaving the only way out Cancel-and-reopen.
    bool ok;
    try {
      ok = await widget.auth.verifyPassword(_password.text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = widget.s.retirementConfirmCheckFailed;
        _checking = false;
      });
      return;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _error = widget.s.retirementWrongPassword;
        _checking = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  // The frames' dialog card, with the password field inside it.
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = context.colors;
    return FigmaDialog(
      title: s.retirementConfirmTitle,
      body: s.retirementConfirmBody,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 6),
            child: Text(s.retirementPasswordLabel,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: c.bg,
                )),
          ),
          FigmaDialogField(
            controller: _password,
            hint: s.retirementPasswordHint,
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => _confirm(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kFigmaOrange, fontSize: 12)),
          ],
        ],
      ),
      secondaryLabel: s.retirementCancel,
      onSecondary: () => Navigator.of(context).pop(false),
      primaryLabel: s.retirementConfirmButton,
      onPrimary: _checking ? null : _confirm,
    );
  }
}
