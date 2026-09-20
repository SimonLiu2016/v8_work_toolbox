import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../note_store.dart';

/// 知识星图视图（阶段四）。
///
/// 笔记为节点、`note_links` 为边。选中笔记高亮并强调其一跳邻域。
/// 布局用**确定性力导向**——初始位置由笔记 id 哈希决定，迭代次数固定，
/// 故同一份数据每次渲染位置一致，不会跳动。
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

class _KnowledgeGraphViewState extends State<KnowledgeGraphView> {
  static const _bg = Color(0xFFF8FAFC);
  static const _edge = Color(0xFFCBD5E1);
  static const _edgeHot = Color(0xFF3B82F6);
  static const _node = Color(0xFF94A3B8);
  static const _nodeHot = Color(0xFF3B82F6);
  static const _nodeSel = Color(0xFF1D4ED8);
  static const _asset = Color(0xFFF59E0B);

  bool _loading = true;
  List<_Node> _nodes = const [];
  List<_Edge> _edges = const [];
  String? _hoverId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KnowledgeGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedNoteId != widget.selectedNoteId) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final links = await NoteStore.instance.allLinks();
      // 只渲染参与关联的笔记——孤立节点在星图里没有意义，且会挤成一团。
      final ids = <String>{};
      for (final l in links) {
        ids.add(l.sourceNoteId);
        ids.add(l.targetNoteId);
      }

      final nodes = <_Node>[];
      for (final id in ids) {
        final note = await NoteStore.instance.noteById(id);
        if (note == null || note.isDeleted) continue;
        nodes.add(_Node(
          id: id,
          title: note.title,
          isAsset: note.assetCategory != null || note.assetExpiryDate != null,
        ));
      }
      final validIds = nodes.map((n) => n.id).toSet();
      final edges = links
          .where((l) =>
              validIds.contains(l.sourceNoteId) && validIds.contains(l.targetNoteId))
          .map((l) => _Edge(
                source: l.sourceNoteId,
                target: l.targetNoteId,
                reason: l.reason,
              ))
          .toList();

      _layout(nodes, edges);
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

  /// 确定性力导向布局。
  ///
  /// 初始位置由 id 哈希映射到单位圆内，保证同一数据每次布局一致；
  /// 迭代斥力（节点间）+ 引力（沿边）后归一化到画布坐标。
  void _layout(List<_Node> nodes, List<_Edge> edges) {
    if (nodes.isEmpty) return;
    const iterations = 200;
    final idx = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};

    // 确定性初始位置
    for (final n in nodes) {
      final h = n.id.hashCode;
      final angle = (h % 3600) / 3600.0 * 2 * math.pi;
      final radius = 0.15 + ((h ~/ 3600) % 100) / 100.0 * 0.35;
      n.x = 0.5 + radius * math.cos(angle);
      n.y = 0.5 + radius * math.sin(angle);
    }

    for (var it = 0; it < iterations; it++) {
      // 斥力：所有节点两两排斥
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          final a = nodes[i], b = nodes[j];
          var dx = a.x - b.x, dy = a.y - b.y;
          var d2 = dx * dx + dy * dy;
          if (d2 < 1e-6) {
            dx = 0.01;
            dy = 0.01;
            d2 = 2e-4;
          }
          final f = 0.002 / d2;
          final d = math.sqrt(d2);
          final fx = dx / d * f, fy = dy / d * f;
          a.x += fx; a.y += fy;
          b.x -= fx; b.y -= fy;
        }
      }
      // 引力：沿边互相吸引
      for (final e in edges) {
        final ai = idx[e.source], bi = idx[e.target];
        if (ai == null || bi == null) continue;
        final a = nodes[ai], b = nodes[bi];
        final dx = b.x - a.x, dy = b.y - a.y;
        final d = math.sqrt(dx * dx + dy * dy) + 1e-6;
        final f = (d - 0.25) * 0.08;
        final fx = dx / d * f, fy = dy / d * f;
        a.x += fx; a.y += fy;
        b.x -= fx; b.y -= fy;
      }
      // 轻微向心，防漂移
      for (final n in nodes) {
        n.x += (0.5 - n.x) * 0.004;
        n.y += (0.5 - n.y) * 0.004;
      }
    }

    // 归一化到 [0.05, 0.95]
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final n in nodes) {
      minX = math.min(minX, n.x); maxX = math.max(maxX, n.x);
      minY = math.min(minY, n.y); maxY = math.max(maxY, n.y);
    }
    final spanX = math.max(maxX - minX, 1e-6);
    final spanY = math.max(maxY - minY, 1e-6);
    for (final n in nodes) {
      n.x = 0.05 + (n.x - minX) / spanX * 0.90;
      n.y = 0.05 + (n.y - minY) / spanY * 0.90;
    }
  }

  /// 选中节点的直接邻居集合（用于邻域强调）。
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
    if (_loading) {
      return const Center(
        child: SizedBox(
            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.6)),
      );
    }
    if (_nodes.isEmpty) return _empty();

    return Container(
      color: _bg,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              boundaryMargin: const EdgeInsets.all(80),
              child: LayoutBuilder(
                builder: (context, c) => GestureDetector(
                  onTapUp: (d) => _handleTap(d.localPosition, c.biggest),
                  child: MouseRegion(
                    onHover: (e) => _handleHover(e.localPosition, c.biggest),
                    onExit: (_) => setState(() => _hoverId = null),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _GraphPainter(
                        nodes: _nodes,
                        edges: _edges,
                        selectedId: widget.selectedNoteId,
                        hoverId: _hoverId,
                        neighborhood: _neighborhood,
                        edgeColor: _edge,
                        edgeHot: _edgeHot,
                        nodeColor: _node,
                        nodeHot: _nodeHot,
                        nodeSel: _nodeSel,
                        assetColor: _asset,
                        labelColor: const Color(0xFF334155),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _legend(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, size: 15, color: _nodeHot),
          const SizedBox(width: 6),
          const Text('知识星图',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
          const SizedBox(width: 8),
          Text('${_nodes.length} 个笔记 · ${_edges.length} 条关联',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 15, color: Color(0xFF64748B)),
            tooltip: '重新加载',
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _dot(_nodeSel, '选中'),
          const SizedBox(width: 12),
          _dot(_nodeHot, '邻域'),
          const SizedBox(width: 12),
          _dot(_asset, '资产笔记'),
          const SizedBox(width: 12),
          _dot(_node, '其他'),
        ],
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        ],
      );

  Widget _empty() {
    return Container(
      color: _bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hub_outlined, size: 40, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('还没有关联的笔记',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            const Text('在笔记详情里用「AI 整理建议」建立关联后，星图会显示在这里',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 13),
              label: const Text('重新加载', style: TextStyle(fontSize: 11)),
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  _Node? _hitTest(Offset pos, Size size) {
    const hitRadius = 14.0;
    _Node? best;
    var bestD = double.infinity;
    for (final n in _nodes) {
      final p = Offset(n.x * size.width, n.y * size.height);
      final d = (p - pos).distance;
      if (d < hitRadius && d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  void _handleTap(Offset pos, Size size) {
    final n = _hitTest(pos, size);
    if (n != null) widget.onOpenNote(n.id);
  }

  void _handleHover(Offset pos, Size size) {
    final n = _hitTest(pos, size);
    if (n?.id != _hoverId) setState(() => _hoverId = n?.id);
  }
}

class _Node {
  final String id;
  final String title;
  final bool isAsset;
  double x = 0.5;
  double y = 0.5;

  _Node({required this.id, required this.title, required this.isAsset});
}

class _Edge {
  final String source;
  final String target;
  final String? reason;

  const _Edge({required this.source, required this.target, this.reason});
}

class _GraphPainter extends CustomPainter {
  final List<_Node> nodes;
  final List<_Edge> edges;
  final String? selectedId;
  final String? hoverId;
  final Set<String> neighborhood;
  final Color edgeColor, edgeHot, nodeColor, nodeHot, nodeSel, assetColor, labelColor;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.hoverId,
    required this.neighborhood,
    required this.edgeColor,
    required this.edgeHot,
    required this.nodeColor,
    required this.nodeHot,
    required this.nodeSel,
    required this.assetColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pos = {
      for (final n in nodes) n.id: Offset(n.x * size.width, n.y * size.height),
    };

    // 边：邻域内的边高亮
    for (final e in edges) {
      final a = pos[e.source], b = pos[e.target];
      if (a == null || b == null) continue;
      final hot = neighborhood.contains(e.source) && neighborhood.contains(e.target);
      final paint = Paint()
        ..color = hot ? edgeHot.withAlpha(160) : edgeColor.withAlpha(110)
        ..strokeWidth = hot ? 1.8 : 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, paint);
    }

    // 先画节点，标签统一在之后绘制以保证不被节点遮盖
    for (final n in nodes) {
      final p = pos[n.id]!;
      final isSel = n.id == selectedId;
      final isHover = n.id == hoverId;
      final inHood = neighborhood.contains(n.id);

      final Color c = isSel
          ? nodeSel
          : (isHover
              ? nodeSel
              : (n.isAsset ? assetColor : (inHood ? nodeHot : nodeColor)));
      final r = isSel ? 9.0 : (isHover ? 8.0 : (inHood ? 6.5 : 5.0));

      if (isSel || isHover) {
        canvas.drawCircle(p, r + 4, Paint()..color = c.withAlpha(40));
      }
      canvas.drawCircle(p, r, Paint()..color = c);

    }

    // 标签：始终显示选中/悬停的，其余在节点少时全显示
    final showAll = nodes.length <= 12;
    for (final n in nodes) {
      final isTarget = n.id == selectedId || n.id == hoverId;
      if (!isTarget && !showAll) continue;
      _drawLabel(canvas, size, pos[n.id]!, n.title, isTarget);
    }
  }

  void _drawLabel(Canvas canvas, Size size, Offset p, String text, bool strong) {
    final tp = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? '无标题' : text,
        style: TextStyle(
          fontSize: strong ? 11 : 9.5,
          color: strong ? labelColor : labelColor.withAlpha(200),
          fontWeight: strong ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    var dx = p.dx + 10;
    if (dx + tp.width > size.width - 4) dx = p.dx - 10 - tp.width;
    final dy = p.dy - tp.height / 2;
    // 底色让标签在边上可读
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(dx - 2, dy - 1, tp.width + 4, tp.height + 2),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xF2F8FAFC),
    );
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.nodes != nodes ||
      old.selectedId != selectedId ||
      old.hoverId != hoverId ||
      old.neighborhood.length != neighborhood.length;
}
