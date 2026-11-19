// The case screen's test data: one report in every state the canvas draws (19 Nov 2026), added to the preview backend's tables.
//
//   216  Under Review, the barangay asked for details
//   301  In Progress, three concerns (one resolved), a barangay photo
//   297  Completed, with the tanod's proof photo and a 5-star rating
//   298  Completed, and the resident has asked to reopen it (a chat thread started)
//   75   Rejected (preview data)       55  Cancelled (preview data)
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/preview/demo_data.dart' show demoResidentId, demoTanodId;
import 'package:resident/preview/fake_backend.dart';

String caseId(int n) => 'b1000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

void seedCaseData(DemoBackend b) {
  ComplaintCatalogue.apply([
    {'key': 'street_obstruction', 'en': 'Street Obstruction', 'fil': 'Sagabal sa Kalsada', 'colour': '#F93535', 'icon': 'street_obstruction', 'options': [{'id': 10, 'en': 'Obstructed Sidewalks'}, {'id': 11, 'en': 'Illegal Parking'}, {'id': 12, 'en': 'Vendor Blocking Sidewalks'}]},
    {'key': 'peace_order_nuisance', 'en': 'Peace, Order, & Nuisance', 'fil': 'Katahimikan at Kaayusan', 'colour': '#E0609A', 'icon': 'peace_order_nuisance', 'options': []},
  ]);
  final reports = b.table('reports');
  Map<String, dynamic> rep(int n, String tracking, String category, String subject, String text, String status, String label, String created,
          {String? resolved}) =>
      {
        'id': caseId(n), 'resident_id': demoResidentId, 'tracking_id': tracking, 'category': category, 'subject': subject, 'description': text,
        'status': status, 'latitude': 14.5262, 'longitude': 121.0168, 'location_label': label, 'is_anonymous': false, 'created_at': created,
        'resolved_at': resolved, 'closed_at': null, 'reopened_count': 0, 'due_at': '2099-01-01T00:00:00Z', 'referred_to': null,
        'referral_note': null, 'followed_up_at': null, 'deleted_at': null,
      };
  reports.addAll([
    rep(216, 'BRG-2026-0116', 'peace_order_nuisance', 'Late-Night Gathering', 'A group drinks and shouts outside a sari-sari store on 7th Street until 2 AM.', 'pending_review', '7th Street', '2026-10-05T09:53:00Z'),
    rep(301, 'BRG-2026-0201', 'street_obstruction', 'Illegal Parking', 'Vans and a vendor cart block the sidewalk of 8th Street every evening.', 'in_progress', '8th Street', '2026-11-17T09:53:00Z'),
    rep(297, 'BRG-2026-0197', 'peace_order_nuisance', 'Unreasonable Neighborhood Noise', 'Unreasonable Neighborhood Noise — loud karaoke on 15th Street past midnight.', 'resolved', '15th Street', '2026-10-07T09:53:00Z', resolved: '2026-10-07T12:15:00Z'),
    rep(298, 'BRG-2026-0198', 'peace_order_nuisance', 'Unreasonable Neighborhood Noise', 'Unreasonable Neighborhood Noise — loud karaoke on 15th Street past midnight.', 'resolved', '15th Street', '2026-10-07T09:53:00Z', resolved: '2026-10-07T12:15:00Z'),
  ]);
  b.table('detail_requests').add({'id': 'dr1', 'report_id': caseId(216), 'message': 'Please tell us the house number or a landmark.', 'requested_at': '2026-10-06T01:00:00Z', 'response': null, 'responded_at': null});
  Map<String, dynamic> log(String id, int n, String? old, String st, String? remark, String at) => {'id': id, 'report_id': caseId(n), 'old_status': old, 'new_status': st, 'remark': remark, 'created_at': at};
  b.table('status_logs').addAll([
    log('L1', 216, null, 'pending_review', 'Report submitted', '2026-10-05T09:53:00Z'),
    log('L2', 216, 'pending_review', 'pending_review', 'More details requested: Please tell us the house number or a landmark.', '2026-10-06T01:00:00Z'),
    log('L3', 301, null, 'pending_review', 'Report submitted', '2026-11-17T09:53:00Z'),
    log('L4', 301, 'pending_review', 'validated', 'Validated by the barangay', '2026-11-17T10:10:00Z'),
    log('L5', 301, 'validated', 'assigned', 'Assigned to a tanod', '2026-11-17T11:02:00Z'),
    log('L6', 301, 'assigned', 'in_progress', 'A tanod is on the way to 8th Street.', '2026-11-18T08:20:00Z'),
    for (final n in [297, 298]) ...[
      log('M1$n', n, null, 'pending_review', 'Report submitted', '2026-10-07T09:53:00Z'),
      log('M2$n', n, 'pending_review', 'validated', 'Validated by the barangay', '2026-10-07T10:10:00Z'),
      log('M3$n', n, 'validated', 'assigned', 'Assigned to a tanod', '2026-10-07T11:02:00Z'),
      log('M4$n', n, 'assigned', 'resolved', 'Talked to the household, they lowered the volume. Photo attached.', '2026-10-07T12:15:00Z'),
    ],
    log('M5', 298, 'resolved', 'resolved', 'Resident requested reopening: The problem came back', DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()),
  ]);
  b.table('report_media').addAll([
    for (final n in [216, 301, 297, 298]) ...[
      {'report_id': caseId(n), 'media_url': 'https://example.invalid/a$n.jpg', 'mime_type': 'image/jpeg'},
      {'report_id': caseId(n), 'media_url': 'https://example.invalid/b$n.jpg', 'mime_type': 'image/jpeg'},
    ],
  ]);
  b.table('dispatches').addAll([
    for (final n in [297, 298])
      {'id': 'zd$n', 'report_id': caseId(n), 'tanod_id': demoTanodId, 'state': 'resolved', 'step': 'arrived', 'accept_due_at': null, 'assigned_at': '2026-10-07T11:02:00Z', 'accepted_at': '2026-10-07T11:05:00Z', 'resolved_at': '2026-10-07T12:15:00Z', 'admin_instructions': null, 'field_report_text': 'x'},
  ]);
  b.table('dispatch_media').addAll([
    for (final n in [297, 298]) {'id': 'zm$n', 'dispatch_id': 'zd$n', 'update_id': null, 'media_url': 'https://example.invalid/proof$n.jpg', 'mime_type': 'image/jpeg'},
  ]);
  b.table('report_evidence').add({'id': 'ev1', 'report_id': caseId(301), 'kind': 'resolution', 'media_url': 'https://example.invalid/ev1.jpg', 'mime_type': 'image/jpeg', 'created_at': '2026-11-18T07:40:00Z'});
  b.table('report_concerns').addAll([
    {'report_id': caseId(301), 'category': 'street_obstruction', 'option_id': 11, 'note': null, 'status': 'resolved', 'resolved_at': '2026-11-18T07:40:00Z', 'remark': 'The van was moved and a warning notice left.', 'created_at': '2026-11-17T09:53:00Z'},
    {'report_id': caseId(301), 'category': 'street_obstruction', 'option_id': 10, 'note': null, 'status': 'open', 'resolved_at': null, 'remark': null, 'created_at': '2026-11-17T09:54:00Z'},
    {'report_id': caseId(301), 'category': 'street_obstruction', 'option_id': 12, 'note': null, 'status': 'open', 'resolved_at': null, 'remark': null, 'created_at': '2026-11-17T09:55:00Z'},
  ]);
  b.table('feedback').add({'report_id': caseId(297), 'rating': 5, 'comment': 'Quick response, thank you.', 'submitted_at': '2026-10-08T00:00:00Z'});
  b.table('report_messages').addAll([
    {'id': 'cm1', 'report_id': caseId(298), 'from_barangay': false, 'body': 'The noise started again last night.', 'created_at': DateTime.now().toUtc().subtract(const Duration(minutes: 50)).toIso8601String()},
    {'id': 'cm2', 'report_id': caseId(298), 'from_barangay': false, 'body': 'Around 11 PM, same house as before.', 'created_at': DateTime.now().toUtc().subtract(const Duration(minutes: 49)).toIso8601String()},
    {'id': 'cm3', 'report_id': caseId(298), 'from_barangay': true, 'body': 'Thanks for telling us.', 'created_at': DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String()},
    {'id': 'cm4', 'report_id': caseId(298), 'from_barangay': true, 'body': 'A tanod will check tonight.', 'created_at': DateTime.now().toUtc().subtract(const Duration(minutes: 19)).toIso8601String()},
  ]);
  // the rejected one gets the barangay's reason in its history
  b.table('status_logs').removeWhere((l) => l['report_id'] == 'b1000000-0000-4000-8000-000000000075' && l['new_status'] == 'rejected');
  b.table('status_logs').add(log('R1', 75, 'pending_review', 'rejected', 'This is outside what the barangay can act on.', '2026-10-06T02:00:00Z'));
}

