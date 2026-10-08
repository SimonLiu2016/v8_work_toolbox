/// 漏洞扫描面板：目标选择 + 模板分类 + 实时 Finding + CVSS 统计。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/markdown_view.dart';
import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/offline_remediation_advisor.dart';
import '../services/security_session_controller.dart';
import '../services/vuln_scan_services.dart';
import '../services/web_recon_services.dart' show hasQueryParameters;
import 'widgets.dart';

class VulnScanView extends StatefulWidget {
  final SecuritySessionController controller;

  const VulnScanView({super.key, required this.controller});

  @override
  State<VulnScanView> createState() => _VulnScanViewState();
}

class _VulnScanViewState extends State<VulnScanView> {
  final Set<String> _selectedAssets = {};
  final Set<String> _selectedFindingIds = {};
  final Set<NucleiCategory> _categories = {NucleiCategory.cves};
  final Set<Severity> _selectedSeverities = {
    Severity.critical,
    Severity.high,
    Severity.medium,
  };
  bool _scanning = false;
  String _sqlmapTarget = '';

  void _consumeIntentIfNeeded(List<PentestAsset> targets) {
    final intent = widget.controller.pendingIntent;
    if (intent != null && intent.targetTab == 'vuln') {
      widget.controller.consumeIntent();
      if (intent.targetAsset != null) {
        _selectedAssets.clear();
        _selectedAssets.add(intent.targetAsset!.id);
      } else if (intent.initialQuery != null) {
        final match = targets.cast<PentestAsset?>().firstWhere(
          (a) => a?.address == intent.initialQuery,
          orElse: () => null,
        );
        if (match != null) {
          _selectedAssets.clear();
          _selectedAssets.add(match.id);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final findings = controller.findingList;
        final targets = controller.assetList;
        _consumeIntentIfNeeded(targets);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '漏洞扫描',
              subtitle: 'nuclei 模板扫描 + sqlmap 注入检测',
              trailing: [
                if (_scanning)
                  SmallActionButton(
                    label: '停止扫描',
                    icon: Icons.stop,
                    onPressed: () => setState(() => _scanning = false),
                  )
                else
                  SmallActionButton(
                    label: '开始 nuclei 扫描',
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onPressed: targets.isEmpty ? null : _runNuclei,
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  if (findings.isNotEmpty) _buildCvssCards(context, findings),
                  _buildCategoryPicker(context),
                  const SizedBox(height: AppTheme.space12),
                  _buildTargetPicker(context, targets),
                  const SizedBox(height: AppTheme.space12),
                  if (findings.isEmpty)
                    EmptyState(
                      message: controller.current == null
                          ? '请先创建会话并扫描'
                          : '暂无漏洞发现',
                      icon: Icons.shield_outlined,
                    )
                  else
                    _buildFindingList(context, findings),
                  const SizedBox(height: AppTheme.space12),
                  _buildSqlmapCard(context),
                  const SizedBox(height: AppTheme.space12),
                  LogConsole(
                    lines: controller.recentLogs(),
                    onClear: controller.clearLogs,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCvssCards(
    BuildContext context,
    List<PentestFinding> findings,
  ) {
    final counts = <Severity, int>{for (final s in Severity.values) s: 0};
    for (final f in findings) {
      counts[f.severityLevel] = (counts[f.severityLevel] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Row(
        children: [
          for (final s in Severity.ordered)
            if ((counts[s] ?? 0) > 0) ...[
              Expanded(
                child: StatCard(
                  label: s.label,
                  value: '${counts[s]}',
                  color: SeverityBadge.colorFor(context, s),
                ),
              ),
              const SizedBox(width: AppTheme.space8),
            ],
        ],
      ),
    );
  }

  Widget _buildCategoryPicker(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('模板分类', style: context.fontBody),
          const SizedBox(height: AppTheme.space8),
          Wrap(
            spacing: AppTheme.space8,
            children: [
              for (final category in NucleiCategory.values)
                FilterChip(
                  label: Text(category.label),
                  selected: _categories.contains(category),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _categories.add(category);
                    } else {
                      _categories.remove(category);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              Text('风险等级过滤 (nuclei -s)', style: context.fontBody),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (_selectedSeverities.length == Severity.ordered.length) {
                    _selectedSeverities
                      ..clear()
                      ..addAll([
                        Severity.critical,
                        Severity.high,
                        Severity.medium,
                      ]);
                  } else {
                    _selectedSeverities
                      ..clear()
                      ..addAll(Severity.ordered);
                  }
                }),
                child: Text(
                  _selectedSeverities.length == Severity.ordered.length
                      ? '恢复默认'
                      : '全选',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Wrap(
            spacing: AppTheme.space8,
            children: [
              for (final s in Severity.ordered)
                FilterChip(
                  label: Text(s.label),
                  selected: _selectedSeverities.contains(s),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedSeverities.add(s);
                    } else {
                      if (_selectedSeverities.length > 1) {
                        _selectedSeverities.remove(s);
                      } else {
                        _toast('请至少保留一个风险等级');
                      }
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetPicker(
    BuildContext context,
    List<PentestAsset> targets,
  ) {
    if (targets.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('扫描目标 (${_selectedAssets.length}/${targets.length})',
                  style: context.fontBody),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (_selectedAssets.length == targets.length) {
                    _selectedAssets.clear();
                  } else {
                    _selectedAssets
                      ..clear()
                      ..addAll(targets.map((a) => a.id));
                  }
                }),
                child: Text(
                  _selectedAssets.length == targets.length ? '全不选' : '全选',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              for (final asset in targets)
                FilterChip(
                  label: Text(asset.address),
                  selected: _selectedAssets.contains(asset.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedAssets.add(asset.id);
                    } else {
                      _selectedAssets.remove(asset.id);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _extractTargetLabel(PentestFinding finding, PentestAsset? asset) {
    if (finding.evidence != null && finding.evidence!.isNotEmpty) {
      try {
        final decoded = jsonDecode(finding.evidence!);
        if (decoded is Map) {
          final matched = decoded['matched-at'] ?? decoded['host'];
          if (matched != null && matched.toString().isNotEmpty) {
            return matched.toString();
          }
        }
      } catch (_) {
        final match = RegExp(r'(?:matched-at|host)[:=]\s*([^,\}\s]+)').firstMatch(finding.evidence!);
        if (match != null && match.group(1) != null) {
          return match.group(1)!;
        }
      }
    }
    if (asset != null && asset.address.isNotEmpty) {
      return asset.address;
    }
    return '';
  }

  Widget _buildFindingList(
    BuildContext context,
    List<PentestFinding> findings,
  ) {
    final assetMap = {for (final a in widget.controller.assetList) a.id: a};
    final highSeverityCount = findings
        .where((f) =>
            f.severityLevel == Severity.critical ||
            f.severityLevel == Severity.high)
        .length;

    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '漏洞发现物 (${findings.length})',
                style: context.fontBody.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              SmallActionButton(
                label: _selectedFindingIds.isNotEmpty
                    ? 'AI 研判选定 (${_selectedFindingIds.length})'
                    : '一键 AI 全量加固清单',
                icon: Icons.auto_awesome,
                primary: true,
                onPressed: findings.isEmpty
                    ? null
                    : () => _generateBatchRemediation(findings),
              ),
              const SizedBox(width: AppTheme.space8),
              TextButton(
                onPressed: () => setState(() {
                  if (_selectedFindingIds.length == findings.length) {
                    _selectedFindingIds.clear();
                  } else {
                    _selectedFindingIds
                      ..clear()
                      ..addAll(findings.map((f) => f.id));
                  }
                }),
                child: Text(
                  _selectedFindingIds.length == findings.length ? '全不选' : '全选',
                ),
              ),
              if (highSeverityCount > 0)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedFindingIds
                      ..clear()
                      ..addAll(findings
                          .where((f) =>
                              f.severityLevel == Severity.critical ||
                              f.severityLevel == Severity.high)
                          .map((f) => f.id));
                  }),
                  child: const Text('仅选高危'),
                ),
            ],
          ),
          if (_selectedFindingIds.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space12,
                vertical: AppTheme.space8,
              ),
              decoration: BoxDecoration(
                color: context.bgWindow,
                borderRadius: AppTheme.borderRadiusSmall,
                border: Border.all(
                  color: context.accentSolid.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_box_outlined,
                    size: 16,
                    color: context.accentSolid,
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    '已选 ${_selectedFindingIds.length} 项',
                    style: context.fontCaption.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text('批量标记：', style: context.fontCaption),
                  const SizedBox(width: AppTheme.space4),
                  SmallActionButton(
                    label: '已确认',
                    icon: Icons.check_circle_outline,
                    onPressed: () =>
                        _batchSetFindingStatus(FindingStatus.verified),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  SmallActionButton(
                    label: '误报',
                    icon: Icons.cancel_outlined,
                    onPressed: () =>
                        _batchSetFindingStatus(FindingStatus.falsePositive),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  SmallActionButton(
                    label: '待验证',
                    icon: Icons.refresh,
                    onPressed: () =>
                        _batchSetFindingStatus(FindingStatus.open),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: '取消选择',
                    onPressed: () => setState(() => _selectedFindingIds.clear()),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppTheme.space8),
          const Divider(height: 1),
          for (final finding in findings) () {
            final asset = assetMap[finding.assetId];
            final targetLabel = _extractTargetLabel(finding, asset);
            final isChecked = _selectedFindingIds.contains(finding.id);
            return ListTile(
              dense: true,
              onTap: () => _recommendRemediation(finding),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isChecked,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedFindingIds.add(finding.id);
                        } else {
                          _selectedFindingIds.remove(finding.id);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  SeverityBadge(
                    severity: finding.severityLevel,
                    cvss: finding.cvssScore,
                  ),
                ],
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      finding.title,
                      style: context.fontBody,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (targetLabel.isNotEmpty) ...[
                    const SizedBox(width: AppTheme.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.bgWindow,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Text(
                        targetLabel,
                        style: context.fontCaption.copyWith(
                          color: context.accentSolid,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                [
                  if (targetLabel.isNotEmpty) '目标: $targetLabel',
                  if (finding.cveId != null) finding.cveId!,
                  '来源: ${FindingSource.labelOf(finding.source)}',
                  FindingStatus.labelOf(finding.status),
                ].join(' · '),
                style: context.fontCaption,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.bolt_rounded, size: 16, color: context.warningSolid),
                    tooltip: '🚀 转入漏洞利用 / PoC 验证',
                    onPressed: () {
                      final resolvedAsset = asset ?? (targetLabel.isNotEmpty ? PentestAsset(
                        id: '',
                        sessionId: widget.controller.current?.id ?? '',
                        type: 'host',
                        address: targetLabel,
                        metadataJson: '{}',
                        riskLevel: finding.severity,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ) : null);
                      widget.controller.navigateToTab(
                        'exploit',
                        intent: NavigationIntent(
                          targetTab: 'exploit',
                          targetAsset: resolvedAsset,
                          targetFinding: finding,
                          initialQuery: finding.cveId ?? finding.title,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.code_rounded, size: 16, color: context.textPrimary),
                    tooltip: '生成复测脚本',
                    onPressed: () {
                      final target = targetLabel.isNotEmpty ? targetLabel : (asset?.address ?? '');
                      final prompt = '编写针对目标 $target 漏洞【${finding.title}】(${finding.cveId ?? "未登记CVE"}) 的安全性复测与验证脚本';
                      widget.controller.navigateToTab(
                        'script',
                        intent: NavigationIntent(
                          targetTab: 'script',
                          targetAsset: asset,
                          targetFinding: finding,
                          initialPrompt: prompt,
                        ),
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 16),
                    color: context.bgCard,
                    onSelected: (action) async {
                      if (action == 'recommend_remediation') {
                        _recommendRemediation(finding);
                        return;
                      }
                      if (action == 'exploit') {
                        widget.controller.navigateToTab(
                          'exploit',
                          intent: NavigationIntent(
                            targetTab: 'exploit',
                            targetAsset: asset,
                            targetFinding: finding,
                            initialQuery: finding.cveId ?? finding.title,
                          ),
                        );
                        return;
                      }
                      if (action == 'script') {
                        final target = targetLabel.isNotEmpty ? targetLabel : (asset?.address ?? '');
                        final prompt = '编写针对目标 $target 漏洞【${finding.title}】(${finding.cveId ?? "未登记CVE"}) 的安全性复测与验证脚本';
                        widget.controller.navigateToTab(
                          'script',
                          intent: NavigationIntent(
                            targetTab: 'script',
                            targetAsset: asset,
                            targetFinding: finding,
                            initialPrompt: prompt,
                          ),
                        );
                        return;
                      }
                      await widget.controller.findings.setStatus(
                        finding.id,
                        action,
                      );
                      await widget.controller.reloadSessionData();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'exploit',
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt_outlined,
                              size: 16,
                              color: context.warningSolid,
                            ),
                            const SizedBox(width: AppTheme.space8),
                            Text('转至漏洞利用与 PoC 验证', style: context.fontBody),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'script',
                        child: Row(
                          children: [
                            Icon(
                              Icons.code_rounded,
                              size: 16,
                              color: context.textPrimary,
                            ),
                            const SizedBox(width: AppTheme.space8),
                            Text('生成定制复测脚本', style: context.fontBody),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'recommend_remediation',
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: context.accentSolid,
                            ),
                            const SizedBox(width: AppTheme.space8),
                            Text('AI 漏洞研判与加固建议', style: context.fontBody),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      for (final status in [
                        FindingStatus.verified,
                        FindingStatus.exploited,
                        FindingStatus.falsePositive,
                        FindingStatus.open,
                      ])
                        PopupMenuItem(
                          value: status,
                          child: Text(
                            '标记为${FindingStatus.labelOf(status)}',
                            style: context.fontBody,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }(),
        ],
      ),
    );
  }

  Widget _buildSqlmapCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SQL 注入检测（sqlmap）', style: context.fontBody),
          const SizedBox(height: AppTheme.space8),
          TextField(
            decoration: const InputDecoration(
              labelText: '含参数的 URL',
              hintText: 'https://example.com/page.php?id=1',
              isDense: true,
            ),
            style: context.fontBody,
            onChanged: (v) => _sqlmapTarget = v,
          ),
          const SizedBox(height: AppTheme.space8),
          SmallActionButton(
            label: _scanning ? '扫描中…' : '运行 sqlmap',
            icon: Icons.play_arrow_rounded,
            onPressed: _scanning ? null : _runSqlmap,
          ),
        ],
      ),
    );
  }

  Future<void> _runNuclei() async {
    final controller = widget.controller;
    final session = controller.current;
    if (session == null) {
      _toast('请先创建或选择一个会话');
      return;
    }
    final selected = controller.assetList
        .where((a) => _selectedAssets.contains(a.id))
        .toList();
    final targets = selected.isEmpty
        ? controller.assetList
        : selected;
    if (targets.isEmpty) {
      _toast('没有可扫描的资产，请先执行侦察');
      return;
    }
    setState(() => _scanning = true);
    controller.log('═══ nuclei 扫描 ${targets.length} 个目标 ═══');
    var count = 0;
    await NucleiService.scan(
      targets: targets.map((t) => t.address).toList(),
      categories: _categories.toList(),
      severities: _selectedSeverities.toList(),
      onLog: controller.log,
      onFinding: (finding) async {
        count++;
        // CVSS 优先用模板 metadata；拿不到再查 NVD（spec 的 fallback）。
        var cvss = finding.cvssScore;
        var severity = finding.severityLevel;
        final cve = finding.cveId;
        if (cve != null && cvss == null) {
          final detail = await CveEnricher.instance.lookup(cve);
          if (detail != null) {
            cvss = detail.cvssScore;
            severity = Severity.fromKey(detail.severity);
          }
        }
        final host = NucleiService.extractHost(finding.matchedAt);
        PentestAsset? asset;
        for (final t in targets) {
          if (t.address == host ||
              NucleiService.extractHost(t.address) == host ||
              t.address == finding.matchedAt) {
            asset = t;
            break;
          }
        }
        asset ??= (targets.length == 1 ? targets.first : null);
        if (asset == null && host.isNotEmpty) {
          asset = await controller.assets.byAddress(session.id, host);
        }
        await controller.findings.add(
          sessionId: session.id,
          assetId: asset?.id,
          cveId: cve,
          title: finding.name,
          severity: severity.key,
          cvssScore: cvss,
          evidence: jsonEncode(finding.raw),
          source: FindingSource.nuclei,
        );
        await controller.reloadSessionData();
      },
    );
    controller.log('nuclei 完成，新增 $count 条发现');
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'nuclei 漏洞扫描',
      detail: {'targets': targets.length, 'findings': count},
    );
    if (mounted) setState(() => _scanning = false);
    if (count > 0) {
      widget.controller.pushAiMessage('assistant', '扫描完成：新增 $count 条发现，可以让我分析优先级。');
    }
  }

  Future<void> _runSqlmap() async {
    final controller = widget.controller;
    final session = controller.current;
    if (session == null) {
      _toast('请先创建或选择一个会话');
      return;
    }
    if (!hasQueryParameters(_sqlmapTarget)) {
      _toast('URL 需要带查询参数（?id=1 这种）');
      return;
    }
    setState(() => _scanning = true);
    controller.log('═══ sqlmap 检测 $_sqlmapTarget ═══');
    final results = await SqlmapService.scan(
      [_sqlmapTarget],
      onLog: controller.log,
    );
    for (final r in results) {
      await controller.findings.add(
        sessionId: session.id,
        title: r.title ?? '${r.targetUrl} 疑似注入点',
        severity: Severity.high.key,
        evidence: 'parameter=${r.parameter} technique=${r.technique} dbms=${r.dbms}',
        source: FindingSource.sqlmap,
      );
    }
    await controller.reloadSessionData();
    controller.log('sqlmap 完成，发现 ${results.length} 个注入点');
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'sqlmap 注入检测',
      detail: {'url': _sqlmapTarget, 'findings': results.length},
    );
    if (mounted) setState(() => _scanning = false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _batchSetFindingStatus(String status) async {
    if (_selectedFindingIds.isEmpty) return;
    final ids = _selectedFindingIds.toList();
    await widget.controller.batchSetFindingStatus(ids, status);
    setState(() => _selectedFindingIds.clear());
    _toast('已批量更新 ${ids.length} 项状态为【${FindingStatus.labelOf(status)}】');
  }

  void _generateBatchRemediation(List<PentestFinding> findings) {
    final targets = _selectedFindingIds.isNotEmpty
        ? findings.where((f) => _selectedFindingIds.contains(f.id)).toList()
        : findings;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _BatchRemediationDialog(
        findings: targets,
        controller: widget.controller,
      ),
    );
  }

  void _recommendRemediation(PentestFinding finding) {
    final asset = widget.controller.assetList
        .cast<PentestAsset?>()
        .firstWhere((a) => a?.id == finding.assetId, orElse: () => null);
    final targetLabel = _extractTargetLabel(finding, asset);
    final targetHost =
        targetLabel.isNotEmpty ? targetLabel : (asset?.address ?? '目标主机');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _AiRemediationDialog(
        finding: finding,
        targetHost: targetHost,
        controller: widget.controller,
      ),
    );
  }
}

class _AiRemediationDialog extends StatefulWidget {
  final PentestFinding finding;
  final String targetHost;
  final SecuritySessionController controller;

  const _AiRemediationDialog({
    required this.finding,
    required this.targetHost,
    required this.controller,
  });

  @override
  State<_AiRemediationDialog> createState() => _AiRemediationDialogState();
}

class _AiRemediationDialogState extends State<_AiRemediationDialog> {
  bool _loading = true;
  String _response = '';
  String? _error;
  bool _isOfflineFallback = false;

  @override
  void initState() {
    super.initState();
    _fetchRecommendation();
  }

  Future<void> _fetchRecommendation({bool forceRetry = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _isOfflineFallback = false;
    });

    try {
      final res = await widget.controller.askFindingRemediation(
        finding: widget.finding,
        targetHost: widget.targetHost,
        ignoreCooldown: forceRetry,
      );
      if (!mounted) return;
      setState(() {
        _response = res;
        _loading = false;
        _error = null;
        _isOfflineFallback = false;
      });
      widget.controller.pushAiMessage(
        'assistant',
        '针对 ${widget.targetHost} 的【${widget.finding.title}】加固方案：\n$res',
      );
    } catch (e) {
      if (!mounted) return;
      final fallback = OfflineRemediationAdvisor.build(
        finding: widget.finding,
        targetHost: widget.targetHost,
      );
      setState(() {
        _error = '$e';
        _response = fallback;
        _loading = false;
        _isOfflineFallback = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: context.accentSolid, size: 20),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              'AI 漏洞研判与加固建议：${widget.finding.title}',
              style: context.fontTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 450,
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppTheme.space12),
                    Text('正在根据漏洞特征生成安全加固与防御方案…'),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isOfflineFallback) ...[
                    Container(
                      padding: const EdgeInsets.all(AppTheme.space12),
                      margin: const EdgeInsets.only(bottom: AppTheme.space12),
                      decoration: BoxDecoration(
                        color: context.warningSolid.withValues(alpha: 0.12),
                        borderRadius: AppTheme.borderRadiusSmall,
                        border: Border.all(
                          color: context.warningSolid.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Tooltip(
                            message: _error ?? '未知错误',
                            child: Icon(
                              Icons.info_outline,
                              size: 18,
                              color: context.warningSolid,
                            ),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          Expanded(
                            child: Text(
                              _error != null && _error!.contains('TimeoutException')
                                  ? '云端 AI 响应超时，已为您自动加载本地离线安全加固基线建议。您可以点击【强制重试】重新向云端请求。'
                                  : '云端 AI 响应异常，已为您自动加载本地离线安全加固基线建议。您可以点击【强制重试】重新向云端请求。',
                              style: context.fontCaption.copyWith(
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          SmallActionButton(
                            label: '强制重试',
                            icon: Icons.refresh,
                            onPressed: () =>
                                _fetchRecommendation(forceRetry: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Expanded(
                    child: SingleChildScrollView(
                      child: AppMarkdownView(
                        data: _response,
                        selectable: true,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (!_loading && _response.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制方案'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _response));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制防御加固方案到剪贴板')),
              );
            },
          ),
        if (!_loading && _isOfflineFallback)
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('强制重试 (绕过冷却)'),
            onPressed: () => _fetchRecommendation(forceRetry: true),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _BatchRemediationDialog extends StatefulWidget {
  final List<PentestFinding> findings;
  final SecuritySessionController controller;

  const _BatchRemediationDialog({
    required this.findings,
    required this.controller,
  });

  @override
  State<_BatchRemediationDialog> createState() =>
      _BatchRemediationDialogState();
}

class _BatchRemediationDialogState extends State<_BatchRemediationDialog> {
  bool _loading = true;
  String _response = '';
  String? _error;
  bool _isOfflineFallback = false;

  @override
  void initState() {
    super.initState();
    _fetchBatchSummary();
  }

  Future<void> _fetchBatchSummary({bool forceRetry = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _isOfflineFallback = false;
    });

    try {
      final res = await widget.controller.askBatchRemediation(
        findings: widget.findings,
        ignoreCooldown: forceRetry,
      );
      if (!mounted) return;
      setState(() {
        _response = res;
        _loading = false;
        _error = null;
        _isOfflineFallback = false;
      });
      widget.controller.pushAiMessage(
        'assistant',
        '全量漏洞加固汇总报告已生成：\n$res',
      );
    } catch (e) {
      if (!mounted) return;
      final session = widget.controller.current;
      final fallback = OfflineRemediationAdvisor.buildBatchSummary(
        sessionName: session?.name ?? '安全巡检会话',
        findings: widget.findings,
        assets: widget.controller.assetList,
      );
      setState(() {
        _error = '$e';
        _response = fallback;
        _loading = false;
        _isOfflineFallback = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: context.accentSolid, size: 20),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              '一键全量漏洞加固汇总报告 (${widget.findings.length} 项发现)',
              style: context.fontTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppTheme.space12),
                    Text('正在聚合共性风险并生成全量加固处置报告…'),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isOfflineFallback) ...[
                    Container(
                      padding: const EdgeInsets.all(AppTheme.space12),
                      margin: const EdgeInsets.only(bottom: AppTheme.space12),
                      decoration: BoxDecoration(
                        color: context.warningSolid.withValues(alpha: 0.12),
                        borderRadius: AppTheme.borderRadiusSmall,
                        border: Border.all(
                          color: context.warningSolid.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Tooltip(
                            message: _error ?? '未知错误',
                            child: Icon(
                              Icons.info_outline,
                              size: 18,
                              color: context.warningSolid,
                            ),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          Expanded(
                            child: Text(
                              _error != null && _error!.contains('TimeoutException')
                                  ? '云端 AI 响应超时，已为您生成本地安全基线加固全量清单。'
                                  : '云端 AI 响应异常，已为您生成本地安全基线加固全量清单。',
                              style: context.fontCaption.copyWith(
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          SmallActionButton(
                            label: '强制重试',
                            icon: Icons.refresh,
                            onPressed: () =>
                                _fetchBatchSummary(forceRetry: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Expanded(
                    child: SingleChildScrollView(
                      child: AppMarkdownView(
                        data: _response,
                        selectable: true,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (!_loading && _response.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制报告'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _response));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制全量加固报告到剪贴板')),
              );
            },
          ),
        if (!_loading && _isOfflineFallback)
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('强制重试 (绕过冷却)'),
            onPressed: () => _fetchBatchSummary(forceRetry: true),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
