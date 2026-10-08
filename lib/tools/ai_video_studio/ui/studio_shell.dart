/// AI 短视频工坊的工作台外壳：三栏布局 + 页面路由。
///
/// 布局照安全工具箱的 `Row[侧导航 | 内容区]`，右侧第三栏是分镜预览播放器
/// （spec 9.1）。侧导航是「工序」而不是「功能」——创意孵化 → IP 主库 → 剧本
/// 看板 → 声音设计 → 合成交付，用户按制作顺序往前走，不该在并列功能里找。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/image_gen_adapter.dart';
import '../services/studio_asset_bridge.dart';
import '../services/studio_project_manager.dart';
import '../services/video_gen_adapter.dart';
import 'delivery_panel.dart';
import 'idea_incubator_panel.dart';
import 'project_list_page.dart';
import 'series_page.dart';
import 'sound_design_panel.dart';
import 'storyboard_board.dart';
import 'studio_settings_dialog.dart';

/// 工坊内的工序页。
enum StudioStage {
  projects('projects', '剧集库', Icons.video_collection_outlined),
  ideas('ideas', '创意孵化', Icons.lightbulb_outline),
  series('series', 'IP 主库', Icons.people_outline),
  storyboard('storyboard', '分镜看板', Icons.dashboard_outlined),
  sound('sound', '声音设计', Icons.graphic_eq_outlined),
  delivery('delivery', '合成交付', Icons.movie_creation_outlined);

  final String id;
  final String label;
  final IconData icon;

  const StudioStage(this.id, this.label, this.icon);
}

/// 全局选中的剧集与集数。切页面时不丢——用户常在 IP 主库改完角色回到看板。
class StudioSession extends ChangeNotifier {
  StudioSeries? series;
  StudioEpisode? episode;

  bool get hasSeries => series != null;

  void select(StudioSeries? next) {
    if (series?.id == next?.id) return;
    series = next;
    episode = null;
    _publishActiveProject();
    notifyListeners();
  }

  void selectEpisode(StudioEpisode? next) {
    if (episode?.id == next?.id) return;
    episode = next;
    _publishActiveProject();
    notifyListeners();
  }

  void reloadEpisode() {
    final current = episode;
    final s = series;
    if (current == null || s == null) return;
    episode = StudioProjectManager.instance.readEpisode(s.id, current.id);
    _publishActiveProject();
    notifyListeners();
  }

  /// 把当前剧集/集发布给视频下载器（spec 16.1 的快捷选项靠它判断显隐）。
  ///
  /// 只写内存里的单例，不落盘：下载器和工坊是同一个进程的不同窗口，
  /// 进程重启后「没有活跃项目」是正确的初始状态。
  void _publishActiveProject() {
    final s = series;
    if (s == null) {
      StudioActiveProjectStore.instance.clearActive();
      return;
    }
    StudioActiveProjectStore.instance.setActive(
      seriesId: s.id,
      seriesName: s.name,
      episodeId: episode?.id,
      episodeTitle: episode?.title,
    );
  }
}

class StudioShellPage extends StatefulWidget {
  const StudioShellPage({super.key});

  @override
  State<StudioShellPage> createState() => _StudioShellPageState();
}

class _StudioShellPageState extends State<StudioShellPage> {
  final _session = StudioSession();
  final _manager = StudioProjectManager.instance;
  StudioStage _stage = StudioStage.projects;

  bool _loading = true;
  String? _loadError;
  bool _isLocalDemoMode = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _checkEngineStatus() async {
    try {
      final silicon = SiliconFlowImageAdapter();
      final kling = KlingVideoAdapter();
      final hasImg = await silicon.isAvailable();
      final hasVid = await kling.isAvailable();
      if (mounted) {
        setState(() {
          _isLocalDemoMode = !hasImg || !hasVid;
        });
      }
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _manager.ensureBaseStructure();
      final series = await _manager.listSeries();
      await _checkEngineStatus();
      if (!mounted) return;
      // 有剧集就默认停在剧集库，没剧集时也是剧集库（那页有新建引导）。
      _session.select(series.isNotEmpty ? series.first : null);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  void _go(StudioStage stage) {
    // 没有剧集就不是所有页面都能进：创意孵化与声音设计都挂在某一部剧下。
    if (!_session.hasSeries && _needsSeries(stage)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建或选择一部剧集')),
      );
      return;
    }
    setState(() => _stage = stage);
  }

  static bool _needsSeries(StudioStage stage) =>
      stage == StudioStage.ideas ||
      stage == StudioStage.storyboard ||
      stage == StudioStage.sound ||
      stage == StudioStage.delivery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgWindow,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError(context)
              : Row(
                  children: [
                    _buildSidebar(context),
                    VerticalDivider(width: 1, color: context.borderSubtle),
                    Expanded(
                      child: Container(
                        color: context.bgContent,
                        child: ListenableBuilder(
                          listenable: _session,
                          builder: (context, _) => Column(
                            children: [
                              _buildTopBar(context),
                              Expanded(
                                child: _buildStage(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: context.errorText),
            const SizedBox(height: 12),
            Text(
              '工坊数据目录初始化失败',
              style: TextStyle(color: context.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _bootstrap,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 176,
      color: context.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.accentText.withAlpha(40),
                    borderRadius: AppTheme.borderRadiusSmall,
                  ),
                  child: Icon(
                    Icons.movie_creation_outlined,
                    color: context.accentText,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '短视频工坊',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final stage in StudioStage.values)
            _StageItem(
              stage: stage,
              selected: _stage == stage,
              enabled: stage == StudioStage.projects ||
                  stage == StudioStage.series || _session.hasSeries,
              onTap: () => _go(stage),
            ),
          const Spacer(),
          const Divider(height: 1),
          _SettingsItem(
            onTap: () => _openSettings(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.bgWindow,
        border: Border(bottom: BorderSide(color: context.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.video_collection_outlined, size: 16, color: context.accentText),
          const SizedBox(width: 8),
          Text(
            _session.series?.name ?? '未选择剧集',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_session.episode != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: context.textTertiary),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.bgSelected,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '第 ${_session.episode!.index} 集: ${_session.episode!.title}',
                style: TextStyle(
                  color: context.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (_session.series != null) ...[
            const SizedBox(width: 10),
            _TypeChip(type: _session.series!.productionType),
          ],
          const Spacer(),
          InkWell(
            onTap: () => _openSettings(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isLocalDemoMode
                    ? context.warningText.withAlpha(25)
                    : context.successText.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isLocalDemoMode
                      ? context.warningText.withAlpha(80)
                      : context.successText.withAlpha(80),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isLocalDemoMode
                        ? Icons.info_outline
                        : Icons.check_circle_outline,
                    size: 14,
                    color: _isLocalDemoMode
                        ? context.warningText
                        : context.successText,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isLocalDemoMode
                        ? '本地免费演示模式 (点击配置)'
                        : 'AI 商业引擎已就绪',
                    style: TextStyle(
                      color: _isLocalDemoMode
                          ? context.warningText
                          : context.successText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case StudioStage.projects:
        return ProjectListPage(
          session: _session,
          onChanged: _bootstrap,
          onNavigateStage: _go,
        );
      case StudioStage.ideas:
        return IdeaIncubatorPanel(
          session: _session,
          onConfirmed: () => setState(() => _stage = StudioStage.series),
        );
      case StudioStage.series:
        return SeriesPage(session: _session);
      case StudioStage.storyboard:
        return StoryboardBoard(session: _session);
      case StudioStage.sound:
        return SoundDesignPanel(session: _session);
      case StudioStage.delivery:
        return DeliveryPanel(session: _session);
    }
  }

  Future<void> _openSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const StudioSettingsDialog(),
    );
    if (mounted) {
      await _checkEngineStatus();
    }
  }
}

class _StageItem extends StatelessWidget {
  const _StageItem({
    required this.stage,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final StudioStage stage;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? context.textDisabled
        : selected
            ? context.accentText
            : context.textSecondary;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.bgSelected : null,
          border: Border(
            left: BorderSide(
              color: selected ? context.accentText : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(stage.icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(
              stage.label,
              style: TextStyle(
                color: enabled ? context.textPrimary : context.textDisabled,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final StudioProductionType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: TextStyle(color: context.accentText, fontSize: 11),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.settings_outlined, size: 18, color: context.textSecondary),
            const SizedBox(width: 10),
            Text(
              '工坊设置',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
