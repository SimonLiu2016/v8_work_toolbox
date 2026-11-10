import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../services/app_paths.dart';

/// 短剧封面解密与多级缓存管理器
///
/// 上游站点短剧封面多为 AES-128-CBC 密文，必须先通过静态 Key 与 IV 解密并去除 PKCS7 填充，
/// 随后缓存至内存与私密磁盘目录，供 UI 秒级加载海报。
class DramaCoverDecryptor {
  DramaCoverDecryptor({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  static final DramaCoverDecryptor instance = DramaCoverDecryptor();

  final http.Client _client;

  static final Uint8List _keyBytes = Uint8List.fromList(utf8.encode('f5d965df75336270'));
  static final Uint8List _ivBytes = Uint8List.fromList(utf8.encode('97b60394abc2fbe1'));

  late final enc.Encrypter _encrypter = enc.Encrypter(
    enc.AES(
      enc.Key(_keyBytes),
      mode: enc.AESMode.cbc,
      padding: null,
    ),
  );
  late final enc.IV _iv = enc.IV(_ivBytes);

  // 内存 LRU 缓存，最多保留 200 张封面
  static const int _maxMemoryEntries = 200;
  final LinkedHashMap<String, Uint8List> _memCache = LinkedHashMap<String, Uint8List>();

  /// 获取封面图片二进制数据（支持内存/磁盘缓存与实时解密）
  Future<Uint8List?> getCoverBytes(String? url) async {
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    final targetUrl = url.trim();

    // 1. 命中内存缓存
    if (_memCache.containsKey(targetUrl)) {
      final cached = _memCache.remove(targetUrl)!;
      _memCache[targetUrl] = cached; // 移至末尾 (最近使用)
      return cached;
    }

    // 2. 检查本地磁盘隔离缓存
    final cacheFile = _getDiskCacheFile(targetUrl);
    try {
      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _putMemCache(targetUrl, bytes);
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('[DramaCoverDecryptor] read disk cache error: $e');
    }

    // 3. 网络拉取并解密
    try {
      final resp = await _client.get(
        Uri.parse(targetUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        return null;
      }

      final rawBytes = resp.bodyBytes;
      final plainBytes = decryptBytes(rawBytes);

      // 4. 回写入内存与磁盘
      _putMemCache(targetUrl, plainBytes);
      _saveDiskCache(cacheFile, plainBytes);

      return plainBytes;
    } catch (e) {
      debugPrint('[DramaCoverDecryptor] fetch/decrypt cover failed ($targetUrl): $e');
      return null;
    }
  }

  /// 同步解密封面字节流（如果是明文图片则原样返回）
  Uint8List decryptBytes(Uint8List rawBytes) {
    if (isPlainImage(rawBytes)) {
      return rawBytes;
    }
    if (rawBytes.isEmpty || rawBytes.length % 16 != 0) {
      return rawBytes;
    }

    try {
      final decrypted = _encrypter.decryptBytes(enc.Encrypted(rawBytes), iv: _iv);
      final stripped = stripPadding(Uint8List.fromList(decrypted));
      if (isPlainImage(stripped)) {
        return stripped;
      }
      return stripped.isNotEmpty ? stripped : rawBytes;
    } catch (e) {
      debugPrint('[DramaCoverDecryptor] aes decrypt failed: $e');
      return rawBytes;
    }
  }

  /// 检测是否已为常见明文图片格式 (JPEG / PNG / GIF / WEBP)
  static bool isPlainImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return true;
    // WEBP (RIFF....WEBP)
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      if (bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) return true;
    }
    return false;
  }

  /// 去除 PKCS7 填充
  static Uint8List stripPadding(Uint8List buf) {
    if (buf.isEmpty) return buf;
    final pad = buf.last;
    if (pad > 0 && pad <= 16 && buf.length >= pad) {
      bool allMatch = true;
      for (int i = buf.length - pad; i < buf.length; i++) {
        if (buf[i] != pad) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) {
        return Uint8List.sublistView(buf, 0, buf.length - pad);
      }
    }
    return buf;
  }

  /// 清空内存缓存
  void clearMemoryCache() {
    _memCache.clear();
  }

  void _putMemCache(String url, Uint8List bytes) {
    if (_memCache.length >= _maxMemoryEntries) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[url] = bytes;
  }

  File _getDiskCacheFile(String url) {
    final hash = crypto.md5.convert(utf8.encode(url)).toString();
    final coversDir = AppPaths.casualShortDramaCoversDir;
    return File('${coversDir.path}/$hash.img');
  }

  Future<void> _saveDiskCache(File file, Uint8List bytes) async {
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('[DramaCoverDecryptor] write disk cache failed: $e');
    }
  }
}
