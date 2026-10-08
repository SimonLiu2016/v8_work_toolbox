import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/context_services_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContextServicesBridge Notification Tests', () {
    test('notificationAction method call triggers onNotificationAction callback with payload', () async {
      final bridge = ContextServicesBridge.instance;
      String? receivedType;
      Map<String, dynamic>? receivedPayload;

      bridge.onNotificationAction = (type, payload) {
        receivedType = type;
        receivedPayload = payload;
      };

      await bridge.handleMethodCallForTest(
        const MethodCall('notificationAction', {
          'actionType': 'news',
          'payload': {
            'taskId': 'task_123',
            'title': 'AI每日动态',
          },
        }),
      );

      expect(receivedType, equals('news'));
      expect(receivedPayload, isNotNull);
      expect(receivedPayload!['taskId'], equals('task_123'));
      expect(receivedPayload!['title'], equals('AI每日动态'));
    });

    test('notificationAction handles empty / malformed arguments without error', () async {
      final bridge = ContextServicesBridge.instance;
      String? receivedType;
      Map<String, dynamic>? receivedPayload;

      bridge.onNotificationAction = (type, payload) {
        receivedType = type;
        receivedPayload = payload;
      };

      await bridge.handleMethodCallForTest(
        const MethodCall('notificationAction', null),
      );

      expect(receivedType, equals(''));
      expect(receivedPayload, isEmpty);
    });

    test('showNotification invokes channel with structured parameters', () async {
      final bridge = ContextServicesBridge.instance;
      MethodCall? recordedCall;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('v8_work_toolbox/context_services'),
        (MethodCall methodCall) async {
          recordedCall = methodCall;
          return null;
        },
      );

      await bridge.showNotification(
        title: '资讯快报提醒 📰',
        subtitle: '最新科技早报',
        body: '今日科技头条速递...',
        actionType: 'news',
        payload: {'taskId': 'task_456'},
      );

      expect(recordedCall, isNotNull);
      expect(recordedCall!.method, equals('showNotification'));
      final args = Map<String, dynamic>.from(recordedCall!.arguments as Map);
      expect(args['title'], equals('资讯快报提醒 📰'));
      expect(args['subtitle'], equals('最新科技早报'));
      expect(args['body'], equals('今日科技头条速递...'));
      expect(args['actionType'], equals('news'));
      expect(args['payload'], equals({'taskId': 'task_456'}));

      // 验证兼容旧模式 (notebook)
      await bridge.showNotification(
        title: '笔记标题',
        notebook: '工作笔记',
      );
      final noteArgs = Map<String, dynamic>.from(recordedCall!.arguments as Map);
      expect(noteArgs['title'], equals('笔记标题'));
      expect(noteArgs['notebook'], equals('工作笔记'));
    });
  });
}
