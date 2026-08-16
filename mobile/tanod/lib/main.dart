// SmartSumbong — tanod app entry point.
//
// Run with:
//   flutter run --dart-define-from-file=dart_defines.json
//
// The same four values as the resident app, pointing at the same
// project. All four are public by design: they ship inside any built
// APK and can be read out of it. RLS is what guards the data, and a
// tanod's JWT carries role 'tanod', which is what every dispatch policy
// keys off. The service role key must never appear here.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/duty_screen.dart';
import 'screens/launch_gate.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final missing = {
    'SUPABASE_URL': _supabaseUrl,
    'SUPABASE_ANON_KEY': _supabaseAnonKey,
    'CLOUDINARY_CLOUD_NAME': _cloudName,
    'CLOUDINARY_UPLOAD_PRESET': _uploadPreset,
  }.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();

  if (missing.isNotEmpty) {
    runApp(_ConfigError(missing));
    return;
  }

  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  runApp(const SmartSumbongTanodApp());
}

class SmartSumbongTanodApp extends StatelessWidget {
  const SmartSumbongTanodApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService(Supabase.instance.client);

    return MaterialApp(
      title: 'SmartSumbong Tanod',
      debugShowCheckedModeBanner: false,
      theme: buildTanodTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => LaunchGate(auth: auth),
        '/login': (_) => LoginScreen(auth: auth),
        '/duty': (_) => const DutyScreen(),
        '/verification-pending': (_) =>
            const _Placeholder('Verification pending'),
        '/verification-rejected': (_) =>
            const _Placeholder('Verification rejected'),
        '/account-suspended': (_) => const _Placeholder('Account suspended'),
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text(name)),
      );
}

class _ConfigError extends StatelessWidget {
  const _ConfigError(this.missing);

  final List<String> missing;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Missing configuration:\n\n${missing.join('\n')}\n\n'
                'Run with --dart-define-from-file=dart_defines.json',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
