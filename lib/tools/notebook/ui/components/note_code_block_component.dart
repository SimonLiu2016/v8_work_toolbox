import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class NoteCodeBlockKeys {
  NoteCodeBlockKeys._();
  static const String type = 'code_block';
  static const String code = 'code';
  static const String language = 'language';
}

Node codeBlockNode({required String code, String language = 'plaintext'}) {
  return Node(
    type: NoteCodeBlockKeys.type,
    attributes: {
      NoteCodeBlockKeys.code: code,
      NoteCodeBlockKeys.language: language,
      'delta': (Delta()..insert(code)).toJson(),
    },
  );
}

class NoteCodeBlockComponentBuilder extends BlockComponentBuilder {
  NoteCodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return NoteCodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class NoteCodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const NoteCodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<NoteCodeBlockComponentWidget> createState() => _NoteCodeBlockComponentWidgetState();
}

class _NoteCodeBlockComponentWidgetState extends State<NoteCodeBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late String _code;
  late String _language;
  bool _copied = false;
  late TextEditingController _textCtrl;
  late FocusNode _codeFocusNode;

  static const List<String> _languages = [
    'plaintext', 'dart', 'python', 'javascript', 'typescript',
    'java', 'c', 'cpp', 'go', 'rust', 'html', 'css',
    'sql', 'bash', 'json', 'yaml', 'markdown', 'swift', 'kotlin',
  ];

  @override
  void initState() {
    super.initState();
    _parseData();
    _textCtrl = TextEditingController(text: _code);
    _textCtrl.addListener(_onTextChanged);
    _codeFocusNode = FocusNode(debugLabel: 'NoteCodeBlockFocus');
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  int get _lineCount {
    final text = _textCtrl.text;
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  String get _lineNumbersText {
    final count = _lineCount;
    final sb = StringBuffer();
    for (int i = 1; i <= count; i++) {
      sb.writeln(i);
    }
    return sb.toString().trimRight();
  }

  @override
  void didUpdateWidget(covariant NoteCodeBlockComponentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      _parseData();
      if (_textCtrl.text != _code) {
        _textCtrl.text = _code;
      }
    }
  }

  @override
  void dispose() {
    _codeFocusNode.dispose();
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _parseData() {
    final rawCode = widget.node.attributes[NoteCodeBlockKeys.code];
    final rawLang = widget.node.attributes[NoteCodeBlockKeys.language];

    if (rawCode is String) {
      _code = rawCode;
    } else if (widget.node.delta != null) {
      _code = widget.node.delta!.toPlainText();
    } else {
      _code = '';
    }

    _language = (rawLang is String && rawLang.isNotEmpty) ? rawLang : 'plaintext';
  }

  void _persist() {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction
      ..updateNode(widget.node, {
        NoteCodeBlockKeys.code: _code,
        NoteCodeBlockKeys.language: _language,
      });
    editorState.apply(transaction);
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _deleteBlock() {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction..deleteNode(widget.node);
    editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // 高级暗色 IDE 风格
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部栏：语言选择器 + 复制按钮 + 删除按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                // 语言切换下拉
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _languages.contains(_language) ? _language : 'plaintext',
                    dropdownColor: const Color(0xFF1E293B),
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8), size: 18),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF93C5FD), fontWeight: FontWeight.bold),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _language = val);
                        _persist();
                      }
                    },
                    items: _languages.map((lang) {
                      return DropdownMenuItem<String>(
                        value: lang,
                        child: Text(lang),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
                // 复制按钮
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 13,
                          color: _copied ? Colors.greenAccent : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? '已复制' : '复制',
                          style: TextStyle(
                            fontSize: 11,
                            color: _copied ? Colors.greenAccent : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                  tooltip: '删除代码块',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: _deleteBlock,
                ),
              ],
            ),
          ),
          // 代码编辑区：左侧独立行号槽 + 右侧代码直接编辑区
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 左侧独立行号槽（Gutter，纯读展示，划选与复制绝不掺杂行号）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _codeFocusNode.requestFocus(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(
                      right: BorderSide(color: Color(0xFF334155), width: 1),
                    ),
                  ),
                  constraints: BoxConstraints(
                    minWidth: _lineCount >= 100 ? 40 : (_lineCount >= 10 ? 32 : 26),
                  ),
                  child: Text(
                    _lineNumbersText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['SF Mono', 'Menlo', 'Monaco', 'Courier New'],
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              // 2. 右侧代码直接编辑区
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                  child: TextField(
                    controller: _textCtrl,
                    focusNode: _codeFocusNode,
                    maxLines: null,
                    onChanged: (val) {
                      _code = val;
                      _persist();
                    },
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['SF Mono', 'Menlo', 'Monaco', 'Courier New'],
                      fontSize: 13,
                      color: Color(0xFFF1F5F9),
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '// 在此处输入代码...',
                      hintStyle: TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
