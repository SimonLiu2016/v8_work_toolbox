import 'dart:convert';
import 'package:flutter/material.dart';

class ShortcutInput extends StatefulWidget {
  final bool isJsonMode;
  final int shortcutRowsCount;
  final List<TextEditingController> idControllers;
  final List<TextEditingController> nameControllers;
  final List<TextEditingController> descriptionControllers;
  final List<TextEditingController> keysControllers;
  final List<TextEditingController> rawControllers;
  final List<TextEditingController> categoryControllers;
  final List<TextEditingController> whenControllers;
  final TextEditingController shortcutsJsonController;
  final Function(bool) onModeChange;
  final Function() onAddRow;
  final Function(int) onRemoveRow;
  final Function() onRemoveLastRow;
  final Function() onGenerateJsonFromInteractive;
  final Function() onParseJsonToInteractive;

  const ShortcutInput({
    Key? key,
    required this.isJsonMode,
    required this.shortcutRowsCount,
    required this.idControllers,
    required this.nameControllers,
    required this.descriptionControllers,
    required this.keysControllers,
    required this.rawControllers,
    required this.categoryControllers,
    required this.whenControllers,
    required this.shortcutsJsonController,
    required this.onModeChange,
    required this.onAddRow,
    required this.onRemoveRow,
    required this.onRemoveLastRow,
    required this.onGenerateJsonFromInteractive,
    required this.onParseJsonToInteractive,
  }) : super(key: key);

  @override
  State<ShortcutInput> createState() => _ShortcutInputState();
}

class _ShortcutInputState extends State<ShortcutInput> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '快捷键信息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('交互式'),
                      selected: !widget.isJsonMode,
                      onSelected: (bool selected) {
                        if (selected) {
                          // 从 JSON 模式切换到交互模式时，解析 JSON 数据
                          if (widget.isJsonMode) {
                            widget.onParseJsonToInteractive();
                          }
                          widget.onModeChange(false);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('JSON'),
                      selected: widget.isJsonMode,
                      onSelected: (bool selected) {
                        if (selected) {
                          // 从交互模式切换到 JSON 模式时，生成 JSON 数据
                          if (!widget.isJsonMode) {
                            widget.onGenerateJsonFromInteractive();
                          }
                          widget.onModeChange(true);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!widget.isJsonMode) ...[
              // 交互式模式
              ...List.generate(
                widget.shortcutRowsCount,
                (index) => _buildShortcutRow(index),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: widget.onAddRow,
                icon: const Icon(Icons.add),
                label: const Text('添加快捷键'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: widget.onRemoveLastRow,
                icon: const Icon(Icons.remove),
                label: const Text('删除最后一行'),
              ),
            ] else ...[
              // JSON 模式
              const SizedBox(height: 10),
              SizedBox(
                height: 200,
                child: TextField(
                  controller: widget.shortcutsJsonController,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText:
                        '输入快捷键 JSON 数据，例如：\n[\n  {\n    "id": "example_shortcut",\n    "name": "Example Shortcut",\n    "description": "An example shortcut",\n    "keys": ["⌘", "C"],\n    "raw": "Cmd+C",\n    "category": "edit",\n    "when": "global"\n  }\n]',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutRow(int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: widget.idControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'ID (英文小写和下划线)',
                      hintText: '如: copy_text',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: widget.nameControllers[index],
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '快捷键名称',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: widget.descriptionControllers[index],
              decoration: const InputDecoration(
                labelText: '描述',
                hintText: '快捷键描述',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.keysControllers[index],
                    decoration: const InputDecoration(
                      labelText: '按键组合',
                      hintText: '如: ["⌘", "C"]',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: widget.rawControllers[index],
                    decoration: const InputDecoration(
                      labelText: '原始格式',
                      hintText: '如: Cmd+C',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.categoryControllers[index],
                    decoration: const InputDecoration(
                      labelText: '类型',
                      hintText: '如: edit',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: widget.whenControllers[index],
                    decoration: const InputDecoration(
                      labelText: '使用时机',
                      hintText: '如: global',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    widget.onRemoveRow(index);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _parseKeysString(String keysString) {
    if (keysString.startsWith('[') && keysString.endsWith(']')) {
      try {
        return jsonDecode(keysString);
      } catch (e) {
        // 如果解析失败，返回原字符串
        return [keysString];
      }
    }
    return [keysString];
  }

  String _formatKeysList(dynamic keys) {
    if (keys is List) {
      return jsonEncode(keys);
    }
    return keys?.toString() ?? '';
  }
}
