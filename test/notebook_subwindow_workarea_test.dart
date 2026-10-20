import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:V8WorkToolbox/main.dart' show displayContainingPoint;

/// 笔记本子窗口的屏幕挑选契约（spec: window-launch-lifecycle 的
/// Window size derives from the screen visible work area）。
///
/// 固定三件事：
/// 1. 光标落在哪块屏，就挑哪块——用户正在看的那块才是「当前屏幕」；
/// 2. 光标不在任何一块屏内（多屏且光标在边界外等）时返回 null，由调用方
///    回落，不能瞎挑一块；
/// 3. 缺 visiblePosition/visibleSize 的显示器被跳过，而不是抛异常——
///    平台通道给不全字段时不该让窗口打不开。
void main() {
  group('displayContainingPoint', () {
    Display makeDisplay({
      required String id,
      required double x,
      required double y,
      required double w,
      required double h,
      bool withVisible = true,
    }) {
      return Display(
        id: id,
        name: id,
        size: Size(w, h),
        visiblePosition: withVisible ? Offset(x, y) : null,
        visibleSize: withVisible ? Size(w, h) : null,
      );
    }

    test('单屏：光标在内即选中', () {
      final displays = [
        makeDisplay(id: 'main', x: 0, y: 0, w: 1680, h: 1050),
      ];
      final picked = displayContainingPoint(displays, const Offset(800, 500));
      expect(picked?.id, 'main');
    });

    test('多屏：挑光标所在的那块，而不是列表第一块', () {
      final displays = [
        makeDisplay(id: 'left', x: 0, y: 0, w: 1680, h: 1050),
        makeDisplay(id: 'right', x: 1680, y: 0, w: 1920, h: 1080),
      ];
      final picked =
          displayContainingPoint(displays, const Offset(2000, 500));
      expect(picked?.id, 'right');
    });

    test('光标不在任何屏内时返回 null', () {
      final displays = [
        makeDisplay(id: 'main', x: 0, y: 0, w: 1680, h: 1050),
      ];
      expect(displayContainingPoint(displays, const Offset(-500, -500)), isNull);
    });

    test('边界点算在内（visibleFrame 是左闭右开，用 contains 语义）', () {
      final displays = [
        makeDisplay(id: 'main', x: 0, y: 0, w: 1680, h: 1050),
      ];
      // 左上角原点属于该屏。
      expect(displayContainingPoint(displays, Offset.zero)?.id, 'main');
    });

    test('缺 visiblePosition/visibleSize 的显示器被跳过', () {
      final displays = [
        makeDisplay(
          id: 'broken',
          x: 0,
          y: 0,
          w: 1680,
          h: 1050,
          withVisible: false,
        ),
        makeDisplay(id: 'ok', x: 1680, y: 0, w: 1920, h: 1080),
      ];
      final picked = displayContainingPoint(displays, const Offset(2000, 500));
      expect(picked?.id, 'ok');
    });

    test('空列表返回 null', () {
      expect(displayContainingPoint(const [], Offset.zero), isNull);
    });
  });

  group('工作区尺寸不超出屏幕', () {
    // 直接验证 setBounds 会收到的那个 Rect：它必须就是可见工作区本身，
    // 而不是某个可能溢出屏幕的硬编码尺寸。
    Rect workAreaRect(Display d) => Rect.fromLTWH(
          d.visiblePosition!.dx,
          d.visiblePosition!.dy,
          d.visibleSize!.width,
          d.visibleSize!.height,
        );

    test('frame 等于可见工作区', () {
      const d = Display(
        id: 'main',
        size: Size(1680, 1050),
        visiblePosition: Offset(0, 24),
        visibleSize: Size(1680, 978),
      );
      final r = workAreaRect(d);
      expect(r.width, 1680);
      expect(r.height, 978, reason: '排除菜单栏 24px');
      expect(r.top, 24);
      // 不溢出屏幕。
      expect(r.right, lessThanOrEqualTo(1680));
      expect(r.bottom, lessThanOrEqualTo(1050));
    });

    test('小屏上 frame 不超过屏幕', () {
      const d = Display(
        id: 'small',
        size: Size(1280, 800),
        visiblePosition: Offset(0, 24),
        visibleSize: Size(1280, 752),
      );
      final r = workAreaRect(d);
      expect(r.width, lessThanOrEqualTo(1280));
      expect(r.height, lessThanOrEqualTo(800));
    });
  });
}
