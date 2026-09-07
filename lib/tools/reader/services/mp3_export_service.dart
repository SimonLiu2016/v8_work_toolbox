import 'dart:io';
import '../models/reader_models.dart';
import 'tts_coordinator.dart';

/// MP3 音频合并与导出服务
class Mp3ExportService {
  final TtsSynthesisCoordinator coordinator;

  Mp3ExportService({required this.coordinator});

  /// 导出完整文档为单独的 MP3 音频文件
  Future<File> exportFullDocumentMp3(
    ReadingDocument document,
    String targetFilePath, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final total = document.chunks.length;
    if (total == 0) {
      throw Exception('文档没有可供导出的文本切片');
    }

    final targetFile = File(targetFilePath);
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }

    final sink = targetFile.openWrite(mode: FileMode.writeOnly);

    try {
      for (int i = 0; i < total; i++) {
        final path = await coordinator.ensureChunkSynthesized(document, i);
        if (path == null) {
          throw Exception('第 ${i + 1} 个段落音频合成失败，无法继续导出');
        }

        final chunkFile = File(path);
        if (!await chunkFile.exists()) {
          throw Exception('未找到已生成的切片音频: $path');
        }

        final chunkBytes = await chunkFile.readAsBytes();
        sink.add(chunkBytes);

        onProgress?.call(i + 1, total);
      }

      await sink.flush();
    } finally {
      await sink.close();
    }

    return targetFile;
  }
}
