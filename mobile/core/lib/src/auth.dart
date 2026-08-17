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

  /// What a tanod submits. Barangay 183 has a handful of tanods and most
  /// Philippine barangays are the same, so this is never a queue to
  /// automate — the admin knows the roster by name and checks the
  /// document against it. Barangay ID first because most barangays issue
  /// no separate appointment order (0019).
  static const tanodOptions = [
    barangayId,
    barangayAppointment,
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
    this.mustChangePassword = false,
  });

  final VerificationState status;

  /// Both are UTC as Postgres returns them. Convert with toLocal() at the
  /// point of display, not here.
  final DateTime? submittedAt;
  final DateTime? dueAt;

  final bool isSuspended;

  /// An administrator issued a temporary password (0028). Until it is
  /// changed, that administrator holds working credentials for this
  /// account — so the client forces a change before allowing anything
  /// else, rather than merely suggesting one.
  final bool mustChangePassword;

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
  RegistrationException(
    this.message, {
    this.field,
    this.goToLogin = false,
    this.isRetryable = false,
  });

  final String message;

  /// Which form field to highlight, when the failure points at one.
  final String? field;

  /// True when the right next step is the login screen rather than a
  /// correction — currently only for a mobile number already in use.
  final bool goToLogin;

  /// True when waiting and trying again is the right advice.
  final bool isRetryable;

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
    required String mobileNumber,
    required String password,
    required IdDocumentType idType,
    required String idImageUrl,
    required String selfieUrl,
    String? contactEmail,
    AccountRole role = AccountRole.resident,
  }) async {
    final mobile = normaliseMobile(mobileNumber);
    if (mobile == null) {
      throw RegistrationException(
        'Enter a mobile number like 09171234567.',
        field: 'mobile_number',
      );
    }

    try {
      await _client.auth.signUp(
        // Synthetic. Derived from the number, never shown, never mailed.
        email: authEmailFor(mobile),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'mobile_number': mobile,
          'contact_email': contactEmail?.trim(),
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

  /// Sign in with a phone number.
  ///
  /// The auth address is recomputed from the number typed, so there is no
  /// lookup: nothing to enumerate, no endpoint that turns a phone number
  /// into someone's real email. See migration 0021.
  Future<void> signIn({
    required String mobileNumber,
    required String password,
  }) async {
    final mobile = normaliseMobile(mobileNumber);
    if (mobile == null) {
      throw RegistrationException(
        'Enter a mobile number like 09171234567.',
        field: 'mobile_number',
      );
    }

    try {
      await _client.auth.signInWithPassword(
        email: authEmailFor(mobile),
        password: password,
      );
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();

      // Should be impossible after 0022, which confirms synthetic
      // addresses at creation. If it happens, the trigger is missing or
      // the account predates it — and the resident cannot fix it, so say
      // who can.
      if (m.contains('not confirmed') || m.contains('email_not_confirmed')) {
        throw RegistrationException(
          'This account is not activated. Please contact the barangay.',
        );
      }
      if (m.contains('banned') || m.contains('suspended')) {
        throw RegistrationException(
          'This account has been suspended. Please contact the barangay.',
        );
      }
      if (m.contains('rate limit') || m.contains('too many')) {
        throw RegistrationException(
          'Too many attempts. Please wait a few minutes and try again.',
          isRetryable: true,
        );
      }

      // Deliberately does not distinguish "no such number" from "wrong
      // password". Either would confirm whether a number is registered.
      if (m.contains('invalid login') || m.contains('invalid credentials')) {
        throw RegistrationException(
          'That mobile number and password do not match an account.',
        );
      }

      // Anything unmatched carries the underlying reason. A generic
      // message here cost twenty minutes of guesswork once already.
      throw RegistrationException('Could not sign you in. (${e.message})');
    }
  }

  /// `+639XXXXXXXXX`, or null if this is not a Philippine mobile number.
  ///
  /// Accepts 09XXXXXXXXX, +639XXXXXXXXX and 639XXXXXXXXX, with or without
  /// spaces or dashes. One normalised form so that the same person always
  /// derives the same identity however they type it.
  static String? normaliseMobile(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 11 && d.startsWith('09')) return '+63${d.substring(1)}';
    if (d.length == 12 && d.startsWith('639')) return '+$d';
    if (d.length == 10 && d.startsWith('9')) return '+63$d';
    return null;
  }

  /// Mirrors `public.auth_email_for()` in migration 0021. If either
  /// changes, both must: an account created under one and signed into
  /// under the other is unreachable.
  ///
  /// .local is reserved by RFC 6762 and unresolvable, so nothing can
  /// accidentally send mail to it.
  static String authEmailFor(String normalisedMobile) =>
      '${normalisedMobile.replaceAll(RegExp(r'[^0-9]'), '')}'
      '@auth.smartsumbong.local';

  /// Sets a new password and clears the temporary-password flag.
  ///
  /// Two calls that must both land. updateUser() changes the credential;
  /// clear_password_change_flag() releases the client from the forced
  /// change. If the second fails the password is already changed, so the
  /// user is not locked out — they simply see the screen again, which is
  /// the harmless direction for this to fail in.
  Future<void> changePassword(String newPassword) async {
    if (_client.auth.currentUser == null) {
      throw const AuthRequiredException();
    }
    if (newPassword.length < 8) {
      throw RegistrationException(
        'Your password must be at least 8 characters long.',
        field: 'password',
      );
    }

    await _client.auth.updateUser(UserAttributes(password: newPassword));
    await _client.rpc('clear_password_change_flag');
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
            'verification_due_at, is_suspended, must_change_password',
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
        mustChangePassword:
            (row['must_change_password'] as bool?) ?? false,
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
    // The auth address is derived from the mobile number, so GoTrue's
    // "already registered" means that *number* is taken — the Register
    // Account UC's alternative flow A1.
    if (m.contains('already registered') ||
        m.contains('user already exists')) {
      return RegistrationException(
        'That mobile number is already registered. Try signing in instead.',
        field: 'mobile_number',
        goToLogin: true,
      );
    }
    if (m.contains('users_email_key')) {
      return RegistrationException(
        'That email address is already used by another account. '
        'You can leave it blank.',
        field: 'email',
      );
    }
    if (m.contains('auth identity does not match')) {
      return RegistrationException(
        'Something went wrong with your mobile number. Please try again.',
        field: 'mobile_number',
      );
    }
    if (m.contains('mobile_number must be in the form')) {
      return RegistrationException(
        'Enter a mobile number like 09171234567.',
        field: 'mobile_number',
      );
    }
    if (m.contains('contact_email is not a valid')) {
      return RegistrationException(
        'That email address does not look right. You can leave it blank.',
        field: 'email',
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
