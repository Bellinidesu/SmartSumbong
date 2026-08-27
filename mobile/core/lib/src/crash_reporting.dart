// SmartSumbong — crash visibility.
//
// Before this, the only way anyone found out a build was crashing on a
// real device was a screenshot someone happened to send. Crashlytics
// rides along on the same Firebase project the push notification setup
// already needs, so it costs nothing extra to wire in.

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashReporting {
  CrashReporting._();

  /// Call once, after Firebase.initializeApp(), before runApp.
  static void install() {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// For the one place install() cannot reach: an error thrown from
  /// main() itself, outside the Flutter widget tree and outside the
  /// platform dispatcher's own zone -- see each app's runZonedGuarded.
  static void recordError(Object error, StackTrace stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  }
}
