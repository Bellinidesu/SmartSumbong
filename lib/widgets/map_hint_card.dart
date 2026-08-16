import 'package:flutter/material.dart';

/// Persistent hint card shown beneath the map on the Barangay 183 Map screen.
///
/// Two states, driven by [showingReports]:
///   false -> "Want to see your reports?"  (closed eye, pins hidden)
///   true  -> "Reports spotted!"           (open eye, pins visible)
///
/// Copy is verbatim from Rose's Figma frames MAP / MAP - SEE REPORTS.
class MapHintCard extends StatelessWidget {
  const MapHintCard({
    super.key,
    required this.showingReports,
    required this.onToggle,
  });

  final bool showingReports;
  final VoidCallback onToggle;

  // Replace these with your theme constants once confirmed against the
  // LaunchGate navy. Sampled from the Figma export.
  static const Color _blue = Color(0xFF0B4BD0);
  static const Color _orange = Color(0xFFF5A623);

  static const String _titleHidden = 'Want to see your reports?';
  static const String _bodyHidden =
      'Just click the \u2018eye\u2019 and you will see the locations of your '
      'reports. You can also move the map around.';

  static const String _titleShown = 'Reports spotted!';
  static const String _bodyShown =
      'Just click the \u2018eye\u2019 again and you will back to the normal '
      'map. You can also move the map around.';

  @override
  Widget build(BuildContext context) {
    final title = showingReports ? _titleShown : _titleHidden;
    final body = showingReports ? _bodyShown : _bodyHidden;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _blue, width: 1.5),
            ),
            padding: const EdgeInsets.fromLTRB(26, 16, 14, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _blue,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: const TextStyle(
                          color: _blue,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _EyeButton(
                  showingReports: showingReports,
                  onTap: onToggle,
                ),
              ],
            ),
          ),

          // Decorative pin straddling the card's top-left corner.
          const Positioned(
            left: -4,
            top: -20,
            child: IgnorePointer(
              child: Icon(
                Icons.location_on_outlined,
                size: 42,
                color: _orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EyeButton extends StatelessWidget {
  const _EyeButton({
    required this.showingReports,
    required this.onTap,
  });

  final bool showingReports;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: showingReports
          ? 'Hide my report locations'
          : 'Show my report locations',
      child: Material(
        color: MapHintCard._orange,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  showingReports
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  key: ValueKey<bool>(showingReports),
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
