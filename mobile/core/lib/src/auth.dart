// SmartSumbong — authentication and registration.
//
// Shared by the resident and tanod apps. The only thing that differs
// between them is the role passed to register().

import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors `public.id_document_type` in migration 0019. The wire values
/// must match the enum labels exactly — the signup trigger casts the
/// string and raises if it is not a recognised document type.
enum IdDocumentType {
  barangayId('barangay_id', 'Barangay ID'),
  driversLicense('drivers_license', "Driver's License"),
  passport('passport', 'Passport'),
  philsys('philsys', 'PhilSys (National) ID'),
  postalId('postal_id', 'Postal ID'),

  /// Some barangays issue a separate appointment order to tanods. Most
  /// do not, in which case a tanod submits their Barangay ID like any
  /// other resident — see the note in 0019 about why the document was
  /// never the real control for staff accounts.
  barangayAppointment('barangay_appointment', 'Barangay Appointment');

  const IdDocumentType(this.wire, this.label);

  /// The value sent to Postgres.
  final String wire;

  /// What the applicant sees in the dropdown.
  final String label;

  /// The five documents a resident can choose from, in the order the
  /// design lists them.
  static const residentOptions = [
    postalId,
    philsys,
    passport,
    barangayId,
    driversLicense,
  ];
}

enum AccountRole {
  resident('resident'),
  tanod('tanod');

  const AccountRole(this.wire);
  final String wire;
}

/// Mirrors `public.verification_state` in 0001.
enum VerificationState {
  pending,
  verified,
  rejected;

  static VerificationState parse(String? wire) => switch (wire) {
        'verified' => VerificationState.verified,
        'rejected' => VerificationState.rejected,
        _ => VerificationState.pending,
      };
}

/// What the Verification Pending screen needs in one round trip.
class VerificationSnapshot {
  const VerificationSnapshot({
    required this.status,
    this.submittedAt,
    this.dueAt,
    this.isSuspended = false,
  });

  final VerificationState status;

  /// Both are UTC as Postgres returns them. Convert with toLocal() at the
  /// point of display, not here.
  final DateTime? submittedAt;
  final DateTime? dueAt;

  final bool isSuspended;

  /// True once the two-hour service target has passed. Admins have been
  /// notified by sweep_overdue_verifications(); nothing happens to the
  /// applicant.
  bool get isOverdue =>
      dueAt != null && DateTime.now().toUtc().isAfter(dueAt!.toUtc());
}

/// The session is gone — expired, signed out elsewhere, or the row was
/// removed. The caller should send the user to login rather than show an
/// error they cannot act on.
class AuthRequiredException implements Exception {
  const AuthRequiredException();
  @override
  String toString() => 'Not signed in';
}

class RegistrationException implements Exception {
  RegistrationException(this.message, {this.field, this.goToLogin = false});

  final String message;

  /// Which form field to highlight, when the failure points at one.
  final String? field;

  /// True when the right next step is the login screen rather than a
  /// correction — currently only for a mobile number already in use.
  final bool goToLogin;

  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;

  /// Create an account.
  ///
  /// Both photos must already be uploaded and their delivery URLs passed
  /// in. That ordering is deliberate: `handle_new_auth_user()` requires
  /// id_image_url and selfie_url and runs inside the same transaction as
  /// the auth.users insert, so an incomplete application produces no
  /// credential at all. Uploading first means a failed signup costs the
  /// applicant a retry, not their photos and not their typed answers.
  ///
  /// The URLs are also CHECKed by users_id_image_url_pinned and
  /// users_selfie_url_pinned, so an address outside the barangay's own
  /// Cloudinary fails the insert rather than becoming something an
  /// administrator's browser would fetch.
  Future<void> register({
    required String fullName,
    required String email,
    required String mobileNumber,
    required String password,
    required IdDocumentType idType,
    required String idImageUrl,
    required String selfieUrl,
    AccountRole role = AccountRole.resident,
  }) async {
    try {
      await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'mobile_number': mobileNumber.trim(),
          'role': role.wire,
          'id_type': idType.wire,
          'id_image_url': idImageUrl,
          'selfie_url': selfieUrl,
        },
      );
    } on AuthException catch (e) {
      throw _translate(e.message);
    } on PostgrestException catch (e) {
      throw _translate(e.message);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      throw RegistrationException(
        e.message.toLowerCase().contains('invalid login')
            ? 'That email and password do not match an account.'
            : 'Could not sign you in. Please try again.',
      );
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  /// One row, four columns, for the Verification Pending screen.
  ///
  /// Reads through users_self_read (`id = auth.uid() or is_admin()`), so
  /// an applicant can only ever see their own standing. Called on app
  /// resume and on the refresh button — never on a timer. See the note in
  /// verification_pending_screen.dart for why this is polled rather than
  /// subscribed to over Realtime.
  Future<VerificationSnapshot> verificationStatus() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthRequiredException();

    try {
      final row = await _client
          .from('users')
          .select(
            'verification_status, verification_submitted_at, '
            'verification_due_at, is_suspended',
          )
          .eq('id', uid)
          .maybeSingle();

      // No row through RLS. Either the account was removed or the session
      // outlived it; either way the user must sign in again.
      if (row == null) throw const AuthRequiredException();

      return VerificationSnapshot(
        status: VerificationState.parse(row['verification_status'] as String?),
        submittedAt: _parseTs(row['verification_submitted_at']),
        dueAt: _parseTs(row['verification_due_at']),
        isSuspended: (row['is_suspended'] as bool?) ?? false,
      );
    } on PostgrestException catch (e) {
      // JWT expired or otherwise unusable.
      if (e.code == 'PGRST301' || e.message.toLowerCase().contains('jwt')) {
        throw const AuthRequiredException();
      }
      rethrow;
    }
  }

  DateTime? _parseTs(Object? v) =>
      v == null ? null : DateTime.tryParse(v as String);

  /// Turn a Postgres or GoTrue message into something a resident can act
  /// on. The trigger raises plain-language exceptions naming the missing
  /// field, and unique violations surface the constraint name, so both
  /// are matchable.
  RegistrationException _translate(String raw) {
    final m = raw.toLowerCase();

    // Register Account UC, alternative flow A1.
    if (m.contains('users_mobile_number_key') ||
        (m.contains('duplicate') && m.contains('mobile'))) {
      return RegistrationException(
        'That mobile number is already registered. Try signing in instead.',
        field: 'mobile_number',
        goToLogin: true,
      );
    }
    if (m.contains('already registered') ||
        m.contains('user already exists') ||
        m.contains('users_email_key')) {
      return RegistrationException(
        'That email address is already registered. Try signing in instead.',
        field: 'email',
        goToLogin: true,
      );
    }

    // Raised by handle_new_auth_user().
    if (m.contains('full_name is required')) {
      return RegistrationException('Please enter your full name.',
          field: 'full_name');
    }
    if (m.contains('mobile_number is required')) {
      return RegistrationException('Please enter your mobile number.',
          field: 'mobile_number');
    }
    if (m.contains('id_type is required') ||
        m.contains('not a recognised document type')) {
      return RegistrationException('Please choose which ID you are attaching.',
          field: 'id_type');
    }
    if (m.contains('id_image_url is required')) {
      return RegistrationException('Please attach a photo of your ID.',
          field: 'id_image');
    }
    if (m.contains('selfie_url is required')) {
      return RegistrationException('Please take a photo of yourself.',
          field: 'selfie');
    }
    if (m.contains('role must be resident or tanod')) {
      return RegistrationException('That account type is not available.');
    }

    // A URL that failed the pin. The applicant cannot fix this and
    // should not be told about Cloudinary.
    if (m.contains('_url_pinned')) {
      return RegistrationException(
        'Your photos could not be attached. Please retake them and try again.',
        field: 'id_image',
      );
    }

    if (m.contains('password')) {
      return RegistrationException(
        'Your password must be at least 8 characters long.',
        field: 'password',
      );
    }

    return RegistrationException(
      'Your account could not be created. Please try again.',
    );
  }
}
