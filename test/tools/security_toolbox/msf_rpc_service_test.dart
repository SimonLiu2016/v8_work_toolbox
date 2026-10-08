import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/exploit_services.dart';

void main() {
  group('MsfRpcService Unit and Lifecycle Tests', () {
    test('default configuration and baseUri', () {
      const config = MsfConfig();
      expect(config.host, equals('127.0.0.1'));
      expect(config.port, equals(55553));
      expect(config.useSsl, isFalse);
      expect(config.baseUri.toString(), equals('http://127.0.0.1:55553/api'));
    });

    test('isDaemonRunning returns false for closed port', () async {
      final running = await MsfRpcService.instance.isDaemonRunning(
        host: '127.0.0.1',
        port: 59999,
        timeout: const Duration(milliseconds: 200),
      );
      expect(running, isFalse);
    });

    test('live integration: startDaemon, login, searchModules, stopDaemon', () async {
      // 仅在本地安装了 msfrpcd 时运行全流程
      if (!File('/opt/metasploit-framework/bin/msfrpcd').existsSync()) {
        return;
      }

      final service = MsfRpcService.instance;
      service.config = const MsfConfig(
        host: '127.0.0.1',
        port: 55553,
        password: 'testunitmsf',
      );

      // 确保端口干净
      await service.stopDaemon();

      // 启动守护进程
      final started = await service.startDaemon();
      expect(started, isTrue, reason: service.lastError);

      final isRunning = await service.isDaemonRunning();
      expect(isRunning, isTrue);

      // 登录
      final loggedIn = await service.login();
      expect(loggedIn, isTrue, reason: service.lastError);
      expect(service.state, equals(MsfConnectionState.connected));
      expect(service.token, isNotNull);

      // 模块搜索
      final modules = await service.searchModules('vsftpd');
      expect(modules, isNotEmpty);
      expect(modules.any((m) => m.fullName.contains('vsftpd')), isTrue);

      // 停止守护进程
      final stopped = await service.stopDaemon();
      expect(stopped, isTrue);
      expect(service.state, equals(MsfConnectionState.disconnected));
    });
  });
}
