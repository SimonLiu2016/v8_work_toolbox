import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/web_recon_services.dart';

void main() {
  group('WebTargetInfo Tests', () {
    test('parses IPv4 with http scheme and port', () {
      final info = WebTargetInfo.parse('http://192.168.1.1:8080/index.html?a=1');
      expect(info, isNotNull);
      expect(info!.host, '192.168.1.1');
      expect(info.port, 8080);
      expect(info.scheme, 'http');
      expect(info.isIp, isTrue);
      expect(info.isLocalOrPrivate, isTrue);
      expect(info.shouldSkipSubdomainEnumeration, isTrue);
      expect(info.probeTarget, 'http://192.168.1.1:8080');
      expect(info.displayAddress, '192.168.1.1:8080');
    });

    test('parses plain IPv4 without scheme', () {
      final info = WebTargetInfo.parse('192.168.1.1');
      expect(info, isNotNull);
      expect(info!.host, '192.168.1.1');
      expect(info.port, isNull);
      expect(info.scheme, isNull);
      expect(info.isIp, isTrue);
      expect(info.isLocalOrPrivate, isTrue);
      expect(info.shouldSkipSubdomainEnumeration, isTrue);
      expect(info.probeTarget, '192.168.1.1');
      expect(info.displayAddress, '192.168.1.1');
    });

    test('parses public domain with https scheme', () {
      final info = WebTargetInfo.parse('https://v8en.com/login');
      expect(info, isNotNull);
      expect(info!.host, 'v8en.com');
      expect(info.port, isNull);
      expect(info.scheme, 'https');
      expect(info.isIp, isFalse);
      expect(info.isLocalOrPrivate, isFalse);
      expect(info.shouldSkipSubdomainEnumeration, isFalse);
      expect(info.probeTarget, 'https://v8en.com');
      expect(info.displayAddress, 'v8en.com');
    });

    test('parses localhost and 127.0.0.1 as local targets', () {
      final local = WebTargetInfo.parse('localhost:3000');
      expect(local, isNotNull);
      expect(local!.host, 'localhost');
      expect(local.port, 3000);
      expect(local.isLocalOrPrivate, isTrue);
      expect(local.shouldSkipSubdomainEnumeration, isTrue);

      final loopback = WebTargetInfo.parse('http://127.0.0.1:8000');
      expect(loopback, isNotNull);
      expect(loopback!.isIp, isTrue);
      expect(loopback.isLocalOrPrivate, isTrue);
      expect(loopback.shouldSkipSubdomainEnumeration, isTrue);
    });

    test('parseList splits multiple lines and separators', () {
      const input = '''
        http://192.168.1.1, https://v8en.com
        10.0.0.1:8443; example.com
      ''';
      final list = WebTargetInfo.parseList(input);
      expect(list.length, 4);
      expect(list[0].host, '192.168.1.1');
      expect(list[1].host, 'v8en.com');
      expect(list[2].host, '10.0.0.1');
      expect(list[2].port, 8443);
      expect(list[3].host, 'example.com');
    });
  });

  group('Httpx Native Probe Test', () {
    test('successfully probes local HTTP server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set('Server', 'TestServer/1.0');
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><head><title>Test Device Page</title></head><body>OK</body></html>');
        req.response.close();
      });

      try {
        final results = await HttpxService.runNativeProbe(
          ['http://127.0.0.1:${server.port}'],
          timeout: const Duration(seconds: 3),
        );

        expect(results.length, 1);
        final r = results.first;
        expect(r.statusCode, 200);
        expect(r.title, 'Test Device Page');
        expect(r.webServer, 'TestServer/1.0');
        expect(r.host, '127.0.0.1');
      } finally {
        await server.close(force: true);
      }
    });
  });
}
