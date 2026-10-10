// Unit tests for the shared core: the rules that decide who a person is
// (their mobile number and sign-in identity), what state their account is
// in, and how photos are asked for. Each one mirrors something on the
// server, so a change on one side without the other fails here first.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

void main() {
  group('AuthService.normaliseMobile', () {
    test('accepts every way people write a PH mobile number', () {
      for (final typed in ['09171234567', '0917 123 4567', '0917-123-4567', '+639171234567', '639171234567', '9171234567', '+63 917 123 4567']) {
        expect(AuthService.normaliseMobile(typed), '+639171234567', reason: typed);
      }
    });

    test('refuses anything that is not a PH mobile number', () {
      for (final typed in ['', '0917123456', '091712345678', '08171234567', '+649171234567', 'abc', '1234']) {
        expect(AuthService.normaliseMobile(typed), isNull, reason: typed);
      }
    });
  });

  group('AuthService.authEmailFor', () {
    test('matches public.auth_email_for() in migration 0021', () {
      expect(AuthService.authEmailFor('+639171234567'), '639171234567@auth.smartsumbong.local');
    });

    test('is the same identity however the number was typed', () {
      final a = AuthService.authEmailFor(AuthService.normaliseMobile('0917 123 4567')!);
      final b = AuthService.authEmailFor(AuthService.normaliseMobile('+639171234567')!);
      expect(a, b);
    });
  });

  group('VerificationState.parse', () {
    test('reads the database values', () {
      expect(VerificationState.parse('verified'), VerificationState.verified);
      expect(VerificationState.parse('rejected'), VerificationState.rejected);
      expect(VerificationState.parse('pending'), VerificationState.pending);
    });

    test('treats anything unknown as pending, never as verified', () {
      expect(VerificationState.parse(null), VerificationState.pending);
      expect(VerificationState.parse('VERIFIED'), VerificationState.pending);
      expect(VerificationState.parse('something-new'), VerificationState.pending);
    });
  });

  group('cloudinarySized', () {
    const original = 'https://res.cloudinary.com/nwb2kryl/image/upload/v1791212357/reports/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg';

    test('asks Cloudinary for the shown width', () {
      expect(cloudinarySized(original, width: 480),
          'https://res.cloudinary.com/nwb2kryl/image/upload/c_limit,w_480,q_auto,f_auto/v1791212357/reports/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg');
    });

    test('leaves an already transformed URL alone', () {
      final once = cloudinarySized(original, width: 480);
      expect(cloudinarySized(once, width: 200), once);
    });

    test('leaves anything that is not a Cloudinary image alone', () {
      for (final url in ['https://example.com/a.jpg', 'https://res.cloudinary.com/nwb2kryl/video/upload/v1/a.mp4', '']) {
        expect(cloudinarySized(url, width: 300), url);
      }
    });
  });

  group('isVideoMime', () {
    test('only video types are videos', () {
      expect(isVideoMime('video/mp4'), isTrue);
      expect(isVideoMime('image/jpeg'), isFalse);
      expect(isVideoMime(null), isFalse);
    });
  });

  group('SavedLogins (one set per role)', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('resident and tanod keep their own number and password', () async {
      await SavedLogins.write('resident', '0917 111 1111', 'resident-pass');
      await SavedLogins.write('tanod', '0918 222 2222', 'tanod-pass');
      final r = await SavedLogins.read('resident');
      final t = await SavedLogins.read('tanod');
      expect((r!.mobile, r.password), ('0917 111 1111', 'resident-pass'));
      expect((t!.mobile, t.password), ('0918 222 2222', 'tanod-pass'));
    });

    test('forgetting one role leaves the other', () async {
      await SavedLogins.write('resident', '0917 111 1111', 'a');
      await SavedLogins.write('tanod', '0918 222 2222', 'b');
      await SavedLogins.forget('tanod');
      expect(await SavedLogins.read('tanod'), isNull);
      expect((await SavedLogins.read('resident'))!.password, 'a');
    });

    test('a password change follows only the same number', () async {
      await SavedLogins.write('resident', '0917 111 1111', 'old');
      await SavedLogins.updatePassword('resident', '+639171111111', 'new');
      expect((await SavedLogins.read('resident'))!.password, 'new');
      await SavedLogins.updatePassword('resident', '+639999999999', 'other');
      expect((await SavedLogins.read('resident'))!.password, 'new');
    });
  });

  group('MediaUploader (0109)', () {
    test('without the signing function it uploads through the unsigned preset', () async {
      final dir = await Directory.systemTemp.createTemp('upload');
      final photo = File('${dir.path}/p.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
      http.MultipartRequest? sent;
      final uploader = MediaUploader(
        cloudName: 'nwb2kryl',
        uploadPreset: 'smartsumbong_unsigned',
        client: MockClient.streaming((request, _) async {
          sent = request as http.MultipartRequest;
          final id = sent!.fields['public_id']!;
          return http.StreamedResponse(
            Stream.value('{"secure_url":"https://res.cloudinary.com/nwb2kryl/image/upload/v1/$id.jpg","format":"jpg","bytes":4,"public_id":"$id"}'.codeUnits),
            200,
          );
        }),
      );
      final media = await uploader.upload(photo, kind: MediaKind.reportPhoto);
      expect(sent!.fields['upload_preset'], 'smartsumbong_unsigned');
      expect(sent!.fields.containsKey('signature'), isFalse);
      expect(media.publicId, startsWith('reports/'));
      await dir.delete(recursive: true);
    });
  });
}
