import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as encrypt_package;
import 'package:cryptography/cryptography.dart' as crypto_package;
import 'dart:math' as math;
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

// 限流相关变量
DateTime? _lastRequestTime;
int _requestCount = 0;

class KmaPackageUtil {
  /// 将指定目录压缩为 ZIP 文件
  static Future<void> createZipFromDirectory(
    String sourceDir,
    String outputPath,
  ) async {
    Directory dir = Directory(sourceDir);
    List<FileSystemEntity> files = dir.listSync(recursive: true);

    Archive archive = Archive();

    for (FileSystemEntity file in files) {
      if (file is File) {
        String filePath = file.path;
        String relativePath = path.relative(filePath, from: sourceDir);
        List<int> data = await file.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, data.length, data));
      }
    }

    List<int> zipBytes = ZipEncoder().encode(archive)!;
    await File(outputPath).writeAsBytes(zipBytes);
  }

  /// 使用 AES-256-GCM 加密文件（使用 PBKDF2 派生密钥）
  static Future<void> encryptFile(
    String inputPath,
    String outputPath,
    String rawKey, [
    Function(String)? logCallback,
  ]) async {
    logCallback?.call('开始加密文件: $inputPath -> $outputPath');
    List<int> fileBytes = await File(inputPath).readAsBytes();
    logCallback?.call('已读取文件，大小: ${fileBytes.length} 字节');

    // 生成 16 字节随机盐值
    final salt = _generateRandomBytes(16);
    logCallback?.call('已生成随机盐值，长度: ${salt.length} 字节');

    // 使用 PBKDF2 对 rawKey + salt 进行派生，生成 32 字节 AES-256 密钥
    final aesKeyList = await _deriveKeyWithPbkdf2(rawKey, salt);
    final aesKey = Uint8List.fromList(aesKeyList);
    logCallback?.call('已派生 AES 密钥，长度: ${aesKey.length} 字节');

    // 使用派生的密钥进行 AES-256-GCM 加密
    final key = encrypt_package.Key(aesKey);
    final iv = encrypt_package.IV.fromSecureRandom(
      12,
    ); // GCM recommended IV size is 12 bytes
    logCallback?.call('已生成随机 IV，长度: ${iv.bytes.length} 字节');

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );
    logCallback?.call('已创建加密器');

    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);
    logCallback?.call('已加密数据，加密后大小: ${encrypted.bytes.length} 字节');

    // 构建输出格式：[盐值(16字节) + IV(12字节) + 加密数据]
    final result = <int>[...salt, ...iv.bytes, ...encrypted.bytes];
    logCallback?.call('构建最终数据，总长度: ${result.length} 字节');

    await File(outputPath).writeAsBytes(result);
    logCallback?.call('已写入加密文件: $outputPath');
  }

  /// 解密 AES-256-GCM 加密的文件（使用 PBKDF2 派生密钥）
  static Future<void> decryptFile(
    String inputPath,
    String outputPath,
    String rawKey, [
    Function(String)? logCallback,
  ]) async {
    logCallback?.call('开始解密文件: $inputPath -> $outputPath');
    List<int> fileBytes = await File(inputPath).readAsBytes();
    logCallback?.call('已读取加密文件，大小: ${fileBytes.length} 字节');

    // 提取盐值（前16字节）、IV（接下来12字节）和加密数据
    if (fileBytes.length < 28) {
      // 16 + 12 = 28
      logCallback?.call('错误：加密文件格式错误：长度不足，实际长度: ${fileBytes.length}');
      throw Exception('加密文件格式错误：长度不足');
    }

    List<int> salt = fileBytes.sublist(0, 16);
    List<int> ivBytes = fileBytes.sublist(16, 28);
    List<int> encryptedData = fileBytes.sublist(28);
    logCallback?.call(
      '已提取盐值: ${salt.length} 字节, IV: ${ivBytes.length} 字节, 加密数据: ${encryptedData.length} 字节',
    );

    // 使用 PBKDF2 派生密钥
    final aesKeyList = await _deriveKeyWithPbkdf2(rawKey, salt);
    final aesKey = Uint8List.fromList(aesKeyList);
    logCallback?.call('已派生 AES 解密密钥，长度: ${aesKey.length} 字节');

    // 使用派生的密钥进行解密
    final key = encrypt_package.Key(aesKey);
    final iv = encrypt_package.IV(Uint8List.fromList(ivBytes));
    logCallback?.call('已创建解密 IV，长度: ${iv.bytes.length} 字节');

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );
    logCallback?.call('已创建解密器');

    final decrypted = encrypter.decryptBytes(
      encrypt_package.Encrypted(Uint8List.fromList(encryptedData)),
      iv: iv,
    );
    logCallback?.call('已解密数据，解密后大小: ${decrypted.length} 字节');

    await File(outputPath).writeAsBytes(decrypted);
    logCallback?.call('已写入解密文件: $outputPath');
  }

  /// 使用 PBKDF2 派生密钥
  static Future<List<int>> _deriveKeyWithPbkdf2(
    String rawKey,
    List<int> salt,
  ) async {
    // 使用 cryptography 包的 PBKDF2 进行密钥派生
    final algorithm = crypto_package.Pbkdf2(
      macAlgorithm: crypto_package.Hmac.sha256(),
      iterations: 16384,
      bits: 256, // 32 bytes
    );

    final key = await algorithm.deriveKey(
      secretKey: crypto_package.SecretKey(
        Uint8List.fromList(utf8.encode(rawKey)),
      ),
      nonce: Uint8List.fromList(salt),
    );

    return await key.extractBytes();
  }

  /// 生成随机字节数组
  static Uint8List _generateRandomBytes(int length) {
    final random = math.Random.secure();
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = random.nextInt(256);
    }
    return result;
  }

  /// 生成 KMA 包（压缩并加密）
  static Future<String> createKmaPackage({
    required String sourceDir,
    required String outputPath,
    required String password,
  }) async {
    String tempZipPath = '${outputPath}.tmp.zip';

    try {
      // 压缩目录
      await createZipFromDirectory(sourceDir, tempZipPath);

      // 加密 ZIP 文件
      await encryptFile(tempZipPath, outputPath, password);

      // 删除临时 ZIP 文件
      await File(tempZipPath).delete();

      return outputPath;
    } catch (e) {
      // 如果出错，清理临时文件
      if (await File(tempZipPath).exists()) {
        await File(tempZipPath).delete();
      }
      rethrow;
    }
  }

  /// 解压 KMA 包（解密并解压缩）
  static Future<String> extractKmaPackage({
    required String inputPath,
    required String outputDir,
    required String password,
  }) async {
    String tempDecryptedPath = '${outputDir}/temp_decrypted.zip';

    try {
      // 解密 KMA 文件
      await decryptFile(inputPath, tempDecryptedPath, password);

      // 解压缩 ZIP 文件到输出目录
      await extractZipToDirectory(tempDecryptedPath, outputDir);

      // 删除临时解密文件
      await File(tempDecryptedPath).delete();

      return outputDir;
    } catch (e) {
      // 如果出错，清理临时文件
      if (await File(tempDecryptedPath).exists()) {
        await File(tempDecryptedPath).delete();
      }
      rethrow;
    }
  }

  /// 解压缩 ZIP 文件到指定目录
  static Future<void> extractZipToDirectory(
    String zipPath,
    String outputDir,
  ) async {
    List<int> zipBytes = await File(zipPath).readAsBytes();
    Archive archive = ZipDecoder().decodeBytes(zipBytes);

    // 确保输出目录存在
    await Directory(outputDir).create(recursive: true);

    for (ArchiveFile file in archive) {
      String filePath = path.join(outputDir, file.name);

      if (file.isFile) {
        // 确保父目录存在
        String parentDir = path.dirname(filePath);
        await Directory(parentDir).create(recursive: true);

        // 写入文件
        File(filePath).writeAsBytes(file.content as List<int>);
      } else {
        // 创建目录
        await Directory(filePath).create(recursive: true);
      }
    }
  }
}

// 翻译服务类型枚举
enum TranslationServiceType {
  baidu, // 百度翻译
  libre, // LibreTranslate
}

class TranslationUtil {
  static const String _baiduAppId = '20221103001434737'; // 百度翻译API App ID
  static const String _baiduAppKey = 'arHn_8TPwN2_vZmJAyvc'; // 百度翻译API密钥

  // LibreTranslate 服务配置
  static const String _libreTranslateUrl =
      'http://localhost:5555/translate'; // 默认本地服务地址
  static const String _libreApiKey = ''; // LibreTranslate API密钥，如果需要的话

  // 当前翻译服务类型
  static TranslationServiceType currentService = TranslationServiceType.baidu;

  // 限流相关变量
  static int _maxQps = 8; // 每秒最大请求数，默认值
  static int _intervalMs = 1000; // 时间窗口毫秒数，默认1秒
  static DateTime? _lastRequestTime;
  static int _requestCount = 0;

  // 将语言代码转换为百度格式
  static String _convertToBaiduLangCode(String lang) {
    // 百度翻译支持的语言代码映射
    Map<String, String> baiduLangMap = {
      'zh': 'zh',
      'zh_CN': 'zh',
      'zh_TW': 'cht',
      'en': 'en',
      'ja': 'jp',
      'ko': 'kor',
      'fr': 'fra',
      'de': 'de',
      'es': 'spa',
      'ru': 'ru',
      'ar': 'ara',
      'pt': 'pt',
      'hi': 'hi',
    };
    return baiduLangMap[lang] ?? lang;
  }

  // 百度翻译 API
  static Future<String> _translateWithBaidu(
    String text,
    String sourceLang,
    String targetLang, [
    Function(String)? logCallback,
  ]) async {
    if (_baiduAppId.isEmpty || _baiduAppKey.isEmpty) {
      throw Exception('百度 API Key 未设置');
    }

    // 百度翻译需要生成签名
    String salt = DateTime.now().millisecondsSinceEpoch.toString();
    String signStr = _baiduAppId + text + salt + _baiduAppKey;
    String sign = md5.convert(utf8.encode(signStr)).toString();

    logCallback?.call(
      '百度翻译请求: 翻译文本(${text.length}字符) $sourceLang -> $targetLang',
    );

    // 百度翻译API使用GET请求
    String query =
        'q=' +
        Uri.encodeComponent(text) +
        '&from=${_convertToBaiduLangCode(sourceLang)}' +
        '&to=${_convertToBaiduLangCode(targetLang)}' +
        '&appid=$_baiduAppId' +
        '&salt=$salt' +
        '&sign=$sign';

    final url = Uri.parse(
      'https://fanyi-api.baidu.com/api/trans/vip/translate?' + query,
    );

    // 添加限流，确保QPS不超过设定值
    await TranslationUtil._rateLimit();
    // 增加日志打印时间及调用信息
    logCallback?.call(
      '百度翻译API调用: 源语言=$sourceLang, 目标语言=$targetLang, 文本长度=${text.length}',
    );
    final response = await http.get(
      url,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['trans_result'] != null &&
          data['trans_result'] is List &&
          data['trans_result'].isNotEmpty) {
        return data['trans_result'][0]['dst'];
      } else if (data['error_code'] != null) {
        throw Exception('百度翻译错误: ${data['error_code']} - ${data['error_msg']}');
      } else {
        throw Exception('翻译失败：未返回翻译结果');
      }
    } else {
      throw Exception('百度翻译 API 错误: ${response.body}');
    }
  }

  // 根据翻译服务类型转换语言代码
  static String _convertLangCodeForService(
    String lang,
    TranslationServiceType service,
  ) {
    if (service == TranslationServiceType.libre) {
      // LibreTranslate对中文有特殊要求
      if (lang == 'zh_CN') {
        return 'zh-Hans'; // 简体中文
      } else if (lang == 'zh_TW') {
        return 'zh-Hant'; // 繁体中文
      }
    } else if (service == TranslationServiceType.baidu) {
      // 百度翻译使用标准代码，但需要映射
      if (lang == 'zh-Hans') {
        return 'zh_CN'; // 简体中文
      } else if (lang == 'zh-Hant') {
        return 'zh_TW'; // 繁体中文
      }
    }
    // 其他语言保持不变
    return lang;
  }

  // LibreTranslate 翻译 API
  static Future<String> _translateWithLibre(
    String text,
    String sourceLang,
    String targetLang, [
    Function(String)? logCallback,
  ]) async {
    logCallback?.call(
      'LibreTranslate请求: 翻译文本(${text.length}字符) $sourceLang -> $targetLang',
    );

    try {
      // 转换语言代码为LibreTranslate格式
      String libreSourceLang = _convertLangCodeForService(
        sourceLang,
        TranslationServiceType.libre,
      );
      String libreTargetLang = _convertLangCodeForService(
        targetLang,
        TranslationServiceType.libre,
      );

      final requestBody = {
        'q': text,
        'source': libreSourceLang,
        'target': libreTargetLang,
        'format': 'text',
        'alternatives': 3,
        'api_key': _libreApiKey,
      };

      logCallback?.call(
        'LibreTranslate API调用: 源语言=$libreSourceLang, 目标语言=$libreTargetLang, 文本长度=${text.length}',
      );

      // 添加限流，确保QPS不超过设定值
      await _rateLimit();

      final response = await http.post(
        Uri.parse(_libreTranslateUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['translatedText'] != null) {
          return data['translatedText'];
        } else {
          throw Exception('LibreTranslate: 未返回翻译结果');
        }
      } else {
        throw Exception(
          'LibreTranslate API 错误: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('LibreTranslate 翻译失败: $e');
    }
  }

  // 翻译文本
  static Future<String> translateText(
    String text,
    String sourceLang,
    String targetLang, [
    Function(String)? logCallback,
  ]) async {
    if (!text.trim().isNotEmpty) return text; // 如果文本为空，直接返回

    try {
      switch (currentService) {
        case TranslationServiceType.baidu:
          return await _translateWithBaidu(
            text,
            sourceLang,
            targetLang,
            logCallback,
          );
        case TranslationServiceType.libre:
          return await _translateWithLibre(
            text,
            sourceLang,
            targetLang,
            logCallback,
          );
      }
    } catch (e) {
      logCallback?.call('翻译失败: $e');
      // 翻译失败时返回原文
      return text;
    }
  }

  // 批量翻译文本
  static Future<List<String>> translateBatch(
    List<String> texts,
    String sourceLang,
    String targetLang, [
    Function(String)? logCallback,
  ]) async {
    List<String> results = [];

    for (int i = 0; i < texts.length; i++) {
      String text = texts[i];
      logCallback?.call('正在翻译文本 $i/${texts.length}: ${text.length} 字符');
      String translated = await translateText(
        text,
        sourceLang,
        targetLang,
        logCallback,
      );
      results.add(translated);
    }

    return results;
  }

  // 翻译快捷键
  static Future<Map<String, dynamic>> translateShortcuts(
    List<Map<String, dynamic>> shortcuts,
    String sourceLang,
    String targetLang, [
    Function(String)? logCallback,
  ]) async {
    List<Map<String, dynamic>> translatedShortcuts = [];

    for (int i = 0; i < shortcuts.length; i++) {
      Map<String, dynamic> shortcut = shortcuts[i];
      logCallback?.call(
        '正在翻译快捷键 $i/${shortcuts.length}: ${shortcut['name'] ?? 'unnamed'}',
      );

      Map<String, dynamic> translatedShortcut = {};

      // 复制原始字段
      translatedShortcut.addAll(shortcut);

      // 翻译特定字段
      if (shortcut['name'] != null && shortcut['name'].isNotEmpty) {
        translatedShortcut['name'] = await translateText(
          shortcut['name'],
          sourceLang,
          targetLang,
          logCallback,
        );
      }

      // 翻译描述
      if (shortcut['description'] != null &&
          shortcut['description'].isNotEmpty) {
        translatedShortcut['description'] = await translateText(
          shortcut['description'],
          sourceLang,
          targetLang,
          logCallback,
        );
      }

      // 翻译 when 字段
      if (shortcut['when'] != null && shortcut['when'].isNotEmpty) {
        translatedShortcut['when'] = await translateText(
          shortcut['when'],
          sourceLang,
          targetLang,
          logCallback,
        );
      }

      translatedShortcuts.add(translatedShortcut);
    }

    return {'shortcuts': translatedShortcuts};
  }

  // 翻译应用信息
  static Future<Map<String, dynamic>> translateAppInfo(
    String appLocalizedName,
    String name,
    String category,
    String sourceLang,
    String targetLang, [
    Function(String)? logCallback,
  ]) async {
    List<String> textsToTranslate = [appLocalizedName, category];
    List<String> translatedTexts = await translateBatch(
      textsToTranslate,
      sourceLang, // 使用配置的源语言
      targetLang,
      logCallback,
    );

    return {
      'appLocalizedName': translatedTexts[0],
      'appShortName': name, // 保持原始值，不进行翻译
      'category': translatedTexts[1],
    };
  }

  // 限流函数，确保QPS不超过设定值
  static Future<void> _rateLimit() async {
    DateTime now = DateTime.now();
    int nowMs = now.millisecondsSinceEpoch;
    int lastMs = _lastRequestTime?.millisecondsSinceEpoch ?? 0;

    // 如果在同一个时间窗口内，检查请求数量
    if (nowMs - lastMs < _intervalMs) {
      if (_requestCount >= _maxQps) {
        // 等待到下一个时间窗口
        int waitTime = _intervalMs - (nowMs - lastMs);
        await Future.delayed(Duration(milliseconds: waitTime));
        _requestCount = 0;
        _lastRequestTime = DateTime.now();
      }
    } else {
      // 进入新的时间窗口，重置计数器
      _requestCount = 0;
      _lastRequestTime = now;
    }

    _requestCount++;
  }

  // 设置限流参数
  static void setRateLimitConfig(int maxQps, int intervalMs) {
    _maxQps = maxQps;
    _intervalMs = intervalMs;
  }

  // 获取当前限流配置
  static Map<String, int> getRateLimitConfig() {
    return {'maxQps': _maxQps, 'intervalMs': _intervalMs};
  }
}
