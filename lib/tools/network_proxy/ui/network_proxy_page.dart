import 'package:flutter/material.dart';

import '../../../components/app_components.dart';
import '../../../services/proxy_settings.dart';
import '../../../theme/app_theme.dart';
import '../services/clash_subscription_parser.dart';
import '../services/network_proxy_service.dart';

/// 系统级「网络代理」独立页面
class NetworkProxyPage extends StatefulWidget {
  const NetworkProxyPage({super.key});

  @override
  State<NetworkProxyPage> createState() => _NetworkProxyPageState();
}

class _NetworkProxyPageState extends State<NetworkProxyPage> {
  final _urlCtrl = TextEditingController();
  final _service = NetworkProxyService.instance;
  final _proxySettings = ProxySettings.instance;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = _service.subscriptionUrl;
    _service.addListener(_onServiceUpdate);
    _proxySettings.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _proxySettings.removeListener(_onServiceUpdate);
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.bgContent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space24,
              38 + AppTheme.space8,
              AppTheme.space24,
              AppTheme.space8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('网络代理管理', style: AppTheme.fontHeadline),
                    const SizedBox(height: AppTheme.space4),
                    Text(
                      '通过 Clash 订阅拉取代理节点，由内嵌代理内核提供本地 HTTP 通道。仅本软件工具生效，不影响外部其他应用。',
                      style: AppTheme.fontCaption.copyWith(
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
                // 全局总开关
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _proxySettings.enabled ? '全局代理通道已启用' : '全局代理通道已停用',
                      style: AppTheme.fontBody.copyWith(
                        color: _proxySettings.enabled
                            ? context.accentText
                            : context.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: AppTheme.space8),
                    AppSwitch(
                      value: _proxySettings.enabled,
                      onChanged: (val) async {
                        try {
                          await _service.setGlobalEnabled(val);
                          if (_service.lastError != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_service.lastError!),
                                backgroundColor: context.errorSolid,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('设置代理开关失败: $e'),
                                backgroundColor: context.errorSolid,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderSubtle),

          // 主体内容滚动区
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppTheme.space24),
              children: [
                // 1. 订阅管理卡片
                _buildSubscriptionCard(),
                const SizedBox(height: AppTheme.space16),

                // 2. 状态提示 / 错误提示
                if (_service.lastError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppTheme.space12),
                    decoration: BoxDecoration(
                      color: context.errorText.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: context.errorText.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: context.errorText, size: 18),
                        const SizedBox(width: AppTheme.space8),
                        Expanded(
                          child: Text(
                            _service.lastError!,
                            style: AppTheme.fontBody.copyWith(color: context.errorText),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.space16),
                ],

                // 3. 节点列表控制栏
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '代理节点列表 (${_service.nodes.length})',
                          style: AppTheme.fontTitle,
                        ),
                        if (_service.selectedNodeName != null) ...[
                          const SizedBox(width: AppTheme.space8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.accentText.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: context.accentSolid.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              '当前生效: ${_service.selectedNodeName}',
                              style: AppTheme.fontCaption.copyWith(color: context.accentText),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        AppButton.secondary(
                          label: _service.isTestingSpeed ? '正在测速...' : '全部测速',
                          icon: Icons.speed_rounded,
                          isLoading: _service.isTestingSpeed,
                          onPressed: _service.nodes.isEmpty || _service.isTestingSpeed
                              ? null
                              : () async {
                                  await _service.testAllDelays();
                                  if (_service.lastError != null && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_service.lastError!),
                                        backgroundColor: context.errorSolid,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),

                // 4. 节点列表视图
                _buildNodesList(),
              ],
            ),
          ),

          // 底部状态栏
          _buildBottomStatusBar(),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download_outlined, size: 20, color: context.accentText),
                const SizedBox(width: AppTheme.space8),
                Text('订阅地址配置', style: AppTheme.fontTitle),
                const Spacer(),
                if (_service.trafficInfo != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.accentText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _service.trafficInfo!,
                      style: AppTheme.fontCaption.copyWith(color: context.accentText),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                ],
                if (_service.lastRefreshTime != null)
                  Text(
                    '上次更新: ${_formatTime(_service.lastRefreshTime!)}',
                    style: AppTheme.fontCaption.copyWith(color: context.textTertiary),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: AppTheme.fontBody,
                    decoration: const InputDecoration(
                      labelText: 'Clash / Mihomo 订阅 URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.space12),
                AppButton.secondary(
                  label: '保存地址',
                  icon: Icons.save_outlined,
                  onPressed: () async {
                    try {
                      await _service.saveSubscriptionUrl(_urlCtrl.text);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('订阅地址已保存'),
                            backgroundColor: context.successSolid,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: context.errorSolid,
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(width: AppTheme.space8),
                AppButton.primary(
                  label: _service.isRefreshing ? '更新中...' : '更新代理列表',
                  icon: Icons.refresh_rounded,
                  isLoading: _service.isRefreshing,
                  onPressed: _service.isRefreshing
                      ? null
                      : () async {
                          try {
                            if (_urlCtrl.text.trim().isNotEmpty &&
                                _urlCtrl.text.trim() != _service.subscriptionUrl) {
                              await _service.saveSubscriptionUrl(_urlCtrl.text);
                            }
                            await _service.refreshSubscription();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '订阅更新成功，已获取 ${_service.nodes.length} 个代理节点',
                                  ),
                                  backgroundColor: context.successSolid,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('刷新失败: $e'),
                                  backgroundColor: context.errorSolid,
                                ),
                              );
                            }
                          }
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodesList() {
    final nodes = _service.nodes;
    if (nodes.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 40, color: context.textTertiary),
            const SizedBox(height: AppTheme.space8),
            Text(
              '暂无可用代理节点，请先配置订阅地址并点击「更新代理列表」',
              style: AppTheme.fontBody.copyWith(color: context.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: nodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final node = nodes[index];
        final isSelected = node.name == _service.selectedNodeName;
        final delay = _service.delayOf(node.name);

        return AppCard(
          backgroundColor: isSelected
              ? context.accentSolid.withValues(alpha: 0.1)
              : context.bgCard,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await _service.selectNode(node);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space16,
                vertical: AppTheme.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? context.accentText : context.textTertiary,
                    size: 18,
                  ),
                  const SizedBox(width: AppTheme.space12),
                  // 协议类型 Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.borderSubtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      node.type.toUpperCase(),
                      style: AppTheme.fontCaption.copyWith(
                        color: context.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  // 节点名称
                  Expanded(
                    child: Text(
                      node.name,
                      style: AppTheme.fontBody.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? context.textPrimary : context.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  // 测速结果
                  _buildDelayBadge(delay),
                  const SizedBox(width: AppTheme.space8),
                  // 单节点测速按钮
                  IconButton(
                    icon: const Icon(Icons.flash_on_outlined, size: 16),
                    tooltip: '测试该节点延迟',
                    color: context.textTertiary,
                    onPressed: () => _service.testNodeDelay(node.name),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDelayBadge(int? delay) {
    if (delay == null) {
      return Text('-', style: AppTheme.fontCaption.copyWith(color: context.textTertiary));
    }
    Color color;
    if (delay <= 0) {
      return Text('超时', style: AppTheme.fontCaption.copyWith(color: context.errorText));
    } else if (delay < 200) {
      color = context.successSolid;
    } else if (delay < 500) {
      color = context.warningSolid;
    } else {
      color = context.errorSolid;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${delay}ms',
        style: AppTheme.fontCaption.copyWith(color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    final isRunning = _service.isRunning;
    final isConfigured = _proxySettings.isConfigured;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space24,
        vertical: AppTheme.space12,
      ),
      decoration: BoxDecoration(
        color: context.bgSidebar,
        border: Border(top: BorderSide(color: context.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(
            isRunning ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
            size: 16,
            color: isRunning && isConfigured ? context.successText : context.textTertiary,
          ),
          const SizedBox(width: AppTheme.space8),
          Text(
            isRunning
                ? (isConfigured
                    ? '代理运行中 (127.0.0.1:7890) - 全局生效已开启'
                    : '内核已启动 (127.0.0.1:7890) - 但全局开关已关闭，当前直连')
                : '代理内核未运行 (选择节点以启动)',
            style: AppTheme.fontCaption.copyWith(
              color: isRunning && isConfigured ? context.textPrimary : context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }
}
