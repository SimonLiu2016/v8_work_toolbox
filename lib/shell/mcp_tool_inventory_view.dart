import 'package:flutter/material.dart';

import '../components/app_components.dart';
import '../services/ai_config_store.dart';
import '../services/mcp_service.dart';
import '../theme/app_theme.dart';

/// 「外部 MCP 客户端」页签内的已加载 MCP 工具清单。
///
/// 数据源是各客户端「测试连接与探测工具」留下的 [McpServerStatus.tools]
/// （[probeResults]），**不**调用 `McpService.getAllTools()`——那会为每个
/// 启用的客户端真实拉起 stdio 子进程，设置页不该有这种隐藏副作用。未探测的
/// 客户端显示占位，避免"没测过"被误读成"没有工具"。
///
/// 以 `client.enabled` 为闸门：停用的客户端不展示工具，回退为占位，使显示的
/// 清单始终反映"当前实际可用"而非历史探测残留。
class McpToolInventoryView extends StatelessWidget {
  const McpToolInventoryView({
    super.key,
    required this.clients,
    required this.probeResults,
  });

  final List<McpClientConfig> clients;

  /// clientId → 该客户端最近一次探测结果；未探测的客户端不在此表中。
  final Map<String, McpServerStatus?> probeResults;

  @override
  Widget build(BuildContext context) {
    // 只列出"已探测过"的客户端；未探测的由下方整体占位统一说明。
    final probed = clients
        .where((c) => probeResults.containsKey(c.id))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTheme.space24),
        Text('已加载的 MCP 工具', style: AppTheme.fontTitle),
        const SizedBox(height: AppTheme.space8),
        Text(
          '工具来自客户端的连接探测结果，不会在打开本页时自动拉起进程。',
          style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
        ),
        const SizedBox(height: AppTheme.space16),
        if (probed.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space24),
              child: Row(
                children: [
                  const Icon(Icons.bolt_outlined,
                      size: 20, color: AppTheme.textTertiary),
                  const SizedBox(width: AppTheme.space12),
                  Expanded(
                    child: Text(
                      '尚未探测任何客户端。点击上方客户端的「测试连接与探测工具」后，'
                      '其工具将显示在这里。',
                      style: AppTheme.fontCaption.copyWith(
                          color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...probed.map((c) => _ClientToolGroup(c, probeResults[c.id])),
      ],
    );
  }
}

/// 单个客户端的工具分组。
class _ClientToolGroup extends StatelessWidget {
  const _ClientToolGroup(this.client, this.status);

  final McpClientConfig client;

  /// 该客户端最近一次探测结果。调用方保证非空（仅传入已探测的客户端）。
  final McpServerStatus? status;

  @override
  Widget build(BuildContext context) {
    final tools = status?.tools ?? const [];
    final enabled = client.enabled;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cable_outlined,
                    size: 16,
                    color:
                        enabled ? AppTheme.accentLight : AppTheme.textTertiary,
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(client.name, style: AppTheme.fontTitle),
                  const SizedBox(width: AppTheme.space8),
                  AppBadge(label: '${tools.length} 个工具'),
                ],
              ),
              const SizedBox(height: AppTheme.space12),
              if (!enabled)
                Text(
                  '该客户端已停用，工具未加载。启用后重新探测即可在此查看。',
                  style: AppTheme.fontCaption.copyWith(
                      color: AppTheme.textTertiary),
                )
              else if (tools.isEmpty)
                Text(
                  '探测完成，但该客户端未发现工具。',
                  style: AppTheme.fontCaption.copyWith(
                      color: AppTheme.textTertiary),
                )
              else
                // 工具数可达数十条，独立滚动容器避免撑高整个页签。
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tools.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppTheme.borderSubtle),
                    itemBuilder: (ctx, idx) {
                      final t = tools[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.space8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.bolt,
                                size: 14, color: AppTheme.accentLight),
                            const SizedBox(width: AppTheme.space8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (t.description.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      t.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.fontCaption.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
