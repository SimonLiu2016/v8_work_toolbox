import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/components/note_image_block_component.dart';

/// 图片块缩小变换的算术（capability: `notebook-editor` 的预设/拖拽场景）。
///
/// 只测不依赖 widget 树的纯函数部分：宽度下限、居中的 ×2 补偿、拖拽方向。
/// 「点 25% 屏幕真的变小」这条路需要活的编辑器，属实机验证（tasks 4.5）。
void main() {
  group('displayedImageWidth', () {
    test('no drag → the committed width', () {
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: 0,
          centered: false,
        ),
        480,
      );
    });

    test('left-edge drag inward shrinks the width', () {
      // 左热区：向右拖 = 图片变窄，位移记为正。
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: 120,
          centered: false,
        ),
        360,
      );
    });

    test('right-edge drag inward also shrinks the width', () {
      // 右热区回调把位移取了负号，所以同一个函数看到的是负值；减一个负数
      // 等于变宽，方向由调用方保证。这里钉住符号约定本身。
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: -120,
          centered: false,
        ),
        600,
      );
    });

    test('floors at the minimum width', () {
      // 下限 30 与 appflowy_editor 内 ResizableImage 同值：拖得再狠也不该
      // 变成一细条。
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: 100000,
          centered: false,
        ),
        kImageMinWidth,
      );
      expect(kImageMinWidth, 30.0);
    });

    test('centered images double the drag compensation', () {
      // 居中对齐时左右各扩一半，所以同样的位移量效果翻倍。删掉这个补偿会让
      // 居中图越拖越偏——它是包内的既有行为。
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: 60,
          centered: true,
        ),
        360,
      );
      // 同样 60 位移，非居中只缩 60。
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: 60,
          centered: false,
        ),
        420,
      );
    });

    test('centered images also floor at the minimum width', () {
      expect(
        displayedImageWidth(
          committedWidth: 480,
          dragDelta: 100000,
          centered: true,
        ),
        kImageMinWidth,
      );
    });
  });

  group('imageAlignmentFromString', () {
    test('maps the three stored values', () {
      expect(imageAlignmentFromString('left'), Alignment.centerLeft);
      expect(imageAlignmentFromString('center'), Alignment.center);
      expect(imageAlignmentFromString('right'), Alignment.centerRight);
    });

    test('unknown and null fall back to center', () {
      // 存量笔记可能没有 align 属性，或被写过别的值；居中是最安全的兜底。
      expect(imageAlignmentFromString(null), Alignment.center);
      expect(imageAlignmentFromString('diagonal'), Alignment.center);
    });
  });
}
