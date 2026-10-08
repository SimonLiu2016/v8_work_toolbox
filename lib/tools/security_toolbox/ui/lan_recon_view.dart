/// LAN 侦察面板：接口选择 + 扫描配置 + 实时进度 + 设备列表。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/lan_recon_services.dart';
import '../services/security_session_controller.dart';
import 'network_topology_graph.dart';
import 'shodan_button.dart';
import 'widgets.dart';

class LanReconView extends StatefulWidget {
  final SecuritySessionController controller;

  const LanReconView({super.key, required this.controller});

  @override
  State<LanReconView> createState() => _LanReconViewState();
}

class _LanReconViewState extends State<LanReconView> {
  List<NetworkInterface> _interfaces = const [];
  String _target = '';
  late final TextEditingController _targetController;
  NmapScanMode _mode = NmapScanMode.standard;
  bool _scanning = false;
  bool _withOs = false;
  String _phase = '';
  int _currentPage = 1;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    final current = widget.controller.current;
    if (current != null && current.isLan && current.scope.isNotEmpty) {
      _target = current.scope.first;
    }
    _targetController = TextEditingController(text: _target);
    _detectInterfaces();
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _detectInterfaces() async {
    final list = await NetworkInterfaceDetector.detect();
    if (!mounted) return;
    setState(() {
      _interfaces = list;
      if (_target.isEmpty && list.isNotEmpty) {
        final first = list.first;
        final prefix = first.cidr.contains('/') ? first.cidr.split('/')[1] : '24';
        final base = first.ipv4.split('.').take(3).join('.');
        _target = '$base.0/$prefix';
        _targetController.text = _target;
      }
    });
  }

  String get _gatewayIp {
    final parts = _target.split('/').first.split('.');
    if (parts.length != 4) return _target;
    return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  }

  Future<void> _startScan() async {
    final controller = widget.controller;
    final session = controller.current;
    if (session == null) {
      _toast('请先创建或选择一个会话');
      return;
    }
    if (_target.trim().isEmpty) {
      _toast('请填写目标网段');
      return;
    }
    setState(() => _scanning = true);
    controller.log('═══ 开始 LAN 侦察: $_target ═══');

    // 阶段 1：ARP 发现
    setState(() => _phase = 'ARP 主机发现…');
    controller.log('[1/2] ARP 发现中…');
    final arpHosts = await ArpScanService.scan(
      cidr: _target,
      onLog: controller.log,
    );
    controller.log('存活探测完成：发现 ${arpHosts.length} 台在线主机');
    for (final host in arpHosts) {
      final info = [
        host.ip,
        if (host.mac != null) host.mac,
        if (host.vendor != null) host.vendor,
        if (host.hostname != null) host.hostname,
      ].join(' · ');
      controller.log('  ▸ $info');
      await controller.assets.upsert(
        sessionId: session.id,
        type: AssetType.host,
        address: host.ip,
        metadata: {
          if (host.mac != null) 'mac': host.mac,
          if (host.vendor != null) 'vendor': host.vendor,
          if (host.hostname != null) 'hostname': host.hostname,
        },
      );
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'ARP 发现 $_target',
      detail: {'hosts': arpHosts.length, 'cidr': _target},
    );

    // 阶段 2：对每台主机 nmap 深度扫描
    setState(() => _phase = '服务与端口枚举…');
    final hosts = arpHosts.map((h) => h.ip).toList();
    var scanned = 0;
    for (final ip in hosts) {
      if (!_scanning) break;
      scanned++;
      setState(() => _phase = '扫描 $ip ($scanned/${hosts.length})');
      controller.log('[2/2] nmap 扫描 $ip');
      final results = await NmapService.scan(
        target: ip,
        mode: _mode,
        withOsDetect: _withOs,
        onLog: controller.log,
      );
      for (final host in results) {
        final existing = await controller.assets.byAddress(session.id, host.ip);
        final risk = riskLevelForHost(host);
        final meta = host.toMetadata();
        // 保留阶段 1 获取的真实 MAC 与厂商信息（非 root 下 nmap 不返回 MAC）
        final prevMeta = existing?.metadata ?? const {};
        if (meta['mac'] == null && prevMeta['mac'] != null) {
          meta['mac'] = prevMeta['mac'];
        }
        if (meta['vendor'] == null && prevMeta['vendor'] != null) {
          meta['vendor'] = prevMeta['vendor'];
        }
        await controller.assets.upsert(
          sessionId: session.id,
          type: AssetType.host,
          address: host.ip,
          metadata: meta,
          riskLevel: existing?.riskLevel == 'unknown'
              ? risk
              : existing?.riskLevel,
        );
      }
      await controller.reloadSessionData();
    }

    if (_scanning == false) {
      controller.log('扫描已被用户中断');
    } else {
      controller.log('═══ LAN 侦察完成 ═══');
    }
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'nmap 深度扫描（${_mode.label}）',
      detail: {'mode': _mode.label, 'hosts': hosts.length},
    );
    if (mounted) setState(() => _scanning = false);
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
        final assets = controller.assetList
            .where((a) => a.type == AssetType.host)
            .toList();
        final totalPages = (assets.length / _pageSize).ceil().clamp(1, double.infinity).toInt();
        final page = _currentPage.clamp(1, totalPages);
        final pagedAssets = assets.skip((page - 1) * _pageSize).take(_pageSize).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '局域网侦察',
              subtitle: '接口识别 → ARP 发现 → 服务枚举 → 拓扑可视化',
              trailing: [
                if (_scanning)
                  SmallActionButton(
                    label: '停止扫描',
                    icon: Icons.stop,
                    onPressed: () => setState(() => _scanning = false),
                  )
                else
                  SmallActionButton(
                    label: '开始扫描',
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onPressed: _startScan,
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  _buildTargetCard(context),
                  const SizedBox(height: AppTheme.space12),
                  if (_phase.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.space12),
                      child: Row(
                        children: [
                          if (_scanning)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (_scanning)
                            const SizedBox(width: AppTheme.space8),
                          Text(_phase, style: context.fontCaption),
                        ],
                      ),
                    ),
                  if (assets.isNotEmpty) ...[
                    _buildTopology(context, assets),
                    const SizedBox(height: AppTheme.space12),
                    _buildDeviceList(context, pagedAssets, assets.length),
                    const SizedBox(height: AppTheme.space8),
                    AssetPaginationBar(
                      currentPage: page,
                      totalPages: totalPages,
                      totalCount: assets.length,
                      pageSize: _pageSize,
                      onPageChanged: (newPage) => setState(() => _currentPage = newPage),
                    ),
                    const SizedBox(height: AppTheme.space12),
                  ] else
                    EmptyState(
                      message: controller.current == null
                          ? '请先创建 LAN 会话'
                          : '还没有发现设备',
                      icon: Icons.router_outlined,
                    ),
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

  Widget _buildTargetCard(BuildContext context) {
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
          TextField(
            controller: _targetController,
            onChanged: (v) => _target = v,
            decoration: const InputDecoration(
              labelText: '目标网段',
              isDense: true,
            ),
            style: context.fontBody,
          ),
          const SizedBox(height: AppTheme.space8),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              for (final iface in _interfaces)
                InkWell(
                  onTap: () {
                    final prefix = iface.cidr.contains('/')
                        ? iface.cidr.split('/')[1]
                        : '24';
                    final base = iface.ipv4.split('.').take(3).join('.');
                    final nextTarget = '$base.0/$prefix';
                    _targetController.text = nextTarget;
                    setState(() => _target = nextTarget);
                  },
                  borderRadius: AppTheme.borderRadiusSmall,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.bgInput,
                      borderRadius: AppTheme.borderRadiusSmall,
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: Text(
                      '${iface.name} ${iface.cidr}',
                      style: context.fontCaption,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          Text('扫描深度', style: context.fontCaption),
          const SizedBox(height: AppTheme.space6),
          Wrap(
            spacing: AppTheme.space8,
            children: [
              for (final mode in NmapScanMode.values)
                ChoiceChip(
                  label: Text('${mode.label} · ${mode.hint}'),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                ),
            ],
          ),
          CheckboxListTile(
            value: _withOs,
            onChanged: (v) => setState(() => _withOs = v ?? false),
            title: Text('OS 指纹识别（-O，需要特权）', style: context.fontCaption),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTopology(BuildContext context, List<PentestAsset> assets) {
    // 拓扑图至多渲染前 150 个节点以保持平滑帧率
    final nodes = assets
        .take(150)
        .map(
          (a) => TopoNode(
            ip: a.address,
            mac: a.metadata['mac'] as String?,
            vendor: a.metadata['vendor'] as String?,
            os: a.metadata['os'] as String?,
            deviceType: a.metadata['device_type'] as String? ?? 'device',
            riskLevel: a.riskLevel,
            ports: const [],
          ),
        )
        .toList();
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
          Text('网络拓扑', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Center(
            child: NetworkTopologyGraph(
              nodes: nodes,
              gatewayIp: _gatewayIp,
              onNodeSelected: (node) {
                final match = assets.cast<PentestAsset?>().firstWhere(
                  (a) => a?.address == node.ip,
                  orElse: () => null,
                );
                if (match != null) {
                  _showAssetActionDialog(context, match);
                } else {
                  _toast('${node.ip} · ${node.vendor ?? "未知厂商"}');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BuildContext context, List<PentestAsset> assets, int totalCount) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTheme.space12),
            child: Text('设备列表 ($totalCount)', style: context.fontTitle),
          ),
          for (final asset in assets)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: SeverityBadge.colorFor(
                  context,
                  Severity.fromKey(asset.riskLevel),
                ).withAlpha(45),
                child: Text(
                  asset.address.split('.').last,
                  style: AppTheme.fontCaption.copyWith(
                    color: SeverityBadge.colorFor(
                      context,
                      Severity.fromKey(asset.riskLevel),
                    ),
                  ),
                ),
              ),
              title: Text(asset.address, style: context.fontBody),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (asset.userNote != null && asset.userNote!.isNotEmpty)
                        '【${asset.userNote}】',
                      if (asset.metadata['mac'] != null) asset.metadata['mac'],
                      if (asset.metadata['vendor'] != null) asset.metadata['vendor'],
                      if (asset.metadata['os'] != null) asset.metadata['os'],
                    ].join(' · '),
                    style: context.fontCaption,
                  ),
                  if (asset.openPorts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final p in asset.openPorts.take(6))
                          _buildPortChip(context, asset, p),
                        if (asset.openPorts.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '+${asset.openPorts.length - 6}个端口',
                              style: context.fontCaption.copyWith(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
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
                  ShodanButton(asset: asset, controller: widget.controller),
                  const SizedBox(width: 4),
                  SeverityBadge(
                    severity: Severity.fromKey(asset.riskLevel),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.bolt_rounded, size: 16, color: context.warningSolid),
                    tooltip: '🚀 转入漏洞利用与验证',
                    onPressed: () => _handleAssetAction(context, asset, 'exploit'),
                  ),
                  _buildAssetActionMenu(context, asset),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortChip(BuildContext context, PentestAsset asset, Map<String, dynamic> portMap) {
    final port = portMap['port'];
    final service = portMap['service'] as String? ?? '';
    final label = service.isNotEmpty ? '$port/$service' : '$port';
    final portNum = port is int ? port : int.tryParse('$port');

    return PopupMenuButton<String>(
      tooltip: '端口 $label 操作',
      onSelected: (value) {
        if (value == 'exploit') {
          widget.controller.navigateToTab(
            'exploit',
            intent: NavigationIntent(
              targetTab: 'exploit',
              targetAsset: asset,
              port: portNum,
              service: service,
              initialQuery: service.isNotEmpty ? service : '$port',
            ),
          );
        } else if (value == 'script') {
          final prompt = '编写针对 ${asset.address}:$port (${service.isNotEmpty ? service : "服务"}) 的协议探测与安全合规核查脚本';
          widget.controller.navigateToTab(
            'script',
            intent: NavigationIntent(
              targetTab: 'script',
              targetAsset: asset,
              port: portNum,
              service: service,
              initialPrompt: prompt,
            ),
          );
        } else if (value == 'vuln') {
          widget.controller.navigateToTab(
            'vuln',
            intent: NavigationIntent(
              targetTab: 'vuln',
              targetAsset: asset,
              port: portNum,
              service: service,
            ),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'exploit',
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, size: 16, color: context.warningSolid),
              const SizedBox(width: 8),
              Text('漏洞利用与 PoC 检索 ($label)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'script',
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 16, color: context.textPrimary),
              const SizedBox(width: 8),
              Text('生成探测脚本 ($label)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'vuln',
          child: Row(
            children: [
              Icon(Icons.bug_report_outlined, size: 16, color: context.accentText),
              const SizedBox(width: 8),
              Text('定向漏洞扫描 ($label)'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: context.bgSelected,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.fontCaption.copyWith(fontSize: 10, color: context.accentText),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 12, color: context.textTertiary),
          ],
        ),
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
              const Text('生成主机测试脚本'),
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
          ),
        );
        break;
      case 'exploit':
        String initialQuery = '';
        for (final p in asset.openPorts) {
          final s = (p['service'] ?? '').toString();
          final port = p['port'];
          if ([21, 22, 23, 25, 53, 80, 443, 445, 1433, 1521, 3306, 3389, 5432, 5900, 6379, 7001, 8080, 8443, 9200, 27017].contains(port)) {
            initialQuery = s.isNotEmpty ? s : '$port';
            break;
          }
        }
        if (initialQuery.isEmpty && asset.openPorts.isNotEmpty) {
          final first = asset.openPorts.first;
          final s = (first['service'] ?? '').toString();
          initialQuery = s.isNotEmpty ? s : '${first['port'] ?? ''}';
        }
        widget.controller.navigateToTab(
          'exploit',
          intent: NavigationIntent(
            targetTab: 'exploit',
            targetAsset: asset,
            initialQuery: initialQuery,
          ),
        );
        break;
      case 'agent':
        final ports = asset.openPorts.map((p) => '${p['port']}/${p['service'] ?? ''}').join(', ');
        final prompt = '针对主机 ${asset.address}${ports.isNotEmpty ? " 及其开放服务 ($ports)" : ""} 展开深度安全合规与暴露风险评估';
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
        final prompt = '编写针对主机 ${asset.address} 的连通性与网络服务探测脚本';
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

  void _showAssetActionDialog(BuildContext context, PentestAsset asset) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: SeverityBadge.colorFor(
                context,
                Severity.fromKey(asset.riskLevel),
              ).withAlpha(45),
              child: Text(
                asset.address.split('.').last,
                style: AppTheme.fontCaption.copyWith(
                  color: SeverityBadge.colorFor(
                    context,
                    Severity.fromKey(asset.riskLevel),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(asset.address, style: context.fontTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '厂商: ${asset.metadata['vendor'] ?? "未知"} · MAC: ${asset.metadata['mac'] ?? "未知"}',
              style: context.fontCaption,
            ),
            if (asset.openPorts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('开放端口 (${asset.openPorts.length}):', style: context.fontBody),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final p in asset.openPorts)
                    _buildPortChip(context, asset, p),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: Icon(Icons.bug_report_outlined, color: context.accentText),
              title: const Text('转至漏洞扫描 (Nuclei)'),
              onTap: () {
                Navigator.pop(context);
                _handleAssetAction(context, asset, 'vuln');
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.bolt_outlined, color: context.warningSolid),
              title: const Text('转至漏洞利用与 PoC 验证'),
              onTap: () {
                Navigator.pop(context);
                _handleAssetAction(context, asset, 'exploit');
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.psychology_outlined, color: context.accentText),
              title: const Text('委托 Security Agent 深度评估'),
              onTap: () {
                Navigator.pop(context);
                _handleAssetAction(context, asset, 'agent');
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.code_rounded, color: context.textPrimary),
              title: const Text('生成测试脚本'),
              onTap: () {
                Navigator.pop(context);
                _handleAssetAction(context, asset, 'script');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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
            hintText: '例如：主办公网关、开发服务器等',
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
