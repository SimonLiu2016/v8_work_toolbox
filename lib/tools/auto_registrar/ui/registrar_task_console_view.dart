import 'package:flutter/material.dart';

import '../services/registrar_config_store.dart';
import '../services/registrar_sidecar_service.dart';
import 'registrar_credentials_dialog.dart';

class RegistrarTaskConsoleView extends StatefulWidget {
  const RegistrarTaskConsoleView({super.key});

  @override
  State<RegistrarTaskConsoleView> createState() => _RegistrarTaskConsoleViewState();
}

class _RegistrarTaskConsoleViewState extends State<RegistrarTaskConsoleView> {
  final _service = RegistrarSidecarService.instance;
  final _configStore = RegistrarConfigStore.instance;
  final _scrollController = ScrollController();

  SystemVisionAiInfo _visionAiInfo = const SystemVisionAiInfo();
  bool _loadingAiInfo = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _configStore.addListener(_onConfigChanged);
    _initData();
  }

  Future<void> _initData() async {
    await _configStore.load();
    await _refreshSystemVisionAi();
  }

  Future<void> _refreshSystemVisionAi() async {
    setState(() => _loadingAiInfo = true);
    final info = await _service.resolveSystemVisionAi();
    if (mounted) {
      setState(() {
        _visionAiInfo = info;
        _loadingAiInfo = false;
      });
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _configStore.removeListener(_onConfigChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleToggleTask() async {
    if (_service.isRunning) {
      await _service.stopTasks();
    } else {
      final cfg = _configStore.config;

      // 如果选择的是 AI 视觉模式，检查系统 AI 是否可用
      if (cfg.captchaMode == 'ai_vision' && !_visionAiInfo.isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动失败：系统 AI 视觉多模态尚未就绪 (${_visionAiInfo.errorMessage ?? "请先在系统设置配置 AI"})'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _service.startTasks(
        concurrency: cfg.concurrency,
        targetDomain: cfg.targetDomain,
        useProxy: cfg.useProxy,
        proxyServer: '127.0.0.1:6160',
        captchaMode: cfg.captchaMode,
        capSolverApiKey: cfg.capSolverApiKey,
        aiVisionApiKey: _visionAiInfo.apiKey,
        aiVisionEndpoint: _visionAiInfo.baseUrl,
        aiVisionModel: _visionAiInfo.model,
        smsApiKey: cfg.smsApiKey,
        smsCountry: cfg.smsCountry,
        recoveryEmail: cfg.recoveryEmail,
        imapAuth: cfg.imapAuth,
        imapServer: cfg.imapServer,
        imapPort: cfg.imapPort,
      );
    }
  }

  void _openCredentialsDialog() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => const RegistrarCredentialsDialog(),
    );
    if (res == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _service.stats;
    final cfg = _configStore.config;

    return Row(
      children: [
        // 左侧日常配置面板
        SizedBox(
          width: 330,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Text('任务控制台', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      tooltip: '配置一次性接码与邮箱凭证',
                      onPressed: _openCredentialsDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 凭据就绪状态卡片
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            cfg.recoveryEmail.isNotEmpty && cfg.imapAuth.isNotEmpty
                                ? Icons.check_circle_rounded
                                : Icons.info_outline,
                            size: 16,
                            color: cfg.recoveryEmail.isNotEmpty && cfg.imapAuth.isNotEmpty
                                ? Colors.green
                                : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              cfg.recoveryEmail.isNotEmpty
                                  ? '恢复邮箱: ${cfg.recoveryEmail}'
                                  : '未设置安全恢复邮箱 (点击右上角设置)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            cfg.smsApiKey.isNotEmpty ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            size: 16,
                            color: cfg.smsApiKey.isNotEmpty ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cfg.smsApiKey.isNotEmpty ? 'SMS 接码服务: 已就绪' : 'SMS 接码: 未启用 (可选)',
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 并发数
                Row(
                  children: [
                    const Text('并发线程数'),
                    const Spacer(),
                    DropdownButton<int>(
                      value: cfg.concurrency,
                      underline: const SizedBox(),
                      items: [1, 2, 3, 5, 8].map((c) => DropdownMenuItem(value: c, child: Text('$c 线程'))).toList(),
                      onChanged: _service.isRunning
                          ? null
                          : (v) {
                              if (v != null) {
                                _configStore.save(cfg.copyWith(concurrency: v));
                              }
                            },
                    ),
                  ],
                ),
                // 域名后缀
                Row(
                  children: [
                    const Text('目标域名'),
                    const Spacer(),
                    DropdownButton<String>(
                      value: cfg.targetDomain,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'outlook.com', child: Text('@outlook.com')),
                        DropdownMenuItem(value: 'hotmail.com', child: Text('@hotmail.com')),
                      ],
                      onChanged: _service.isRunning
                          ? null
                          : (v) {
                              if (v != null) {
                                _configStore.save(cfg.copyWith(targetDomain: v));
                              }
                            },
                    ),
                  ],
                ),
                // 代理开关
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('通过本地代理网络'),
                  subtitle: const Text('127.0.0.1:6160 (Mihomo)'),
                  value: cfg.useProxy,
                  onChanged: _service.isRunning
                      ? null
                      : (v) => _configStore.save(cfg.copyWith(useProxy: v)),
                ),
                const Divider(),

                // 验证码模式
                Row(
                  children: [
                    const Text('人机解题模式'),
                    const Spacer(),
                    DropdownButton<String>(
                      value: cfg.captchaMode,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'ai_vision', child: Text('系统 AI 视觉')),
                        DropdownMenuItem(value: 'capsolver', child: Text('CapSolver')),
                      ],
                      onChanged: _service.isRunning
                          ? null
                          : (v) {
                              if (v != null) {
                                _configStore.save(cfg.copyWith(captchaMode: v));
                              }
                            },
                    ),
                  ],
                ),

                // AI 视觉状态卡片（直接复用系统配置）
                if (cfg.captchaMode == 'ai_vision') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _visionAiInfo.isAvailable
                          ? Colors.green.withAlpha(20)
                          : Colors.orange.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _visionAiInfo.isAvailable
                            ? Colors.green.withAlpha(80)
                            : Colors.orange.withAlpha(80),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _visionAiInfo.isAvailable ? Icons.auto_awesome : Icons.warning_amber_rounded,
                              size: 16,
                              color: _visionAiInfo.isAvailable ? Colors.green[700] : Colors.orange[800],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '复用系统 AI 视觉配置',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _visionAiInfo.isAvailable ? Colors.green[800] : Colors.orange[800],
                              ),
                            ),
                            const Spacer(),
                            if (_loadingAiInfo)
                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                            else
                              InkWell(
                                onTap: _refreshSystemVisionAi,
                                child: const Icon(Icons.refresh, size: 14),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_visionAiInfo.isAvailable)
                          Text(
                            '模型: ${_visionAiInfo.providerName} / ${_visionAiInfo.model}',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          )
                        else
                          Text(
                            _visionAiInfo.errorMessage ?? '未在系统配置中检测到可用多模态模型',
                            style: const TextStyle(fontSize: 11, color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    cfg.capSolverApiKey.isNotEmpty ? 'CapSolver Key 已就绪' : '未配置 CapSolver Key (在右上角设置中填写)',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _service.isRunning ? Colors.red : theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(_service.isRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_service.isRunning ? '停止注册任务' : '启动自动化注册'),
                  onPressed: _handleToggleTask,
                ),
              ],
            ),
          ),
        ),
        // 右侧状态与日志终端
        Expanded(
          child: Column(
            children: [
              // 统计指标条
              Container(
                padding: const EdgeInsets.all(12),
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard('在途任务', '${stats.running}', Colors.blue),
                    _buildStatCard('注册成功', '${stats.success}', Colors.green),
                    _buildStatCard('遇到失败', '${stats.failed}', Colors.red),
                    _buildStatCard('累计解出码', '${stats.captchaSolved}', Colors.orange),
                    _buildStatCard('已使用接码', '${stats.smsUsed}', Colors.purple),
                  ],
                ),
              ),
              // 终端控制条
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.black87,
                child: Row(
                  children: [
                    const Icon(Icons.terminal, color: Colors.greenAccent, size: 16),
                    const SizedBox(width: 8),
                    const Text('任务实时运行日志', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _service.clearLogs(),
                      child: const Text('清空日志', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              // 日志列表终端
              Expanded(
                child: Container(
                  color: const Color(0xFF1E1E1E),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _service.logs.length,
                    itemBuilder: (ctx, i) {
                      final log = _service.logs[i];
                      Color msgColor = Colors.white70;
                      if (log.level == 'error') msgColor = Colors.redAccent;
                      if (log.level == 'warn') msgColor = Colors.amberAccent;
                      if (log.level == 'success') msgColor = Colors.greenAccent;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '[${log.timestamp.split('T').last.split('.').first}] ${log.workerId > 0 ? "[#${log.workerId}] " : ""}${log.message}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: msgColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
