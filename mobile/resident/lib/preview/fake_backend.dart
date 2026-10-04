// SmartSumbong — the preview's in-memory backend.
//
// A package:http client that answers the calls supabase_flutter makes —
// PostgREST tables, RPCs and the auth endpoints — from the dummy tables in
// demo_data.dart. The real screens run unchanged on top of it, and what
// the preview does is remembered for the session: accepting a dispatch,
// posting a message, resolving a case all change the tables, so the next
// screen sees them. Filters (eq, neq, in, is, gt/lt, not) and order/limit
// are honoured; `select` is ignored (rows carry every column).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo_data.dart';

class DemoBackend extends http.BaseClient {
  DemoBackend({required String role}) : _me = role == 'tanod' ? demoTanodId : demoResidentId;

  final _t = buildDemoTables();
  String _me;
  var _seq = 200;

  String get meId => _me;
  bool get isTanod => _me == demoTanodId;
  Map<String, dynamic> get _meRow => _t['users']!.firstWhere((u) => u['id'] == _me);

  String _uid() => 'zz${(_seq++).toString().padLeft(6, '0')}-0000-4000-8000-${DateTime.now().microsecondsSinceEpoch.toString().padLeft(12, '0').substring(0, 12)}';
  String _now() => DateTime.now().toUtc().toIso8601String();

  // ───────── session ─────────
  String _jwt() {
    String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
    return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': _me, 'role': 'authenticated', 'aud': 'authenticated', 'exp': exp, 'email': _meRow['email'] ?? 'tanod@demo.test'})}.demo';
  }

  Map<String, dynamic> _user() => {
        'id': _me, 'aud': 'authenticated', 'role': 'authenticated', 'email': _meRow['email'] ?? 'tanod@demo.test',
        'phone': '', 'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}, 'created_at': _now(), 'updated_at': _now(),
      };

  Map<String, dynamic> sessionJson() {
    final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
    return {'access_token': _jwt(), 'token_type': 'bearer', 'expires_in': 315360000, 'expires_at': exp, 'refresh_token': 'demo', 'user': _user()};
  }

  // ───────── http ─────────
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await _handle(request);
    // postgrest reads response.request, which a hand-built response lacks
    return http.StreamedResponse(r.stream, r.statusCode, contentLength: r.contentLength, request: request, headers: r.headers, reasonPhrase: r.reasonPhrase);
  }

  Future<http.StreamedResponse> _handle(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    dynamic data;
    try {
      data = body.isEmpty ? null : jsonDecode(body);
    } catch (_) {}
    final path = request.url.path;
    try {
      if (path.contains('/auth/v1/')) return _auth(request, path, data);
      if (path.contains('/rest/v1/rpc/')) return _rpc(path.split('/rpc/').last, data);
      if (path.contains('/rest/v1/')) return _table(request, path.split('/rest/v1/').last, data);
      if (path.contains('/functions/v1/')) return _json(200, <String, dynamic>{});
    } catch (e) {
      return _json(400, {'code': 'DEMO', 'message': '$e'});
    }
    return _json(404, {'message': 'not found: $path'});
  }

  http.StreamedResponse _json(int status, Object? body, {Map<String, String> headers = const {}}) {
    final bytes = body == null ? <int>[] : utf8.encode(jsonEncode(body));
    return http.StreamedResponse(Stream.value(bytes), status, contentLength: bytes.length, headers: {'content-type': 'application/json; charset=utf-8', ...headers});
  }

  http.StreamedResponse _empty(int status) => http.StreamedResponse(const Stream.empty(), status, headers: const {'content-type': 'application/json'});

  // ───────── auth ─────────
  http.StreamedResponse _auth(http.BaseRequest r, String path, dynamic data) {
    if (path.endsWith('/logout')) return _empty(204);
    if (path.endsWith('/token')) {
      if (r.url.queryParameters['grant_type'] == 'password' && data is Map) {
        // The tanod's demo number is 0927 126 9625; any other signs in as Rose.
        final who = '${data['email'] ?? ''}${data['phone'] ?? ''}';
        _me = who.contains('9271269625') || who.contains('9271269625'.substring(1)) ? demoTanodId : demoResidentId;
      }
      return _json(200, sessionJson());
    }
    if (path.endsWith('/user')) return _json(200, _user());
    return _json(200, <String, dynamic>{});
  }

  // ───────── tables ─────────
  dynamic _path(Map<String, dynamic> row, String key) {
    dynamic v = row;
    for (final k in key.split('.')) {
      if (v is Map) {
        v = v[k];
      } else {
        return null;
      }
    }
    return v;
  }

  bool _cmp(dynamic v, String expr) {
    if (expr.startsWith('not.')) return !_cmp(v, expr.substring(4));
    final dot = expr.indexOf('.');
    final op = dot < 0 ? expr : expr.substring(0, dot);
    final arg = dot < 0 ? '' : expr.substring(dot + 1);
    String s(dynamic x) => x == null ? 'null' : '$x';
    switch (op) {
      case 'eq':
        return s(v) == arg;
      case 'neq':
        return s(v) != arg;
      case 'is':
        return arg == 'null' ? v == null : s(v) == arg;
      case 'in':
        final items = arg.substring(1, arg.length - 1).split(',').map((e) => e.replaceAll('"', '').trim()).toList();
        return items.contains(s(v));
      case 'gt':
      case 'gte':
      case 'lt':
      case 'lte':
        final a = num.tryParse(s(v)), b = num.tryParse(arg);
        final c = (a != null && b != null) ? a.compareTo(b) : s(v).compareTo(arg);
        return op == 'gt' ? c > 0 : op == 'gte' ? c >= 0 : op == 'lt' ? c < 0 : c <= 0;
      case 'ilike':
      case 'like':
        return s(v).toLowerCase().contains(arg.replaceAll('%', '').toLowerCase());
      default:
        return true;
    }
  }

  /// Rows of [table] with the embedded resources the screens ask for.
  List<Map<String, dynamic>> _rows(String table) {
    final rows = _t[table] ?? <Map<String, dynamic>>[];
    if (table == 'dispatches') {
      return [
        for (final d in rows)
          {
            ...d,
            'reports': _t['reports']!.where((r) => r['id'] == d['report_id']).firstOrNull,
            'dispatch_media': _t['dispatch_media']!.where((m) => m['dispatch_id'] == d['id']).toList(),
          },
      ];
    }
    if (table == 'dispatch_media') {
      return [
        for (final m in rows)
          {...m, 'dispatches': {'report_id': _t['dispatches']!.where((d) => d['id'] == m['dispatch_id']).firstOrNull?['report_id']}},
      ];
    }
    return [for (final r in rows) {...r}];
  }

  List<Map<String, dynamic>> _filtered(String table, Map<String, List<String>> q) {
    var rows = _rows(table);
    q.forEach((key, exprs) {
      if (const {'select', 'order', 'limit', 'offset', 'columns', 'on_conflict'}.contains(key)) return;
      for (final e in exprs) {
        rows = rows.where((r) => _cmp(_path(r, key), e)).toList();
      }
    });
    final order = q['order']?.first;
    if (order != null) {
      final first = order.split(',').first.split('.');
      final key = first.first, desc = first.length > 1 && first[1] == 'desc';
      rows.sort((a, b) {
        final x = '${a[key] ?? ''}', y = '${b[key] ?? ''}';
        final nx = num.tryParse(x), ny = num.tryParse(y);
        final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
        return desc ? -c : c;
      });
    }
    final limit = int.tryParse(q['limit']?.first ?? '');
    if (limit != null && rows.length > limit) rows = rows.sublist(0, limit);
    return rows;
  }

  http.StreamedResponse _table(http.BaseRequest r, String table, dynamic data) {
    final q = r.url.queryParametersAll;
    final accept = r.headers['Accept'] ?? r.headers['accept'] ?? '';
    final prefer = r.headers['Prefer'] ?? r.headers['prefer'] ?? '';
    final wantsRows = prefer.contains('return=representation');
    switch (r.method) {
      case 'GET':
      case 'HEAD':
        final rows = _filtered(table, q);
        final n = rows.length;
        final range = {'content-range': n == 0 ? '*/0' : '0-${n - 1}/$n'};
        if (r.method == 'HEAD') return _json(200, null, headers: range);
        if (accept.contains('vnd.pgrst.object')) {
          if (rows.isEmpty) {
            return _json(406, {'code': 'PGRST116', 'details': 'The result contains 0 rows', 'hint': null, 'message': 'JSON object requested, multiple (or no) rows returned'});
          }
          return _json(200, rows.first, headers: range);
        }
        return _json(200, rows, headers: range);
      case 'POST':
        final items = data is List ? data : [data];
        final made = <Map<String, dynamic>>[];
        for (final it in items) {
          final row = {'id': _uid(), 'created_at': _now(), ...(it as Map<String, dynamic>)};
          (_t[table] ??= []).add(row);
          made.add(row);
        }
        return wantsRows ? _json(201, data is List ? made : made.first) : _empty(201);
      case 'PATCH':
        final hit = _filtered(table, q).map((e) => e['id']).toSet();
        final out = <Map<String, dynamic>>[];
        for (final row in _t[table] ?? <Map<String, dynamic>>[]) {
          if (hit.contains(row['id'])) {
            row.addAll(data as Map<String, dynamic>);
            out.add(row);
          }
        }
        return wantsRows ? _json(200, out) : _empty(204);
      case 'DELETE':
        final hit = _filtered(table, q).map((e) => e['id']).toSet();
        _t[table]?.removeWhere((row) => hit.contains(row['id']));
        return _empty(204);
    }
    return _json(405, {'message': 'method'});
  }

  // ───────── rpc ─────────
  Map<String, dynamic>? _find(String table, Object? id) => _t[table]!.where((r) => r['id'] == id).firstOrNull;

  void _log(String reportId, String? old, String status, String remark) => _t['status_logs']!.add({
        'id': _uid(), 'report_id': reportId, 'old_status': old, 'new_status': status, 'remark': remark, 'created_at': _now(),
      });

  http.StreamedResponse _rpc(String fn, dynamic p) {
    final a = (p is Map ? p : <String, dynamic>{}).cast<String, dynamic>();
    switch (fn) {
      case 'my_role':
        return _json(200, isTanod ? 'tanod' : 'resident');
      case 'check_login_lockout':
      case 'register_login_failure':
        return _json(200, [{'locked': false, 'seconds_remaining': 0, 'attempts_left': 5}]);
      case 'my_retirement_status':
        final pending = (_t['retirement'] ?? []).isNotEmpty;
        return _json(200, [{'status': pending ? 'pending' : 'none'}]);
      case 'request_retirement':
        (_t['retirement'] ??= []).add({'id': _uid()});
        return _empty(204);
      case 'public_incidents':
        return _json(200, [
          {'id': 'p1', 'latitude': 14.5272, 'longitude': 121.0156, 'category': 'street_obstruction', 'status': 'in_progress'},
          {'id': 'p2', 'latitude': 14.5249, 'longitude': 121.0170, 'category': 'environmental_waste_hazard', 'status': 'pending_review'},
          {'id': 'p3', 'latitude': 14.5290, 'longitude': 121.0135, 'category': 'traffic_violation', 'status': 'resolved'},
        ]);
      case 'my_resolution_authors':
        return _json(200, [
          for (final id in (a['p_report_ids'] as List? ?? []))
            {'report_id': id, 'is_system': false, 'author_name': 'Kim'},
        ]);
      case 'my_status_log_authors':
        final logs = _t['status_logs']!.where((l) => l['report_id'] == a['p_report_id']).toList();
        return _json(200, [for (var i = 0; i < logs.length; i++) {'status_log_id': logs[i]['id'], 'is_system': i == 0, 'author_name': 'Kim'}]);
      case 'file_report':
        final n = _t['reports']!.length + 98;
        final row = {
          'id': _uid(), 'resident_id': _me, 'tracking_id': 'BRG-2026-0${n + 100}', 'category': a['p_category'], 'subject': a['p_subject'],
          'description': a['p_description'], 'status': 'pending_review', 'latitude': a['p_latitude'], 'longitude': a['p_longitude'],
          'location_label': null, 'is_anonymous': a['p_is_anonymous'] ?? false, 'created_at': _now(), 'resolved_at': null, 'closed_at': null,
          'reopened_count': 0, 'due_at': DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String(), 'referred_to': null,
          'referral_note': null, 'followed_up_at': null, 'deleted_at': null,
        };
        _t['reports']!.add(row);
        _log(row['id'] as String, null, 'pending_review', 'Report submitted');
        return _json(200, row);
      case 'cancel_report':
        final r = _find('reports', a['p_report']);
        if (r != null) {
          _log(r['id'] as String, r['status'] as String, 'cancelled', 'Cancelled by the resident');
          r['status'] = 'cancelled';
        }
        return _empty(204);
      case 'request_reopen':
      case 'request_appeal':
        final r = _find('reports', a['p_report']);
        if (r != null) {
          _log(r['id'] as String, r['status'] as String, 'pending_review', a['p_reason'] as String? ?? 'Requested');
          r['status'] = 'pending_review';
          r['reopened_count'] = (r['reopened_count'] as int? ?? 0) + 1;
        }
        return _empty(204);
      case 'follow_up_report':
        _find('reports', a['p_report'])?['followed_up_at'] = _now();
        return _empty(204);
      case 'post_report_message':
        _t['report_messages']!.add({'id': _uid(), 'report_id': a['p_report'], 'from_barangay': false, 'body': a['p_body'], 'created_at': _now()});
        return _empty(204);
      case 'request_additional_details':
        _t['detail_requests']!.add({'id': _uid(), 'report_id': a['p_report'], 'message': a['p_message'], 'requested_at': _now(), 'response': null, 'responded_at': null});
        return _empty(204);
      case 'submit_additional_details':
        final d = _find('detail_requests', a['p_request']);
        if (d != null) {
          d['responded_at'] = _now();
          d['response'] = a['p_details'];
        }
        return _empty(204);
      case 'set_notification_mute':
        final list = ((_meRow['muted_notification_kinds'] as List?) ?? []).cast<String>().toList();
        a['p_muted'] == true ? list.add('${a['p_kind']}') : list.remove('${a['p_kind']}');
        _meRow['muted_notification_kinds'] = list.toSet().toList();
        return _empty(204);
      case 'accept_dispatch':
        final d = _find('dispatches', a['p_dispatch']);
        if (d != null) {
          d['state'] = 'accepted';
          d['accepted_at'] = _now();
          _t['dispatch_updates']!.add({'id': _uid(), 'dispatch_id': d['id'], 'author_id': _me, 'kind': 'step', 'step': 'accepted', 'body': null, 'created_at': _now()});
        }
        return _empty(204);
      case 'reroute_dispatch':
        _find('dispatches', a['p_dispatch'])?['state'] = 'rerouted';
        return _empty(204);
      case 'set_dispatch_step':
        final d = _find('dispatches', a['p_dispatch']);
        if (d != null) {
          d['step'] = a['p_step'];
          _t['dispatch_updates']!.add({'id': _uid(), 'dispatch_id': d['id'], 'author_id': _me, 'kind': 'step', 'step': a['p_step'], 'body': null, 'created_at': _now()});
          final rep = _find('reports', d['report_id']);
          if (rep != null && rep['status'] == 'assigned') rep['status'] = 'in_progress';
        }
        return _empty(204);
      case 'post_dispatch_update':
        final id = _uid();
        _t['dispatch_updates']!.add({'id': id, 'dispatch_id': a['p_dispatch'], 'author_id': _me, 'kind': 'note', 'step': null, 'body': a['p_body'], 'created_at': _now()});
        for (final m in (a['p_media'] as List? ?? [])) {
          if (m is Map) _t['dispatch_media']!.add({'id': _uid(), 'dispatch_id': a['p_dispatch'], 'update_id': id, 'media_url': m['media_url'], 'mime_type': m['mime_type']});
        }
        return _empty(204);
      case 'submit_field_report':
        final d = _find('dispatches', a['p_dispatch']);
        if (d != null) {
          d['state'] = 'resolved';
          d['resolved_at'] = _now();
          d['field_report_text'] = a['p_text'];
        }
        return _empty(204);
      case 'request_escalation':
        _t['escalation_requests']!.add({'id': _uid(), 'dispatch_id': a['p_dispatch'], 'reason': a['p_reason'], 'status': 'pending', 'decision_note': null, 'created_at': _now()});
        return _empty(204);
      default:
        // set_report_location_label, update_my_location, request_profile_change,
        // register/unregister_device_token, clear_*: accepted and forgotten.
        return _empty(204);
    }
  }
}

/// Holds the demo session in memory in place of the Keystore.
class DemoSessionStorage extends LocalStorage {
  DemoSessionStorage(this._session);

  String? _session;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<bool> hasAccessToken() async => _session != null;

  @override
  Future<void> persistSession(String persistSessionString) async => _session = persistSessionString;

  @override
  Future<void> removePersistedSession() async => _session = null;
}
