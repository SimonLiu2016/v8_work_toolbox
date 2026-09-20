import 'package:flutter/material.dart';

import '../../../components/markdown_view.dart';
import '../notebook_kb_service.dart';
import 'notebook_light_scope.dart';

/// 笔记本 AI 问答面板（阶段二）。
///
/// 提问 → 经 [NotebookKbService.ask]（FTS 检索 + LLM）→ 回答 + 可点击引用。
/// 无相关笔记时明确告知，不伪造答案。
class NotebookQaPanel extends StatefulWidget {
  const NotebookQaPanel({super.key, required this.onOpenNote});

  /// 点击引用时定位到对应笔记。
  final void Function(String noteId) onOpenNote;

  @override
  State<NotebookQaPanel> createState() => _NotebookQaPanelState();
}

class _NotebookQaPanelState extends State<NotebookQaPanel> {
  // 浅色面板调色板统一取自 [NotebookLightScope]，避免各面板各自写字面量。
  static const _titleColor = NotebookLightScope.textPrimary;
  static const _subColor = NotebookLightScope.textSecondary;
  static const _borderColor = NotebookLightScope.border;
  static const _accent = NotebookLightScope.accent;

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  /// 问答历史，最新在后。
  final List<_QaTurn> _turns = [];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    _ctrl.clear();

    setState(() {
      _busy = true;
      _turns.add(_QaTurn(question: q, pending: true));
    });
    _scrollToEnd();

    KbAnswer answer;
    try {
      answer = await NotebookKbService.instance.ask(q);
    } catch (e) {
      answer = KbAnswer.failure('出错了：$e');
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _turns.last = _QaTurn(question: q, answer: answer);
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotebookLightScope(
      child: Container(
        color: NotebookLightScope.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const Divider(height: 1, color: _borderColor),
            Expanded(
              child: _turns.isEmpty
                  ? _emptyHint()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _turns.length,
                      itemBuilder: (_, i) => _buildTurn(_turns[i]),
                    ),
            ),
            const Divider(height: 1, color: _borderColor),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 15, color: _accent),
          const SizedBox(width: 6),
          const Text(
            '问我的笔记',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _titleColor,
            ),
          ),
          const Spacer(),
          if (_turns.isNotEmpty)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 15,
                  color: _subColor,
                ),
                tooltip: '清空对话',
                onPressed: () => setState(_turns.clear),
                padding: EdgeInsets.zero,
                // 收窄默认 48px 最小点击区：面板宽由父容器写死 360，header 的
                // 横向余量必须留给将来可能新增的入口，而不是固定消耗在
                // 一个 48px 的按钮上（曾因 48px + 一段不换行的说明文字
                // 把本按钮挤出面板边界，只露出一半）。
                constraints: const BoxConstraints(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.forum_outlined, size: 40, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          const Text(
            '问点关于你笔记的事',
            style: TextStyle(fontSize: 13, color: _subColor),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '例如「豆浆机坏了怎么办」「我有哪些快到期的服务」',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _subColor.withAlpha(180)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurn(_QaTurn turn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 用户问题
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                turn.question,
                style: const TextStyle(fontSize: 12, color: _titleColor),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 回答
          if (turn.pending)
            Row(
              children: const [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                SizedBox(width: 8),
                Text(
                  '正在检索你的笔记…',
                  style: TextStyle(fontSize: 12, color: _subColor),
                ),
              ],
            )
          else if (turn.answer != null) ...[
            if (turn.answer!.error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  turn.answer!.text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              )
            else if (turn.answer!.noMatch)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      turn.answer!.text,
                      style: const TextStyle(fontSize: 12, color: _subColor),
                    ),
                    const SizedBox(height: 8),
                    // 无匹配时提议降级到联网检索
                    OutlinedButton.icon(
                      icon: const Icon(Icons.travel_explore, size: 13),
                      label: const Text(
                        '改用联网检索',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: _busy ? null : () => _askWeb(turn.question),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              )
            else
              AppMarkdownView(
                data: turn.answer!.text,
                baseStyle: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _titleColor,
                ),
                // 本面板是浅色容器：显式给浅色代码底色，避免共享组件的暗色默认值
                // 把深灰底盖在浅色画布上、与近黑文字叠在一起看不清。
                codeBlockColor: NotebookLightScope.codeSurface,
              ),
            if (turn.answer!.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: turn.answer!.citations
                    .map((c) => _citationChip(c))
                    .toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _citationChip(KbCitation c) {
    return InkWell(
      onTap: () => widget.onOpenNote(c.noteId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 11, color: _subColor),
            const SizedBox(width: 4),
            Text(c.title, style: const TextStyle(fontSize: 11, color: _accent)),
          ],
        ),
      ),
    );
  }

  /// 用户明确要求联网时，补一轮问答（问题加联网提示词）。
  Future<void> _askWeb(String question) async {
    setState(() {
      _busy = true;
      _turns.add(_QaTurn(question: '（联网）$question', pending: true));
    });
    _scrollToEnd();
    try {
      final res = await NotebookKbService.instance.askWeb(question);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _turns.last = _QaTurn(question: '（联网）$question', answer: res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _turns.last = _QaTurn(
          question: '（联网）$question',
          answer: KbAnswer.failure('联网检索失败：$e'),
        );
      });
    }
    _scrollToEnd();
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor),
              ),
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                enabled: !_busy,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(fontSize: 13, color: _titleColor),
                decoration: const InputDecoration(
                  hintText: '问关于你笔记的问题，Enter 发送…',
                  hintStyle: TextStyle(fontSize: 12, color: _subColor),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 18),
            color: _accent,
            tooltip: '发送',
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _QaTurn {
  final String question;
  final KbAnswer? answer;
  final bool pending;

  _QaTurn({required this.question, this.answer, this.pending = false});
}
