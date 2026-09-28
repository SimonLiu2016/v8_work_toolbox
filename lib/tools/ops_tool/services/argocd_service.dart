import 'dart:async';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import 'gitlab_client.dart';

/// 配置仓路径解析结果：仓库路径 / 分支 / 子目录。
/// 对应原工具 `parse_projects_path`，路径形如 `/tree/master/argocd/projects`。
class ArgoCdRepoRef {
  final String repo;
  final String branch;
  final String fileDir;

  const ArgoCdRepoRef({
    required this.repo,
    required this.branch,
    required this.fileDir,
  });
}

/// 从配置仓 YAML 文件中解析出的镜像 Tag 条目。
class ArgoCdYamlTag {
  final String projectName;
  final String filePath;
  final String currentTag;

  const ArgoCdYamlTag({
    required this.projectName,
    required this.filePath,
    required this.currentTag,
  });
}

/// 「刷新 Tag」/巡检的拉取结果。`failures` 让读取失败可见——
/// 历史上 `catch (_) {}` 曾让整个目录的服务文件一个都读不到时界面毫无提示。
class ArgoCdTagScanResult {
  final List<ArgoCdYamlTag> tags;
  final List<ArgoCdTagReadFailure> failures;
  final int skippedNonServiceFiles;

  const ArgoCdTagScanResult({
    required this.tags,
    this.failures = const [],
    this.skippedNonServiceFiles = 0,
  });

  int get successCount => tags.length;
  int get failureCount => failures.length;
}

/// 单个服务文件读取失败的原因，供 UI 汇总展示。
class ArgoCdTagReadFailure {
  final String filePath;
  final String reason;

  const ArgoCdTagReadFailure({required this.filePath, required this.reason});
}

/// 一次巡检发现的 Tag 变更事件，供 UI 实时刷新与通知通道消费。
class ArgoCdChangeEvent {
  final String envId;
  final String envName;
  final String projectName;
  final String currentTag;
  final String? targetTag;
  final String monitorMode;
  final bool restored;

  const ArgoCdChangeEvent({
    required this.envId,
    required this.envName,
    required this.projectName,
    required this.currentTag,
    required this.targetTag,
    required this.monitorMode,
    this.restored = false,
  });

  /// 面向通知与日志的展示文案。
  String get message =>
      '[$envName] $projectName Tag 漂移: $currentTag → 目标 ${targetTag ?? "(未设定)"}'
      '${restored ? ' (已自动修复)' : ''}';
}

class ArgoCdService {
  ArgoCdService._();
  static final ArgoCdService instance = ArgoCdService._();

  final StreamController<ArgoCdChangeEvent> _changeController =
      StreamController<ArgoCdChangeEvent>.broadcast();

  /// 变更事件流：仅推送「需要提醒」的行（未被关闭提醒）。
  /// 取代原工具的 `listen('argocd-tag-changed')`，UI 不再自行轮询。
  Stream<ArgoCdChangeEvent> get changes => _changeController.stream;

  // ==========================================================================
  // YAML Tag 解析
  // ==========================================================================

  static String? extractImageTag(String content) {
    final lines = content.split('\n');
    bool inImageSection = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.toLowerCase() == 'image:' || trimmed.toLowerCase().startsWith('image:')) {
        inImageSection = true;
        continue;
      }

      if (inImageSection) {
        if (line.startsWith(' ') || line.startsWith('\t')) {
          final lower = trimmed.toLowerCase();
          if (lower.startsWith('tag:')) {
            final val = _stripQuotes(trimmed.substring(4).trim());
            if (val.isNotEmpty) return val;
          }
        } else {
          break;
        }
      }
    }

    // Fallback: search for any "Tag:" line
    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('tag:')) {
        final val = _stripQuotes(trimmed.substring(4).trim());
        if (val.isNotEmpty) return val;
      }
    }

    return null;
  }

  /// 剥离 YAML 标量两端成对的引号——`tag: "1.6.24.0"` 与 `tag: 1.6.24.0` 必须
  /// 归一为同一值，否则比对时全部误判为不一致并触发无意义的锁定回写。
  static String _stripQuotes(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  static String replaceImageTag(String content, String newTag) {
    final lines = content.split('\n');
    final result = <String>[];
    bool inImageSection = false;
    bool replaced = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.toLowerCase() == 'image:' || trimmed.toLowerCase().startsWith('image:')) {
        inImageSection = true;
        result.add(line);
        continue;
      }

      if (inImageSection && !replaced) {
        if (line.startsWith(' ') || line.startsWith('\t')) {
          final lower = trimmed.toLowerCase();
          if (lower.startsWith('tag:')) {
            final indent = line.substring(0, line.length - trimmed.length);
            result.add('${indent}Tag: $newTag');
            replaced = true;
            continue;
          }
        } else {
          inImageSection = false;
        }
      }

      result.add(line);
    }

    return result.join('\n');
  }

  /// 从 YAML 文件名推导项目名：`values-dc-order.yaml` → `dc-order`。
  /// 作为配置表的合并键，推导规则必须跨扫描稳定，且与原工具 `parse_projects_path`
  /// 配套逻辑保持一致（先剥扩展名，再剥 `values-` 前缀，均不可省略）。
  static String extractProjectName(String fileName) {
    String base = fileName.split('/').last;
    for (final ext in ['.yaml', '.yml']) {
      if (base.toLowerCase().endsWith(ext)) {
        base = base.substring(0, base.length - ext.length);
        break;
      }
    }
    if (base.startsWith('values-')) {
      base = base.substring('values-'.length);
    }
    return base;
  }

  /// 该文件名是否是服务文件：`values-` 前缀 + `.yaml` / `.yml` 结尾。
  ///
  /// 配置仓目录下同时存在 `Chart.yaml`、`demo.yaml`、`.gitlab-ci.yml` 与
  /// `templates/` 目录，它们都不是微服务，不得进入 Tag 配置表。
  static bool isServiceValueFile(String fileName) {
    final base = fileName.split('/').last;
    if (!base.toLowerCase().startsWith('values-')) return false;
    final lower = base.toLowerCase();
    return lower.endsWith('.yaml') || lower.endsWith('.yml');
  }

  // ==========================================================================
  // 配置仓路径解析
  // ==========================================================================

  /// 解析 `/tree/<branch>/<dir...>` 形式的配置仓路径。
  /// 仓库名为空时回退为从 GitLab URL 尾段提取（支持 `https://host/group/repo`）。
  static ArgoCdRepoRef parseProjectsPath(String path, String gitlabUrl) {
    final parts = path.trim().replaceFirst(RegExp(r'^/'), '').split('/');

    final treeIdx = parts.indexWhere((p) => p == 'tree');
    if (treeIdx == -1 || treeIdx + 1 >= parts.length) {
      throw Exception('无法解析配置仓路径: $path（需要包含 /tree/<branch>）');
    }

    var repo = parts.sublist(0, treeIdx).join('/');
    final branch = parts[treeIdx + 1];
    final fileDir = treeIdx + 2 < parts.length
        ? parts.sublist(treeIdx + 2).join('/')
        : '';

    if (repo.isEmpty) {
      repo = _extractRepoFromUrl(gitlabUrl);
    }
    if (repo.isEmpty) {
      throw Exception('无法解析配置仓路径: 缺少仓库路径且无法从 GitLab URL 提取');
    }

    return ArgoCdRepoRef(repo: repo, branch: branch, fileDir: fileDir);
  }

  static String _extractRepoFromUrl(String gitlabUrl) {
    var url = gitlabUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final schemeIdx = url.indexOf('://');
    if (schemeIdx != -1) {
      final afterScheme = url.substring(schemeIdx + 3);
      final slashIdx = afterScheme.indexOf('/');
      if (slashIdx != -1) {
        return afterScheme.substring(slashIdx + 1);
      }
    }
    return '';
  }

  // ==========================================================================
  // 配置表合并与巡检
  // ==========================================================================

  static String tagId(String envId, String projectName) =>
      '${envId}_$projectName';

  /// 「刷新 Tag」的纯合并逻辑：以远程为基准重建配置行，按项目名保留用户已填写的
  /// 目标 Tag / 关闭提醒 / 启用状态。id 由 `envId_projectName` 推导，保证跨扫描稳定。
  static List<ArgoCDTag> mergeRemoteTags(
    String envId,
    List<ArgoCdYamlTag> remote,
    List<ArgoCDTag> existing,
  ) {
    final existingMap = {for (final t in existing) t.projectName: t};
    final stamp = _nowStamp();

    return [
      for (final y in remote)
        ArgoCDTag(
          id: tagId(envId, y.projectName),
          envId: envId,
          projectName: y.projectName,
          currentTag: y.currentTag,
          targetTag: existingMap[y.projectName]?.targetTag ?? '',
          muted: existingMap[y.projectName]?.muted ?? false,
          enabled: existingMap[y.projectName]?.enabled ?? true,
          lastChecked: stamp,
        ),
    ];
  }

  /// 巡检写回时重建的行：只更新当前 Tag 与最后检查时间，
  /// 目标 Tag / 关闭提醒 / 启用状态一律沿用已有配置（无已有行时 target 由调用方指定）。
  static ArgoCDTag buildUpsertTag(
    ArgoCDTag? stored,
    String envId,
    String projectName,
    String current,
    String? target,
  ) {
    return ArgoCDTag(
      id: tagId(envId, projectName),
      envId: envId,
      projectName: projectName,
      currentTag: current,
      targetTag: target,
      muted: stored?.muted ?? false,
      enabled: stored?.enabled ?? true,
      lastChecked: _nowStamp(),
    );
  }

  GitLabClient createGitLabClient(ArgoCDEnvironment env) {
    final config = GitlabConfig(
      url: env.gitlabUrl,
      username: env.gitlabUsername ?? '',
      password: env.gitlabPassword ?? '',
      token: env.gitlabToken,
    );
    return GitLabClient(config);
  }

  /// 拉取配置仓内全部服务文件的 Image Tag（已分页遍历）。
  ///
  /// 目录下每个 `values-<服务名>.yaml` 对应一个微服务；`Chart.yaml`、`demo.yaml`、
  /// `.gitlab-ci.yml` 与目录条目不是服务文件，必须排除——否则它们会出现在
  /// Tag 配置表里，成为既无目标 Tag 也无法锁定的空行。
  Future<ArgoCdTagScanResult> listYamlTags(ArgoCDEnvironment env) async {
    final ref = parseProjectsPath(env.projectsPath, env.gitlabUrl);
    final client = createGitLabClient(env);
    await client.ensureToken();
    final projectId = await client.resolveProjectId(ref.repo);

    final files = await client.listRepositoryFiles(
      projectId: projectId,
      path: ref.fileDir,
      ref: ref.branch,
    );

    final serviceFiles = <RepoFile>[];
    var skipped = 0;
    for (final f in files) {
      if (f.type == 'tree') {
        skipped++;
        continue;
      }
      if (!isServiceValueFile(f.name)) {
        skipped++;
        continue;
      }
      serviceFiles.add(f);
    }

    // 兜底校验：目录明明有条目却没有任何服务文件。两种情形的修法完全不同，
    // 文案必须分开——历史上混为一谈会把「请求构造丢了 path」表述成用户配置错误。
    if (files.isNotEmpty && serviceFiles.isEmpty) {
      if (ref.fileDir.isEmpty) {
        throw Exception(
          '未指定子目录：列举请求退化为列举仓库根目录，在 ${files.length} 个条目中'
          '未找到任何 values-*.yaml 服务文件。这通常是请求构造问题而非配置问题，'
          '请检查「配置仓项目路径」是否形如 /tree/<分支>/<子目录>。',
        );
      }
      throw Exception(
        '已限定子目录 ${ref.fileDir}（分支 ${ref.branch}），但该目录下未找到任何 '
        'values-*.yaml 服务文件（共 ${files.length} 个条目）。'
        '请确认目录下存在 values-*.yaml，或分支名是否正确。',
      );
    }

    final results = <ArgoCdYamlTag>[];
    final failures = <ArgoCdTagReadFailure>[];
    for (final f in serviceFiles) {
      try {
        final content = await client.readFile(projectId, f.path, ref.branch);
        results.add(ArgoCdYamlTag(
          projectName: extractProjectName(f.name),
          filePath: f.path,
          currentTag: extractImageTag(content) ?? '',
        ));
      } catch (e) {
        failures.add(ArgoCdTagReadFailure(
          filePath: f.path,
          reason: e.toString().replaceFirst('Exception: ', ''),
        ));
      }
    }

    return ArgoCdTagScanResult(
      tags: results,
      failures: failures,
      skippedNonServiceFiles: skipped,
    );
  }

  /// 拉取 + 合并 + 落库：保留用户填写的目标 Tag / 关闭提醒 / 启用状态。
  Future<ArgoCdTagScanResult> refreshEnvTags(
    ArgoCDEnvironment env,
    List<ArgoCDTag> existing,
  ) async {
    final scan = await listYamlTags(env);
    await persistMergedTags(env.id, scan.tags, existing);
    return scan;
  }

  /// 以远程结果与既有配置合并后全量落库。
  Future<List<ArgoCDTag>> persistMergedTags(
    String envId,
    List<ArgoCdYamlTag> remote,
    List<ArgoCDTag> existing,
  ) async {
    final merged = mergeRemoteTags(envId, remote, existing);
    await OpsDatabase.instance.saveArgoCdTags(envId, merged);
    return merged;
  }

  /// 后台巡检入口：比对远程 Tag 与配置表目标 Tag，写回当前 Tag 并推送变更事件。
  ///
  /// 仅对 `enabled` 且 `target_tag` 非空的行比对；`muted` 行跳过通知与事件，
  /// 但仍更新当前 Tag。返回值为「需要提醒」的变更列表（供通知通道消费）。
  Future<List<ArgoCdChangeEvent>> checkEnvironment(ArgoCDEnvironment env) async {
    final stored = await OpsDatabase.instance.loadArgoCdTags(env.id);
    final storedMap = {for (final t in stored) t.projectName: t};

    final remote = (await listYamlTags(env)).tags;
    final events = <ArgoCdChangeEvent>[];

    for (final y in remote) {
      final storedTag = storedMap[y.projectName];
      final target = storedTag?.targetTag ?? '';
      final muted = storedTag?.muted ?? false;
      final enabled = storedTag?.enabled ?? true;

      // 未配置目标 Tag：仅记录当前值
      if (target.trim().isEmpty) {
        await _upsertCurrent(storedTag, env.id, y.projectName, y.currentTag, null);
        continue;
      }

      // 已停用：仅更新当前 Tag
      if (!enabled) {
        await _upsertCurrent(storedTag, env.id, y.projectName, y.currentTag, target);
        continue;
      }

      if (y.currentTag.isEmpty || y.currentTag == target) continue;

      var current = y.currentTag;
      var restored = false;

      if (env.monitorMode == 'lock') {
        // 锁定模式：回写配置仓并重新读取回写后的实际值
        final reRead = await _restoreLock(env, y.filePath, target);
        if (reRead != null) {
          restored = true;
          current = reRead;
        }
      }

      await _upsertCurrent(storedTag, env.id, y.projectName, current, target);

      if (muted) continue;

      final event = ArgoCdChangeEvent(
        envId: env.id,
        envName: env.name,
        projectName: y.projectName,
        currentTag: current,
        targetTag: target,
        monitorMode: env.monitorMode,
        restored: restored,
      );
      events.add(event);
      _changeController.add(event);
    }

    return events;
  }

  /// 锁定模式回写。成功返回重新读取到的实际 Tag，失败返回 null。
  Future<String?> _restoreLock(
    ArgoCDEnvironment env,
    String filePath,
    String target,
  ) async {
    try {
      final ref = parseProjectsPath(env.projectsPath, env.gitlabUrl);
      final client = createGitLabClient(env);
      await client.ensureToken();
      final projectId = await client.resolveProjectId(ref.repo);

      final content = await client.readFile(projectId, filePath, ref.branch);
      final updated = replaceImageTag(content, target);
      await client.updateFile(
        projectId,
        filePath,
        updated,
        ref.branch,
        'chore: update image tag to $target',
      );

      final reRead = await client.readFile(projectId, filePath, ref.branch);
      return extractImageTag(reRead);
    } catch (_) {
      return null;
    }
  }

  /// 单行 upsert：仅更新当前 Tag 与最后检查时间，不清空用户配置。
  /// 巡检一律走此方法，禁止 delete-then-insert 全量替换。
  Future<void> _upsertCurrent(
    ArgoCDTag? stored,
    String envId,
    String projectName,
    String current,
    String? target,
  ) async {
    await OpsDatabase.instance
        .updateArgoCdTag(buildUpsertTag(stored, envId, projectName, current, target));
  }

  static String _nowStamp() => DateTime.now().toIso8601String();
}
