/// 网络拓扑图（CustomPainter）：星形布局，网关/路由器居中，主机环绕。
///
/// 用 CustomPainter 而不是引入图库：安全拓扑的节点数通常 < 50，星形布局是固定的
/// 三角函数运算，一帧画完；而 Flutter 的图可视化库生态基本空白，引一个半成品
/// 不如 150 行自绘可控。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../services/lan_recon_services.dart';

/// 拓扑图上的一个节点（对应一台主机）。
class TopoNode {
  final String ip;
  final String? mac;
  final String? vendor;
  final String? os;
  final String deviceType;
  final String riskLevel;
  final List<ScannedPort> ports;

  const TopoNode({
    required this.ip,
    this.mac,
    this.vendor,
    this.os,
    required this.deviceType,
    required this.riskLevel,
    this.ports = const [],
  });

  Severity get severity => Severity.fromKey(riskLevel);
}

class _PlacedNode {
  final TopoNode node;
  final Offset center;
  final double radius;

  const _PlacedNode(this.node, this.center, this.radius);
}

/// 星形拓扑图。
///
/// 网关固定居中（这里用"网段第一个 IP"当网关，也是用户最熟悉的那台设备），
/// 其余主机按角度均布。命中测试单独走 [_PlacedNode] 列表，不依赖
/// RenderBox 的 hitTest——节点的屏幕位置由 painter 自己算，两者必须一致。
class NetworkTopologyGraph extends StatefulWidget {
  final List<TopoNode> nodes;
  final String gatewayIp;
  final ValueChanged<TopoNode>? onNodeSelected;
  final double size;

  const NetworkTopologyGraph({
    super.key,
    required this.nodes,
    required this.gatewayIp,
    this.onNodeSelected,
    this.size = 420,
  });

  @override
  State<NetworkTopologyGraph> createState() => _NetworkTopologyGraphState();
}

class _NetworkTopologyGraphState extends State<NetworkTopologyGraph> {
  final List<_PlacedNode> _placed = [];
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _layout(const Size(420, 420));
  }

  @override
  void didUpdateWidget(NetworkTopologyGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes) ||
        oldWidget.gatewayIp != widget.gatewayIp) {
      _layout(_lastSize);
    }
  }

  void _layout(Size size) {
    _lastSize = size;
    final placed = <_PlacedNode>[];
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = (size.shortestSide / 2) - 44;

    // 网关节点（若在列表里）居中，其余环绕。
    final hosts = widget.nodes
        .where((n) => n.ip != widget.gatewayIp)
        .toList();
    final gateway = widget.nodes
        .where((n) => n.ip == widget.gatewayIp)
        .firstOrNull;

    if (gateway != null) {
      placed.add(_PlacedNode(gateway, center, 30));
    } else {
      // 没有识别出网关时画一个虚拟中心，边上标"网关"
      placed.add(
        _PlacedNode(
          const TopoNode(
            ip: '',
            deviceType: 'router',
            riskLevel: 'unknown',
          ),
          center,
          26,
        ),
      );
    }

    final count = hosts.length;
    for (var i = 0; i < count; i++) {
      // 从正上方开始顺时针分布；count 为 1 时角度无所谓。
      final angle = (i / count) * 2 * 3.141592653589793 - 3.141592653589793 / 2;
      final offset = Offset(
        center.dx + ringRadius * math.cos(angle),
        center.dy + ringRadius * math.sin(angle),
      );
      placed.add(_PlacedNode(hosts[i], offset, 20));
    }
    _placed
      ..clear()
      ..addAll(placed);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.size.toDouble();
        _layout(Size(side, side));
        return GestureDetector(
          onTapUp: (details) => _handleTap(details.localPosition),
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _TopologyPainter(
                placed: _placed,
                gatewayIp: widget.gatewayIp,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset position) {
    for (final placed in _placed) {
      if (placed.node.ip.isEmpty) continue;
      final dx = position.dx - placed.center.dx;
      final dy = position.dy - placed.center.dy;
      if (dx * dx + dy * dy <= placed.radius * placed.radius * 2.2) {
        widget.onNodeSelected?.call(placed.node);
        return;
      }
    }
  }
}

class _TopologyPainter extends CustomPainter {
  final List<_PlacedNode> placed;
  final String gatewayIp;

  const _TopologyPainter({required this.placed, required this.gatewayIp});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..strokeWidth = 1;

    // 先画连线，节点覆盖在上面。
    for (final node in placed) {
      if (node.node.ip.isEmpty || node.node.ip == gatewayIp) continue;
      canvas.drawLine(center, node.center, linePaint);
    }

    for (final node in placed) {
      _paintNode(canvas, node);
    }
  }

  void _paintNode(Canvas canvas, _PlacedNode placed) {
    final node = placed.node;
    final isGateway = node.ip == gatewayIp;
    final severity = node.severity;

    final fillColor = switch (severity) {
      Severity.critical => AppTheme.error,
      Severity.high => const Color(0xFFF97316),
      Severity.medium => AppTheme.warning,
      Severity.low => AppTheme.info,
      Severity.info => AppTheme.bgCardHover,
    };

    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(placed.center, placed.radius, paint);

    final border = Paint()
      ..color = Colors.white.withAlpha(isGateway ? 160 : 60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isGateway ? 2 : 1;
    canvas.drawCircle(placed.center, placed.radius, border);

    // 设备类型图标（≤ 2 个字符，够区分 PC/路由器/手机）。
    final iconText = TextPainter(
      text: TextSpan(
        text: _iconFor(node.deviceType),
        style: TextStyle(
          color: Colors.white,
          fontSize: placed.radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconText.paint(
      canvas,
      placed.center - Offset(iconText.width / 2, iconText.height / 2),
    );

    // IP 标签画在节点下方。
    final label = TextPainter(
      text: TextSpan(
        text: node.ip.isEmpty ? '网关' : node.ip,
        style: const TextStyle(color: Colors.white70, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(
        placed.center.dx - label.width / 2,
        placed.center.dy + placed.radius + 2,
      ),
    );
  }

  static String _iconFor(String type) => switch (type) {
    'router' => 'R',
    'phone' => 'P',
    'pc' => 'C',
    'server' => 'S',
    _ => '•',
  };

  @override
  bool shouldRepaint(_TopologyPainter old) =>
      !identical(old.placed, placed) || old.gatewayIp != gatewayIp;
}
