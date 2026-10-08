/// 威胁情报面板：CVE 列表、过滤、同步、AI 日报、资产命中高亮。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/security_session_controller.dart';
import '../services/intel_digest_scheduler.dart';
import '../services/digest_store.dart';
import '../services/intel_store.dart';
import '../services/threat_intel_services.dart';
import 'widgets.dart';

class ThreatIntelView extends StatefulWidget {
  final SecuritySessionController controller;
  final ThreatIntelRepository intelRepo;

  const ThreatIntelView({
    super.key,
    required this.controller,
    required this.intelRepo,
  });

  @override
  State<ThreatIntelView> createState() => _ThreatIntelViewState();
}

class _ThreatIntelViewState extends State<ThreatIntelView> {
  List<ThreatIntelEntry> _entries = const [];
  List<IntelMatch> _matches = const [];
  bool _loading = false;
  bool _syncing = false;
  String _keyword = '';
  String _severityFilter = 'all';
  bool _kevOnly = false;
  bool _pocOnly = false;
  String _digest = '';
  int _generatedFindings = 0;
  bool _generatingFindings = false;
  List<DigestRecord> _digestHistory = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadDigestHistory();
  }

  Future<void> _loadDigestHistory() async {
    final history = await DigestStore.instance.recent();
    if (!mounted) return;
    setState(() => _digestHistory = history);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await widget.intelRepo.all();
    final matches = IntelCrossMatcher.match(
      widget.controller.assetList,
      entries,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _matches = matches;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    widget.controller.log('开始同步威胁情报…');
    final result = await ThreatIntelSyncService(widget.intelRepo).sync(
      config: await IntelSettingsStore.instance.load(),
      onLog: widget.controller.log,
    );
    widget.controller.log('情报同步完成: ${result.written} 条');
    await _load();
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _generateDigest() async {
    final last24h = _entries.where(isWithin24h).toList();
    if (last24h.isEmpty) {
      setState(() => _digest = '过去 24 小时没有新漏洞情报，请先执行同步。');
      return;
    }
    setState(() => _digest = '生成中…');
    // 走调度器：它同时被每日 09:00 的定时任务复用，逻辑只有一份。
    final digest = await IntelDigestScheduler.instance.runOnce(
      repo: widget.intelRepo,
    );
    if (!mounted) return;
    if (digest == null) {
      setState(() => _digest = '生成失败：AI 未配置或网络不可用');
      return;
    }
    await DigestStore.instance.append(digest);
    await _loadDigestHistory();
    if (!mounted) return;
    setState(() => _digest = digest);
    widget.controller.pushAiMessage('assistant', digest);
  }

  List<ThreatIntelEntry> get _filtered {
    return _entries.where((e) {
      if (_kevOnly && !e.isKev) return false;
      if (_pocOnly && (e.pocUrl == null || e.pocUrl!.isEmpty)) return false;
      if (_severityFilter != 'all' && e.severity != _severityFilter) {
        return false;
      }
      if (_keyword.isNotEmpty) {
        final q = _keyword.toLowerCase();
        final hit =
            e.cveId.toLowerCase().contains(q) ||
            e.title.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q);
        if (!hit) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        // KEV 优先，然后 CVSS 降序。
        if (a.isKev != b.isKev) return a.isKev ? -1 : 1;
        final av = a.cvssScore ?? -1;
        final bv = b.cvssScore ?? -1;
        return bv.compareTo(av);
      });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '威胁情报',
          subtitle: 'NVD · CISA KEV · GitHub PoC · 资产交叉比对',
          trailing: [
            SmallActionButton(
              label: _syncing ? '同步中…' : '同步情报',
              icon: Icons.sync,
              onPressed: _syncing ? null : _sync,
            ),
            const SizedBox(width: AppTheme.space8),
            SmallActionButton(
              label: 'AI 日报',
              icon: Icons.auto_awesome_rounded,
              primary: true,
              onPressed: _generateDigest,
            ),
          ],
        ),
        _buildFilters(context),
        const SizedBox(height: AppTheme.space12),
        if (_matches.isNotEmpty) _buildMatchBanner(context),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
              ? EmptyState(
                      message: _entries.isEmpty
                          ? '情报库为空，点击「同步情报」拉取最近 7 天 CVE'
                          : '没有匹配的条目',
                      icon: Icons.shield_outlined,
                    )
              : ListView(
                  children: [
                    for (final entry in shown) _buildEntryTile(context, entry),
                    if (_digest.isNotEmpty) ...[
                      const Divider(),
                      Text('AI 日报', style: context.fontTitle),
                      const SizedBox(height: AppTheme.space8),
                      Text(_digest, style: context.fontBody),
                    ],
                    if (_digestHistory.isNotEmpty) ...[
                      const Divider(),
                      Text('历史日报（近 7 天）', style: context.fontTitle),
                      const SizedBox(height: AppTheme.space8),
                      for (final record in _digestHistory)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            record.headline,
                            style: context.fontCaption,
                          ),
                          childrenPadding: const EdgeInsets.only(
                            bottom: AppTheme.space8,
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                record.text,
                                style: context.fontBodySecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Wrap(
      spacing: AppTheme.space8,
      runSpacing: AppTheme.space8,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            decoration: const InputDecoration(
              labelText: '搜索 CVE / 关键词',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 16),
            ),
            style: context.fontBody,
            onChanged: (v) => setState(() => _keyword = v),
          ),
        ),
        ChoiceChip(
          label: const Text('全部'),
          selected: _severityFilter == 'all',
          onSelected: (_) => setState(() => _severityFilter = 'all'),
        ),
        for (final s in Severity.ordered)
          ChoiceChip(
            label: Text(s.label),
            selected: _severityFilter == s.key,
            onSelected: (_) => setState(() => _severityFilter = s.key),
          ),
        FilterChip(
          label: const Text('仅 KEV'),
          selected: _kevOnly,
          onSelected: (v) => setState(() => _kevOnly = v),
        ),
        FilterChip(
          label: const Text('有 PoC'),
          selected: _pocOnly,
          onSelected: (v) => setState(() => _pocOnly = v),
        ),
      ],
    );
  }

  /// 命中横幅 + 一键生成 Finding。
  ///
  /// 不做全自动：首次同步 7 天 CVE 可能命中几十个资产，自动灌入几十条
  /// "待验证"会让用户先删一遍——噪音成本大于便利（design E）。
  Widget _buildMatchBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space12),
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.errorSolid.withAlpha(28),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.errorSolid.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: context.errorSolid),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              _generatedFindings > 0
                  ? '已生成 $_generatedFindings 条情报 Finding'
                  : '${_matches.length} 条情报与当前会话资产相关'
                      '（如 ${_matches.first.cveId} → ${_matches.first.assetAddress}）',
              style: context.fontCaption,
            ),
          ),
          if (_generatedFindings == 0) ...[
            const SizedBox(width: AppTheme.space8),
            SmallActionButton(
              label: _generatingFindings ? '生成中…' : '生成 Finding',
              icon: Icons.playlist_add_outlined,
              primary: true,
              onPressed: _generatingFindings ? null : _generateFindings,
            ),
          ],
        ],
      ),
    );
  }

  static const int _maxIntelFindings = 50;

  Future<void> _generateFindings() async {
    final controller = widget.controller;
    final session = controller.current;
    if (session == null || _matches.isEmpty) return;

    setState(() => _generatingFindings = true);
    var created = 0;
    var skipped = 0;
    var truncated = _matches.length - _maxIntelFindings;
    for (final match in _matches) {
      if (created + skipped >= _matches.length) break;
      if (created >= _maxIntelFindings) break;
      final asset = controller.assetList.firstWhere(
        (a) => a.address == match.assetAddress,
        orElse: () => controller.assetList.first,
      );
      // 幂等：同一 资产+CVE 只建一条。
      final exists = await controller.findings.existsForAssetCve(
        session.id,
        asset.id,
        match.cveId,
      );
      if (exists) {
        skipped++;
        continue;
      }
      await controller.findings.add(
        sessionId: session.id,
        assetId: asset.id,
        cveId: match.cveId,
        title: '情报匹配: ${match.cveId}',
        severity: match.entry.severity,
        cvssScore: match.entry.cvssScore,
        evidence: match.entry.title,
        source: FindingSource.intelMatch,
      );
      created++;
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.findingUpdate,
      title: '情报交叉比对生成 Finding',
      detail: {'created': created, 'skipped': skipped},
    );
    if (!mounted) return;
    setState(() {
      _generatedFindings = created;
      _generatingFindings = false;
    });
    final msg = StringBuffer('新建 $created 条，跳过 $skipped 条已存在');
    if (truncated > 0) {
      msg.write('；超出的 $truncated 条请缩小同步时间范围');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg.toString())),
    );
  }

  Widget _buildEntryTile(BuildContext context, ThreatIntelEntry entry) {
    final isMatch = _matches.any((m) => m.cveId == entry.cveId);
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space8),
      decoration: BoxDecoration(
        color: isMatch
            ? context.errorSolid.withAlpha(20)
            : context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Text(entry.cveId, style: context.fontBody),
            const SizedBox(width: AppTheme.space8),
            if (entry.isKev) const KevBadge(),
            if (entry.isKev) const SizedBox(width: 4),
            if (entry.pocUrl != null && entry.pocUrl!.isNotEmpty) const PocBadge(),
            if (isMatch) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.errorSolid.withAlpha(38),
                  borderRadius: AppTheme.borderRadiusSmall,
                ),
                child: Text('资产命中', style: context.fontCaption),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${entry.title}\nCVSS ${entry.cvssScore?.toStringAsFixed(1) ?? '-'} · '
          '${Severity.fromKey(entry.severity).label}',
          style: context.fontCaption,
        ),
        isThreeLine: true,
      ),
    );
  }
}
