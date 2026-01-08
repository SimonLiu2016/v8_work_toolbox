import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_info_parser.dart';

class AppBundleSelector extends StatelessWidget {
  final Function(Map<String, String>) onAppInfoParsed;

  const AppBundleSelector({Key? key, required this.onAppInfoParsed})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _showInstructionsDialog(context),
      icon: const Icon(Icons.folder_outlined),
      label: const Text('解析应用'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _showInstructionsDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择应用'),
          content: const Text(
            '请选择一个 .app 应用程序包。在 /Applications 目录中浏览并选择所需的应用程序。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _selectAppBundle(context);
              },
              child: const Text('继续'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectAppBundle(BuildContext context) async {
    print('开始选择app bundle');
    try {
      // 通过MethodChannel调用原生代码选择.app包
      const MethodChannel channel = MethodChannel('app_package_browser');

      // 调用原生方法选择.app包
      print('调用原生方法selectAppPackage');
      final result = await channel.invokeMethod('selectAppPackage');
      print('原生方法返回结果: $result');

      // 确保结果是Map类型
      if (result is! Map) {
        print('结果类型错误: ${result.runtimeType}');
        _showErrorDialog(context, '获取应用包信息失败');
        return;
      }

      // 将结果转换为Map<String, dynamic>
      Map<String, dynamic> resultMap = Map<String, dynamic>.from(result);
      String? appPath = resultMap['appPath'];
      print('获取到appPath: $appPath');

      if (appPath != null) {
        print('调用解析对话框');
        // 弹出解析进度对话框
        await _showParsingDialog(context, appPath);
      } else {
        print('appPath为空');
        _showErrorDialog(context, '未选择任何应用包');
      }
    } on PlatformException catch (e) {
      print('PlatformException: $e');
      _showErrorDialog(context, '选择应用包时出错: ${e.message}');
    }
  }

  Future<void> _showParsingDialog(BuildContext context, String appPath) async {
    // 在后台解析应用信息
    try {
      Map<String, String>? result = await AppInfoParser.parseAppBundle(appPath);

      if (result != null) {
        // 调用回调函数传递解析结果
        onAppInfoParsed(result);
      } else {
        _showErrorDialog(context, '未能解析到应用信息');
      }
    } catch (e) {
      _showErrorDialog(context, '解析失败: $e');
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('错误'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
