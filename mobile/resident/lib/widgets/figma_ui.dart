// SmartSumbong — the Figma building blocks, shared.
//
// The translated screens each grew private copies of the same few pieces
// (the pill shadow, the 300-wide dialog card, the page title). This file
// holds them once, for the screens that were styled after those — the
// ones with no frame of their own (Appearance, Notification Preferences,
// Account status, …) take their look from here so they match the rest.
//
// Values are the Figma file's: pills radius 50 with a 1px #F3F3F3 edge
// and a y5 / blur 5 shadow at 30%; dialogs 300 wide, radius 50, 2px
// #252525 edge, 24/700 orange title, 16/500 body, 106x40 pills.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import '../d/d_theme.dart';

/// The design's drop shadow: y 5, blur 5, #121212 at 30%.
const kFigmaShadow = [
  BoxShadow(
    color: Color(0x4D121212),
    blurRadius: 3.5,
    offset: Offset(0, 5),
  ),
];

/// The design's accent orange.
const kFigmaOrange = Color(0xFFFF9800);

/// The design's warning red (the location-off pill, form notes).
const kFigmaRed = Color(0xFFFF4949);

/// A page title as the frames set it: 28/800 navy, centred.
class FigmaTitle extends StatelessWidget {
  const FigmaTitle(this.text, {super.key, this.size = 28});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Urbanist',
          fontWeight: FontWeight.w800,
          fontSize: size,
          height: 43.68 / 28,
          color: context.colors.navy,
        ),
      );
}

/// Top padding that puts content [figmaY] from the top of the *screen*,
/// as the frames measure it, inside a SafeArea.
double figmaTop(BuildContext context, double figmaY, {double min = 8}) =>
    (figmaY - MediaQuery.paddingOf(context).top).clamp(min, figmaY);

enum FigmaPillStyle {
  /// Navy fill, light text, 1px light edge — the frames' primary.
  navy,

  /// #FBFBFB fill, navy text and edge — the frames' Back / Skip.
  light,

  /// Orange fill, white text — Log In, the map eye.
  orange,
}

/// The frames' pill button: radius 50, the design shadow, 16/700 label.
/// [width] null stretches to the parent (the 301/323-wide ones); give it
/// 150 for the Back / Continue pairs.
class FigmaPill extends StatelessWidget {
  const FigmaPill({
    super.key,
    required this.child,
    required this.onPressed,
    this.style = FigmaPillStyle.navy,
    this.width,
    this.height = 44,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final FigmaPillStyle style;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, edge) = switch (style) {
      FigmaPillStyle.navy => (c.navy, c.bg, c.bg),
      FigmaPillStyle.light => (c.field, c.navy, c.navy),
      FigmaPillStyle.orange => (kFigmaOrange, Colors.white, c.bg),
    };
    final size = Size(width ?? double.infinity, height);

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(50)),
          boxShadow: kFigmaShadow,
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            // Still readable while disabled (busy), not a blank pill.
            disabledBackgroundColor: bg.withValues(alpha: 0.55),
            disabledForegroundColor: fg.withValues(alpha: 0.8),
            minimumSize: size,
            maximumSize: size,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            elevation: 0,
            side: BorderSide(color: edge),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The frames' dialog card (CONFIRM CANCEL, LOG OUT, EDIT PROFILE - BACK):
/// 300 wide, navy, radius 50, 2px #252525 edge; the title orange at
/// 24/700, the body light at 16/500, and up to two 106x40 pills 13 apart.
/// [content] goes between the body and the pills (a text field, say).
class FigmaDialog extends StatelessWidget {
  const FigmaDialog({
    super.key,
    required this.title,
    this.body,
    this.content,
    this.titleColor = kFigmaOrange,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.destructive = false,
  });

  final String title;
  final String? body;
  final Widget? content;
  final Color titleColor;

  /// Draws the primary pill red — for an action that can't be undone.
  final bool destructive;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 300,
        padding: EdgeInsets.fromLTRB(
            20, body != null || content != null ? 30 : 40, 20, 27),
        decoration: BoxDecoration(
          // 7 Oct 2026: the D card in both themes, like showDDialog. The
          // old navy surface turned white in dark mode.
          color: d.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: d.line, width: 1.5),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  height: 1.1,
                  color: titleColor,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 20),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    height: 1.25,
                    color: d.ink2,
                  ),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: 16),
                content!,
              ],
              SizedBox(height: body != null || content != null ? 23 : 32),
              // Side by side, 13 apart, as the frames have them; a pair
              // too long for one line (a Filipino label, "Delete my
              // account") stacks instead of overflowing.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 13,
                runSpacing: 12,
                children: [
                  if (secondaryLabel != null)
                    FigmaDialogPill(
                      label: secondaryLabel!,
                      onPressed: onSecondary,
                      filled: false,
                    ),
                  FigmaDialogPill(
                    label: primaryLabel,
                    onPressed: onPrimary,
                    filled: true,
                    destructive: destructive,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dialogs' 106x40 pill: light-filled for the primary, navy with a
/// light edge for the secondary. Widens for a longer (Filipino) label.
class FigmaDialogPill extends StatelessWidget {
  const FigmaDialogPill({
    super.key,
    required this.label,
    required this.onPressed,
    required this.filled,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final bg = destructive ? kFigmaRed : (filled ? DColors.orange : Colors.transparent);
    final fg = destructive ? Colors.white : (filled ? const Color(0xFF141B34) : d.ink);
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(50)),
        boxShadow: kFigmaShadow,
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          disabledForegroundColor: fg.withValues(alpha: 0.6),
          minimumSize: const Size(106, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
          side: filled ? BorderSide.none : BorderSide(color: d.line, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Opens a [FigmaDialog] with the frames' faded page behind it.
Future<T?> showFigmaDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: context.colors.bg.withValues(alpha: 0.7),
      builder: builder,
    );

/// The logo art as the login and role frames place it: the square image
/// 403 wide (scaled down on narrower screens) with its transparent lower
/// edge allowed to run under whatever follows, [visibleHeight] tall.
class FigmaLogo extends StatelessWidget {
  const FigmaLogo({super.key, this.visibleHeight = 307});

  final double visibleHeight;

  @override
  Widget build(BuildContext context) {
    final k = (MediaQuery.sizeOf(context).width / 412).clamp(0.0, 1.0);
    final side = 403 * k;
    return SizedBox(
      height: visibleHeight * k,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -33 * k,
            width: side,
            height: side,
            child: Image.asset(
              'assets/images/onboarding-logo.png',
              semanticLabel: 'SmartSumbong',
              filterQuality: FilterQuality.medium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The contour texture behind the entry screens, same asset and opacity
/// everywhere.
class FigmaTexture extends StatelessWidget {
  const FigmaTexture({super.key});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: Opacity(
          opacity: 0.55,
          child: Image.asset(
            'assets/images/texture.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
      );
}

/// The LANGUAGES frame's picker row: the label 16/600 navy, the 20px
/// orange radio (1.5 stroke, 11 dot) at the right; 15 above and below so
/// each row is a 50-tall target on the frame's 70 pitch (20 between).
class FigmaRadioRow extends StatelessWidget {
  const FigmaRadioRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: context.colors.navy,
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

/// The report form's anonymous toggle, at any size: a navy track with a
/// light knob. The frame draws only the "on" look; off here keeps the
/// knob left and lightens the track so the two states can't be confused.
/// The tap target is at least 48x40 whatever the drawn size.
class FigmaSwitch extends StatelessWidget {
  const FigmaSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 40,
    this.height = 24,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: width,
                height: height,
                padding: EdgeInsets.all(height * 0.12),
                decoration: BoxDecoration(
                  color: value ? c.navy : c.navy.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(height),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: height * 0.76,
                    height: height * 0.76,
                    decoration: BoxDecoration(
                      color: c.bg,
                      shape: BoxShape.circle,
                    ),
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

/// The frames' 150x45 navy Back pill (NOTIFICATION, LANGUAGES).
class FigmaBackPill extends StatelessWidget {
  const FigmaBackPill({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FigmaPill(
        width: 150,
        height: 45,
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        child: Text(label),
      );
}

/// A text field for inside a [FigmaDialog]'s navy card: the design's
/// light pill field (radius 50), navy text, 44 tall.
class FigmaDialogField extends StatelessWidget {
  const FigmaDialogField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: d.ink,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Urbanist',
          fontStyle: FontStyle.italic,
          fontSize: 13,
          color: d.muted,
        ),
        isDense: true,
        filled: true,
        fillColor: d.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: d.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: d.line),
        ),
      ),
    );
  }
}

/// Camera or gallery, asked the design's way: a sheet with a radius-25
/// top holding the navy Take Photo pill over the light Choose from
/// Gallery pill, each with its icon, 301 wide.
Future<ImageSource?> showFigmaSourceSheet(
  BuildContext context, {
  required String takeLabel,
  required String galleryLabel,
}) {
  final c = context.colors;
  Widget pill(BuildContext sheet, IconData icon, String label,
          ImageSource source, FigmaPillStyle style) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 301),
        child: FigmaPill(
          style: style,
          onPressed: () => Navigator.of(sheet).pop(source),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      );
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: c.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    builder: (sheet) => SafeArea(
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
            const SizedBox(height: 22),
            pill(sheet, Icons.photo_camera_outlined, takeLabel,
                ImageSource.camera, FigmaPillStyle.navy),
            const SizedBox(height: 14),
            pill(sheet, Icons.photo_library_outlined, galleryLabel,
                ImageSource.gallery, FigmaPillStyle.light),
          ],
        ),
      ),
    ),
  );
}
