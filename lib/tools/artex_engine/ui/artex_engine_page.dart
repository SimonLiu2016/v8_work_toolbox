import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/app_components.dart';
import '../../../theme/app_theme.dart';
import '../models/artex_engine_config.dart';
import '../models/artex_engine_state.dart';
import '../services/artex_ca_service.dart';
import '../services/artex_callback_service.dart';
import '../services/artex_compose_service.dart';
import '../services/artex_config_store.dart';
import '../services/artex_image_build_service.dart';
import 'artex_log_viewer.dart';

/// ARTEX 引擎工具主页面（task 8）。
///
/// 布局：上半是状态与控制，中间是构建/容器日志，下半是三块**不可折叠**的
/// 说明区（数据位置、能力边界、根 CA）——spec 要求它们「出现在用户首次进入
/// 工具时可见的位置，而不是仅存在于文档中」，折叠面板不满足这一点。
class ArtexEnginePage extends StatefulWidget {
  const ArtexEnginePage({super.key});

  @override
  State<ArtexEnginePage> createState() => _ArtexEnginePageState();
}

class _ArtexEnginePageState extends State<ArtexEnginePage> {
  final ArtexComposeService _engine = ArtexComposeService.instance;
  final ArtexImageBuildService _build = ArtexImageBuildService.instance;
  final ArtexConfigStore _config = ArtexConfigStore.instance;
  final ArtexCaService _ca = ArtexCaService.instance;

  late final TextEditingController _dirController;
  late final TextEditingController _httpPortController;
  late final TextEditingController _proxyPortController;
  late final TextEditingController _callbackAddrController;
  late final TextEditingController _tunnelPortMinController;
  late final TextEditingController _tunnelPortMaxController;

  ArtexCaState _caState = ArtexCaState.notGenerated;
  bool _caChecking = true;

  /// 探测到的候选回连地址（多网卡时供选择）。
  List<String> _callbackCandidates = const [];

  /// 上次启动时实际使用的回连地址。用于检测 DHCP 换 IP。
  ///
  /// 存在 config 里而不是内存：用户可能关掉工具再打开，那时「地址变了」
  /// 这个事实依然要能被发现。
  String? _lastUsedCallbackAddr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshCallbackCandidates();
  }

  /// 后台探测候选回连地址，用于「当前地址」提示与多网卡选择。
  Future<void> _refreshCallbackCandidates() async {
    final candidates = await ArtexCallbackService.detectCandidates();
    if (!mounted) return;
    setState(() => _callbackCandidates = candidates);
    _warnIfCallbackAddrChanged();
  }

  /// DHCP 换 IP 后提示用户：旧地址写进了目标机上的 chisel client，不重启
  /// 引擎的话它们仍然回连到那个已经不存在的地址。
  void _warnIfCallbackAddrChanged() {
    final pinned = _config.config.callbackAddr?.trim();
    // 手动填定的人自己知道地址是什么，不用提醒。
    if (pinned != null && pinned.isNotEmpty) return;
    final last = _lastUsedCallbackAddr;
    if (last == null || last.isEmpty) return;
    final current = _callbackCandidates.contains(last)
        ? last
        : (_callbackCandidates.isEmpty ? null : _callbackCandidates.first);
    if (current == null || current == last) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('回连地址已从 $last 变为 $current，重启引擎后生效'),
        duration: const Duration(seconds: 8),
      ),
    );
    _lastUsedCallbackAddr = current;
  }

  @override
  void initState() {
    super.initState();
    _dirController = TextEditingController(text: _config.config.projectDir);
    _httpPortController = TextEditingController(
      text: '${_config.config.httpPort}',
    );
    _proxyPortController = TextEditingController(
      text: '${_config.config.proxyPort}',
    );
    _callbackAddrController = TextEditingController(
      text: _config.config.callbackAddr ?? '',
    );
    _tunnelPortMinController = TextEditingController(
      text: '${_config.config.tunnelPortMin}',
    );
    _tunnelPortMaxController = TextEditingController(
      text: '${_config.config.tunnelPortMax}',
    );
    _config.addListener(_onConfigChanged);
    _build.addListener(_onBuildChanged);
    _refreshCaState();
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _build.removeListener(_onBuildChanged);
    _dirController.dispose();
    _httpPortController.dispose();
    _proxyPortController.dispose();
    _callbackAddrController.dispose();
    _tunnelPortMinController.dispose();
    _tunnelPortMaxController.dispose();
    super.dispose();
  }

  void _onConfigChanged() {
    // 配置被别处改动时同步输入框，避免显示过期值。
    if (_dirController.text != _config.config.projectDir) {
      _dirController.text = _config.config.projectDir;
    }
    if (_httpPortController.text != '${_config.config.httpPort}') {
      _httpPortController.text = '${_config.config.httpPort}';
    }
    if (_proxyPortController.text != '${_config.config.proxyPort}') {
      _proxyPortController.text = '${_config.config.proxyPort}';
    }
    final callback = _config.config.callbackAddr ?? '';
    if (_callbackAddrController.text != callback) {
      _callbackAddrController.text = callback;
    }
    if (_tunnelPortMinController.text != '${_config.config.tunnelPortMin}') {
      _tunnelPortMinController.text = '${_config.config.tunnelPortMin}';
    }
    if (_tunnelPortMaxController.text != '${_config.config.tunnelPortMax}') {
      _tunnelPortMaxController.text = '${_config.config.tunnelPortMax}';
    }
  }

  void _onBuildChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshCaState() async {
    final state = await _ca.detect(_config.config.projectDir);
    if (!mounted) return;
    setState(() {
      _caState = state;
      _caChecking = false;
    });
  }

  // -------------------------------------------------------------------------
  // 动作
  // -------------------------------------------------------------------------

  Future<void> _toggleEngine(bool start) async {
    if (start) {
      await _engine.start();
      await _refreshCaState();
      _recordUsedCallbackAddr();
    } else {
      await _engine.stop();
    }
  }

  Future<void> _buildImage() async {
    await _build.build();
    if (!mounted) return;
    final result = _build.lastResult;
    if (result != null && !result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.failureKind?.hint ?? '构建失败')),
      );
    }
  }

  void _openWorkspace() {
    final url = 'http://127.0.0.1:${_config.config.httpPort}';
    Process.run('open', <String>[url]);
  }

  void _openDockerApp() {
    Process.run('open', <String>['-a', 'Docker']);
  }

  Future<void> _savePorts() async {
    final httpPort = int.tryParse(_httpPortController.text.trim());
    final proxyPort = int.tryParse(_proxyPortController.text.trim());
    if (httpPort == null || httpPort < 1 || httpPort > 65535) {
      _showError('HTTP 端口必须是 1-65535 之间的数字');
      return;
    }
    if (proxyPort == null || proxyPort < 1 || proxyPort > 65535) {
      _showError('代理端口必须是 1-65535 之间的数字');
      return;
    }
    if (httpPort == proxyPort) {
      _showError('HTTP 端口与代理端口不能相同');
      return;
    }
    await _config.save(
      _config.config.copyWith(httpPort: httpPort, proxyPort: proxyPort),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('端口已保存，下次启动生效')));
  }

  /// 记下这次启动实际用的回连地址，供下次打开时检测变化。
  void _recordUsedCallbackAddr() {
    final pinned = _config.config.callbackAddr?.trim();
    _lastUsedCallbackAddr =
        (pinned != null && pinned.isNotEmpty)
            ? pinned
            : (_callbackCandidates.isEmpty
                  ? null
                  : _callbackCandidates.first);
  }

  /// 回连地址下方的说明文字：告诉用户当前会用哪个地址。
  String _callbackHintText() {
    final pinned = _config.config.callbackAddr?.trim();
    if (pinned != null && pinned.isNotEmpty) {
      return '当前使用手动指定的 $pinned（清空则恢复自动探测）';
    }
    if (_callbackCandidates.isEmpty) {
      return '未探测到可用的物理网卡地址，启动时会再次尝试';
    }
    final auto = _callbackCandidates.first;
    final extra = _callbackCandidates.length > 1
        ? '（检测到 ${_callbackCandidates.length} 个候选，启动时需选择）'
        : '';
    return '当前将自动使用 $auto$extra';
  }

  /// 点候选芯片：填入手动值并保存，避开「多候选要选」那一步。
  Future<void> _pickCallbackAddr(String addr) async {
    _callbackAddrController.text = addr;
    await _config.save(_config.config.copyWith(callbackAddr: addr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('回连地址已设为 $addr，下次启动生效')),
    );
  }

  Future<void> _saveInternalNetwork() async {
    final rawCallback = _callbackAddrController.text.trim();
    // 留空 = 恢复自动探测（与 config 的 null 语义对应）。
    final callback = rawCallback.isEmpty ? null : rawCallback;
    if (callback != null && !_isIPv4(callback)) {
      _showError('回连地址必须是 IPv4 格式（例如 192.168.1.3）');
      return;
    }

    final min = int.tryParse(_tunnelPortMinController.text.trim());
    final max = int.tryParse(_tunnelPortMaxController.text.trim());
    if (min == null || max == null || min < 1 || max > 65535) {
      _showError('隧道池端口必须是 1-65535 之间的数字');
      return;
    }
    if (min > max) {
      _showError('隧道池起始端口不能大于结束端口');
      return;
    }
    // 与引擎端口重叠会让预检永远报冲突，且 NAT 目标会撞车。
    final enginePorts = {_config.config.httpPort, _config.config.proxyPort};
    if (enginePorts.contains(min) || enginePorts.contains(max)) {
      _showError('隧道池端口不能与 HTTP / 代理端口相同');
      return;
    }

    await _config.save(
      _config.config.copyWith(
        callbackAddr: callback,
        tunnelPortMin: min,
        tunnelPortMax: max,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('内网设置已保存，下次启动生效')),
    );
  }

  static bool _isIPv4(String value) =>
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').hasMatch(value);

  Future<void> _saveProjectDir() async {
    final dir = _dirController.text.trim();
    if (dir.isEmpty) {
      _showError('工程目录不能为空');
      return;
    }
    await _config.save(_config.config.copyWith(projectDir: dir));
    await _refreshCaState();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('工程目录已保存')));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyToClipboard(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what 已复制到剪贴板')));
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
                SizedBox(
                  height: 260,
                  child: ArtexLogViewer(
                    lines: _build.isBuilding
                        ? _build.lines
                        : state.containerLogTail,
                    title: _build.isBuilding ? '构建日志' : '容器日志',
                    busy: _build.isBuilding || state.isBusy,
                    emptyHint: _build.isBuilding ? '等待输出…' : '暂无日志',
                  ),
                ),
                const SizedBox(height: AppTheme.space16),
                _buildCapabilityNotice(context),
                const SizedBox(height: AppTheme.space16),
                _buildDataLocationCard(context, cfg),
                const SizedBox(height: AppTheme.space16),
                _buildCaSection(context),
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
    ArtexEngineState state,
    ArtexEngineConfig cfg,
  ) {
    final (statusText, statusColor) = switch (state.status) {
      ArtexEngineStatus.running => ('运行中', context.successText),
      ArtexEngineStatus.starting => ('启动中…', context.infoText),
      ArtexEngineStatus.stopping => ('停止中…', context.infoText),
      ArtexEngineStatus.failed => ('失败', context.errorText),
      ArtexEngineStatus.stopped => ('已停止', context.textSecondary),
      ArtexEngineStatus.idle => ('未启动', context.textSecondary),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, color: context.accentText),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ARTEX 渗透引擎', style: context.fontTitle),
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      'AI 自主渗透测试平台 · Docker 容器托管',
                      style: context.fontCaption,
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value:
                    state.status == ArtexEngineStatus.running ||
                    state.status == ArtexEngineStatus.starting,
                onChanged: state.isBusy ? null : _toggleEngine,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          _InfoRow(
            label: '状态',
            value: statusText,
            valueColor: statusColor,
          ),
          _InfoRow(
            label: '工作台地址',
            value: 'http://127.0.0.1:${cfg.httpPort}',
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              AppButton(
                label: '打开工作台',
                icon: Icons.open_in_new,
                variant: AppButtonVariant.primary,
                // 未就绪不可点——spec「打开引擎工作台」的未就绪场景。
                onPressed: state.canOpenWorkspace ? _openWorkspace : null,
              ),
              AppButton(
                label: 'Docker Desktop',
                icon: Icons.settings_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: _openDockerApp,
              ),
              if (state.failureKind ==
                  ArtexEngineFailureKind.dockerUnavailable)
                AppButton(
                  label: '重试启动',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _engine.start(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(BuildContext context, ArtexEngineConfig cfg) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(title: '配置'),
          const SizedBox(height: AppTheme.space8),
          AppTextField(
            controller: _dirController,
            label: 'Compose 工程目录',
            hintText: ArtexEngineConfig.defaultProjectDir,
            helperText: 'ARTEX 仓库位置（需含 docker-compose.yml）',
          ),
          const SizedBox(height: AppTheme.space8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: '保存目录',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: _saveProjectDir,
            ),
          ),
          const Divider(height: AppTheme.space24),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _httpPortController,
                  label: 'HTTP 端口',
                  hintText: '8787',
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: AppTextField(
                  controller: _proxyPortController,
                  label: '流量代理端口',
                  hintText: '8788',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: '保存端口',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: _savePorts,
            ),
          ),
          const Divider(height: AppTheme.space24),
          AppTextField(
            controller: _callbackAddrController,
            label: '回连地址',
            hintText: '留空 = 自动探测',
          ),
          const SizedBox(height: AppTheme.space4),
          Text(
            _callbackHintText(),
            style: context.fontCaption,
          ),
          if (_callbackCandidates.length > 1) ...[
            const SizedBox(height: AppTheme.space8),
            Wrap(
              spacing: AppTheme.space8,
              runSpacing: AppTheme.space4,
              children: [
                for (final candidate in _callbackCandidates)
                  ActionChip(
                    label: Text(candidate),
                    onPressed: () => _pickCallbackAddr(candidate),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _tunnelPortMinController,
                  label: '隧道池起始端口',
                  hintText: '20000',
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: AppTextField(
                  controller: _tunnelPortMaxController,
                  label: '隧道池结束端口',
                  hintText: '20099',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          Text(
            '内网目标机回连平台用的端口池，会被发布到上面的回连地址。'
            '每条隧道占用 2 个端口；范围越大启动越慢'
            '（100 个约 +3 秒，1000 个约 +41 秒）。',
            style: context.fontCaption,
          ),
          const SizedBox(height: AppTheme.space8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: '保存内网设置',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: _saveInternalNetwork,
            ),
          ),
          const Divider(height: AppTheme.space24),
          _SwitchRow(
            title: '退出应用时停止引擎',
            subtitle: '关闭后引擎容器会在后台继续运行',
            value: cfg.stopOnAppExit,
            onChanged: (v) =>
                _config.save(_config.config.copyWith(stopOnAppExit: v)),
          ),
          _SwitchRow(
            title: '关闭引擎伪装门控',
            subtitle: '单机部署必须关闭，否则健康检查会被假页面欺骗',
            value: cfg.gateOff,
            onChanged: (v) => _config.save(_config.config.copyWith(gateOff: v)),
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
          AppSectionHeader(
            title: '镜像',
            trailing: Text(
              _build.lastResult?.duration.inSeconds != null &&
                      !_build.isBuilding
                  ? '上次构建 ${_build.lastResult!.duration.inSeconds}s'
                  : '',
              style: context.fontCaption,
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            '首次使用需构建镜像（约 9 分钟，1.67GB）。构建参数可在下方调整，'
            '国内网络默认走镜像源。',
            style: context.fontCaption,
          ),
          const SizedBox(height: AppTheme.space12),
          AppButton(
            label: _build.isBuilding ? '构建中…' : '构建镜像',
            icon: Icons.build_outlined,
            variant: AppButtonVariant.primary,
            isLoading: _build.isBuilding,
            onPressed: _build.isBuilding ? null : _buildImage,
          ),
        ],
      ),
    );
  }

  Widget _buildFailureCard(BuildContext context, ArtexEngineState state) {
    if (state.status != ArtexEngineStatus.failed ||
        state.failureKind == null) {
      return const SizedBox.shrink();
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: context.errorText),
              const SizedBox(width: AppTheme.space8),
              Text(state.failureKind!.label, style: context.fontTitle),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(state.failure ?? '', style: context.fontBody),
          if (state.failureDetail != null &&
              state.failureDetail!.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            Text(state.failureDetail!, style: context.fontCaption),
          ],
          // 多候选回连地址：把选择直接摆在失败卡片里。塞进设置区的话，
          // 用户看到的是「启动失败」+ 一个不知道去哪选的地址列表。
          if (state.callbackCandidates.length > 1) ...[
            const SizedBox(height: AppTheme.space12),
            Text('选择目标机可达的地址：', style: context.fontCaption),
            const SizedBox(height: AppTheme.space4),
            Wrap(
              spacing: AppTheme.space8,
              runSpacing: AppTheme.space4,
              children: [
                for (final candidate in state.callbackCandidates)
                  ActionChip(
                    avatar: const Icon(Icons.lan_outlined, size: 16),
                    label: Text(candidate),
                    onPressed: () => _pickCallbackAddr(candidate),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCapabilityNotice(BuildContext context) {
    return AppCard(
      backgroundColor: context.warningSolid.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: context.warningText),
              const SizedBox(width: AppTheme.space8),
              Text('能力边界', style: context.fontTitle),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            '镜像未预置内网隧道工具（chisel / suo5），因此「立足点与内网纵深」'
            '能力开箱不可用。开箱范围是外网自动化探索：资产图、探索图、'
            'planner/worker 编排、蜜罐识别、流量证据链、漏洞验证闭环。\n'
            '启用方式：把对应平台的二进制放进工程目录的 data/tools/ 后重启引擎。\n'
            '启动日志中出现隧道工具缺失的提示是已知情况，不影响上述能力。',
            style: context.fontBodySecondary,
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            '内网目标机回连平台需要一个宿主机上可被内网路由的 IPv4 地址'
            '（下方「回连地址」）。默认自动探测物理网卡，多网卡时需要手动选；'
            '地址变化后要重启引擎，目标机才会拿到新地址。',
            style: context.fontBodySecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildDataLocationCard(BuildContext context, ArtexEngineConfig cfg) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('数据位置', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Text(
            '引擎数据不在本软件的数据目录内，而归 Docker 与 ARTEX 仓库管理：\n'
            '· PostgreSQL 数据卷：artex-ymh_pgdata（docker volume）\n'
            '· 工程数据目录：${cfg.projectDir}/data\n'
            '· 本工具只保存自己的配置与 override 备份。\n'
            '删除本软件不会删除引擎数据；备份时请一并考虑上述位置。',
            style: context.fontBodySecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildCaSection(BuildContext context) {
    if (_caChecking) {
      return const AppCard(
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_caState == ArtexCaState.notGenerated) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: context.textTertiary),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text(
                '根证书将在引擎首次运行后生成',
                style: context.fontCaption,
              ),
            ),
          ],
        ),
      );
    }

    if (_caState == ArtexCaState.trusted) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.verified_outlined, color: context.successText),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text('根证书已安装到系统信任库', style: context.fontBody),
            ),
          ],
        ),
      );
    }

    final cmd = _ca.installCommand(_config.config.projectDir);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.gpp_maybe_outlined, color: context.warningText),
              const SizedBox(width: AppTheme.space8),
              Expanded(child: Text('根证书未安装', style: context.fontTitle)),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            '引擎的流量录制代理需要解密 HTTPS。请在终端执行以下命令安装根证书：',
            style: context.fontBodySecondary,
          ),
          const SizedBox(height: AppTheme.space8),
          Container(
            padding: const EdgeInsets.all(AppTheme.space8),
            decoration: BoxDecoration(
              color: context.bgInput,
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: SelectableText(cmd, style: AppTheme.fontCaption),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(_ca.uninstallHint, style: context.fontCaption),
          const SizedBox(height: AppTheme.space8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: '复制命令',
              icon: Icons.copy,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: () => _copyToClipboard(cmd, '安装命令'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行「标签 / 值」。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: context.fontCaption),
          ),
          Expanded(
            child: Text(
              value,
              style: context.fontBody.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行开关。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.fontBody),
                const SizedBox(height: AppTheme.space2),
                Text(subtitle, style: context.fontCaption),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
