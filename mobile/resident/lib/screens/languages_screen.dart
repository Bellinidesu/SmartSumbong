// SmartSumbong — Select Language.
//
// Figma: LANGUAGES.
//
// The screen from the design, with the choice recorded per handset.
// Nothing is translated yet: i18n is deferred for both apps, so English
// is the only option that changes anything today. Filipino is offered
// because the frame offers it and because the barangay asked for it —
// but it is marked as not yet available rather than silently doing
// nothing, since a radio button that appears to take and then changes
// no text is the worse failure.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

const languageKey = 'language';

class LanguagesScreen extends StatefulWidget {
  const LanguagesScreen({super.key});

  @override
  State<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends State<LanguagesScreen> {
  String _value = 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(languageKey);
      if (!mounted || v == null) return;
      setState(() => _value = v);
    } catch (_) {
      // Falls back to English, which is what the app renders anyway.
    }
  }

  Future<void> _choose(String v) async {
    setState(() => _value = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(languageKey, v);
    } catch (_) {
      // The choice stands for this session either way.
    }

    if (v == 'fil' && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Tokens.navy,
            content: Text('Filipino is not available yet. The app will '
                'stay in English for now.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text('Select Language',
                  style: t.headlineLarge?.copyWith(fontSize: 24)),
              const SizedBox(height: 28),

              _LanguageRow(
                label: 'Filipino / Tagalog',
                selected: _value == 'fil',
                onTap: () => _choose('fil'),
              ),
              const SizedBox(height: 14),
              _LanguageRow(
                label: 'English',
                selected: _value == 'en',
                onTap: () => _choose('en'),
              ),

              const SizedBox(height: 30),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
                child: const Text('Back'),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _orange = Color(0xFFFF9800);

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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 14, color: Tokens.navy),
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _orange, width: 2),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _orange,
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
