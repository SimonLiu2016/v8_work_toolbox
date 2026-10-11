import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_ca_service.dart';

void main() {
  late Directory tempDir;
  late ArtexCaService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('artex_ca');
    service = ArtexCaService.instance;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 造出引擎运行后才会有的证书文件。
  void createCert() {
    final dir = Directory('${tempDir.path}/data/traffic/_ca');
    dir.createSync(recursive: true);
    File('${dir.path}/mitmproxy-ca-cert.pem').writeAsStringSync(
      '-----BEGIN CERTIFICATE-----\n',
    );
  }

  group('证书路径（task 7.1）', () {
    test('指向工程目录下的 data/traffic/_ca', () {
      expect(
        service.certPath('/proj'),
        '/proj/data/traffic/_ca/mitmproxy-ca-cert.pem',
      );
    });
  });

  group('三态检测（task 7.4）', () {
    test('证书不存在 → notGenerated（引擎没跑过）', () async {
      final state = await service.detect(tempDir.path);
      expect(state, ArtexCaState.notGenerated);
      expect(state.needsGuidance, isFalse);
    });

    test('证书存在且未装 → generatedNotTrusted，需要引导', () async {
      createCert();
      final state = await service.detect(
        tempDir.path,
        isTrusted: (_) async => false,
      );
      expect(state, ArtexCaState.generatedNotTrusted);
      expect(state.needsGuidance, isTrue);
    });

    test('证书存在且已装 → trusted，不重复引导', () async {
      createCert();
      final state = await service.detect(
        tempDir.path,
        isTrusted: (_) async => true,
      );
      expect(state, ArtexCaState.trusted);
      expect(state.needsGuidance, isFalse);
    });
  });

  group('安装命令（task 7.3）', () {
    test('命令包含 sudo、trustRoot、System.keychain 与正确的证书路径', () {
      final cmd = service.installCommand(tempDir.path);
      expect(cmd, contains('sudo security add-trusted-cert'));
      expect(cmd, contains('-r trustRoot'));
      expect(cmd, contains('/Library/Keychains/System.keychain'));
      expect(cmd, contains(service.certPath(tempDir.path)));
    });

    test('证书路径带引号，避免路径含空格时被 shell 拆开', () {
      final cmd = service.installCommand('/Users/a b/artex');
      expect(cmd, contains('"/Users/a b/artex/data/traffic/_ca/mitmproxy-ca-cert.pem"'));
    });
  });

  group('系统级影响必须明示（spec）', () {
    test('卸载提示非空且指向钥匙串访问', () {
      expect(service.uninstallHint, contains('钥匙串访问'));
      expect(service.uninstallHint, contains('全系统'));
    });
  });
}
