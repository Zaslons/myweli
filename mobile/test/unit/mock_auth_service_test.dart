import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

void main() {
  const phone = '+2250700000099';
  const wrong = '000000';
  const correct = MockAuthService.demoOtp;

  test('a wrong code is rejected with an attempts-remaining message', () async {
    final service = MockAuthService();
    await service.sendOtp(phone);

    final res = await service.verifyOtp(phone, wrong);

    expect(res.success, isFalse);
    expect(res.code, 'otp_invalid');
    expect(res.error, contains('restant'));
  });

  test('locks after the max wrong attempts and stays locked', () async {
    final service = MockAuthService();
    await service.sendOtp(phone);

    var res = await service.verifyOtp(phone, wrong);
    for (var i = 1; i < 5; i++) {
      res = await service.verifyOtp(phone, wrong);
    }
    expect(res.code, 'otp_locked');

    // Even the correct code is refused once locked.
    final afterLock = await service.verifyOtp(phone, correct);
    expect(afterLock.code, 'otp_locked');
  });

  test('the correct code logs in and consumes the code', () async {
    final service = MockAuthService();
    await service.sendOtp(phone);

    final ok = await service.verifyOtp(phone, correct);
    expect(ok.success, isTrue);
    expect(ok.data?.phoneNumber, phone);

    // Code is single-use: a second verify has no active code.
    final again = await service.verifyOtp(phone, correct);
    expect(again.code, 'otp_none');
  });

  test('an expired code is rejected', () async {
    final service = MockAuthService(otpValidity: Duration.zero);
    await service.sendOtp(phone);

    final res = await service.verifyOtp(phone, correct);
    expect(res.code, 'otp_expired');
  });

  test('verifying with no active code reports otp_none', () async {
    final service = MockAuthService();

    final res = await service.verifyOtp(phone, correct);
    expect(res.code, 'otp_none');
  });

  test('resends are capped after the initial send', () async {
    final service = MockAuthService();
    await service.sendOtp(phone); // initial
    await service.sendOtp(phone); // resend 1
    await service.sendOtp(phone); // resend 2
    await service.sendOtp(phone); // resend 3

    final blocked = await service.sendOtp(phone); // resend 4 — over the cap
    expect(blocked.success, isFalse);
    expect(blocked.code, 'otp_resend_limit');
  });
}
