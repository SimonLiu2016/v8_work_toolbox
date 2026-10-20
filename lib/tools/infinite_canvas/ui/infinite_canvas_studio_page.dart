import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/app_components.dart';
import '../../../services/settings_store.dart';
import '../../../theme/app_theme.dart';
import '../models/infinite_canvas_config.dart';
import '../models/infinite_canvas_state.dart';
import '../services/infinite_canvas_bridge_server.dart';
import '../services/infinite_canvas_compose_service.dart';
import '../services/infinite_canvas_config_store.dart';
import '../services/infinite_canvas_image_build_service.dart';
import 'infinite_canvas_asset_bridge_panel.dart';
import 'infinite_canvas_log_viewer.dart';

/// 无限画布工具主页面（spec: 容器启停与状态呈现）。
///
/// 布局：状态卡 → 配置卡 → 构建区 → 失败卡 → 日志查看器 → 数据位置卡 →
/// 能力边界说明。
///
/// 后两块**不可折叠**：spec 要求它们「出现在用户首次进入工具时可见的位置，
/// 而不是仅存在于文档中」，折叠面板不满足这一点（与 ARTEX 同理）。
class InfiniteCanvasStudioPage extends StatefulWidget {
  const InfiniteCanvasStudioPage({super.key});

  @override
  State<InfiniteCanvasStudioPage> createState() => _InfiniteCanvasStudioPageState();
}

class _InfiniteCanvasStudioPageState extends State<InfiniteCanvasStudioPage> {
  final InfiniteCanvasComposeService _engine = InfiniteCanvasComposeService.instance;
  final InfiniteCanvasImageBuildService _build = InfiniteCanvasImageBuildService.instance;
  final InfiniteCanvasConfigStore _config = InfiniteCanvasConfigStore.instance;
  final InfiniteCanvasBridgeServer _bridge = InfiniteCanvasBridgeServer.instance;

  late final TextEditingController _dirController;
  late final TextEditingController _portController;
  late final TextEditingController _bridgePortController;
  bool _stopOnExit = true;
  bool _useLocalImage = false;

  @override
  void initState() {
    super.initState();
    _dirController = TextEditingController(text: _config.config.projectDir);
    _portController = TextEditingController(text: '${_config.config.httpPort}');
    _bridgePortController = TextEditingController(
      text: '${_config.config.bridgePort}',
    );
    _stopOnExit = _config.config.stopOnAppExit;
    _useLocalImage = _config.config.useLocalImage;
    _config.addListener(_onConfigChanged);
    _build.addListener(_onBuildChanged);
    _bridge.start();
    _config.load();
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _build.removeListener(_onBuildChanged);
    _dirController.dispose();
    _portController.dispose();
    _bridgePortController.dispose();
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
    if (_bridgePortController.text != '${_config.config.bridgePort}') {
      _bridgePortController.text = '${_config.config.bridgePort}';
    }
    _stopOnExit = _config.config.stopOnAppExit;
    _useLocalImage = _config.config.useLocalImage;
  }

  void _onBuildChanged() {
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // 动作
  // -------------------------------------------------------------------------

  Future<void> _saveConfig() async {
    final port = int.tryParse(_portController.text.trim()) ?? 3177;
    final bridgePort = int.tryParse(_bridgePortController.text.trim()) ?? 8798;
    await _config.save(
      _config.config.copyWith(
        projectDir: _dirController.text.trim(),
        httpPort: port,
        bridgePort: bridgePort,
        stopOnAppExit: _stopOnExit,
        useLocalImage: _useLocalImage,
      ),
    );
    // 端口变了要重启资产桥，否则插件还在打旧端口。
    await _restartBridgeIfRunning();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已保存，下次启动生效')),
    );
  }

  Future<void> _restartBridgeIfRunning() async {
    if (!_bridge.isRunning) return;
    await _bridge.stop();
    await _bridge.start();
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
                const InfiniteCanvasAssetBridgePanel(),
                const SizedBox(height: AppTheme.space16),
                SizedBox(
                  height: 260,
                  child: InfiniteCanvasLogViewer(
                    lines: _build.isBuilding ? _build.lines : state.containerLogTail,
                    title: _build.isBuilding ? '构建日志' : '容器日志',
                    busy: _build.isBuilding || state.isBusy,
                    emptyHint: _build.isBuilding ? '等待输出…' : '暂无日志',
                  ),
                ),
                const SizedBox(height: AppTheme.space16),
                _buildPluginInstallCard(context),
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
    InfiniteCanvasState state,
    InfiniteCanvasConfig cfg,
  ) {
    final (statusText, statusColor) = switch (state.status) {
      InfiniteCanvasStatus.running => ('运行中', context.successText),
      InfiniteCanvasStatus.starting => ('启动中…', context.infoText),
      InfiniteCanvasStatus.stopping => ('停止中…', context.infoText),
      InfiniteCanvasStatus.failed => ('失败', context.errorText),
      InfiniteCanvasStatus.stopped => ('已停止', context.textSecondary),
      InfiniteCanvasStatus.idle => ('未启动', context.textSecondary),
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
                    Text('无限画布', style: context.fontTitle),
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      'AI 图片创作工作台 · Docker 容器托管',
                      style: context.fontCaption,
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: state.status == InfiniteCanvasStatus.running ||
                    state.status == InfiniteCanvasStatus.starting,
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
              if (state.status == InfiniteCanvasStatus.failed)
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
    InfiniteCanvasConfig cfg,
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
            hintText: InfiniteCanvasConfig.defaultProjectDir,
            helperText: '无限画布仓库位置（需含 Dockerfile 与 compose 文件）',
          ),
          const SizedBox(height: AppTheme.space8),
          AppTextField(
            controller: _portController,
            label: '工作台端口',
            hintText: '3177',
            helperText: '工作台访问端口（只绑 127.0.0.1），冲突时换个空闲值',
          ),
          const SizedBox(height: AppTheme.space8),
          AppTextField(
            controller: _bridgePortController,
            label: '资产桥端口',
            hintText: '8798',
            helperText: '本机回环服务端口，供画布插件读写剧集数据',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSwitch(
                value: _useLocalImage,
                onChanged: (v) => setState(() => _useLocalImage = v),
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  '用本地构建的镜像（infinite-canvas:local）',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (_useLocalImage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '打开前请先在无限画布仓库执行 docker build -t '
                '${InfiniteCanvasConfig.localImageName} .，否则启动会报'
                '「镜像未拉取」。',
                style: TextStyle(color: context.warningText, fontSize: 11),
              ),
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
          const AppSectionHeader(title: '镜像'),
          const SizedBox(height: AppTheme.space8),
          Text(
            '默认从 ghcr.io 拉取已发布镜像，点「启动」即可。'
            '只有要跑你本地改过的代码时才需要本地构建。',
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
    InfiniteCanvasState state,
  ) {
    if (state.status != InfiniteCanvasStatus.failed || state.failure == null) {
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

  Widget _buildPluginInstallCard(BuildContext context) {
    final url = '${_bridge.baseUrl}/v8-plugin.js';
    final installed = _bridge.lastHandshakeAt != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('安装画布插件', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Text(
            '在无限画布的「节点插件」面板里选择「按 URL 安装」，填入下面的地址。'
            '装一次即由无限画布自己记住，重启浏览器不用重装。',
            style: context.fontBodySecondary,
          ),
          const SizedBox(height: AppTheme.space12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.textTertiary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              _bridge.isRunning ? url : '资产桥服务未运行',
              style: AppTheme.fontCaption.copyWith(fontFamily: 'Menlo'),
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              AppButton.secondary(
                label: '复制插件地址',
                icon: Icons.copy,
                onPressed: _bridge.isRunning
                    ? () => _copyToClipboard(url, '插件地址')
                    : null,
              ),
              AppButton.secondary(
                label: '复制资产桥密钥',
                icon: Icons.key_outlined,
                onPressed: () => _copyToClipboard(
                  _bridgeSecret(),
                  '资产桥密钥',
                ),
              ),
              if (!_bridge.isRunning)
                AppButton.secondary(
                  label: '重试启动资产桥',
                  icon: Icons.refresh,
                  onPressed: () => _bridge.start(),
                ),
            ],
          ),
          if (_bridge.lastError != null) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              _bridge.lastError!,
              style: TextStyle(color: context.errorText, fontSize: 11),
            ),
          ],
          const SizedBox(height: AppTheme.space8),
          Text(
            installed ? '插件已连接' : '尚未检测到插件连接',
            style: TextStyle(
              color: installed ? context.successText : context.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _bridgeSecret() {
    // 资产桥复用本地词典桥的密钥槽——两者都是「只听回环 + 密钥校验」的服务，
    // 密钥的生成与持久化语义完全同构。
    return SettingsStore.instance.localDictionaryBridgeSecretOrEmpty;
  }

  Widget _buildCapabilityNotice(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('能力边界', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Text(
            '本工具只负责托管容器与在两侧搬运资产，不实现任何无限画布创作能力：\n'
            '· 出图、出视频都在无限画布工作台内完成，用你自己配置的渠道；\n'
            '· 资产桥只写内容节点与参考素材，不写画布连线、不触发生成；\n'
            '· 渠道密钥只存在浏览器本地，不经过本工具。',
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
