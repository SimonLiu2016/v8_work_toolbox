/// 实时会议翻译工具的主窗口管理/设置页。
///
/// 主窗口呈现管理与设置（spec: app-shell 常驻悬浮窗形态），识别与字幕在
/// 悬浮窗进行。本页负责：设备选择、识别语言与热词、翻译开关与目标语言、
/// 说话人命名、开始/停止识别与记录、导出。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/app_paths.dart';
import '../../../services/settings_store.dart';
import '../models/capture_config.dart';
import '../services/audio_capture_service.dart';
import '../services/live_translator_coordinator.dart';
import '../services/live_translator_host.dart';

/// 工具级持久化配置键（toolId = live-meeting-translator）。
const _kSelectedDeviceIndex = 'selectedDeviceIndex';
const _kSelectedDeviceName = 'selectedDeviceName';

/// 虚拟声卡关键词（用于预选优先级 D3）。
const _virtualDeviceKeywords = [
  'soundflower',
  'blackhole',
  '虚拟',
  'aggregate',
  '聚集',
];

/// 实时会议翻译工具页。
class LiveTranslatorPage extends StatefulWidget {
  const LiveTranslatorPage({super.key});

  @override
  State<LiveTranslatorPage> createState() => _LiveTranslatorPageState();
}

class _LiveTranslatorPageState extends State<LiveTranslatorPage> {
  final _host = LiveTranslatorHost.instance;
  late final LiveTranslatorCoordinator _coord = _host.coordinator;

  String _language = 'zh';
  String _targetLang = 'zh';
  bool _translationEnabled = true;
  final List<String> _hotwords = [];
  final _hotwordController = TextEditingController();

  List<AudioCaptureDevice> _devices = [];
  AudioCaptureDevice? _selectedDevice;
  bool _enumerating = false;
  String? _ffmpegPath;

  @override
  void initState() {
    super.initState();
    _coord.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _initDevices();
  }

  /// 首次打开：解析 ffmpeg → 读记忆 → 枚举设备 → 预选。
  Future<void> _initDevices() async {
    setState(() => _enumerating = true);
    _ffmpegPath = await _resolveFfmpeg();
    if (_ffmpegPath == null) {
      setState(() => _enumerating = false);
      return;
    }
    final devices = await AudioCaptureService.listDevices(_ffmpegPath!);
    // 读记忆（名字 + 索引）。
    int? savedIndex;
    String? savedName;
    try {
      final cfg =
          await SettingsStore.instance.readToolConfig('live-meeting-translator');
      savedIndex = (cfg[_kSelectedDeviceIndex] as num?)?.toInt();
      savedName = cfg[_kSelectedDeviceName] as String?;
    } catch (_) {}
    setState(() {
      _devices = devices;
      _enumerating = false;
      _selectedDevice = _preselect(devices, savedIndex, savedName);
    });
    _applyDeviceToConfig();
  }

  /// 预选优先级（design D3）：记忆（索引在范围内且名字匹配）> 虚拟声卡关键词 > 第一个。
  AudioCaptureDevice? _preselect(
    List<AudioCaptureDevice> devices,
    int? savedIndex,
    String? savedName,
  ) {
    if (devices.isEmpty) return null;
    if (savedIndex != null && savedName != null) {
      final match = devices.cast<AudioCaptureDevice?>().firstWhere(
            (d) => d?.deviceIndex == savedIndex && d?.name == savedName,
            orElse: () => null,
          );
      if (match != null) return match;
    }
    for (final d in devices) {
      final lower = d.name.toLowerCase();
      if (_virtualDeviceKeywords.any((k) => lower.contains(k.toLowerCase()))) {
        return d;
      }
    }
    return devices.first;
  }

  void _applyDeviceToConfig() {
    final idx = _selectedDevice?.deviceIndex ?? -1;
    _coord.setConfig(CaptureConfig(
      deviceName: _selectedDevice?.name ?? '',
      deviceIndex: idx,
      deviceChannels: _selectedDevice?.channels ?? 2,
    ));
    if (idx >= 0) _persistDevice();
  }

  Future<void> _persistDevice() async {
    final d = _selectedDevice;
    if (d == null) return;
    try {
      await SettingsStore.instance.writeToolConfig('live-meeting-translator', {
        _kSelectedDeviceIndex: d.deviceIndex,
        _kSelectedDeviceName: d.name,
      });
    } catch (_) {}
  }

  bool get _hasVirtualDevice => _devices.any((d) {
        final lower = d.name.toLowerCase();
        return _virtualDeviceKeywords.any((k) => lower.contains(k.toLowerCase()));
      });

  @override
  void dispose() {
    _hotwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _coord.state;
    final running = state.status == LiveStatus.running ||
        state.status == LiveStatus.paused;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(state, running),
          if (state.lastError != null) ...[
            const SizedBox(height: 14),
            _buildErrorBanner(state.lastError!),
          ],
          const SizedBox(height: 16),
          _buildStatusCard(state),
          const SizedBox(height: 16),
          _buildLiveCaptionStreamCard(state),
          const SizedBox(height: 16),
          _buildRecognitionSection(running),
          const SizedBox(height: 16),
          _buildTranslationSection(),
          const SizedBox(height: 16),
          _buildRecordExportSection(),
        ],
      ),
    );
  }

  Widget _buildHeader(LiveState state, bool running) {
    return Row(
      children: [
        const Icon(Icons.subtitles_outlined, size: 28),
        const SizedBox(width: 10),
        const Text('实时会议翻译',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        FilledButton.icon(
          onPressed: running
              ? _stop
              : (_selectedDevice == null ? null : _start),
          icon: Icon(running ? Icons.stop : Icons.play_arrow),
          label: Text(running ? '停止识别' : '开始识别'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _host.openCaptionWindow,
          icon: const Icon(Icons.open_in_new),
          label: const Text('打开字幕窗'),
        ),
      ],
    );
  }

  Widget _buildDevicePicker() {
    if (_enumerating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('正在枚举设备…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    if (_ffmpegPath == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('未检测到 ffmpeg，无法枚举音频设备',
            style: TextStyle(fontSize: 12, color: Colors.redAccent)),
      );
    }
    if (_devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Expanded(
              child: Text('未枚举到音频捕获设备',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            ),
            TextButton(onPressed: _initDevices, child: const Text('刷新')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedDevice?.deviceIndex.toString(),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '音频捕获设备',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final d in _devices)
                    DropdownMenuItem(
                      value: d.deviceIndex.toString(),
                      child: Text(
                        '${d.name}（${d.channels}ch）',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) {
                  final idx = int.tryParse(v ?? '');
                  if (idx == null) return;
                  final d = _devices
                      .cast<AudioCaptureDevice?>()
                      .firstWhere((e) => e?.deviceIndex == idx, orElse: () => null);
                  if (d == null) return;
                  setState(() => _selectedDevice = d);
                  _applyDeviceToConfig();
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _initDevices, child: const Text('刷新')),
          ],
        ),
        if (!_hasVirtualDevice) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '未检测到虚拟声卡。内录系统音频需要虚拟声卡（如 BlackHole 或 '
                    'Soundflower）：安装后把它设为系统输出，再回来刷新设备列表。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusCard(LiveState state) {
    final statusText = switch (state.status) {
      LiveStatus.idle => '空闲',
      LiveStatus.running => '识别中',
      LiveStatus.paused => '已暂停',
      LiveStatus.error => '出错',
    };
    final isRunning = state.status == LiveStatus.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning ? Icons.graphic_eq : Icons.info_outline,
                  color: isRunning ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 10),
                Text(
                  '状态：$statusText',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (state.status == LiveStatus.paused)
                  TextButton.icon(
                    onPressed: _coord.resume,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('恢复'),
                  )
                else if (isRunning)
                  TextButton.icon(
                    onPressed: _coord.pause,
                    icon: const Icon(Icons.pause, size: 16),
                    label: const Text('暂停'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '当前说话人：${state.speaker.active.name}'
              '${state.isRecording ? ' · 正在记录' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (isRunning) ...[
              const SizedBox(height: 10),
              _buildVuMeter(state.inputRms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVuMeter(double rms) {
    final ratio = (rms / 300.0).clamp(0.0, 1.0);
    final isVoice = rms >= 50.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isVoice
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isVoice
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_up,
                size: 16,
                color: isVoice ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                '音频输入电平: ${rms.toStringAsFixed(1)} RMS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isVoice ? Colors.green : Colors.grey,
                ),
              ),
              const Spacer(),
              Text(
                isVoice ? '● 检测到音频输入' : '○ 静音 / 等待音频',
                style: TextStyle(
                  fontSize: 11,
                  color: isVoice ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                isVoice ? Colors.green : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCaptionStreamCard(LiveState state) {
    final captions = state.captions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.subtitles, size: 18),
                const SizedBox(width: 8),
                Text(
                  '实时字幕流 (${captions.length} 条)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (captions.isNotEmpty)
                  TextButton.icon(
                    onPressed: _coord.clearCaptions,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('清空'),
                  ),
              ],
            ),
            const Divider(),
            if (captions.isEmpty)
              Container(
                height: 120,
                alignment: Alignment.center,
                child: Text(
                  state.status == LiveStatus.running
                      ? '已就绪，播放会议/网页音频即可在此处实时输出字幕...'
                      : '暂无字幕记录，点击上方「开始识别」启动流式翻译',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  reverse: true,
                  itemCount: captions.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, idx) {
                    final item = captions[captions.length - 1 - idx];
                    final speakerName =
                        state.speaker.slots[item.speakerSlot.clamp(0, 2)].name;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                speakerName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (!item.isFinal)
                              const Text(
                                '识别中…',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.orange,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          item.text,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: item.isFinal
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                        if (item.translation != null &&
                            item.translation!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          SelectableText(
                            item.translation!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecognitionSection(bool running) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('识别设置',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildDevicePicker(),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(
                labelText: '识别语言',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('中文')),
                DropdownMenuItem(value: 'en', child: Text('英语')),
                DropdownMenuItem(value: 'ja', child: Text('日语')),
                DropdownMenuItem(value: 'ko', child: Text('韩语')),
              ],
              onChanged: running
                  ? null
                  : (v) => setState(() {
                        _language = v ?? 'zh';
                        _coord.setLanguage(_language);
                      }),
            ),
            const SizedBox(height: 12),
            const Text('说话人（用热键 ⌥1/⌥2/⌥3 切换）',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextFormField(
                  initialValue: _coord.state.speaker.slots[i].name,
                  decoration: InputDecoration(
                    labelText: '说话人 ${i + 1}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      setState(() => _coord.state.speaker.slots[i].name = v),
                ),
              ),
            const SizedBox(height: 12),
            const Text('热词（提升术语识别）',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hotwordController,
                    decoration: const InputDecoration(
                      hintText: '输入术语后点添加',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    final w = _hotwordController.text.trim();
                    if (w.isNotEmpty && !_hotwords.contains(w)) {
                      setState(() {
                        _hotwords.add(w);
                        _coord.setHotwords(List.of(_hotwords));
                      });
                      _hotwordController.clear();
                    }
                  },
                  child: const Text('添加'),
                ),
              ],
            ),
            if (_hotwords.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final w in _hotwords)
                    Chip(
                      label: Text(w, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => setState(() {
                        _hotwords.remove(w);
                        _coord.setHotwords(List.of(_hotwords));
                      }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('翻译',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开启同步翻译'),
              value: _translationEnabled,
              onChanged: (v) {
                setState(() => _translationEnabled = v);
                _coord.setTranslationEnabled(v);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _targetLang,
              decoration: const InputDecoration(
                labelText: '目标语言',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('中文')),
                DropdownMenuItem(value: 'en', child: Text('英语')),
                DropdownMenuItem(value: 'ja', child: Text('日语')),
                DropdownMenuItem(value: 'ko', child: Text('韩语')),
              ],
              onChanged: (v) {
                setState(() => _targetLang = v ?? 'zh');
                _coord.setTargetLanguage(_targetLang);
              },
            ),
            const SizedBox(height: 6),
            const Text(
              '默认沿用系统「AI 能力配置」的 text 槽位；如需单独指定翻译模型，'
              '请通过工具级覆盖配置。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordExportSection() {
    final recording = _coord.state.isRecording;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('记录与导出',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: recording ? _stopRecording : _startRecording,
                  icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(recording ? '停止记录' : '开始记录'),
                ),
                OutlinedButton.icon(
                  onPressed: _coord.recorded.isEmpty ? null : () => _export('srt'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出 SRT'),
                ),
                OutlinedButton.icon(
                  onPressed: _coord.recorded.isEmpty ? null : () => _export('vtt'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出 VTT'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('已记录 ${_coord.recorded.length} 条字幕',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Future<void> _start() async {
    // 用仓库既有的 FFmpeg 路径解析逻辑。
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未检测到 ffmpeg，无法开始内录捕获')),
        );
      }
      return;
    }
    try {
      await _coord.start(ffmpeg);
    } catch (e) {
      if (mounted) {
        final message = e is StateError ? e.message : '启动失败：$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _stop() => _coord.stop();

  void _startRecording() => _coord.startRecording();
  void _stopRecording() => _coord.stopRecording();

  Future<void> _export(String format) async {
    final content =
        format == 'srt' ? _coord.exportSrt() : _coord.exportVtt();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dir = await AppPaths.liveTranslatorExportDir.create(recursive: true);
    final target = '${dir.path}/live_caption_$ts.$format';
    await File(target).writeAsString(content);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出：$target')),
      );
    }
  }

  Future<String?> _resolveFfmpeg() async {
    const candidates = [
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      'ffmpeg',
    ];
    for (final p in candidates) {
      try {
        final r = await Process.run(p, ['-version']);
        if (r.exitCode == 0) return p;
      } catch (_) {}
    }
    return null;
  }
}
