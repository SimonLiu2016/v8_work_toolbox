import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// macOS entitlements 契约。
///
/// 背景：`file_picker` 10.3.x 的 Swift 端强制校验 App Sandbox 的
/// user-selected 文件权限——`pickFiles`/`getDirectoryPath` 要求 read-only 或
/// read-write 任一，`saveFile` 只认 read-write。两个 key 缺任何一个都会让
/// 全库 28 处文件面板调用失败（用户实测「导入文档」点击无反应或报
/// ENTITLEMENT_NOT_FOUND）。
///
/// 另有一层：§1 实测发现 Xcode 构建产物与部署脚本重签后的 app
/// **都不带**这些 entitlement，所以 `scripts/deploy_local.sh` 必须显式传
/// `--entitlements`。本测试守的是源文件层面的完整性——部署脚本那条由
/// 任务 6.7 的部署后 codesign 验收兜底。
const _requiredKeys = [
  'com.apple.security.files.user-selected.read-only',
  'com.apple.security.files.user-selected.read-write',
];

const _entitlementFiles = [
  'macos/Runner/Release.entitlements',
  'macos/Runner/DebugProfile.entitlements',
];

/// 极简 plist key 提取：匹配 <key>X</key>。
final _keyRe = RegExp(r'<key>([^<]+)</key>');

void main() {
  group('macOS entitlements', () {
    for (final path in _entitlementFiles) {
      test('$path 含全部 user-selected key', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path 不存在');

        final content = file.readAsStringSync();
        final keys = _keyRe.allMatches(content).map((m) => m.group(1)!).toSet();

        for (final key in _requiredKeys) {
          expect(
            keys,
            contains(key),
            reason:
                '$path 缺少 $key——file_picker 的对应调用会失败。\n'
                'pickFiles/getDirectoryPath 需要 read-only 或 read-write 任一，\n'
                'saveFile（导出 MP3/思维导图/密码备份/字幕/对比报告）只认 read-write。',
          );
        }
      });
    }

    test('两个 entitlement 文件的 key 集合一致', () {
      // 历史上两文件内容一致。若只改一个，会出现「debug 好用 release 挂」
      // 或反过来——极难定位。
      final sets = _entitlementFiles.map((p) {
        final c = File(p).readAsStringSync();
        return _keyRe.allMatches(c).map((m) => m.group(1)!).toSet();
      }).toList();

      expect(sets[0], sets[1],
          reason: 'Release 与 DebugProfile 的 entitlement key 不一致');
    });

    test('Debug/Release 的既有网络与 Apple Events 权限未被误删', () {
      // 只加不删：历史上这些 key 支撑代理、mihomo、终端脚本调用。
      const legacy = [
        'com.apple.security.network.client',
        'com.apple.security.network.server',
        'com.apple.security.automation.apple-events',
        'com.apple.security.cs.allow-unsigned-executable-memory',
      ];

      for (final path in _entitlementFiles) {
        final c = File(path).readAsStringSync();
        final keys = _keyRe.allMatches(c).map((m) => m.group(1)!).toSet();
        for (final k in legacy) {
          expect(keys, contains(k), reason: '$path 丢失了既有 key $k');
        }
      }
    });

    test('Xcode 工程未启用 App Sandbox', () {
      // design Non-Goals：加 entitlement 只为通过 file_picker 校验，
      // 不开沙盒。开了会牵动全库文件 I/O 重审。
      final pbx = File('macos/Runner.xcodeproj/project.pbxproj');
      expect(pbx.existsSync(), isTrue);

      final content = pbx.readAsStringSync();
      final enabled =
          RegExp(r'ENABLE_APP_SANDBOX\s*=\s*YES').hasMatch(content);
      expect(
        enabled,
        isFalse,
        reason: 'ENABLE_APP_SANDBOX 被开启——本次 change 明确不开沙盒',
      );
    });
  });
}
