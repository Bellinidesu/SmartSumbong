"""A fake Supabase (PostgREST + enough GoTrue) with fixture data, to see portal screens without touching production."""
import json, re, sys, datetime as dt
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

NOW = dt.datetime.now(dt.timezone.utc)
def ago(h): return (NOW - dt.timedelta(hours=h)).isoformat()
def ahead(h): return (NOW + dt.timedelta(hours=h)).isoformat()

ADMIN = {'id': 'a0000000-0000-0000-0000-000000000001', 'full_name': 'Reyes, Marites', 'email': 'sec@brgy183.test', 'role': 'admin',
         'verification_status': 'verified', 'is_suspended': False, 'must_change_password': False, 'avatar_url': None,
         'official_role': 'secretary', 'committee': None, 'created_at': ago(900)}
KAG = {**ADMIN, 'id': 'a0000000-0000-0000-0000-000000000002', 'full_name': 'Dela Cruz, Ramon', 'email': 'kag@brgy183.test', 'official_role': 'kagawad', 'committee': 'peace_order'}
CHAIR = {**ADMIN, 'id': 'a0000000-0000-0000-0000-000000000003', 'full_name': 'Santos, Elena', 'email': 'chair@brgy183.test', 'official_role': 'chairman'}

def tanod(i, name, women=False):
    return {'id': f'b0000000-0000-0000-0000-00000000000{i}', 'full_name': name, 'role': 'tanod', 'women_responder': women, 'is_suspended': False}

CATS = ['public_safety_infrastructure', 'peace_order_nuisance', 'environmental_waste_hazard', 'traffic_violation',
        'street_obstruction', 'animal_welfare', 'barangay_service', 'other']
SUBJ = ['Live wire sparking near the school', 'Neighbours fighting every night', 'Clogged canal, knee-deep flood', 'Truck blocking the intersection',
        'Vendors on the sidewalk', 'Stray dogs near the market', 'No response to my earlier report', 'Loud karaoke past midnight']

def report(i, **kw):
    r = {'id': f'c0000000-0000-0000-0000-0000000000{i:02d}', 'tracking_id': f'SS-2610-{1000+i}', 'category': CATS[i % 8], 'subject': SUBJ[i % 8],
         'description': 'Please help. This has been going on for days and the whole street is affected.', 'status': ['pending_review', 'validated', 'assigned', 'in_progress', 'resolved'][i % 5],
         'created_at': ago(3 + i * 7), 'due_at': ahead(20 - i * 3), 'reporter_id': 'd0000000-0000-0000-0000-000000000001', 'is_anonymous': False,
         'latitude': 14.5, 'longitude': 121.0, 'handler_id': ADMIN['id'] if i % 3 == 0 else None, 'handler_name': 'Reyes, Marites' if i % 3 == 0 else None,
         'tier': 0, 'is_sensitive': False, 'deleted_at': None, 'referred_to': None, 'higher_official': None, 'higher_official_note': None, 'handed_up_at': None,
         'location_text': 'Purok 2, Barangay 183', 'version': 1, 'reporter': {'full_name': 'Garcia, Juan', 'mobile_number': '09171234567'},
         'triage': {'score': 80 - i * 6, 'effective_level': ['urgent', 'high', 'normal', 'low'][i % 4], 'override_level': None, 'possible_duplicates': []}}
    r.update(kw); return r

REPORTS = [report(i) for i in range(1, 20)]
for r in REPORTS:
    if r['handler_id']: r['handler'] = {'id': ADMIN['id'], 'full_name': ADMIN['full_name'], 'official_role': 'secretary', 'committee': None}
REPORTS[0].update(status='validated', tier=1, handler_id=KAG['id'], handler={'id': KAG['id'], 'full_name': KAG['full_name'], 'official_role': 'kagawad', 'committee': 'peace_order'}, subject='Live wire sparking near the school', is_sensitive=False)
REPORTS[1].update(is_sensitive=True, subject='Husband hits wife, children scared', category='peace_order_nuisance', status='validated')

TABLES = {
    'users': [ADMIN, KAG, CHAIR, tanod(1, 'Bautista, Jose'), tanod(2, 'Mendoza, Liza', True), tanod(3, 'Cruz, Ben')],
    'reports': REPORTS,
    'report_concerns': [
        {'id': 'e1', 'report_id': REPORTS[0]['id'], 'category': 'public_safety_infrastructure', 'note': 'Wire is on the ground', 'status': 'resolved', 'resolved_at': ago(2), 'remark': 'Meralco crew cut the power', 'created_at': ago(30)},
        {'id': 'e2', 'report_id': REPORTS[0]['id'], 'category': 'barangay_service', 'note': 'Nobody answered the hotline', 'status': 'open', 'resolved_at': None, 'remark': None, 'created_at': ago(29)}],
    'committee_for_category': [{'category': c, 'committee': 'peace_order'} for c in CATS],
    'smart_rules': [{'id': 1, 'storm_mode': True, 'storm_until': ahead(8), 'storm_reason': 'PAGASA orange rainfall warning', 'category_points': {'public_safety_infrastructure': 35, 'peace_order_nuisance': 30, 'environmental_waste_hazard': 25, 'traffic_violation': 20,
                     'street_obstruction': 20, 'animal_welfare': 15, 'barangay_service': 10, 'other': 10}, 'urgent_from': 70, 'high_from': 45, 'normal_from': 25,
                     'storm_mode': True, 'storm_until': ahead(20), 'storm_reason': 'PAGASA orange rainfall warning', 'digest_enabled': True}],
    'operational_settings': [{'max_deadline_extensions': 2}],
    'notifications': [{'id':'n1','kind':'sla_warning','message':'SMART: Urgent report SS-2610-1001 has waited 42 min without a tanod.','created_at':ago(2),'is_read':False,'report_id':REPORTS[0]['id']},{'id':'n2','kind':'status_change','message':'A tanod filed a resolution','created_at':ago(30),'is_read':False,'report_id':REPORTS[1]['id']}],
    'places': [{'id': 1, 'name': 'Barangay 183 Hall', 'grp': 'hall', 'aliases': ['brgy hall'], 'lat': 14.525104, 'lng': 121.012596, 'source': 'barangay'},
               {'id': 2, 'name': 'Harvard Street', 'grp': 'street', 'aliases': [], 'lat': 14.5236, 'lng': 121.0129, 'source': 'barangay'}],
    'web_push_subscriptions': [{'id': 1, 'endpoint': 'https://fcm.googleapis.com/fcm/send/demo', 'label': 'Chrome on Windows', 'created_at': ago(3000), 'last_ok_at': ago(40)}],
    'place_kinds': [{'grp': g, 'label': l} for g, l in [('area', 'Area'), ('hall', 'Barangay hall'), ('shop', 'Shop'), ('street', 'Street')]],
    'dispatches': [], 'status_logs': [], 'sla_policies': [{'category': 'public_safety_infrastructure', 'hours': 24}],
}

RPC = {
  'search_places': [
    {'id': 1, 'name': 'Barangay 183 Hall', 'grp': 'hall', 'kind': None, 'lat': 14.525104, 'lng': 121.012596, 'metres': 0, 'branches': 1, 'source': 'barangay', 'info': {}},
    {'id': 2, 'name': 'Watsons', 'grp': 'shop', 'kind': 'chemist', 'lat': 14.5235, 'lng': 121.0151, 'metres': 310, 'branches': 4, 'source': 'osm', 'info': {'opening_hours': 'Mo-Su 08:00-21:00'}},
    {'id': 3, 'name': 'Air Force General Hospital', 'grp': 'health', 'kind': 'hospital', 'lat': 14.5161, 'lng': 121.0177, 'metres': 1150, 'branches': 1, 'source': 'osm', 'info': {}},
    {'id': 4, 'name': 'Sampaguita Street', 'grp': 'street', 'kind': 'street', 'lat': 14.5241, 'lng': 121.0118, 'metres': 140, 'branches': 1, 'source': 'osm', 'info': {}}],
    'place_save': 99, 'place_remove': None,
    'smart_summary': {'urgent_waiting': 3, 'high_waiting': 5, 'recurring': 4, 'recurring_open': 2},
    'smart_deadline_risk': [{'report_id': REPORTS[0]['id'], 'tracking_id': 'SS-2610-1001', 'risk': 'high', 'hours_left': 5, 'typical_hours': 18}],
    'smart_spikes': [{'category': 'animal_welfare', 'this_week': 6, 'usual': 0.5, 'times_usual': 12, 'place': 'Purok 3'},
                     {'category': 'environmental_waste_hazard', 'this_week': 9, 'usual': 3.0, 'times_usual': 3, 'place': 'Purok 1'}],
    'smart_sla_scorecard': [{'category': c, 'finished': 10, 'on_time': 8, 'on_time_pct': 80 - i * 4, 'last_month_pct': 75, 'change_pct': 5 - i * 2, 'overdue_now': i % 3} for i, c in enumerate(CATS)],
    'smart_stuck_cases': [{'report_id': 'x', 'tracking_id': 'SS-2610-1005', 'days_quiet': 4}] * 2,
    'smart_queue': [{'report_id': REPORTS[i]['id'], 'tracking_id': REPORTS[i]['tracking_id'], 'subject': REPORTS[i]['subject'], 'stage': ['review', 'dispatch', 'accept', 'follow_up'][i % 4],
                     'level': ['urgent', 'high', 'normal'][i % 3], 'score': 90 - i * 5, 'why': 'Wire down near a school', 'waiting_minutes': 40 + i * 30, 'category': REPORTS[i]['category']} for i in range(8)],
    'smart_case_card': {'level': 'urgent', 'score': 82, 'override_level': None, 'computed_level': 'urgent',
                        'reasons': [{'factor': 'kind', 'detail': 'Public safety', 'points': 35}, {'factor': 'words', 'detail': 'live wire', 'points': 25}, {'factor': 'hazard', 'detail': 'Flood zone 2', 'points': 10}, {'factor': 'neighbours', 'detail': '3 others reported it', 'points': 12}],
                        'duplicates': [], 'eta': {'minutes': 14, 'tanod': 'Bautista, Jose'}, 'risk': {'risk': 'high', 'hours_left': 5, 'typical_hours': 18}},
    'smart_tanod_ranking': [{'tanod_id': 'b0000000-0000-0000-0000-000000000002', 'full_name': 'Mendoza, Liza', 'score': 91, 'metres': 180, 'active_jobs': 0, 'closed_nearby': 3, 'location_fresh': True, 'reasons': []},
                            {'tanod_id': 'b0000000-0000-0000-0000-000000000001', 'full_name': 'Bautista, Jose', 'score': 74, 'metres': 420, 'active_jobs': 1, 'closed_nearby': 1, 'location_fresh': True, 'reasons': []},
                            {'tanod_id': 'b0000000-0000-0000-0000-000000000003', 'full_name': 'Cruz, Ben', 'score': 55, 'metres': 900, 'active_jobs': 2, 'closed_nearby': 0, 'location_fresh': False, 'reasons': []}],
    'tanod_roster': [{'tanod_id': 'b0000000-0000-0000-0000-00000000000%d' % i, 'full_name': n, 'assignable': True, 'location_fresh': f, 'metres': m, 'unavailable_why': None}
                     for i, n, f, m in [(1, 'Bautista, Jose', True, 420), (2, 'Mendoza, Liza', True, 180), (3, 'Cruz, Ben', False, 900)]],
    'smart_calibration': [{'level': l, 'reports': 20 + i * 5, 'raised': i, 'lowered': 2 + i, 'median_minutes_to_dispatch': 25 + i * 11, 'median_hours_to_resolve': 12} for i, l in enumerate(['urgent', 'high', 'normal', 'low'])],
    'smart_factor_stats': [{'factor': 'words', 'detail': 'fight', 'reports': 14, 'raised': 1, 'lowered': 6}, {'factor': 'neighbours', 'detail': '', 'reports': 22, 'raised': 2, 'lowered': 3}],
    'smart_digest_preview': 'Good morning. 3 urgent cases wait for a tanod. 2 may miss their deadline. Animal welfare is up 12 times the usual in Purok 3.',
    'smart_patterns': [{'pattern_key': 'p1', 'category': 'environmental_waste_hazard', 'lat': 14.5, 'lng': 121.0, 'reports': 6, 'weeks': 4, 'residents': 5, 'still_open': 2, 'hazard': 'Flood zone 2', 'tracking_ids': ['SS-2610-1003', 'SS-2610-1011', 'SS-2610-1015']}],
    'dashboard_metrics': {'daily': [{'d': f'2026-10-{i:02d}', 'n': (i * 3) % 7 + 1} for i in range(1, 15)], 'efficiency': [], 'resolution_status': {'done': 30, 'overdue': 4, 'late': 3, 'processing': 12, 'rejected': 2},
                          'categories': [{'category': c, 'n': 5 + i} for i, c in enumerate(CATS)], 'tiles': {'resolved': 30, 'escalated': 6, 'overdue': 4}, 'total': 51},
    'account_directory': [
  {'id':'u1','full_name':'Besarra, Rose','email':'person0@example.test','mobile_number':'+639170000001','verification_status':'pending','is_suspended':False,'suspended_reason':None,'is_overdue':True,'minutes_left':None,'avatar_url':None,'duty_status':None,'holding_incident':False,'is_retired':False,'role':'resident'},
  {'id':'u2','full_name':'Lediac, Ace','email':None,'mobile_number':'+639170000002','verification_status':'verified','is_suspended':False,'suspended_reason':None,'is_overdue':False,'minutes_left':None,'avatar_url':None,'duty_status':'on_duty','holding_incident':False,'is_retired':False,'role':'resident'},
  {'id':'u3','full_name':'Arcibal, Kim Justine','email':None,'mobile_number':'+639170000003','verification_status':'verified','is_suspended':False,'suspended_reason':None,'is_overdue':False,'minutes_left':None,'avatar_url':None,'duty_status':'offline','holding_incident':False,'is_retired':False,'role':'resident'},
  {'id':'u4','full_name':'Deleted Resident','email':'deleted+f3f2193fe8ba406ca910b5635eba2b5e@smartsumbong.invalid','mobile_number':'deleted-f3f2193fe8','verification_status':'verified','is_suspended':True,'suspended_reason':'Account deleted by the resident','is_overdue':False,'minutes_left':None,'avatar_url':None,'duty_status':None,'holding_incident':False,'is_retired':False,'role':'resident'},
  {'id':'u5','full_name':'Martin, Jericho Troy','email':'person4@example.test','mobile_number':'+639170000004','verification_status':'verified','is_suspended':False,'suspended_reason':None,'is_overdue':False,'minutes_left':None,'avatar_url':None,'duty_status':'lunch','holding_incident':True,'is_retired':False,'role':'resident'},
  {'id':'u6','full_name':'Martin, Jericho Troy','email':'person6@example.test','mobile_number':'+639170000000','verification_status':'verified','is_suspended':False,'suspended_reason':None,'is_overdue':False,'minutes_left':None,'avatar_url':None,'duty_status':None,'holding_incident':False,'is_retired':False,'role':'resident'}
], 'portal_uptime_summary': None,
}


def apply_filters(rows, qs):
    out = rows
    for k, vs in qs.items():
        if k in ('select', 'order', 'limit', 'offset'): continue
        v = vs[0]
        if v.startswith('eq.'):
            want = v[3:]
            if any(k in r for r in out): out = [r for r in out if str(r.get(k)) == want]
    return out


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send(self, code, body, extra=None):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*'); self.send_header('Access-Control-Allow-Headers', '*'); self.send_header('Access-Control-Allow-Methods', '*'); self.send_header('Access-Control-Expose-Headers', '*')
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers(); self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(204); self.send_header('Access-Control-Allow-Origin', '*'); self.send_header('Access-Control-Allow-Headers', '*'); self.send_header('Access-Control-Allow-Methods', '*'); self.send_header('Content-Length', '0'); self.end_headers()
    def do_GET(self): self.route('GET')
    def do_POST(self): self.route('POST')
    def do_PATCH(self): self.route('PATCH')
    def do_PUT(self): self.route('PUT')

    def route(self, m):
        u = urlparse(self.path); qs = parse_qs(u.query)
        n = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(n) if n else b''
        if u.path.startswith('/auth/v1/'):
            if 'token' in u.path:
                return self.send(200, {'access_token': 'fake', 'refresh_token': 'fake', 'expires_in': 3600, 'user': {'id': ADMIN['id']}})
            return self.send(200, {'id': ADMIN['id'], 'email': ADMIN['email'], 'last_sign_in_at': ago(1)})
        if u.path.startswith('/rest/v1/rpc/'):
            fn = u.path.split('/')[-1]
            if fn in RPC: return self.send(200, RPC[fn])
            print('RPC missing', fn, file=sys.stderr, flush=True)
            return self.send(200, [])
        if u.path.startswith('/rest/v1/'):
            t = u.path.split('/')[-1]
            rows = TABLES.get(t)
            if rows is None:
                print('TABLE missing', t, file=sys.stderr, flush=True); rows = []
            if m != 'GET': return self.send(200, rows[:1])
            rows = apply_filters(rows, qs)
            total = len(rows)
            extra = {}
            rng = self.headers.get('Range')
            if 'count=exact' in (self.headers.get('Prefer') or ''):
                extra['Content-Range'] = f'0-0/{total}'
            lim = qs.get('limit'); off = int(qs.get('offset', ['0'])[0])
            rows = rows[off:]
            if lim: rows = rows[:int(lim[0])]
            return self.send(200, rows, extra)
        self.send(404, {'message': 'nope'})


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 54399), H).serve_forever()
