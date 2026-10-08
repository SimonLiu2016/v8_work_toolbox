/// 每日 AI 威胁情报日报的调度（spec 8.5）。
///
/// 用 `cron` 而不是 `Timer.periodic`：后者按启动后的相对时间推进，Mac 休眠
/// 一段再唤醒，日报可能整天都不出。cron 按墙钟判定，唤醒后会补触发当天
/// 的时间点，日报才不会断。
library;

import 'package:cron/cron.dart' as cron_pkg;

import '../../../../services/ai_service.dart';
import '../models/security_models.dart';
import 'intel_store.dart';
import 'threat_intel_services.dart';

/// 每日情报日报调度。
class IntelDigestScheduler {
  IntelDigestScheduler._();
  static final IntelDigestScheduler instance = IntelDigestScheduler._();

  final _cron = cron_pkg.Cron();
  cron_pkg.ScheduledTask? _task;

  /// 生成者：由 UI 注入（要调 AiService，属于服务层不该依赖的东西）。
  ///
  /// 返回日报文本；抛异常时本次调度静默跳过，不影响明天的触发。
  Future<String> Function(DailyDigestInput input)? generate;

  /// 资产提供者：当前会话的资产列表。
  List<PentestAsset> Function()? currentAssets;

  bool get isRunning => _task != null;

  /// 启动每日 09:00 的日报。
  ///
  /// 本地时区（cron 默认用本地时间），所以"09:00"就是用户看到的 09:00。
  void start() {
    if (_task != null) return;
    _task = _cron.schedule(cron_pkg.Schedule.parse('0 9 * * *'), () async {
      await runOnce();
    });
  }

  void stop() {
    _task?.cancel();
    _task = null;
  }

  /// 手动跑一次（情报面板的「AI 日报」按钮走这里）。
  ///
  /// 返回日报文本；没有新数据或生成失败时返回 null。
  Future<String?> runOnce({ThreatIntelRepository? repo}) async {
    final entries = repo == null ? const <ThreatIntelEntry>[] : await repo.all();
    final last24h = entries.where(isWithin24h).toList();
    if (last24h.isEmpty) return null;

    final assets = currentAssets?.call() ?? const <PentestAsset>[];
    final matches = IntelCrossMatcher.match(assets, last24h);
    final input = DailyDigestInput(last24h: last24h, matches: matches);

    if (generate != null) {
      try {
        return await generate!(input);
      } catch (_) {
        return null;
      }
    }

    // 没注入生成者时的兜底：直接把 prompt 交给默认 AI 调用。
    try {
      final result = await AiService.instance.chat(
        messages: [
          {'role': 'system', 'content': SecuritySessionPrompt.digest},
          {'role': 'user', 'content': buildDailyDigestPrompt(input)},
        ],
      );
      return result.text;
    } catch (_) {
      return null;
    }
  }
}

/// 日报用的系统 prompt。与主分析 prompt 分开：日报要短、要结论优先。
abstract final class SecuritySessionPrompt {
  static const String digest = '''
你是一名威胁情报分析师。基于给定的漏洞情报生成中文日报，要求：
1. 500 字以内，结论优先
2. 标注哪些漏洞已在野利用（KEV）
3. 有公开 PoC 的重点提示
4. 与本地资产相关的漏洞单独列出并给出建议动作
''';
}
