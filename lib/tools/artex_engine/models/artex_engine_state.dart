/// ARTEX 引擎工具的状态模型。
///
/// 状态机（design D5）：
///
///   idle ──start()──▶ starting ──健康探测通过──▶ running
///                      │                          │
///                      │超时/失败                 │stop()
///                      ▼                          ▼
///                   failed(reason) ◀──stop()失败── stopping
///                      │                          │
///                      │                          ▼
///                      └──────start()────────▶ stopped
///
/// 不变量：
/// - `failed` 必须带原因（spec「容器启停与状态呈现」：失败要保留原因供修正后重试）
/// - 只有 `running` 才允许打开工作台（spec「打开引擎工作台」）
/// - `starting` 期间重复触发 start 是空操作，不重入
library;

/// 容器生命周期状态。
enum ArtexEngineStatus {
  /// 初始状态，未启动过。
  idle,

  /// 启动中：容器已拉起，正在等待健康探测通过。
  starting,

  /// 运行中且已就绪。
  running,

  /// 停止中。
  stopping,

  /// 已停止（用户主动停止，或启动成功前从未运行）。
  stopped,

  /// 失败，[ArtexEngineState.failure] 非空。
  failed,
}

/// 失败类别。用于把底层错误映射为可操作的 UI 提示（spec 各条要求的
/// 「报告可读原因」），而不是把 docker / 网络的原始输出丢给用户。
enum ArtexEngineFailureKind {
  /// Docker 守护进程不可达（未启动或正在启动中还没就绪）。
  dockerUnavailable('Docker 未运行'),

  /// Compose 工程目录不存在或缺少 docker-compose.yml。
  projectNotFound('未找到 Compose 工程'),

  /// 端口被占用。
  portConflict('端口被占用'),

  /// 健康探测超时（引擎起来了但没返回预期响应）。
  healthTimeout('引擎未就绪'),

  /// 健康探测收到 200 但内容是门控的假欢迎页。
  gateBlocked('引擎被伪装门控拦截'),

  /// 容器启动或停止过程本身失败。
  composeFailed('容器操作失败'),

  /// 其他未分类错误。
  unknown('未知错误');

  const ArtexEngineFailureKind(this.label);

  /// 给用户看的一行摘要。
  final String label;
}

/// 引擎的当前状态快照。
class ArtexEngineState {
  const ArtexEngineState({
    this.status = ArtexEngineStatus.idle,
    this.failure,
    this.failureKind,
    this.failureDetail,
    this.containerLogTail = const <String>[],
  });

  /// 初始状态。
  const ArtexEngineState.initial() : this();

  final ArtexEngineStatus status;

  /// 失败类别；[status] 为 [ArtexEngineStatus.failed] 时非空。
  final ArtexEngineFailureKind? failureKind;

  /// 一行摘要（面向用户）。
  final String? failure;

  /// 详细原因（容器日志尾部、具体端口号等），可展开查看。
  final String? failureDetail;

  /// 失败时附带的容器日志尾部，供定位。
  final List<String> containerLogTail;

  bool get isRunning => status == ArtexEngineStatus.running;
  bool get isBusy =>
      status == ArtexEngineStatus.starting ||
      status == ArtexEngineStatus.stopping;

  /// 是否允许打开工作台。只有真正就绪才允许——被门控拦截的假 200 不算
  /// （spec「健康就绪判定必须校验响应体」）。
  bool get canOpenWorkspace => status == ArtexEngineStatus.running;

  ArtexEngineState copyWith({
    ArtexEngineStatus? status,
    ArtexEngineFailureKind? failureKind,
    String? failure,
    String? failureDetail,
    List<String>? containerLogTail,
    bool clearFailure = false,
  }) {
    return ArtexEngineState(
      status: status ?? this.status,
      // clearFailure 用于「确实要清空」的场景。可空字段的 copyWith 无法用
      // 传 null 表达清除（null 会被当作「不修改」），这是 Dart copyWith 的
      // 固有歧义，用显式开关绕过。
      failureKind: clearFailure ? null : (failureKind ?? this.failureKind),
      failure: clearFailure ? null : (failure ?? this.failure),
      failureDetail: clearFailure ? null : (failureDetail ?? this.failureDetail),
      containerLogTail: containerLogTail ?? this.containerLogTail,
    );
  }

  /// 清空失败信息的状态副本（重试前调用）。
  ArtexEngineState cleared() => copyWith(
    status: ArtexEngineStatus.idle,
    clearFailure: true,
    containerLogTail: const <String>[],
  );
}
