/// 脚本生成面板：模板库、AI 生成、编辑器、沙箱执行。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../services/script_generator_services.dart';
import '../services/security_session_controller.dart';
import 'widgets.dart';

class ScriptGeneratorView extends StatefulWidget {
  final SecuritySessionController controller;

  const ScriptGeneratorView({super.key, required this.controller});

  @override
  State<ScriptGeneratorView> createState() => _ScriptGeneratorViewState();
}

class _ScriptGeneratorViewState extends State<ScriptGeneratorView> {
  final _promptController = TextEditingController();
  final _codeController = TextEditingController();
  final _outputController = StreamController<ScriptRunEvent>.broadcast();

  List<ScriptTemplate> _templates = const [];
  ScriptTemplate? _selected;
  String _language = 'python';
  String _code = '';
  final List<String> _runOutput = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    widget.controller.addListener(_onControllerChanged);
    _consumeIntentIfNeeded();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _promptController.dispose();
    _codeController.dispose();
    _outputController.close();
    super.dispose();
  }

  void _onControllerChanged() {
    _consumeIntentIfNeeded();
  }

  void _consumeIntentIfNeeded() {
    final intent = widget.controller.pendingIntent;
    if (intent != null && intent.targetTab == 'script') {
      widget.controller.consumeIntent();
      if (intent.initialPrompt != null && intent.initialPrompt!.isNotEmpty) {
        _promptController.text = intent.initialPrompt!;
      } else if (intent.targetAsset != null) {
        _promptController.text = '编写针对主机 ${intent.targetAsset!.address} 的端口连通性与服务可用性安全检测脚本';
      } else if (intent.targetFinding != null) {
        _promptController.text = '编写针对漏洞【${intent.targetFinding!.title}】(${intent.targetFinding!.cveId ?? "未登记CVE"}) 的复测验证脚本';
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadTemplates() async {
    final list = await ScriptTemplateStore.instance.all();
    if (!mounted) return;
    setState(() => _templates = list);
  }

  Future<void> _generate() async {
    final description = _promptController.text.trim();
    if (description.isEmpty) return;
    widget.controller.setAiBusy(true);
    try {
      final reply = await widget.controller.askAi(
        buildScriptPrompt(
          description: description,
          language: _language,
          targetContext: widget.controller.sessionContextJson(),
        ),
      );
      if (!mounted) return;
      final extracted = extractCodeBlock(reply, language: _language);
      _codeController.text = extracted;
      setState(() => _code = extracted);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e')),
      );
    } finally {
      widget.controller.setAiBusy(false);
    }
  }

  Future<void> _run() async {
    if (_code.trim().isEmpty) return;
    setState(() {
      _running = true;
      _runOutput.clear();
    });
    final sink = <String>[];
    await ScriptSandboxService.instance.run(
      _code,
      _language,
      onEvent: (event) {
        final prefix = event.isStderr ? '[stderr] ' : '';
        setState(() => _runOutput.add(prefix + event.text));
        sink.add(prefix + event.text);
      },
    );
    if (!mounted) return;
    setState(() => _running = false);
    if (sink.isNotEmpty) {
      await widget.controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '脚本执行 ($_language)',
        detail: {'output_lines': sink.length},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = ScriptTemplateStore.groupByCategory(_templates);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '脚本生成器',
          subtitle: '自然语言 → 可执行脚本 → 沙箱运行',
          trailing: [
            SmallActionButton(
              label: _running ? '运行中…' : '运行脚本',
              icon: Icons.play_arrow_rounded,
              primary: true,
              onPressed: _running || _code.isEmpty ? null : _run,
            ),
            const SizedBox(width: AppTheme.space8),
            if (_running)
              SmallActionButton(
                label: '停止',
                icon: Icons.stop,
                onPressed: ScriptSandboxService.instance.stop,
              ),
            if (!_running && _code.isNotEmpty)
              SmallActionButton(
                label: '存为模板',
                icon: Icons.bookmark_add_outlined,
                onPressed: _saveAsTemplate,
              ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              _buildPromptCard(context),
              const SizedBox(height: AppTheme.space12),
              Text('模板库', style: context.fontTitle),
              const SizedBox(height: AppTheme.space8),
              for (final entry in grouped.entries) ...[
                Text(entry.key, style: context.fontCaption),
                const SizedBox(height: AppTheme.space6),
                Wrap(
                  spacing: AppTheme.space8,
                  runSpacing: AppTheme.space8,
                  children: [
                    for (final template in entry.value)
                      ChoiceChip(
                        label: Text('${template.name} [${template.language}]'),
                        selected: _selected?.id == template.id,
                        onSelected: (_) => setState(() {
                          _selected = template;
                          _code = template.body;
                          _codeController.text = template.body;
                          _language = template.language;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),
              ],
              Row(
                children: [
                  Text('语言', style: context.fontCaption),
                  const SizedBox(width: AppTheme.space8),
                  for (final lang in ['python', 'bash', 'ruby'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(lang),
                        selected: _language == lang,
                        onSelected: (_) => setState(() => _language = lang),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppTheme.space8),
              TextField(
                controller: _codeController,
                onChanged: (v) => _code = v,
                maxLines: 16,
                style: AppTheme.fontCaption.copyWith(
                  fontFamily: 'Menlo',
                  color: context.textSecondary,
                ),
                decoration: const InputDecoration(labelText: '脚本内容'),
              ),
              const SizedBox(height: AppTheme.space12),
              if (_runOutput.isNotEmpty) LogConsole(lines: _runOutput, height: 180),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _promptController,
            decoration: const InputDecoration(
              labelText: '描述你要脚本做什么',
              hintText: '对 192.168.1.105 的 445 端口测试 SMB 用户名枚举',
            ),
            style: context.fontBody,
            maxLines: 2,
          ),
          const SizedBox(height: AppTheme.space8),
          Row(
            children: [
              SmallActionButton(
                label: widget.controller.aiBusy ? '生成中…' : 'AI 生成脚本',
                icon: Icons.auto_awesome_rounded,
                primary: true,
                onPressed: widget.controller.aiBusy ? null : _generate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsTemplate() async {
    if (_code.trim().isEmpty) return;
    final template = ScriptTemplate(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: '自定义脚本 ${DateTime.now().millisecondsSinceEpoch % 10000}',
      category: '自定义',
      language: _language,
      body: _code,
      createdAt: DateTime.now(),
    );
    await ScriptTemplateStore.instance.save(template);
    await _loadTemplates();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存为模板')),
    );
  }
}
