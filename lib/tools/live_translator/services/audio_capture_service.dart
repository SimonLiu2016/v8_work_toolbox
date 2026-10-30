/// 音频捕获服务
///
/// 通过 FFmpeg + avfoundation 捕获虚拟声卡设备的系统音频输出（内录），
/// 输出 16kHz 单声道 PCM 字节流（design D1）。音频全程内存处理，不落盘
/// （spec: 音频数据不落盘）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/capture_config.dart';

/// 音频捕获异常（设备不可用、FFmpeg 启动失败等）。
class AudioCaptureException implements Exception {
  AudioCaptureException(this.message);
  final String message;
  @override
  String toString() => 'AudioCaptureException: $message';
}

/// 捕获生命周期状态。
enum CaptureStatus { idle, running, paused, stopped }

/// 音频捕获服务：管理 FFmpeg 子进程与 PCM 流。
class AudioCaptureService {
  Process? _process;
  CaptureStatus _status = CaptureStatus.idle;

  /// 原始 PCM 字节流广播（每批为 FFmpeg stdout 吐出的数据）。
  final _pcmController = StreamController<Uint8List>.broadcast();

  CaptureStatus get status => _status;

  Stream<Uint8List> get pcmStream => _pcmController.stream;

  /// 枚举可用音频捕获设备。
  ///
  /// 调用 FFmpeg 列出 avfoundation 音频设备，解析出名称与索引。解析失败时
  /// 返回空列表（调用方据此提示降级）。
  static Future<List<AudioCaptureDevice>> listDevices(String ffmpegPath) async {
    try {
      final result = await Process.run(ffmpegPath, [
        '-f', 'avfoundation',
        '-list_devices', 'true',
        '-i', '',
      ]);
      // FFmpeg 把设备列表写到 stderr。
      final output = '${result.stderr}';
      return parseDeviceList(output);
    } catch (_) {
      return [];
    }
  }

  /// 解析 FFmpeg avfoundation 输出中的音频设备列表。
  ///
  /// 兼容 FFmpeg 各版本的输出格式：
  /// - 现代带前缀格式：`[AVFoundation indev @ 0x...] [0] 聚集设备`
  /// - 传统/无前缀格式：`[0] 聚集设备`
  /// 采用抗前缀行扫描解析，避免定界符截断。
  @visibleForTesting
  static List<AudioCaptureDevice> parseDeviceList(String output) {
    final devices = <AudioCaptureDevice>[];
    final lines = output.split(RegExp(r'\r?\n'));
    bool inAudioSection = false;

    // 匹配 `[0] 设备名称`，前面允许有任意日志前缀（如 `[AVFoundation indev @ 0x...] `）
    final deviceLineRe = RegExp(r'(?:\]\s+|^)\[(\d+)\]\s+(.+?)\s*$');
    final channelRe = RegExp(r'\((\d+)ch\)');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.contains('AVFoundation audio devices:')) {
        inAudioSection = true;
        continue;
      }

      if (inAudioSection) {
        if (line.contains('AVFoundation video devices:') ||
            line.startsWith('Error opening') ||
            line.contains('[in#')) {
          break;
        }

        final m = deviceLineRe.firstMatch(line);
        if (m != null) {
          final index = int.tryParse(m.group(1)!);
          if (index != null) {
            final name = m.group(2)!.trim();
            final chMatch = channelRe.firstMatch(name);
            final channels = chMatch != null ? int.parse(chMatch.group(1)!) : 1;
            devices.add(AudioCaptureDevice(
              name: name,
              channels: channels,
              deviceIndex: index,
            ));
          }
        }
      }
    }
    return devices;
  }

  /// 启动捕获。
  ///
  /// [config.deviceIndex] 为目标设备索引。设备索引无效（<0）时抛出
  /// [AudioCaptureException]。
  Future<void> start(String ffmpegPath, CaptureConfig config) async {
    if (_status == CaptureStatus.running ||
        _status == CaptureStatus.paused) {
      return;
    }
    if (config.deviceIndex < 0) {
      throw AudioCaptureException(
        '未选择有效的音频捕获设备（${config.deviceName}），请检查系统音频设置与虚拟声卡是否安装。',
      );
    }

    final isMultiChannel = config.deviceChannels > 2 ||
        RegExp(r'\b([3-9]|\d{2,})ch\b', caseSensitive: false)
            .hasMatch(config.deviceName);

    final args = <String>[
      '-f', 'avfoundation',
      '-i', ':${config.deviceIndex}',
    ];
    if (isMultiChannel) {
      args.addAll([
        '-af', 'pan=mono|c0=0.5*c0+0.5*c1',
      ]);
    }
    args.addAll([
      '-ar', '${config.sampleRate}',
      '-ac', '${config.channels}',
      '-f', 's16le',
      '-', // PCM 输出到 stdout
    ]);

    try {
      _process = await Process.start(ffmpegPath, args);
    } catch (e) {
      throw AudioCaptureException('FFmpeg 启动失败：$e');
    }

    _status = CaptureStatus.running;

    final recentStderr = <String>[];
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (recentStderr.length >= 20) {
          recentStderr.removeAt(0);
        }
        recentStderr.add(line);
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _process!.exitCode.then((code) {
      if (_status != CaptureStatus.stopped && code != 0) {
        final errText = recentStderr.isNotEmpty
            ? recentStderr.join('\n')
            : 'FFmpeg 进程异常退出 (code $code)';
        _status = CaptureStatus.stopped;
        if (!_pcmController.isClosed) {
          _pcmController.addError(AudioCaptureException(errText));
        }
      }
    });

    _process!.stdout.listen(
      (data) {
        if (_status == CaptureStatus.running) {
          _pcmController.add(Uint8List.fromList(data));
        }
      },
      onError: (Object e) {
        _pcmController.addError(
          AudioCaptureException('音频捕获流出错：$e'),
        );
      },
      onDone: () {
        if (_status == CaptureStatus.running) {
          _status = CaptureStatus.stopped;
        }
      },
      cancelOnError: false,
    );
  }

  /// 暂停：停止向下游转发数据，但不终止子进程。
  void pause() {
    if (_status == CaptureStatus.running) {
      _status = CaptureStatus.paused;
    }
  }

  /// 恢复：继续转发数据。
  void resume() {
    if (_status == CaptureStatus.paused) {
      _status = CaptureStatus.running;
    }
  }

  /// 停止：终止子进程并关闭流。
  Future<void> stop() async {
    _status = CaptureStatus.stopped;
    _process?.kill();
    await _process?.exitCode;
    _process = null;
  }

  /// 释放资源。
  Future<void> dispose() async {
    await stop();
    await _pcmController.close();
  }
}
