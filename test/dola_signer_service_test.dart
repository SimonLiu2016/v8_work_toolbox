import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_signer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DolaSignerService Tests', () {
    test('node is available on test environment', () async {
      final isNode = await DolaSignerService.instance.isNodeAvailable();
      expect(isNode, isTrue);
    });

    test('signUrl successfully attaches a_bogus parameter', () async {
      final result = await DolaSignerService.instance.signUrl(
        url: 'https://www.dola.com/api/v1/im/chain/single',
        cookies: {'sessionid': 'mock_session_id_12345678'},
      );

      expect(result.isSuccess, isTrue);
      expect(result.signedUrl, contains('https://www.dola.com/api/v1/im/chain/single'));
      expect(result.signedUrl, contains('a_bogus='));
      expect(result.aBogus.isNotEmpty, isTrue);
    });

    test('concurrent signUrl calls resolve correctly with request IDs', () async {
      final futures = <Future<DolaSignedResult>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(DolaSignerService.instance.signUrl(
          url: 'https://www.dola.com/api/v1/im/chain/single?test=$i',
          cookies: {'sessionid': 'session_$i'},
        ));
      }

      final results = await Future.wait(futures);
      expect(results.length, equals(5));
      for (var i = 0; i < 5; i++) {
        expect(results[i].isSuccess, isTrue);
        expect(results[i].signedUrl, contains('test=$i'));
        expect(results[i].signedUrl, contains('a_bogus='));
      }
    });
  });
}
