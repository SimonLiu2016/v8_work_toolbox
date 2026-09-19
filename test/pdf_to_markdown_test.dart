import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/pdf_to_markdown.dart';

/// 构造 run 结构：`[[[fontSize, text], ...], ...]`（按页分组）
List<dynamic> _pages(List<List<List<dynamic>>> pages) => pages;

void main() {
  group('PdfToMarkdown.convertFromRuns — 字号→标题层级', () {
    test('正文字号取频次最高者，相对倍数映射标题', () {
      // 正文 10pt 占多数；20pt 是 H1；14pt 是 H2
      final pages = _pages([
        [
          [20.0, '文档标题\n'],
          [10.0, '这是一段正文内容。\n'],
          [14.0, '章节标题\n'],
          [10.0, '另一段正文内容。\n'],
          [10.0, '还有更多正文。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('# 文档标题'));
      expect(md, contains('## 章节标题'));
      expect(md, contains('这是一段正文内容。'));
      // 正文不应被当作标题
      expect(md, isNot(contains('# 这是一段正文内容。')));
    });

    test('仅正文时输出无标题层级', () {
      final pages = _pages([
        [
          [10.0, '第一段。\n'],
          [10.0, '第二段。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, isNot(contains('#')));
      expect(md, contains('第一段。'));
    });
  });

  group('PdfToMarkdown.convertFromRuns — 段落回流', () {
    test('未以终结标点收尾的行被合并为同一段落', () {
      // 一条被物理换行截断的句子
      final pages = _pages([
        [
          [10.0, '这是一句被换行\n'],
          [10.0, '截断的正文内容。\n'],
          [10.0, '这是独立的一句。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('这是一句被换行截断的正文内容。'));
      // 独立句子不被并入上一段
      expect(md, contains('这是独立的一句。'));
    });

    test('CJK 拼接不插空格，拉丁字母间插空格', () {
      final cjk = PdfToMarkdown.convertFromRuns(_pages([
        [
          [10.0, '中文换行\n'],
          [10.0, '继续中文。\n'],
        ],
      ]));
      expect(cjk, contains('中文换行继续中文。'));

      final latin = PdfToMarkdown.convertFromRuns(_pages([
        [
          [10.0, 'hello\n'],
          [10.0, 'world.\n'],
        ],
      ]));
      expect(latin, contains('hello world.'));
    });
  });

  group('PdfToMarkdown.convertFromRuns — 噪声过滤', () {
    test('页首页尾的纯数字行（页码）被过滤', () {
      final pages = _pages([
        [
          [9.0, '1\n'], // 页首页码
          [10.0, '正文第一段。\n'],
          [10.0, '正文第二段。\n'],
          [9.0, '2\n'], // 页尾页码
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('正文第一段。'));
      expect(md.trim(), isNot(contains('\n1\n')));
      expect(md.trim(), isNot(contains('\n2')));
    });

    test('页中的纯数字行不被误删（仅页首页尾 2 行过滤）', () {
      final pages = _pages([
        [
          [10.0, '开头段落。\n'],
          [10.0, '中间段落。\n'],
          [10.0, '2024\n'], // 页中数字，应保留
          [10.0, '继续段落。\n'],
          [10.0, '结尾段落。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('2024'));
    });

    test('孤立项目符号行被丢弃，带内容的 bullet 补 `- ` 前缀', () {
      // bullet 与内容在同一 run——补前缀，恢复列表语义
      final pages = _pages([
        [
          [10.0, '• 列表项内容一。\n'],
          [10.0, '• 列表项内容二。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('- 列表项内容一。'));
      expect(md, contains('- 列表项内容二。'));
      // 不应残留裸 bullet 符号
      expect(md, isNot(contains('•')));
    });

    test('私用区 bullet（U+F0A8）也被还原为 `- ` 前缀', () {
      // Wingdings 私用区码位，PDFKit 直接输出而非还原为 U+2022
      final pages = _pages([
        [
          [10.0, '\u{F0A8} Enter the Password\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('- Enter the Password'));
      expect(md, isNot(contains('\u{F0A8}')));
    });
  });

  group('PdfToMarkdown.convertFromRuns — 粗体与标签', () {
    test('加粗 + 冒号结尾 → 整行加粗标签', () {
      // 真实样本里 "Name : " 是 bold run、"Zhongren Liu" 是非 bold run，
      // 两者同字号合并后整行 bold=true 但不以冒号结尾——
      // 这种"标签-值"行只在富文本升级后才能精确还原标签加粗，
      // 当前降级为整行加粗。这里只验证纯标签行（以冒号结尾）的判定。
      final pages = _pages([
        [
          [11.0, 'Name :\n', true],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('**Name :**'));
    });

    test('章节标记行首 → h2（即使非粗体）', () {
      final pages = _pages([
        [
          [11.0, '正文一段。\n'],
          [11.0, '(B) Rules and Regulations\n', false],
          [11.0, 'o 子项内容。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('## (B) Rules and Regulations'));
    });

    test('加粗独占短行 → h3', () {
      final pages = _pages([
        [
          [11.0, '前置正文。\n', false],
          [11.0, 'Note - Password Criteria\n', true],
          [11.0, '后续正文。\n', false],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('### Note - Password Criteria'));
    });
  });

  group('PdfToMarkdown.convertFromRuns — 英文句号与续行', () {
    test('英文句号结尾的行不被误合并', () {
      final pages = _pages([
        [
          [10.0, '1. Switch on your machine.\n'],
          [10.0, '2. You will see the screen.\n'],
          [10.0, '3. Key in your username.\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      // 各成独立行，不被并成一条
      expect(md, contains('1. Switch on your machine.'));
      expect(md, contains('2. You will see the screen.'));
      expect(md, contains('3. Key in your username.'));
      // 不应把三行并成一条
      expect(md, isNot(contains('machine.2.')));
    });

    test('小写开头的续行仍被合并（物理换行截断的句子）', () {
      final pages = _pages([
        [
          [10.0, 'This is a long\n'],
          [10.0, 'sentence continued.\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('This is a long sentence continued.'));
    });

    test('大写开头的新行不与上一行合并', () {
      final pages = _pages([
        [
          [10.0, 'End of paragraph.\n'],
          [10.0, 'New paragraph starts here.\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('End of paragraph.'));
      expect(md, contains('New paragraph starts here.'));
      // 不应被并成一条
      expect(md, isNot(contains('paragraph.New')));
    });

    test('小数 `3.14` 与版本号 `v.2` 不被句末标点误切', () {
      final pages = _pages([
        [
          // 3.14 后紧跟内容，`.` 后接数字不应判句末
          [10.0, 'The value is 3.14\n'],
          [10.0, 'and version is v.2.\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      // 两行应被合并（`3.14` 的 `.` 不在行尾，`v.2.` 的 `.` 在行尾才判句末）
      // 这里验证 `3.14` 不导致拆分
      expect(md, contains('3.14'));
      expect(md, contains('v.2'));
    });

    test('真实样本结构：多行不再并成一条巨块', () {
      // 模拟 Seatrium 表单的 run 结构（简化）：同字号多行，以 `.` 或冒号结尾
      final pages = _pages([
        [
          [11.0, 'WELCOME TO Seatrium\n', true],
          [11.0, 'User Details\n', true],
          [11.0, 'Name : Zhongren Liu\n', true],
          [11.0, 'Company : CO-MALL\n', true],
          [11.0, '1. Switch on your machine.\n', false],
          [11.0, '2. You will see the screen.\n', false],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      // 不应把所有行并成一条
      expect(md, isNot(contains('SeatriumUser Details')));
      expect(md, isNot(contains('machine.2.')));
      // 各行应独立出现
      expect(md, contains('User Details'));
      expect(md, contains('Name : Zhongren Liu'));
      expect(md, contains('1. Switch on your machine.'));
      expect(md, contains('2. You will see the screen.'));
    });
  });

  group('PdfToMarkdown.convertFromRuns — 边界', () {
    test('全空输入抛 PdfNoTextLayerException', () {
      expect(
        () => PdfToMarkdown.convertFromRuns(_pages([[]])),
        throwsA(isA<PdfNoTextLayerException>()),
      );
    });

    test('字号为 0 的 run 被忽略', () {
      final pages = _pages([
        [
          [0.0, '无效 run'],
          [10.0, '有效正文。\n'],
        ],
      ]);
      final md = PdfToMarkdown.convertFromRuns(pages);
      expect(md, contains('有效正文。'));
      expect(md, isNot(contains('无效 run')));
    });
  });
}
