import 'dart:io';
import 'dart:convert';

void main() async {
  // 定义 Beyond Compare 配置文件路径
  String bcDir = '/Users/simon/Library/ApplicationSupport/Beyond Compare';

  try {
    // 步骤1: 修改 BCState.xml 文件
    await modifyBCStateFile('$bcDir/BCState.xml');

    // 步骤2: 修改 BCSessions.xml 文件
    await modifyBCSessionsFile('$bcDir/BCSessions.xml');

    // 步骤3: 启动 Beyond Compare
    await launchBeyondCompare();

    print('所有操作已完成！');
  } catch (e) {
    print('执行过程中出现错误: $e');
  }
}

/// 修改 BCState.xml 文件，删除 TCheckForUpdatesState 中的 CheckID 和 LastChecked
Future<void> modifyBCStateFile(String filePath) async {
  print('正在处理 BCState.xml 文件...');

  File file = File(filePath);
  if (!await file.exists()) {
    throw Exception('文件不存在: $filePath');
  }

  String content = await file.readAsString();

  // 使用正则表达式删除 CheckID 和 LastChecked 标签
  content = content.replaceAll(RegExp(r'<CheckID[^>]*>\s*'), '');
  content = content.replaceAll(RegExp(r'<LastChecked[^>]*>\s*'), '');

  // 写入修改后的内容
  await file.writeAsString(content);
  print('BCState.xml 文件已更新');
}

/// 修改 BCSessions.xml 文件，删除 BCSessions 标签中的 Flags 属性
Future<void> modifyBCSessionsFile(String filePath) async {
  print('正在处理 BCSessions.xml 文件...');

  File file = File(filePath);
  if (!await file.exists()) {
    throw Exception('文件不存在: $filePath');
  }

  String content = await file.readAsString();

  // 使用正则表达式删除 Flags 属性
  content = content.replaceAll(RegExp(r'Flags="[^"]*"\s*'), '');

  // 写入修改后的内容
  await file.writeAsString(content);
  print('BCSessions.xml 文件已更新');
}

/// 启动 Beyond Compare 应用程序
Future<void> launchBeyondCompare() async {
  print('正在启动 Beyond Compare...');

  // macOS 中启动应用程序的命令
  ProcessResult result = await Process.run('open', ['-a', 'Beyond Compare']);

  if (result.exitCode == 0) {
    print('Beyond Compare 已成功启动');
  } else {
    print('启动 Beyond Compare 时出现错误: ${result.stderr}');
  }
}
