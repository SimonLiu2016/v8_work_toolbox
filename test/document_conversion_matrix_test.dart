import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/notebook/convert/matrix.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/ooxml_rewriter.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/spreadsheetml_rewriter.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/simple_rewriter.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/flatten.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/writers.dart';

/// 矩阵一致性测试。
///
/// 职责：把 [kConversionMatrix] 与 [converterRegistry] 交叉比对。
/// - 矩阵标了 T1/T2 但没注册 converter → **fail**（静默落格）
/// - 注册了 converter 但矩阵标的是 unavailable → **fail**（多余实现）
/// - unavailable 格不出现在 [availableTargets] 的结果里
///
/// **设计意图（先红）：**
/// 此测试建好时，27 个可用格全部没有 converter 注册，所以
/// "矩阵标了可用但没实现"的断言全部失败——这是预期。
/// 随着每个格的 converter 被注册，对应的断言才会转绿。
/// 最终所有 27 格全绿即为完整交付。

void main() {
  setUpAll(() {
    OoxmlRewriter.register();
    SpreadsheetmlRewriter.register();
    SimpleRewriter.register();
    Flatten.register();
    Writers.register();
  });

  group('矩阵完整性', () {
    test('每个可用格都已注册 converter（先红：27 格未实现则 27 条 fail）', () {
      final failures = <String>[];
      for (final source in DocFormat.values) {
        for (final target in DocFormat.values) {
          final tier = conversionTier(source, target);
          if (tier == ConversionTier.unavailable) continue;
          final registered = converterRegistry.containsKey((source, target));
          if (!registered) {
            failures.add(
              '${source.name}→${target.name} [${tier.name}] 矩阵标可用但无 converter',
            );
          }
        }
      }
      expect(
        failures,
        isEmpty,
        reason: '以下格子矩阵标了可用，但没有注册 converter：\n${failures.join('\n')}',
      );
    });

    test('每个已注册的 converter 都在矩阵中标为可用', () {
      final extras = <String>[];
      for (final entry in converterRegistry.entries) {
        final (source, target) = entry.key;
        final tier = conversionTier(source, target);
        if (tier == ConversionTier.unavailable) {
          extras.add(
            '${source.name}→${target.name} [${entry.value}] 已注册但矩阵标不可用',
          );
        }
      }
      expect(
        extras,
        isEmpty,
        reason: '以下 converter 已注册，但矩阵标为不可用：\n${extras.join('\n')}',
      );
    });
  });

  group('availableTargets 不出现不可用格', () {
    for (final source in DocFormat.values) {
      test('source=${source.name} 的 availableTargets 不含不可用格', () {
        final targets = availableTargets(source);
        for (final target in targets) {
          final tier = conversionTier(source, target);
          expect(
            tier,
            isNot(ConversionTier.unavailable),
            reason:
                '${source.name}→${target.name} 出现在 availableTargets 但矩阵标不可用',
          );
        }
      });
    }
  });

  group('矩阵规范值校验（硬编码对照，防止矩阵被意外改动）', () {
    // ── docx ──────────────────────────────────────────────────────────────
    test('docx→docx = T1', () => _assertTier(DocFormat.docx, DocFormat.docx, ConversionTier.t1));
    test('docx→pdf  = T2', () => _assertTier(DocFormat.docx, DocFormat.pdf,  ConversionTier.t2));
    test('docx→md   = T2', () => _assertTier(DocFormat.docx, DocFormat.md,   ConversionTier.t2));
    test('docx→txt  = T2', () => _assertTier(DocFormat.docx, DocFormat.txt,  ConversionTier.t2));
    test('docx→xlsx = —',  () => _assertTier(DocFormat.docx, DocFormat.xlsx, ConversionTier.unavailable));
    test('docx→csv  = —',  () => _assertTier(DocFormat.docx, DocFormat.csv,  ConversionTier.unavailable));

    // ── md ────────────────────────────────────────────────────────────────
    test('md→docx = T2', () => _assertTier(DocFormat.md, DocFormat.docx, ConversionTier.t2));
    test('md→pdf  = T1', () => _assertTier(DocFormat.md, DocFormat.pdf,  ConversionTier.t1));
    test('md→md   = T2', () => _assertTier(DocFormat.md, DocFormat.md,   ConversionTier.t2));
    test('md→txt  = T2', () => _assertTier(DocFormat.md, DocFormat.txt,  ConversionTier.t2));
    test('md→xlsx = —',  () => _assertTier(DocFormat.md, DocFormat.xlsx, ConversionTier.unavailable));
    test('md→csv  = —',  () => _assertTier(DocFormat.md, DocFormat.csv,  ConversionTier.unavailable));

    // ── txt ───────────────────────────────────────────────────────────────
    test('txt→docx = T1', () => _assertTier(DocFormat.txt, DocFormat.docx, ConversionTier.t1));
    test('txt→pdf  = T1', () => _assertTier(DocFormat.txt, DocFormat.pdf,  ConversionTier.t1));
    test('txt→md   = T1', () => _assertTier(DocFormat.txt, DocFormat.md,   ConversionTier.t1));
    test('txt→txt  = T1', () => _assertTier(DocFormat.txt, DocFormat.txt,  ConversionTier.t1));
    test('txt→xlsx = —',  () => _assertTier(DocFormat.txt, DocFormat.xlsx, ConversionTier.unavailable));
    test('txt→csv  = —',  () => _assertTier(DocFormat.txt, DocFormat.csv,  ConversionTier.unavailable));

    // ── pdf ───────────────────────────────────────────────────────────────
    test('pdf→docx = —',  () => _assertTier(DocFormat.pdf, DocFormat.docx, ConversionTier.unavailable));
    test('pdf→pdf  = T2', () => _assertTier(DocFormat.pdf, DocFormat.pdf,  ConversionTier.t2));
    test('pdf→md   = T2', () => _assertTier(DocFormat.pdf, DocFormat.md,   ConversionTier.t2));
    test('pdf→txt  = T2', () => _assertTier(DocFormat.pdf, DocFormat.txt,  ConversionTier.t2));
    test('pdf→xlsx = —',  () => _assertTier(DocFormat.pdf, DocFormat.xlsx, ConversionTier.unavailable));
    test('pdf→csv  = —',  () => _assertTier(DocFormat.pdf, DocFormat.csv,  ConversionTier.unavailable));

    // ── xlsx ──────────────────────────────────────────────────────────────
    test('xlsx→docx = T2', () => _assertTier(DocFormat.xlsx, DocFormat.docx, ConversionTier.t2));
    test('xlsx→pdf  = T2', () => _assertTier(DocFormat.xlsx, DocFormat.pdf,  ConversionTier.t2));
    test('xlsx→md   = T2', () => _assertTier(DocFormat.xlsx, DocFormat.md,   ConversionTier.t2));
    test('xlsx→txt  = T2', () => _assertTier(DocFormat.xlsx, DocFormat.txt,  ConversionTier.t2));
    test('xlsx→xlsx = T1', () => _assertTier(DocFormat.xlsx, DocFormat.xlsx, ConversionTier.t1));
    test('xlsx→csv  = T2', () => _assertTier(DocFormat.xlsx, DocFormat.csv,  ConversionTier.t2));

    // ── csv ───────────────────────────────────────────────────────────────
    test('csv→docx = T2', () => _assertTier(DocFormat.csv, DocFormat.docx, ConversionTier.t2));
    test('csv→pdf  = T2', () => _assertTier(DocFormat.csv, DocFormat.pdf,  ConversionTier.t2));
    test('csv→md   = T2', () => _assertTier(DocFormat.csv, DocFormat.md,   ConversionTier.t2));
    test('csv→txt  = T2', () => _assertTier(DocFormat.csv, DocFormat.txt,  ConversionTier.t2));
    test('csv→xlsx = T2', () => _assertTier(DocFormat.csv, DocFormat.xlsx, ConversionTier.t2));
    test('csv→csv  = T1', () => _assertTier(DocFormat.csv, DocFormat.csv,  ConversionTier.t1));
  });

  group('可用格数量校验', () {
    test('矩阵共有 27 个可用格（T1×8 + T2×19）', () {
      int t1Count = 0, t2Count = 0;
      for (final source in DocFormat.values) {
        for (final target in DocFormat.values) {
          final tier = conversionTier(source, target);
          if (tier == ConversionTier.t1) t1Count++;
          if (tier == ConversionTier.t2) t2Count++;
        }
      }
      expect(t1Count, 8, reason: 'T1 应为 8 格');
      expect(t2Count, 19, reason: 'T2 应为 19 格');
      expect(t1Count + t2Count, 27, reason: '可用格应共 27 个');
    });

    test('矩阵共有 9 个不可用格', () {
      int unavailableCount = 0;
      for (final source in DocFormat.values) {
        for (final target in DocFormat.values) {
          if (conversionTier(source, target) == ConversionTier.unavailable) {
            unavailableCount++;
          }
        }
      }
      expect(unavailableCount, 9, reason: '不可用格应为 9 个');
    });
  });
}

void _assertTier(DocFormat source, DocFormat target, ConversionTier expected) {
  expect(
    conversionTier(source, target),
    expected,
    reason: '${source.name}→${target.name} 期望 ${expected.name}',
  );
}
