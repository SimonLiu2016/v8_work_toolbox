import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/proxy_settings.dart';

void main() {
  group('ProxySettings Bypass & FindProxy Tests', () {
    final proxy = ProxySettings.instance;

    setUp(() {
      proxy.setForTesting(
        host: '127.0.0.1',
        port: 7890,
        enabled: true,
        bypassList: ['119.29.249.154', '*.internal.company.com'],
      );
    });

    test('未启用代理时一律返回 DIRECT', () {
      proxy.setForTesting(enabled: false);
      expect(proxy.findProxyFor(Uri.parse('https://google.com')), equals('DIRECT'));
      expect(proxy.findProxyFor(Uri.parse('http://119.29.249.154:3356')), equals('DIRECT'));
    });

    test('本机回环与私网地址自动绕过代理返回 DIRECT', () {
      // localhost
      expect(proxy.findProxyFor(Uri.parse('http://localhost:8080')), equals('DIRECT'));
      expect(proxy.findProxyFor(Uri.parse('http://127.0.0.1:7890')), equals('DIRECT'));
      // 10.0.0.0/8
      expect(proxy.findProxyFor(Uri.parse('http://10.1.2.3:8080')), equals('DIRECT'));
      // 172.16.0.0/12
      expect(proxy.findProxyFor(Uri.parse('http://172.20.1.1:8080')), equals('DIRECT'));
      // 192.168.0.0/16
      expect(proxy.findProxyFor(Uri.parse('http://192.168.1.100:3000')), equals('DIRECT'));
    });

    test('配置在 bypassList 中的目标 IP 或域名返回 DIRECT', () {
      // 用户的公网 NewAPI 服务器
      expect(proxy.findProxyFor(Uri.parse('http://119.29.249.154:3356/v1/chat/completions')), equals('DIRECT'));
      // 通配子域名
      expect(proxy.findProxyFor(Uri.parse('https://api.internal.company.com/v1')), equals('DIRECT'));
    });

    test('普通外网域名正常走代理 PROXY host:port', () {
      expect(proxy.findProxyFor(Uri.parse('https://www.google.com')), equals('PROXY 127.0.0.1:7890'));
      expect(proxy.findProxyFor(Uri.parse('https://api.openai.com/v1')), equals('PROXY 127.0.0.1:7890'));
      expect(proxy.findProxyFor(Uri.parse('https://cn.bing.com/search')), equals('PROXY 127.0.0.1:7890'));
    });

    test('ProxySettings 变更能够通知监听者', () {
      bool notified = false;
      void listener() {
        notified = true;
      }

      proxy.addListener(listener);
      proxy.setForTesting(enabled: false);
      expect(notified, isTrue);
      proxy.removeListener(listener);
    });
  });
}
