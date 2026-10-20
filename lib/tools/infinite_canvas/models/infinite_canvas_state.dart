import 'package:flutter/foundation.dart' show immutable;

/// 容器运行状态（spec: 容器启停与状态呈现）。
enum InfiniteCanvasStatus {
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

  /// 失败，[InfiniteCanvasState.failure] 非空。
  failed('失败');

  final String label;
  const InfiniteCanvasStatus(this.label);
}

/// 失败类别（spec: 容器启停与状态呈现 / 镜像入口与失败诊断）。
///
/// 每一类都对应一个**用户能执行的动作**，而不是把 docker 的原始输出转述一遍。
enum InfiniteCanvasFailureKind {
  /// Docker 守护进程不可达。
  dockerUnavailable('Docker 未运行'),

  /// 工程目录不存在或缺少 `Dockerfile` / compose 文件。
  projectNotFound('未找到 Compose 工程'),

  /// 端口被占用（工作台端口或资产桥端口）。
  portConflict('端口被占用'),

  /// 健康探测超时。
  healthTimeout('服务未就绪'),

  /// 容器启动或停止过程本身失败。
  composeFailed('容器操作失败'),

  /// 镜像不存在，需要先拉取或构建。
  buildRequired('镜像未拉取'),

  /// 构建失败（分类见 `InfiniteCanvasBuildFailureKind`）。
  buildFailed('构建失败'),

  /// 其他未分类错误。
  unknown('未知错误');

  final String label;
  const InfiniteCanvasFailureKind(this.label);
}

/// 构建失败类别（spec: 镜像入口与失败诊断）。
///
/// 与 Toonflow 版的差异：删掉了 bun 锁文件条目（上游 Dockerfile 用的包管理
/// 器不同，且默认路径根本不本地构建），新增「构建上下文缺失」——本地没有
/// 仓库时点「构建镜像」是常见误操作。
enum InfiniteCanvasBuildFailureKind {
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

  /// 本地没有仓库，无法构建。
  missingContext(
    '缺少构建上下文',
    '本地构建需要工程目录完整（含 web/ 与 Dockerfile）。若你只是想用已发布'
    '的版本，直接点「启动」即可——默认会从 ghcr.io 拉取镜像。',
  ),

  /// 工程定位失败。
  projectNotFound(
    '未找到 Compose 工程',
    '请先在设置中配置正确的无限画布仓库目录。',
  ),

  /// 未分类失败：回退展示原始输出尾部。
  unknown('构建失败', '请查看下方构建日志定位原因。');

  final String label;

  /// 给用户的可操作建议。
  final String hint;

  const InfiniteCanvasBuildFailureKind(this.label, this.hint);
}

/// 引擎的当前状态快照。
@immutable
class InfiniteCanvasState {
  const InfiniteCanvasState({
    this.status = InfiniteCanvasStatus.idle,
    this.failure,
    this.failureKind,
    this.failureDetail,
    this.containerLogTail = const <String>[],
  });

  const InfiniteCanvasState.initial() : this();

  final InfiniteCanvasStatus status;

  /// 失败类别；[status] 为 [InfiniteCanvasStatus.failed] 时非空。
  final InfiniteCanvasFailureKind? failureKind;

  /// 一行摘要（面向用户）。
  final String? failure;

  /// 详细原因（面向排障）。
  final String? failureDetail;

  /// 容器日志尾部（启动失败时附上，帮助定位）。
  final List<String> containerLogTail;

  /// 是否有任务在跑（启动中 / 停止中）。UI 用它禁用按钮防止重复触发。
  bool get isBusy =>
      status == InfiniteCanvasStatus.starting ||
      status == InfiniteCanvasStatus.stopping;

  /// 是否已就绪。只有它就绪后才能打开工作台。
  bool get isRunning => status == InfiniteCanvasStatus.running;

  /// 是否可以打开工作台。
  bool get canOpenWorkspace => isRunning;

  InfiniteCanvasState copyWith({
    InfiniteCanvasStatus? status,
    InfiniteCanvasFailureKind? failureKind,
    String? failure,
    String? failureDetail,
    List<String>? containerLogTail,
    bool clearFailure = false,
  }) {
    return InfiniteCanvasState(
      status: status ?? this.status,
      failureKind: clearFailure ? null : (failureKind ?? this.failureKind),
      failure: clearFailure ? null : (failure ?? this.failure),
      failureDetail: clearFailure ? null : (failureDetail ?? this.failureDetail),
      containerLogTail: containerLogTail ?? this.containerLogTail,
    );
  }
}
