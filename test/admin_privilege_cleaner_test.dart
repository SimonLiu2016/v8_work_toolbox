import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/system_service.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';

void main() {
  group('Admin Privilege Cleaner - Security Whitelist Tests', () {
    final home = Platform.environment['HOME'] ?? '/Users/test';

    test('允许安全白名单范围内的有效子目录', () {
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/jsDesignAgent'), isTrue);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Caches/com.legacy.app'), isTrue);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Containers/com.sandboxed.app'), isTrue);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Downloads/old_installer.pkg'), isTrue);
      expect(SystemService.isPathSafeForAdminCleanup('/tmp/temp_orphaned_dir'), isTrue);
      expect(SystemService.isPathSafeForAdminCleanup('/private/tmp/temp_cache'), isTrue);
      expect(SystemService.isPathSafeForAdminCleanup('/Library/Java/JavaVirtualMachines/jdk-11.jdk'), isTrue);
    });

    test('严格拒绝系统根目录、用户主目录根及白名单根路径本身', () {
      expect(SystemService.isPathSafeForAdminCleanup('/'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup(home), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Caches/'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('/Library/Java/JavaVirtualMachines/'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('/System/Library/CoreServices'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('/usr/bin'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('/bin/sh'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('/Applications/V8WorkToolbox.app'), isFalse);
    });

    test('严格拒绝包含路径穿越与特殊字符/命令注入的危险路径', () {
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/../Documents'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/test; rm -rf /'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/test && whoami'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/test | ls'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/test\nrm'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/test`id`'), isFalse);
      expect(SystemService.isPathSafeForAdminCleanup('$home/Library/Application Support/test\$VAR'), isFalse);
    });
  });

  group('SlimCandidateItem requiresAdmin Model Tests', () {
    test('requiresAdmin 默认为 false，支持 copyWith 保持不可变完整性', () {
      const item = SlimCandidateItem(
        id: 'item_1',
        path: '/path/to/item',
        title: 'Item 1',
        subtitle: 'Sub',
        sizeBytes: 1000,
        category: SlimmerCategory.orphanApp,
      );
      expect(item.requiresAdmin, isFalse);

      final updated = item.copyWith(requiresAdmin: true);
      expect(updated.requiresAdmin, isTrue);
      expect(item.requiresAdmin, isFalse); // 原对象不变
    });

    test('RecycleResult 准确反映 rootOwnedFailedPaths 与 hasRootOwnedFailures 状态', () {
      const resWithoutRoot = RecycleResult(
        successPaths: ['/a'],
        failedPaths: ['/b'],
      );
      expect(resWithoutRoot.hasRootOwnedFailures, isFalse);

      const resWithRoot = RecycleResult(
        successPaths: ['/a'],
        failedPaths: ['/b'],
        rootOwnedFailedPaths: ['/b'],
      );
      expect(resWithRoot.hasRootOwnedFailures, isTrue);
      expect(resWithRoot.rootOwnedFailedPaths, ['/b']);
    });
  });

  group('Admin Privilege UI Widget Tests', () {
    testWidgets('带 requiresAdmin 的项目在列表中渲染「需管理员权限」徽标', (tester) async {
      const adminItem = SlimCandidateItem(
        id: 'jsDesignAgent',
        path: '/Users/test/Library/Application Support/jsDesignAgent',
        title: 'jsDesignAgent',
        subtitle: '已卸载残留 (6.5 MB)',
        sizeBytes: 6500000,
        category: SlimmerCategory.orphanApp,
        safety: SafetyRating.caution,
        requiresAdmin: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(adminItem.title, style: AppTheme.fontBody),
                  if (adminItem.requiresAdmin) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.errorSubtle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 11, color: AppTheme.error),
                          SizedBox(width: 3),
                          Text('需管理员权限', style: TextStyle(color: AppTheme.error, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('jsDesignAgent'), findsOneWidget);
      expect(find.text('需管理员权限'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('清理失败弹窗针对管理员项显示「授权管理员清理」按钮和精准提示', (tester) async {
      const rootFailedPath = '/Users/test/Library/Application Support/jsDesignAgent';
      const result = RecycleResult(
        successPaths: [],
        failedPaths: [rootFailedPath],
        rootOwnedFailedPaths: [rootFailedPath],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: ctx,
                      builder: (dCtx) => AlertDialog(
                        backgroundColor: AppTheme.bgCard,
                        title: const Text('移入废纸篓失败'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (result.hasRootOwnedFailures)
                              const Text('原因：包含由系统管理员 (root) 拥有的项目，普通权限无法移入废纸篓。'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dCtx).pop(),
                            child: const Text('稍后处理'),
                          ),
                          if (result.hasRootOwnedFailures)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.error,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.lock_open_rounded, size: 16),
                              label: const Text('授权管理员清理'),
                              onPressed: () => Navigator.of(dCtx).pop(),
                            ),
                        ],
                      ),
                    );
                  },
                  child: const Text('触发弹窗'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发弹窗'));
      await tester.pumpAndSettle();

      expect(find.text('移入废纸篓失败'), findsOneWidget);
      expect(find.text('原因：包含由系统管理员 (root) 拥有的项目，普通权限无法移入废纸篓。'), findsOneWidget);
      expect(find.text('授权管理员清理'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);

      await tester.tap(find.text('授权管理员清理'));
      await tester.pumpAndSettle();
      expect(find.text('移入废纸篓失败'), findsNothing);
    });
  });
}
