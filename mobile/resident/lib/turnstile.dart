// SmartSumbong — Cloudflare Turnstile, the bot check Supabase Auth asks for
// once CAPTCHA protection is switched on (backend review, 10 Oct 2026).
//
// Built on webview_flutter (maintained by the Flutter team) rather than a
// third-party Turnstile package: the one tried first pulled in a webview
// plugin whose Android build no longer compiles with this project's Gradle
// plugin. Turnstile's own script runs in a small web view laid over the
// current screen; it solves the challenge (invisibly, for the Invisible
// widget mode, or with one tap for Managed) and hands the token back.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// One fresh token for [siteKey], or null when the check could not finish
/// (offline, timed out, or Cloudflare refused). [baseUrl] must be one of
/// the widget's allowed domains in Cloudflare; [overlay] is where the
/// small web view is shown while the check runs.
Future<String?> turnstileToken({
  required String siteKey,
  required String baseUrl,
  required OverlayState? overlay,
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (overlay == null) return null;
  final done = Completer<String?>();
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.transparent)
    ..addJavaScriptChannel('SmartSumbongTurnstile', onMessageReceived: (m) {
      if (done.isCompleted) return;
      final token = m.message;
      done.complete(token.isEmpty ? null : token);
    });

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        // Turnstile's own frame is 300x65; it draws nothing unless a person
        // has to tick the box.
        child: SizedBox(width: 300, height: 70, child: WebViewWidget(controller: controller)),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await controller.loadHtmlString(_page(siteKey), baseUrl: baseUrl);
    return await done.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    entry.remove();
  }
}

String _page(String siteKey) => '''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;background:transparent;display:flex;justify-content:center}</style>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer onload="go()"></script>
<script>
function send(t) { SmartSumbongTurnstile.postMessage(t || ''); }
function go() {
  turnstile.render('#box', {
    sitekey: ${jsonEncode(siteKey)},
    appearance: 'interaction-only',
    callback: send,
    'error-callback': function () { send(''); },
    'expired-callback': function () { send(''); }
  });
}
</script></head><body><div id="box"></div></body></html>''';
