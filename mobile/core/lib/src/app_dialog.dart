// SmartSumbong — the design's dialog card, for the shared core widgets.
//
// The apps' own screens use their widgets/figma_ui.dart. Core can't
// import either app, so the dialogs core raises itself (permission
// prompts) take the same shape here and read their colours from the
// app's ColorScheme: primary is the card (navy in the resident app),
// onPrimary the text and light pill. The shape and type are the Figma
// file's: 300 wide, radius 50, 2px #252525 edge, 24/700 orange title,
// 16/500 body, 106x40 pills 13 apart.

import 'package:flutter/material.dart';

const _orange = Color(0xFFFF9800);

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = scheme.primary;
    final ink = scheme.onPrimary;

    Widget pill(String label, VoidCallback? onTap, {required bool filled}) =>
        DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(50)),
            boxShadow: [
              BoxShadow(
                color: Color(0x4D121212),
                blurRadius: 3.5,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: filled ? ink : card,
              foregroundColor: filled ? card : ink,
              minimumSize: const Size(106, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              elevation: 0,
              side: filled ? BorderSide.none : BorderSide(color: ink),
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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 27),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: const Color(0xFF252525), width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  height: 1.1,
                  color: _orange,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 1.25,
                  color: ink,
                ),
              ),
              const SizedBox(height: 23),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 13,
                runSpacing: 12,
                children: [
                  if (secondaryLabel != null)
                    pill(secondaryLabel!, onSecondary, filled: false),
                  pill(primaryLabel, onPrimary, filled: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens an [AppDialog] over the page faded toward the app's surface
/// colour, as the frames draw it.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) =>
    showDialog<T>(
      context: context,
      barrierColor:
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      builder: builder,
    );
