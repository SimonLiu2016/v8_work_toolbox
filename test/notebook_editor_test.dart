import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('NoteEditor renders without localization crash or overflow', (tester) async {
    final note = Note(
      id: 'test-note-1',
      title: '测试笔记',
      deltaJson: jsonEncode([
        {'insert': '第一行文字\n'},
      ]),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      isDeleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteEditor(note: note),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and editor rendered
    expect(find.text('测试笔记'), findsOneWidget);
    expect(find.byType(QuillSimpleToolbar), findsOneWidget);
    expect(find.byType(QuillEditor), findsOneWidget);

    // Verify no exception occurred during pump
    expect(tester.takeException(), isNull);

    // Verify tapping on empty editor area triggers focus
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
  });

  testWidgets('NoteEditor renders notes with links, code blocks and lists without crash', (tester) async {
    final complexNote = Note(
      id: 'test-note-complex',
      title: 'Docker常规操作',
      deltaJson: jsonEncode([
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
      ]),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      isDeleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteEditor(note: complexNote),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify no exception occurred during pump
    expect(tester.takeException(), isNull);
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.text('Docker常规操作'), findsOneWidget);
  });

  testWidgets('NoteEditor renders notes with image embeds and unknown embeds without crash', (tester) async {
    final noteWithEmbeds = Note(
      id: 'test-note-sdd-kit',
      title: 'SDD Kit',
      deltaJson: jsonEncode([
        {'insert': 'Using GitHub Spec Kit with your EXISTING PROJECTS', 'attributes': {'link': 'https://www.youtube.com'}},
        {'insert': '\n', 'attributes': {'list': 'ordered'}},
        {'insert': '命令\n'},
        {'insert': {'image': '/tmp/test_image_fake.png'}},
        {'insert': '\n'},
        {'insert': {'video': 'https://example.com/video.mp4'}},
        {'insert': '\n'},
      ]),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      isDeleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteEditor(note: noteWithEmbeds),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and editor rendered without exception
    expect(tester.takeException(), isNull);
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.text('SDD Kit'), findsOneWidget);

    // Verify translucent textSelectionTheme applied
    final themeFinder = find.ancestor(
      of: find.byType(QuillEditor),
      matching: find.byType(Theme),
    );
    expect(themeFinder, findsWidgets);
    final themeWidget = tester.widget<Theme>(themeFinder.first);
    expect(themeWidget.data.textSelectionTheme.selectionColor, const Color(0x66BFDBFE));
  });
}

