// The preview's dummy data: Rose Besarra (a resident) with six reports in
// every state, Kim Arcibal (a tanod) with a dispatch waiting, one in
// progress and a week of history — the same cast as the HTML app preview.

import 'dart:math';

const demoResidentId = 'a0000000-0000-4000-8000-000000000001';
const demoTanodId = 'a0000000-0000-4000-8000-000000000002';

String _ago({int days = 0, int hours = 0, int minutes = 0}) =>
    DateTime.now().toUtc().subtract(Duration(days: days, hours: hours, minutes: minutes)).toIso8601String();
String _in({int days = 0, int hours = 0, int minutes = 0}) =>
    DateTime.now().toUtc().add(Duration(days: days, hours: hours, minutes: minutes)).toIso8601String();

String _id(String prefix, int n) => '$prefix-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Map<String, List<Map<String, dynamic>>> buildDemoTables() {
  Map<String, dynamic> report(int n, String tracking, String category, String subject, String text, String status,
          {required double lat, required double lng, required String label, String? referred, String? referralNote, int ago = 1, DateTime? due, bool reopened = false}) =>
      {
        'id': _id('b1000000', n),
        'resident_id': demoResidentId,
        'tracking_id': tracking,
        'category': category,
        'subject': subject,
        'description': text,
        'status': status,
        'latitude': lat,
        'longitude': lng,
        'location_label': label,
        'is_anonymous': false,
        'created_at': _ago(days: ago),
        'resolved_at': status == 'resolved' || status == 'closed' ? _ago(days: max(0, ago - 1)) : null,
        'closed_at': status == 'closed' ? _ago(days: max(0, ago - 1)) : null,
        'reopened_count': reopened ? 1 : 0,
        'due_at': due?.toUtc().toIso8601String() ?? _in(days: 1),
        'referred_to': referred,
        'referral_note': referralNote,
        'followed_up_at': null,
        'deleted_at': null,
      };

  final reports = [
    report(103, 'BRG-2026-0103', 'public_safety_infrastructure', 'Poor Street Lighting',
        'The streetlight at the corner of 10th Street has been out for a week. It is very dark at night.', 'in_progress',
        lat: 14.5262, lng: 121.0168, label: '10th Street', ago: 1),
    report(101, 'BRG-2026-0101', 'environmental_waste_hazard', 'Clogged Drainage',
        'The drain on 13th Street is clogged and the street floods every time it rains.', 'pending_review',
        lat: 14.5281, lng: 121.0149, label: '13th Street', ago: 2),
    report(88, 'BRG-2026-0088', 'street_obstruction', 'Illegal Parking',
        'Vehicles parked outside the garage every night, blocking the way out.', 'resolved',
        lat: 14.5255, lng: 121.0137, label: '7th Street', ago: 8),
    report(80, 'BRG-2026-0080', 'peace_order_nuisance', 'Neighborhood Noise',
        'Loud karaoke every night until 2 AM.', 'in_progress',
        lat: 14.5271, lng: 121.0158, label: '9th Street', ago: 5, referred: 'Lupong Tagapamayapa', referralNote: 'Referred for mediation between the neighbours.'),
    report(75, 'BRG-2026-0075', 'animal_welfare', 'Stray Animals',
        'A pack of stray dogs near the school entrance.', 'rejected',
        lat: 14.5248, lng: 121.0151, label: 'Villamor Road', ago: 12),
    report(55, 'BRG-2026-0055', 'traffic_violation', 'Reckless Driving',
        'Motorcycles speeding through the small street.', 'cancelled',
        lat: 14.5277, lng: 121.0141, label: '12th Street', ago: 20),
  ];

  final users = [
    {
      'id': demoResidentId, 'role': 'resident', 'full_name': 'Rose Besarra', 'mobile_number': '+639171234567', 'email': 'rose@example.com',
      'address': '12 Manlunas St., Barangay 183', 'avatar_url': null, 'verification_status': 'verified',
      'verification_submitted_at': _ago(days: 40), 'verification_due_at': _ago(days: 38), 'is_suspended': false, 'must_change_password': false,
      'rejection_reason': null, 'is_retired': false, 'retired_at': null, 'id_image_url': null, 'id_type': null, 'ocr_rescan_requested_at': null,
      'muted_notification_kinds': <String>[], 'duty_status': null, 'last_location_at': null,
    },
    {
      'id': demoTanodId, 'role': 'tanod', 'full_name': 'Kim Arcibal', 'mobile_number': '+639271269625', 'email': null,
      'address': 'Barangay 183', 'avatar_url': null, 'verification_status': 'verified',
      'verification_submitted_at': _ago(days: 90), 'verification_due_at': _ago(days: 88), 'is_suspended': false, 'must_change_password': false,
      'rejection_reason': null, 'is_retired': false, 'retired_at': null, 'id_image_url': null, 'id_type': null, 'ocr_rescan_requested_at': null,
      'muted_notification_kinds': <String>[], 'duty_status': 'on_duty', 'last_location_at': _ago(minutes: 4),
    },
  ];

  Map<String, dynamic> rep(int n) => reports.firstWhere((r) => r['id'] == _id('b1000000', n));

  final dispatches = [
    {
      'id': _id('c1000000', 1), 'report_id': _id('b1000000', 101), 'tanod_id': demoTanodId, 'state': 'assigned', 'step': null,
      'accept_due_at': _in(minutes: 9), 'assigned_at': _ago(minutes: 1), 'accepted_at': null, 'resolved_at': null,
      'admin_instructions': 'Check the drain cover near the sari-sari store and photograph the blockage before clearing.', 'field_report_text': null,
    },
    {
      'id': _id('c1000000', 2), 'report_id': _id('b1000000', 103), 'tanod_id': demoTanodId, 'state': 'accepted', 'step': null,
      'accept_due_at': null, 'assigned_at': _ago(hours: 3), 'accepted_at': _ago(hours: 2, minutes: 50), 'resolved_at': null,
      'admin_instructions': 'Yung kalye siyempre. Check both ends of 10th Street.', 'field_report_text': null,
    },
    {
      'id': _id('c1000000', 3), 'report_id': _id('b1000000', 88), 'tanod_id': demoTanodId, 'state': 'resolved', 'step': 'arrived',
      'accept_due_at': null, 'assigned_at': _ago(days: 3), 'accepted_at': _ago(days: 3), 'resolved_at': _ago(days: 3, hours: -2),
      'admin_instructions': null, 'field_report_text': 'Spoke to the owner. The cars are now parked inside the compound.',
    },
    {
      'id': _id('c1000000', 4), 'report_id': _id('b1000000', 80), 'tanod_id': demoTanodId, 'state': 'expired', 'step': null,
      'accept_due_at': _ago(days: 5), 'assigned_at': _ago(days: 5), 'accepted_at': null, 'resolved_at': null,
      'admin_instructions': null, 'field_report_text': null,
    },
  ];

  final reportMedia = [
    {'report_id': _id('b1000000', 103), 'media_url': 'https://picsum.photos/seed/streetlight/800/600', 'mime_type': 'image/jpeg'},
    {'report_id': _id('b1000000', 101), 'media_url': 'https://picsum.photos/seed/drain/800/600', 'mime_type': 'image/jpeg'},
    {'report_id': _id('b1000000', 101), 'media_url': 'https://picsum.photos/seed/flood/800/600', 'mime_type': 'image/jpeg'},
  ];

  final dispatchMedia = [
    {'id': _id('d1000000', 1), 'dispatch_id': _id('c1000000', 3), 'update_id': null, 'media_url': 'https://picsum.photos/seed/cleared/800/600', 'mime_type': 'image/jpeg'},
  ];

  Map<String, dynamic> log(int n, int reportN, String? old, String status, String? remark, {int hours = 0, int days = 0}) =>
      {'id': _id('e1000000', n), 'report_id': _id('b1000000', reportN), 'old_status': old, 'new_status': status, 'remark': remark, 'created_at': _ago(days: days, hours: hours)};
  final statusLogs = [
    log(1, 103, null, 'pending_review', 'Report submitted', days: 1),
    log(2, 103, 'pending_review', 'validated', 'Validated by the barangay', hours: 20),
    log(3, 103, 'validated', 'assigned', 'Assigned to a tanod', hours: 3),
    log(4, 103, 'assigned', 'in_progress', 'The tanod is working on it', hours: 2),
    log(5, 101, null, 'pending_review', 'Report submitted', days: 2),
    log(6, 88, null, 'pending_review', 'Report submitted', days: 8),
    log(7, 88, 'pending_review', 'assigned', 'Assigned to a tanod', days: 7),
    log(8, 88, 'assigned', 'resolved', 'Spoke to the owner. The cars are now parked inside the compound.', days: 3),
    log(9, 75, null, 'pending_review', 'Report submitted', days: 12),
    log(10, 75, 'pending_review', 'rejected', 'Stray animals are handled by the city veterinary office; we sent them your report.', days: 11),
    log(11, 80, null, 'pending_review', 'Report submitted', days: 5),
    log(12, 80, 'pending_review', 'in_progress', 'Referred to the Lupong Tagapamayapa.', days: 4),
    log(13, 55, null, 'pending_review', 'Report submitted', days: 20),
    log(14, 55, 'pending_review', 'cancelled', 'Cancelled by the resident', days: 19),
  ];

  Map<String, dynamic> notif(int n, String kind, String message, int reportN, {int hours = 0, int days = 0, bool read = false}) => {
        'id': _id('f1000000', n), 'user_id': demoResidentId, 'kind': kind, 'message': message,
        'is_read': read, 'created_at': _ago(days: days, hours: hours), 'report_id': reportN == 0 ? null : _id('b1000000', reportN),
      };
  final notifications = [
    notif(1, 'assignment', 'A tanod is on your report BRG-2026-0103.', 103, hours: 3),
    notif(2, 'status_change', 'BRG-2026-0103 is now In Progress.', 103, hours: 2),
    notif(3, 'status_change', 'BRG-2026-0101 is under review.', 101, days: 2, read: true),
    notif(4, 'status_change', 'BRG-2026-0088 was resolved. Tell us how it went.', 88, days: 3, read: true),
    notif(5, 'escalation', 'BRG-2026-0080 was referred to the Lupong Tagapamayapa.', 80, days: 4, read: true),
    notif(6, 'status_change', 'BRG-2026-0075 was rejected.', 75, days: 11, read: true),
    // the tanod's own notices
    {'id': _id('f1000000', 20), 'user_id': demoTanodId, 'kind': 'assignment', 'message': 'New dispatch: Clogged Drainage, BRG-2026-0101. Accept within 10 minutes.', 'is_read': false, 'created_at': _ago(minutes: 1), 'report_id': null},
    {'id': _id('f1000000', 21), 'user_id': demoTanodId, 'kind': 'status_change', 'message': 'The barangay approved your report for BRG-2026-0088.', 'is_read': true, 'created_at': _ago(days: 2), 'report_id': null},
  ];

  final reportMessages = [
    {'id': _id('g1000000', 1), 'report_id': _id('b1000000', 103), 'from_barangay': false, 'body': 'Is there an update? It is still dark at night.', 'created_at': _ago(hours: 5)},
    {'id': _id('g1000000', 2), 'report_id': _id('b1000000', 103), 'from_barangay': true, 'body': 'We are sorry for the inconvenience. A tanod is on the way and your report is now in progress.', 'created_at': _ago(hours: 4)},
  ];

  final dispatchUpdates = [
    {'id': _id('h1000000', 1), 'dispatch_id': _id('c1000000', 2), 'author_id': demoTanodId, 'kind': 'step', 'step': 'accepted', 'body': null, 'created_at': _ago(hours: 2, minutes: 50)},
    {'id': _id('h1000000', 2), 'dispatch_id': _id('c1000000', 2), 'author_id': null, 'kind': 'note', 'step': null, 'body': 'Please take a photo of the post number.', 'created_at': _ago(hours: 2, minutes: 30)},
  ];

  final hotlineGroups = [
    {'id': 'hg1', 'parent_id': null, 'name': 'National emergency', 'display': 'inline', 'sort_order': 1, 'is_active': true},
    {'id': 'hg2', 'parent_id': null, 'name': 'Fire', 'display': 'inline', 'sort_order': 2, 'is_active': true},
    {'id': 'hg3', 'parent_id': null, 'name': 'Barangay 183 Hotline', 'display': 'inline', 'sort_order': 3, 'is_active': true},
    {'id': 'hg4', 'parent_id': null, 'name': 'Police Villamor Substation S59', 'display': 'link', 'sort_order': 4, 'is_active': true},
    {'id': 'hg5', 'parent_id': null, 'name': 'Pasay City Hotlines', 'display': 'link', 'sort_order': 5, 'is_active': true},
    {'id': 'hg5a', 'parent_id': 'hg5', 'name': 'Disaster Risk Reduction (CDRRMO)', 'display': 'inline', 'sort_order': 1, 'is_active': true},
    {'id': 'hg5b', 'parent_id': 'hg5', 'name': 'City Health Office', 'display': 'inline', 'sort_order': 2, 'is_active': true},
  ];
  final hotlineNumbers = [
    {'group_id': 'hg1', 'label': '911', 'number': '911', 'carrier': null, 'sort_order': 1, 'is_active': true},
    {'group_id': 'hg2', 'label': 'Fire Protection Pasay City', 'number': '(02) 8831 5555', 'carrier': null, 'sort_order': 1, 'is_active': true},
    {'group_id': 'hg3', 'label': null, 'number': '0927 126 9625', 'carrier': 'Globe', 'sort_order': 1, 'is_active': true},
    {'group_id': 'hg3', 'label': null, 'number': '0917 555 0183', 'carrier': 'Smart', 'sort_order': 2, 'is_active': true},
    {'group_id': 'hg4', 'label': null, 'number': '(02) 8551 2316', 'carrier': 'Landline', 'sort_order': 1, 'is_active': true},
    {'group_id': 'hg4', 'label': null, 'number': '0998 598 6159', 'carrier': 'Smart', 'sort_order': 2, 'is_active': true},
    {'group_id': 'hg5a', 'label': null, 'number': '(02) 8853 0450', 'carrier': 'Landline', 'sort_order': 1, 'is_active': true},
    {'group_id': 'hg5a', 'label': null, 'number': '0917 880 1175', 'carrier': 'Globe', 'sort_order': 2, 'is_active': true},
    {'group_id': 'hg5b', 'label': null, 'number': '(02) 8551 8601', 'carrier': 'Landline', 'sort_order': 1, 'is_active': true},
  ];

  // referenced so the unused helper stays honest
  rep(103);

  return {
    'users': users,
    'reports': reports,
    'dispatches': dispatches,
    'report_media': reportMedia,
    'dispatch_media': dispatchMedia,
    'status_logs': statusLogs,
    'notifications': notifications,
    'report_messages': reportMessages,
    'dispatch_updates': dispatchUpdates,
    'detail_requests': <Map<String, dynamic>>[],
    'feedback': <Map<String, dynamic>>[],
    'escalation_requests': <Map<String, dynamic>>[],
    'hotline_groups': hotlineGroups,
    'hotline_numbers': hotlineNumbers,
  };
}
