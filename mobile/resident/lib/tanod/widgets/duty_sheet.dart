// SmartSumbong — the duty status popup (branch B).
//
// Opened from the status button in the middle of the nav bar. The same
// two steps the Home card had: pick, then Submit. Going off duty by a
// mistap costs the barangay a responder without anyone noticing; one
// extra tap is cheap against that.

import 'package:flutter/material.dart';

import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../duty.dart';
import '../tanod_strings.dart';
import '../../theme.dart';
import '../../widgets/figma_ui.dart';

/// The colour each status wears, in the popup and on the nav button.
Color dutyColour(BuildContext context, DutyState? s) => switch (s) {
      DutyState.onDuty => const Color(0xFF16C25B),
      DutyState.breakTime || DutyState.lunch => kFigmaOrange,
      DutyState.offline => kFigmaRed,
      null => context.colors.muted,
    };

Future<void> showDutySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.d.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => const _DutySheet(),
    );

class _DutySheet extends StatefulWidget {
  const _DutySheet();

  @override
  State<_DutySheet> createState() => _DutySheetState();
}

class _DutySheetState extends State<_DutySheet> {
  final _duty = DutyController.instance;
  DutyState? _picked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _picked = _duty.status;
  }

  Future<void> _submit() async {
    final next = _picked;
    if (next == null) return;
    setState(() => _error = null);
    final err = await _duty.submit(next);
    if (!mounted) return;
    if (err == null) {
      // Stay open while the first fix is taken, so "Location shared" or
      // "Location is off" is seen; close straight away otherwise.
      if (next != DutyState.onDuty) Navigator.of(context).pop();
      return;
    }
    setState(() => _error = err == DutyError.notTanod
        ? context.ts.homeNotTanod
        : context.ts.homeStatusUpdateFailed);
  }

  String? _noteText(TanodStrings s, LocationNote? n) => switch (n) {
        LocationNote.sharing => s.homeLocationSharing,
        LocationNote.shared => s.homeLocationShared,
        LocationNote.off => s.homeLocationOff,
        LocationNote.failed => s.homeLocationShareFailed,
        null => null,
      };

  // Branch D: the question, the statuses as cards each with its colour
  // (the picked one ringed in it, the current one labelled), the location
  // note while on duty, and Submit.
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    return ListenableBuilder(
      listenable: _duty,
      builder: (context, _) {
        final note = _duty.status == DutyState.onDuty ? _noteText(s, _duty.note) : null;
        final changed = _picked != null && _picked != _duty.status;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(5)))),
              const SizedBox(height: 16),
              Text(s.homeStatusQuestion, textAlign: TextAlign.center, style: DType.h2(d.ink)),
              const SizedBox(height: 14),
              for (final st in DutyState.values) ...[
                _StatusRow(
                  label: s.dutyStateLabel(st.wire),
                  colour: dutyColour(context, st),
                  current: st == _duty.status,
                  selected: st == _picked,
                  onTap: _duty.saving
                      ? null
                      : () => setState(() {
                            _picked = st;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 8),
              ],
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note, textAlign: TextAlign.center, style: DType.body(d.muted, size: 12.5)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
              ],
              const SizedBox(height: 12),
              DButton(s.homeSubmit, kind: DButtonKind.accent, expand: true, busy: _duty.saving, onTap: _duty.saving || !changed ? null : _submit),
            ]),
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.colour, required this.current, required this.selected, required this.onTap});

  final String label;
  final Color colour;
  final bool current;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colour.withValues(alpha: .12) : d.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? colour : d.line, width: selected ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: colour, shape: BoxShape.circle, boxShadow: [BoxShadow(color: colour.withValues(alpha: .35), spreadRadius: 4)]),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: DType.body(d.ink, size: 16, w: FontWeight.w800))),
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: colour.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
                  child: Text(context.ts.dutyCurrent, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11, color: colour)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
