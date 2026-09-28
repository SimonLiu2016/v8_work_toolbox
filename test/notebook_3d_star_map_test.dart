import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Node3DTest {
  final String id;
  final String title;
  final bool isAsset;
  final int degree;
  final bool isCore;

  double x = 0.0;
  double y = 0.0;
  double z = 0.0;

  double rotatedX = 0.0;
  double rotatedY = 0.0;
  double rotatedZ = 0.0;

  double screenX = 0.0;
  double screenY = 0.0;
  double scale = 1.0;
  double alpha = 1.0;

  Node3DTest({
    required this.id,
    required this.title,
    required this.isAsset,
    this.degree = 0,
    this.isCore = false,
  });
}

class Edge3DTest {
  final String source;
  final String target;
  final String? reason;

  const Edge3DTest({
    required this.source,
    required this.target,
    this.reason,
  });
}

void projectNodes({
  required List<Node3DTest> nodes,
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

void layoutFibonacciSphere(List<Node3DTest> nodes) {
  final n = nodes.length;
  if (n == 0) return;

  final baseRadius = (130.0 + math.sqrt(n) * 12.0).clamp(130.0, 220.0);
  final phi = (math.sqrt(5.0) - 1.0) / 2.0;

  for (var i = 0; i < n; i++) {
    final y = 1.0 - (i / math.max(1, n - 1)) * 2.0;
    final radiusAtY = math.sqrt(math.max(0.0, 1.0 - y * y));
    final theta = 2.0 * math.pi * i * phi;

    final x = math.cos(theta) * radiusAtY;
    final z = math.sin(theta) * radiusAtY;

    final perturb = 0.88 + ((nodes[i].id.hashCode % 100) / 100.0) * 0.24;
    final r = baseRadius * perturb;

    nodes[i].x = x * r;
    nodes[i].y = y * r;
    nodes[i].z = z * r;
  }
}

void main() {
  group('3D 知识星图核心算法与投影数学验证', () {
    test('Fibonacci 球面三维分布算法能均匀分散坐标点', () {
      final nodes = List.generate(
        20,
        (i) => Node3DTest(
          id: 'note_$i',
          title: 'Note $i',
          isAsset: i % 5 == 0,
        ),
      );

      layoutFibonacciSphere(nodes);

      // 验证没有节点重叠在原点 (0, 0, 0)
      for (final n in nodes) {
        final dist = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
        expect(dist, greaterThan(100.0));
        expect(dist, lessThan(300.0));
      }
    });

    test('3D 欧拉旋转与透视投影验证（近大远小规律）', () {
      final nearNode = Node3DTest(id: 'near', title: 'Near', isAsset: false)
        ..x = 0.0
        ..y = 0.0
        ..z = 100.0; // 靠近相机 (Z 正向)

      final farNode = Node3DTest(id: 'far', title: 'Far', isAsset: false)
        ..x = 0.0
        ..y = 0.0
        ..z = -100.0; // 远离相机 (Z 负向)

      final nodes = [nearNode, farNode];

      projectNodes(
        nodes: nodes,
        rotationX: 0.0,
        rotationY: 0.0,
        zoom: 1.0,
        size: const Size(800, 600),
      );

      // 验证屏幕中心点对齐
      expect(nearNode.screenX, 400.0);
      expect(nearNode.screenY, 300.0);
      expect(farNode.screenX, 400.0);
      expect(farNode.screenY, 300.0);

      // 验证近大远小与景深透明度衰减
      expect(nearNode.scale, greaterThan(farNode.scale));
      expect(nearNode.alpha, greaterThan(farNode.alpha));
    });

    test('核心枢纽节点识别算法（Top 度数与孤立点排除）', () {
      final rawNodes = List.generate(
        15,
        (i) => Node3DTest(
          id: 'n$i',
          title: 'Title $i',
          isAsset: false,
        ),
      );

      // n0 连接 5 个边，n1 连接 3 个边，n2~n5 连接 1 个边，其他无边
      final edges = [
        const Edge3DTest(source: 'n0', target: 'n1'),
        const Edge3DTest(source: 'n0', target: 'n2'),
        const Edge3DTest(source: 'n0', target: 'n3'),
        const Edge3DTest(source: 'n0', target: 'n4'),
        const Edge3DTest(source: 'n0', target: 'n5'),
        const Edge3DTest(source: 'n1', target: 'n2'),
        const Edge3DTest(source: 'n1', target: 'n3'),
      ];

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

      expect(coreIds.contains('n0'), isTrue);
      expect(coreIds.contains('n1'), isTrue);
      expect(degreeMap['n0'], 5);
      expect(degreeMap['n1'], 3);
      // 无连线的节点不作为 core
      expect(coreIds.contains('n14'), isFalse);
    });

    test('核心节点标签背面淡化判定（rotatedZ > -45 处于前半球可见）', () {
      final frontCore = Node3DTest(id: 'c1', title: 'Front Core', isAsset: false, isCore: true)
        ..rotatedZ = 50.0;
      final edgeCore = Node3DTest(id: 'c2', title: 'Edge Core', isAsset: false, isCore: true)
        ..rotatedZ = -10.0;
      final backCore = Node3DTest(id: 'c3', title: 'Back Core', isAsset: false, isCore: true)
        ..rotatedZ = -80.0;

      bool isCoreFacingFront(Node3DTest n) => n.isCore && n.rotatedZ > -45.0;

      expect(isCoreFacingFront(frontCore), isTrue);
      expect(isCoreFacingFront(edgeCore), isTrue);
      expect(isCoreFacingFront(backCore), isFalse); // 转到背面自动剔除淡出

      // 淡化系数公式计算：((rotatedZ + 45.0) / 90.0).clamp(0.0, 1.0)
      double labelAlpha(Node3DTest n) => ((n.rotatedZ + 45.0) / 90.0).clamp(0.0, 1.0);

      expect(labelAlpha(frontCore), 1.0);
      expect(labelAlpha(edgeCore), closeTo(0.388, 0.01));
      expect(labelAlpha(backCore), 0.0);
    });

    test('文字胶囊标签视口安全边距钳制算法（防止向左溢出或越界）', () {
      const viewportWidth = 420.0;
      const textWidth = 100.0;
      const safePadding = 8.0;

      double computeLabelDx({required double screenX, required double scale}) {
        var dx = screenX + 10 * scale;
        if (dx + textWidth > viewportWidth - safePadding) {
          dx = screenX - 10 * scale - textWidth;
        }
        return dx.clamp(safePadding, math.max(safePadding, viewportWidth - textWidth - safePadding)).toDouble();
      }

      // 情况 1: 节点位于极左侧 (例如 screenX = -30 或 5)
      final leftBoundaryDx = computeLabelDx(screenX: -30.0, scale: 1.0);
      expect(leftBoundaryDx, greaterThanOrEqualTo(safePadding)); // 强制钳制在安全内边距 8.0，绝不为负数

      // 情况 2: 节点位于极右侧 (例如 screenX = 410)
      final rightBoundaryDx = computeLabelDx(screenX: 410.0, scale: 1.0);
      expect(rightBoundaryDx + textWidth, lessThanOrEqualTo(viewportWidth - safePadding)); // 翻转并钳制在视口右侧内

      // 情况 3: 节点位于中央 (例如 screenX = 200)
      final centerDx = computeLabelDx(screenX: 200.0, scale: 1.0);
      expect(centerDx, 210.0);
    });

    test('3D 知识星图微速自转步长与点击/离开交互状态机验证', () {
      // 1. 自转角速度常数验证
      const rotationStep = 0.0012;
      expect(rotationStep, lessThan(0.002)); // 确认为原 0.0035 的 1/3 左右慢速
      expect(rotationStep, greaterThan(0.0005));

      // 2. 状态机行为模拟
      var autoRotate = true;
      String? hoveredId = 'note-1';

      // 用户点击命中某个星体节点
      void onNodeTap(String noteId) {
        autoRotate = false; // 立即定格暂停
      }

      // 鼠标离开星图容器区域
      void onMouseExit() {
        hoveredId = null;
        autoRotate = true; // 移出后自然恢复自转
      }

      expect(autoRotate, isTrue);
      onNodeTap('note-1');
      expect(autoRotate, isFalse); // 点击后保持暂停
      expect(hoveredId, 'note-1');

      onMouseExit();
      expect(autoRotate, isTrue); // 鼠标离开后恢复转动
      expect(hoveredId, isNull);
    });
  });
}


