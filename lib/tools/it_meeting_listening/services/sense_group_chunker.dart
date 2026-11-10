/// 意群分块器（Sense Group Chunker）。
///
/// 将长发言文本按母语者的认知意群（Sense Group / Chunks）进行切分，
/// 辅以呼吸停顿标识符（`//`），帮助学习者摆脱逐词心译，按块接收英文信息流。
library;

class SenseGroupChunk {
  final String text;
  final bool isSentenceEnd;
  final String pauseMarker;

  const SenseGroupChunk({
    required this.text,
    this.isSentenceEnd = false,
    this.pauseMarker = '//',
  });

  @override
  String toString() => '$text $pauseMarker';
}

class SenseGroupChunker {
  SenseGroupChunker._();

  static const Set<String> _sentenceEnds = {'.', '?', '!'};

  /// 常见从句与并列引导词（意群前导切分点）
  static final RegExp _clauseSplitters = RegExp(
    r'\b(so that|in order to|as long as|even though|as well as|moving forward|in this case|that|which|who|because|since|although|when|while|where|if|unless|however|therefore|whereas)\b',
    caseSensitive: false,
  );

  /// 把一段连续发言拆解为意群块列表
  static List<SenseGroupChunk> chunk(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return const [];

    // 先按句子初步切分（保留句末标点）
    final sentences = _splitSentences(raw);
    final results = <SenseGroupChunk>[];

    for (var sIdx = 0; sIdx < sentences.length; sIdx++) {
      final sentence = sentences[sIdx].trim();
      if (sentence.isEmpty) continue;

      final isLastSentence = sIdx == sentences.length - 1;
      final sentenceChunks = _chunkSingleSentence(sentence);

      for (var cIdx = 0; cIdx < sentenceChunks.length; cIdx++) {
        final isChunkSentenceEnd = cIdx == sentenceChunks.length - 1;
        results.add(
          SenseGroupChunk(
            text: sentenceChunks[cIdx],
            isSentenceEnd: isChunkSentenceEnd,
            pauseMarker: isChunkSentenceEnd ? (isLastSentence ? '' : '//') : '//',
          ),
        );
      }
    }

    return results;
  }

  /// 按标点拆解句子，同时保留尾部标点
  static List<String> _splitSentences(String text) {
    final sentences = <String>[];
    final buffer = StringBuffer();

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(char);

      if (_sentenceEnds.contains(char)) {
        // 避开缩写如 e.g. / i.e. / vs. / Dr. / Mr. / No.
        final curr = buffer.toString().trim();
        if (!_isAbbreviation(curr)) {
          sentences.add(curr);
          buffer.clear();
        }
      }
    }

    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) {
      sentences.add(rest);
    }

    return sentences;
  }

  static bool _isAbbreviation(String s) {
    final lower = s.toLowerCase();
    return lower.endsWith('e.g.') ||
        lower.endsWith('i.e.') ||
        lower.endsWith('vs.') ||
        lower.endsWith('etc.') ||
        lower.endsWith('dr.') ||
        lower.endsWith('mr.');
  }

  /// 对单句进行意群切分
  static List<String> _chunkSingleSentence(String sentence) {
    final allWords = sentence.trim().split(RegExp(r'\s+'));
    // 超短句（<= 5 个词）直接作为一个意群，即使有称呼逗号也不强行拆碎
    if (allWords.length <= 5) {
      return [sentence.trim()];
    }

    // 1. 如果带有逗号、分号、破折号，优先在逗号标点处切断
    final commaSegments = sentence
        .split(RegExp(r'(?<=[,;—–])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final chunks = <String>[];

    for (final segment in commaSegments) {
      final words = segment.trim().split(RegExp(r'\s+'));
      // 短段落（<= 7 个单词）无需进一步拆解
      if (words.length <= 7) {
        chunks.add(segment.trim());
        continue;
      }

      // 长段落根据从句引导词进一步切断
      final subChunks = _splitByClause(segment.trim());
      chunks.addAll(subChunks);
    }

    return chunks.isEmpty ? [sentence.trim()] : chunks;
  }

  /// 根据从句引导词切分长句
  static List<String> _splitByClause(String text) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 7) return [text];

    final chunks = <String>[];
    var current = <String>[];

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final cleanWord = word.replaceAll(RegExp(r'[^\w-]'), '');

      // 检查当前词是否是从句切分点（且当前累积已经有一定长度 >= 3 个词，且剩余词数 >= 3）
      final isSplitter = _clauseSplitters.hasMatch(cleanWord);
      if (isSplitter && current.length >= 3 && (words.length - i) >= 3) {
        chunks.add(current.join(' '));
        current = [word];
      } else {
        current.add(word);
      }
    }

    if (current.isNotEmpty) {
      chunks.add(current.join(' '));
    }

    return chunks;
  }
}
