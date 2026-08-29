// SmartSumbong — background-resume lock.
//
// Face ID / fingerprint unlock (Settings toggle, see biometric_auth.dart)
// only ever gated a *cold start* until this file: each app's
// launch_gate.dart only runs its check once per process, the very first
// launch, so nothing ran when a resident or tanod merely switched away
// to another app and back without Android killing the process -- which,
// on a modern phone, is most of what "backgrounding" actually looks
// like. This covers that second case: a WidgetsBindingObserver watching
// for a real background -> foreground transition, wrapped once around
// each app's MaterialApp via its `builder` parameter, the same place
// ConnectivityBanner already wraps.
//
// Deliberately generic in appearance rather than matching either app's
// palette, same reasoning as ConnectivityBanner: this is infrastructure
// neither app's Figma file has ever drawn, not a designed screen.
//
// The escape hatch matters as much as the lock itself. A resident whose
// finger will not scan right now (wet, cold, bandaged) is not owed a
// dead end -- [onFallback], when the app supplies one, offers a way back
// to the ordinary password screen without ever calling signOut(). The
// session on disk is still perfectly good; a failed prompt only failed
// to prove it is still the same person holding the phone right now, the
// same distinction launch_gate.dart's cold-start version of this gate
// already makes.

import 'package:flutter/material.dart';

import 'biometric_auth.dart';

class BiometricLockGate extends StatefulWidget {
  const BiometricLockGate({
    super.key,
    required this.child,
    this.reason = 'Unlock SmartSumbong',
    this.title = 'Locked',
    this.body = 'Unlock with Face ID or fingerprint to continue.',
    this.unlockLabel = 'Unlock',
    this.fallbackLabel = 'Use password instead',
    this.onFallback,
  });

  final Widget child;

  /// Shown by the OS's own biometric prompt, not by any UI in this file.
  final String reason;
  final String title;
  final String body;
  final String unlockLabel;
  final String fallbackLabel;

  /// Called when the resident/tanod gives up on the prompt and wants the
  /// password screen instead. Left null hides that button entirely.
  /// Wire this to a plain navigation to the app's own login route --
  /// e.g. `navigatorKey.currentState?.pushNamedAndRemoveUntil('/login',
  /// (_) => false)` -- NOT a sign-out. See the header above for why.
  final VoidCallback? onFallback;

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate>
    with WidgetsBindingObserver {
  final _biometrics = BiometricAuthService();

  /// Whether the app has actually been sent to the background since this
  /// widget was built -- covers only paused/hidden -> resumed, not
  /// inactive -> resumed, which also fires for things like the system
  /// volume HUD or a permission dialog passing overhead and is not
  /// "backgrounding" in any sense worth locking over.
  bool _wasBackgrounded = false;

  bool _locked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _maybeLock();
    }
  }

  Future<void> _maybeLock() async {
    if (!await BiometricAuthService.enabled()) return;
    if (!await _biometrics.isAvailable()) return;
    if (!mounted) return;
    setState(() => _locked = true);
    _unlock();
  }

  Future<void> _unlock() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await _biometrics.authenticate(widget.reason);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (ok) _locked = false;
    });
  }

  void _fallback() {
    // Drop the overlay first: onFallback navigates the app underneath
    // it, and a still-locked overlay would just cover the login screen
    // it navigated to.
    setState(() => _locked = false);
    widget.onFallback?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockScreen(
              checking: _checking,
              title: widget.title,
              body: widget.body,
              unlockLabel: widget.unlockLabel,
              fallbackLabel: widget.fallbackLabel,
              onUnlock: _unlock,
              onFallback: widget.onFallback == null ? null : _fallback,
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.checking,
    required this.title,
    required this.body,
    required this.unlockLabel,
    required this.fallbackLabel,
    required this.onUnlock,
    required this.onFallback,
  });

  final bool checking;
  final String title;
  final String body;
  final String unlockLabel;
  final String fallbackLabel;
  final VoidCallback onUnlock;
  final VoidCallback? onFallback;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF14181D),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              if (checking)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onUnlock,
                    child: Text(unlockLabel),
                  ),
                ),
                if (onFallback != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onFallback,
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    child: Text(fallbackLabel),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
