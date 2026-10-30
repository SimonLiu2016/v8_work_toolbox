/// IT 会议听力的全局热键。
///
/// 热键必须在**任意前台应用**中生效——用户正在 IDE 里跑测试时，手不离开键盘
/// 就能暂停/切段（spec「全局热键控制播放」）。macOS 上这必须走 Carbon 的
/// `RegisterEventHotKey`，Dart 侧没有等价能力。
///
/// 原生侧的实现见 `macos/Runner/AppDelegate.swift`：
/// - `registerListeningHotKeys` —— 批量注册，回传失败的键名
/// - `handleListeningHotKey` —— 热键按下时回调 Dart
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/settings_store.dart';

/// 播放控制动作。
class ListeningHotKeyAction {
  /// 播放/暂停切换。
  static const String toggle = 'toggle';

  /// 上一段。
  static const String previous = 'previous';

  /// 下一段。
  static const String next = 'next';

  /// 减速一档。
  static const String slower = 'slower';

  /// 加速一档。
  static const String faster = 'faster';

  /// 全部动作（注册顺序即原生侧的 id 顺序）。
  static const List<String> all = [toggle, previous, next, slower, faster];
}

/// 一个热键绑定。
class ListeningHotKeyBinding {
  /// 动作名（[ListeningHotKeyAction] 之一）。
  final String action;

  /// Carbon modifiers：optionKey=2048, controlKey=4096, cmdKey=256, shiftKey=512。
  final int modifiers;

  /// macOS 虚拟键码。
  final int keyCode;

  /// 展示用标签。
  final String label;

  const ListeningHotKeyBinding({
    required this.action,
    required this.modifiers,
    required this.keyCode,
    required this.label,
  });

  Map<String, dynamic> toMap() => {
        'name': action,
        'modifiers': modifiers,
        'keyCode': keyCode,
        'label': label,
      };
}

/// 全局热键管理。
class ListeningHotKeyService {
  ListeningHotKeyService._();
  static final ListeningHotKeyService instance = ListeningHotKeyService._();

  static const MethodChannel _channel =
      MethodChannel('v8_work_toolbox/it_listening');

  /// Carbon modifier 常量。
  static const int optionKey = 2048;
  static const int controlKey = 4096;
  static const int cmdKey = 256;
  static const int shiftKey = 512;

  /// 默认绑定。
  ///
  /// 全部用 ⌃⌥ 组合：避开既有的 ⌥Space / ⌥D / ⌥S（查词与存笔记），
  /// 也避开编辑器里最常用的 ⌘ 组合。
  static const List<ListeningHotKeyBinding> defaultBindings = [
    ListeningHotKeyBinding(
      action: ListeningHotKeyAction.toggle,
      modifiers: controlKey | optionKey,
      keyCode: 49, // Space
      label: '⌃⌥Space',
    ),
    ListeningHotKeyBinding(
      action: ListeningHotKeyAction.previous,
      modifiers: controlKey | optionKey,
      keyCode: 46, // C
      label: '⌃⌥C',
    ),
    ListeningHotKeyBinding(
      action: ListeningHotKeyAction.next,
      modifiers: controlKey | optionKey,
      keyCode: 45, // B
      label: '⌃⌥B',
    ),
    ListeningHotKeyBinding(
      action: ListeningHotKeyAction.slower,
      modifiers: controlKey | optionKey,
      keyCode: 21, // 1
      label: '⌃⌥1',
    ),
    ListeningHotKeyBinding(
      action: ListeningHotKeyAction.faster,
      modifiers: controlKey | optionKey,
      keyCode: 20, // 0
      label: '⌃⌥0',
    ),
  ];

  /// 热键按下时的回调（原生侧调用）。
  void Function(String action)? onAction;

  /// 注册热键。
  ///
  /// 返回**注册失败**的绑定列表。失败意味着该键被系统或其他应用占用——
  /// 调用方必须给出提示，不能静默失效（spec「热键冲突时给出反馈」）。
  Future<List<ListeningHotKeyBinding>> register(
      List<ListeningHotKeyBinding> bindings) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'registerListeningHotKeys',
        {'bindings': bindings.map((b) => b.toMap()).toList()},
      );
      final failures = (res?['failures'] as List?) ?? const [];
      final failedActions =
          failures.map((e) => (e as Map)['name'] as String? ?? '').toSet();
      return bindings
          .where((b) => failedActions.contains(b.action))
          .toList();
    } catch (e) {
      debugPrint('[ListeningHotKey] 注册失败: $e');
      return bindings;
    }
  }

  /// 注销全部热键。
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod('unregisterListeningHotKeys');
    } catch (e) {
      debugPrint('[ListeningHotKey] 注销失败: $e');
    }
  }

  /// 从持久化配置读取绑定。
  ///
  /// 读不到（首次运行 / 配置损坏）时回落到默认绑定。存的是裸 map，
  /// 这里转回绑定对象；动作名对不上的条目直接丢弃（配置被手改过）。
  List<ListeningHotKeyBinding> loadBindings() {
    final saved = SettingsStore.instance.getListeningHotKeyBindings();
    if (saved.isEmpty) return defaultBindings;
    final byAction = <String, ListeningHotKeyBinding>{};
    for (final m in saved) {
      final action = m['name'] as String? ?? '';
      final modifiers = (m['modifiers'] as num?)?.toInt();
      final keyCode = (m['keyCode'] as num?)?.toInt();
      if (action.isEmpty || modifiers == null || keyCode == null) continue;
      byAction[action] = ListeningHotKeyBinding(
        action: action,
        modifiers: modifiers,
        keyCode: keyCode,
        label: _labelFor(action, modifiers, keyCode),
      );
    }
    // 逐个与默认绑定对齐：动作必须一一对应，缺哪个补哪个。
    final out = <ListeningHotKeyBinding>[];
    for (final d in defaultBindings) {
      out.add(byAction[d.action] ?? d);
    }
    return out;
  }

  /// 持久化绑定。
  Future<void> saveBindings(List<ListeningHotKeyBinding> bindings) async {
    await SettingsStore.instance.setListeningHotKeyBindings(
      bindings.map((b) => b.toMap()).toList(),
    );
  }

  /// 由键位生成展示标签。
  static String _labelFor(String action, int modifiers, int keyCode) {
    final parts = <String>[];
    if (modifiers & cmdKey != 0) parts.add('⌘');
    if (modifiers & controlKey != 0) parts.add('⌃');
    if (modifiers & optionKey != 0) parts.add('⌥');
    if (modifiers & shiftKey != 0) parts.add('⇧');
    parts.add(_keyName(keyCode));
    return parts.join();
  }

  /// 常用键位的中文名。
  static String _keyName(int keyCode) {
    const names = <int, String>{
      0: 'A', 1: 'S', 2: 'D', 3: 'F', 4: 'H', 5: 'G', 6: 'Z', 7: 'X',
      8: 'C', 9: 'V', 11: 'B', 12: 'Q', 13: 'W', 14: 'E', 15: 'R',
      16: 'Y', 17: 'T', 18: '1', 19: '2', 20: '3', 21: '4', 22: '6',
      23: '5', 24: '=', 25: '9', 26: '7', 27: '-', 28: '8', 29: '0',
      30: ']', 31: 'O', 32: 'U', 33: '[', 34: 'I', 35: 'P', 37: 'L',
      38: 'J', 39: 'Quote', 40: 'K', 41: ';', 42: 'Backslash', 43: ',', 44: '/',
      45: 'N', 46: 'M', 47: '.', 48: 'Tab', 49: 'Space', 50: '`',
    };
    return names[keyCode] ?? '键$keyCode';
  }

  /// 初始化：注册通道 handler。
  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'listeningHotKey') {
        final action = (call.arguments as String?) ?? '';
        onAction?.call(action);
      }
      return null;
    });
  }
}
