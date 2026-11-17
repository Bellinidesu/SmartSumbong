// SmartSumbong — one time limit for every call the app makes to Supabase (17 Nov 2026, the phone pass).
//
// On a weak signal a request can hang with no answer, and a screen that waits for it spins forever. The
// portal's live checks give up after 10 seconds; the app's location push already gave up after 15. This
// client is handed to Supabase.initialize, so every query, RPC and auth call made through
// Supabase.instance.client stops waiting after 15 seconds and throws a TimeoutException, which each
// screen's existing catch turns into its error and retry. A request with a large body (an upload) gets
// two minutes; live updates use their own WebSocket and are not affected.

import 'dart:async';

import 'package:http/http.dart' as http;

class TimeoutClient extends http.BaseClient {
  TimeoutClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  static const normal = Duration(seconds: 15);
  static const upload = Duration(minutes: 2);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final big = (request.contentLength ?? 0) > 512 * 1024;
    return _inner.send(request).timeout(big ? upload : normal);
  }

  @override
  void close() => _inner.close();
}
