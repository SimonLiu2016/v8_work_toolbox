import 'dart:io';
import 'dart:convert';

// 添加 Platform 导入
import 'dart:io' show Platform;

void main() async {
  // 定义 Beyond Compare 配置文件路径
  String bcDir =
      '${Platform.environment['HOME']}/Library/Application Support/Beyond Compare';

  print('Beyond Compare 配置修复工具');
  print('==========================');
  print('目标目录: $bcDir');

  try {
    // 检查目录是否存在
    Directory dir = Directory(bcDir);
    if (!await dir.exists()) {
      print('错误: Beyond Compare 配置目录不存在');
      print('请确保 Beyond Compare 已安装');
      return;
    }

    // 步骤1: 修改 BCState.xml 文件
    await modifyBCStateFile('$bcDir/BCState.xml');

    // 步骤2: 修改 BCSessions.xml 文件
    await modifyBCSessionsFile('$bcDir/BCSessions.xml');

    // 步骤3: 启动 Beyond Compare
    await launchBeyondCompare();

    print('所有操作已完成！');
    print('');
    print('提示: 如果遇到权限问题，请尝试以下方法:');
    print('1. 在终端中运行此脚本: ./fix_bc_config.sh');
    print('2. 或者在系统偏好设置中为应用程序授权');
  } on PathAccessException catch (e) {
    handlePermissionError(bcDir);
  } catch (e) {
    // 检查是否为权限错误
    if (e.toString().contains('Operation not permitted') ||
        e.toString().contains('Permission denied')) {
      handlePermissionError(bcDir);
    } else {
      print('执行过程中出现错误: $e');
    }
  }
}

/// 处理权限错误
void handlePermissionError(String bcDir) {
  print('权限错误: 无法访问 Beyond Compare 配置目录');
  print('这是 macOS 的安全机制导致的限制。');
  print('');
  print('解决方案:');
  print('1. 使用终端脚本 (推荐):');
  print('   打开终端并运行: ./fix_bc_config.sh');
  print('');
  print('2. 通过系统偏好设置授权:');
  print('   - 打开系统偏好设置 > 安全性与隐私 > 隐私');
  print('   - 在左侧选择"文件和文件夹"或"完全磁盘访问权限"');
  print('   - 为本应用程序添加访问权限');
  print('');
  print('3. 手动修改配置文件:');
  print('   打开终端并运行以下命令:');
  print('   cd "$bcDir"');
  print('   sed -i "" "/<CheckID/d" BCState.xml');
  print('   sed -i "" "/<LastChecked/d" BCState.xml');
  print('   sed -i "" "s/Flags=\\"[^\\"]*\\" //" BCSessions.xml');
}

/// 修改 BCState.xml 文件，删除 TCheckForUpdatesState 中的 CheckID 和 LastChecked
Future<void> modifyBCStateFile(String filePath) async {
  print('正在处理 BCState.xml 文件...');

  File file = File(filePath);
  if (!await file.exists()) {
    print('警告: BCState.xml 文件不存在: $filePath');
    return;
  }

  // 尝试创建备份文件
  try {
    await file.copy('$filePath.bak');
    print('已创建 BCState.xml 备份文件');
  } catch (e) {
    print('警告: 无法创建备份文件: $e');
  }

  String content = await file.readAsString();

  // 使用正则表达式删除 CheckID 和 LastChecked 标签
  content = content.replaceAll(RegExp(r'<CheckID[^>]*>\s*'), '');
  content = content.replaceAll(RegExp(r'<LastChecked[^>]*>\s*'), '');

  // 写入修改后的内容
  await file.writeAsString(content);
  print('✓ BCState.xml 文件已更新');
}

/// 修改 BCSessions.xml 文件，删除 BCSessions 标签中的 Flags 属性
Future<void> modifyBCSessionsFile(String filePath) async {
  print('正在处理 BCSessions.xml 文件...');

  File file = File(filePath);
  if (!await file.exists()) {
    print('警告: BCSessions.xml 文件不存在: $filePath');
    return;
  }

  // 尝试创建备份文件
  try {
    await file.copy('$filePath.bak');
    print('已创建 BCSessions.xml 备份文件');
  } catch (e) {
    print('警告: 无法创建备份文件: $e');
  }

  String content = await file.readAsString();

  // 使用正则表达式删除 Flags 属性
  content = content.replaceAll(RegExp(r'Flags="[^"]*"\s*'), '');

  // 写入修改后的内容
  await file.writeAsString(content);
  print('✓ BCSessions.xml 文件已更新');
}

/// 启动 Beyond Compare 应用程序
Future<void> launchBeyondCompare() async {
  print('正在启动 Beyond Compare...');

  // macOS 中启动应用程序的命令
  ProcessResult result = await Process.run('open', ['-a', 'Beyond Compare']);

  if (result.exitCode == 0) {
    print('✓ Beyond Compare 已成功启动');
  } else {
    print('警告: 启动 Beyond Compare 时出现错误: ${result.stderr}');
  }
}
