import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// 发音播放的**设备边界**接口。
///
/// 刻意只暴露"设备操作"（停止 / 播放文件 / 完成事件 / 释放），**不含任何编排**：
/// 顺序、超时上限、失败处理都留上层的业务代码。这样测试注入假后端时，替换掉的
/// 是**设备**而非**逻辑**——"停止 → 播放 → 等待完成（带超时上限）"这些真正会
/// 抛错的行，才会在测试里被真实执行。
///
/// 反例是曾经的 `audioPlayerFn`：它把整段播放逻辑替换掉，于是生产唯一走的分支
/// 在测试里从未被走过，崩溃既拦不住、也解释不清。
abstract class PronunciationAudioBackend {
  /// 停止当前播放（当前没有播放时也应安全返回）。
  Future<void> stop();

  /// 播放指定的本地音频文件。
  Future<void> playFile(String path);

  /// 播放完成事件流；连续磨耳朵按它决定何时步进到下一个词。
  Stream<void> get onPlayerComplete;

  /// 释放底层资源。
  Future<void> dispose();
}

/// 生产实现：对 audioplayers 的 [AudioPlayer] 做**无逻辑**包装。
///
/// 这里只做转发，不写判断。一旦在这里加逻辑，逻辑就落到了"可被测试替换"的
/// 那一侧，接缝位置等于白设。
class AudioplayersPronunciationBackend implements PronunciationAudioBackend {
  AudioplayersPronunciationBackend({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));

  @override
  Stream<void> get onPlayerComplete =>
      _player.onPlayerComplete.map<void>((_) {});

  @override
  Future<void> dispose() => _player.dispose();
}