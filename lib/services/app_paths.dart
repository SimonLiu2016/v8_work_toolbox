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

  /// 隐私空间私密浏览器目录（`tools/private_browser/`）。
  static Directory get privateBrowserDir =>
      Directory(p.join(root.path, 'PrivateBrowser'));

  /// 隐私空间私密浏览器 SQLite 数据库文件。
  static File get privateBrowserDbFile =>
      File(p.join(privateBrowserDir.path, 'PrivateBrowser.sqlite'));

  /// 隐私空间私密浏览器缩略图与图标缓存目录。
  static Directory get privateBrowserThumbnailsDir =>
      Directory(p.join(privateBrowserDir.path, 'thumbnails'));

  /// 安全工具箱根目录（`tools/security_toolbox/`）。
  static Directory get securityDir => Directory(p.join(root.path, 'security'));

  /// 安全工具箱 SQLite 库（`tools/security_toolbox/database/security_database.dart`）。
  ///
  /// 与 note.db 分开：渗透会话的 Finding 数量级远高于笔记，导出与备份互不影响。
  static File get securityDbFile =>
      File(p.join(securityDir.path, 'security.db'));

  /// 脚本模板库（`tools/security_toolbox/services/script_template_store.dart`）。
  static File get scriptTemplatesFile =>
      File(p.join(securityDir.path, 'script_templates.json'));

  /// ARTEX 引擎工具根目录（`tools/artex_engine/`）。
  ///
  /// **只存本工具自己的产物**（override 备份、构建日志副本）。
  /// 引擎的数据（PostgreSQL 命名卷 + 工程目录下的 `data/`）归 Docker 与
  /// artex 仓库管，不在这里登记——把它们纳入会破坏 AppPaths「本软件生成的
  /// 本地数据」这一语义，也会让备份/清理误判引擎数据的归属。
  static Directory get artexDir => Directory(p.join(root.path, 'artex'));

  /// AI 短视频工坊根目录（`tools/ai_video_studio/`）。
  static Directory get videoStudioDir => Directory(p.join(root.path, 'video_studio'));

  /// 全局公共库：跨剧通用资产（BGM / SFX / 风格预设）。
  static Directory get videoStudioGlobalLibDir =>
      Directory(p.join(videoStudioDir.path, 'global_library'));

  /// 全局公共预设目录（美学风格库与时代题材库）。
  static Directory get videoStudioPresetsDir =>
      Directory(p.join(videoStudioGlobalLibDir.path, 'presets'));

  /// 全局美学风格预设文件（`aesthetic_styles.json`）。
  static File get aestheticStylesFile =>
      File(p.join(videoStudioPresetsDir.path, 'aesthetic_styles.json'));

  /// 全局时代题材预设文件（`visual_eras.json`）。
  static File get visualErasFile =>
      File(p.join(videoStudioPresetsDir.path, 'visual_eras.json'));

  /// 全局系统提示词与规则模板文件（`prompt_templates.json`）。
  static File get promptTemplatesFile =>
      File(p.join(videoStudioPresetsDir.path, 'prompt_templates.json'));

  /// 资产库：跨剧复用的图片资产。
  ///
  /// 与 `global_library/bgm`、`global_library/sfx` 平级但分开目录——那两类是
  /// 用户从外部丢进来的素材，这里是软件生成、经用户精选的产物。语义不同：
  /// 一个可能是版权素材，一个是自己付过费生成的。
  static Directory get videoStudioAssetImagesDir =>
      Directory(p.join(videoStudioDir.path, 'assets', 'images'));

  /// 资产库：跨剧复用的视频片段资产。
  static Directory get videoStudioAssetClipsDir =>
      Directory(p.join(videoStudioDir.path, 'assets', 'clips'));

  /// 资产索引文件（ID → 元数据）。
  ///
  /// 单 JSON + 原子写。资产是用户精选，预期几百条量级，不值得上 SQLite；
  /// 若将来要做检索再迁，数据是一整条记录、导出迁移不难。
  static File get videoStudioAssetIndexFile =>
      File(p.join(videoStudioDir.path, 'assets', 'asset_index.json'));

  /// 连续剧 IP 主库：每部剧一个子目录（`series_library/<series-id>/`）。
  static Directory get videoStudioSeriesDir =>
      Directory(p.join(videoStudioDir.path, 'series_library'));

  /// 独立持久化 IP 主库：存放长效 IP 资产（角色卡、场景库、道具、世界观）。
  static Directory get videoStudioIpDir =>
      Directory(p.join(videoStudioDir.path, 'ip_library'));

  /// Agnes 试炼场根目录（`tools/agnes_playground/`）。
  ///
  /// 挂在 `video_studio/` 下而不是自己一个顶层目录：它的产物要进同一个
  /// 资产库（`AssetLibrary`），模型与供应商配置也全部来自 AI 基础设施。把它
  /// 放在工坊数据目录内，备份与清理时这一整块会一起被考虑。
  static Directory get agnesPlaygroundDir =>
      Directory(p.join(videoStudioDir.path, 'agnes_playground'));

  /// 试炼场轮次索引（会话与轮次的轻量元数据）。
  ///
  /// 单 JSON + 原子写，与 `asset_index.json`、`video_task_ledger` 同一套做法。
  /// 媒体本体不在这里——它放在各轮次自己的目录下。
  static File get agnesPlaygroundIndexFile =>
      File(p.join(agnesPlaygroundDir.path, 'index.json'));

  /// 试炼场外部调用草稿文件（供工坊一键转试炼场调试使用）。
  static File get agnesPlaygroundDraftFile =>
      File(p.join(agnesPlaygroundDir.path, 'draft.json'));

  /// 单个轮次的目录：参考图副本、产物与 `request.json` 都在里面。
  static Directory agnesPlaygroundTurnDir(String turnId) =>
      Directory(p.join(agnesPlaygroundDir.path, 'turns', turnId));

  /// 无限画布工具自己的目录（`infinite_canvas/`）。
  ///
  /// **只存本工具自己的产物**（override 备份、日志副本）。
  ///
  /// 刻意**没有**对应的数据目录：无限画布的 docker 容器是 nginx 静态服务器，
  /// 密钥、画布、素材与生成记录全在浏览器本地存储里，宿主机文件系统上一个
  /// 字节都没有——没有东西可以 bind mount（design D1）。
  static Directory get infiniteCanvasDir =>
      Directory(p.join(root.path, 'infinite_canvas'));

  /// 实时会议翻译工具的字幕导出目录（`live_translator/`）。
  ///
  /// 只存用户显式导出的字幕文件（SRT/VTT）。原始音频不落盘（spec），
  /// 字幕记录在内存累积，导出时写入此处或用户选定位置。
  static Directory get liveTranslatorExportDir =>
      Directory(p.join(root.path, 'live_translator'));

  /// Dola 号池根目录（账号元数据 + 能力覆盖配置）。
  ///
  /// `dola_accounts.json` 此前直接躺在 [root] 根下，与其他工具的目录约定不
  /// 一致。sessionid 不在这里——它在 Keychain（`dola_account_session_<id>`）。
  static Directory get dolaDir => Directory(p.join(root.path, 'dola'));

  /// 云端视频异步任务台账目录。
  ///
  /// 单独一个目录而不是塞进 `video_studio/`：台账记的是**跨工具**的云端任务
  /// 生命周期（AI 视频工坊是当前唯一使用者，但 Kling / SenseAudio 同样是
  /// 异步任务模型），它不属于某个工具的产物目录。
  static Directory get videoTaskLedgerDir =>
      Directory(p.join(root.path, 'video_task_ledger'));

  /// 视频任务台账文件。
  ///
  /// 单文件 + 原子替换写。任务创建即计费，所以这个文件丢失等于用户失去
  /// 「积分扣了但视频在哪」的唯一线索——它必须比任务本身先落盘。
  static File get videoTaskLedgerFile =>
      File(p.join(videoTaskLedgerDir.path, 'tasks.json'));

  /// IT 会议听力素材目录。
  ///
  /// 存**烘焙产物**：片段音频（`<clipId>.mp3`）与逐轮文稿清单
  /// （`<clipId>.json`），外加一个全量索引（`index.json`）。
  ///
  /// 音频与文稿分离且同目录配对：精听模式的逐句高亮、术语收藏的时间点、
  /// 以及将来导入其它来源（用户自己的会议录音）都依赖这份文稿结构。
  static Directory get itMeetingListeningDir =>
      Directory(p.join(root.path, 'it_meeting_listening'));

  /// IT 会议听力的烘焙缓存目录（逐轮临时音频）。
  ///
  /// 与素材目录分开：素材是产物、需长期保留；缓存是合成过程的中间物，
  /// 拼接完即可清理。混在一起会让"清理缓存"误删成品。
  static Directory get itMeetingListeningCacheDir =>
      Directory(p.join(itMeetingListeningDir.path, 'cache'));

  /// IT 会议听力收藏的术语读音音频目录。
  ///
  /// 与素材目录分开：素材是烘焙产物（可整体重建），术语读音是**用户收藏的
  /// 成果**（丢了就没了），两者生命周期不同，混在一起会让"重建素材"误删收藏。
  static Directory get itMeetingTermAudioDir =>
      Directory(p.join(itMeetingListeningDir.path, 'term_audio'));

  /// IT 会议听力的来源同步状态文件。
  ///
  /// **与素材目录分开**（design D7）：素材是产物（会被重烘焙覆盖），
  /// 同步状态是"上次同步到哪了"的历史——重烘焙不该让它丢失。
  static File get itMeetingSyncStateFile =>
      File(p.join(itMeetingListeningDir.path, 'sync_state.json'));

  /// IT 会议听力的播放断点记忆文件。
  ///
  /// 记录每个场景最后播放到的片段与偏移。单独存一个文件而不是塞进素材索引：
  /// 索引是烘焙产物（会被整体重写），断点是**用户行为**（不该被烘焙覆盖）。
  static File get itMeetingListeningProgressFile =>
      File(p.join(itMeetingListeningDir.path, 'play_progress.json'));

  /// 排练会议的中间产物目录（材料、讲稿、剧本）。
  ///
  /// 与素材目录分开：素材目录装的是**成品**（mp3 + json 清单，被索引整体描述），
  /// 这里装的是**三阶段各自的中间产物**——讲稿改了剧本要重生成、剧本改了音频
  /// 要重烘，但材料本身不变。混在一起会让"清理缓存"误删用户改过的讲稿。
  static Directory get itMeetingRehearsalDir =>
      Directory(p.join(itMeetingListeningDir.path, 'rehearsal'));

  /// 导入的会议材料原始副本目录。
  ///
  /// 材料是**用户提供的原始文件**（MD/HTML），讲稿与剧本都从它派生。单独放
  /// 一份副本而不是只记路径：源文件可能被移动或修改，用户要能追溯"这场会议
  /// 是基于哪一版材料生成的"。
  static Directory get itMeetingMaterialDir =>
      Directory(p.join(itMeetingRehearsalDir.path, 'materials'));

  /// 真实会议（导入的逐字稿）根目录。
  ///
  /// **与 [itMeetingRehearsalDir] 分开**：排练会议的三层产物（材料/讲稿/剧本）
  /// 是"从材料生成"的，真实会议的四层（原稿/设定/回答/合成状态）是"导入后
  /// 演进"的。两者同名文件（`materials` vs `meetings`）混在一起时，清理任一侧
  /// 都会误伤另一侧。
  static Directory get realMeetingDir =>
      Directory(p.join(itMeetingListeningDir.path, 'real_meetings'));

  /// 真实会议原稿目录（`meetings/<meetingId>.json`）。
  static Directory get realMeetingMeetingsDir =>
      Directory(p.join(realMeetingDir.path, 'meetings'));

  /// 真实会议说话人设定目录（覆盖层）。
  static Directory get realMeetingSettingsDir =>
      Directory(p.join(realMeetingDir.path, 'settings'));

  /// 真实会议插入回答目录（回答层）。
  static Directory get realMeetingAnswersDir =>
      Directory(p.join(realMeetingDir.path, 'answers'));

  /// 真实会议合成状态目录（派生数据，与整篇音频同目录）。
  static Directory get realMeetingAudioDir =>
      Directory(p.join(realMeetingDir.path, 'audio'));

  /// 真实会议逐轮音频目录（`turns/<meetingId>/g<k>.mp3`）。
  ///
  /// **必须在持久目录**：界面的「清理缓存」会清空
  /// [itMeetingListeningCacheDir]，而插入一段回答后的整篇重建依赖这些逐轮
  /// 文件。放进缓存目录，清一次缓存就退化成重跑几百轮 TTS（design D4）。
  static Directory realMeetingTurnsDir(String meetingId) =>
      Directory(p.join(realMeetingDir.path, 'turns', meetingId));

  /// 跨会议词汇索引文件。
  ///
  /// 与会议数据分开：索引是派生产物，损坏/缺失时从 `meetings/*.json` 全量重建。
  static File get meetingVocabularyIndexFile =>
      File(p.join(realMeetingDir.path, 'vocabulary_index.json'));

  /// 「我的身份」配置文件（跨所有真实会议恒等）。
  static File get listeningMyIdentityFile =>
      File(p.join(itMeetingListeningDir.path, 'my_identity.json'));

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
    privateBrowserDbFile,
    securityDbFile,
    scriptTemplatesFile,
    videoTaskLedgerFile,
    videoStudioAssetIndexFile,
    agnesPlaygroundIndexFile,
    agnesPlaygroundDraftFile,
    aestheticStylesFile,
    visualErasFile,
    itMeetingSyncStateFile,
    itMeetingListeningProgressFile,
    meetingVocabularyIndexFile,
    listeningMyIdentityFile,
  ];

  /// 全部导出目录，供回归测试断言单一性。
  static List<Directory> get allDirs => [
    configDir,
    logsDir,
    attachmentsDir,
    opsToolDir,
    privateMediaDir,
    readerConfigDir,
    privateBrowserDir,
    privateBrowserThumbnailsDir,
    securityDir,
    artexDir,
    videoStudioDir,
    videoStudioGlobalLibDir,
    videoStudioPresetsDir,
    videoStudioSeriesDir,
    videoStudioIpDir,
    infiniteCanvasDir,
    dolaDir,
    novelLibraryDir,
    videoTaskLedgerDir,
    videoStudioAssetImagesDir,
    videoStudioAssetClipsDir,
    agnesPlaygroundDir,
    itMeetingListeningDir,
    itMeetingListeningCacheDir,
    itMeetingTermAudioDir,
    itMeetingRehearsalDir,
    itMeetingMaterialDir,
    realMeetingDir,
    realMeetingMeetingsDir,
    realMeetingSettingsDir,
    realMeetingAnswersDir,
    realMeetingAudioDir,
    liveTranslatorExportDir,
  ];

  /// 小说管理器根目录（`tools/novel_manager/`）。
  static Directory get novelLibraryDir =>
      Directory(p.join(root.path, 'novel_library'));

  /// 小说管理器 SQLite 数据库文件。
  static File get novelDatabaseFile =>
      File(p.join(novelLibraryDir.path, 'novel_manager.sqlite'));

  /// 单部小说目录。
  static Directory novelDir(String novelId) =>
      Directory(p.join(novelLibraryDir.path, novelId));

  /// 单部小说的章节正文存放目录。
  static Directory novelChaptersDir(String novelId) =>
      Directory(p.join(novelDir(novelId).path, 'chapters'));
}
