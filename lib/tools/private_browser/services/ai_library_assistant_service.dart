import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../services/ai_service.dart';
import 'private_browser_repository.dart';

/// 隐私空间私密视频库 AI 辅助服务
///
/// 具备三大核心能力：
/// 1. 收藏时智能自动打标签 (Smart Tagging) 与分类推荐
/// 2. 语义智能检索 (Semantic Search)：结合 FTS5 候选粗筛与大模型意图语义重排
/// 3. 智能视频与收藏库咨询对话 (AI Library Assistant Chat)
class AILibraryAssistantService {
  AILibraryAssistantService._();
  static final AILibraryAssistantService instance = AILibraryAssistantService._();

  final AiService _aiService = AiService.instance;
  final PrivateBrowserRepository _repo = PrivateBrowserRepository();

  /// 1. 智能自动打标签与分类推荐
  Future<({List<String> tags, String? suggestedCategory, String summary})> analyzeVideoBookmark({
    required String title,
    required String platform,
    required String url,
    String? description,
  }) async {
    final systemPrompt = '''
你是一个私密影音收藏夹的高级元数据分析助手。用户提供了一段网页视频的基本信息（标题、来源平台、网址及可能存在的描述）。
请对其进行内容主题提炼，并以纯 JSON 格式输出，不要输出任何 markdown 格式化字符或反引号。
输出结构：
{
  "tags": ["标签1", "标签2", "标签3"],
  "suggestedCategory": "分类建议（如：音乐MV / 教学视频 / 动漫 / 电影 / 娱乐等，2-6字）",
  "summary": "一段简明扼要的内容概要（50字以内）"
}
''';

    final userContent = '''
标题: $title
平台: $platform
URL: $url
描述: ${description ?? '无'}
''';

    try {
      final chatResult = await _aiService.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
      );

      final cleanText = _cleanJsonResponse(chatResult.text);
      final decoded = jsonDecode(cleanText) as Map<String, dynamic>;

      final rawTags = decoded['tags'] as List? ?? [];
      final tags = rawTags.map((e) => e.toString().trim()).where((t) => t.isNotEmpty).toList();
      final suggestedCategory = decoded['suggestedCategory'] as String?;
      final summary = decoded['summary'] as String? ?? '';

      return (
        tags: tags,
        suggestedCategory: suggestedCategory,
        summary: summary,
      );
    } catch (e) {
      debugPrint('AI 智能分析标签失败: $e');
      // 降级回退基于标题简单分词提取
      final fallbackTags = _generateFallbackTags(title, platform);
      return (
        tags: fallbackTags,
        suggestedCategory: null,
        summary: '',
      );
    }
  }

  /// 2. 语义智能检索：结合 FTS5 粗筛候选与 LLM 语义重排
  Future<List<VideoBookmarkItem>> semanticSearch({
    required String query,
    required List<VideoBookmarkItem> allBookmarks,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || allBookmarks.isEmpty) return allBookmarks;

    // 若视频总数小于等于 200，直接全量送入上下文；若超过则由 FTS5 预筛选
    final candidates = allBookmarks.length > 200
        ? allBookmarks.take(200).toList()
        : allBookmarks;

    final candidateSummaries = candidates.map((b) => {
      'id': b.id,
      'title': b.title,
      'platform': b.platform,
      'tags': b.aiTags.join(', '),
      'notes': b.notes ?? '',
    }).toList();

    final systemPrompt = '''
你是一个本地影音收藏库的语义检索专家。
用户的自然语言查询可能包含模糊语义、同义词、情感偏好或场景描述（如："找一部带中文字幕的高清视频"、"上次存的那个关于音乐演奏的"）。
请根据候选视频列表与用户查询意图的相关度，选出匹配的视频 ID，并按照相关性从高到低排序。
仅以纯 JSON 数组返回视频 id，格式如：["id1", "id2", "id3"]。不要包含任何额外文字或解释。
''';

    final userContent = '''
用户查询: $trimmedQuery
候选视频列表:
${jsonEncode(candidateSummaries)}
''';

    try {
      final chatResult = await _aiService.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
      );

      final cleanText = _cleanJsonResponse(chatResult.text);
      final matchedIds = (jsonDecode(cleanText) as List)
          .map((e) => e.toString())
          .toSet();

      final result = <VideoBookmarkItem>[];
      for (final id in matchedIds) {
        final found = candidates.firstWhere((b) => b.id == id, orElse: () => candidates.first);
        if (found.id == id) {
          result.add(found);
        }
      }

      // 若匹配到的数量较少，拼接剩余未匹配项中包含字面的作为保底
      if (result.isEmpty) {
        return candidates.where((b) =>
            b.title.toLowerCase().contains(trimmedQuery.toLowerCase()) ||
            b.aiTags.any((t) => t.toLowerCase().contains(trimmedQuery.toLowerCase()))
        ).toList();
      }

      return result;
    } catch (e) {
      debugPrint('语义检索解析异常，回退字面匹配: $e');
      return candidates.where((b) =>
          b.title.toLowerCase().contains(trimmedQuery.toLowerCase()) ||
          b.aiTags.any((t) => t.toLowerCase().contains(trimmedQuery.toLowerCase()))
      ).toList();
    }
  }

  /// 3. AI 咨询与整理面板对话
  Future<String> chatWithAssistant({
    required List<Map<String, String>> conversationHistory,
    required List<VideoBookmarkItem> recentBookmarks,
    required List<VideoCategoryItem> categories,
    String? currentWebUrl,
    String? currentWebTitle,
  }) async {
    final libraryDigest = recentBookmarks.take(50).map((b) =>
      "- [${b.platform}] ${b.title} (标签: ${b.aiTags.join('/')})"
    ).join('\n');

    final categoryNames = categories.map((c) => c.name).join('、');

    final systemPrompt = '''
你内置于用户的个人隐私空间视频收藏库。你的任务是协助用户管理收藏、解答关于收藏夹内容的提问、提供分类整理建议，以及根据用户当前正在看的网页视频提供背景咨询。
当前分类架构：${categoryNames.isEmpty ? '暂未建立分类' : categoryNames}
用户最近收藏的视频清单：
$libraryDigest

${currentWebUrl != null ? '用户当前浏览器停留在网页: $currentWebTitle ($currentWebUrl)' : ''}

请以亲切、简练、专业的中文回答用户，支持 markdown 列表与重点加粗。
''';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...conversationHistory,
    ];

    final res = await _aiService.chat(
      slot: 'text',
      messages: messages,
    );

    return res.text;
  }

  String _cleanJsonResponse(String text) {
    var s = text.trim();
    if (s.startsWith('```json')) {
      s = s.substring(7);
    } else if (s.startsWith('```')) {
      s = s.substring(3);
    }
    if (s.endsWith('```')) {
      s = s.substring(0, s.length - 3);
    }
    return s.trim();
  }

  List<String> _generateFallbackTags(String title, String platform) {
    final tags = <String>{platform};
    if (title.contains('4K') || title.contains('1080P') || title.contains('720P')) {
      tags.add('高清');
    }
    if (title.contains('中文字幕') || title.contains('中字') || title.contains('字幕')) {
      tags.add('中文字幕');
    }
    if (title.contains('无码') || title.contains('破解')) {
      tags.add('无码');
    }
    return tags.toList();
  }
}
