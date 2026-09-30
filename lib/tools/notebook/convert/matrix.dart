/// 文档转换矩阵——格式枚举、还原度分级与可用目标推导。
///
/// 这是整个转换功能的唯一数据源：
///   - UI 下拉菜单只渲染 [availableTargets] 的结果
///   - 矩阵一致性测试把本表与已注册的 converter 交叉比对
///
/// **分级定义：**
/// - [ConversionTier.t1]：排版/图片零变化——原地替换文本节点，其余字节不动
/// - [ConversionTier.t2]：内容与图片保留，排版尽力还原（best-effort）
/// - [ConversionTier.unavailable]：不提供，不出现在 UI
library;

// 矩阵（规范性，与 spec 同步）：
//
// 源＼目标   docx     pdf      md       txt      xlsx     csv
// ─────────────────────────────────────────────────────────────────
// docx       T1       T2       T2       T2       —        —
// md         T2       T1       T2       T2       —        —
// txt        T1       T1       T1       T1       —        —
// pdf        —        T2       T2       T2       —        —
// xlsx       T2       T2       T2       T2       T1       T2
// csv        T2       T2       T2       T2       T2       T1

/// 支持转换的文档格式。
enum DocFormat {
  docx,
  pdf,
  md,
  txt,
  xlsx,
  csv;

  /// 用户可读的格式名称。
  String get label {
    switch (this) {
      case DocFormat.docx:
        return 'Word (.docx)';
      case DocFormat.pdf:
        return 'PDF';
      case DocFormat.md:
        return 'Markdown (.md)';
      case DocFormat.txt:
        return '纯文本 (.txt)';
      case DocFormat.xlsx:
        return 'Excel (.xlsx)';
      case DocFormat.csv:
        return 'CSV';
    }
  }

  /// 文件扩展名（不含点）。
  String get extension {
    switch (this) {
      case DocFormat.docx:
        return 'docx';
      case DocFormat.pdf:
        return 'pdf';
      case DocFormat.md:
        return 'md';
      case DocFormat.txt:
        return 'txt';
      case DocFormat.xlsx:
        return 'xlsx';
      case DocFormat.csv:
        return 'csv';
    }
  }

  /// MIME 类型。
  String get mime {
    switch (this) {
      case DocFormat.docx:
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case DocFormat.pdf:
        return 'application/pdf';
      case DocFormat.md:
        return 'text/markdown';
      case DocFormat.txt:
        return 'text/plain';
      case DocFormat.xlsx:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case DocFormat.csv:
        return 'text/csv';
    }
  }

  /// 从文件扩展名推断格式（不含点，小写）。返回 null 表示不支持。
  static DocFormat? fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'docx':
      case 'doc':
        return DocFormat.docx;
      case 'pdf':
        return DocFormat.pdf;
      case 'md':
      case 'markdown':
        return DocFormat.md;
      case 'txt':
        return DocFormat.txt;
      case 'xlsx':
      case 'xls':
        return DocFormat.xlsx;
      case 'csv':
        return DocFormat.csv;
      default:
        return null;
    }
  }
}

/// 转换还原度分级。
enum ConversionTier {
  /// 排版/图片零变化——原地替换文本节点，其余字节不动。
  t1,

  /// 内容与图片保留，排版尽力还原（best-effort）。
  t2,

  /// 不提供，不出现在 UI。
  unavailable,
}

/// 规范性转换矩阵。
///
/// 外层 key = 源格式，内层 key = 目标格式，value = 分级。
/// 矩阵中每个 (源, 目标) 对都有一个显式声明，不存在"隐含不可用"。
const Map<DocFormat, Map<DocFormat, ConversionTier>> kConversionMatrix = {
  DocFormat.docx: {
    DocFormat.docx: ConversionTier.t1,
    DocFormat.pdf: ConversionTier.t2,
    DocFormat.md: ConversionTier.t2,
    DocFormat.txt: ConversionTier.t2,
    DocFormat.xlsx: ConversionTier.unavailable,
    DocFormat.csv: ConversionTier.unavailable,
  },
  DocFormat.md: {
    DocFormat.docx: ConversionTier.t2,
    DocFormat.pdf: ConversionTier.t1,
    DocFormat.md: ConversionTier.t2,
    DocFormat.txt: ConversionTier.t2,
    DocFormat.xlsx: ConversionTier.unavailable,
    DocFormat.csv: ConversionTier.unavailable,
  },
  DocFormat.txt: {
    DocFormat.docx: ConversionTier.t1,
    DocFormat.pdf: ConversionTier.t1,
    DocFormat.md: ConversionTier.t1,
    DocFormat.txt: ConversionTier.t1,
    DocFormat.xlsx: ConversionTier.unavailable,
    DocFormat.csv: ConversionTier.unavailable,
  },
  DocFormat.pdf: {
    DocFormat.docx: ConversionTier.unavailable,
    DocFormat.pdf: ConversionTier.t2,
    DocFormat.md: ConversionTier.t2,
    DocFormat.txt: ConversionTier.t2,
    DocFormat.xlsx: ConversionTier.unavailable,
    DocFormat.csv: ConversionTier.unavailable,
  },
  DocFormat.xlsx: {
    DocFormat.docx: ConversionTier.t2,
    DocFormat.pdf: ConversionTier.t2,
    DocFormat.md: ConversionTier.t2,
    DocFormat.txt: ConversionTier.t2,
    DocFormat.xlsx: ConversionTier.t1,
    DocFormat.csv: ConversionTier.t2,
  },
  DocFormat.csv: {
    DocFormat.docx: ConversionTier.t2,
    DocFormat.pdf: ConversionTier.t2,
    DocFormat.md: ConversionTier.t2,
    DocFormat.txt: ConversionTier.t2,
    DocFormat.xlsx: ConversionTier.t2,
    DocFormat.csv: ConversionTier.t1,
  },
};

/// 返回给定源格式的可用目标格式列表（按矩阵顺序，不包含不可用格）。
///
/// UI 下拉菜单只渲染此结果，保证不可用路径不出现在选项里。
List<DocFormat> availableTargets(DocFormat source) {
  final row = kConversionMatrix[source];
  if (row == null) return const [];
  return row.entries
      .where((e) => e.value != ConversionTier.unavailable)
      .map((e) => e.key)
      .toList();
}

/// 查询单格的还原度分级。返回 [ConversionTier.unavailable] 表示不提供。
ConversionTier conversionTier(DocFormat source, DocFormat target) {
  return kConversionMatrix[source]?[target] ?? ConversionTier.unavailable;
}

/// 已注册的 converter 集合——实现层向此表注册后，矩阵一致性测试才会放行。
///
/// key = (source, target) 对，value = converter 标识符（用于调试信息）。
/// 注册由各 converter 文件在顶层调用 [registerConverter] 完成。
final Map<(DocFormat, DocFormat), String> _converterRegistry = {};

/// 注册一个 converter 实现。
///
/// 由各 `*_rewriter.dart` / `*_writer.dart` 在文件顶层调用。
void registerConverter(DocFormat source, DocFormat target, String converterId) {
  _converterRegistry[(source, target)] = converterId;
}

/// 只读视图，供测试使用。
Map<(DocFormat, DocFormat), String> get converterRegistry =>
    Map.unmodifiable(_converterRegistry);
