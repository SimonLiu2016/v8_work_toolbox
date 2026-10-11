import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../services/app_http_client.dart';
import '../models/dola_account.dart';
import 'dola_account_store.dart';
import 'dola_signer_service.dart';

/// 探测结果模型。
class DolaProbeResult {
  final bool isValid;
  final int pointsLeft;
  final String? message;
  final String? rawResponse;

  const DolaProbeResult({
    required this.isValid,
    this.pointsLeft = 4,
    this.message,
    this.rawResponse,
  });
}

/// Dola 账号可用性与真实余额探活服务。
class DolaProbeService {
  DolaProbeService._();
  static final DolaProbeService instance = DolaProbeService._();

  static const String _probeEndpoint = 'https://www.dola.com/alice/user/get_web_anon_id';

  /// 探活单个账号，校验登录态有效性与提取剩余点数
  Future<DolaProbeResult> probeAccount(DolaAccount account, {http.Client? client}) async {
    if (account.sessionid.trim().isEmpty) {
      return const DolaProbeResult(isValid: false, message: 'SessionID 为空');
    }

    try {
      // 1. 获取 BDMS 签名
      final signed = await DolaSignerService.instance.signUrl(
        url: _probeEndpoint,
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: '{}',
        cookies: {'sessionid': account.sessionid},
      );

      final httpClient = client ?? AppHttpClient.create();
      final request = http.Request('POST', Uri.parse(signed.signedUrl));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Cookie'] = 'sessionid=${account.sessionid}';
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';
      request.body = '{}';

      final streamedResponse = await httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      // 上游真实协议以 x-tt-agw-login 头判断登录态 ('1' 为有效登录)
      final agwLogin = response.headers['x-tt-agw-login'];
      final isLoggedIn = agwLogin == '1';

      if (!isLoggedIn) {
        final errorMsg = '登录态已失效 (x-tt-agw-login=${agwLogin ?? "missing"})';
        await DolaAccountStore.instance.updateAccount(account.copyWith(
          status: DolaAccountStatus.risk,
          lastError: errorMsg,
        ));
        return DolaProbeResult(
          isValid: false,
          message: errorMsg,
          rawResponse: response.body,
        );
      }

      // 尝试从返回中解析今日可用额度
      var points = 4;
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) {
          final data = parsed['data'];
          if (data is Map) {
            final credits = data['credits'] ?? data['video_credits'] ?? data['remaining_credits'];
            if (credits is num) {
              points = credits.toInt().clamp(0, 4);
            }
          }
        }
      } catch (_) {}

      // 回写到 Store
      DolaAccountStatus status = DolaAccountStatus.full;
      if (points <= 1) {
        status = DolaAccountStatus.cooling;
      } else if (points < account.dailyLimit) {
        status = DolaAccountStatus.half;
      }

      await DolaAccountStore.instance.updateAccount(account.copyWith(
        points: points,
        status: status,
        lastError: null,
      ));

      return DolaProbeResult(
        isValid: true,
        pointsLeft: points,
        message: '有效，今日剩余 $points 点',
        rawResponse: response.body,
      );
    } catch (e) {
      debugPrint('[DolaProbeService] probe error: $e');
      return DolaProbeResult(isValid: false, message: e.toString());
    }
  }
}
