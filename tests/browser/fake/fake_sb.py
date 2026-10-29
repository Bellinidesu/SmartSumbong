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
         'location_text': 'Purok 2, Barangay 183', 'version': 1, 'reporter': {'full_name': 'Garcia, Juan', 'mobile_number': '09171234567'}, 'resident': {'id': 'd0000000-0000-0000-0000-000000000001', 'full_name': 'Garcia, Juan'},
         'triage': {'score': 80 - i * 6, 'effective_level': ['urgent', 'high', 'normal', 'low'][i % 4], 'override_level': None, 'possible_duplicates': []}}
    r.update(kw); return r

REPORTS = [report(i) for i in range(1, 20)]
for r in REPORTS:
    if r['handler_id']: r['handler'] = {'id': ADMIN['id'], 'full_name': ADMIN['full_name'], 'official_role': 'secretary', 'committee': None}
REPORTS[0].update(is_anonymous=True, status='validated', tier=1, handler_id=KAG['id'], handler={'id': KAG['id'], 'full_name': KAG['full_name'], 'official_role': 'kagawad', 'committee': 'peace_order'}, subject='Live wire sparking near the school', is_sensitive=False)
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
    'command_state': [{'id': 1, 'auto_switch': False}],
    'command_display_links': [{'id': 'd0000000-0000-0000-0000-000000000001', 'label': 'Hall TV', 'created_at': ago(2880), 'revoked_at': None, 'last_seen_at': ago(1)},
                              {'id': 'd0000000-0000-0000-0000-000000000002', 'label': 'Old tablet', 'created_at': ago(9000), 'revoked_at': ago(4000), 'last_seen_at': ago(4100)}],
    'command_sessions': [{'id': 'c0000000-0000-0000-0000-000000000009', 'mode': 'flood', 'how': 'suggested', 'reason': '3 reports in the last 3 hours mention flood water, from 3 residents.',
                          'started_at': ago(1500), 'ended_at': ago(1320), 'end_note': 'Humupa na ang baha; sarado na ang evacuation center', 'starter': {'full_name': 'Reyes, Marites'}}],
    'smart_work_orders': [{'id': 'f0000000-0000-0000-0000-000000000001', 'pattern_key': 'zzz', 'title': 'Replace the drain on 13th Street', 'category': 'environmental_waste_hazard', 'status': 'planned', 'note': None, 'evidence': {'reports': 5, 'tracking_ids': ['SS-2610-1003', 'SS-2610-1011']}, 'created_at': ago(30)}],
    'places': [{'id': 1, 'name': 'Barangay 183 Hall', 'grp': 'hall', 'aliases': ['brgy hall'], 'lat': 14.525104, 'lng': 121.012596, 'source': 'barangay'},
               {'id': 2, 'name': 'Harvard Street', 'grp': 'street', 'aliases': [], 'lat': 14.5236, 'lng': 121.0129, 'source': 'barangay'}],
    'web_push_subscriptions': [{'id': 1, 'endpoint': 'https://fcm.googleapis.com/fcm/send/demo', 'label': 'Chrome on Windows', 'created_at': ago(3000), 'last_ok_at': ago(40)}],
    'place_kinds': [{'grp': g, 'label': l} for g, l in [('area', 'Area'), ('hall', 'Barangay hall'), ('shop', 'Shop'), ('street', 'Street')]],
    'dispatches': [], 'status_logs': [], 'sla_policies': [{'category': 'public_safety_infrastructure', 'hours': 24}],
}

# The command center (0143): a small memory of which mode is on, so a test can turn one on, hand over and turn it off.
CMD = {'active': None}
FEAT = {'workspace': True, 'command_center': True}   # 0144: the real database ships both off; the tests flip them with /__feat
CMD_MODES = [{'mode': 'fire', 'en': 'Fire Surroundings', 'fil': 'Paligid ng Sunog'}, {'mode': 'quake', 'en': 'Quake Check', 'fil': 'Suri sa Lindol'},
             {'mode': 'flood', 'en': 'Flood Watch', 'fil': 'Bantay-baha'}, {'mode': 'typhoon', 'en': 'Typhoon Board', 'fil': 'Pisara ng Bagyo'}]


def _cmd_square(lat, lng, d=0.00045):
    return {'type': 'Polygon', 'coordinates': [[[lng - d, lat - d], [lng + d, lat - d], [lng + d, lat + d], [lng - d, lat + d], [lng - d, lat - d]]]}


def _cmd_board(p):
    a = CMD['active']
    out = {'as_of': ago(0), 'auto_switch': False, 'modes': CMD_MODES,
           'active': None if not a else {'id': 'c0000000-0000-0000-0000-000000000001', 'mode': a, 'how': 'admin', 'reason': 'Malakas ang ulan',
                                          'started_at': ago(40), 'started_by': 'Reyes, Marites', 'en': next(m['en'] for m in CMD_MODES if m['mode'] == a),
                                          'fil': next(m['fil'] for m in CMD_MODES if m['mode'] == a)},
           'suggestion': None if a == 'flood' else {'mode': 'flood', 'name_en': 'Flood Watch', 'name_fil': 'Bantay-baha', 'reports': 3, 'residents': 3, 'hours': 3,
                                                    'why_en': '3 reports in the last 3 hours mention flood water, from 3 residents.',
                                                    'why_fil': '3 ulat sa nakaraang 3 oras ang bumanggit ng baha, mula sa 3 residente.'}}
    mode = p.get('p_mode') or a
    if not mode:
        return out
    m = next(x for x in CMD_MODES if x['mode'] == mode)
    out.update({'mode': mode, 'en': m['en'], 'fil': m['fil'], 'live': a == mode, 'since': ago(160), 'window_hours': 24, 'cell_metres': 100,
                'counts': {'reports': 3, 'residents': 3, 'open': 2, 'resolved': 1, 'dispatched': 1, 'last_at': ago(12)},
                'tanods': {'on_duty': 4, 'located': 3},
                'checklist': [{'key': 'pagasa', 'en': 'PAGASA rainfall advisory read', 'fil': 'Nabasa ang rainfall advisory ng PAGASA', 'done': a == mode, 'note': None, 'at': ago(20), 'by': 'Reyes, Marites'},
                              {'key': 'evac', 'en': 'Evacuation center opened', 'fil': 'Nabuksan ang evacuation center', 'done': False, 'note': None, 'at': None, 'by': None}],
                'handover': {'at': ago(15), 'note': 'Bukas ang covered court; tatlong kalye ang may baha', 'by': 'Reyes, Marites'} if a == mode else None,
                'reports': []})
    if mode == 'flood':
        out['tags'] = [{'tag': 'waist', 'rank': 6, 'en': 'waist-deep (about 37 in)', 'fil': 'hanggang baywang (mga 37 pulgada)', 'reports': 1, 'last_at': ago(12)},
                       {'tag': 'knee', 'rank': 4, 'en': 'knee-deep (about 19 in)', 'fil': 'hanggang tuhod (mga 19 pulgada)', 'reports': 2, 'last_at': ago(30)}]
        out['cells'] = [{'key': '100:1', 'outline': _cmd_square(14.5194, 121.0122), 'lat': 14.5194, 'lng': 121.0122, 'reports': 1, 'open': 1, 'tag': 'waist', 'rank': 6,
                         'tag_en': 'waist-deep (about 37 in)', 'tag_fil': 'hanggang baywang (mga 37 pulgada)', 'last_at': ago(12), 'tracking_ids': ['SS-2610-1021'], 'noah': 3, 'surge': None},
                        {'key': '100:2', 'outline': _cmd_square(14.5203, 121.0131), 'lat': 14.5203, 'lng': 121.0131, 'reports': 2, 'open': 1, 'tag': 'knee', 'rank': 4,
                         'tag_en': 'knee-deep (about 19 in)', 'tag_fil': 'hanggang tuhod (mga 19 pulgada)', 'last_at': ago(30), 'tracking_ids': ['SS-2610-1019', 'SS-2610-1020'], 'noah': 2, 'surge': None}]
    elif mode == 'fire':
        out['tags'] = [{'tag': 'people_inside', 'rank': 4, 'en': 'people inside', 'fil': 'may tao sa loob', 'reports': 1, 'last_at': ago(8)}]
        out['sites'] = [{'lat': 14.5194, 'lng': 121.0122, 'reports': 2, 'first_at': ago(14), 'last_at': ago(8), 'tag': 'people_inside', 'tag_en': 'people inside', 'tag_fil': 'may tao sa loob',
                         'tracking_ids': ['SS-2610-1030', 'SS-2610-1031'],
                         'rings': [{'metres': 50, 'places': 1, 'other_reports': 0, 'named': [{'id': 1, 'name': 'Gasolinahan sa Kanto', 'kind': 'fuel', 'metres': 40}]},
                                   {'metres': 100, 'places': 0, 'other_reports': 1, 'named': []},
                                   {'metres': 200, 'places': 1, 'other_reports': 0, 'named': [{'id': 2, 'name': 'Paaralang Elementarya ng 183', 'kind': 'school', 'metres': 150}]}],
                         'fire_station': {'name': 'Pasay Fire Station', 'metres': 1450},
                         'tanods': [{'name': 'Bautista, Jose', 'metres': 300, 'as_of': ago(3)}]}]
    elif mode == 'quake':
        out['tags'] = [{'tag': 'crack', 'rank': 1, 'en': 'cracks', 'fil': 'bitak', 'reports': 2, 'last_at': ago(10)}]
        out['cells'] = []
        out['places'] = [{'id': 2, 'name': 'Paaralang Elementarya ng 183', 'kind': 'school', 'lat': 14.5206, 'lng': 121.0122, 'status': None, 'note': None, 'at': None, 'by': None, 'reports_near': 1}]
    else:
        out['tags'] = []; out['cells'] = []; out['storm'] = {'on': False, 'until': None, 'reason': None}; out['signal'] = None
    return out


def _cmd_start(p):
    CMD['active'] = p.get('p_mode'); return 'c0000000-0000-0000-0000-000000000001'


def _cmd_end(p):
    CMD['active'] = None; return None


RPC = {
    'command_hall': lambda p: None if (p.get('p_token') != 'f' * 48 or not FEAT['command_center']) else {
        'as_of': ago(0), 'barangay': 'Barangay 183, Zone 20', 'today': {'filed': 7, 'resolved': 3, 'open': 19}, 'tanods_on_duty': 4,
        'mode': {'mode': 'flood', 'en': 'Flood Watch', 'fil': 'Bantay-baha', 'since': ago(40), 'reports': 3, 'open': 2, 'resolved': 1,
                 'tags': [{'en': 'waist-deep (about 37 in)', 'fil': 'hanggang baywang (mga 37 pulgada)', 'reports': 1}, {'en': 'knee-deep (about 19 in)', 'fil': 'hanggang tuhod (mga 19 pulgada)', 'reports': 2}],
                 'checklist_done': 2, 'checklist_total': 5}},
    'command_board': _cmd_board, 'command_start': _cmd_start, 'command_end': _cmd_end, 'command_handover': 1, 'command_check': None,
    'command_place_check': None, 'command_dismiss': None, 'command_suggest': None,
    'command_feed': [{'at': ago(5), 'kind': 'filed', 'report_id': 'x', 'tracking_id': 'SS-2610-1021', 'subject': 'Bumabaha na', 'place': 'Kalye Uno'},
                     {'at': ago(9), 'kind': 'check', 'item': 'pagasa', 'done': True, 'en': 'PAGASA rainfall advisory read', 'fil': 'Nabasa ang rainfall advisory ng PAGASA', 'by': 'Reyes, Marites'},
                     {'at': ago(20), 'kind': 'smart', 'event': 'command_on', 'summary': 'Flood Watch on (Reyes, Marites): Malakas ang ulan', 'report_id': None}],
  'search_places': [
    {'id': 1, 'name': 'Barangay 183 Hall', 'grp': 'hall', 'kind': None, 'lat': 14.525104, 'lng': 121.012596, 'metres': 0, 'branches': 1, 'source': 'barangay', 'info': {}},
    {'id': 2, 'name': 'Watsons', 'grp': 'shop', 'kind': 'chemist', 'lat': 14.5235, 'lng': 121.0151, 'metres': 310, 'branches': 4, 'source': 'osm', 'info': {'opening_hours': 'Mo-Su 08:00-21:00'}},
    {'id': 3, 'name': 'Air Force General Hospital', 'grp': 'health', 'kind': 'hospital', 'lat': 14.5161, 'lng': 121.0177, 'metres': 1150, 'branches': 1, 'source': 'osm', 'info': {}},
    {'id': 4, 'name': 'Sampaguita Street', 'grp': 'street', 'kind': 'street', 'lat': 14.5241, 'lng': 121.0118, 'metres': 140, 'branches': 1, 'source': 'osm', 'info': {}}],
    'place_save': 99, 'place_remove': None,
    'smart_engine_health': {'watch_last_at': ago(0.05), 'watch_last_ok': True, 'watch_failures_24h': 0, 'open_reports': 19, 'unscored': 0, 'last_scored_at': ago(3), 'events_24h': 12, 'routing_on': True, 'queue_on': True},
    'smart_pick_stats': {'days': 90, 'dispatches': 16, 'ranked': 9, 'top_pick': 6, 'top_three': 9, 'top_pick_pct': 66.7},
    'smart_fix_stats': {'days': 90, 'asked': 12, 'answered': 8, 'fixed': 6, 'not_fixed': 2, 'waiting_for_barangay': 1, 'by_kind': []},

    'smart_rule_history': [
        {'version': 3, 'at': ago(2), 'reason': 'Flood reports rated too low in the storm season', 'by': 'Reyes, Marites', 'changed': ['urgent_from'], 'words': 56, 'current': True},
        {'version': 2, 'at': ago(300), 'reason': 'Word list changed', 'by': 'Reyes, Marites', 'changed': ['word list'], 'words': 56, 'current': False},
        {'version': 1, 'at': ago(900), 'reason': 'The rules as they were when versions began (0141)', 'by': None, 'changed': [], 'words': 55, 'current': False}],
    'smart_replay': {'days': 90, 'reports': 15, 'moved': 2, 'transitions': [{'from': 'normal', 'to': 'high', 'reports': 2}, {'from': 'low', 'to': 'low', 'reports': 13}],
                     'changed': [{'tracking_id': 'SS-2610-1004', 'subject': 'Clogged canal', 'score_before': 40, 'score_after': 47, 'level_before': 'normal', 'level_after': 'high'}]},
    'smart_save_rules': 4, 'smart_rollback': 4,
    'smart_roster_suggestion': {'days': 90, 'weeks': 10.7, 'blocks': [
        {'dow': 3, 'block': 4, 'from_hour': 12, 'reports': 9, 'expected': 0.8, 'suggested': 1, 'usual': 0.0, 'gap': 1.0},
        {'dow': 6, 'block': 7, 'from_hour': 21, 'reports': 6, 'expected': 0.6, 'suggested': 1, 'usual': 2.0, 'gap': -1.0}]},
    'smart_forecast': {'days': 28, 'open_now': 19, 'arrive_per_day': 1.3, 'close_per_day': 0.9, 'open_in_7_days': 22,
                       'this_week': [{'category': 'barangay_service', 'expected': 3.5}, {'category': 'street_obstruction', 'expected': 2.1}],
                       'history_days': 75, 'seasonal_ready': False, 'seasonal': None},
    'smart_fairness': {'days': 14, 'dispatches': 10, 'tanods': [
        {'tanod_id': 'b0000000-0000-0000-0000-000000000001', 'name': 'Bautista, Jose', 'assigned': 6, 'share_pct': 60, 'resolved': 5, 'median_accept_minutes': 6.0},
        {'tanod_id': 'b0000000-0000-0000-0000-000000000002', 'name': 'Mendoza, Liza', 'assigned': 4, 'share_pct': 40, 'resolved': 4, 'median_accept_minutes': 4.5}],
        'tanod_note': 'one_tanod_most',
        'admins': [{'admin_id': 'x', 'name': 'Reyes, Marites', 'open': 8, 'share_pct': 80}, {'admin_id': 'y', 'name': 'Santos, Ben', 'open': 2, 'share_pct': 20}], 'admin_note': 'one_admin_most'},
    'smart_workorder_create': 'f0000000-0000-0000-0000-000000000001', 'smart_workorder_set': None,
    'smart_summary': {'urgent_waiting': 3, 'high_waiting': 5, 'recurring': 4, 'recurring_open': 2},
    'smart_deadline_risk': [{'report_id': REPORTS[0]['id'], 'tracking_id': 'SS-2610-1001', 'risk': 'high', 'hours_left': 5, 'typical_hours': 18}],
    'smart_spikes': [{'category': 'animal_welfare', 'this_week': 6, 'usual': 0.5, 'times_usual': 12, 'place': 'Purok 3'},
                     {'category': 'environmental_waste_hazard', 'this_week': 9, 'usual': 3.0, 'times_usual': 3, 'place': 'Purok 1'}],
    'smart_sla_scorecard': [{'category': c, 'finished': 10, 'on_time': 8, 'on_time_pct': 80 - i * 4, 'last_month_pct': 75, 'change_pct': 5 - i * 2, 'overdue_now': i % 3} for i, c in enumerate(CATS)],
    'smart_stuck_cases': [{'report_id': 'x', 'tracking_id': 'SS-2610-1005', 'days_quiet': 4}] * 2,
    'smart_queue': [{'report_id': REPORTS[i]['id'], 'tracking_id': REPORTS[i]['tracking_id'], 'subject': REPORTS[i]['subject'], 'stage': ['review', 'dispatch', 'accept', 'follow_up', 'recheck'][i % 5],
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
], 'portal_uptime_summary': {'day_checks': 144, 'day_ok': 144, 'week_checks': 1008, 'week_ok': 1006, 'last_at': ago(0.1), 'last_ok': True, 'mem_now': 138, 'mem_limit': 512, 'mem_week_avg': 131, 'mem_week_max': 204, 'mem_samples': 1008}, 'engine_status': {'configured': True, 'waiting': 1, 'failed_week': 0, 'read_week': 6, 'last_read_at': ago(2)},
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
        if u.path == '/__feat':   # ?ws=0&cc=0
            FEAT['workspace'] = qs.get('ws', ['1'])[0] == '1'; FEAT['command_center'] = qs.get('cc', ['1'])[0] == '1'
            return self.send(200, {})
        if u.path == '/__cmd_reset':   # the command-center test starts with nothing on
            CMD['active'] = None; return self.send(200, {})
        if u.path.startswith('/auth/v1/'):
            if 'token' in u.path:
                return self.send(200, {'access_token': 'fake', 'refresh_token': 'fake', 'expires_in': 3600, 'user': {'id': ADMIN['id']}})
            return self.send(200, {'id': ADMIN['id'], 'email': ADMIN['email'], 'last_sign_in_at': ago(1)})
        if u.path.startswith('/rest/v1/rpc/'):
            fn = u.path.split('/')[-1]
            if fn in RPC:
                v = RPC[fn]
                return self.send(200, v(json.loads(body or b'{}')) if callable(v) else v)
            print('RPC missing', fn, file=sys.stderr, flush=True)
            return self.send(200, [])
        if u.path.startswith('/rest/v1/'):
            t = u.path.split('/')[-1]
            rows = TABLES.get(t)
            if t == 'feature_switches': rows = [{'key': k, 'enabled': v} for k, v in FEAT.items()]
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
