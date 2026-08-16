// SmartSumbong — resident app entry point.
//
// Run with:
//   flutter run --dart-define-from-file=dart_defines.json
//
// dart_defines.json holds the cloud name, the unsigned preset, the
// Supabase URL and the anon key. All four are public by design: they
// ship inside any built APK and can be read out of it. RLS is what
// guards the data. The service role key must never appear in that file
// or anywhere else under mobile/ — it bypasses RLS entirely and this
// repo is public.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/complaint_category.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/emergency_screen.dart';
import 'screens/home_screen.dart';
import 'screens/languages_screen.dart';
import 'screens/launch_gate.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/register_screen.dart';
import 'screens/report_category_screen.dart';
import 'screens/role_picker_screen.dart';
import 'screens/report_details_screen.dart';
import 'screens/report_submitted_screen.dart';
import 'screens/report_view_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/verification_pending_screen.dart';
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
  runApp(const SmartSumbongApp());
}

class SmartSumbongApp extends StatelessWidget {
  const SmartSumbongApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService(Supabase.instance.client);
    final uploader = MediaUploader(
      cloudName: _cloudName,
      uploadPreset: _uploadPreset,
    );

    return MaterialApp(
      title: 'SmartSumbong',
      debugShowCheckedModeBanner: false,
      theme: buildResidentTheme(),
      // Every launch goes through the gate, which decides where the
      // person actually belongs: no session, pending, verified,
      // rejected or suspended. A fixed initialRoute cannot know.
      initialRoute: '/',
      // The details screen carries the chosen category, which a plain
      // route table cannot pass.
      onGenerateRoute: (settings) {
        if (settings.name == '/report-submitted') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => ReportSubmittedScreen(
              trackingId: settings.arguments as String?,
            ),
          );
        }
        if (settings.name == '/report') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) =>
                ReportViewScreen(reportId: settings.arguments as String),
          );
        }
        if (settings.name == '/submit-report/details') {
          final choice = settings.arguments as CategoryChoice;
          return MaterialPageRoute(
            settings: settings,
            builder: (_) =>
                ReportDetailsScreen(choice: choice, uploader: uploader),
          );
        }
        return null;
      },
      routes: {
        '/': (_) => LaunchGate(auth: auth),
        '/register': (_) => RegisterScreen(auth: auth, uploader: uploader),
        '/verification-pending': (_) => VerificationPendingScreen(auth: auth),
        '/verification-rejected': (_) =>
            const _Placeholder('Verification rejected'),
        '/account-suspended': (_) => const _Placeholder('Account suspended'),
        '/home': (_) => HomeScreen(auth: auth),

        // Tabs and destinations reachable from Home. Each becomes a real
        // screen in turn; until then the placeholder keeps navigation
        // from throwing on an unknown route.
        '/emergency': (_) => const EmergencyScreen(),
        '/reports': (_) => ReportsScreen(auth: auth),
        '/map': (_) => MapScreen(auth: auth),
        '/settings': (_) => SettingsScreen(auth: auth),
        '/edit-profile': (_) => EditProfileScreen(auth: auth),
        '/languages': (_) => const LanguagesScreen(),
        '/notifications': (_) => const NotificationsScreen(),
        '/submit-report': (_) => const ReportCategoryScreen(),

        '/login': (_) => LoginScreen(auth: auth),
        '/onboarding': (_) => const OnboardingScreen(),
        '/roles': (_) => const RolePickerScreen(),
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text('$name — not built yet')),
      );
}

class _ConfigError extends StatelessWidget {
  const _ConfigError(this.missing);
  final List<String> missing;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          backgroundColor: Tokens.bg,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Missing build configuration',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Tokens.navy),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${missing.join(', ')}\n\n'
                    'Run with --dart-define-from-file=dart_defines.json',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Tokens.hint),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
