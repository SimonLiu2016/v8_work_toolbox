import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/auto_registrar/services/registrar_config_store.dart';
import 'package:V8WorkToolbox/tools/auto_registrar/services/registrar_sidecar_service.dart';

void main() {
  test('测试 RegistrarConfigStore 持久化及读取', () async {
    final tempDir = await Directory.systemTemp.createTemp('v8_test_reg_config_');
    AppPaths.overrideRootForTesting(tempDir);

    final store = RegistrarConfigStore.instance;
    await store.load();

    // 默认值
    expect(store.config.concurrency, 2);
    expect(store.config.targetDomain, 'outlook.com');

    // 修改并保存
    final updated = store.config.copyWith(
      concurrency: 5,
      targetDomain: 'hotmail.com',
      recoveryEmail: 'test_recovery@qq.com',
      imapAuth: 'abcdef1234567890',
      smsApiKey: 'sms_token_test_123',
    );
    await store.save(updated);

    // 重新加载验证
    await store.load();
    expect(store.config.concurrency, 5);
    expect(store.config.targetDomain, 'hotmail.com');
    expect(store.config.recoveryEmail, 'test_recovery@qq.com');
    expect(store.config.imapAuth, 'abcdef1234567890');
    expect(store.config.smsApiKey, 'sms_token_test_123');

    // 测试系统 AI 视觉解析方法（不会崩溃）
    final sidecar = RegistrarSidecarService.instance;
    final aiInfo = await sidecar.resolveSystemVisionAi();
    print('系统 AI 视觉解析结果: isAvailable=${aiInfo.isAvailable}, provider=${aiInfo.providerName}, model=${aiInfo.model}');

    await tempDir.delete(recursive: true);
  });
}
