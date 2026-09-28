import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'proxy_settings.dart';

/// 应用统一 HTTP 出口。
///
/// 所有出站 HTTP 请求 SHALL 通过此客户端发出，使代理策略（见
/// [ProxySettings]）在一次实现中即可覆盖 AI 对话、语音合成、文档解析
/// 等全部模块。未配置代理时保持直连行为。
///
/// 代理配置变更后，调用方应丢弃旧实例并通过 [create] 重建。见
/// [AiService.rebuildHttpClient]。
class AppHttpClient extends http.BaseClient {
  AppHttpClient._(this._inner);

  final http.Client _inner;

  /// 按当前代理设置构造受控 HTTP 客户端。
  ///
  /// 若指定了 [toolId]，且该工具未在 [ProxySettings] 中启用代理（[isToolEnabled]
  /// 返回 false），即使全局代理已配置，也会返回直连客户端。
  ///
  /// 保留 `HttpClient` 默认的 `autoUncompress = true`，与既有裸
  /// `http.Client()` 行为一致——调用方（如 [document_parser] 用
  /// `utf8.decode(response.bodyBytes)`）依赖已解压的响应体。
  factory AppHttpClient.create({String? toolId}) {
    final proxy = ProxySettings.instance;
    if (!proxy.isConfigured) {
      return AppHttpClient._(http.Client());
    }
    if (toolId != null && !proxy.isToolEnabled(toolId)) {
      return AppHttpClient._(http.Client());
    }
    final ioClient = HttpClient()..findProxy = proxy.findProxyFor;
    return AppHttpClient._(IOClient(ioClient));
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => _inner.close();
}
