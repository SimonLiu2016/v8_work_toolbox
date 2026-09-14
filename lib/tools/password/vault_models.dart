/// Vault 条目模型（明文元数据 + 加密 secret 引用）
///
/// 设计 D3：元数据（title/url/username/tags/timestamps）明文存储供搜索；
/// secret 字段（password/totpSeed/noteBody）仅存于加密 blob，以 secretRef 关联。
library;

enum VaultEntryType { login, note, totp }

class VaultItem {
  final String id;
  final VaultEntryType type;
  final String title;
  final String url;
  final String username;
  final List<String> tags;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime passwordUpdatedAt;

  /// 加密 blob 中的 secret 引用键（不含明文）
  final String secretRef;

  const VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.url = '',
    this.username = '',
    this.tags = const [],
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    required this.passwordUpdatedAt,
    required this.secretRef,
  });

  VaultItem copyWith({
    String? title,
    String? url,
    String? username,
    List<String>? tags,
    String? notes,
    DateTime? updatedAt,
    DateTime? passwordUpdatedAt,
  }) {
    return VaultItem(
      id: id,
      type: type,
      title: title ?? this.title,
      url: url ?? this.url,
      username: username ?? this.username,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
      secretRef: secretRef,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'url': url,
        'username': username,
        'tags': tags,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'passwordUpdatedAt': passwordUpdatedAt.toIso8601String(),
        'secretRef': secretRef,
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return VaultItem(
      id: json['id'] as String,
      type: VaultEntryType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'login'),
        orElse: () => VaultEntryType.login,
      ),
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      notes: json['notes'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      passwordUpdatedAt:
          DateTime.tryParse(json['passwordUpdatedAt'] as String? ?? '') ?? now,
      secretRef: json['secretRef'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VaultItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 加密 blob 中单个条目的 secret 内容
class VaultSecret {
  /// login 类型的密码 / note 类型的正文
  final String secret;

  /// totp 类型的 Base32 seed（可为空）
  final String totpSeed;

  const VaultSecret({this.secret = '', this.totpSeed = ''});

  bool get isEmpty => secret.isEmpty && totpSeed.isEmpty;

  Map<String, dynamic> toJson() => {
        'secret': secret,
        'totpSeed': totpSeed,
      };

  factory VaultSecret.fromJson(Map<String, dynamic> json) => VaultSecret(
        secret: json['secret'] as String? ?? '',
        totpSeed: json['totpSeed'] as String? ?? '',
      );
}
