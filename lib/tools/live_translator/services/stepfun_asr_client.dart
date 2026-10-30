/// StepFun ASR SSE 客户端
///
/// 按 design D3：每个音频块发起一次 SSE 请求（POST /v1/audio/asr/sse），
/// 消费该请求的 delta/done/error 事件。不做长连接（StepFun 无此能力）。
/// 端点与协议见 spec: live-asr-streaming。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'live_asr_client.dart';
export 'live_asr_client.dart';

/// StepFun ASR SSE 客户端。
class StepFunAsrClient implements LiveAsrClient {
  StepFunAsrClient({
    required this.apiKey,
    String? endpoint,
    http.Client? client,
  })  : endpoint = endpoint ?? 'https://api.stepfun.com/v1/audio/asr/sse',
        _client = client ?? http.Client();

  final String apiKey;
  final String endpoint;
  final http.Client _client;

  /// 识别一个音频块，产出 SSE 事件流。
  ///
  /// [pcm] 为 16-bit 小端单声道 PCM。[language] 语言代码（zh/en/ja/ko）。
  /// [hotwords] 自定义热词。请求完成后事件流结束。
  @override
  Stream<AsrEvent> transcribe(
    List<int> pcm, {
    String language = 'zh',
    List<String> hotwords = const [],
    bool enableTimestamp = true,
    String? model,
  }) async* {
    final targetModel =
        (model != null && model.isNotEmpty) ? model : 'stepaudio-2.5-asr';
    final b64 = base64Encode(pcm);
    final payload = {
      'audio': {
        'data': b64,
        'input': {
          'transcription': {
            'model': targetModel,
            'language': language,
            'enable_itn': true,
            'enable_timestamp': enableTimestamp,
            if (hotwords.isNotEmpty) 'hotwords': hotwords,
          },
          'format': {
            'type': 'pcm',
            'codec': 'pcm_s16le',
            'rate': 16000,
            'bits': 16,
            'channel': 1,
          },
        },
      },
    };

    final http.Request request;
    try {
      request = http.Request('POST', Uri.parse(endpoint))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(payload);
    } catch (e) {
      throw AsrException(AsrErrorKind.unknown, '构造请求失败：$e');
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw AsrException(AsrErrorKind.network, '网络错误：$e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AsrException(AsrErrorKind.auth, '鉴权失败（${response.statusCode}），请检查供应商 API Key');
    }
    if (response.statusCode == 404) {
      throw AsrException(AsrErrorKind.endpoint, '端点不可用（404），请检查供应商配置');
    }
    if (response.statusCode == 429) {
      throw AsrException(AsrErrorKind.quota, '配额不足（429）');
    }
    if (response.statusCode == 402) {
      final body = await response.stream.bytesToString();
      final isStepPlan = endpoint.contains('step_plan');
      final msg = isStepPlan
          ? 'Step Plan 额度已用尽（402）：$body'
          : '开放平台余额不足或为会员套餐（HTTP 402）。若您使用的是 Step Plan 会员套餐，请将 AI 能力配置中的 StepFun Base URL 改为 https://api.stepfun.com/step_plan/v1';
      throw AsrException(AsrErrorKind.quota, msg);
    }
    if (response.statusCode != 200) {
      // 读错误体以便归因。
      final body = await response.stream.bytesToString();
      throw AsrException(
        _classifyStatus(response.statusCode),
        'HTTP ${response.statusCode}: $body',
      );
    }

    // 解析 SSE。
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final type = json['type'] as String?;
      if (type == 'transcript.text.delta') {
        final text = (json['delta'] as String?) ?? '';
        yield AsrEvent.delta(
          text,
          startMs: (json['start_time'] as num?)?.toInt(),
          endMs: (json['end_time'] as num?)?.toInt(),
        );
      } else if (type == 'transcript.text.done') {
        final text = (json['text'] as String?) ?? '';
        yield AsrEvent.done(
          text,
          startMs: (json['start_time'] as num?)?.toInt(),
          endMs: (json['end_time'] as num?)?.toInt(),
        );
      } else if (type == 'error') {
        final msg = (json['message'] as String?) ?? '未知错误';
        yield AsrEvent.error(msg);
      }
    }
  }

  AsrErrorKind _classifyStatus(int code) {
    if (code == 401 || code == 403) return AsrErrorKind.auth;
    if (code == 404) return AsrErrorKind.endpoint;
    if (code == 429 || code == 402) return AsrErrorKind.quota;
    return AsrErrorKind.unknown;
  }

  void close() => _client.close();
}
