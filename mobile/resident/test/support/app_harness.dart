// Runs the real app in a widget test, over the preview's in-memory backend
// (lib/preview/fake_backend.dart): real screens, real navigation, dummy
// data, no network. Each test file runs in its own isolate, so each gets a
// fresh Supabase client and backend.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/i18n.dart';
import 'package:resident/main.dart' show SmartSumbongApp;
import 'package:resident/preview/demo.dart';
import 'package:resident/preview/fake_backend.dart';
import 'package:resident/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The native plugins the app touches on start, answered the way a phone
/// with a working connection would.
void stubPlatform({bool online = true}) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>[online ? 'wifi' : 'none'] : null);
  for (final name in ['dev.fluttercommunity.plus/connectivity_status', 'com.llfbandit.app_links/events']) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
}

bool _fontsLoaded = false;

/// The app's own fonts, so text is measured as on a phone (the test
/// default draws every letter as a wide square, which overflows layouts
/// that fit fine). An overflow these tests report is a real one.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  const families = {
    'Urbanist': ['Light', 'Regular', 'Italic', 'Medium', 'MediumItalic', 'SemiBold', 'Bold', 'BoldItalic', 'ExtraBold', 'Black'],
    'Inter': ['Regular', 'Medium', 'SemiBold', 'Bold'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final style in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/${entry.key}-$style.ttf'));
    }
    await loader.load();
  }
}

/// Boots the app. [role] 'resident' or 'tanod' starts signed in as the demo
/// account; null starts signed out (onboarding already seen).
Future<DemoBackend> bootApp(WidgetTester tester, {String? role = 'resident', bool online = true}) async {
  // A typical Android phone, portrait (the app is portrait only).
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  // No network in tests: pictures (avatars, map tiles, evidence) cannot
  // load. That is not what these tests check, so only those errors are
  // ignored; every other error still fails the test.
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'image resource service') return;
    reportError?.call(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
  SharedPreferences.setMockInitialValues({'onboarding_seen': true});
  FlutterSecureStorage.setMockInitialValues({});
  stubPlatform(online: online);
  kDemo = true;
  PermissionGate.bypass = true;
  final backend = DemoBackend(role: role ?? 'resident');
  await tester.runAsync(() async {
    await loadAppFonts();
    // A fresh client per test, not the previous test's session.
    try {
      await Supabase.instance.dispose();
    } catch (_) {}
    await Supabase.initialize(
      url: 'https://demo.supabase.co',
      publishableKey: 'demo',
      httpClient: backend,
      authOptions: FlutterAuthClientOptions(
        localStorage: DemoSessionStorage(role == null ? null : jsonEncode(backend.sessionJson())),
        autoRefreshToken: false,
      ),
    );
  });
  AppRoleController.instance.value = role == 'tanod' ? AppRole.tanod : AppRole.resident;
  final locale = await LocaleController.load();
  final theme = await ThemeController.load();
  await tester.pumpWidget(SmartSumbongApp(locale: locale, themeController: theme));
  await settle(tester);
  return backend;
}

/// Lets real async work (the fake backend's HTTP, storage) finish between
/// frames; pumpAndSettle alone never returns while a spinner animates.
Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Every piece of text on screen, for assertions and for debugging.
List<String> screenText() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText())
    .whereType<String>()
    .toList();

/// Ends a test: unmounts the app and lets one-shot timers (refreshes,
/// toasts) run out, so no screen's timer outlives the test. Call last.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 5));
}
