import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// 音频分块本地缓存管理器
/// 统一管理 ~/.v8worktoolbox/audio_cache/<docId>/ 下的切片音频文件
class AudioCacheManager {
  final String? customBasePath;

  AudioCacheManager({this.customBasePath});

  String get _home => Platform.environment['HOME'] ?? '';

  String get baseCacheDir =>
      customBasePath ?? p.join(_home, '.v8worktoolbox', 'audio_cache');

  /// 获取指定文档的独立缓存目录，若不存在则递归创建
  Future<Directory> getDocCacheDir(String docId) async {
    final dir = Directory(p.join(baseCacheDir, docId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 根据音频二进制头嗅探格式扩展名 (支持 RIFF/WAVE 与 MP3)
  static String detectAudioExtension(Uint8List bytes) {
    if (bytes.length >= 12) {
      // 检查 RIFF .... WAVE 标头
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x41 &&
          bytes[10] == 0x56 &&
          bytes[11] == 0x45) {
        return 'wav';
      }
    }
    return 'mp3';
  }

  /// 获取已存在的切片文件（检查 .wav 和 .mp3）
  File? findExistingChunkFile(String docId, int chunkIndex) {
    final wavFile = File(p.join(baseCacheDir, docId, 'chunk_${chunkIndex.toString().padLeft(4, '0')}.wav'));
    if (wavFile.existsSync() && wavFile.lengthSync() > 0) {
      return wavFile;
    }
    final mp3File = File(p.join(baseCacheDir, docId, 'chunk_${chunkIndex.toString().padLeft(4, '0')}.mp3'));
    if (mp3File.existsSync() && mp3File.lengthSync() > 0) {
      return mp3File;
    }
    return null;
  }

  /// 获取指定切片的标准存储路径（若已有缓存文件则返回对应实际扩展名路径）
  String getChunkFilePath(String docId, int chunkIndex, {String ext = 'mp3'}) {
    final existing = findExistingChunkFile(docId, chunkIndex);
    if (existing != null) {
      return existing.path;
    }
    final filename = 'chunk_${chunkIndex.toString().padLeft(4, '0')}.$ext';
    return p.join(baseCacheDir, docId, filename);
  }

  /// 检查切片是否已被持久化缓存
  bool isChunkCached(String docId, int chunkIndex) {
    return findExistingChunkFile(docId, chunkIndex) != null;
  }

  /// 保存合成的切片二进制音频到本地文件（自动嗅探 WAV/MP3 后缀）
  Future<File> saveChunkAudio(
    String docId,
    int chunkIndex,
    Uint8List audioBytes,
  ) async {
    await getDocCacheDir(docId);
    final ext = detectAudioExtension(audioBytes);
    final filePath = p.join(baseCacheDir, docId, 'chunk_${chunkIndex.toString().padLeft(4, '0')}.$ext');
    final file = File(filePath);
    await file.writeAsBytes(audioBytes, flush: true);

    // 清理可能遗留的旧后缀文件
    final otherExt = ext == 'wav' ? 'mp3' : 'wav';
    final otherFile = File(p.join(baseCacheDir, docId, 'chunk_${chunkIndex.toString().padLeft(4, '0')}.$otherExt'));
    if (otherFile.existsSync()) {
      try {
        otherFile.deleteSync();
      } catch (_) {}
    }

    return file;
  }

  /// 读取已缓存切片的音频字节流
  Future<Uint8List?> getChunkAudio(String docId, int chunkIndex) async {
    final file = findExistingChunkFile(docId, chunkIndex);
    if (file != null && await file.exists() && await file.length() > 0) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// 获取指定文档所有已缓存切片文件（按序号正序排序，兼容 .mp3 与 .wav）
  Future<List<File>> getCachedChunkFiles(String docId) async {
    final dir = Directory(p.join(baseCacheDir, docId));
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (ext == '.mp3' || ext == '.wav') {
          files.add(entity);
        }
      }
    }
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  /// 清除指定文档的全部音频缓存
  Future<void> clearDocCache(String docId) async {
    try {
      final dir = Directory(p.join(baseCacheDir, docId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// 清空整个音讯缓存总目录
  Future<void> clearAllAudioCache() async {
    try {
      final dir = Directory(baseCacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  /// 计算当前音频缓存占用总字节大小
  Future<int> calculateTotalCacheSize() async {
    final dir = Directory(baseCacheDir);
    if (!await dir.exists()) return 0;

    int totalBytes = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
    } catch (_) {}
    return totalBytes;
  }
}
