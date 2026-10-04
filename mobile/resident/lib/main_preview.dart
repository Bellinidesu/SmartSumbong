// SmartSumbong — the Dart preview's entry point (branch D).
//
// The app, itself, on dummy data. No translation from HTML: these are the
// real screens, the real theme and the real navigation, running over an
// in-memory backend (preview/fake_backend.dart).
//
//   flutter run -d web-server --web-port 5000 -t lib/main_preview.dart
//
// then open http://localhost:5000 — add ?role=tanod to start as Kim the
// tanod, ?role=none to start signed out (onboarding, role picker, sign-in;
// 0927 126 9625 and any password signs in as the tanod, any other number
// as Rose the resident). Nothing here is reachable from the real app.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'i18n.dart';
import 'main.dart' show SmartSumbongApp;
import 'preview/demo.dart';
import 'preview/fake_backend.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kDemo = true;
  // No native permission prompts in a browser; the pickers just open.
  PermissionGate.bypass = true;

  final role = Uri.base.queryParameters['role'] ?? 'resident';
  final backend = DemoBackend(role: role == 'tanod' ? 'tanod' : 'resident');
  await Supabase.initialize(
    url: 'https://demo.supabase.co',
    anonKey: 'demo',
    httpClient: backend,
    authOptions: FlutterAuthClientOptions(
      localStorage: DemoSessionStorage(role == 'none' ? null : jsonEncode(backend.sessionJson())),
      autoRefreshToken: false,
    ),
  );

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedOut) {
      unawaited(AppRoleController.instance.set(AppRole.resident));
    }
  });

  final locale = await LocaleController.load();
  final theme = await ThemeController.load();
  AppRoleController.instance.value = role == 'tanod' ? AppRole.tanod : AppRole.resident;
  runApp(SmartSumbongApp(locale: locale, themeController: theme));
}
