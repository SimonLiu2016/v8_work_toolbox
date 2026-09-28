import 'package:yaml/yaml.dart';

/// Clash 订阅解析失败时抛出。
class ClashParseException implements Exception {
  final String message;
  const ClashParseException(this.message);

  @override
  String toString() => 'ClashParseException: $message';
}

/// 单个代理节点，保留所有原始字段以供 mihomo config 原样写入。
class ProxyNode {
  final String name;
  final String type;
  final Map<String, dynamic> rawConfig;

  const ProxyNode({
    required this.name,
    required this.type,
    required this.rawConfig,
  });

  factory ProxyNode.fromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString() ?? '';
    final type = map['type']?.toString() ?? 'unknown';
    return ProxyNode(name: name, type: type, rawConfig: map);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'rawConfig': rawConfig,
  };

  factory ProxyNode.fromJson(Map<String, dynamic> json) {
    final raw = (json['rawConfig'] as Map?)?.cast<String, dynamic>() ?? {};
    return ProxyNode(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'unknown',
      rawConfig: raw,
    );
  }

  @override
  String toString() => 'ProxyNode($type: $name)';
}

/// 解析 Clash/mihomo 格式的订阅 YAML，提取代理节点列表。
class ClashSubscriptionParser {
  /// 解析订阅 YAML 字符串，返回代理节点列表。
  ///
  /// 抛出 [ClashParseException] 当：
  /// - 内容无法识别为有效 YAML
  /// - `proxies:` 字段不存在或为空列表
  static List<ProxyNode> parse(String yamlContent) {
    if (yamlContent.trim().isEmpty) {
      throw const ClashParseException('订阅内容为空');
    }

    dynamic doc;
    try {
      doc = loadYaml(yamlContent);
    } catch (e) {
      throw ClashParseException('YAML 解析失败: $e');
    }

    if (doc is! Map) {
      throw const ClashParseException('订阅内容格式无效，根结构不是 Map');
    }

    final proxiesRaw = doc['proxies'];
    if (proxiesRaw == null) {
      throw const ClashParseException('订阅内容无效，未找到 proxies: 字段');
    }

    if (proxiesRaw is! List || proxiesRaw.isEmpty) {
      throw const ClashParseException('订阅内容无效，代理节点列表为空');
    }

    final nodes = <ProxyNode>[];
    for (final item in proxiesRaw) {
      if (item is Map) {
        try {
          final map = _deepConvert(item);
          if (map['name'] != null && map['name'].toString().isNotEmpty) {
            nodes.add(ProxyNode.fromMap(map));
          }
        } catch (_) {
          // 跳过格式异常的单个节点
        }
      }
    }

    if (nodes.isEmpty) {
      throw const ClashParseException('订阅内容无效，所有节点解析均失败');
    }

    return nodes;
  }

  /// 将 YamlMap/YamlList 递归转换为普通 Dart Map/List。
  static Map<String, dynamic> _deepConvert(Map raw) {
    final result = <String, dynamic>{};
    for (final key in raw.keys) {
      result[key.toString()] = _convertValue(raw[key]);
    }
    return result;
  }

  static dynamic _convertValue(dynamic value) {
    if (value is Map) return _deepConvert(value);
    if (value is List) return value.map(_convertValue).toList();
    return value;
  }
}
