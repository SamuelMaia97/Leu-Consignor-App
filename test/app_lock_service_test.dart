import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/services/app_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AppLockService', () {
    test('verifyAndGetUsername returns the username on correct credentials', () async {
      final service = AppLockService();

      final username = await service.verifyAndGetUsername('admin', 'LeuConsignorApp2026!');

      expect(username, 'admin');
    });

    test('verifyAndGetUsername returns null on wrong password', () async {
      final service = AppLockService();

      final username = await service.verifyAndGetUsername('admin', 'wrong');

      expect(username, isNull);
    });

    test('verifyAndGetUsername returns null on unknown username', () async {
      final service = AppLockService();

      final username = await service.verifyAndGetUsername('unknown', 'LeuConsignorApp2026!');

      expect(username, isNull);
    });

    test('upsertUser adds a user that can then be verified', () async {
      final service = AppLockService();

      await service.upsertUser('clerk', 'secret');

      expect(await service.verifyAndGetUsername('clerk', 'secret'), 'clerk');
    });

    test('removeUser prevents login for that username afterwards', () async {
      final service = AppLockService();
      await service.upsertUser('clerk', 'secret');

      await service.removeUser('clerk');

      expect(await service.verifyAndGetUsername('clerk', 'secret'), isNull);
    });

    test('listUsernames returns all stored usernames', () async {
      final service = AppLockService();
      await service.upsertUser('clerk', 'secret');

      final usernames = await service.listUsernames();

      expect(usernames, containsAll(['admin', 'clerk']));
    });
  });
}
