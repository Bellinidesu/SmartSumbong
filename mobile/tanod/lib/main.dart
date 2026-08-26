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

import 'screens/edit_profile_screen.dart';
import 'screens/languages_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tanod_home_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/account_status_screen.dart';
import 'screens/change_password_screen.dart';
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
        // '/duty' is gone. Duty status lives on Home now, per
        // HOME - TANOD, so the launch gate lands here instead.
        '/home': (_) => TanodHomeScreen(auth: auth),
        '/reports': (_) => const ReportsScreen(),
        '/notifications': (_) => const NotificationsScreen(),
        '/settings': (_) => SettingsScreen(auth: auth),
        '/edit-profile': (_) => EditProfileScreen(auth: auth),
        '/languages': (_) => const LanguagesScreen(),
        '/change-password': (_) => ChangePasswordScreen(auth: auth),
        '/verification-pending': (_) =>
            const _Placeholder('Verification pending'),
        '/verification-rejected': (_) => AccountStatusScreen(
              auth: auth,
              block: AccountBlock.rejected,
              canRegisterAgain: false),
        '/account-suspended': (_) => AccountStatusScreen(
              auth: auth,
              block: AccountBlock.suspended,
              canRegisterAgain: false),
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
