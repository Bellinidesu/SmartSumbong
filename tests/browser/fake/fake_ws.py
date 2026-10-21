"""The fake Supabase from fake_sb.py plus fixtures for the Workspace widgets (0132)."""
import datetime as dt, random
import fake_sb as F
from fake_sb import ago, ahead, REPORTS, ADMIN, CHAIR, KAG, CATS, RPC, TABLES

random.seed(7)
for i, r in enumerate(REPORTS):
    r['latitude'] = 14.5194 + random.uniform(-.006, .006)
    r['longitude'] = 121.0122 + random.uniform(-.008, .008)
    r['report_triage'] = {'effective_level': r['triage']['effective_level']}
    r['location_label'] = ['Rizal Ext.', '9th St.', 'Libertad Market', 'Andrews Ave.'][i % 4]
    if i % 3: r['handler'] = {'full_name': 'Reyes, Marites'}

today = dt.date.today()
d = lambda n: (today + dt.timedelta(days=n)).isoformat()

RPC.update({
    'smart_word_suggestions': [
        {'word': 'nagliliyab', 'reports': 4, 'mostly_category': 'public_safety_infrastructure', 'share': 1.0, 'likely_spelling_of': None, 'example': 'Nagliliyab ang poste sa tapat ng paaralan'},
        {'word': 'basuraa', 'reports': 3, 'mostly_category': 'environmental_waste_hazard', 'share': 0.67, 'likely_spelling_of': 'basura', 'example': 'Basuraa na naipon sa kanto'}],
    'smart_time_patterns': [
        {'category': 'peace_order_nuisance', 'weekday': 'Saturday', 'hours': '21:00-00:00', 'reports': 8, 'times_usual': 8.4, 'place': 'Purok 2'},
        {'category': 'animal_welfare', 'weekday': 'Monday', 'hours': '06:00-09:00', 'reports': 6, 'times_usual': 5.1, 'place': 'Purok 3'}],
    'smart_teach_word': None,

    '_ws_is_lead': True,
    'workspace_risk': [{'report_id': REPORTS[i]['id'], 'tracking_id': REPORTS[i]['tracking_id'], 'subject': REPORTS[i]['subject'], 'sensitive': i == 1,
                        'category': REPORTS[i]['category'], 'place': REPORTS[i]['location_label'], 'lat': REPORTS[i]['latitude'], 'lng': REPORTS[i]['longitude'],
                        'hazard': 'flood' if i % 3 else 'surge', 'level': [3, 2, 1][i % 3]} for i in range(5)],
    'workspace_numbers': {
        'status': {'waiting': 5, 'in_progress': 4, 'resolved': 6, 'rejected': 1},
        'by_category': [{'category': c, 'n': n} for c, n in zip(CATS[:6], [5, 4, 3, 2, 1, 1])],
        'per_day': [{'d': d(-29 + i), 'n': (i * 7) % 6 + (2 if i > 20 else 0)} for i in range(30)],
        'per_hour': [0, 0, 1, 0, 1, 2, 4, 6, 8, 7, 5, 4, 3, 3, 2, 4, 5, 6, 8, 6, 3, 2, 1, 1],
        'pace': {'days': [{'d': d(-6 + i), 'hours': None if i == 1 else round(1 + (i * 1.7) % 5, 1)} for i in range(7)], 'avg_hours': 2.4, 'fastest_minutes': 12, 'slowest_hours': 31.5, 'still_waiting': 3},
        'month': {'received': 17, 'resolved': 7, 'resolved_pct': 41, 'avg_hours': 22.4, 'overdue': 2, 'escalated': 3, 'last_received': 14, 'last_resolved_pct': 75},
        'resolved_today': [{'report_id': REPORTS[2]['id'], 'tracking_id': 'SS-2610-1003', 'subject': 'Stray dog removed', 'sensitive': False, 'at': ago(2), 'by': 'Arcibal Kim'},
                           {'report_id': REPORTS[3]['id'], 'tracking_id': 'SS-2610-1004', 'subject': 'Noise complaint settled', 'sensitive': False, 'at': ago(5), 'by': 'Marites Reyes'}],
        'streets': [{'place': 'Rizal Ext.', 'open': 4, 'category': 'street_obstruction'}, {'place': '9th St.', 'open': 3, 'category': 'peace_order_nuisance'}, {'place': 'Libertad Market', 'open': 2, 'category': 'environmental_waste_hazard'}],
        'escalations': [{'report_id': REPORTS[0]['id'], 'tracking_id': 'SS-2610-1001', 'subject': 'Live wire sparking near the school', 'sensitive': False, 'tier': 2, 'to': 'Kagawad (Peace and Order)', 'at': ago(3)},
                        {'report_id': REPORTS[1]['id'], 'tracking_id': 'SS-2610-1002', 'subject': 'Husband hits wife', 'sensitive': True, 'tier': 1, 'to': None, 'at': ago(9)}],
        'escalation_requests': 1},
    'workspace_team': {
        'tanods': [{'id': 'b0000000-0000-0000-0000-000000000001', 'name': 'Bautista, Jose', 'duty': 'on_duty', 'since': ago(3), 'jobs': 1, 'first_on': ago(3), 'rostered_hour': 6, 'late_minutes': 12, 'hours_week': 21.5},
                   {'id': 'b0000000-0000-0000-0000-000000000002', 'name': 'Mendoza, Liza', 'duty': 'on_duty', 'since': ago(2), 'jobs': 0, 'first_on': ago(2), 'rostered_hour': 6, 'late_minutes': 0, 'hours_week': 30},
                   {'id': 'b0000000-0000-0000-0000-000000000003', 'name': 'Cruz, Ben', 'duty': 'break', 'since': ago(1), 'jobs': 0, 'first_on': ago(6), 'rostered_hour': None, 'late_minutes': None, 'hours_week': 12.2},
                   {'id': 'b0000000-0000-0000-0000-000000000004', 'name': 'Barretto, Martin', 'duty': 'offline', 'since': ago(20), 'jobs': 0, 'first_on': None, 'rostered_hour': None, 'late_minutes': None, 'hours_week': 4}],
        'roster': [{'id': f'r{i}{s}', 'date': d(i), 'shift': s, 'user_id': 'x', 'name': n, 'role': 'tanod'} for i in range(0, 5) for s, n in [('morning', 'Cruz, Ben'), ('night', 'Mendoza, Liza')]],
        'shift_starts': [6, 14, 22],
        'leave': [{'id': 'l1', 'user_id': 'x', 'name': 'Barretto, Martin', 'from': d(-1), 'to': d(2), 'reason': 'Family', 'now': True}],
        'credentials': [{'id': 'c1', 'user_id': 'x', 'name': 'Cruz, Ben', 'kind': 'first_aid', 'label': 'Red Cross first aid', 'expires_on': d(21), 'days_left': 21},
                        {'id': 'c2', 'user_id': 'x', 'name': 'Mendoza, Liza', 'kind': 'tanod_id', 'label': 'Tanod ID', 'expires_on': d(400), 'days_left': 400}],
        'birthdays': [{'user_id': 'x', 'name': 'Reyes, Marites', 'on': d(3), 'in_days': 3}],
        'directory': [{'id': CHAIR['id'], 'name': CHAIR['full_name'], 'role': 'admin', 'position': 'chairman', 'committee': None, 'mobile': '0917 000 0000', 'duty': None},
                      {'id': KAG['id'], 'name': KAG['full_name'], 'role': 'admin', 'position': 'kagawad', 'committee': 'peace_order', 'mobile': '0917 000 0000', 'duty': None},
                      {'id': ADMIN['id'], 'name': ADMIN['full_name'], 'role': 'admin', 'position': 'secretary', 'committee': None, 'mobile': '0917 000 0000', 'duty': None},
                      {'id': 'b0000000-0000-0000-0000-000000000001', 'name': 'Bautista, Jose', 'role': 'tanod', 'position': None, 'committee': None, 'mobile': '0917 000 0000', 'duty': 'on_duty'}],
        'waiting': {'residents': 3, 'residents_oldest': ago(60), 'profile_requests': 1, 'retirements': 0, 'escalations': 1}},
    'workspace_activity': [{'kind': 'new', 'at': ago(0.2), 'report_id': REPORTS[4]['id'], 'tracking_id': 'SS-2610-1005', 'subject': 'Vendors on the sidewalk', 'sensitive': False, 'category': 'street_obstruction', 'place': 'Rizal Ext.'},
                           {'kind': 'dispatch', 'at': ago(0.5), 'report_id': REPORTS[0]['id'], 'tracking_id': 'SS-2610-1001', 'subject': 'Live wire sparking near the school', 'sensitive': False, 'tanod': 'Mendoza Liza', 'by': 'Marites Reyes'},
                           {'kind': 'status', 'at': ago(1), 'report_id': REPORTS[2]['id'], 'tracking_id': 'SS-2610-1003', 'subject': 'Clogged canal', 'sensitive': False, 'status': 'resolved', 'by': 'Arcibal Kim'},
                           {'kind': 'handler_take', 'at': ago(2), 'report_id': REPORTS[1]['id'], 'tracking_id': 'SS-2610-1002', 'subject': 'x', 'sensitive': True, 'by': 'Elena Santos'}],
    'workspace_photos': [{'url': 'data:image/svg+xml;utf8,' + f"<svg xmlns='http://www.w3.org/2000/svg' width='320' height='240'><rect width='320' height='240' fill='{c}'/></svg>", 'at': ago(i), 'from': f, 'report_id': REPORTS[i]['id'], 'tracking_id': REPORTS[i]['tracking_id']}
                         for i, (c, f) in enumerate([('%238FA8C8', 'resident'), ('%23C9A27E', 'tanod'), ('%239DBF9A', 'staff'), ('%23B7A0C8', 'resident')])],
    'workspace_alarm_db': {'urgent2h': [], 'deadline': [{'report_id': REPORTS[0]['id'], 'tracking_id': 'SS-2610-1001', 'hours_left': 5}], 'rules': ['red', 'sig3']},
    'shift_mood_totals': {'date': d(0), 'answered': 5, 'hidden': False, 'calm': 2, 'busy': 2, 'tired': 1},
})
TABLES.update({
    'workspace_prefs': [],
    'workspace_settings': [{'alarm_rules': ['red', 'sig3'], 'games_enabled': True, 'shift_starts': [6, 14, 22], 'fares': {'trike_base': 20, 'trike_base_km': 1, 'trike_per_km': 10, 'jeep_min': 13, 'jeep_min_km': 4, 'jeep_per_km': 2, 'special_trip': 120}, 'updated_at': ago(5)}],
    'team_posts': [{'id': 'p1', 'kind': 'notice', 'body': 'Typhoon prep meeting at the hall, 3 PM. Every tanod on duty must attend. Radios charged.', 'author_id': CHAIR['id'], 'pinned_until': ahead(8), 'created_at': ago(1), 'author': {'full_name': CHAIR['full_name'], 'official_role': 'chairman'}, 'team_post_reads': [{'user_id': 'a'}, {'user_id': 'b'}]},
                   {'id': 'p2', 'kind': 'board', 'body': 'Road on 9th St. is closed for the drainage works.', 'author_id': ADMIN['id'], 'pinned_until': None, 'created_at': ago(2), 'author': {'full_name': ADMIN['full_name'], 'official_role': 'secretary'}, 'team_post_reads': []},
                   {'id': 'p3', 'kind': 'handover', 'body': 'Videoke on 9th St. again; spoke to the owner twice. If it happens tonight it goes to the Kagawad.', 'author_id': ADMIN['id'], 'pinned_until': None, 'created_at': ago(9), 'author': {'full_name': 'Reyes, Marites', 'official_role': None}, 'team_post_reads': []}],
    'polls': [{'id': 'q1', 'question': 'Who can cover Saturday night?', 'options': ['Kim', 'Martin', 'Nobody yet'], 'created_by': ADMIN['id'], 'closes_at': ahead(20), 'closed_at': None, 'created_at': ago(3), 'author': {'full_name': 'Reyes, Marites'}, 'poll_votes': [{'user_id': 'a', 'choice': 0}, {'user_id': 'b', 'choice': 0}, {'user_id': 'c', 'choice': 2}]}],
    'patrol_checkpoints': [{'id': 'k1', 'name': 'Barangay hall', 'lat': 14.5194, 'lng': 121.0122, 'sort_order': 1}, {'id': 'k2', 'name': 'Libertad Market', 'lat': 14.52, 'lng': 121.01, 'sort_order': 2}, {'id': 'k3', 'name': 'Pasay Elementary School', 'lat': 14.521, 'lng': 121.015, 'sort_order': 3}],
    'checkpoint_scans': [{'id': 's1', 'checkpoint_id': 'k1', 'tanod_id': 'x', 'scanned_at': ago(3), 'tanod': {'full_name': 'Bautista, Jose'}}],
    'relief_tally': [{'id': 'f1', 'event': 'Typhoon Kristine', 'street': 'Rizal Ext.', 'packs': 120, 'given_on': d(-2), 'recorded_by': ADMIN['id']}, {'id': 'f2', 'event': 'Typhoon Kristine', 'street': '9th St.', 'packs': 85, 'given_on': d(-2), 'recorded_by': ADMIN['id']}, {'id': 'f3', 'event': 'Typhoon Kristine', 'street': 'Libertad', 'packs': 40, 'given_on': d(-1), 'recorded_by': ADMIN['id']}],
    'shift_checkins': [], 'game_scores': [{'user_id': ADMIN['id'], 'game': 'react', 'best': 268, 'plays': 3, 'updated_at': ago(2), 'user': {'full_name': 'Reyes, Marites'}}, {'user_id': 'b', 'game': 'react', 'best': 301, 'plays': 2, 'updated_at': ago(3), 'user': {'full_name': 'Cruz, Ben'}}, {'user_id': ADMIN['id'], 'game': 'snake', 'best': 120, 'plays': 5, 'updated_at': ago(3), 'user': {'full_name': 'Reyes, Marites'}}],
    'safe_point_notes': [],
    'hotline_groups': [{'id': 'g1', 'name': 'National Emergency', 'icon': None, 'sort_order': 1, 'parent_id': None, 'hotline_numbers': [{'label': 'Emergency', 'number': '911', 'carrier': None, 'sort_order': 1, 'is_active': True}, {'label': 'Fire Protection Pasay City', 'number': '(02) 8831 5555', 'carrier': None, 'sort_order': 2, 'is_active': True}]},
                       {'id': 'g2', 'name': 'Barangay 183 Hotline', 'icon': None, 'sort_order': 2, 'parent_id': None, 'hotline_numbers': [{'label': None, 'number': '0927 126 9625', 'carrier': 'Globe', 'sort_order': 1, 'is_active': True}]}],
    'profile_requests': [], 'retirement_requests': [],
})
if __name__ == '__main__':
    F.ThreadingHTTPServer(('127.0.0.1', 54399), F.H).serve_forever()
