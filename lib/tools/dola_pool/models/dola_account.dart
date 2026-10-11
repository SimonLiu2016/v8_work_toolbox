/// Dola 账号生命周期状态。
enum DolaAccountStatus {
  /// 满额 (剩余点数 == 4 点，可出 1 条 2.0 或 2 条 2.5)
  full,

  /// 半额 (2 <= 剩余点数 < 4 点，只够出 1 条 2.5)
  half,

  /// 冷却 (剩余点数 <= 1，点数耗尽，等待东京时间 0 点重置)
  cooling,

  /// 生成中 (当前有任务占用该账号，同号互斥防打穿)
  busy,

  /// 风控 (遭遇 Cloudflare/滑块/拒绝，进入 30 分钟冷却隔离)
  risk,

  /// 异常 (多次无响应或连续失败，暂时熔断)
  abnormal,
}

/// Dola 平台账号模型。
class DolaAccount {
  final String id;
  final String name;
  final String sessionid;
  final String? proxyUrl; // 绑定的独立出海代理，如 http://127.0.0.1:7890
  final int points; // 当日剩余生成点数（默认 4 点）
  final int dailyLimit; // 每日最大点数（默认 4 点）
  final DolaAccountStatus status;
  final DateTime? lastUsedAt;
  final DateTime? cooldownUntil;
  final String? lastError;

  const DolaAccount({
    required this.id,
    required this.name,
    required this.sessionid,
    this.proxyUrl,
    this.points = 4,
    this.dailyLimit = 4,
    this.status = DolaAccountStatus.full,
    this.lastUsedAt,
    this.cooldownUntil,
    this.lastError,
  });

  bool get isAvailable {
    if (status == DolaAccountStatus.cooling ||
        status == DolaAccountStatus.busy ||
        status == DolaAccountStatus.risk ||
        status == DolaAccountStatus.abnormal) {
      if (cooldownUntil != null && DateTime.now().isAfter(cooldownUntil!)) {
        // 冷却已过期，允许重新探测/激活
        return points >= 2;
      }
      return false;
    }
    return points >= 2;
  }

  DolaAccount copyWith({
    String? id,
    String? name,
    String? sessionid,
    String? proxyUrl,
    int? points,
    int? dailyLimit,
    DolaAccountStatus? status,
    DateTime? lastUsedAt,
    DateTime? cooldownUntil,
    String? lastError,
  }) {
    return DolaAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      sessionid: sessionid ?? this.sessionid,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      points: points ?? this.points,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      status: status ?? this.status,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sessionid': sessionid,
      'proxyUrl': proxyUrl,
      'points': points,
      'dailyLimit': dailyLimit,
      'status': status.name,
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'cooldownUntil': cooldownUntil?.toIso8601String(),
      'lastError': lastError,
    };
  }

  factory DolaAccount.fromJson(Map<String, dynamic> json) {
    DolaAccountStatus status = DolaAccountStatus.full;
    final statusStr = json['status'] as String?;
    if (statusStr != null) {
      status = DolaAccountStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => DolaAccountStatus.full,
      );
    }

    return DolaAccount(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sessionid: json['sessionid'] as String? ?? '',
      proxyUrl: json['proxyUrl'] as String?,
      points: (json['points'] as num?)?.toInt() ?? 4,
      dailyLimit: (json['dailyLimit'] as num?)?.toInt() ?? 4,
      status: status,
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.tryParse(json['lastUsedAt'] as String)
          : null,
      cooldownUntil: json['cooldownUntil'] != null
          ? DateTime.tryParse(json['cooldownUntil'] as String)
          : null,
      lastError: json['lastError'] as String?,
    );
  }
}
