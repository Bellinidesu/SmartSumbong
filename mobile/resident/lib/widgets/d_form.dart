// SmartSumbong — the pieces the three steps of filing a report share (19 Nov 2026, from the approved artifact:
// Button, FormBar and the "Step n of 3" chip, and the 44 px Back at the top of a step).

import 'package:flutter/material.dart';

import '../d/d_theme.dart';

enum DFormKind { primary, ghost }

/// The artifact's button: 56 high (small 44), radius 16 (small 14), 16 / 800 lettering (small 14), the orange
/// primary with a flat lower lip, the ghost a card with a line round it. A primary with no [onTap] is the artifact's
/// disabled button: grey, no lip. The area that answers a touch is never under 44 high.
class DFormButton extends StatelessWidget {
  const DFormButton(this.label, {super.key, required this.onTap, this.kind = DFormKind.primary, this.icon, this.small = false, this.fit = false, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final DFormKind kind;
  final IconData? icon;
  final bool small;

  /// As wide as its label, not the row.
  final bool fit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final dark = d.dark;
    final enabled = onTap != null && !busy;
    Color bg, fg;
    Color? edge;
    List<BoxShadow> lip = const [];
    if (kind == DFormKind.ghost) {
      bg = d.card;
      fg = d.ink;
      edge = dark ? const Color(0xFF34383E) : const Color(0xFFD6DCEA);
    } else if (onTap == null && !busy) {
      bg = dark ? const Color(0xFF2A2D33) : const Color(0xFFDDE2EE);
      fg = dark ? const Color(0xFFA8A8A8) : const Color(0xFF5F6673);
    } else {
      bg = const Color(0xFFFF9800);
      fg = const Color(0xFF141B34);
      lip = [BoxShadow(color: const Color(0xFFFF9800).withValues(alpha: dark ? .22 : .30), offset: const Offset(0, 5))];
    }
    final h = small ? 44.0 : 56.0;
    final child = busy
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: small ? 14 : 16, height: 1, color: fg)),
            ),
          ]);
    final radius = BorderRadius.circular(small ? 14 : 16);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: SizedBox(
            width: fit ? null : double.infinity,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: radius, boxShadow: lip),
              child: Material(
                color: bg,
                shape: RoundedRectangleBorder(borderRadius: radius, side: edge == null ? BorderSide.none : BorderSide(color: edge, width: 1.5)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled ? onTap : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: small ? 18 : 22),
                    child: Center(widthFactor: fit ? 1 : null, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back and the next step, pinned at the bottom of a step: a card strip with a line above, two equal buttons.
class DFormBar extends StatelessWidget {
  const DFormBar({super.key, required this.backLabel, required this.onBack, required this.okLabel, required this.onOk, this.busy = false});

  final String backLabel;
  final VoidCallback? onBack;
  final String okLabel;
  final VoidCallback? onOk;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
      padding: EdgeInsets.fromLTRB(18, 14, 18, 9 + MediaQuery.paddingOf(context).bottom),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: DFormButton(backLabel, kind: DFormKind.ghost, onTap: onBack)),
        const SizedBox(width: 10),
        Expanded(child: DFormButton(okLabel, onTap: onOk, busy: busy)),
      ]),
    );
  }
}

/// "Step 3 of 3", at the top right of a step.
class DStepChip extends StatelessWidget {
  const DStepChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: d.line)),
      child: Text(text, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, height: 1, color: d.ink2)),
    );
  }
}

/// The round Back at the top left of a step: 44 across, a card with a line round it.
class DFormBack extends StatelessWidget {
  const DFormBack({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      excludeSemantics: true,
      child: Material(
        color: d.card,
        shape: CircleBorder(side: BorderSide(color: d.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap ?? () => Navigator.of(context).maybePop(),
          child: SizedBox(width: 44, height: 44, child: Icon(Icons.chevron_left_rounded, size: 28, color: d.ink)),
        ),
      ),
    );
  }
}
