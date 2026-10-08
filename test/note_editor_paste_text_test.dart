import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/tools/notebook/services/clipboard_image_service.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

/// 接管粘贴命令后的纯文本粘贴行为（capability:
/// `notebook-clipboard-image-paste` 的 "Text pasting behaviour is preserved"）。
///
/// 两组证据，边界不同，读前务必分清：
///
/// 1. **叶子函数**（`insertPlainTextPaste` 组）：断言来自读接管前包内实现
///    （`appflowy_editor` 的 `paste_command.dart`）得出的契约，**不是跑出来的**。
///    那个 handler 是包内私有的，测试与生产都调不到它。所以这里证明的是
///    「接管后符合这份读源码得出的契约」，不宣称「与接管前行为逐位相等」。
/// 2. **分派层**（`handleClipboardPaste` 组）：断言"三条出路各走各的"，这是我们
///    自己的逻辑，**不是**从包行为推断的。它存在的原因见该组注释——上一轮失效
///    就发生在这一层，而它当时测不到。
///
/// 两者的实机对比都见 tasks 6.3-6.7。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a pasted URL stays plain text', () {
    // 接管前包内有一个 URL→href 的分支，但它排在 deleteSelectionIfNeeded()
    // 之后，而删除后 selection 必然 isCollapsed，该分支的守卫又要求
    // isCollapsed == false —— 永远不可达。所以接管前粘 URL 也是纯文本。
    // 这里钉住"我们没有把死分支抄成活的"。
    test('URL is inserted as text, not as a link', () async {
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, 'https://example.com');

      final hrefs = _collectHrefs(state);
      expect(hrefs, isEmpty, reason: '接管前也不会变链接');
      expect(_allText(state), contains('https://example.com'));
    });

    test('phone number is inserted as text, not as a tel: link', () async {
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, '13800138000');

      expect(_collectHrefs(state), isEmpty);
      expect(_allText(state), contains('13800138000'));
    });
  });

  group('insertPlainTextPaste', () {
    test('single line continues in the current paragraph', () async {
      // 接管前 pasteSingleLineNode 的语义是"在光标处续写"，不是新建段落——
      // 只有当目标段落本身为空时才整段替换。这条钉住那个语义。
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, '新的一行');

      expect(state.document.root.children.length, 1);
      expect(
        state.document.root.children.single.delta!.toPlainText(),
        '第一段新的一行',
      );
    });

    test('single line into an empty paragraph replaces it', () async {
      final state = _stateWithDoc('');

      await insertPlainTextPaste(state, '只有一行');

      expect(state.document.root.children.length, 1);
      expect(
        state.document.root.children.single.delta!.toPlainText(),
        '只有一行',
      );
    });

    test('multiple lines merge into the current paragraph then split', () async {
      // pasteMultiLineNodes 的语义：当前段在光标之前的内容并入第一个新节点，
      // 之后按行拆段。所以 '第一段' + 三行 = 3 个节点，第一个是 '第一段行一'。
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, '行一\n行二\n行三');

      expect(state.document.root.children.length, 3);
      expect(state.document.root.children[0].delta!.toPlainText(), '第一段行一');
      expect(state.document.root.children[1].delta!.toPlainText(), '行二');
      expect(state.document.root.children[2].delta!.toPlainText(), '行三');
    });

    test('CR is stripped and trailing whitespace trimmed', () async {
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, 'windows 行\r\n带尾空格   ');

      expect(state.document.root.children.length, 2);
      expect(state.document.root.children[0].delta!.toPlainText(), '第一段windows 行');
      expect(state.document.root.children[1].delta!.toPlainText(), '带尾空格');
    });

    test('a URL replaces the selected text', () async {
      final state = _stateWithDoc('要被替换的旧内容');
      _selectAll(state);

      await insertPlainTextPaste(state, 'https://example.com');

      final all = _allText(state);
      expect(all, isNot(contains('要被替换的旧内容')));
      expect(all, contains('https://example.com'));
    });

    test('inline attributes at the selection are inherited', () async {
      // 光标落在加粗段内：接管前用 getDeltaAttributesInSelectionStart() 取
      // 行内属性并带给新插入的文本。
      final state = _stateWithDoc('第一段');
      // 文档只有一段（path [0]），直接把它整段设成加粗。
      final fmtTx = state.transaction;
      fmtTx.formatText(state.getNodeAtPath([0])!, 0, 3, {
        AppFlowyRichTextKeys.bold: true,
      });
      await state.apply(fmtTx);
      state.updateSelectionWithReason(
        Selection.single(path: [0], startOffset: 1),
        reason: SelectionUpdateReason.uiEvent,
      );
      expect(
        state.getDeltaAttributesInSelectionStart(),
        isNotNull,
        reason: '测试前提：光标处必须读得到行内属性',
      );

      await insertPlainTextPaste(state, '续写');

      final target = state.getNodeAtPath([0])!;
      // 光标在 offset 1（"第"之后），所以续写插在"第"与"一段"之间。
      expect(target.delta!.toPlainText(), '第续写一段');
      // Delta 会把相邻同属性的 insert 合并成一个 op，所以不能按
      // op.data == '续写' 精确定位；整段同属性即证明粘贴文本继承了加粗。
      final allBold = target.delta!
          .whereType<TextInsert>()
          .every((op) => op.attributes?[AppFlowyRichTextKeys.bold] == true);
      expect(
        allBold,
        isTrue,
        reason: '粘贴文本必须继承光标处的行内属性',
      );
    });

    test('a non-empty selection is replaced, not appended after', () async {
      final state = _stateWithDoc('要被替换掉的旧内容');
      _selectAll(state);

      await insertPlainTextPaste(state, '新内容');

      // 接管前 deleteSelectionIfNeeded() 先删选中区；若漏了这一步，粘贴会
      // 变成"追加"，原文还在。
      final all = state.document.root.children
          .map((n) => n.delta?.toPlainText() ?? '')
          .join();
      expect(all, isNot(contains('要被替换掉的旧内容')));
      expect(all, contains('新内容'));
    });
  });

  // ---------------------------------------------------------------------------
  // 分派层：handleClipboardPaste —— 本文件存在的理由
  //
  // 上面那些组测的是"粘贴逻辑对不对"。这一组测的是"它到底会不会被调到"。
  // 上一轮失效全在后半句：三态 enum 里表示"没有图片"的值没有任何生产者，
  // 于是剪贴板有文字时 handler 提前 return，_pastePlainText 从落地起就没通过。
  // 用户看到的是 ⌘V 粘图片好的、粘文字毫无反应。而同一时期上面 9 个用例全绿。
  //
  // 所以这里三条出路各钉一条，且必须继续钉着：任何时候让 handleClipboardPaste
  // 变成不可测或删掉这一组，都等于把同类事故重新请回来。
  // ---------------------------------------------------------------------------
  group('handleClipboardPaste 分派层', () {
    test('剪贴板只有文字时文字真的进了正文（本 bug 的回归测试）', () async {
      final state = _stateWithDoc('第一段');

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        ClipboardImageResult.failure(
          ClipboardImageFailure.nothingPasteable,
          clipboardText: '粘贴进来的文字',
        ),
        onError: (_) => fail('纯文字粘贴不该触发出错气泡'),
      );

      expect(acted, isTrue, reason: '这一下确实对文档做了点什么');
      expect(_allText(state), contains('粘贴进来的文字'));
    });

    test('多行文字在分派层也按行拆段', () async {
      final state = _stateWithDoc('第一段');

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        ClipboardImageResult.failure(
          ClipboardImageFailure.nothingPasteable,
          clipboardText: '行一\n行二',
        ),
        onError: (_) => fail('不该出错'),
      );

      expect(acted, isTrue);
      expect(state.document.root.children.length, 2);
      expect(state.document.root.children[0].delta!.toPlainText(), '第一段行一');
      expect(state.document.root.children[1].delta!.toPlainText(), '行二');
    });

    test('剪贴板既无文字也无图片时什么都不做，且不弹气泡', () async {
      final state = _stateWithDoc('第一段');
      final before = _allText(state);

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        // 位图探测失败这一路服务层返回 nothingPasteable，文本为 null：
        // 位图没读到、文本也没读到，剪贴板就是空的。
        const ClipboardImageResult.failure(
          ClipboardImageFailure.nothingPasteable,
        ),
        onError: (_) => fail('空剪贴板不是错误，不该打扰用户'),
      );

      expect(acted, isFalse, reason: 'false = 按键该交还系统，别安静吃掉');
      expect(_allText(state), before, reason: '文档必须保持原样');
    });

    test('取图真的失败时弹气泡、文档不动', () async {
      final state = _stateWithDoc('第一段');
      final before = _allText(state);
      final messages = <String>[];

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        const ClipboardImageResult.failure(
          ClipboardImageFailure.downloadFailed,
          detail: 'HTTP 404',
        ),
        onError: messages.add,
      );

      expect(acted, isFalse);
      expect(messages, hasLength(1));
      expect(messages.single, contains('下载失败'));
      expect(messages.single, contains('404'), reason: '要说清是哪一步');
      expect(_allText(state), before, reason: '失败不能把文档改坏');
    });

    test('图片在剪贴板里时插图片块，不走文字分支', () async {
      final state = _stateWithDoc('第一段');
      // 一个真实的 1×1 PNG——saveImage 只按路径搬运，内容不重要，但形状要真。
      final png = await _writeTempPng('pasted.png');
      final messages = <String>[];
      final savedPaths = <String>[];

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        ClipboardImageResult.success(
          ClipboardImage(
            file: png,
            source: ClipboardImageSource.clipboardBitmap,
            ownedByService: false,
          ),
        ),
        onError: messages.add,
        saveImage: ({required noteId, required sourceFile, filename}) async {
          savedPaths.add(sourceFile.path);
          return 'attachments/fake_hash.png';
        },
      );

      expect(acted, isTrue);
      expect(messages, isEmpty, reason: '图片插入成功不需要气泡');
      expect(savedPaths, [png.path], reason: '落盘的必须是我们拿到的那张图');
      // 图片块是 image 类型的节点，不是新的段落。
      final types = state.document.root.children.map((n) => n.type).toList();
      expect(types, contains('image'));
      expect(_allText(state), '第一段', reason: '文字分支没有被走到');
    });

    test('图片与文字同时在剪贴板里时图片优先', () async {
      final state = _stateWithDoc('第一段');
      final png = await _writeTempPng('pasted.png');

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        ClipboardImageResult.success(
          ClipboardImage(
            file: png,
            source: ClipboardImageSource.clipboardBitmap,
            ownedByService: false,
          ),
        ),
        onError: (_) => fail('不该出错'),
        saveImage: ({required noteId, required sourceFile, filename}) async =>
            'attachments/fake_hash.png',
      );

      expect(acted, isTrue);
      // 位图优先：文字分支根本没被调用，所以正文里没有任何新文字。
      expect(_allText(state), '第一段');
    });

    test('图片落盘失败时弹气泡、文档不动', () async {
      final state = _stateWithDoc('第一段');
      final png = await _writeTempPng('pasted.png');
      final messages = <String>[];

      final acted = await handleClipboardPaste(
        state,
        'test-note-1',
        ClipboardImageResult.success(
          ClipboardImage(
            file: png,
            source: ClipboardImageSource.clipboardBitmap,
            ownedByService: false,
          ),
        ),
        onError: messages.add,
        saveImage: ({required noteId, required sourceFile, filename}) =>
            throw StateError('磁盘满了'),
      );

      expect(acted, isFalse);
      expect(messages.single, contains('磁盘满了'));
      final types = state.document.root.children.map((n) => n.type).toList();
      expect(types, isNot(contains('image')), reason: '失败不能留下半个图片块');
    });
  });
}

EditorState _stateWithDoc(String text) {
  // 必须是 Document(root: pageNode(children: [...]))——直接拿 paragraphNode
  // 当 root 会得到 0 个 children（它自己被当成 page），后面全部断言都会空。
  final doc = Document(
    root: pageNode(children: [paragraphNode(delta: Delta()..insert(text))]),
  );
  final state = EditorState(document: doc);
  state.updateSelectionWithReason(
    Selection.single(path: [0], startOffset: text.length),
    reason: SelectionUpdateReason.uiEvent,
  );
  return state;
}

/// 选中整篇文档内容，模拟用户按下 ⌘A 之后的状态。
void _selectAll(EditorState state) {
  final first = state.document.root.children.first;
  final length = first.delta?.length ?? 0;
  state.updateSelectionWithReason(
    Selection.single(path: first.path, startOffset: 0, endOffset: length),
    reason: SelectionUpdateReason.uiEvent,
  );
}

Set<String> _collectHrefs(EditorState state) {
  final hrefs = <String>{};
  for (final node in state.document.root.children) {
    for (final op in node.delta!.whereType<TextInsert>()) {
      final href = op.attributes?[AppFlowyRichTextKeys.href];
      if (href is String) hrefs.add(href);
    }
  }
  return hrefs;
}

String _allText(EditorState state) {
  return state.document.root.children
      .map((n) => n.delta?.toPlainText() ?? '')
      .join();
}

/// 造一个真实的 1×1 PNG（能过魔数校验），供图片分支的 saveAttachment 落盘。
Future<File> _writeTempPng(String name) async {
  final file = File(p.join(Directory.systemTemp.path, 'v8_paste_test_$name'));
  await file.writeAsBytes(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
      'DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
    ),
    flush: true,
  );
  return file;
}

