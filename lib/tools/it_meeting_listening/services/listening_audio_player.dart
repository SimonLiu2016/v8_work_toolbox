/// 播放器抽象层。
///
/// 抽这一层只有一个理由：**`audioplayers` 在 flutter test 里没有平台实现**。
/// 它的 EventChannel 名带运行期生成的 player id（`xyz.luan/audioplayers/events/<uuid>`），
/// 测试里根本无法 mock——所以 widget 测试必须能注入一个假播放器。
///
/// 生产用 [AudioPlayerListeningAdapter]（包 audioplayers 的真实实现）。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// 播放器需要提供的能力（只取本工具用到的部分）。
abstract class ListeningAudioPlayer {
  /// 播放进度流。
  Stream<Duration> get onPositionChanged;

  /// 总时长流。
  Stream<Duration> get onDurationChanged;

  /// 播放完成事件。
  Stream<void> get onPlayerComplete;

  /// 播放状态流。
  Stream<PlayerState> get onPlayerStateChanged;

  /// 播放一个本地文件。
  Future<void> playFile(String path);

  /// 暂停。
  Future<void> pause();

  /// 继续。
  Future<void> resume();

  /// 停止。
  Future<void> stop();

  /// 跳转到指定位置。
  Future<void> seek(Duration position);

  /// 设置播放速率。
  Future<void> setPlaybackRate(double rate);

  /// 释放。
  Future<void> release();
}

/// 生产实现：包 audioplayers。
class AudioPlayerListeningAdapter implements ListeningAudioPlayer {
  final AudioPlayer _player;

  AudioPlayerListeningAdapter([AudioPlayer? player])
      : _player = player ?? AudioPlayer();

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  @override
  Future<void> playFile(String path) =>
      _player.play(DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Future<void> release() => _player.dispose();
}
