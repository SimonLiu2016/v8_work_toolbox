import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/reader_models.dart';
import '../services/audio_cache_manager.dart';
import '../services/audio_reader_controller.dart';
import '../services/document_parser.dart';
import '../services/mp3_export_service.dart';
import '../services/tts_coordinator.dart';
import '../services/tts_engine.dart';
import '../../../../services/ai_config_store.dart';
import '../../../../shell/ai_config_page.dart';

/// 文档与网页 AI 语音朗读助手页面
class DocAudioReaderPage extends StatefulWidget {
  const DocAudioReaderPage({super.key});

  @override
  State<DocAudioReaderPage> createState() => _DocAudioReaderPageState();
}

class _DocAudioReaderPageState extends State<DocAudioReaderPage> {
  late final AudioCacheManager _cacheManager;
  late final TtsSynthesisCoordinator _coordinator;
  late final AudioReaderController _controller;
  late final Mp3ExportService _exportService;
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  String _loadingMessage = '';
  double? _exportProgress;

  @override
  void initState() {
    super.initState();
    _cacheManager = AudioCacheManager();
    _coordinator = TtsSynthesisCoordinator(cacheManager: _cacheManager);
    _controller = AudioReaderController(coordinator: _coordinator);
    _exportService = Mp3ExportService(coordinator: _coordinator);

    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      if (_controller.lastErrorMessage != null) {
        final msg = _controller.lastErrorMessage!;
        _controller.clearErrorMessage();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('语音合成失败: $msg', style: const TextStyle(fontSize: 13))),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() {});
      _scrollToActiveChunk();
    }
  }

  /// 聚光灯平滑居中滚动至当前正在朗读的段落
  void _scrollToActiveChunk() {
    if (!_scrollController.hasClients) return;
    final doc = _controller.document;
    if (doc == null || doc.chunks.isEmpty) return;

    final targetIndex = _controller.currentChunkIndex;
    // 粗略估算每个段落卡片高度约 90 像素
    final targetOffset = (targetIndex * 92.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _scrollController.dispose();
    _controller.dispose();
    _coordinator.dispose();
    super.dispose();
  }

  /// 导入本地文档文件
  Future<void> _importLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'markdown', 'epub'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _isLoading = true;
          _loadingMessage = '正在解析文档内容...';
        });

        final doc = await DocumentParser.parseFile(path);
        await _controller.loadDocument(doc);
      }
    } catch (e) {
      _showErrorSnackBar('导入文档失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 导入网页文章 URL
  Future<void> _showUrlInputDialog() async {
    final textController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('输入文章网址 (URL)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持技术博客、新闻资讯、掘金、微信文章、知乎专栏等公开网页正文提取：',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'https://...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('开始提取'),
          ),
        ],
      ),
    );

    if (confirmed == true && textController.text.trim().isNotEmpty) {
      final url = textController.text.trim();
      setState(() {
        _isLoading = true;
        _loadingMessage = '正在拉取并解析网页正文...';
      });

      try {
        final doc = await DocumentParser.parseUrl(url);
        await _controller.loadDocument(doc);
      } catch (e) {
        _showErrorSnackBar('提取网页文章失败: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  /// 导出完整音频为 MP3
  Future<void> _exportFullMp3() async {
    final doc = _controller.document;
    if (doc == null || doc.chunks.isEmpty) {
      _showErrorSnackBar('请先导入要导出的文档');
      return;
    }

    final defaultFileName = '${doc.title}_朗读音频.mp3';
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出完整 MP3 朗读音频',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );

    if (targetPath == null) return;

    setState(() {
      _exportProgress = 0.0;
    });

    try {
      await _exportService.exportFullDocumentMp3(
        doc,
        targetPath,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _exportProgress = completed / total;
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('MP3 导出成功: $targetPath'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('导出 MP3 失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _exportProgress = null;
        });
      }
    }
  }

  /// 打开音色与合成配置弹窗
  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SettingsModalContent(
        initialConfig: _coordinator.config,
        onConfigChanged: (newConfig) {
          _coordinator.updateConfig(newConfig);
          setState(() {});
        },
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final doc = _controller.document;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.record_voice_over_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                '文档与网页 AI 语音朗读助手',
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _importLocalFile,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: const Text('导入文档'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _showUrlInputDialog,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('网页链接'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: doc != null ? _exportFullMp3 : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('导出 MP3'),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _showSettingsModal,
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'TTS 模态与音色设置',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_exportProgress != null)
                LinearProgressIndicator(
                  value: _exportProgress,
                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                ),
              // 主内容区域
              Expanded(
                child: doc == null
                    ? _buildEmptyState(theme, isDark)
                    : _buildReaderContent(doc, theme, isDark),
              ),
              // 底部常驻播放器控制器
              _buildBottomPlayerBar(theme, isDark),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black38,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_loadingMessage, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 空状态引导卡片
  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: Container(
        constraints: const Duration(seconds: 0) == Duration.zero
            ? const BoxConstraints(maxWidth: 580)
            : null,
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones_rounded, size: 64, color: Colors.blueAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            const Text(
              '用耳朵听文档与长文',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 PDF, Word (.docx), TXT, Markdown, EPUB 电子书与网页链接。\n利用微软 Edge 免费神经网络语音与 AI 智能切片，享受流畅自然的听读体验。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _importLocalFile,
                  icon: const Icon(Icons.file_open_rounded),
                  label: const Text('选择本地文件'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _showUrlInputDialog,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('输入网页文章链接'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 正在朗读的主界面
  Widget _buildReaderContent(ReadingDocument doc, ThemeData theme, bool isDark) {
    return Column(
      children: [
        // 顶部元数据条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            border: Border(bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              _buildSourceBadge(doc.sourceType),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  doc.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${doc.totalWordCount} 字 · 预计 ${doc.estimatedDuration.inMinutes} 分钟 · 共 ${doc.chunks.length} 段',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              if (doc.chapters.isNotEmpty) ...[
                const SizedBox(width: 16),
                _buildChapterDropdown(doc),
              ],
            ],
          ),
        ),
        // 段落列表 (支持聚光灯高亮与点击跳播)
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            itemCount: doc.chunks.length,
            itemBuilder: (ctx, idx) {
              final chunk = doc.chunks[idx];
              final isActive = idx == _controller.currentChunkIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => _controller.jumpToChunk(idx),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isActive
                          ? (isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50)
                          : (isDark ? Colors.grey.shade900 : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? Colors.blueAccent
                            : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧指示器
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 10),
                          child: _buildChunkIndicator(chunk, isActive),
                        ),
                        // 正文文本
                        Expanded(
                          child: Text(
                            chunk.text,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive
                                  ? (isDark ? Colors.blue.shade200 : Colors.blue.shade900)
                                  : (isDark ? Colors.grey.shade200 : Colors.grey.shade800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChunkIndicator(ReadingChunk chunk, bool isActive) {
    if (isActive) {
      return const Icon(Icons.volume_up_rounded, size: 18, color: Colors.blueAccent);
    }
    switch (chunk.status) {
      case ChunkSynthesisStatus.synthesizing:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ChunkSynthesisStatus.cached:
        return const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.green);
      case ChunkSynthesisStatus.error:
        return const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent);
      case ChunkSynthesisStatus.pending:
        return Text(
          '${chunk.index + 1}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        );
    }
  }

  Widget _buildSourceBadge(DocumentSourceType type) {
    Color bg;
    Color fg;
    String label;

    switch (type) {
      case DocumentSourceType.pdf:
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        label = 'PDF';
        break;
      case DocumentSourceType.docx:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'Word';
        break;
      case DocumentSourceType.epub:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'EPUB';
        break;
      case DocumentSourceType.webUrl:
        bg = Colors.teal.shade100;
        fg = Colors.teal.shade800;
        label = 'Web';
        break;
      case DocumentSourceType.markdown:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade800;
        label = 'Markdown';
        break;
      case DocumentSourceType.txt:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = 'TXT';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildChapterDropdown(ReadingDocument doc) {
    return PopupMenuButton<ReadingChapter>(
      tooltip: '章节目录',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.list_rounded, size: 16),
            SizedBox(width: 4),
            Text('章节', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      onSelected: (chap) {
        _controller.jumpToChunk(chap.startChunkIndex);
      },
      itemBuilder: (ctx) => doc.chapters.map((c) {
        return PopupMenuItem<ReadingChapter>(
          value: c,
          child: Text(c.title),
        );
      }).toList(),
    );
  }

  /// 底部全局音频播放控制条
  Widget _buildBottomPlayerBar(ThemeData theme, bool isDark) {
    final hasDoc = _controller.document != null;
    final isPlaying = _controller.isPlaying;
    final isBuffering = _controller.isBuffering;
    final currentIdx = _controller.currentChunkIndex;
    final total = _controller.document?.chunks.length ?? 0;
    final currentVoiceName = (_coordinator.config.customVoiceId != null && _coordinator.config.customVoiceId!.isNotEmpty)
        ? _coordinator.config.customVoiceId!
        : _coordinator.config.voiceId.split('-').last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 上一段
          IconButton(
            onPressed: hasDoc ? _controller.previousChunk : null,
            icon: const Icon(Icons.skip_previous_rounded, size: 24),
            tooltip: '上一段',
          ),
          // 播放 / 暂停
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blueAccent,
            ),
            child: IconButton(
              iconSize: 28,
              color: Colors.white,
              onPressed: hasDoc
                  ? () {
                      if (isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                    }
                  : null,
              icon: isBuffering
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ),
          // 下一段
          IconButton(
            onPressed: hasDoc ? _controller.nextChunk : null,
            icon: const Icon(Icons.skip_next_rounded, size: 24),
            tooltip: '下一段',
          ),
          const SizedBox(width: 12),
          // 当前进度指示
          Text(
            hasDoc ? '${currentIdx + 1} / $total 段' : '未就绪',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          // 当前音色标签
          ActionChip(
            avatar: const Icon(Icons.record_voice_over, size: 14),
            label: Text(currentVoiceName, style: const TextStyle(fontSize: 12)),
            onPressed: _showSettingsModal,
          ),
          const SizedBox(width: 16),
          // 语速倍率选择
          DropdownButton<double>(
            value: _controller.speed,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0.75, child: Text('0.75x')),
              DropdownMenuItem(value: 1.0, child: Text('1.0x')),
              DropdownMenuItem(value: 1.25, child: Text('1.25x')),
              DropdownMenuItem(value: 1.5, child: Text('1.5x')),
              DropdownMenuItem(value: 2.0, child: Text('2.0x')),
            ],
            onChanged: (val) {
              if (val != null) _controller.setSpeed(val);
            },
          ),
          const SizedBox(width: 16),
          // 音量滑块
          const Icon(Icons.volume_up_rounded, size: 18, color: Colors.grey),
          SizedBox(
            width: 90,
            child: Slider(
              value: _controller.volume,
              min: 0.0,
              max: 1.0,
              onChanged: _controller.setVolume,
            ),
          ),
        ],
      ),
    );
  }
}

/// TTS 模态与音色选择配置 Sheet
class _SettingsModalContent extends StatefulWidget {
  final TtsSynthesisConfig initialConfig;
  final ValueChanged<TtsSynthesisConfig> onConfigChanged;

  const _SettingsModalContent({
    required this.initialConfig,
    required this.onConfigChanged,
  });

  @override
  State<_SettingsModalContent> createState() => _SettingsModalContentState();
}

class _SettingsModalContentState extends State<_SettingsModalContent> {
  late TtsMode _selectedMode;
  late String _selectedVoiceId;
  late bool _useSystemAiConfig;
  String? _selectedSystemProviderId;
  late TextEditingController _customVoiceController;
  late TextEditingController _endpointController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialConfig.mode;
    _selectedVoiceId = widget.initialConfig.voiceId;
    _useSystemAiConfig = widget.initialConfig.useSystemAiConfig;
    _selectedSystemProviderId = widget.initialConfig.systemProviderId;
    _customVoiceController = TextEditingController(text: widget.initialConfig.customVoiceId ?? '');
    _endpointController = TextEditingController(text: widget.initialConfig.customEndpoint ?? '');
    _apiKeyController = TextEditingController(text: widget.initialConfig.customApiKey ?? '');
    _modelController = TextEditingController(text: widget.initialConfig.customModel ?? 'tts-1');
  }

  @override
  void dispose() {
    _customVoiceController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _save(String effectiveVoiceId) {
    final newConfig = widget.initialConfig.copyWith(
      mode: _selectedMode,
      voiceId: effectiveVoiceId,
      useSystemAiConfig: _useSystemAiConfig,
      systemProviderId: _selectedSystemProviderId,
      customVoiceId: _customVoiceController.text.trim().isEmpty ? null : _customVoiceController.text.trim(),
      customEndpoint: _endpointController.text.trim().isEmpty ? null : _endpointController.text.trim(),
      customApiKey: _apiKeyController.text.trim().isEmpty ? null : _apiKeyController.text.trim(),
      customModel: _modelController.text.trim().isEmpty ? 'tts-1' : _modelController.text.trim(),
    );
    widget.onConfigChanged(newConfig);
    Navigator.of(context).pop();
  }

  Future<void> _openAiConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (navCtx) => Scaffold(
          appBar: AppBar(
            title: const Text('AI 基础设施配置'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(navCtx).pop(),
            ),
          ),
          body: const AiConfigPage(),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  List<TtsVoiceOption> _getVoicesForMode(
    TtsMode mode, {
    required bool useSystemAi,
    AiProviderConfig? activeProvider,
    String? activeModel,
    String? customEndpoint,
    String? customModel,
  }) {
    switch (mode) {
      case TtsMode.edge:
        return TtsVoiceOption.defaultEdgeVoices;
      case TtsMode.customAi:
        final model = useSystemAi ? (activeModel ?? '') : (customModel ?? '');
        final endpoint = useSystemAi ? (activeProvider?.baseUrl ?? '') : (customEndpoint ?? '');
        final providerName = useSystemAi ? activeProvider?.name : null;

        final isMimo = OpenAiTtsEngine.isMimoModel(
          model,
          baseUrl: endpoint,
          providerName: providerName,
        );

        if (isMimo) {
          return TtsVoiceOption.defaultMimoVoices;
        }
        return TtsVoiceOption.defaultOpenAiVoices;
      case TtsMode.macosNative:
        return TtsVoiceOption.defaultMacOsVoices;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final store = AiConfigStore.instance;
    final allProviders = store.providers.where((p) => p.enabled).toList();

    // 动态确定当前绑定的系统 AI 供应商
    AiProviderConfig? activeProvider;

    if (_selectedSystemProviderId != null && _selectedSystemProviderId!.isNotEmpty) {
      activeProvider = allProviders.cast<AiProviderConfig?>().firstWhere(
        (p) => p?.id == _selectedSystemProviderId,
        orElse: () => null,
      );
    }

    if (activeProvider == null) {
      final candidates = store.slotBindings['tts'] ?? [];
      for (final cand in candidates) {
        final matched = allProviders.cast<AiProviderConfig?>().firstWhere(
          (p) => p?.id == cand.providerId,
          orElse: () => null,
        );
        if (matched != null) {
          activeProvider = matched;
          break;
        }
      }
    }

    if (activeProvider == null) {
      activeProvider = allProviders.cast<AiProviderConfig?>().firstWhere(
        (p) => p != null && (p.protocol == AiProtocolType.openai || p.ttsModels.isNotEmpty),
        orElse: () => null,
      );
    }

    final activeModel = OpenAiTtsEngine.resolveSystemModel(
      provider: activeProvider,
      configuredModel: _modelController.text.trim(),
      store: store,
    );

    final voices = _getVoicesForMode(
      _selectedMode,
      useSystemAi: _useSystemAiConfig,
      activeProvider: activeProvider,
      activeModel: activeModel,
      customEndpoint: _endpointController.text.trim(),
      customModel: _modelController.text.trim(),
    );

    final voiceIds = voices.map((v) => v.id).toSet();
    final effectiveSelectedVoiceId = voiceIds.contains(_selectedVoiceId)
        ? _selectedVoiceId
        : (voices.isNotEmpty ? voices.first.id : _selectedVoiceId);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TTS 语音合成与音色配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 16),
            const Text('合成引擎模态：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<TtsMode>(
              segments: const [
                ButtonSegment(value: TtsMode.edge, label: Text('Edge-TTS 免密')),
                ButtonSegment(value: TtsMode.customAi, label: Text('商用 AI TTS')),
                ButtonSegment(value: TtsMode.macosNative, label: Text('macOS 离线')),
              ],
              selected: {_selectedMode},
              onSelectionChanged: (set) {
                setState(() {
                  _selectedMode = set.first;
                  final newVoices = _getVoicesForMode(
                    _selectedMode,
                    useSystemAi: _useSystemAiConfig,
                    activeProvider: activeProvider,
                    activeModel: activeModel,
                    customEndpoint: _endpointController.text.trim(),
                    customModel: _modelController.text.trim(),
                  );
                  _selectedVoiceId = newVoices.first.id;
                });
              },
            ),
            const SizedBox(height: 20),
            if (_selectedMode == TtsMode.customAi) ...[
              const Text('商用 AI 配置来源：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('跟随系统 AI 配置 (推荐)'),
                    icon: Icon(Icons.hub_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('自定义独立配置'),
                    icon: Icon(Icons.edit_note_rounded, size: 16),
                  ),
                ],
                selected: {_useSystemAiConfig},
                onSelectionChanged: (set) {
                  setState(() {
                    _useSystemAiConfig = set.first;
                  });
                },
              ),
              const SizedBox(height: 14),
              if (_useSystemAiConfig) ...[
                if (allProviders.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade700.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '系统尚未配置 AI 供应商。请点击右侧按钮前往添加。',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: _openAiConfig,
                          child: const Text('前往配置 ↗'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.blue.shade50.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                activeProvider != null
                                    ? '当前绑定供应商：${activeProvider.name}'
                                    : '未找到可用的 OpenAI 兼容供应商',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: _openAiConfig,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('管理 AI 配置 ↗', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        if (activeProvider != null) ...[
                          const SizedBox(height: 6),
                          Text('• 服务地址：${activeProvider.baseUrl}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('• 预设模型：$activeModel', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const Text('• 安全密钥：●●●●●●●● (已安全托管于 macOS Keychain)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('指定供应商：', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedSystemProviderId,
                          isDense: true,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('跟随系统默认 TTS 槽位绑定', overflow: TextOverflow.ellipsis),
                            ),
                            ...allProviders.map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.name} (${p.baseUrl})', overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedSystemProviderId = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
              ] else ...[
                TextField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    labelText: 'API Endpoint (OpenAI 兼容地址)',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: '模型名称 (Model)',
                    hintText: 'tts-1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
            const Text('选择朗读音色：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...voices.map((v) {
              return RadioListTile<String>(
                value: v.id,
                groupValue: effectiveSelectedVoiceId,
                title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(v.description ?? v.language),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedVoiceId = val;
                    });
                  }
                },
              );
            }),
            if (_selectedMode == TtsMode.customAi) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customVoiceController,
                decoration: const InputDecoration(
                  labelText: '自定义音色 ID (可选)',
                  hintText: '例如 fishaudio-voice-1，若填写将优先于上方预设音色',
                  prefixIcon: Icon(Icons.record_voice_over_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _save(effectiveSelectedVoiceId),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存配置', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
