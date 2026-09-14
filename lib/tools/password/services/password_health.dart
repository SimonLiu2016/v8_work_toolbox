import '../vault_models.dart';

/// 密码体检（设计 D8：zxcvbn 风格简化本地评分，纯本地无网络）
///
/// 评分维度：长度、字符多样性、常见模式（字典词/序列/重复/日期）
/// 0–100 分，分档：0–40 弱 / 40–70 中 / 70+ 强
class PasswordHealth {
  static const int weakThreshold = 40;
  static const int strongThreshold = 70;
  static const int ageWarningDays = 180;

  /// 评分单个密码（0–100）
  int score(String password) {
    if (password.isEmpty) return 0;

    var score = 0;

    // 长度分（最多 40）
    final len = password.length;
    if (len >= 16) {
      score += 40;
    } else if (len >= 12) {
      score += 32;
    } else if (len >= 8) {
      score += 22;
    } else {
      score += len * 2;
    }

    // 字符多样性（最多 30）
    var classes = 0;
    if (password.contains(RegExp(r'[a-z]'))) classes++;
    if (password.contains(RegExp(r'[A-Z]'))) classes++;
    if (password.contains(RegExp(r'[0-9]'))) classes++;
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) classes++;
    score += classes * 7;
    if (classes == 4) score += 2;

    // 熵估计加成（最多 10）：唯一字符占比
    final uniqueRatio = password.split('').toSet().length / len;
    score += (uniqueRatio * 10).round();

    // 模式惩罚
    score -= _patternPenalty(password);

    return score.clamp(0, 100).toInt();
  }

  /// 分档标签
  String band(int score) {
    if (score < weakThreshold) return 'weak';
    if (score < strongThreshold) return 'medium';
    return 'strong';
  }

  int _patternPenalty(String password) {
    var penalty = 0;
    final lower = password.toLowerCase();

    // 纯数字或纯字母
    if (RegExp(r'^[0-9]+$').hasMatch(password)) penalty += 25;
    if (RegExp(r'^[a-zA-Z]+$').hasMatch(password)) penalty += 12;

    // 常见弱密码
    const weak = [
      'password', '123456', 'qwerty', 'admin', 'letmein', 'welcome',
      'abc123', '111111', 'iloveyou', 'monkey', 'dragon', 'master',
    ];
    for (final w in weak) {
      if (lower.contains(w)) {
        penalty += 30;
        break;
      }
    }

    // 连续序列（abc/bcd/123/234…长度≥4）
    penalty += _sequencePenalty(password);

    // 重复子串（如 abcabc、1212）
    if (RegExp(r'(.{2,})\1').hasMatch(lower)) penalty += 15;

    // 键盘行走（qwerty/asdf 片段）
    const walks = ['qwer', 'wert', 'asdf', 'sdfg', 'zxcv', 'xcvb'];
    for (final w in walks) {
      if (lower.contains(w)) {
        penalty += 12;
        break;
      }
    }

    // 年份（19xx/20xx）
    if (RegExp(r'(19|20)\d{2}').hasMatch(password)) penalty += 8;

    return penalty.clamp(0, 60).toInt();
  }

  int _sequencePenalty(String password) {
    final lower = password.toLowerCase();
    var maxRun = 1;
    var run = 1;
    for (var i = 1; i < lower.length; i++) {
      final prev = lower.codeUnitAt(i - 1);
      final curr = lower.codeUnitAt(i);
      if (curr == prev + 1) {
        run++;
        if (run > maxRun) maxRun = run;
      } else {
        run = 1;
      }
    }
    if (maxRun >= 5) return 20;
    if (maxRun >= 4) return 12;
    return 0;
  }

  /// 重复密码聚类：返回 password → 使用该密码的条目 id 列表（仅 ≥2 条的）
  Map<String, List<String>> findDuplicates(
    Map<String, String> itemIdToPassword,
  ) {
    final byPassword = <String, List<String>>{};
    itemIdToPassword.forEach((id, password) {
      if (password.isEmpty) return;
      byPassword.putIfAbsent(password, () => []).add(id);
    });
    byPassword.removeWhere((_, ids) => ids.length < 2);
    return byPassword;
  }

  /// 年龄超标的条目（passwordUpdatedAt 距今 > ageWarningDays）
  List<VaultItem> findAged(List<VaultItem> items, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    return items.where((item) {
      if (item.type != VaultEntryType.login) return false;
      return ref.difference(item.passwordUpdatedAt).inDays > ageWarningDays;
    }).toList();
  }
}

/// 体检报告
class HealthReport {
  final List<WeakPasswordEntry> weak;
  final List<DuplicateGroup> duplicates;
  final List<VaultItem> aged;

  const HealthReport({
    required this.weak,
    required this.duplicates,
    required this.aged,
  });

  int get totalIssues =>
      weak.length +
      duplicates.fold<int>(0, (sum, g) => sum + g.itemIds.length) +
      aged.length;
}

class WeakPasswordEntry {
  final String itemId;
  final String title;
  final int score;

  const WeakPasswordEntry({
    required this.itemId,
    required this.title,
    required this.score,
  });
}

class DuplicateGroup {
  final List<String> itemIds;
  final List<String> titles;

  const DuplicateGroup({required this.itemIds, required this.titles});
}
