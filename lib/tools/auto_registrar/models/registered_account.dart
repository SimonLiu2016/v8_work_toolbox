import 'package:uuid/uuid.dart';

class RegisteredAccount {
  final String id;
  final String platform; // 'outlook' | 'hotmail' | ...
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String birthDate;
  final String? recoveryEmail;
  final String? recoveryPhone;
  final String? proxyUsed;
  final String status; // 'SUCCESS' | 'FAILED' | 'REGISTERING'
  final DateTime createdAt;
  final String? errorLog;
  final bool verified;
  final DateTime? verifiedAt;

  RegisteredAccount({
    String? id,
    this.platform = 'outlook',
    required this.email,
    required this.password,
    this.firstName = '',
    this.lastName = '',
    this.birthDate = '',
    this.recoveryEmail,
    this.recoveryPhone,
    this.proxyUsed,
    this.status = 'SUCCESS',
    DateTime? createdAt,
    this.errorLog,
    this.verified = false,
    this.verifiedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  RegisteredAccount copyWith({
    String? id,
    String? platform,
    String? email,
    String? password,
    String? firstName,
    String? lastName,
    String? birthDate,
    String? recoveryEmail,
    String? recoveryPhone,
    String? proxyUsed,
    String? status,
    DateTime? createdAt,
    String? errorLog,
    bool? verified,
    DateTime? verifiedAt,
  }) {
    return RegisteredAccount(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      email: email ?? this.email,
      password: password ?? this.password,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      birthDate: birthDate ?? this.birthDate,
      recoveryEmail: recoveryEmail ?? this.recoveryEmail,
      recoveryPhone: recoveryPhone ?? this.recoveryPhone,
      proxyUsed: proxyUsed ?? this.proxyUsed,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      errorLog: errorLog ?? this.errorLog,
      verified: verified ?? this.verified,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'platform': platform,
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'birthDate': birthDate,
        'recoveryEmail': recoveryEmail,
        'recoveryPhone': recoveryPhone,
        'proxyUsed': proxyUsed,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'errorLog': errorLog,
        'verified': verified,
        'verifiedAt': verifiedAt?.toIso8601String(),
      };

  factory RegisteredAccount.fromJson(Map<String, dynamic> json) {
    return RegisteredAccount(
      id: json['id'] as String?,
      platform: (json['platform'] as String?) ?? 'outlook',
      email: (json['email'] as String?) ?? '',
      password: (json['password'] as String?) ?? '',
      firstName: (json['firstName'] as String?) ?? '',
      lastName: (json['lastName'] as String?) ?? '',
      birthDate: (json['birthDate'] as String?) ?? '',
      recoveryEmail: json['recoveryEmail'] as String?,
      recoveryPhone: json['recoveryPhone'] as String?,
      proxyUsed: json['proxyUsed'] as String?,
      status: (json['status'] as String?) ?? 'SUCCESS',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      errorLog: json['errorLog'] as String?,
      verified: (json['verified'] as bool?) ?? false,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String)
          : null,
    );
  }
}
