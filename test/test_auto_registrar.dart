import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/auto_registrar/services/excel_helper.dart';
import 'package:V8WorkToolbox/tools/auto_registrar/services/registered_account_store.dart';
import 'package:V8WorkToolbox/tools/password/vault_store.dart';

void main() {
  test('自动导入历史 Excel 账号并同步至密码保险箱', () async {
    final tempDir = await Directory.systemTemp.createTemp('v8_test_account_');
    AppPaths.overrideRootForTesting(tempDir);

    const excelPath = '/Users/simon/Downloads/邮箱信息.xlsx';
    expect(File(excelPath).existsSync(), isTrue);

    // 1. 测试解析
    final parsed = await ExcelHelper.parseExcelFile(excelPath);
    print('成功解析到 ${parsed.length} 个账号');
    expect(parsed.length, 57);
    expect(parsed.first.email, contains('@outlook.com'));

    // 2. 测试 Store 导入与持久化
    final store = RegisteredAccountStore.instance;
    final importedCount = await store.importAccounts(parsed);
    print('成功导入 Store: $importedCount 个条目');
    expect(importedCount, 57);
    expect(store.accounts.length, 57);

    // 3. 测试批量同步至密码保险箱
    final vaultStore = VaultStore(customRootDir: tempDir);
    await vaultStore.load();
    final syncedCount = await store.syncToPasswordVault(
      accountIds: store.accounts.take(5).map((a) => a.id).toList(),
      vaultStore: vaultStore,
    );
    print('成功同步至密码保险箱: $syncedCount 个条目');
    expect(syncedCount, 5);
    expect(vaultStore.items.length, 5);
    expect(vaultStore.items.first.title, contains('OUTLOOK 邮箱'));

    // 4. 清理
    await tempDir.delete(recursive: true);
  });
}
