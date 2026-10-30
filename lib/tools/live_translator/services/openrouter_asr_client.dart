/// OpenRouter ASR 客户端
///
/// 将 16kHz 16-bit 单声道 PCM 音频切片在内存中封装为合法的 WAV 字节流，
/// 遵循 OpenRouter 规范（POST /api/v1/audio/transcriptions）发起 STT 语音识别。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'live_asr_client.dart';

/// OpenRouter ASR 客户端。
class OpenRouterAsrClient implements LiveAsrClient {
  OpenRouterAsrClient({
    required this.apiKey,
    String? endpoint,
    String? defaultModel,
    http.Client? client,
  })  : endpoint = endpoint ?? defaultEndpoint,
        defaultModel = defaultModel ?? 'qwen/qwen3-asr-0.6b',
        _client = client ?? http.Client();

  static const String defaultEndpoint =
      'https://openrouter.ai/api/v1/audio/transcriptions';

  final String apiKey;
  final String endpoint;
  final String defaultModel;
  final http.Client _client;

  /// 自适应解析 OpenRouter ASR 端点。
  static String resolveEndpoint(String baseUrl) {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/audio/transcriptions')) {
      return root;
    }
    if (root.endsWith('/v1')) {
      return '$root/audio/transcriptions';
    }
    return '$root/v1/audio/transcriptions';
  }

  /// 将 16kHz 16-bit 单声道 PCM 裸流打包为规范的 44 字节 RIFF/WAV 格式。
  @visibleForTesting
  static Uint8List pcmToWav(
    List<int> pcm, {
    int sampleRate = 16000,
    int numChannels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final totalDataLen = pcm.length;
    final totalAudioLen = totalDataLen + 36;

    final header = ByteData(44);
    // RIFF 块标志
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, totalAudioLen, Endian.little);

    // WAVE 格式标志
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt 子块
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // SubChunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data 子块
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, totalDataLen, Endian.little);

    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + pcm.length, pcm);
    return wav;
  }

  @override
  Stream<AsrEvent> transcribe(
    List<int> pcm, {
    String language = 'zh',
    List<String> hotwords = const [],
    bool enableTimestamp = true,
    String? model,
  }) async* {
    if (pcm.isEmpty) return;

    final wav = pcmToWav(pcm);
    final base64Audio = base64Encode(wav);
    final targetModel = model ?? defaultModel;

    final bodyPayload = jsonEncode({
      'model': targetModel,
      'input_audio': {
        'data': base64Audio,
        'format': 'wav',
      },
    });

    final uri = Uri.parse(endpoint);
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

    try {
      final response = await _client
          .post(uri, headers: headers, body: bodyPayload)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final text = (decoded['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) {
          yield AsrEvent.done(text);
        }
        return;
      }

      final errorBody = utf8.decode(response.bodyBytes);
      String detailMsg = errorBody;
      try {
        final errJson = jsonDecode(errorBody);
        if (errJson is Map && errJson['error'] != null) {
          final errObj = errJson['error'];
          if (errObj is Map) {
            detailMsg = errObj['message']?.toString() ?? errorBody;
          } else {
            detailMsg = errObj.toString();
          }
        }
      } catch (_) {}

      switch (response.statusCode) {
        case 401:
          throw AsrException(
            AsrErrorKind.auth,
            'OpenRouter API Key 无效或未授权: $detailMsg',
          );
        case 402:
          throw AsrException(
            AsrErrorKind.quota,
            'OpenRouter 账户余额或配额不足: $detailMsg',
          );
        default:
          throw AsrException(
            AsrErrorKind.unknown,
            'OpenRouter ASR 错误 (${response.statusCode}): $detailMsg',
          );
      }
    } on SocketException catch (e) {
      throw AsrException(AsrErrorKind.network, '网络连接失败: ${e.message}');
    } on TimeoutException {
      throw AsrException(AsrErrorKind.network, 'OpenRouter 语音识别请求超时');
    } on http.ClientException catch (e) {
      throw AsrException(AsrErrorKind.network, 'HTTP 客户端异常: ${e.message}');
    }
  }
}
