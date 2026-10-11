import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/app_components.dart';
import '../../../theme/app_theme.dart';
import '../models/toonflow_studio_config.dart';
import '../models/toonflow_studio_state.dart';
import '../services/toonflow_compose_service.dart';
import '../services/toonflow_config_store.dart';
import '../services/toonflow_image_build_service.dart';
import 'toonflow_asset_bridge_panel.dart';
import 'toonflow_log_viewer.dart';

/// Toonflow 漫剧工坊主页面（spec: 容器启停与状态呈现）。
///
/// 布局：状态卡 → 配置卡 → 构建区 → 失败卡 → 日志查看器 → 数据位置卡 →
/// 能力边界说明。
///
/// 后两块**不可折叠**：spec 要求它们「出现在用户首次进入工具时可见的位置，
/// 而不是仅存在于文档中」，折叠面板不满足这一点（与 ARTEX 同理）。
class ToonflowStudioPage extends StatefulWidget {
  const ToonflowStudioPage({super.key});

  @override
  State<ToonflowStudioPage> createState() => _ToonflowStudioPageState();
}

class _ToonflowStudioPageState extends State<ToonflowStudioPage> {
  final ToonflowComposeService _engine = ToonflowComposeService.instance;
  final ToonflowImageBuildService _build = ToonflowImageBuildService.instance;
  final ToonflowConfigStore _config = ToonflowConfigStore.instance;

  late final TextEditingController _dirController;
  late final TextEditingController _portController;
  late final TextEditingController _registryController;
  bool _stopOnExit = true;

  @override
  void initState() {
    super.initState();
    _dirController = TextEditingController(text: _config.config.projectDir);
    _portController = TextEditingController(text: '${_config.config.httpPort}');
    _registryController = TextEditingController(text: _config.config.bunRegistry);
    _stopOnExit = _config.config.stopOnAppExit;
    _config.addListener(_onConfigChanged);
    _build.addListener(_onBuildChanged);
    _config.load();
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _build.removeListener(_onBuildChanged);
    _dirController.dispose();
    _portController.dispose();
    _registryController.dispose();
    super.dispose();
  }

  void _onConfigChanged() {
    if (!mounted) return;
    // 配置被别处改动时同步输入框，避免显示过期值。
    if (_dirController.text != _config.config.projectDir) {
      _dirController.text = _config.config.projectDir;
    }
    if (_portController.text != '${_config.config.httpPort}') {
      _portController.text = '${_config.config.httpPort}';
    }
    if (_registryController.text != _config.config.bunRegistry) {
      _registryController.text = _config.config.bunRegistry;
    }
    _stopOnExit = _config.config.stopOnAppExit;
  }

  void _onBuildChanged() {
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // 动作
  // -------------------------------------------------------------------------

  Future<void> _saveConfig() async {
    final port = int.tryParse(_portController.text.trim()) ?? 3177;
    await _config.save(
      _config.config.copyWith(
        projectDir: _dirController.text.trim(),
        httpPort: port,
        bunRegistry: _registryController.text.trim(),
        stopOnAppExit: _stopOnExit,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已保存，下次启动生效')),
    );
  }

  Future<void> _toggleEngine(bool start) async {
    if (start) {
      await _engine.start();
    } else {
      await _engine.stop();
    }
  }

  Future<void> _buildImage() async {
    await _build.build();
    if (!mounted) return;
    final result = _build.lastResult;
    if (result != null && !result.success) {
      final kind = result.failureKind;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kind == null ? '构建失败' : '${kind.label}：${kind.hint}'),
          duration: const Duration(seconds: 12),
        ),
      );
    }
  }

  void _openWorkspace() {
    Process.run('open', <String>['http://127.0.0.1:${_config.config.httpPort}']);
  }

  void _openDockerApp() {
    Process.run('open', <String>['-a', 'Docker']);
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 已复制')),
    );
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable?>[_engine, _config]),
      builder: (context, _) {
        final state = _engine.state;
        final cfg = _config.config;

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.space20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, state, cfg),
                const SizedBox(height: AppTheme.space16),
                _buildConfigSection(context, cfg),
                const SizedBox(height: AppTheme.space16),
                _buildBuildSection(context),
                const SizedBox(height: AppTheme.space16),
                _buildFailureCard(context, state),
                const SizedBox(height: AppTheme.space16),
                const ToonflowAssetBridgePanel(),
                const SizedBox(height: AppTheme.space16),
                SizedBox(
                  height: 260,
                  child: ToonflowLogViewer(
                    lines: _build.isBuilding ? _build.lines : state.containerLogTail,
                    title: _build.isBuilding ? '构建日志' : '容器日志',
                    busy: _build.isBuilding || state.isBusy,
                    emptyHint: _build.isBuilding ? '等待输出…' : '暂无日志',
                  ),
                ),
                const SizedBox(height: AppTheme.space16),
                _buildDataLocationCard(context, cfg),
                const SizedBox(height: AppTheme.space16),
                _buildCapabilityNotice(context),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // 各区段
  // -------------------------------------------------------------------------

  Widget _buildHeader(
    BuildContext context,
    ToonflowStudioState state,
    ToonflowStudioConfig cfg,
  ) {
    final (statusText, statusColor) = switch (state.status) {
      ToonflowStatus.running => ('运行中', context.successText),
      ToonflowStatus.starting => ('启动中…', context.infoText),
      ToonflowStatus.stopping => ('停止中…', context.infoText),
      ToonflowStatus.failed => ('失败', context.errorText),
      ToonflowStatus.stopped => ('已停止', context.textSecondary),
      ToonflowStatus.idle => ('未启动', context.textSecondary),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_mosaic_outlined, color: context.accentText),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Toonflow 漫剧工坊', style: context.fontTitle),
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      'AI 短剧漫剧平台 · Docker 容器托管',
                      style: context.fontCaption,
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: state.status == ToonflowStatus.running ||
                    state.status == ToonflowStatus.starting,
                onChanged: state.isBusy ? null : _toggleEngine,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          _InfoRow(label: '状态', value: statusText, valueColor: statusColor),
          _InfoRow(
            label: '工作台地址',
            value: 'http://127.0.0.1:${cfg.httpPort}',
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              AppButton.primary(
                label: '打开工作台',
                icon: Icons.open_in_new,
                // 未就绪不可点（spec: 打开工作台与容器未就绪时的引导）。
                onPressed: state.canOpenWorkspace ? _openWorkspace : null,
              ),
              AppButton.secondary(
                label: 'Docker Desktop',
                icon: Icons.settings_outlined,
                onPressed: _openDockerApp,
              ),
              if (state.status == ToonflowStatus.failed)
                AppButton.secondary(
                  label: '重试启动',
                  icon: Icons.refresh,
                  onPressed: () => _engine.start(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(
    BuildContext context,
    ToonflowStudioConfig cfg,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(title: '配置'),
          const SizedBox(height: AppTheme.space8),
          AppTextField(
            controller: _dirController,
            label: 'Compose 工程目录',
            hintText: ToonflowStudioConfig.defaultProjectDir,
            helperText: 'Toonflow 仓库位置（需含 compose.yaml 与 Dockerfile）',
          ),
          const SizedBox(height: AppTheme.space8),
          AppTextField(
            controller: _portController,
            label: 'HTTP 端口',
            hintText: '3177',
            helperText: '工作台访问端口，冲突时换个空闲值',
          ),
          const SizedBox(height: AppTheme.space8),
          AppTextField(
            controller: _registryController,
            label: 'bun 镜像站',
            hintText: ToonflowStudioConfig.defaultBunRegistry,
            helperText: '构建期下载依赖用；国内网络建议保留默认',
          ),
          const SizedBox(height: AppTheme.space8),
          Row(
            children: [
              AppSwitch(
                value: _stopOnExit,
                onChanged: (v) => setState(() => _stopOnExit = v),
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  '应用退出时停止容器',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.secondary(
              label: '保存配置',
              icon: Icons.save_outlined,
              onPressed: _saveConfig,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuildSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(title: '镜像构建'),
          const SizedBox(height: AppTheme.space8),
          Text(
            '首次使用需要构建镜像。实测首次构建约 13 分钟、镜像约 1.8GB，'
            '期间请保持网络畅通。',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              AppButton.primary(
                label: _build.isBuilding ? '构建中…' : '构建镜像',
                icon: Icons.build_outlined,
                onPressed: _build.isBuilding ? null : _buildImage,
              ),
              if (_build.lastResult?.success == true)
                Text(
                  '上次构建成功',
                  style: TextStyle(color: context.successText, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFailureCard(
    BuildContext context,
    ToonflowStudioState state,
  ) {
    if (state.status != ToonflowStatus.failed || state.failure == null) {
      return const SizedBox.shrink();
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: context.errorText),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(state.failure!, style: context.fontTitle),
              ),
            ],
          ),
          if (state.failureDetail != null) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              state.failureDetail!,
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: AppTheme.space8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.secondary(
              label: '复制详情',
              icon: Icons.copy,
              onPressed: () => _copyToClipboard(
                '${state.failure}\n${state.failureDetail ?? ''}',
                '错误详情',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLocationCard(
    BuildContext context,
    ToonflowStudioConfig cfg,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('数据位置', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Text(
            'Toonflow 的数据通过 bind mount 落在本软件数据目录下：\n'
            '· 数据根目录：~/Library/Application Support/V8WorkToolbox/'
            'toonflow_data/\n'
            '· 工作区与素材：toonflow_data/workspaces/<项目>/\n'
            '· 本工具只保存自己的配置与 override 备份（toonflow/）。\n'
            '删除本软件不会删除 Toonflow 数据；备份时请一并考虑上述位置。',
            style: context.fontBodySecondary,
          ),
          const SizedBox(height: AppTheme.space12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.warningText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 16, color: context.warningText),
                const SizedBox(width: AppTheme.space8),
                Expanded(
                  child: Text(
                    'toonflow_data/settings.json 保存 Toonflow 自己的供应商 '
                    'API Key（明文，权限 600）。本工具不读取、不修改、不导出'
                    '该文件；如需配置模型密钥，请在 Toonflow 工作台内操作。',
                    style: TextStyle(
                      color: context.warningText,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityNotice(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('能力边界', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Text(
            '本工具只负责托管容器与在两侧搬运资产，不实现任何 Toonflow 创作能力：\n'
            '· 剧本、分镜、图片与视频生成都在 Toonflow 工作台内完成；\n'
            '· 资产桥只写内容节点与素材文件，不写画布连线、不触发生成；\n'
            '· 本工具不内嵌 Toonflow 的 Web 界面，也不复刻它的交互。',
            style: context.fontBodySecondary,
          ),
        ],
      ),
    );
  }
}

/// 一行「标签 - 值」信息。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? context.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
