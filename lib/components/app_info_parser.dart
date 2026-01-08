import 'dart:io';
import 'package:flutter/services.dart';

class AppInfoParser {
  static Future<Map<String, String>?> parseAppBundle(String appPath) async {
    print('开始解析app bundle: $appPath');
    try {
      // 通过MethodChannel调用原生代码解析.app包
      const MethodChannel channel = MethodChannel('app_package_browser');

      print('准备调用原生方法readInfoPlist');
      final result = await channel.invokeMethod('readInfoPlist', {
        'appPath': appPath,
      });
      print('readInfoPlist返回结果: $result');

      // 确保结果是Map类型
      if (result is! Map) {
        print('解析应用程序包失败: 返回结果类型错误 ${result.runtimeType}');
        return null;
      }

      // 将结果转换为Map<String, dynamic>
      Map<String, dynamic> resultMap = Map<String, dynamic>.from(result);

      String bundleId = resultMap['bundleId'] ?? '';
      String bundleName = resultMap['name'] ?? '';
      String bundleVersion = resultMap['version'] ?? '';

      print(
        '解析到的信息 - Bundle ID: $bundleId, Bundle Name: $bundleName, Version: $bundleVersion',
      );

      // 查找Resources目录下的icns文件
      String resourcesPath = '$appPath/Contents/Resources';
      print('正在查找资源文件: $resourcesPath');
      String? iconPath = await _findIcnsFile(resourcesPath);
      print('找到图标路径: $iconPath');

      if (bundleId.isNotEmpty && bundleName.isNotEmpty) {
        var returnResult = {
          'bundleId': bundleId,
          'bundleName': bundleName,
          'bundleVersion': bundleVersion,
          'iconPath': iconPath ?? '',
          'appType': 'Utils',
          'appPath': appPath,
        };
        print('返回解析结果: $returnResult');
        return returnResult;
      } else {
        print('Bundle ID 或 Bundle Name 为空，解析失败');
      }
    } catch (e) {
      print('解析应用程序包失败: $e');
      print('错误堆栈: ');
      print(e.toString());
      // 即使出错也返回null而不是抛出异常，以便上层处理
      return null;
    }

    print('解析结束，返回null');
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
