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
    String rawKey,
  ) async {
    print('开始加密文件: $inputPath -> $outputPath');
    List<int> fileBytes = await File(inputPath).readAsBytes();
    print('已读取文件，大小: ${fileBytes.length} 字节');

    // 生成 16 字节随机盐值
    final salt = _generateRandomBytes(16);
    print('已生成随机盐值，长度: ${salt.length} 字节');

    // 使用 PBKDF2 对 rawKey + salt 进行派生，生成 32 字节 AES-256 密钥
    final aesKeyList = await _deriveKeyWithPbkdf2(rawKey, salt);
    final aesKey = Uint8List.fromList(aesKeyList);
    print('已派生 AES 密钥，长度: ${aesKey.length} 字节');

    // 使用派生的密钥进行 AES-256-GCM 加密
    final key = encrypt_package.Key(aesKey);
    final iv = encrypt_package.IV.fromSecureRandom(
      12,
    ); // GCM recommended IV size is 12 bytes
    print('已生成随机 IV，长度: ${iv.bytes.length} 字节');

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );
    print('已创建加密器');

    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);
    print('已加密数据，加密后大小: ${encrypted.bytes.length} 字节');

    // 构建输出格式：[盐值(16字节) + IV(12字节) + 加密数据]
    final result = <int>[...salt, ...iv.bytes, ...encrypted.bytes];
    print('构建最终数据，总长度: ${result.length} 字节');

    await File(outputPath).writeAsBytes(result);
    print('已写入加密文件: $outputPath');
  }

  /// 解密 AES-256-GCM 加密的文件（使用 PBKDF2 派生密钥）
  static Future<void> decryptFile(
    String inputPath,
    String outputPath,
    String rawKey,
  ) async {
    print('开始解密文件: $inputPath -> $outputPath');
    List<int> fileBytes = await File(inputPath).readAsBytes();
    print('已读取加密文件，大小: ${fileBytes.length} 字节');

    // 提取盐值（前16字节）、IV（接下来12字节）和加密数据
    if (fileBytes.length < 28) {
      // 16 + 12 = 28
      print('错误：加密文件格式错误：长度不足，实际长度: ${fileBytes.length}');
      throw Exception('加密文件格式错误：长度不足');
    }

    List<int> salt = fileBytes.sublist(0, 16);
    List<int> ivBytes = fileBytes.sublist(16, 28);
    List<int> encryptedData = fileBytes.sublist(28);
    print(
      '已提取盐值: ${salt.length} 字节, IV: ${ivBytes.length} 字节, 加密数据: ${encryptedData.length} 字节',
    );

    // 使用 PBKDF2 派生密钥
    final aesKeyList = await _deriveKeyWithPbkdf2(rawKey, salt);
    final aesKey = Uint8List.fromList(aesKeyList);
    print('已派生 AES 解密密钥，长度: ${aesKey.length} 字节');

    // 使用派生的密钥进行解密
    final key = encrypt_package.Key(aesKey);
    final iv = encrypt_package.IV(Uint8List.fromList(ivBytes));
    print('已创建解密 IV，长度: ${iv.bytes.length} 字节');

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );
    print('已创建解密器');

    final decrypted = encrypter.decryptBytes(
      encrypt_package.Encrypted(Uint8List.fromList(encryptedData)),
      iv: iv,
    );
    print('已解密数据，解密后大小: ${decrypted.length} 字节');

    await File(outputPath).writeAsBytes(decrypted);
    print('已写入解密文件: $outputPath');
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

class TranslationUtil {
  static const String _baiduAppId = '20221103001434737'; // 百度翻译API App ID
  static const String _baiduAppKey = 'arHn_8TPwN2_vZmJAyvc'; // 百度翻译API密钥

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
    String targetLang,
  ) async {
    if (_baiduAppId.isEmpty || _baiduAppKey.isEmpty) {
      throw Exception('百度 API Key 未设置');
    }

    // 百度翻译需要生成签名
    String salt = DateTime.now().millisecondsSinceEpoch.toString();
    String signStr = _baiduAppId + text + salt + _baiduAppKey;
    String sign = md5.convert(utf8.encode(signStr)).toString();

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

  // 翻译文本
  static Future<String> translateText(
    String text,
    String sourceLang,
    String targetLang,
  ) async {
    if (!text.trim().isNotEmpty) return text; // 如果文本为空，直接返回

    try {
      return await _translateWithBaidu(text, sourceLang, targetLang);
    } catch (e) {
      print('翻译失败: $e');
      // 翻译失败时返回原文
      return text;
    }
  }

  // 批量翻译文本
  static Future<List<String>> translateBatch(
    List<String> texts,
    String sourceLang,
    String targetLang,
  ) async {
    List<String> results = [];
    for (String text in texts) {
      results.add(await translateText(text, sourceLang, targetLang));
      // 添加延迟以避免API限制
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return results;
  }

  // 翻译快捷键数据
  static Future<Map<String, dynamic>> translateShortcuts(
    List<Map<String, dynamic>> shortcuts,
    String sourceLang,
    String targetLang,
  ) async {
    List<Map<String, dynamic>> translatedShortcuts = [];

    for (var shortcut in shortcuts) {
      Map<String, dynamic> translatedShortcut = Map.from(shortcut);

      // 翻译名称
      if (shortcut['name'] != null && shortcut['name'].isNotEmpty) {
        translatedShortcut['name'] = await translateText(
          shortcut['name'],
          sourceLang,
          targetLang,
        );
      }

      // 翻译描述
      if (shortcut['description'] != null &&
          shortcut['description'].isNotEmpty) {
        translatedShortcut['description'] = await translateText(
          shortcut['description'],
          sourceLang,
          targetLang,
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
    String targetLang,
  ) async {
    List<String> textsToTranslate = [appLocalizedName, name, category];
    List<String> translatedTexts = await translateBatch(
      textsToTranslate,
      sourceLang, // 使用配置的源语言
      targetLang,
    );

    return {
      'appLocalizedName': translatedTexts[0],
      'appShortName': translatedTexts[1],
      'category': translatedTexts[2],
    };
  }
}
