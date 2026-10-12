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
      // 默认跳过：这条测试起真的 msfrpcd 并绑死 55553，与其他测试并发跑时
      // 必然互相竞争（表现为时好时坏）。只在显式要求跑 live integration 时
      // 才执行：
      //   V8_RUN_LIVE_INTEGRATION=1 flutter test ...
      final liveEnabled = Platform.environment['V8_RUN_LIVE_INTEGRATION'] == '1';
      final msfrpcdInstalled =
          File('/opt/metasploit-framework/bin/msfrpcd').existsSync();
      if (!liveEnabled || !msfrpcdInstalled) {
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
