import 'dart:io';
import 'package:flutter/services.dart';

class AppInfoParser {
  static Future<Map<String, String>?> parseAppBundle(String appPath) async {
    try {
      // 通过MethodChannel调用原生代码解析.app包
      const MethodChannel channel = MethodChannel('app_package_browser');

      final result = await channel.invokeMethod('readInfoPlist', {'appPath': appPath});
      
      // 确保结果是Map类型
      if (result is! Map) {
        print('解析应用程序包失败: 返回结果类型错误');
        return null;
      }
      
      // 将结果转换为Map<String, dynamic>
      Map<String, dynamic> resultMap = Map<String, dynamic>.from(result);
      
      String bundleId = resultMap['bundleId'] ?? '';
      String bundleName = resultMap['name'] ?? '';
      String bundleVersion = resultMap['version'] ?? '';

      // 查找Resources目录下的icns文件
      String resourcesPath = '\$appPath/Contents/Resources';
      String? iconPath = await _findIcnsFile(resourcesPath);

      if (bundleId.isNotEmpty && bundleName.isNotEmpty) {
        return {
          'bundleId': bundleId,
          'bundleName': bundleName,
          'bundleVersion': bundleVersion,
          'iconPath': iconPath ?? '',
          'appType': 'Utils',
        };
      }
    } catch (e) {
      print('解析应用程序包失败: \$e');
      // 即使出错也返回null而不是抛出异常，以便上层处理
      return null;
    }

    return null;
  }

  static Future<String?> _findIcnsFile(String resourcesPath) async {
    Directory resourcesDir = Directory(resourcesPath);

    if (!await resourcesDir.exists()) {
      return null;
    }

    List<FileSystemEntity> files = await resourcesDir.list().toList();

    // 查找.icns文件
    for (FileSystemEntity file in files) {
      if (file is File && file.path.toLowerCase().endsWith('.icns')) {
        // 返回相对于appBundle的路径
        String relativePath = file.path
            .split('/')
            .skipWhile((part) => part != 'Resources')
            .join('/');
        return relativePath;
      }
    }

    return null;
  }
}
