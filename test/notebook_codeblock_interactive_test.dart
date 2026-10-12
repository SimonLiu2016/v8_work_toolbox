import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Baseline Plain TextField backspace test', (tester) async {
    final ctrl = TextEditingController(text: 'hello');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: ctrl, autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ctrl.text, equals('hello'));

    ctrl.selection = const TextSelection.collapsed(offset: 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    print('Plain TextField backspace result: "${ctrl.text}"');
  });
}
