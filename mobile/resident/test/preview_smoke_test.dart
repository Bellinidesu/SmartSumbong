// Drives the Dart preview's screens over its in-memory backend and fails on
// any exception: a missing column in the dummy data, a type that does not
// cast, a screen that cannot build. No visuals — that is what a phone is
// for — but it proves every screen can open on the data it is given.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/i18n.dart';
import 'package:resident/main.dart' show SmartSumbongApp, navigatorKey;
import 'package:resident/preview/demo.dart';
import 'package:resident/preview/fake_backend.dart';
import 'package:resident/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _boot(String role) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({'onboarding_seen': true});
  kDemo = true;
  PermissionGate.bypass = true;
  // plugins with no test implementation answer "nothing"
  for (final ch in ['dev.fluttercommunity.plus/connectivity', 'dev.fluttercommunity.plus/connectivity_status', 'com.llfbandit.app_links/messages', 'com.llfbandit.app_links/events']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
  }
  final backend = DemoBackend(role: role);
  await Supabase.initialize(
    url: 'https://demo.supabase.co',
    publishableKey: 'demo',
    httpClient: backend,
    authOptions: FlutterAuthClientOptions(localStorage: DemoSessionStorage(jsonEncode(backend.sessionJson())), autoRefreshToken: false),
  );
  AppRoleController.instance.value = role == 'tanod' ? AppRole.tanod : AppRole.resident;
}

/// Opens [route] on top of the app and returns what it threw, if anything.
Future<List<String>> _visit(WidgetTester tester, List<String> routes, {Object? arguments}) async {
  final problems = <String>[];
  for (final r in routes) {
    navigatorKey.currentState!.pushNamed(r, arguments: arguments is Map ? arguments[r] : arguments);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final e = tester.takeException();
    if (e != null) problems.add('$r: $e');
    navigatorKey.currentState!.popUntil((x) => x.isFirst);
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();
  }
  return problems;
}

void main() {
  // network images answer 400 in tests; that is not what this checks
  final ignore = RegExp(r'HTTP request failed|NetworkImage|Image provider|image resource|Failed to load network image|statusCode: 400');
  final real = <String>[];
  setUpAll(() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (!ignore.hasMatch(s) && !ignore.hasMatch('${d.library}')) real.add(s.split('\n').first);
      prev?.call(d);
    };
  });

  testWidgets('resident: every screen opens', (tester) async {
    await _boot('resident');
    final locale = LocaleController();
    final theme = ThemeController();
    await tester.pumpWidget(SmartSumbongApp(locale: locale, themeController: theme));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    final problems = await _visit(tester, [
      '/reports', '/home', '/emergency', '/settings', '/edit-profile', '/languages', '/appearance', '/notifications',
      '/notification-preferences', '/terms-privacy', '/submit-report', '/change-password',
    ]);
    // one report's page, its messages
    for (final n in ['103', '101', '088', '080', '075', '055']) {
      problems.addAll(await _visit(tester, ['/report'], arguments: 'b1000000-0000-4000-8000-000000000$n'));
    }
    expect(problems, isEmpty);
    expect(real, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
