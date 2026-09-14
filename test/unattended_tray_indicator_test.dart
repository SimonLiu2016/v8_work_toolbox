import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/launcher_service.dart';
import 'package:V8WorkToolbox/services/unattended_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const launcherChannel = MethodChannel('v8_work_toolbox/launcher');
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (MethodCall methodCall) async {
      methodCalls.add(methodCall);
      if (methodCall.method == 'setUnattendedStatus') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
  });

  group('Unattended Tray Indicator Formatter Tests', () {
    test('格式化大于1小时的时长', () {
      final d = const Duration(hours: 1, minutes: 45, seconds: 30);
      final formatted = UnattendedService.formatRemainingDuration(d);
      expect(formatted, '1小时45分');
    });

    test('格式化小于1小时但大于1分钟的时长', () {
      final d = const Duration(minutes: 25, seconds: 12);
      final formatted = UnattendedService.formatRemainingDuration(d);
      expect(formatted, '25分钟');
    });

    test('格式化小于1分钟的时长', () {
      final d = const Duration(seconds: 42);
      final formatted = UnattendedService.formatRemainingDuration(d);
      expect(formatted, '42秒');
    });

    test('格式化0或负数时长', () {
      expect(UnattendedService.formatRemainingDuration(Duration.zero), '00:00');
      expect(UnattendedService.formatRemainingDuration(const Duration(seconds: -10)), '00:00');
    });
  });

  group('LauncherService.setUnattendedStatus Platform Channel Tests', () {
    test('发送 active=true 及其专属 Tooltip', () async {
      final success = await LauncherService.instance.setUnattendedStatus(
        active: true,
        tooltip: 'V8 工作工具箱 - 无人值守运行中 (剩余 01:30)',
      );

      expect(success, isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'setUnattendedStatus');
      expect(methodCalls.first.arguments['active'], isTrue);
      expect(methodCalls.first.arguments['tooltip'], contains('无人值守运行中'));
    });

    test('发送 active=false 及其默认 Tooltip', () async {
      final success = await LauncherService.instance.setUnattendedStatus(
        active: false,
        tooltip: 'V8 工作工具箱 (⌥Space)',
      );

      expect(success, isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'setUnattendedStatus');
      expect(methodCalls.first.arguments['active'], isFalse);
      expect(methodCalls.first.arguments['tooltip'], 'V8 工作工具箱 (⌥Space)');
    });
  });

  group('UnattendedService Tray Sync Lifecycle Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('v8_tray_test_');
      final service = UnattendedService.instance;
      service.customStateFilePath = '${tempDir.path}/state.json';
      service.customAuditFilePath = '${tempDir.path}/audit.jsonl';
      service.customBinDirPath = '${tempDir.path}/bin';
      service.customClaudeSettingsPath = '${tempDir.path}/claude_settings.json';
      service.customAgyHooksPath = '${tempDir.path}/agy_hooks.json';
      service.customGeminiSettingsPath = '${tempDir.path}/gemini_settings.json';
      service.customAgySettingsPath = '${tempDir.path}/agy_settings.json';
      service.customAgyProjectPath = '${tempDir.path}/agy_project.json';
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('UnattendedService enable & disable 自动触发托盘状态同步', () async {
      final service = UnattendedService.instance;
      await service.init();

      // 清空 init 产生的调用记录
      methodCalls.clear();

      // 开启无人值守模式 60 分钟
      await service.enable(ttlMinutes: 60);

      expect(methodCalls.any((call) =>
          call.method == 'setUnattendedStatus' &&
          call.arguments['active'] == true &&
          (call.arguments['tooltip'] as String).contains('无人值守运行中')), isTrue);

      methodCalls.clear();

      // 关闭无人值守模式
      await service.disable();

      expect(methodCalls.any((call) =>
          call.method == 'setUnattendedStatus' &&
          call.arguments['active'] == false &&
          (call.arguments['tooltip'] as String).contains('⌥Space')), isTrue);
    });
  });
}
