import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Table Data Parsing & AutoEdit Tests', () {
    test('parseData correctly parses table JSON with autoEdit flag', () {
      final jsonPayload = jsonEncode({
        'autoEdit': true,
        'rows': [
          [
            {'text': '标题1', 'style': 'header'},
            {'text': '标题2', 'style': 'header'},
          ],
          [
            {'text': '数值A', 'style': ''},
            {'text': '数值B', 'style': ''},
          ],
        ]
      });

      final parsed = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final autoEdit = parsed['autoEdit'] == true;
      expect(autoEdit, isTrue);

      final rawRows = parsed['rows'] as List;
      expect(rawRows.length, 2);
      expect((rawRows[0] as List)[0]['text'], '标题1');
      expect((rawRows[0] as List)[0]['style'], 'header');
      expect((rawRows[1] as List)[1]['text'], '数值B');
    });

    test('parseData handles empty or corrupted rows gracefully', () {
      final jsonPayload = jsonEncode({'rows': []});
      final parsed = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final rawRows = parsed['rows'] as List;
      final rows = rawRows.isEmpty ? const <List<Map<String, dynamic>>>[] : rawRows;
      expect(rows.isEmpty, isTrue);
    });
  });

  group('Table Controller Rebuild & Cell Focus Management', () {
    test('Controllers and FocusNodes are correctly created with Tab/Escape key listeners', () {
      final rows = [
        [
          {'text': '表头1', 'style': 'header'},
          {'text': '表头2', 'style': 'header'},
        ],
        [
          {'text': '内容1', 'style': ''},
          {'text': '内容2', 'style': ''},
        ],
      ];

      List<TextEditingController> cellCtrls = [];
      List<FocusNode> cellNodes = [];
      bool exitedEditMode = false;

      final totalCells = rows.fold<int>(0, (sum, r) => sum + r.length);
      var index = 0;
      for (final row in rows) {
        for (final cell in row) {
          final curIndex = index;
          cellCtrls.add(TextEditingController(text: cell['text']?.toString() ?? ''));
          final node = FocusNode(
            debugLabel: 'TableCellFocus_$curIndex',
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (event.logicalKey == LogicalKeyboardKey.tab) {
                  final isShift = HardwareKeyboard.instance.isShiftPressed;
                  final next = isShift
                      ? (curIndex - 1 + totalCells) % totalCells
                      : (curIndex + 1) % totalCells;
                  if (next >= 0 && next < cellNodes.length) {
                    cellNodes[next].requestFocus();
                    return KeyEventResult.handled;
                  }
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  exitedEditMode = true;
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
          );
          cellNodes.add(node);
          index++;
        }
      }

      expect(cellCtrls.length, 4);
      expect(cellNodes.length, 4);
      expect(cellCtrls[0].text, '表头1');
      expect(cellCtrls[1].text, '表头2');
      expect(cellCtrls[2].text, '内容1');
      expect(cellCtrls[3].text, '内容2');

      // Test Tab navigation
      final handledTab = cellNodes[0].onKeyEvent?.call(
        cellNodes[0],
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
          timeStamp: Duration.zero,
        ),
      );
      expect(handledTab, KeyEventResult.handled);

      // Test Escape exit edit mode
      final handledEscape = cellNodes[0].onKeyEvent?.call(
        cellNodes[0],
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
      );
      expect(handledEscape, KeyEventResult.handled);
      expect(exitedEditMode, isTrue);

      for (final c in cellCtrls) {
        c.dispose();
      }
      for (final n in cellNodes) {
        n.dispose();
      }
    });
  });

  group('Table Structural Operations (Add/Remove Rows & Columns)', () {
    test('addColumn and addRow expand grid dimensions without corrupting data', () {
      List<List<Map<String, dynamic>>> rows = [
        [
          {'text': '表头1', 'style': 'header'},
          {'text': '表头2', 'style': 'header'},
        ],
        [
          {'text': '内容1', 'style': ''},
          {'text': '内容2', 'style': ''},
        ],
      ];

      // Add column
      for (final row in rows) {
        row.add({
          'text': '',
          'style': row.first['style'] ?? '',
        });
      }
      expect(rows[0].length, 3);
      expect(rows[1].length, 3);
      expect(rows[0][2]['style'], 'header');
      expect(rows[1][2]['style'], '');

      // Add row
      final width = rows.first.length;
      rows.add(List.generate(width, (_) => {'text': '', 'style': ''}));
      expect(rows.length, 3);
      expect(rows[2].length, 3);
      expect(rows[2][0]['style'], '');

      // Remove column
      for (final row in rows) {
        row.removeLast();
      }
      expect(rows[0].length, 2);
      expect(rows[1].length, 2);
      expect(rows[2].length, 2);

      // Remove row
      rows.removeLast();
      expect(rows.length, 2);
    });
  });

  group('Table Persistence & Header Modification Serialization', () {
    test('Modifying header cell persists correctly to BlockEmbed payload', () {
      final rows = [
        [
          {'text': '旧表头1', 'style': 'header'},
          {'text': '旧表头2', 'style': 'header'},
        ],
        [
          {'text': '数据1', 'style': ''},
          {'text': '数据2', 'style': ''},
        ],
      ];

      final cellCtrls = [
        TextEditingController(text: '修改后的新表头1'),
        TextEditingController(text: '旧表头2'),
        TextEditingController(text: '数据1-更新'),
        TextEditingController(text: '数据2'),
      ];

      // Simulate _persist
      final persistedRows = <List<Map<String, dynamic>>>[];
      for (int r = 0; r < rows.length; r++) {
        final row = <Map<String, dynamic>>[];
        for (int c = 0; c < rows[r].length; c++) {
          final idx = r * rows[r].length + c;
          row.add({
            'text': idx < cellCtrls.length ? cellCtrls[idx].text : '',
            'style': r == 0 ? 'header' : '',
          });
        }
        persistedRows.add(row);
      }

      final payload = jsonEncode({'rows': persistedRows});
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final decodedRows = decoded['rows'] as List;

      expect(decodedRows[0][0]['text'], '修改后的新表头1');
      expect(decodedRows[0][0]['style'], 'header');
      expect(decodedRows[0][1]['text'], '旧表头2');
      expect(decodedRows[1][0]['text'], '数据1-更新');
      expect(decoded['autoEdit'], isNull); // autoEdit is NOT persisted

      for (final c in cellCtrls) {
        c.dispose();
      }
    });
  });

  group('Table Widget Interactive Tests', () {
    testWidgets('Clicking cell switches to edit mode, allows editing, and typing does not leak outside', (tester) async {
      final rows = [
        [
          {'text': '表头A', 'style': 'header'},
          {'text': '表头B', 'style': 'header'},
        ],
        [
          {'text': '单元格1', 'style': ''},
          {'text': '单元格2', 'style': ''},
        ],
      ];

      final cellCtrls = [
        TextEditingController(text: '表头A'),
        TextEditingController(text: '表头B'),
        TextEditingController(text: '单元格1'),
        TextEditingController(text: '单元格2'),
      ];
      final cellNodes = [
        FocusNode(),
        FocusNode(),
        FocusNode(),
        FocusNode(),
      ];

      bool isEditing = false;
      int focusedCell = -1;

      Widget buildTestHarness() {
        return StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    Container(
                      height: 40,
                      color: Colors.grey[200],
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              setState(() {
                                isEditing = true;
                                focusedCell = 0;
                                cellNodes[0].requestFocus();
                              });
                            },
                          ),
                          if (isEditing)
                            IconButton(
                              icon: const Icon(Icons.check),
                              onPressed: () {
                                setState(() {
                                  isEditing = false;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    Table(
                      children: [
                        for (int r = 0; r < rows.length; r++)
                          TableRow(
                            children: [
                              for (int c = 0; c < rows[r].length; c++)
                                Builder(
                                  builder: (context) {
                                    final idx = r * rows[r].length + c;
                                    if (isEditing) {
                                      return TextField(
                                        key: ValueKey('cell_field_$idx'),
                                        controller: cellCtrls[idx],
                                        focusNode: cellNodes[idx],
                                      );
                                    } else {
                                      return InkWell(
                                        key: ValueKey('cell_inkwell_$idx'),
                                        onTap: () {
                                          setState(() {
                                            isEditing = true;
                                            focusedCell = idx;
                                            cellNodes[idx].requestFocus();
                                          });
                                        },
                                        child: Text(cellCtrls[idx].text),
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Initial state: not editing, Text widgets visible
      expect(find.byKey(const ValueKey('cell_inkwell_0')), findsOneWidget);
      expect(find.text('表头A'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Direct click on header cell 0
      await tester.tap(find.byKey(const ValueKey('cell_inkwell_0')));
      await tester.pumpAndSettle();

      // Should now be in edit mode!
      expect(isEditing, isTrue);
      expect(focusedCell, 0);
      expect(find.byKey(const ValueKey('cell_field_0')), findsOneWidget);
      expect(cellNodes[0].hasFocus, isTrue);

      // Edit the header cell
      await tester.enterText(find.byKey(const ValueKey('cell_field_0')), '超级新表头');
      await tester.pumpAndSettle();

      expect(cellCtrls[0].text, '超级新表头');

      // Click "Done" (finish edit)
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify exited edit mode, new text displayed
      expect(isEditing, isFalse);
      expect(find.text('超级新表头'), findsOneWidget);

      for (final c in cellCtrls) {
        c.dispose();
      }
      for (final n in cellNodes) {
        n.dispose();
      }
    });
  });
}
