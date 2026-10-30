/// 文稿中的 IT 术语高亮。
///
/// 目标是让用户**不用逐字扫描**就能定位术语——把技术词用强调色标出，
/// 其余保持普通文字色。文稿在精听模式里按需展开，术语高亮是它最核心的
/// 视觉价值。
library;

import 'package:flutter/material.dart';

/// 一个词单元（词 + 在原文中的起止位置）。
class _Token {
  final String text;
  final int start;
  final int end;
  const _Token(this.text, this.start, this.end);
}

/// IT 术语集合。
///
/// 词表来自 CoderSlingo 的开放数据集（CC-BY 4.0）与本工具的关键词表。
/// 命中按**词边界**匹配，避免 `test` 命中 `latest` 这类子串误报。
class TermHighlighter {
  /// 术语词表（小写）。
  static final Set<String> _terms = _buildTerms();

  /// 词表里最长的术语有几个词（用于 n-gram 匹配的上限）。
  static final int _maxTermWords = _computeMaxWords();

  static Set<String> _buildTerms() {
    const base = <String>{
      // 会议与流程
      'standup', 'stand-up', 'retro', 'retrospective', 'sprint', 'backlog',
      'blocker', 'blocked', 'scrum', 'planning', 'demo', 'review',
      'postmortem', 'post-mortem', 'handoff', 'onboarding', 'async', 'sync',
      'action item', 'timebox', 'velocity', 'story point', 'definition of done',
      // 部署与运维
      'deploy', 'deployment', 'deploying', 'rollback', 'roll back', 'hotfix',
      'hot fix', 'release', 'canary', 'staging', 'production', 'prod',
      'rollback plan', 'outage', 'incident', 'sev-1', 'sev1',
      'monitoring', 'alerting', 'alert', 'dashboard', 'metric', 'slo', 'sla',
      'latency', 'throughput', 'downtime', 'mitigation', 'root cause',
      // 代码与架构
      'code review', 'pull request', 'pr', 'merge', 'conflict', 'regression',
      'refactor', 'refactoring', 'legacy', 'technical debt', 'api', 'sdk',
      'endpoint', 'microservice', 'monolith', 'idempotent', 'idempotency',
      'circuit breaker', 'load balancer', 'cache', 'caching', 'database',
      'schema', 'migration', 'dependency', 'dependencies', 'trade-off',
      'trade off', 'scope creep', 'architecture', 'repository',
      'pipeline', 'ci', 'cd', 'cicd', 'build', 'test', 'tests', 'testing',
      'flaky test', 'unit test', 'integration test', 'coverage', 'lint',
      'formatting', 'tech debt',
      // 数据与指标
      'percentile', 'p99', 'p95', 'uptime',
      'scalability', 'redundancy', 'failover', 'partition', 'sharding',
      'replication', 'transaction', 'consistency', 'eventual consistency',
      // 通用职场
      'impediment', 'workaround', 'follow up', 'follow-up',
      'actionable', 'scope', 'priority', 'estimate', 'capacity', 'spike',
      'ticket', 'jira', 'severity', 'p1', 'p2', 'p3',
    };
    return base.map((e) => e.toLowerCase()).toSet();
  }

  static int _computeMaxWords() {
    var max = 1;
    for (final t in _terms) {
      final n = t.split(' ').length;
      if (n > max) max = n;
    }
    return max;
  }

  /// 把文本切成词单元（保留原位置，供高亮用）。
  ///
  /// 每个词单元是**单个词**（连续的字母数字，或以连字符连接的词段，如
  /// `post-mortem`）。多词术语（`flaky test`）由 [_matchTerms] 的 n-gram
  /// 逻辑在**相邻词单元**上拼出来。
  ///
  /// 注意：不能用 `word(?:[ -]word)*` 这种"贪婪吞空格"的正则——它会把
  /// 整句 "We need a Hotfix and a Rollback" 吞成一个词单元。
  static List<_Token> _tokenize(String text) {
    final tokens = <_Token>[];
    final pattern = RegExp(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*");
    for (final m in pattern.allMatches(text)) {
      tokens.add(_Token(m.group(0)!, m.start, m.end));
    }
    return tokens;
  }

  /// 贪心 n-gram 匹配：优先匹配更长的术语。
  ///
  /// `The flaky test in the pipeline` 必须命中 `flaky test` 而不是
  /// `flaky` + `test` 两个独立词——前者才是用户要找的术语。
  static List<({int start, int end, String word})> _matchTerms(String text) {
    final tokens = _tokenize(text);
    final hits = <({int start, int end, String word})>[];
    var i = 0;
    while (i < tokens.length) {
      var matched = false;
      // 从最长候选往回试
      for (var n = _maxTermWords; n >= 1; n--) {
        if (i + n > tokens.length) continue;
        final candidate = tokens
            .sublist(i, i + n)
            .map((t) => t.text)
            .join(' ')
            .toLowerCase()
            .replaceAll(RegExp(r'\s*-'), '-');
        if (!_terms.contains(candidate)) continue;
        hits.add((
          start: tokens[i].start,
          end: tokens[i + n - 1].end,
          word: text.substring(tokens[i].start, tokens[i + n - 1].end),
        ));
        i += n;
        matched = true;
        break;
      }
      if (!matched) i++;
    }
    return hits;
  }

  /// 在 [text] 中高亮 IT 术语。
  ///
  /// [active] 是术语的强调色，[base] 是普通文字色。
  static TextSpan highlight(String text,
      {required Color active, required Color base}) {
    if (text.isEmpty) {
      return TextSpan(text: text, style: TextStyle(color: base));
    }
    final hits = _matchTerms(text);
    if (hits.isEmpty) {
      return TextSpan(text: text, style: TextStyle(color: base));
    }
    final spans = <TextSpan>[];
    var last = 0;
    for (final hit in hits) {
      if (hit.start > last) {
        spans.add(TextSpan(text: text.substring(last, hit.start)));
      }
      spans.add(TextSpan(
        text: hit.word,
        style: TextStyle(color: active, fontWeight: FontWeight.w600),
      ));
      last = hit.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return TextSpan(style: TextStyle(color: base), children: spans);
  }

  /// 文本中命中的术语列表（供术语收藏使用）。
  static List<String> extractTerms(String text) {
    final found = <String>{};
    for (final hit in _matchTerms(text)) {
      found.add(hit.word);
    }
    return found.toList();
  }
}
