import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:V8WorkToolbox/tools/notebook/services/clipboard_image_service.dart';

/// 剪贴板图片服务（capability: `notebook-clipboard-image-paste`）。
///
/// 验的是三条来源分支与它们的失败态：
///   1. 剪贴板位图（osascript → class PNGf）；
///   2. 剪贴板图片 URL（浏览器复制图片）；
///   3. 剪贴板本地图片路径（Finder 复制文件）。
///
/// `osascript` 用注入的替身进程执行器，不打真实系统剪贴板；下载用本地
/// `HttpServer`，不打外网。服务的 `readImage()` 读 Flutter 剪贴板，测试里
/// 那条走 [TestDefaultBinaryMessengerBinding] 的桩。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ClipboardImageService service;
  late List<File> tempFiles;
  late Directory tempDir;

  /// 1×1 PNG（真的能过魔数校验）。
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
    'DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_clipimg_test_');
    tempFiles = [];
    service = ClipboardImageService.instance;
    service.processRunner = fakeRunnerOk();
  });

  tearDown(() async {
    service.processRunner = (e, a) async => const ProcessOutcome(
          exitCode: 0,
          stdout: '',
          stderr: '',
        );
    service.clipboardTextReader = () async => null;
    for (final f in tempFiles) {
      if (f.existsSync()) f.deleteSync();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 造一个临时文件并登记以便 tearDown 清理。
  File track(String name, List<int> bytes) {
    final f = File('${tempDir.path}/$name');
    f.writeAsBytesSync(bytes);
    tempFiles.add(f);
    return f;
  }

  group('clipboard bitmap', () {
    test('osascript returns ok and writes bytes → success with temp file',
        () async {
      final fake = track('fake_bitmap.png', pngBytes);
      service.processRunner = fakeRunnerOk(fileToReturn: fake);

      final result = await service.readImage();

      final image = result.asSuccess();
      expect(image, isNotNull);
      expect(image!.source, ClipboardImageSource.clipboardBitmap);
      expect(image.ownedByService, isTrue, reason: '临时文件必须由调用方清理');
      expect(await image.file.readAsBytes(), pngBytes);
    });

    test('osascript returns fail → falls through, not an error', () async {
      // 剪贴板里没有位图时 AppleScript 走 on error 分支返回 "fail"——这是
      // 正常情况，必须让 readImage 继续试下一种来源而不是直接失败。
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('');

      final result = await service.readImage();

      expect(result.asFailure()?.$1, ClipboardImageFailure.nothingPasteable);
    });

    test('osascript throws → bitmapReadFailed, distinguishable', () async {
      service.processRunner = (exe, args) async => throw StateError(
            '模拟 osascript 崩溃',
          );

      final result = await service.readImage();

      expect(result.asFailure()?.$1, ClipboardImageFailure.bitmapReadFailed);
    });
  });

  group('image url from clipboard', () {
    // flutter_test 会把全局 HttpOverrides 换成恒返 400 的 mock，所以这里必须
    // 往服务里注入客户端；不打真外网，由 MockClient 直接给响应。
    void stubHttpClient(
      Future<http.Response> Function(http.Request) handler,
    ) {
      service.httpClientFactory = () => _StubClient(handler);
    }

    test('serves a png → downloaded and owned by service', () async {
      stubHttpClient((req) async {
        return http.Response.bytes(pngBytes, 200, headers: {
          'content-type': 'image/png',
        });
      });
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('https://example.com/pic.png');

      final result = await service.readImage();

      final image = result.asSuccess();
      expect(image, isNotNull);
      expect(image!.source, ClipboardImageSource.downloadedUrl);
      expect(image.ownedByService, isTrue);
      expect(await image.file.readAsBytes(), pngBytes);
    });

    test('non-200 → downloadFailed with the status as detail', () async {
      stubHttpClient((req) async => http.Response('gone', 404));
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('https://example.com/missing.png');

      final result = await service.readImage();

      final (reason, detail) = result.asFailure()!;
      expect(reason, ClipboardImageFailure.downloadFailed);
      expect(detail, contains('404'));
    });

    test('html body with image extension → downloadFailed, not a fake image',
        () async {
      // 有些站点对错误页也返回 200。URL 以 .png 结尾但内容是 HTML，
      // 必须被拒——否则笔记里会躺一个打不开的"图片"。
      stubHttpClient((req) async => http.Response(
            '<html>not found</html>',
            200,
            headers: {'content-type': 'text/html'},
          ));
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('https://example.com/fake.png');

      final result = await service.readImage();

      final (reason, detail) = result.asFailure()!;
      expect(reason, ClipboardImageFailure.downloadFailed);
      expect(detail, contains('不是受支持的图片'));
    });

    test('octet-stream with real png bytes is accepted by magic number',
        () async {
      // 有些 CDN 不返回 content-type 或给 application/octet-stream。
      // 这时按魔数判，不能把真图片误杀。
      stubHttpClient((req) async {
        return http.Response.bytes(pngBytes, 200, headers: {
          'content-type': 'application/octet-stream',
        });
      });
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('https://example.com/cdn.bin');

      final result = await service.readImage();

      // URL 不以图片扩展名结尾，走不到下载分支——这条守的是"扩展名不匹配
      // 时根本不尝试下载"，避免把任意 URL 都当图片拖下来。
      expect(result.asFailure()?.$1, ClipboardImageFailure.nothingPasteable);
    });

    test('url without an image extension is not treated as an image url',
        () async {
      // 只认"看起来就是图片"的 URL；其余按纯文本交给编辑器粘贴。
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('https://example.com/page?x=1');

      final result = await service.readImage();

      expect(result.asFailure()?.$1, ClipboardImageFailure.nothingPasteable);
    });
  });

  group('local image path', () {
    test('existing png on disk → success and NOT owned by service', () async {
      final file = track('user_original.png', pngBytes);
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText(file.path);

      final result = await service.readImage();

      final image = result.asSuccess();
      expect(image, isNotNull);
      expect(image!.source, ClipboardImageSource.localPath);
      // 关键：这是用户磁盘上的原件，调用方用完不许删。
      expect(image.ownedByService, isFalse);
      expect(image.file.path, file.path);
    });

    test('non-image extension → nothingPasteable', () async {
      final file = track('notes.txt', utf8.encode('hello'));
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText(file.path);

      final result = await service.readImage();

      expect(result.asFailure()?.$1, ClipboardImageFailure.nothingPasteable);
    });

    test('non-existent path → nothingPasteable', () async {
      service.processRunner = fakeRunnerOk(stdoutText: 'fail');
      clipboardText('${tempDir.path}/gone.png');

      final result = await service.readImage();

      expect(result.asFailure()?.$1, ClipboardImageFailure.nothingPasteable);
    });
  });
}

/// 注入剪贴板文本。走服务自身的注入点，不去桩 Flutter 的平台消息通道——
/// 那是框架的私有契约，消息格式随版本变，桩住它等于把测试绑在内部实现上。
void clipboardText(String text) {
  ClipboardImageService.instance.clipboardTextReader = () async => text;
}

/// 位图探测的替身进程执行器。
///
/// [stdoutText] 为 'ok' 时表示"剪贴板有位图"，并按 AppleScript 脚本的约定
/// 把内容写进脚本里的那个 `/tmp/v8_clipboard_paste_*.png` 路径——测试用
/// [fileToReturn] 提供真实字节来模拟。默认 'fail'（无位图）。
///
/// 返回 [ProcessOutcome] 而不是 [ProcessResult]：后者是 final class，测试
/// 无法伪造实现，所以服务的注入形状用的是自有记录类型。
Future<ProcessOutcome> Function(String, List<String>) fakeRunnerOk({
  String stdoutText = 'ok',
  File? fileToReturn,
}) {
  return (exe, args) {
    if (fileToReturn != null && stdoutText == 'ok') {
      final script = args.length > 1 ? args[1] : '';
      final match =
          RegExp(r'/tmp/v8_clipboard_paste_\d+\.png').firstMatch(script);
      if (match != null) {
        File(match.group(0)!).writeAsBytesSync(fileToReturn.readAsBytesSync());
      }
    }
    return Future.value(
      ProcessOutcome(exitCode: 0, stdout: stdoutText, stderr: ''),
    );
  };
}


/// 最小 Client 替身：只实现服务用到的那一条路径。
class _StubClient implements http.Client {
  _StubClient(this.handler);

  final Future<http.Response> Function(http.Request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final plain = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request && request.body.isNotEmpty) {
      plain.body = request.body;
    }
    final response = await handler(plain);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: plain,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      throw UnimplementedError();

  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      throw UnimplementedError();

  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      throw UnimplementedError();

  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      throw UnimplementedError();

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  void close() {}
}
