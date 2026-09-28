import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 本地数据存储的唯一路径源。
///
/// 历史上本项目存在三套并行的路径解析：硬编码 `HOME` 拼接、平台 API
/// `getApplicationSupportDirectory()`、以及 drift 的默认数据库目录。应用一旦被
/// 授予文件访问授权（沙盒化），后两套会被重定向到带 bundle id 的目录，而第一套
/// 原地不动——同一份设计承诺（运维工具与 AI 配置同目录）因此在实现层分裂，
/// 运维数据库与笔记附件整体失联。
///
/// 现在全部本地数据路径都从这里派生。根目录经平台 API 解析后拼接固定子目录名，
/// 与 bundle id 解耦：即使将来 bundle id 变化，路径也不会漂移。
///
/// 使用方式：`main()` 中各窗口入口经 `WindowServices` 调用 [init]（异步一次），
/// 之后各模块同步读取下方导出路径。测试用 [overrideRootForTesting] 隔离。
abstract final class AppPaths {
  static Directory? _root;

  /// 应用支持目录下的固定子目录名。
  ///
  /// 用固定名而非 bundle id，是为了让路径与打包标识解耦——bundle id 改过一次
  /// （com.example → com.v8en），路径不能再跟着漂。
  static const String appDirName = 'V8WorkToolbox';

  /// 本地数据根目录。未初始化时抛出而非返回 null：静默 null 会让下游拼出
  /// `null/xxx` 这类路径，把「忘了 init」变成难查的数据写入错位。
  static Directory get root {
    final root = _root;
    if (root == null) {
      throw StateError(
        'AppPaths 尚未初始化。应在 main() 的 WindowServices.initFor() 中调用 '
        'AppPaths.init()——各窗口入口都必须覆盖，包括子窗口。',
      );
    }
    return root;
  }

  static bool get isInitialized => _root != null;

  /// 解析并记录根目录。幂等，但重复调用会以最后一次为准（测试可借此重置）。
  ///
  /// **macOS 上刻意不用 `getApplicationSupportDirectory()`。** 该插件在 macOS
  /// 必然在返回值后追加 bundle id（`PathProviderPlugin.swift` 的
  /// `appendingPathComponent(Bundle.main.bundleIdentifier!)`，对沙盒与非沙盒
  /// 一视同仁），而本项目全部历史数据位于无 bundle id 的
  /// `~/Library/Application Support/V8WorkToolbox`。跟随平台 API 就等于把数据
  /// 目录绑定到打包标识上——bundle id 改一次（com.example → com.v8en）数据就
  /// 失联一次，且 `AppPaths` 再拼一层固定子目录只会得到
  /// `com.v8en.V8WorkToolbox/V8WorkToolbox` 这种三层路径。
  ///
  /// 本项目实际只发布 macOS，因此这里显式走硬编码，非 macOS 才回退平台 API。
  static Future<Directory> init() async {
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return overrideRootForTesting(Directory(
        p.join(home, 'Library', 'Application Support', appDirName),
      ));
    }
    final appSupport = await getApplicationSupportDirectory();
    return overrideRootForTesting(
      Directory(p.join(appSupport.path, appDirName)),
    );
  }

  /// 仅供测试：把根目录替换为指定目录。
  @visibleForTesting
  static Directory overrideRootForTesting(Directory dir) {
    _root = dir;
    return dir;
  }

  /// 仅供测试：清空根目录，用于验证「未初始化」分支。
  @visibleForTesting
  static void resetForTesting() {
    _root = null;
  }

  // --------------------------------------------------------------------------
  // 导出路径。新增本地数据时在此登记，不要在模块里自行拼接。
  // --------------------------------------------------------------------------

  /// AI 供应商与槽位绑定配置（`services/ai_config_store.dart`）。
  static File get aiConfigFile => File(p.join(root.path, 'ai_config.json'));

  /// 应用级配置（`services/settings_store.dart`）。
  static File get appConfigFile => File(p.join(root.path, 'app.json'));

  /// 各工具的分项配置目录（`services/settings_store.dart`）。
  static Directory get configDir => Directory(p.join(root.path, 'config'));

  /// 运行日志目录。
  static Directory get logsDir => Directory(p.join(root.path, 'logs'));

  /// 笔记主库（`tools/notebook/note_database.dart`）。
  ///
  /// 原为 drift 默认目录 `~/Documents/notebook.db`，属第三套路径策略，
  /// 已收敛至此。
  static File get noteDbFile => File(p.join(root.path, 'notebook.db'));

  /// 笔记附件目录（`tools/notebook/note_store.dart`）。
  static Directory get attachmentsDir =>
      Directory(p.join(root.path, 'notebook_attachments'));

  /// 运维工具根目录（`tools/ops_tool/`）。
  static Directory get opsToolDir => Directory(p.join(root.path, 'ops_tool'));

  /// 运维工具 SQLite 库（`tools/ops_tool/database/ops_database.dart`）。
  static File get opsToolDbFile => File(p.join(opsToolDir.path, 'ops_tool.db'));

  /// 隐私空间媒体（`tools/private_player/services/private_storage_manager.dart`）。
  static Directory get privateMediaDir =>
      Directory(p.join(root.path, 'PrivateMedia'));

  /// 密码库元数据（明文 JSON，`tools/password/vault_store.dart`）。
  static File get vaultMetadataFile =>
      File(p.join(root.path, 'vault_metadata.json'));

  /// 密码库密文（`tools/password/vault_file_store.dart`）。
  static File get vaultSecretsFile => File(p.join(root.path, '.secrets.bin'));

  /// 密码库 DEK 文件（`tools/password/crypto/kek_manager.dart`）。
  static File get kekFile => File(p.join(root.path, '.dek'));

  /// 资产提醒状态（`tools/notebook/asset_reminder_service.dart`）。
  static File get assetRemindersFile =>
      File(p.join(root.path, 'asset_reminders.json'));

  /// AI 调用日志（`services/ai_logger.dart`）。
  static File get aiLogFile => File(p.join(logsDir.path, 'ai.log'));

  /// 定时资讯任务列表（`services/scheduled_news_service.dart`）。
  static File get newsTasksFile =>
      File(p.join(root.path, 'scheduled_news_tasks.json'));

  /// 定时资讯已生成简报（`services/scheduled_news_service.dart`）。
  static File get newsBriefingsFile =>
      File(p.join(root.path, 'scheduled_news_briefings.json'));

  /// AI 助手会话历史（`tools/ai_assistant/services/ai_assistant_service.dart`）。
  static File get aiAssistantHistoryFile =>
      File(p.join(root.path, 'ai_assistant_history.json'));

  /// 阅读器配置目录（`tools/reader/services/reader_config_store.dart`）。
  static Directory get readerConfigDir =>
      Directory(p.join(root.path, 'reader_config'));

  /// 全部导出路径，供回归测试断言单一性。
  static List<File> get allFiles => [
    aiConfigFile,
    appConfigFile,
    noteDbFile,
    opsToolDbFile,
    vaultMetadataFile,
    vaultSecretsFile,
    kekFile,
    newsTasksFile,
    assetRemindersFile,
    aiLogFile,
    newsBriefingsFile,
    aiAssistantHistoryFile,
  ];

  /// 全部导出目录，供回归测试断言单一性。
  static List<Directory> get allDirs => [
    configDir,
    logsDir,
    attachmentsDir,
    opsToolDir,
    privateMediaDir,
    readerConfigDir,
  ];
}
