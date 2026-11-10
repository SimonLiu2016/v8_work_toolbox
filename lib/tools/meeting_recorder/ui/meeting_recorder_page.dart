import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../services/audio_playback_speed.dart';
import '../models/recording_models.dart';
import '../services/meeting_playback_controller.dart';
import '../services/meeting_record_engine.dart';
import '../services/meeting_recorder_store.dart';
import '../services/recording_file_scanner.dart';
import 'live_waveform_meter.dart';

/// 会议录音工具主页面
class MeetingRecorderPage extends StatefulWidget {
  final MeetingRecorderStore? store;
  final MeetingRecordEngine? engine;
  final RecordingFileScanner? scanner;
  final MeetingPlaybackController? playbackController;

  const MeetingRecorderPage({
    super.key,
    this.store,
    this.engine,
    this.scanner,
    this.playbackController,
  });

  @override
  State<MeetingRecorderPage> createState() => _MeetingRecorderPageState();
}

class _MeetingRecorderPageState extends State<MeetingRecorderPage>
    with SingleTickerProviderStateMixin {
  late final MeetingRecorderStore _store;
  late final MeetingRecordEngine _engine;
  late final RecordingFileScanner _scanner;
  late final MeetingPlaybackController _playback;

  MeetingRecorderConfig _config = const MeetingRecorderConfig(outputDirectory: '');
  List<RecordingAudioDevice> _devices = [];
  RecordingAudioDevice? _selectedDevice;
  List<MeetingRecordingItem> _recordings = [];
  bool _isLoading = true;
  String? _ffmpegError;

  int _elapsedMs = 0;
  double _currentAudioLevel = 0.0;
  StreamSubscription<int>? _elapsedSub;
  StreamSubscription<MeetingRecordState>? _stateSub;
  StreamSubscription<double>? _audioLevelSub;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? MeetingRecorderStore();
    _engine = widget.engine ?? FfmpegMeetingRecordEngine();
    _scanner = widget.scanner ?? RecordingFileScanner();
    _playback = widget.playbackController ?? MeetingPlaybackController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _elapsedSub = _engine.elapsedMsStream.listen((ms) {
      if (mounted) {
        setState(() => _elapsedMs = ms);
      }
    });

    _audioLevelSub = _engine.audioLevelStream.listen((lvl) {
      if (mounted) {
        setState(() => _currentAudioLevel = lvl);
      }
    });

    _stateSub = _engine.stateStream.listen((state) {
      if (mounted) {
        if (state == MeetingRecordState.recording) {
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
        } else {
          _pulseController.stop();
          _currentAudioLevel = 0.0;
        }
        setState(() {});
        if (state == MeetingRecordState.idle) {
          _refreshRecordings();
        }
      }
    });

    _playback.addListener(_onPlaybackChanged);

    _initData();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _elapsedSub?.cancel();
    _audioLevelSub?.cancel();
    _stateSub?.cancel();
    _playback.removeListener(_onPlaybackChanged);
    if (widget.playbackController == null) {
      _playback.dispose();
    }
    if (widget.engine == null && _engine is FfmpegMeetingRecordEngine) {
      (_engine as FfmpegMeetingRecordEngine).dispose();
    }
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    _config = await _store.loadConfig();
    if (_config.playbackRate > 0) {
      await _playback.setPlaybackRate(_config.playbackRate);
    }

    await _loadDevices();
    await _refreshRecordings();

    setState(() => _isLoading = false);
  }

  Future<void> _onPlaybackRateSelected(double rate) async {
    await _playback.setPlaybackRate(rate);
    _config = _config.copyWith(playbackRate: rate);
    await _store.saveConfig(_config);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDevices() async {
    final devices = await _engine.listDevices();
    _devices = devices;
    if (devices.isEmpty) {
      _ffmpegError = '未检测到可用音频输入设备或系统中未安装 FFmpeg';
      _selectedDevice = null;
    } else {
      _ffmpegError = null;
      // 匹配上次记住的设备，默认选第一个
      _selectedDevice = devices.firstWhere(
        (d) =>
            d.id == _config.selectedDeviceId ||
            d.name == _config.selectedDeviceName,
        orElse: () => devices.first,
      );
    }
  }

  Future<void> _refreshRecordings() async {
    if (_config.outputDirectory.isNotEmpty) {
      final items = await _scanner.scanDirectory(_config.outputDirectory);
      if (mounted) {
        setState(() => _recordings = items);
      }
    }
  }

  Future<void> _selectOutputDirectory() async {
    if (_engine.state != MeetingRecordState.idle) return;

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择会议录音存放位置',
      initialDirectory: _config.outputDirectory.isNotEmpty
          ? _config.outputDirectory
          : null,
    );

    if (result != null && result.trim().isNotEmpty) {
      final updated = _config.copyWith(outputDirectory: result.trim());
      await _store.saveConfig(updated);
      setState(() => _config = updated);
      await _refreshRecordings();
    }
  }

  Future<void> _onDeviceChanged(RecordingAudioDevice? device) async {
    if (device == null || _engine.state != MeetingRecordState.idle) return;

    setState(() => _selectedDevice = device);
    final updated = _config.copyWith(
      selectedDeviceId: device.id,
      selectedDeviceName: device.name,
    );
    await _store.saveConfig(updated);
    _config = updated;
  }

  Future<void> _startRecording() async {
    if (_selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择可用的录音音频输入设备')),
      );
      return;
    }

    if (_config.outputDirectory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音存放目录未指定')),
      );
      return;
    }

    // 暂停正在播放的音频，避免回放声音录入
    await _playback.stop();

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final fileName = '会议录音_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.m4a';
    final targetPath = p.join(_config.outputDirectory, fileName);

    try {
      await _engine.start(
        deviceIndex: _selectedDevice!.id,
        outputPath: targetPath,
      );
      setState(() => _elapsedMs = 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动录音失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pauseRecording() async {
    await _engine.pause();
  }

  Future<void> _resumeRecording() async {
    await _engine.resume();
  }

  Future<void> _stopRecording() async {
    await _engine.stop();
  }

  void _revealInFinder(String filePath) {
    Process.run('open', ['-R', filePath]);
  }

  Future<void> _deleteRecording(MeetingRecordingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除录音'),
        content: Text('确定要删除文件 "${item.fileName}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_playback.isPathSelected(item.filePath)) {
        await _playback.stop();
      }
      final ok = await _scanner.deleteRecording(item.filePath);
      if (ok) {
        await _refreshRecordings();
      }
    }
  }

  Future<void> _renameRecording(MeetingRecordingItem item) async {
    final controller = TextEditingController(
      text: p.basenameWithoutExtension(item.fileName),
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名录音'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '录音名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      if (_playback.isPathSelected(item.filePath)) {
        await _playback.stop();
      }
      final updated = await _scanner.renameRecording(item.filePath, newName);
      if (updated != null) {
        await _refreshRecordings();
      }
    }
  }

  String _formatTimer(int ms) {
    final d = Duration(milliseconds: ms);
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _buildHeaderBar(theme),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConfigPanel(theme, isDark),
                  const SizedBox(height: 16),
                  _buildRecordingControlCard(theme, isDark),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _buildRecordingsList(theme, isDark),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_rounded, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 10),
          Text(
            '会议录音',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '采集开会音频 · 自定义存放 · 随时回听',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新设备与录音列表',
            onPressed: () async {
              await _loadDevices();
              await _refreshRecordings();
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPanel(ThemeData theme, bool isDark) {
    final isLocked = _engine.state != MeetingRecordState.idle;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.settings_input_component_rounded, size: 18),
                const SizedBox(width: 8),
                const Text('录音输入设备:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: _devices.isEmpty
                      ? Text(
                          _ffmpegError ?? '无可用输入设备',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<RecordingAudioDevice>(
                            isExpanded: true,
                            value: _selectedDevice,
                            items: _devices.map((d) {
                              final isVirtual = d.name.toLowerCase().contains('blackhole') ||
                                  d.name.toLowerCase().contains('soundflower') ||
                                  d.name.contains('虚拟');
                              return DropdownMenuItem(
                                value: d,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        d.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    if (isVirtual)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '内录声卡',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: theme.colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: isLocked ? null : _onDeviceChanged,
                          ),
                        ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Icon(Icons.folder_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('存放位置:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _config.outputDirectory.isNotEmpty
                        ? _config.outputDirectory
                        : '未配置',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isLocked ? null : _selectOutputDirectory,
                  icon: const Icon(Icons.drive_file_move_outline, size: 14),
                  label: const Text('更改位置', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: '在访达中打开文件夹',
                  visualDensity: VisualDensity.compact,
                  onPressed: _config.outputDirectory.isNotEmpty
                      ? () => Process.run('open', [_config.outputDirectory])
                      : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingControlCard(ThemeData theme, bool isDark) {
    final state = _engine.state;
    final isRecording = state == MeetingRecordState.recording;
    final isPaused = state == MeetingRecordState.paused;
    final isStopping = state == MeetingRecordState.stopping;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isRecording
            ? Colors.red.withValues(alpha: isDark ? 0.12 : 0.06)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRecording
              ? Colors.redAccent.withValues(alpha: 0.4)
              : theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isRecording) ...[
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(
                        alpha: 0.3 + 0.7 * _pulseController.value,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _formatTimer(_elapsedMs),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isRecording
                ? '正在录音中...'
                : (isPaused
                    ? '已暂停'
                    : (isStopping ? '正在保存音频元数据...' : '就绪')),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isRecording
                  ? Colors.redAccent
                  : (isPaused ? Colors.amber.shade700 : theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          // 宽屏全展动态声波舞台
          Container(
            width: double.infinity,
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: (isRecording ? Colors.redAccent : theme.colorScheme.surface)
                  .withValues(alpha: isDark ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isRecording ? Colors.redAccent : theme.dividerColor)
                    .withValues(alpha: isRecording ? 0.25 : 0.08),
              ),
            ),
            child: LiveWaveformMeter(
              level: _currentAudioLevel,
              isRecording: isRecording,
              height: 60.0,
              barWidth: 4.0,
              barSpacing: 4.0,
              activeColor: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state == MeetingRecordState.idle)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: _devices.isNotEmpty ? _startRecording : null,
                  icon: const Icon(Icons.fiber_manual_record_rounded, size: 18),
                  label: const Text('开始录音', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              if (isRecording) ...[
                OutlinedButton.icon(
                  onPressed: _pauseRecording,
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('暂停'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('停止并保存', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
              if (isPaused) ...[
                FilledButton.icon(
                  onPressed: _resumeRecording,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('继续录音'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('停止保存'),
                ),
              ],
              if (isStopping)
                const CircularProgressIndicator(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsList(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, size: 18),
            const SizedBox(width: 6),
            Text(
              '历史录音 (${_recordings.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _recordings.isEmpty
              ? Center(
                  child: Text(
                    '当前目录下暂无录音文件',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _recordings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _recordings[index];
                    return _buildRecordingCard(theme, isDark, item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingCard(
    ThemeData theme,
    bool isDark,
    MeetingRecordingItem item,
  ) {
    final isSelected = _playback.isPathSelected(item.filePath);
    final isPlaying = _playback.isPathPlaying(item.filePath);

    return Card(
      elevation: 0,
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.3 : 0.2)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.dividerColor.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _playback.togglePlay(
                    item.filePath,
                    fallbackDurationMs: item.durationMs,
                  ),
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fileName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.formattedSize}  •  时长: ${item.formattedDuration}  •  ${item.createdAt.toString().split('.').first}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '重命名',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _renameRecording(item),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
                IconButton(
                  tooltip: '在访达中显示',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _revealInFinder(item.filePath),
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                ),
                IconButton(
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deleteRecording(item),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 6),
              _buildInlinePlayerBar(theme, item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlinePlayerBar(ThemeData theme, MeetingRecordingItem item) {
    final pos = _playback.position;
    final total = _playback.duration.inMilliseconds > 0
        ? _playback.duration
        : Duration(milliseconds: item.durationMs);

    final posMs = pos.inMilliseconds.clamp(0, total.inMilliseconds);
    final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds : 1;

    String fmt(Duration d) {
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 44, right: 8, bottom: 4),
      child: Row(
        children: [
          Text(fmt(pos), style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 3,
              ),
              child: Slider(
                value: posMs.toDouble(),
                max: maxMs.toDouble(),
                onChanged: (val) {
                  _playback.seek(Duration(milliseconds: val.toInt()));
                },
              ),
            ),
          ),
          Text(fmt(total), style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 10),
          PopupMenuButton<double>(
            tooltip: '播放倍速',
            initialValue: _playback.playbackRate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_playback.playbackRate}x',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            onSelected: (rate) => _onPlaybackRateSelected(rate),
            itemBuilder: (ctx) => [
              for (final step in kUniversalSpeedSteps)
                PopupMenuItem(
                  value: step,
                  child: Text(step == 1.0 ? '1.0x (原速)' : '${step}x'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
