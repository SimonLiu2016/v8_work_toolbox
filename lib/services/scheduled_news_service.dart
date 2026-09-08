import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ai_service.dart';
import 'mcp_service.dart';

/// 定时检索任务配置
class ScheduledNewsTask {
  final String id;
  final String title;
  final String query;
  final int intervalMinutes;
  bool enabled;
  DateTime? lastRunTime;
  String? lastBriefing;
  String? lastFingerprint;

  ScheduledNewsTask({
    required this.id,
    required this.title,
    required this.query,
    this.intervalMinutes = 60,
    this.enabled = true,
    this.lastRunTime,
    this.lastBriefing,
    this.lastFingerprint,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'query': query,
    'intervalMinutes': intervalMinutes,
    'enabled': enabled,
    'lastRunTime': lastRunTime?.toIso8601String(),
    'lastBriefing': lastBriefing,
    'lastFingerprint': lastFingerprint,
  };

  factory ScheduledNewsTask.fromJson(Map<String, dynamic> json) {
    return ScheduledNewsTask(
      id: json['id'] as String? ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? '未命名资讯任务',
      query: json['query'] as String? ?? '',
      intervalMinutes: json['intervalMinutes'] as int? ?? 60,
      enabled: json['enabled'] as bool? ?? true,
      lastRunTime: DateTime.tryParse(json['lastRunTime'] as String? ?? ''),
      lastBriefing: json['lastBriefing'] as String?,
      lastFingerprint: json['lastFingerprint'] as String?,
    );
  }
}

/// 历史资讯快报条目
class NewsBriefingItem {
  final String id;
  final String taskId;
  final String taskTitle;
  final String content;
  final DateTime timestamp;
  bool isRead;

  NewsBriefingItem({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.content,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
  };

  factory NewsBriefingItem.fromJson(Map<String, dynamic> json) {
    return NewsBriefingItem(
      id: json['id'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      taskTitle: json['taskTitle'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
    );
  }
}

/// 定时检索与资讯追踪后台服务
class ScheduledNewsService extends ChangeNotifier {
  ScheduledNewsService._();
  static final ScheduledNewsService instance = ScheduledNewsService._();

  final List<ScheduledNewsTask> _tasks = [];
  List<ScheduledNewsTask> get tasks => List.unmodifiable(_tasks);

  final List<NewsBriefingItem> _briefings = [];
  List<NewsBriefingItem> get briefings => List.unmodifiable(_briefings);

  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  Timer? _schedulerTimer;
  File? _tasksFile;
  File? _briefingsFile;
  bool _isRunningTask = false;

  Future<void> init({Directory? customRootDir}) async {
    try {
      Directory dir;
      if (customRootDir != null) {
        dir = customRootDir;
      } else {
        final home = Platform.environment['HOME'];
        if (Platform.isMacOS && home != null && home.isNotEmpty) {
          dir = Directory(p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'));
        } else {
          final appSupport = await getApplicationSupportDirectory();
          dir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
        }
      }

      if (!dir.existsSync()) dir.createSync(recursive: true);
      _tasksFile = File(p.join(dir.path, 'scheduled_news_tasks.json'));
      _briefingsFile = File(p.join(dir.path, 'scheduled_news_briefings.json'));

      await _loadData();
      _startScheduler();
    } catch (e) {
      debugPrint('初始化 ScheduledNewsService 失败: $e');
    }
  }

  void _startScheduler() {
    _schedulerTimer?.cancel();
    // 每 30 秒检查一次是否有到期任务
    _schedulerTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkDueTasks());
  }

  Future<void> _loadData() async {
    if (_tasksFile != null && await _tasksFile!.exists()) {
      try {
        final raw = jsonDecode(await _tasksFile!.readAsString()) as List<dynamic>;
        _tasks.clear();
        _tasks.addAll(raw.map((e) => ScheduledNewsTask.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('加载定时任务失败: $e');
      }
    }

    // 默认如果任务列表为空，提供一个示例任务
    if (_tasks.isEmpty) {
      _tasks.add(ScheduledNewsTask(
        id: 'task_default_ai',
        title: '每日 AI 大模型与开源资讯',
        query: 'AI 大模型 开源 最新进展',
        intervalMinutes: 120,
        enabled: true,
      ));
      await _saveTasks();
    }

    if (_briefingsFile != null && await _briefingsFile!.exists()) {
      try {
        final raw = jsonDecode(await _briefingsFile!.readAsString()) as List<dynamic>;
        _briefings.clear();
        _briefings.addAll(raw.map((e) => NewsBriefingItem.fromJson(e as Map<String, dynamic>)));
        _updateUnreadCount();
      } catch (e) {
        debugPrint('加载快报失败: $e');
      }
    }

    notifyListeners();
  }

  Future<void> _saveTasks() async {
    if (_tasksFile == null) return;
    try {
      final raw = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await _tasksFile!.writeAsString(raw);
    } catch (e) {
      debugPrint('保存定时任务失败: $e');
    }
  }

  Future<void> _saveBriefings() async {
    if (_briefingsFile == null) return;
    try {
      final raw = jsonEncode(_briefings.map((b) => b.toJson()).toList());
      await _briefingsFile!.writeAsString(raw);
    } catch (e) {
      debugPrint('保存快报失败: $e');
    }
  }

  void _updateUnreadCount() {
    final unread = _briefings.where((b) => !b.isRead).length;
    unreadCountNotifier.value = unread;
  }

  /// 标记全部已读
  Future<void> markAllAsRead() async {
    for (final b in _briefings) {
      b.isRead = true;
    }
    _updateUnreadCount();
    await _saveBriefings();
    notifyListeners();
  }

  /// 添加或更新任务
  Future<void> saveTask(ScheduledNewsTask task) async {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      _tasks[idx] = task;
    } else {
      _tasks.add(task);
    }
    await _saveTasks();
    notifyListeners();
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    await _saveTasks();
    notifyListeners();
  }

  /// 检查是否有到期任务并触发执行
  Future<void> _checkDueTasks() async {
    if (_isRunningTask) return;
    final now = DateTime.now();

    for (final task in _tasks) {
      if (!task.enabled) continue;

      bool isDue = false;
      if (task.lastRunTime == null) {
        isDue = true;
      } else {
        final diffMin = now.difference(task.lastRunTime!).inMinutes;
        if (diffMin >= task.intervalMinutes) {
          isDue = true;
        }
      }

      if (isDue) {
        await runTaskNow(task);
        break; // 一次执行一个，避免并发过大
      }
    }
  }

  /// 手动或定时执行某个任务
  Future<void> runTaskNow(ScheduledNewsTask task) async {
    if (_isRunningTask) return;
    _isRunningTask = true;
    notifyListeners();

    try {
      debugPrint('开始执行定时资讯任务: ${task.title} (query: ${task.query})');
      task.lastRunTime = DateTime.now();

      // 1. 调用 MCP 搜索工具
      final searchResult = await McpService.instance.callTool(
        'firecrawl_search',
        {
          'query': task.query,
          'limit': 3,
        },
      );

      String contentToSummarize = '';
      if (!searchResult.isError && searchResult.text.isNotEmpty) {
        contentToSummarize = searchResult.text;
      } else {
        debugPrint('MCP firecrawl_search 调用提示: ${searchResult.rawError}');
      }

      // 2. 调用 AI 生成 150 字精炼快报
      String summary = '';
      if (contentToSummarize.isNotEmpty) {
        try {
          final res = await AiService.instance.chat(
            slot: 'text',
            messages: [
              {
                'role': 'system',
                'content': '你是一个专业的信息分析师，善于从搜索结果中提炼最新要闻并保持客观准确。',
              },
              {
                'role': 'user',
                'content': '请根据以下最新检索到的原始内容，提取 2~3 条最新动态要点，总结成一段精炼的资讯快报（150字以内，附带关键来源）：\n\n$contentToSummarize',
              },
            ],
          );
          summary = res.text.trim();
        } catch (e) {
          summary = '检索到数据，但生成快报时出现异常: $e';
        }
      } else {
        summary = '未检索到新的有效动态（搜索服务暂时无返回或连接受阻）。';
      }

      task.lastBriefing = summary;

      // 3. 检查是否有新鲜资讯（与上次摘要指纹比对）
      final fingerprint = summary.hashCode.toString();
      if (task.lastFingerprint != fingerprint && contentToSummarize.isNotEmpty) {
        task.lastFingerprint = fingerprint;

        final item = NewsBriefingItem(
          id: 'brief_${DateTime.now().millisecondsSinceEpoch}',
          taskId: task.id,
          taskTitle: task.title,
          content: summary,
        );

        _briefings.insert(0, item);
        _updateUnreadCount();
        await _saveBriefings();

        // 4. 发送 macOS 系统通知
        _dispatchMacNotification(task.title, summary);
      }

      await _saveTasks();
    } catch (e) {
      debugPrint('执行资讯任务失败: $e');
    } finally {
      _isRunningTask = false;
      notifyListeners();
    }
  }

  /// 唤起 macOS 系统通知
  void _dispatchMacNotification(String title, String body) {
    if (!Platform.isMacOS) return;
    try {
      final safeTitle = title.replaceAll('"', '\\"');
      final safeBody = body.replaceAll('"', '\\"').replaceAll('\n', ' ');
      Process.run('osascript', [
        '-e',
        'display notification "$safeBody" with title "V8 资讯提醒" subtitle "$safeTitle"',
      ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }
}
