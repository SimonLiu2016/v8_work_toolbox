import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/components/note_editor_toolbar.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/notebook/note_store.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';

/// `NoteEditor` 的渲染冒烟测试（spec: notebook-editor）。
///
/// 这个文件曾因断言 `QuillEditor` / `QuillSimpleToolbar` 而整体失败——编辑器
/// 早已换成 `AppFlowyEditor` + 自有的 `NoteEditorToolbar`，测试却没跟上。
/// 一度被删掉，那等于放弃了对编辑器渲染的保护，所以按当前契约重写。
///
/// 断言形态与旧版的关键差异：AppFlowyEditor 的正文不走 Material 的
/// `find.text`（文本由 RichText 逐 span 渲染），所以正文内容改从
/// `EditorState.document` 经 [AppFlowyCodec.documentToPlainText] 读取。
Widget wrapWith(Note note) => MaterialApp(
  theme: AppTheme.darkTheme,
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 600,
      child: NoteEditor(note: note),
    ),
  ),
);

Note makeNote({
  required String id,
  required String title,
  required List<dynamic> delta,
}) => Note(
  id: id,
  title: title,
  deltaJson: jsonEncode(delta),
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
  isPinned: false,
  isDeleted: false,
);

/// 取出编辑器当前文档的纯文本，用于断言正文真的渲染进了编辑器。
String documentText(WidgetTester tester) {
  final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
  return AppFlowyCodec.documentToPlainText(editor.editorState.document);
}

void main() {
  setUpAll(() async {
    // NoteStore 未初始化时 _loadMetadata 会抛 LateInitializationError（已被
    // catch，但每条测试都刷一行噪声）。装上真实 store 让日志干净。
    // 数据落临时目录，不碰用户真实的笔记本数据库。
    final tempDir = await Directory.systemTemp.createTemp('note_editor_test_');
    AppPaths.overrideRootForTesting(tempDir);
    addTearDown(() async {
      AppPaths.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await NoteStore.instance.init();
  });

  testWidgets('NoteEditor 渲染标题、工具栏与编辑器画布', (tester) async {
    await tester.pumpWidget(wrapWith(makeNote(
      id: 'n1',
      title: '测试笔记',
      delta: [
        {'insert': '第一行文字\n'},
      ],
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('测试笔记'), findsOneWidget, reason: '标题输入框');
    expect(find.byType(NoteEditorToolbar), findsOneWidget,
        reason: '格式工具栏（不再是 QuillSimpleToolbar）');
    expect(find.byType(AppFlowyEditor), findsOneWidget,
        reason: '编辑器画布（不再是 QuillEditor）');
    expect(documentText(tester), contains('第一行文字'));
  });

  testWidgets('链接、代码块与列表内容渲染不崩溃', (tester) async {
    await tester.pumpWidget(wrapWith(makeNote(
      id: 'n2',
      title: 'Docker常规操作',
      delta: [
        {'insert': 'Docker容器操作指南'},
        {'insert': '\n', 'attributes': {'header': 1}},
        {'insert': '查看官方文档: '},
        {'insert': 'Docker Hub', 'attributes': {'link': 'https://hub.docker.com'}},
        {'insert': '\n'},
        {'insert': 'docker run -d -p 80:80 nginx'},
        {'insert': '\n', 'attributes': {'code-block': true}},
        {'insert': '检查容器状态'},
        {'insert': '\n', 'attributes': {'list': 'bullet'}},
        {'insert': '已完成端口验证'},
        {'insert': '\n', 'attributes': {'list': 'checked'}},
      ],
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Docker常规操作'), findsOneWidget);
    // 内容必须真的进了文档，而不是静默丢弃。
    final text = documentText(tester);
    expect(text, contains('Docker容器操作指南'));
    expect(text, contains('docker run -d -p 80:80 nginx'));
    expect(text, contains('检查容器状态'));
    expect(text, contains('已完成端口验证'));
  });

  testWidgets('未知嵌入（图片 / 视频）渲染不崩溃', (tester) async {
    // 图片路径不存在、视频是外链——两者都不该让编辑器崩。
    await tester.pumpWidget(wrapWith(makeNote(
      id: 'n3',
      title: 'SDD Kit',
      delta: [
        {
          'insert': 'Using GitHub Spec Kit with your EXISTING PROJECTS',
          'attributes': {'link': 'https://www.youtube.com'}
        },
        {'insert': '\n', 'attributes': {'list': 'ordered'}},
        {'insert': '命令\n'},
        {'insert': {'image': '/tmp/test_image_fake.png'}},
        {'insert': '\n'},
        {'insert': {'video': 'https://example.com/video.mp4'}},
        {'insert': '\n'},
      ],
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SDD Kit'), findsOneWidget);
    expect(documentText(tester), contains('命令'));
  });

  testWidgets('空笔记也能渲染（note 为 null 的旁路）', (tester) async {
    // NoteEditor 的 note 可为 null（新建未保存的笔记）。这条守的是
    // `_initEditor` 的 else 分支——_editorState 为 null 时不能崩。
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: const Scaffold(
        body: SizedBox(width: 800, height: 600, child: NoteEditor()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
