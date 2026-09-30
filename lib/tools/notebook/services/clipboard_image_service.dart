import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show Clipboard;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 从剪贴板取到的一张图片（等调用方转存到笔记附件目录）。
class ClipboardImage {
  ClipboardImage({
    required this.file,
    required this.source,
    required this.ownedByService,
  });

  /// 图片内容所在文件。可能是本服务刚生成的临时文件，也可能是用户磁盘上
  /// 已有的文件（本地路径分支）——由 [ownedByService] 区分。
  final File file;

  /// 这张图片是怎么来的。仅用于诊断信息与测试断言，不影响行为。
  final ClipboardImageSource source;

  /// 为 true 时调用方用完必须删除它（临时文件）；为 false 时那是用户的
  /// 原件，删了会毁用户数据。
  final bool ownedByService;
}

enum ClipboardImageSource {
  /// macOS 剪贴板里的位图表示（`class PNGf`）——微信 / QQ / 系统截图 / Preview 复制。
  clipboardBitmap,

  /// 剪贴板里的图片 URL——浏览器「复制图片」。
  downloadedUrl,

  /// 剪贴板里的本地图片路径——Finder 复制文件。
  localPath,
}

/// 取剪贴板图片失败的原因。
///
/// 分成四类而不是一个 `error`：气泡要按类型说不同的话（"没识别到图片"与
/// "下载失败"用户能采取的下一步完全不同），混成一句就是骗人。
enum ClipboardImageFailure {
  /// 剪贴板里没有可识别的图片形态。
  nothingPasteable,

  /// 有位图但读不出来（AppleScript 被拒、权限缺失等）。
  bitmapReadFailed,

  /// 有图片 URL 但下载失败或内容不是图片。
  downloadFailed,

  /// 下载到的内容超出体积上限。
  tooLarge,
}

/// 剪贴板图片服务。
///
/// 三件事：
///   1. 探测 macOS 剪贴板的位图表示（`osascript` + `class PNGf`）；
///   2. 识别剪贴板里的图片 URL 并下载；
///   3. 兼容既有行为：剪贴板文本是本地图片路径。
///
/// 为什么位图走 `osascript` 而不是 Flutter 的 `Clipboard.getData('image/png')`：
/// Flutter 的剪贴板 API 在桌面端只可靠暴露文本，图片数据支持不完整；而
/// `osascript` 这条路在本机实测过——从真实的微信截图生成出 46137 字节的 PNG。
///
/// 为什么 `Process.run` 可注入：它是整个链路里最脆的一环（macOS 自动化授权、
/// 剪贴板表示变化都会让它失败），必须能在测试里替换掉，不能打真实系统剪贴板。
class ClipboardImageService {
  ClipboardImageService._();
  static final ClipboardImageService instance = ClipboardImageService._();

  /// 下载体积上限。剪贴板里的 URL 可能是任意外链，无上限会把一个巨大的
  /// 响应整个读进内存；单机自用不需要传几百兆的图。
  static const int maxDownloadBytes = 32 * 1024 * 1024;

  /// 每一步都有超时：`osascript` 偶发挂起（授权弹窗等待时），下载要防慢响应。
  /// 真账里这两个超时都远小于 MV3/UI 可感知的卡顿阈值。
  static const Duration _bitmapTimeout = Duration(seconds: 5);
  static const Duration _downloadTimeout = Duration(seconds: 20);

  static const List<String> _supportedExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  ];

  static final RegExp _imageUrlPattern = RegExp(
    r'''^https?://[^\s<>"']+\.(png|jpe?g|gif|webp|bmp)(\?[^\s<>"']*)?$''',
    caseSensitive: false,
  );

  /// 进程执行结果。[ProcessResult] 是 final class，测试无法伪造实现，因此这里
  /// 用自有记录类型承接，生产路径由 [_defaultProcessRunner] 适配。
  /// 进程执行器。测试注入替身；生产走真实 `Process.run`。
  Future<ProcessOutcome> Function(String executable, List<String> args)
      processRunner = _adaptProcessRunner;

  static Future<ProcessOutcome> _adaptProcessRunner(
    String executable,
    List<String> args,
  ) async {
    final r = await Process.run(executable, args);
    return ProcessOutcome(
      exitCode: r.exitCode,
      stdout: r.stdout.toString(),
      stderr: r.stderr.toString(),
    );
  }

  /// HTTP 客户端工厂。测试注入；生产走真实客户端。
  ///
  /// `flutter_test` 会把全局 `HttpOverrides` 换成恒返 400 的 mock，所以这个
  /// 注入点不是洁癖——不注入就只能在测试里拿到伪造的 400。
  http.Client Function() httpClientFactory = http.Client.new;

  /// 剪贴板文本读取。测试直接给字符串；生产走 Flutter 的剪贴板 API。
  ///
  /// 不走 `flutter/platform` 消息通道的桩：那是 Flutter 的私有契约，消息格式
  /// 随版本变，桩住它等于把测试绑在框架内部实现上。
  Future<String?> Function() clipboardTextReader = _readPlatformClipboardText;

  static Future<String?> _readPlatformClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  /// 按优先级尝试从剪贴板取图。
  ///
  /// 顺序即优先级：位图优先于 URL。两者同时存在时（有些应用既放位图又放
  /// 一个自造的 URL），位图是用户真正想粘的东西。
  Future<ClipboardImageResult> readImage() async {
    final bitmap = await _readClipboardBitmap();
    if (bitmap != null) return bitmap;

    final urlOrPath = await clipboardTextReader();
    if (urlOrPath == null || urlOrPath.trim().isEmpty) {
      return const ClipboardImageResult.failure(
        ClipboardImageFailure.nothingPasteable,
      );
    }
    final text = urlOrPath.trim();

    if (_imageUrlPattern.hasMatch(text)) {
      return _downloadImage(text);
    }
    return _adoptLocalPath(text);
  }

  // -------------------------------------------------------------------------
  // 1. 剪贴板位图
  // -------------------------------------------------------------------------

  Future<ClipboardImageResult?> _readClipboardBitmap() async {
    final tempPath =
        '/tmp/v8_clipboard_paste_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      final result = await processRunner('osascript', [
        '-e',
        'try\n'
            '  set theFile to open for access POSIX file "$tempPath" with write permission\n'
            '  set eof theFile to 0\n'
            '  write (the clipboard as «class PNGf») to theFile\n'
            '  close access theFile\n'
            '  return "ok"\n'
            'on error\n'
            '  try\n'
            '    close access POSIX file "$tempPath"\n'
            '  end try\n'
            '  return "fail"\n'
            'end try',
      ]).timeout(_bitmapTimeout);

      if (result.exitCode != 0 ||
          result.stdout.toString().trim() != 'ok') {
        // 剪贴板里没有位图时 AppleScript 走 on error 分支返回 "fail"，
        // 这是正常情况而不是错误——返回 null 让调用方继续试下一种来源。
        return null;
      }

      final file = File(tempPath);
      if (!await file.exists() || await file.length() == 0) {
        await _deleteQuietly(file);
        return null;
      }
      return ClipboardImageResult.success(
        ClipboardImage(
          file: file,
          source: ClipboardImageSource.clipboardBitmap,
          ownedByService: true,
        ),
      );
    } on TimeoutException {
      debugPrint('[ClipboardImage] 剪贴板位图探测超时');
      return null;
    } catch (e) {
      debugPrint('[ClipboardImage] 剪贴板位图探测异常: $e');
      return const ClipboardImageResult.failure(
        ClipboardImageFailure.bitmapReadFailed,
      );
    }
  }

  // -------------------------------------------------------------------------
  // 2. 图片 URL（浏览器复制图片）
  // -------------------------------------------------------------------------

  Future<ClipboardImageResult> _downloadImage(String url) async {
    final tempPath =
        '/tmp/v8_clipboard_dl_${DateTime.now().millisecondsSinceEpoch}'
        '${p.extension(Uri.parse(url).path)}';
    final file = File(tempPath);
    try {
      final client = httpClientFactory();
      try {
        // 不走应用代理：图片多由 CDN 提供、国内可达，过代理只加延迟。
        // 这一点是 spec 的显式场景，别当成遗漏又"修"进去。
        final request = http.Request('GET', Uri.parse(url))
          ..followRedirects = true
          ..headers['User-Agent'] = 'Mozilla/5.0';
        // fromStream 会把流转成完整 Response 并读入 bodyBytes；超时只管到
        // 首字节之后的整体读取，慢响应一样会被掐断。
        final response = await client
            .send(request)
            .timeout(_downloadTimeout)
            .then(http.Response.fromStream);

        if (response.statusCode != 200) {
          return ClipboardImageResult.failure(
            ClipboardImageFailure.downloadFailed,
            detail: 'HTTP ${response.statusCode}',
          );
        }
        if (!_looksLikeImage(response.headers['content-type'], response.bodyBytes)) {
          return ClipboardImageResult.failure(
            ClipboardImageFailure.downloadFailed,
            detail: '内容不是受支持的图片',
          );
        }
        if (response.bodyBytes.length > maxDownloadBytes) {
          return const ClipboardImageResult.failure(
            ClipboardImageFailure.tooLarge,
          );
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return ClipboardImageResult.success(
          ClipboardImage(
            file: file,
            source: ClipboardImageSource.downloadedUrl,
            ownedByService: true,
          ),
        );
      } finally {
        client.close();
      }
    } catch (e) {
      await _deleteQuietly(file);
      debugPrint('[ClipboardImage] 下载图片失败: $url ($e)');
      return ClipboardImageResult.failure(
        ClipboardImageFailure.downloadFailed,
        detail: '$e',
      );
    }
  }

  // -------------------------------------------------------------------------
  // 3. 本地图片路径（Finder 复制文件的既有行为）
  // -------------------------------------------------------------------------

  Future<ClipboardImageResult> _adoptLocalPath(String text) async {
    final file = File(text);
    if (!await file.exists()) {
      return const ClipboardImageResult.failure(
        ClipboardImageFailure.nothingPasteable,
      );
    }
    final ext = p.extension(text).toLowerCase();
    if (!_supportedExtensions.contains(ext)) {
      return const ClipboardImageResult.failure(
        ClipboardImageFailure.nothingPasteable,
      );
    }
    // 不复制到临时目录：调用方的 saveAttachment 会自己复制一份进附件目录。
    // 多一次复制只会让大图在磁盘上多躺一瞬间。ownedByService=false 是关键：
    // 这是用户磁盘上的原件，调用方用完不许删。
    return ClipboardImageResult.success(
      ClipboardImage(
        file: file,
        source: ClipboardImageSource.localPath,
        ownedByService: false,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // helpers
  // -------------------------------------------------------------------------

  bool _looksLikeImage(String? contentType, Uint8List bytes) {
    final type = (contentType ?? '').toLowerCase();
    if (type.startsWith('image/')) return true;
    // 有些 CDN 不返回 content-type 或返回 application/octet-stream；
    // 这时按魔数判。判不出就当不是图片，避免把一个 HTML 错误页存成 .png。
    if (bytes.length >= 4) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50) return true; // PNG
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true; // JPEG
      if (bytes[0] == 0x47 && bytes[1] == 0x49) return true; // GIF
      if (bytes[0] == 0x52 && bytes[1] == 0x49) return true; // WEBP
      if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true; // BMP
    }
    return false;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// 进程执行的三个字段。只为可测性而存在，不承载更多语义。
class ProcessOutcome {
  const ProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// 取图结果：成功带文件，失败带原因与可选细节。
///
/// 用 [asFailure] / [asSuccess] 判别，而不是让调用方 switch 私有子类——
/// 那样测试就用不到它们了。
sealed class ClipboardImageResult {
  const ClipboardImageResult();

  const factory ClipboardImageResult.success(ClipboardImage image) =
      _ClipboardImageSuccess;

  const factory ClipboardImageResult.failure(
    ClipboardImageFailure reason, {
    String? detail,
  }) = _ClipboardImageFailure;

  /// 失败时返回 `(原因, 细节)`；成功时返回 null。
  (ClipboardImageFailure, String?)? asFailure() {
    final self = this;
    return self is _ClipboardImageFailure ? (self.reason, self.detail) : null;
  }

  /// 成功时返回图片；失败时返回 null。
  ClipboardImage? asSuccess() {
    final self = this;
    return self is _ClipboardImageSuccess ? self.image : null;
  }
}

final class _ClipboardImageSuccess extends ClipboardImageResult {
  const _ClipboardImageSuccess(this.image);
  final ClipboardImage image;
}

final class _ClipboardImageFailure extends ClipboardImageResult {
  const _ClipboardImageFailure(this.reason, {this.detail});
  final ClipboardImageFailure reason;

  /// 附加细节（HTTP 状态、异常文本），用于诊断信息。
  final String? detail;
}
