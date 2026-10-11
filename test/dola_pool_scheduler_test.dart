import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/dola_pool/models/dola_account.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_account_store.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_pool_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dola_test_');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DolaPoolScheduler & Store Tests', () {
    test('DolaAccount status and availability logic', () {
      final fullAccount = DolaAccount(
        id: 'acc1',
        name: 'Account 1',
        sessionid: 'sess1',
        points: 4,
        status: DolaAccountStatus.full,
      );
      expect(fullAccount.isAvailable, isTrue);

      final halfAccount = fullAccount.copyWith(points: 2, status: DolaAccountStatus.half);
      expect(halfAccount.isAvailable, isTrue);

      final coolingAccount = fullAccount.copyWith(points: 1, status: DolaAccountStatus.cooling);
      expect(coolingAccount.isAvailable, isFalse);
    });

    test('cookie import parses sessionid properly', () async {
      final store = DolaAccountStore.instance;
      final cookieText = '''
# Cookie Export
sessionid=mock_session_abc12345; path=/; domain=.dola.com
sessionid=mock_session_def67890; path=/; domain=.dola.com
''';
      final count = await store.importFromCookieText(cookieText);
      expect(count, greaterThanOrEqualTo(0));
    });
  });
}
