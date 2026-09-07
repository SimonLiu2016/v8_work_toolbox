import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_logger.dart';
import 'package:V8WorkToolbox/shell/ai_log_dialog.dart';

void main() {
  setUp(() {
    AiLogger.clear();
  });

  group('AiLogger In-Memory Buffer & Notification Tests', () {
    test('记录请求、响应、警告和错误日志到内存队列', () {
      expect(AiLogger.entries.isEmpty, isTrue);

      AiLogger.logRequest(
        providerName: 'openai-test',
        protocol: 'openai',
        model: 'gpt-4o',
        endpoint: 'https://api.openai.com/v1/chat/completions',
        promptSummary: 'Hello world test',
      );

      AiLogger.logResponse(
        providerName: 'openai-test',
        statusCode: 200,
        durationMs: 350,
        bodyPreview: '{"choices":[{"message":{"content":"Hello back"}}]}',
      );

      AiLogger.logWarning('Rate limit 429 warning', providerName: 'openai-test');
      AiLogger.logError('Network connection timeout', providerName: 'openai-test');

      expect(AiLogger.entries.length, equals(4));
      expect(AiLogger.entries[0].type, equals(AiLogType.request));
      expect(AiLogger.entries[0].providerName, equals('openai-test'));
      expect(AiLogger.entries[1].type, equals(AiLogType.response));
      expect(AiLogger.entries[1].statusCode, equals(200));
      expect(AiLogger.entries[2].type, equals(AiLogType.warning));
      expect(AiLogger.entries[3].type, equals(AiLogType.error));
    });

    test('超出容量时遵循 FIFO 环形淘汰', () {
      for (int i = 0; i < 210; i++) {
        AiLogger.logWarning('Message $i');
      }

      expect(AiLogger.entries.length, equals(AiLogger.maxEntries));
      // First 10 items (0..9) should have been evicted
      expect(AiLogger.entries.first.message, equals('Message 10'));
      expect(AiLogger.entries.last.message, equals('Message 209'));
    });

    test('clear() 清空内存队列并重置 ValueNotifier', () {
      AiLogger.logWarning('Test 1');
      AiLogger.logWarning('Test 2');
      expect(AiLogger.entries.length, equals(2));

      AiLogger.clear();
      expect(AiLogger.entries.isEmpty, isTrue);
      expect(AiLogger.notifier.value.isEmpty, isTrue);
    });

    test('exportAsString() 正确格式化纯文本转储', () {
      AiLogger.logRequest(
        providerName: 'mimo',
        protocol: 'anthropic',
        model: 'mimo-v2.5-pro',
        endpoint: 'https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages',
        promptSummary: 'Disk analysis prompt',
      );

      final exported = AiLogger.exportAsString();
      expect(exported, contains('[REQUEST]'));
      expect(exported, contains('Provider: mimo'));
      expect(exported, contains('Endpoint: https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages'));
      expect(exported, contains('Message: Disk analysis prompt'));
    });
  });

  group('AiLogDialog Widget Tests', () {
    testWidgets('无日志时显示空状态', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiLogDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 调用实时观察器'), findsOneWidget);
      expect(find.text('暂无 AI 调用记录'), findsOneWidget);
    });

    testWidgets('有日志时渲染卡片并支持展开与清空', (WidgetTester tester) async {
      AiLogger.logRequest(
        providerName: 'mimo',
        protocol: 'anthropic',
        model: 'mimo-v2.5-pro',
        endpoint: 'https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages',
        promptSummary: 'Brief query',
      );
      AiLogger.logResponse(
        providerName: 'mimo',
        statusCode: 200,
        durationMs: 500,
        bodyPreview: 'This is a long response body that exceeds the message length for expansion testing',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiLogDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REQUEST'), findsOneWidget);
      expect(find.text('RESP 200'), findsOneWidget);
      expect(find.text('mimo'), findsNWidgets(2));

      // Test clearing logs
      final clearButton = find.byTooltip('清空内存日志');
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('暂无 AI 调用记录'), findsOneWidget);
      expect(AiLogger.entries.isEmpty, isTrue);
    });
  });
}
