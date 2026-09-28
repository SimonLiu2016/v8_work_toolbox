import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../batch_organizer_service.dart';
import '../note_store.dart';
import 'notebook_light_scope.dart';

/// 3D 沉浸式动态知识星图（Knowledge Star Map）
class KnowledgeGraphView extends StatefulWidget {
  const KnowledgeGraphView({
    super.key,
    required this.onOpenNote,
    this.selectedNoteId,
  });

  final void Function(String noteId) onOpenNote;
  final String? selectedNoteId;

  @override
  State<KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<KnowledgeGraphView>
    with SingleTickerProviderStateMixin {
  // 深空宇宙调色板
  static const _bgStart = Color(0xFF080C16);
  static const _bgEnd = Color(0xFF0F172A);
  static const _edgeColor = Color(0x3860A5FA); // 淡蓝半透明星轨光纤
  static const _edgeHot = Color(0xFF38BDF8); // 高亮青白星轨
  static const _nodeBase = Color(0xFF93C5FD); // 普通星体天青蓝
  static const _nodeCore = Color(0xFFFFFFFF); // 核心枢纽白光恒星
  static const _nodeHot = Color(0xFF67E8F9); // 悬停/邻域高亮
  static const _nodeSel = Color(0xFF60A5FA); // 选中星体
  static const _assetColor = Color(0xFFFBBF24); // 资产笔记金色星辰

  bool _loading = true;
  List<_Node3D> _nodes = const [];
  List<_Edge3D> _edges = const [];
  String? _hoverId;

  // 3D 视角与动画控制
  late AnimationController _animController;
  double _rotationX = 0.25; // 俯仰角（略微俯瞰，呈现立体星盘感）
  double _rotationY = 0.0; // 方位角（绕垂直轴缓慢自转）
  double _zoom = 1.0;
  bool _autoRotate = true;
  Timer? _resumeTimer;

  // 批量 AI 整理状态
  bool _isOrganizing = false;
  BatchOrganizeProgress? _batchProgress;
  BatchCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    // 60秒持续自转引擎
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..addListener(() {
        if (_autoRotate && mounted) {
          setState(() {
            _rotationY += 0.0012; // 静谧微速自转 (平稳悠远)
          });
        }
      })..repeat();

    _load();
  }

  @override
  void didUpdateWidget(covariant KnowledgeGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedNoteId != widget.selectedNoteId) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _animController.dispose();
    _cancellationToken?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final links = await NoteStore.instance.allLinks();
      final ids = <String>{};
      for (final l in links) {
        ids.add(l.sourceNoteId);
        ids.add(l.targetNoteId);
      }

      final rawNodes = <_Node3D>[];
      for (final id in ids) {
        final note = await NoteStore.instance.noteById(id);
        if (note == null || note.isDeleted) continue;
        rawNodes.add(_Node3D(
          id: id,
          title: note.title,
          isAsset: note.assetCategory != null || note.assetExpiryDate != null,
        ));
      }

      final validIds = rawNodes.map((n) => n.id).toSet();
      final edges = links
          .where((l) =>
              validIds.contains(l.sourceNoteId) && validIds.contains(l.targetNoteId))
          .map((l) => _Edge3D(
                source: l.sourceNoteId,
                target: l.targetNoteId,
                reason: l.reason,
              ))
          .toList();

      // 统计节点度数并标记核心枢纽节点 (Top 10 度数节点)
      final degreeMap = <String, int>{};
      for (final e in edges) {
        degreeMap[e.source] = (degreeMap[e.source] ?? 0) + 1;
        degreeMap[e.target] = (degreeMap[e.target] ?? 0) + 1;
      }

      final sortedByDegree = rawNodes.toList()
        ..sort((a, b) => (degreeMap[b.id] ?? 0).compareTo(degreeMap[a.id] ?? 0));

      final coreIds = <String>{};
      for (var i = 0; i < sortedByDegree.length && i < 12; i++) {
        if ((degreeMap[sortedByDegree[i].id] ?? 0) > 0) {
          coreIds.add(sortedByDegree[i].id);
        }
      }

      final nodes = rawNodes.map((n) {
        final deg = degreeMap[n.id] ?? 0;
        final isCore = coreIds.contains(n.id) || n.isAsset;
        return _Node3D(
          id: n.id,
          title: n.title,
          isAsset: n.isAsset,
          degree: deg,
          isCore: isCore,
        );
      }).toList();

      // 3D 黄金分割球体排布 (Fibonacci Sphere)
      _layoutFibonacciSphere(nodes);

      if (mounted) {
        setState(() {
          _nodes = nodes;
          _edges = edges;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('星图加载失败: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 3D 黄金分割球面点阵分布算法
  void _layoutFibonacciSphere(List<_Node3D> nodes) {
    final n = nodes.length;
    if (n == 0) return;

    // 自适应球体半径 (115 ~ 180，针对 420px 视口优化星盘聚拢感)
    final baseRadius = (115.0 + math.sqrt(n) * 10.0).clamp(115.0, 180.0);
    final phi = (math.sqrt(5.0) - 1.0) / 2.0; // 黄金比例 ~0.618

    for (var i = 0; i < n; i++) {
      final y = 1.0 - (i / math.max(1, n - 1)) * 2.0; // 从 1 递减到 -1
      final radiusAtY = math.sqrt(math.max(0.0, 1.0 - y * y));
      final theta = 2.0 * math.pi * i * phi;

      final x = math.cos(theta) * radiusAtY;
      final z = math.sin(theta) * radiusAtY;

      // 为避免过于机械，加入适度哈希半径微扰，形成厚度星云层
      final perturb = 0.88 + ((nodes[i].id.hashCode % 100) / 100.0) * 0.24;
      final r = baseRadius * perturb;

      nodes[i].x = x * r;
      nodes[i].y = y * r;
      nodes[i].z = z * r;
    }
  }

  /// 选中节点的直接邻接星体集合
  Set<String> get _neighborhood {
    final sel = widget.selectedNoteId ?? _hoverId;
    if (sel == null) return const {};
    final out = <String>{sel};
    for (final e in _edges) {
      if (e.source == sel) out.add(e.target);
      if (e.target == sel) out.add(e.source);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_isOrganizing) {
      return Container(
        color: _bgStart,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: Color(0xFF38BDF8),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgStart, _bgEnd],
        ),
      ),
      child: Column(
        children: [
          _isOrganizing ? _organizingHeader() : _header(),
          Expanded(
            child: _nodes.isEmpty ? _emptyBody() : _graphBody(),
          ),
          if (_nodes.isNotEmpty) _legend(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Row(
        children: [
          const Icon(Icons.blur_on_rounded, size: 16, color: Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          const Text(
            '3D 知识星图',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF1F5F9),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_nodes.length} 星点 · ${_edges.length} 星轨',
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _loading ? null : _openBatchOrganizeDialog,
            icon: const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF67E8F9)),
            label: const Text(
              '批量整理',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF67E8F9),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0x1F38BDF8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.refresh, size: 15, color: Color(0xFF94A3B8)),
            tooltip: '重新加载',
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _organizingHeader() {
    final progress = _batchProgress;
    final current = progress?.current ?? 0;
    final total = progress?.total ?? 0;
    final title = progress?.currentNoteTitle ?? '';
    final ratio = progress?.ratio ?? 0.0;
    final percent = (ratio * 100).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF064E3B),
        border: Border(bottom: BorderSide(color: Color(0xFF059669))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF34D399)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在整理 ($current/$total 篇 · $percent%)：$title',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFECFDF5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _stopBatchOrganize,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFDC2626)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop, size: 12, color: Color(0xFFFCA5A5)),
                      SizedBox(width: 2),
                      Text(
                        '停止',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFCA5A5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: const Color(0xFF047857),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _graphBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              setState(() {
                if (event.scrollDelta.dy > 0) {
                  _zoom = (_zoom * 0.95).clamp(0.5, 2.5);
                } else if (event.scrollDelta.dy < 0) {
                  _zoom = (_zoom * 1.05).clamp(0.5, 2.5);
                }
              });
            }
          },
          child: GestureDetector(
            onPanStart: (_) {
              _resumeTimer?.cancel();
              _autoRotate = false;
            },
            onPanUpdate: (d) {
              setState(() {
                _rotationY += d.delta.dx * 0.007;
                _rotationX = (_rotationX - d.delta.dy * 0.007).clamp(-1.25, 1.25);
              });
            },
            onPanEnd: (_) {
              _resumeTimer?.cancel();
              _resumeTimer = Timer(const Duration(milliseconds: 1600), () {
                if (mounted) setState(() => _autoRotate = true);
              });
            },
            onTapUp: (d) => _handleTap(d.localPosition, size),
            child: MouseRegion(
              onHover: (e) => _handleHover(e.localPosition, size),
              onExit: (_) {
                _resumeTimer?.cancel();
                setState(() {
                  _hoverId = null;
                  _autoRotate = true; // 鼠标移出星图区域后自动恢复平滑自转
                });
              },
              child: ClipRect(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _StarMap3DPainter(
                    nodes: _nodes,
                    edges: _edges,
                    selectedId: widget.selectedNoteId,
                    hoverId: _hoverId,
                    neighborhood: _neighborhood,
                    rotationX: _rotationX,
                    rotationY: _rotationY,
                    zoom: _zoom,
                    edgeColor: _edgeColor,
                    edgeHot: _edgeHot,
                    nodeBase: _nodeBase,
                    nodeCore: _nodeCore,
                    nodeHot: _nodeHot,
                    nodeSel: _nodeSel,
                    assetColor: _assetColor,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.blur_on_rounded, size: 44, color: Color(0xFF334155)),
          const SizedBox(height: 12),
          const Text(
            '知识星系暂无关联星点',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '可单篇使用「AI 整理建议」，或直接点击「批量整理」自动建立关联边',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 13),
                label: const Text('批量整理', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: _isOrganizing ? null : _openBatchOrganizeDialog,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 13, color: Color(0xFF94A3B8)),
                label: const Text('重新加载', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0x33FFFFFF)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _isOrganizing ? null : _load,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
      ),
      child: Row(
        children: [
          _dot(_nodeSel, '当前选中'),
          const SizedBox(width: 14),
          _dot(_nodeCore, '核心枢纽'),
          const SizedBox(width: 14),
          _dot(_assetColor, '资产笔记'),
          const SizedBox(width: 14),
          _dot(_nodeBase, '普通星辰'),
          const Spacer(),
          const Text(
            '拖拽旋转 · 悬停高亮',
            style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.withAlpha(120),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ],
      );

  // ---------------------------------------------------------------------------
  // 3D 命中测试 (基于投影屏幕坐标与近处优先准则)
  // ---------------------------------------------------------------------------

  _Node3D? _hitTest(Offset pos, Size size) {
    if (_nodes.isEmpty) return null;

    // 运行 3D 投影变换
    _StarMap3DPainter.project(
      nodes: _nodes,
      rotationX: _rotationX,
      rotationY: _rotationY,
      zoom: _zoom,
      size: size,
    );

    _Node3D? best;
    var bestZ = -double.infinity;

    for (final n in _nodes) {
      final p = Offset(n.screenX, n.screenY);
      final hitRadius = 14.0 * n.scale;
      final dist = (p - pos).distance;

      // 距离在触控范围内，且位于更靠前的 Z 轴景深
      if (dist <= hitRadius && n.rotatedZ > bestZ) {
        bestZ = n.rotatedZ;
        best = n;
      }
    }
    return best;
  }

  void _handleTap(Offset pos, Size size) {
    final n = _hitTest(pos, size);
    if (n != null) {
      _resumeTimer?.cancel();
      setState(() => _autoRotate = false); // 点击节点时立即定格暂停转动
      widget.onOpenNote(n.id);
    }
  }

  void _handleHover(Offset pos, Size size) {
    final n = _hitTest(pos, size);
    if (n?.id != _hoverId) {
      setState(() => _hoverId = n?.id);
    }
  }

  // ---------------------------------------------------------------------------
  // 批量整理业务对话框
  // ---------------------------------------------------------------------------

  Future<void> _openBatchOrganizeDialog() async {
    final metrics = await BatchOrganizerService.instance.getScopeMetrics();

    if (!mounted) return;

    var selectedScope = BatchOrganizeScope.allNotes;
    var organizeTags = true;
    var organizeLinks = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return NotebookLightScope(
              child: AlertDialog(
                backgroundColor: NotebookLightScope.surface,
                title: const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Text(
                      '批量 AI 整理建议',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: NotebookLightScope.textPrimary,
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI 将逐篇分析笔记内容，提炼精准标签并自动挖掘同主题笔记建立关联关系。',
                        style: TextStyle(
                          fontSize: 12,
                          color: NotebookLightScope.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '整理范围',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NotebookLightScope.textPrimary,
                        ),
                      ),
                      RadioGroup<BatchOrganizeScope>(
                        groupValue: selectedScope,
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedScope = val);
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<BatchOrganizeScope>(
                              title: Text(
                                '全部有效笔记 (${metrics.totalNotes} 篇)',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: const Text(
                                '对库中所有正常笔记全量执行',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: BatchOrganizeScope.allNotes,
                            ),
                            RadioListTile<BatchOrganizeScope>(
                              title: Text(
                                '仅未关联的孤立笔记 (${metrics.unlinkedNotes} 篇)',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: const Text(
                                '仅整理当前星图中尚未建立关联的笔记，节省时间',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: BatchOrganizeScope.unlinkedOnly,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '整理项目',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NotebookLightScope.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        title: const Text('建议并写入标签', style: TextStyle(fontSize: 13)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: organizeTags,
                        onChanged: (val) {
                          setDialogState(() => organizeTags = val ?? true);
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('挖掘并建立关联', style: TextStyle(fontSize: 13)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: organizeLinks,
                        onChanged: (val) {
                          setDialogState(() => organizeLinks = val ?? true);
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: (!organizeTags && !organizeLinks)
                        ? null
                        : () => Navigator.of(dialogCtx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                    child: const Text('开始整理'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      _startBatchOrganize(
        scope: selectedScope,
        organizeTags: organizeTags,
        organizeLinks: organizeLinks,
      );
    }
  }

  void _startBatchOrganize({
    required BatchOrganizeScope scope,
    required bool organizeTags,
    required bool organizeLinks,
  }) async {
    final token = BatchCancellationToken();
    setState(() {
      _isOrganizing = true;
      _cancellationToken = token;
      _batchProgress = null;
    });

    try {
      final summary = await BatchOrganizerService.instance.runBatch(
        scope: scope,
        organizeTags: organizeTags,
        organizeLinks: organizeLinks,
        cancellationToken: token,
        onProgress: (p) {
          if (mounted) {
            setState(() => _batchProgress = p);
          }
        },
      );

      if (mounted) {
        final buffer = StringBuffer();
        if (summary.wasCancelled) {
          buffer.write('批量整理已停止。');
        } else {
          buffer.write('批量整理完成！');
        }
        buffer.write('处理 ${summary.processedNotes}/${summary.totalNotes} 篇');
        if (summary.tagsAdded > 0) buffer.write('，新增 ${summary.tagsAdded} 个标签');
        if (summary.linksCreated > 0) buffer.write('，建立 ${summary.linksCreated} 条关联');
        if (summary.skippedNotes > 0) buffer.write('，跳过 ${summary.skippedNotes} 篇空白笔记');
        if (summary.failedNotes > 0) buffer.write('，失败 ${summary.failedNotes} 篇');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(buffer.toString()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量整理发生异常: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOrganizing = false;
          _cancellationToken = null;
        });
        _load();
      }
    }
  }

  void _stopBatchOrganize() {
    _cancellationToken?.cancel();
  }
}

// =============================================================================
// 3D 节点与边模型
// =============================================================================

class _Node3D {
  final String id;
  final String title;
  final bool isAsset;
  final int degree;
  final bool isCore;

  // 3D 球体空间原点坐标
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;

  // 欧拉旋转后的 3D 坐标
  double rotatedX = 0.0;
  double rotatedY = 0.0;
  double rotatedZ = 0.0;

  // 投影到 2D 视口的屏幕坐标与参数
  double screenX = 0.0;
  double screenY = 0.0;
  double scale = 1.0;
  double alpha = 1.0;

  _Node3D({
    required this.id,
    required this.title,
    required this.isAsset,
    this.degree = 0,
    this.isCore = false,
  });
}

class _Edge3D {
  final String source;
  final String target;
  final String? reason;

  const _Edge3D({
    required this.source,
    required this.target,
    this.reason,
  });
}

// =============================================================================
// 3D 星图 CustomPainter (深空星系透视绘制)
// =============================================================================

class _StarMap3DPainter extends CustomPainter {
  final List<_Node3D> nodes;
  final List<_Edge3D> edges;
  final String? selectedId;
  final String? hoverId;
  final Set<String> neighborhood;

  final double rotationX;
  final double rotationY;
  final double zoom;

  final Color edgeColor, edgeHot, nodeBase, nodeCore, nodeHot, nodeSel, assetColor;

  _StarMap3DPainter({
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.hoverId,
    required this.neighborhood,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.edgeColor,
    required this.edgeHot,
    required this.nodeBase,
    required this.nodeCore,
    required this.nodeHot,
    required this.nodeSel,
    required this.assetColor,
  });

  /// 3D 透视投影变换核心算法
  static void project({
    required List<_Node3D> nodes,
    required double rotationX,
    required double rotationY,
    required double zoom,
    required Size size,
    double cameraDistance = 450.0,
  }) {
    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);
    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);

    final centerX = size.width / 2.0;
    final centerY = size.height / 2.0;

    for (final node in nodes) {
      // 1. 绕 Y 轴旋转（水平自转）
      final x1 = node.x * cosY + node.z * sinY;
      final z1 = -node.x * sinY + node.z * cosY;

      // 2. 绕 X 轴旋转（俯仰倾角）
      final y2 = node.y * cosX - z1 * sinX;
      final z2 = node.y * sinX + z1 * cosX;

      node.rotatedX = x1 * zoom;
      node.rotatedY = y2 * zoom;
      node.rotatedZ = z2 * zoom;

      // 3. 透视投影（视距与深度缩放）
      final denom = cameraDistance - node.rotatedZ;
      final s = cameraDistance / math.max(60.0, denom);

      node.screenX = centerX + node.rotatedX * s;
      node.screenY = centerY + node.rotatedY * s;
      node.scale = s;

      // 景深透明度 ([-200, 200] -> [0.25, 1.0])
      final depth = (node.rotatedZ + 180.0) / 360.0;
      node.alpha = depth.clamp(0.25, 1.0);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    // 1. 执行 3D 透视投影
    project(
      nodes: nodes,
      rotationX: rotationX,
      rotationY: rotationY,
      zoom: zoom,
      size: size,
    );

    // 2. 绘制微光背景静态星尘粒子 (产生深邃宇宙意境)
    _drawStarDust(canvas, size);

    final nodeMap = {for (final n in nodes) n.id: n};

    // 3. 绘制 3D 星轨连线 (带有深度渐变衰减)
    for (final e in edges) {
      final a = nodeMap[e.source];
      final b = nodeMap[e.target];
      if (a == null || b == null) continue;

      final hot = neighborhood.contains(e.source) && neighborhood.contains(e.target);
      // 平均景深决定连线透明度
      final avgZ = (a.rotatedZ + b.rotatedZ) / 2.0;
      final edgeDepth = ((avgZ + 180.0) / 360.0).clamp(0.15, 1.0);

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot ? 1.6 : 0.85
        ..color = hot
            ? edgeHot.withAlpha((255 * edgeDepth).toInt())
            : edgeColor.withAlpha((180 * edgeDepth).toInt());

      canvas.drawLine(
        Offset(a.screenX, a.screenY),
        Offset(b.screenX, b.screenY),
        linePaint,
      );
    }

    // 4. 按 Z 轴从远到近排序节点（前后遮挡深度渲染）
    final sortedNodes = nodes.toList()
      ..sort((a, b) => a.rotatedZ.compareTo(b.rotatedZ));

    // 5. 绘制星体粒子与发光光晕
    for (final n in sortedNodes) {
      final isSel = n.id == selectedId;
      final isHover = n.id == hoverId;
      final inHood = neighborhood.contains(n.id);

      Color c;
      if (isSel) {
        c = nodeSel;
      } else if (isHover) {
        c = nodeHot;
      } else if (n.isAsset) {
        c = assetColor;
      } else if (n.isCore) {
        c = nodeCore;
      } else if (inHood) {
        c = nodeHot;
      } else {
        c = nodeBase;
      }

      // 星体基础半径随透视缩放
      double r = (n.isCore ? 5.8 : (n.isAsset ? 5.0 : 4.0)) * n.scale;
      if (isSel || isHover) r *= 1.4;

      final p = Offset(n.screenX, n.screenY);
      final alpha = (255 * n.alpha).toInt();

      // 核心恒星与高亮星体绘制外发光光斑 (Radial Glow)
      if (n.isCore || isSel || isHover || n.isAsset) {
        final glowRadius = r * 2.8;
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              c.withAlpha((alpha * 0.45).toInt()),
              c.withAlpha(0),
            ],
          ).createShader(Rect.fromCircle(center: p, radius: glowRadius));
        canvas.drawCircle(p, glowRadius, glowPaint);
      }

      // 核心光核绘制
      final corePaint = Paint()..color = c.withAlpha(alpha);
      canvas.drawCircle(p, r, corePaint);

      // 高亮或核心星体中心点缀亮白耀斑
      if (n.isCore || isSel || isHover) {
        canvas.drawCircle(p, r * 0.45, Paint()..color = Colors.white.withAlpha(alpha));
      }
    }

    // 6. 绘制文字标签 (核心节点常驻显示 + 背面平滑淡化剔除 + Hover/Select 高亮)
    for (final n in sortedNodes) {
      final isTarget = n.id == selectedId || n.id == hoverId;

      // 核心节点：面向相机的前半球 (rotatedZ > -45) 时常驻显示
      final isCoreFacingFront = n.isCore && n.rotatedZ > -45.0;

      if (!isTarget && !isCoreFacingFront) continue;

      // 背面淡化剔除系数：越转向背面越透明，转到前方越清晰
      double labelAlpha = 1.0;
      if (!isTarget) {
        labelAlpha = ((n.rotatedZ + 45.0) / 90.0).clamp(0.0, 1.0);
      }

      if (labelAlpha > 0.05) {
        _drawNodeLabel(
          canvas: canvas,
          size: size,
          node: n,
          isTarget: isTarget,
          opacity: labelAlpha,
        );
      }
    }
  }

  /// 绘制微光星尘背景
  void _drawStarDust(Canvas canvas, Size size) {
    const starCount = 60;
    final starPaint = Paint()..color = const Color(0x2E94A3B8);

    for (var i = 0; i < starCount; i++) {
      // 确定性伪随机分布
      final seedX = ((i * 137.5) % 1000) / 1000.0;
      final seedY = ((i * 293.7) % 1000) / 1000.0;
      final seedR = ((i * 17) % 3) == 0 ? 1.2 : 0.8;

      canvas.drawCircle(
        Offset(seedX * size.width, seedY * size.height),
        seedR,
        starPaint,
      );
    }
  }

  /// 绘制带有半透明深空胶囊的星体文字标签
  void _drawNodeLabel({
    required Canvas canvas,
    required Size size,
    required _Node3D node,
    required bool isTarget,
    required double opacity,
  }) {
    final text = node.title.isEmpty ? '无标题' : node.title;
    final textColor = isTarget
        ? Colors.white
        : (node.isAsset
            ? const Color(0xFFFDE68A)
            : const Color(0xFFE2E8F0));

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: isTarget ? 11.5 : (node.isCore ? 10.0 : 9.0),
          fontWeight: isTarget || node.isCore ? FontWeight.w600 : FontWeight.normal,
          color: textColor.withAlpha((255 * opacity).toInt()),
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 130);

    var dx = node.screenX + 10 * node.scale;
    if (dx + tp.width > size.width - 8) {
      dx = node.screenX - 10 * node.scale - tp.width;
    }
    // 确保文字胶囊在视口左右安全边距内，避免靠边时被切除或向左溢出
    dx = dx.clamp(8.0, math.max(8.0, size.width - tp.width - 8.0)).toDouble();
    final dy = (node.screenY - tp.height / 2.0).clamp(4.0, math.max(4.0, size.height - tp.height - 4.0)).toDouble();

    // 半透明深空黑蓝微光胶囊底色
    final capsuleRect = Rect.fromLTWH(
      dx - 4,
      dy - 2,
      tp.width + 8,
      tp.height + 4,
    );
    final bgPaint = Paint()
      ..color = Color(0xCC0B1120).withAlpha((180 * opacity).toInt());

    canvas.drawRRect(
      RRect.fromRectAndRadius(capsuleRect, const Radius.circular(4)),
      bgPaint,
    );

    // 选中或悬停时绘制外边框光晕
    if (isTarget) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Color(0xFF38BDF8).withAlpha((200 * opacity).toInt());
      canvas.drawRRect(
        RRect.fromRectAndRadius(capsuleRect, const Radius.circular(4)),
        borderPaint,
      );
    }

    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _StarMap3DPainter old) =>
      old.rotationY != rotationY ||
      old.rotationX != rotationX ||
      old.zoom != zoom ||
      old.selectedId != selectedId ||
      old.hoverId != hoverId ||
      old.nodes.length != nodes.length ||
      old.edges.length != edges.length;
}
