// SmartSumbong — the duty status popup (branch B).
//
// Opened from the status button in the middle of the nav bar. The same
// two steps the Home card had: pick, then Submit. Going off duty by a
// mistap costs the barangay a responder without anyone noticing; one
// extra tap is cheap against that.

import 'package:flutter/material.dart';

import '../duty.dart';
import '../tanod_strings.dart';
import '../../theme.dart';
import '../../widgets/figma_ui.dart';

/// The colour each status wears, in the popup and on the nav button.
Color dutyColour(BuildContext context, DutyState? s) => switch (s) {
      DutyState.onDuty => const Color(0xFF058F00),
      DutyState.breakTime || DutyState.lunch => kFigmaOrange,
      DutyState.offline => kFigmaRed,
      null => context.colors.muted,
    };

Future<void> showDutySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.bg,
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

  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final c = context.colors;
    return ListenableBuilder(
      listenable: _duty,
      builder: (context, _) {
        final note = _duty.status == DutyState.onDuty
            ? _noteText(s, _duty.note)
            : null;
        final changed = _picked != null && _picked != _duty.status;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 10, 40, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                FigmaTitle(s.homeStatusQuestion, size: 24),
                const SizedBox(height: 10),
                for (final d in DutyState.values)
                  _StatusRow(
                    label: s.dutyStateLabel(d.wire),
                    colour: dutyColour(context, d),
                    current: d == _duty.status,
                    selected: d == _picked,
                    onTap: _duty.saving
                        ? null
                        : () => setState(() {
                              _picked = d;
                              _error = null;
                            }),
                  ),
                if (note != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    note,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: c.muted),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.hint)),
                ],
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 301),
                  child: FigmaPill(
                    onPressed: _duty.saving || !changed ? null : _submit,
                    child: _duty.saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.bg),
                          )
                        : Text(s.homeSubmit),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A status: its colour dot, the label 16/600, the orange radio; the
/// current one marked in its own colour.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.colour,
    required this.current,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final bool current;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.navy;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: ink,
                    ),
                    children: [
                      if (current)
                        TextSpan(
                          text: '  •  ${context.ts.dutyCurrent}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: colour,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kFigmaOrange, width: 1.5),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: kFigmaOrange,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
