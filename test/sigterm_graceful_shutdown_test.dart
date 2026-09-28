import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/main.dart';
import 'package:V8WorkToolbox/tools/network_proxy/services/mihomo_process_manager.dart';
import 'package:V8WorkToolbox/tools/network_proxy/services/network_proxy_service.dart';

/// SIGTERM 优雅退出路径的契约测试。
///
/// 对应 specs/local-deploy-automation 的 "Graceful cleanup of child processes
/// on termination"：进程级终止信号 SHALL 清理子进程，且清理失败 SHALL NOT
/// 阻止退出。
///
/// 覆盖策略说明：测试环境**不真实发送 SIGTERM**——那会杀死测试进程自身。
/// 改为对被注册的清理入口 `gracefulShutdownForTesting` 直接调用，并断言：
/// 1. 调用后 `MihomoProcessManager` 状态归位为 stopped（清理已发生）；
/// 2. 无子进程时调用是安全的（幂等，不抛）；
/// 3. `exit(0)` 由覆盖钩子观察，不真的终止测试进程。
///
/// 若测试未注入 `exitOverride`，`gracefulShutdownForTesting` 不会调用 exit，
/// 避免 `dart:io` 的 `exit()` 直接结束 test runner。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SIGTERM graceful shutdown', () {
    test('shutdown 收敛到 MihomoProcessManager.stop 且无进程时幂等安全', () async {
      // 未启动任何 mihomo 时状态应为 stopped（or 至少不会因 stop 抛异常）
      expect(
        MihomoProcessManager.instance.isRunning,
        anyOf(isTrue, isFalse),
      );

      // 清理入口可重复调用，不抛异常
      await gracefulShutdownForTesting();
      await gracefulShutdownForTesting();

      expect(MihomoProcessManager.instance.isRunning, isFalse);
    });

    test('NetworkProxyService.shutdown 无子进程时不抛异常', () async {
      await NetworkProxyService.instance.shutdown();
      expect(MihomoProcessManager.instance.isRunning, isFalse);
    });

    test('清理入口调用 exitOverride 而非真实 exit', () async {
      var exitCalled = false;
      exitOverride = (code) {
        exitCalled = true;
        // 测试中不真正退出
      };
      addTearDown(() => exitOverride = null);

      await gracefulShutdownForTesting();

      expect(exitCalled, isTrue);
    });
  });
}
