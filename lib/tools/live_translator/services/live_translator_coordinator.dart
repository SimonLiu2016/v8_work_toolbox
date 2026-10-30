/// 实时翻译协调器
///
/// 主进程持有的状态中心（design D4）：串联音频捕获 → VAD 分块 → ASR → 翻译 →
/// 字幕记录，向下暴露字幕快照流供悬浮窗订阅。识别、翻译、记录全部在此，
/// 悬浮窗只是视图。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:uuid/uuid.dart';

import '../../../services/ai_config_store.dart';
import '../../../services/keychain_service.dart';
import '../models/capture_config.dart';
import '../models/caption_segment.dart';
import '../models/speaker_state.dart';
import 'audio_capture_service.dart';
import 'openrouter_asr_client.dart';
import 'stepfun_asr_client.dart';
import 'translation_service.dart';
import 'vad_chunker.dart';

/// 识别运行状态。
enum LiveStatus { idle, running, paused, error }

/// 协调器对外可见的状态快照。
class LiveState {
  LiveState({
    required this.status,
    required this.captions,
    required this.speaker,
    required this.isRecording,
    required this.translationEnabled,
    required this.targetLanguage,
    this.lastError,
    this.inputRms = 0.0,
  });

  final LiveStatus status;

  /// 最近的字幕列表（已定稿 + 当前识别中）。
  final List<CaptionSegment> captions;

  final SpeakerState speaker;

  /// 是否正在记录（用于导出）。
  final bool isRecording;

  final bool translationEnabled;

  /// 目标语言代码（zh/en/ja/ko）。
  final String targetLanguage;

  final String? lastError;

  /// 实时输入音量（RMS 能量值，0..32768）。
  final double inputRms;

  LiveState copyWith({
    LiveStatus? status,
    List<CaptionSegment>? captions,
    SpeakerState? speaker,
    bool? isRecording,
    bool? translationEnabled,
    String? targetLanguage,
    String? lastError,
    double? inputRms,
  }) {
    return LiveState(
      status: status ?? this.status,
      captions: captions ?? this.captions,
      speaker: speaker ?? this.speaker,
      isRecording: isRecording ?? this.isRecording,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      lastError: lastError ?? this.lastError,
      inputRms: inputRms ?? this.inputRms,
    );
  }
}

/// 实时翻译协调器。
class LiveTranslatorCoordinator {
  LiveTranslatorCoordinator({
    AudioCaptureService? capture,
    StepFunAsrClient? asrClient,
    TranslationService? translation,
  })  : _capture = capture ?? AudioCaptureService(),
        _translation = translation ?? TranslationService();

  final AudioCaptureService _capture;
  final TranslationService? _translation;
  LiveAsrClient? _asrClient;
  VadChunker? _chunker;

  final _uuid = const Uuid();
  final _stateController = StreamController<LiveState>.broadcast();

  LiveState _state = LiveState(
    status: LiveStatus.idle,
    captions: [],
    speaker: SpeakerState(),
    isRecording: false,
    translationEnabled: true,
    targetLanguage: 'zh',
  );

  /// 状态快照流（悬浮窗订阅）。
  Stream<LiveState> get stateStream => _stateController.stream;

  LiveState get state => _state;

  @visibleForTesting
  set stateForTesting(LiveState value) {
    _state = value;
  }

  CaptureConfig _config = CaptureConfig();
  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<AudioChunk>? _chunkSub;
  int _lastRmsEmitMs = 0;

  /// 已记录的字幕（仅在 isRecording 时累积，供导出）。
  final List<CaptionSegment> _recorded = [];

  String _language = 'zh';
  List<String> _hotwords = const [];

  void _emit() => _stateController.add(_state);

  void setConfig(CaptureConfig config) => _config = config;

  void setLanguage(String lang) => _language = lang;

  void setHotwords(List<String> words) => _hotwords = words;

  void setTranslationEnabled(bool enabled) {
    _state = _state.copyWith(translationEnabled: enabled);
    _emit();
  }

  void setTargetLanguage(String lang) {
    _state = _state.copyWith(targetLanguage: lang);
    _emit();
  }

  void setActiveSpeaker(int index) {
    _state.speaker.setActive(index);
    if (_state.captions.isNotEmpty) {
      final lastIdx = _state.captions.length - 1;
      final last = _state.captions[lastIdx];
      if (!last.isFinal) {
        final list = List<CaptionSegment>.from(_state.captions);
        list[lastIdx] = last.copyWith(speakerSlot: index);
        _state = _state.copyWith(captions: list);
      }
    }
    _emit();
  }

  void clearCaptions() {
    _state = _state.copyWith(captions: []);
    _recorded.clear();
    _emit();
  }

  void setFontSizeForUi(double _) {
    // 字号由悬浮窗本地持有，协调器不参与（spec: 字号调节作用于窗口视图）。
  }

  /// 启动捕获 + 识别。
  Future<void> start(String ffmpegPath) async {
    if (_state.status == LiveStatus.running ||
        _state.status == LiveStatus.paused) {
      return;
    }
    _asrClient = await _buildAsrClient();
    if (_asrClient == null) {
      const err =
          '未配置可用的语音识别 (STT) 供应商，请在“AI能力配置”中为 STT 槽位绑定有效的供应商与模型（支持 StepFun、OpenRouter 等）';
      _state = _state.copyWith(
        status: LiveStatus.error,
        lastError: err,
      );
      _emit();
      throw StateError(err);
    }

    _chunker = VadChunker(_config);
    _chunkSub = _chunker!.chunkStream.listen(_onChunk);

    _pcmSub = _capture.pcmStream.listen(
      (data) {
        _chunker?.addPcm(data);
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastRmsEmitMs >= 100) {
          _lastRmsEmitMs = now;
          final rms = VadChunker.computeRms(data);
          _state = _state.copyWith(inputRms: rms);
          _emit();
        }
      },
      onError: (Object err) {
        _state = _state.copyWith(
          status: LiveStatus.error,
          lastError: err.toString(),
          inputRms: 0.0,
        );
        _emit();
      },
    );

    await _capture.start(ffmpegPath, _config);
    _state = _state.copyWith(
      status: LiveStatus.running,
      lastError: null,
      inputRms: 0.0,
    );
    _emit();
  }

  Future<void> pause() async {
    _capture.pause();
    _state = _state.copyWith(status: LiveStatus.paused, inputRms: 0.0);
    _emit();
  }

  Future<void> resume() async {
    _capture.resume();
    _state = _state.copyWith(status: LiveStatus.running);
    _emit();
  }

  Future<void> stop() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    _chunker?.flush();
    await _chunkSub?.cancel();
    _chunkSub = null;
    await _capture.stop();
    _state = _state.copyWith(status: LiveStatus.idle, inputRms: 0.0);
    _emit();
  }

  void startRecording() {
    _recorded.clear();
    _state = _state.copyWith(isRecording: true);
    _emit();
  }

  void stopRecording() {
    _state = _state.copyWith(isRecording: false);
    _emit();
  }

  List<CaptionSegment> get recorded => List.unmodifiable(_recorded);

  /// 解析 StepFun ASR SSE 端点地址。
  ///
  /// 兼容官方文档中的两套路径格式：
  /// - Step Plan 专属路径：`https://api.stepfun.com/step_plan/v1/audio/asr/sse`
  /// - 开放平台常规路径：`https://api.stepfun.com/v1/audio/asr/sse`
  @visibleForTesting
  static String resolveAsrEndpoint(String baseUrl) {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/audio/asr/sse')) {
      return root;
    }
    if (root.endsWith('/v1')) {
      return '$root/audio/asr/sse';
    }
    return '$root/v1/audio/asr/sse';
  }

  Future<LiveAsrClient?> _buildAsrClient() async {
    final store = AiConfigStore.instance;
    final candidates = store.slotBindings['stt'] ?? [];
    for (final cand in candidates) {
      final provider = store.providers
          .cast<dynamic>()
          .firstWhere((p) => p?.id == cand.providerId, orElse: () => null);
      if (provider == null || provider.enabled != true) continue;
      final key =
          await KeychainService.instance.readSecret(provider.keychainKeyId);
      if (key == null || key.isEmpty) continue;

      final model = cand.model.isNotEmpty ? cand.model : null;
      final baseUrl = (provider.baseUrl as String?)?.trim() ?? '';

      // 1. StepFun 协议或 StepAudio 系列模型
      if (provider.protocol == AiProtocolType.stepfun ||
          (model != null && model.toLowerCase().contains('stepaudio'))) {
        final endpoint = resolveAsrEndpoint(baseUrl);
        return StepFunAsrClient(apiKey: key, endpoint: endpoint);
      }

      // 2. OpenRouter / OpenAI 协议，或 OpenRouter 域名 / 模型
      if (provider.protocol == AiProtocolType.openrouter ||
          provider.protocol == AiProtocolType.openai ||
          baseUrl.contains('openrouter.ai') ||
          (model != null &&
              (model.contains('qwen3-asr') ||
                  model.contains('asr') ||
                  model.contains('whisper')))) {
        final endpoint = OpenRouterAsrClient.resolveEndpoint(
          baseUrl.isNotEmpty ? baseUrl : OpenRouterAsrClient.defaultEndpoint,
        );
        return OpenRouterAsrClient(
          apiKey: key,
          endpoint: endpoint,
          defaultModel: model ?? 'qwen/qwen3-asr-0.6b',
        );
      }
    }
    return null;
  }

  Future<void> _onChunk(AudioChunk chunk) async {
    final client = _asrClient;
    if (client == null) {
      _state = _state.copyWith(
        status: LiveStatus.error,
        lastError:
            '未配置可用的语音识别 (STT) 供应商，请在“AI能力配置”中为 STT 槽位绑定有效的供应商与模型。',
      );
      _emit();
      await stop();
      return;
    }

    final speakerSlot = _state.speaker.activeIndex;
    final segId = _uuid.v4();
    var segment = CaptionSegment(
      id: segId,
      text: '',
      speakerSlot: speakerSlot,
      startMs: chunk.startMs,
      endMs: 0,
      translationStatus: _state.translationEnabled
          ? TranslationStatus.pending
          : TranslationStatus.disabled,
    );

    // 先放入识别中的占位，供增量刷新。
    _state.captions.add(segment);
    _emit();

    try {
      await for (final event in client.transcribe(
        chunk.data,
        language: _language,
        hotwords: _hotwords,
      )) {
        switch (event.type) {
          case AsrEventType.delta:
            final curSlot = _getCaptionSpeakerSlot(segment.id) ?? segment.speakerSlot;
            segment = segment.copyWith(text: event.text, speakerSlot: curSlot);
            _updateCaption(segment);
            _emit();
            break;
          case AsrEventType.done:
            final curSlot = _getCaptionSpeakerSlot(segment.id) ?? segment.speakerSlot;
            segment = segment.copyWith(
              text: event.text,
              speakerSlot: curSlot,
              isFinal: true,
              endMs: event.endMs ?? chunk.startMs + 2000,
            );
            _updateCaption(segment);
            if (_state.isRecording) _recorded.add(segment);
            _emit();
            // 定稿后触发翻译（不阻塞后续块）。
            if (_state.translationEnabled) {
              _translate(segment);
            }
            break;
          case AsrEventType.error:
            segment = segment.copyWith(
              translationStatus: TranslationStatus.failed,
            );
            _updateCaption(segment);
            _state = _state.copyWith(lastError: event.message);
            _emit();
            break;
        }
      }
    } on AsrException catch (e) {
      _state = _state.copyWith(
        status: LiveStatus.error,
        lastError: e.toString(),
      );
      _emit();
      await stop();
    }
  }

  int? _getCaptionSpeakerSlot(String id) {
    for (final c in _state.captions) {
      if (c.id == id) return c.speakerSlot;
    }
    return null;
  }

  void _updateCaption(CaptionSegment seg) {
    final idx = _state.captions.indexWhere((c) => c.id == seg.id);
    if (idx >= 0) {
      final list = List<CaptionSegment>.from(_state.captions);
      list[idx] = seg;
      _state = _state.copyWith(captions: list);
    }
  }

  Future<void> _translate(CaptionSegment seg) async {
    final svc = _translation;
    if (svc == null) return;
    try {
      final result = await svc.translate(
        text: seg.text,
        targetLang: _state.targetLanguage,
      );
      final updated = seg.copyWith(
        translation: result,
        translationStatus: TranslationStatus.done,
      );
      _updateCaption(updated);
      final recIdx = _recorded.indexWhere((c) => c.id == seg.id);
      if (recIdx >= 0) _recorded[recIdx] = updated;
      _emit();
    } catch (_) {
      // 翻译失败不阻塞原文（spec: 译文为空不阻塞）。
      final updated = seg.copyWith(translationStatus: TranslationStatus.failed);
      _updateCaption(updated);
      _emit();
    }
  }

  /// 序列化记录为 SRT（spec: subtitle-export-with-speakers）。
  String exportSrt() => _buildSubtitle(format: SubtitleFormat.srt);

  /// 序列化记录为 VTT。
  String exportVtt() => _buildSubtitle(format: SubtitleFormat.vtt);

  String _buildSubtitle({required SubtitleFormat format}) {
    final sb = StringBuffer();
    var index = 1;
    for (final seg in _recorded) {
      if (seg.text.trim().isEmpty) continue;
      final speakerName = _state.speaker.slots[seg.speakerSlot].name;
      final start = _formatTime(seg.startMs, format);
      final end = _formatTime(seg.endMs, format);
      final body = StringBuffer();
      if (format == SubtitleFormat.srt) {
        body.writeln('[$speakerName] ${seg.text}');
        if (seg.translation != null && seg.translation!.isNotEmpty) {
          body.write(seg.translation);
        }
      } else {
        body.writeln('<v $speakerName>${seg.text}');
        if (seg.translation != null && seg.translation!.isNotEmpty) {
          body.write('<v $speakerName>${seg.translation}');
        }
      }
      if (format == SubtitleFormat.vtt && index == 1) {
        sb.writeln('WEBVTT');
        sb.writeln();
      }
      sb.writeln(index);
      sb.writeln('$start --> $end');
      sb.writeln(body.toString().trimRight());
      sb.writeln();
      index++;
    }
    return sb.toString();
  }

  static String _formatTime(int ms, SubtitleFormat format) {
    final h = (ms ~/ 3600000).toString().padLeft(2, '0');
    final m = ((ms ~/ 60000) % 60).toString().padLeft(2, '0');
    final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final milli = (ms % 1000).toString().padLeft(3, '0');
    return format == SubtitleFormat.srt
        ? '$h:$m:$s,$milli'
        : '$h:$m:$s.$milli';
  }

  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}

enum SubtitleFormat { srt, vtt }
