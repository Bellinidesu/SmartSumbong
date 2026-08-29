// SmartSumbong — this file moved.
//
// Face ID / fingerprint unlock now lives in smartsumbong_core, shared
// with the tanod app -- see mobile/core/lib/src/biometric_auth.dart and
// biometric_lock_gate.dart. Nothing in this app imports this file any
// more; both screens.launch_gate.dart and screens/settings_screen.dart
// get BiometricAuthService from `package:smartsumbong_core/
// smartsumbong_core.dart` instead, same as every other shared type.
//
// Left as a dead stub rather than deleted: this session's remote-device
// bridge can overwrite files on your PC but cannot delete them. Safe to
// delete by hand.
