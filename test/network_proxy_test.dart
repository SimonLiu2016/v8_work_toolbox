import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_http_client.dart';
import 'package:V8WorkToolbox/services/proxy_settings.dart';
import 'package:V8WorkToolbox/tools/network_proxy/services/clash_subscription_parser.dart';
import 'package:V8WorkToolbox/tools/tool_definition.dart';

void main() {
  group('ClashSubscriptionParser', () {
    test('正确解析包含多协议节点的 Clash YAML', () {
      const yaml = '''
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
proxies:
  - name: "香港 01 [BGP]"
    type: vmess
    server: hk.example.com
    port: 443
    uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    alterId: 0
    cipher: auto
    tls: true
  - name: "日本 02 [Trojan]"
    type: trojan
    server: jp.example.com
    port: 443
    password: "mypassword"
    sni: jp.example.com
  - name: "美国 03 [SS]"
    type: ss
    server: us.example.com
    port: 8388
    cipher: aes-256-gcm
    password: "sspassword"
  - name: "香港 04 [VLESS]"
    type: vless
    server: vless.example.com
    port: 443
    uuid: "4d519957-915e-47d3-a906-74df3a0c340e"
    network: ws
    ws-opts:
      path: /ws-path
      headers:
        Host: vless.example.com
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "香港 01 [BGP]"
      - "日本 02 [Trojan]"
      - "美国 03 [SS]"
rules:
  - MATCH,PROXY
''';

      final nodes = ClashSubscriptionParser.parse(yaml);
      expect(nodes.length, 4);

      expect(nodes[0].name, '香港 01 [BGP]');
      expect(nodes[0].type, 'vmess');
      expect(nodes[0].rawConfig['server'], 'hk.example.com');
      expect(nodes[0].rawConfig['port'], 443);

      expect(nodes[1].name, '日本 02 [Trojan]');
      expect(nodes[1].type, 'trojan');
      expect(nodes[1].rawConfig['password'], 'mypassword');

      expect(nodes[2].name, '美国 03 [SS]');
      expect(nodes[2].type, 'ss');

      expect(nodes[3].name, '香港 04 [VLESS]');
      expect(nodes[3].type, 'vless');
      expect(nodes[3].rawConfig['ws-opts'], isA<Map>());
    });

    test('内容为空时抛出 ClashParseException', () {
      expect(
        () => ClashSubscriptionParser.parse('   '),
        throwsA(isA<ClashParseException>()),
      );
    });

    test('缺少 proxies 字段时抛出 ClashParseException', () {
      const yaml = '''
port: 7890
mode: rule
rules:
  - MATCH,DIRECT
''';
      expect(
        () => ClashSubscriptionParser.parse(yaml),
        throwsA(isA<ClashParseException>()),
      );
    });

    test('proxies 列表为空时抛出 ClashParseException', () {
      const yaml = '''
port: 7890
proxies: []
rules:
  - MATCH,DIRECT
''';
      expect(
        () => ClashSubscriptionParser.parse(yaml),
        throwsA(isA<ClashParseException>()),
      );
    });
  });

  group('ProxySettings per-tool 开关', () {
    final proxy = ProxySettings.instance;

    setUp(() {
      proxy.setForTesting(
        host: '127.0.0.1',
        port: 7890,
        enabled: true,
        perToolEnabled: {kToolIdAiAssistant: true, kToolIdDocAudioReader: false},
      );
    });

    test('正确读取工具开关状态，未设置时默认 false', () {
      expect(proxy.isToolEnabled(kToolIdAiAssistant), isTrue);
      expect(proxy.isToolEnabled(kToolIdDocAudioReader), isFalse);
      expect(proxy.isToolEnabled('unknown-tool'), isFalse);
    });

    test('AppHttpClient 根据 toolId 返回直连或代理客户端', () {
      // 全局配置且已开启
      expect(proxy.isConfigured, isTrue);

      // doc-audio-reader 关：直连客户端
      final readerClient = AppHttpClient.create(toolId: kToolIdDocAudioReader);
      // 客户端创建无抛错
      expect(readerClient, isNotNull);

      // ai-assistant 开：代理客户端
      final aiClient = AppHttpClient.create(toolId: kToolIdAiAssistant);
      expect(aiClient, isNotNull);

      readerClient.close();
      aiClient.close();
    });
  });
}
