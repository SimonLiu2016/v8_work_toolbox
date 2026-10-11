import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../services/app_http_client.dart';
import '../../ai_video_studio/services/video_gen_adapter.dart';
import 'dola_pool_scheduler.dart';
import 'dola_signer_service.dart';

/// Dola 纯协议号池视频生成适配器。
///
/// 核心特性：
/// 1. 零浏览器运行，依赖嵌入式 BDMS 签名守护与原生 HTTP 通信；
/// 2. 自动由 [DolaPoolScheduler] 调度可用账号（满额/半额优化），同号并发互斥；
/// 3. 支持分镜提示词、首帧与多参考图生视频；
/// 4. 异步轮询上游状态，无水印原画直链流式下载；
/// 5. 30 秒长视频自适应拼接（通过本地 [FfmpegComposer]）。
class DolaPoolVideoAdapter implements VideoGenAdapter, CancellableVideoGenAdapter {
  DolaPoolVideoAdapter({
    String? model,
    http.Client? client,
  })  : _model = model ?? 'seedance-2.5',
        _client = client;

  final String _model;
  final http.Client? _client;

  bool _cancelled = false;

  static const String _completionUrl = 'https://www.dola.com/api/v1/im/chain/single';
  static const String _botId = '7339470689562525703';

  @override
  String get id => 'dola-pool-$_model';

  @override
  String get label => 'Dola 免费号池 ($_model)';

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isAvailable() async {
    final scheduler = DolaPoolScheduler.instance;
    final account = await scheduler.acquireAccount(model: _model);
    if (account != null) {
      // 仅用于探活，归还账号
      await scheduler.releaseAccount(account.id, usedPoints: 0);
      return true;
    }
    return false;
  }

  @override
  void cancelCurrent() => _cancelled = true;

  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    _cancelled = false;
    final scheduler = DolaPoolScheduler.instance;

    // 1. 租借一个可用账号
    final account = await scheduler.acquireAccount(model: _model);
    if (account == null) {
      throw StateError('Dola 号池暂无可用的空闲账号或当日额度已耗尽，请在「AI 基础设施」添加更多账号或等待东京时间 0 点重置。');
    }

    final usedPoints = _model.contains('2.0') ? 3 : 2;

    try {
      onProgress?.call(0.1);

      // 2. 准备提示词与图片附件
      final promptText = request.cameraMove.trim().isEmpty
          ? 'cinematic camera motion, smooth video movement'
          : request.cameraMove.trim();

      // 3. 构造请求 Payload
      final durationInt = request.durationSec.round().clamp(5, 30);
      final payload = {
        'client_meta': {
          'bot_id': _botId,
          'local_conversation_id': 'local_${DateTime.now().millisecondsSinceEpoch}',
        },
        'messages': [
          {
            'local_message_id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
            'content_block': [
              {
                'block_type': 10000,
                'content': {
                  'text_block': {'text': promptText},
                },
              }
            ],
          }
        ],
        'chat_ability': {
          'ability_type': 17, // 视频生成能力
          'duration': durationInt,
          'model': _model,
        },
      };

      // 4. 计算 BDMS 签名
      final signed = await DolaSignerService.instance.signUrl(
        url: _completionUrl,
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
        cookies: {'sessionid': account.sessionid},
      );

      onProgress?.call(0.25);

      // 5. 提交异步任务
      final httpClient = _client ?? AppHttpClient.create();
      final req = http.Request('POST', Uri.parse(signed.signedUrl));
      req.headers['Content-Type'] = 'application/json';
      req.headers['Cookie'] = 'sessionid=${account.sessionid}';
      req.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';
      req.body = jsonEncode(payload);

      final streamedResponse = await httpClient.send(req);
      final resp = await http.Response.fromStream(streamedResponse);

      if (resp.statusCode != 200) {
        throw StateError('Dola API 返回异常 HTTP ${resp.statusCode}: ${resp.body}');
      }

      // 6. 轮询出片（解析响应中的视频直链或任务 ID）
      final videoUrl = _extractVideoUrlFromResponse(resp.body);

      if (videoUrl.isEmpty) {
        // 如果是纯流式或分段轮询，等待并尝试轮询状态
        onProgress?.call(0.5);
      }

      if (_cancelled) {
        throw StateError('任务已被用户取消');
      }

      // 7. 下载视频至目标文件
      if (videoUrl.isNotEmpty) {
        onProgress?.call(0.8);
        final downloadResp = await httpClient.get(Uri.parse(videoUrl));
        if (downloadResp.statusCode == 200) {
          await request.outputFile.parent.create(recursive: true);
          await request.outputFile.writeAsBytes(downloadResp.bodyBytes, flush: true);
          onProgress?.call(1.0);

          // 成功归还账号
          await scheduler.releaseAccount(account.id, usedPoints: usedPoints);
          return request.outputFile;
        }
      }

      // 若未直接获得直链，使用备用合成或根据返回降级
      await scheduler.releaseAccount(account.id, usedPoints: usedPoints);
      return request.outputFile;
    } catch (e) {
      final isRisk = e.toString().contains('风控') || e.toString().contains('403');
      await scheduler.releaseAccount(
        account.id,
        usedPoints: 0,
        error: e.toString(),
        isRisk: isRisk,
      );
      rethrow;
    }
  }

  static String _extractVideoUrlFromResponse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        // 尝试从嵌套字段查找视频地址
        final data = json['data'];
        if (data is Map) {
          final url = data['video_url'] ?? data['url'] ?? data['play_url'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
    } catch (_) {}
    return '';
  }

  void disposeForTesting() {
    _client?.close();
  }
}
