import 'package:flutter/foundation.dart' show immutable;

/// 容器运行状态（spec: 容器启停与状态呈现）。
enum ToonflowStatus {
  /// 初始状态，未启动过。
  idle('未启动'),

  /// 启动中：容器已拉起，正在等待健康探测通过。
  starting('启动中…'),

  /// 运行中且已就绪。
  running('运行中'),

  /// 停止中。
  stopping('停止中…'),

  /// 已停止。
  stopped('已停止'),

  /// 失败，[ToonflowStudioState.failure] 非空。
  failed('失败');

  final String label;
  const ToonflowStatus(this.label);
}

/// 失败类别（spec: 容器启停与状态呈现 / 镜像构建入口与失败诊断）。
///
/// 每一类都对应一个**用户能执行的动作**，而不是把 docker 的原始输出转述一遍。
enum ToonflowFailureKind {
  /// Docker 守护进程不可达。
  dockerUnavailable('Docker 未运行'),

  /// 工程目录不存在或缺少 `Dockerfile` / `compose.yaml`。
  projectNotFound('未找到 Compose 工程'),

  /// 端口被占用。
  portConflict('端口被占用'),

  /// 健康探测超时。
  healthTimeout('服务未就绪'),

  /// 容器启动或停止过程本身失败。
  composeFailed('容器操作失败'),

  /// 镜像不存在，需要先构建。
  buildRequired('镜像未构建'),

  /// 构建失败（分类见 `ToonflowBuildFailureKind`）。
  buildFailed('构建失败'),

  /// 其他未分类错误。
  unknown('未知错误');

  final String label;
  const ToonflowFailureKind(this.label);
}

/// 构建失败类别（spec: 镜像构建入口与失败诊断）。
///
/// spike 实测：首次构建真的失败了，死在中美网络不通导致的 TLS 握手超时。
/// 所以这一类的 hint 必须是可执行的——指向 Docker 的镜像源配置。
enum ToonflowBuildFailureKind {
  /// Docker 守护进程不可达。
  dockerUnavailable(
    'Docker 未运行',
    '请先启动 Docker Desktop 并等待其完全就绪，然后重试。',
  ),

  /// 镜像源不可达 / 返回 403。
  registryBlocked(
    '镜像源不可达',
    '拉取基础镜像失败。Docker Hub 在国内通常不可直连——请在 '
    'Docker Desktop → Settings → Docker Engine 中配置 registry-mirrors'
    '（国内镜像源），然后重试。',
  ),

  /// 网络超时（含 TLS 握手超时）。
  networkTimeout(
    '网络不通',
    '拉取镜像或下载依赖超时。请检查 VPN / 代理后重试——已完成的构建层'
    '有缓存，重试不会从零开始。',
  ),

  /// `bun install --frozen-lockfile` 失败。
  lockfileMismatch(
    '依赖锁文件不匹配',
    '`bun install --frozen-lockfile` 失败，通常是 bun.lock 与 package.json '
    '不同步。请在 Toonflow 仓库执行 `bun install` 后重试，或修改 bun 镜像站'
    '配置。',
  ),

  /// 缺少 compose 要求的环境变量。
  missingEnv(
    '缺少环境变量配置',
    'Docker Compose 要求的环境变量未设置。',
  ),

  /// 工程定位失败。
  projectNotFound(
    '未找到 Compose 工程',
    '请先在设置中配置正确的 Toonflow 仓库目录。',
  ),

  /// 未分类失败：回退展示原始输出尾部。
  unknown('构建失败', '请查看下方构建日志定位原因。');

  final String label;

  /// 给用户的可操作建议。
  final String hint;

  const ToonflowBuildFailureKind(this.label, this.hint);
}

/// 引擎的当前状态快照。
@immutable
class ToonflowStudioState {
  const ToonflowStudioState({
    this.status = ToonflowStatus.idle,
    this.failure,
    this.failureKind,
    this.failureDetail,
    this.containerLogTail = const <String>[],
  });

  const ToonflowStudioState.initial() : this();

  final ToonflowStatus status;

  /// 失败类别；[status] 为 [ToonflowStatus.failed] 时非空。
  final ToonflowFailureKind? failureKind;

  /// 一行摘要（面向用户）。
  final String? failure;

  /// 详细原因（面向排障）。
  final String? failureDetail;

  /// 容器日志尾部（启动失败时附上，帮助定位）。
  final List<String> containerLogTail;

  /// 是否有任务在跑（启动中 / 停止中）。UI 用它禁用按钮防止重复触发。
  bool get isBusy =>
      status == ToonflowStatus.starting || status == ToonflowStatus.stopping;

  /// 是否已就绪。只有它就绪后才能打开工作台。
  bool get isRunning => status == ToonflowStatus.running;

  /// 是否可以打开工作台。
  bool get canOpenWorkspace => isRunning;

  ToonflowStudioState copyWith({
    ToonflowStatus? status,
    ToonflowFailureKind? failureKind,
    String? failure,
    String? failureDetail,
    List<String>? containerLogTail,
    bool clearFailure = false,
  }) {
    return ToonflowStudioState(
      status: status ?? this.status,
      failureKind: clearFailure ? null : (failureKind ?? this.failureKind),
      failure: clearFailure ? null : (failure ?? this.failure),
      failureDetail: clearFailure ? null : (failureDetail ?? this.failureDetail),
      containerLogTail: containerLogTail ?? this.containerLogTail,
    );
  }
}
