/// Web 资产侦察面板：域名输入 → 子域名 → 存活探测 → 爬虫/内容发现。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/security_session_controller.dart';
import '../services/security_settings_store.dart';
import '../services/web_recon_services.dart';
import 'shodan_button.dart';
import 'widgets.dart';

class WebReconView extends StatefulWidget {
  final SecuritySessionController controller;

  const WebReconView({super.key, required this.controller});

  @override
  State<WebReconView> createState() => _WebReconViewState();
}

class _WebReconViewState extends State<WebReconView> {
  final _domainController = TextEditingController();
  bool _running = false;
  String _phase = '';
  String _statusFilter = 'all';
  String _techFilter = '';
  int _currentPage = 1;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    final current = widget.controller.current;
    if (current != null && !current.isLan && current.scope.isNotEmpty) {
      _domainController.text = current.scope.first;
    }
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  List<WebTargetInfo> get _targetInfos =>
      WebTargetInfo.parseList(_domainController.text);

  Future<void> _run() async {
    final controller = widget.controller;
    final session = controller.current;
    if (session == null) {
      _toast('请先创建或选择一个 Web 会话');
      return;
    }
    final targets = _targetInfos;
    if (targets.isEmpty) {
      _toast('请填写目标（域名或 IP）');
      return;
    }
    setState(() => _running = true);
    controller.log('═══ 开始 Web 侦察: ${targets.map((t) => t.displayAddress).join(', ')} ═══');

    // 阶段 1：子域名枚举（自动分流：纯 IP / 内网目标直接跳过）
    final fqdnTargets = targets.where((t) => !t.shouldSkipSubdomainEnumeration).map((t) => t.host).toSet().toList();
    final subs = <SubdomainResult>[];

    if (fqdnTargets.isEmpty) {
      controller.log('[1/3] 目标全为 IP/内网地址，自动跳过子域名枚举，直接进行 HTTP 存活探测');
    } else {
      setState(() => _phase = '子域名枚举（subfinder）…');
      controller.log('[1/3] subfinder 枚举子域名: ${fqdnTargets.join(', ')}…');
      final foundSubs = await SubfinderService.run(
        fqdnTargets,
        onLog: controller.log,
      );
      subs.addAll(foundSubs);
      controller.log('发现 ${foundSubs.length} 个子域名（仅作为候选，待存活探测后入库）');
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: 'subfinder 子域名枚举',
        detail: {'domains': fqdnTargets, 'count': foundSubs.length},
      );
    }
    if (!_running) return;

    // 阶段 2：HTTP 存活探测（全流程保全：用户输入的原始根目标 + 子域名候选合并去重）
    final probeList = <String>{
      ...targets.map((t) => t.probeTarget),
      ...subs.map((s) => s.host),
    }.toList();

    if (probeList.isEmpty) {
      setState(() => _phase = '');
      controller.log('无目标可探测，结束侦察流程');
      if (mounted) setState(() => _running = false);
      return;
    }

    setState(() => _phase = 'HTTP 存活探测（httpx / 原生引擎）…');
    controller.log('[2/3] 存活探测 ${probeList.length} 个目标（含根目标与子域名候选）…');
    final httpResults = await HttpxService.run(
      probeList,
      onLog: controller.log,
    );
    controller.log('存活 ${httpResults.length} 个 HTTP 资产');

    // 存活优先入库：仅持久化成功响应的端点
    for (final r in httpResults) {
      final parsedUri = Uri.tryParse(r.url);
      final host = r.host ?? parsedUri?.host ?? r.url;
      final port = parsedUri?.port;
      final displayAddress = (port != null && port != 80 && port != 443) ? '$host:$port' : host;

      final existing = await controller.assets.byAddress(session.id, displayAddress) ??
          await controller.assets.byAddress(session.id, host);

      final metadata = r.toMetadata();
      metadata['url'] = r.url;

      await controller.assets.upsert(
        sessionId: session.id,
        type: AssetType.url,
        address: displayAddress,
        metadata: metadata,
        riskLevel: existing?.riskLevel == 'unknown'
            ? riskLevelForWeb(r)
            : existing?.riskLevel,
      );
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'HTTP 存活探测',
      detail: {'probed': probeList.length, 'alive': httpResults.length},
    );

    // 阶段 3：对存活资产爬虫（katana）
    if (httpResults.isNotEmpty) {
      setState(() => _phase = 'JS 感知爬虫（katana）…');
      controller.log('[3/3] katana 爬取 ${httpResults.length} 个存活资产…');
      var crawled = 0;
      for (final r in httpResults.take(20)) {
        if (!_running) break;
        final endpoints = await KatanaService.run(r.url, onLog: controller.log);
        crawled += endpoints.length;
        if (endpoints.isNotEmpty) {
          final parsedUri = Uri.tryParse(r.url);
          final host = r.host ?? parsedUri?.host ?? r.url;
          final port = parsedUri?.port;
          final displayAddress = (port != null && port != 80 && port != 443) ? '$host:$port' : host;

          final existing = await controller.assets.byAddress(session.id, displayAddress) ??
              await controller.assets.byAddress(session.id, host);
          final merged = <String, dynamic>{
            ...?existing?.metadata,
            'crawled_urls': [
              ...((existing?.metadata['crawled_urls'] as List?) ?? const []),
              for (final e in endpoints) e.url,
            ].take(200).toList(),
          };
          await controller.assets.upsert(
            sessionId: session.id,
            type: AssetType.url,
            address: displayAddress,
            metadata: merged,
          );
        }
      }
      controller.log('爬取到 $crawled 个端点');
      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: 'katana 爬虫',
        detail: {'assets': httpResults.length, 'endpoints': crawled},
      );
    } else {
      controller.log('[3/3] 无存活资产，跳过 katana 爬虫阶段');
    }
    controller.log('═══ Web 侦察完成 ═══');
    if (mounted) {
      setState(() {
        _phase = '';
        _running = false;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final urlAssets = controller.assetList
            .where((a) => a.type == AssetType.url)
            .toList();
        final filtered = urlAssets.where((a) {
          final meta = a.metadata;
          if (_statusFilter != 'all') {
            final code = meta['status_code'];
            final isAlive = code != null && (code as num) < 400;
            if (_statusFilter == 'alive' && !isAlive) return false;
            if (_statusFilter == 'dead' && isAlive) return false;
          }
          if (_techFilter.isNotEmpty) {
            final tech = (meta['tech_stack'] as List?) ?? const [];
            final hit = tech.any(
              (t) => t.toString().toLowerCase().contains(
                    _techFilter.toLowerCase(),
                  ),
            );
            if (!hit) return false;
          }
          return true;
        }).toList();
        final totalPages = (filtered.length / _pageSize).ceil().clamp(1, double.infinity).toInt();
        final page = _currentPage.clamp(1, totalPages);
        final pagedAssets = filtered.skip((page - 1) * _pageSize).take(_pageSize).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Web 资产侦察',
              subtitle: '发现 → 探测 → 爬虫 三阶段工作流',
              trailing: [
                if (_running)
                  SmallActionButton(
                    label: '停止',
                    icon: Icons.stop,
                    onPressed: () => setState(() => _running = false),
                  )
                else ...[
                  _shodanKeyEntry(),
                  const SizedBox(width: AppTheme.space8),
                  SmallActionButton(
                    label: '开始侦察',
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onPressed: _run,
                  ),
                ],
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  _buildInputCard(context),
                  const SizedBox(height: AppTheme.space12),
                  if (_phase.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.space12),
                      child: Row(
                        children: [
                          if (_running)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (_running) const SizedBox(width: 8),
                          Text(_phase, style: context.fontCaption),
                        ],
                      ),
                    ),
                  _buildFilters(context, urlAssets.length, filtered.length),
                  const SizedBox(height: AppTheme.space12),
                  if (filtered.isEmpty)
                    EmptyState(
                      message: controller.current == null
                          ? '请先创建 Web 会话'
                          : '还没有资产，点击「开始侦察」',
                      icon: Icons.language_outlined,
                    )
                  else ...[
                    _buildAssetList(context, pagedAssets),
                    const SizedBox(height: AppTheme.space8),
                    AssetPaginationBar(
                      currentPage: page,
                      totalPages: totalPages,
                      totalCount: filtered.length,
                      pageSize: _pageSize,
                      onPageChanged: (newPage) => setState(() => _currentPage = newPage),
                    ),
                  ],
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

  /// 顶部 Shodan Key 状态与配置入口（未配置时显眼提示，已配置时显示脱敏值）。
  Widget _shodanKeyEntry() {
    return FutureBuilder<String>(
      future: SecuritySettingsStore.instance.shodanKey(),
      builder: (context, snapshot) {
        final masked = maskApiKey(snapshot.data ?? '');
        return SmallActionButton(
          label: 'Shodan $masked',
          icon: snapshot.data == null || snapshot.data!.isEmpty
              ? Icons.key_off_outlined
              : Icons.key_outlined,
          onPressed: () async {
            final keyController = TextEditingController();
            final key = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: context.bgCard,
                title: Text('Shodan API Key', style: context.fontTitle),
                content: TextField(
                  controller: keyController,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    isDense: true,
                  ),
                  style: context.fontBody,
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, keyController.text.trim()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            );
            keyController.dispose();
            if (key == null || key.isEmpty) return;
            await SecuritySettingsStore.instance.saveShodanKey(key);
            if (!context.mounted) return;
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildInputCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: TextField(
        controller: _domainController,
        decoration: const InputDecoration(
          labelText: '根域名（每行一个）',
          hintText: 'example.com',
        ),
        style: context.fontBody,
        maxLines: 3,
      ),
    );
  }

  Widget _buildFilters(BuildContext context, int total, int shown) {
    return Row(
      children: [
        Text('资产 $shown/$total', style: context.fontCaption),
        const SizedBox(width: AppTheme.space12),
        ChoiceChip(
          label: const Text('全部'),
          selected: _statusFilter == 'all',
          onSelected: (_) => setState(() {
            _statusFilter = 'all';
            _currentPage = 1;
          }),
        ),
        const SizedBox(width: AppTheme.space6),
        ChoiceChip(
          label: const Text('存活'),
          selected: _statusFilter == 'alive',
          onSelected: (_) => setState(() {
            _statusFilter = 'alive';
            _currentPage = 1;
          }),
        ),
        const SizedBox(width: AppTheme.space6),
        ChoiceChip(
          label: const Text('无响应'),
          selected: _statusFilter == 'dead',
          onSelected: (_) => setState(() {
            _statusFilter = 'dead';
            _currentPage = 1;
          }),
        ),
        const SizedBox(width: AppTheme.space12),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              labelText: '技术栈过滤',
              isDense: true,
            ),
            style: context.fontBody,
            onChanged: (v) => setState(() {
              _techFilter = v;
              _currentPage = 1;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildAssetList(BuildContext context, List<PentestAsset> assets) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        children: [
          for (final asset in assets)
            ListTile(
              dense: true,
              title: Row(
                children: [
                  Text(asset.address, style: context.fontBody),
                  if (asset.metadata['url'] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      asset.metadata['url'] as String,
                      style: context.fontCaption.copyWith(color: context.textTertiary),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                [
                  if (asset.userNote != null && asset.userNote!.isNotEmpty)
                    '【${asset.userNote}】',
                  if (asset.metadata['status_code'] != null)
                    'HTTP ${asset.metadata['status_code']}',
                  if (asset.metadata['webserver'] != null && (asset.metadata['webserver'] as String).isNotEmpty)
                    'Server: ${asset.metadata['webserver']}',
                  if (asset.metadata['title'] != null && (asset.metadata['title'] as String).isNotEmpty)
                    'Title: ${asset.metadata['title']}',
                  if ((asset.metadata['tech_stack'] as List?)?.isNotEmpty ??
                      false)
                    (asset.metadata['tech_stack'] as List).join(' / '),
                ].join(' · '),
                style: context.fontCaption,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      asset.userNote != null && asset.userNote!.isNotEmpty
                          ? Icons.comment
                          : Icons.add_comment_outlined,
                      size: 16,
                      color: asset.userNote != null && asset.userNote!.isNotEmpty
                          ? context.accentText
                          : context.textTertiary,
                    ),
                    tooltip: asset.userNote ?? '添加备注',
                    onPressed: () => _editNote(asset),
                  ),
                  ShodanButton(
                    asset: asset,
                    controller: widget.controller,
                  ),
                  const SizedBox(width: 4),
                  SeverityBadge(
                    severity: Severity.fromKey(asset.riskLevel),
                  ),
                  const SizedBox(width: 4),
                  _buildAssetActionMenu(context, asset),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAssetActionMenu(BuildContext context, PentestAsset asset) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: context.textSecondary),
      tooltip: '快速操作 / 转入工具',
      onSelected: (value) => _handleAssetAction(context, asset, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'vuln',
          child: Row(
            children: [
              Icon(Icons.bug_report_outlined, size: 16, color: context.accentText),
              const SizedBox(width: 8),
              const Text('转至漏洞扫描 (Nuclei)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'exploit',
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, size: 16, color: context.warningSolid),
              const SizedBox(width: 8),
              const Text('转至漏洞利用与验证'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'agent',
          child: Row(
            children: [
              Icon(Icons.psychology_outlined, size: 16, color: context.accentText),
              const SizedBox(width: 8),
              const Text('委托 Agent 深度评估'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'script',
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 16, color: context.textPrimary),
              const SizedBox(width: 8),
              const Text('生成端点测试脚本'),
            ],
          ),
        ),
      ],
    );
  }

  void _handleAssetAction(BuildContext context, PentestAsset asset, String action) {
    switch (action) {
      case 'vuln':
        widget.controller.navigateToTab(
          'vuln',
          intent: NavigationIntent(
            targetTab: 'vuln',
            targetAsset: asset,
            initialQuery: asset.address,
          ),
        );
        break;
      case 'exploit':
        widget.controller.navigateToTab(
          'exploit',
          intent: NavigationIntent(
            targetTab: 'exploit',
            targetAsset: asset,
            initialQuery: asset.address,
          ),
        );
        break;
      case 'agent':
        final title = asset.metadata['title'] as String?;
        final tech = (asset.metadata['tech_stack'] as List?)?.join(', ');
        final prompt = '针对 Web 端点 ${asset.address}${title != null ? " (标题: $title)" : ""}${tech != null && tech.isNotEmpty ? " 技术栈: $tech" : ""} 展开深入安全脆弱性核查与敏感接口发现';
        widget.controller.navigateToTab(
          'agent',
          intent: NavigationIntent(
            targetTab: 'agent',
            targetAsset: asset,
            initialPrompt: prompt,
          ),
        );
        break;
      case 'script':
        final prompt = '编写针对 Web 端点 ${asset.address} 的 HTTP 响应头安全检查与基本连通性探测脚本';
        widget.controller.navigateToTab(
          'script',
          intent: NavigationIntent(
            targetTab: 'script',
            targetAsset: asset,
            initialPrompt: prompt,
          ),
        );
        break;
    }
  }

  Future<void> _editNote(PentestAsset asset) async {
    final controller = TextEditingController(text: asset.userNote ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('资产备注: ${asset.address}', style: context.fontTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '备注信息',
            hintText: '例如：主站网关、API服务、测试环境等',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note != null) {
      await widget.controller.assets.setUserNote(
        asset.id,
        note.isEmpty ? null : note,
      );
      await widget.controller.reloadSessionData();
    }
  }
}
