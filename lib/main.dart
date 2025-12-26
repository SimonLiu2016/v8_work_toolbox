import 'package:flutter/material.dart';

// 导入新工具页面
import 'bc_config_tool.dart';
import 'bc_config_shell.dart';
import 'batch_rename_tool.dart';
import 'folder_compare_tool.dart';
import 'kma_package_tool.dart';

void main() {
  runApp(const FileToolsApp());
}

class FileToolsApp extends StatelessWidget {
  const FileToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文件工具箱',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainToolsPage(),
    );
  }
}

class MainToolsPage extends StatelessWidget {
  const MainToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件工具箱'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildToolCard(
              context,
              title: 'BC配置工具',
              subtitle: '修改Beyond Compare配置',
              icon: Icons.settings,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BcConfigHomePage(),
                  ),
                );
              },
            ),
            _buildToolCard(
              context,
              title: '批量重命名',
              subtitle: '按规则批量重命名文件',
              icon: Icons.text_format,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BatchRenameHomePage(),
                  ),
                );
              },
            ),
            // 可以在这里添加更多工具卡片
            _buildToolCard(
              context,
              title: '文件夹对比',
              subtitle: '对比两个文件夹中的文件',
              icon: Icons.compare,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FolderCompareHomePage(),
                  ),
                );
              },
            ),
            _buildToolCard(
              context,
              title: 'BC脚本管理',
              subtitle: '管理BC配置脚本',
              icon: Icons.code,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BcConfigShellPage(),
                  ),
                );
              },
            ),
            _buildToolCard(
              context,
              title: 'KMA 包生成',
              subtitle: '生成加密的 KMA 包',
              icon: Icons.archive,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KmaPackageToolPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).primaryColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BcConfigApp extends StatelessWidget {
  const BcConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beyond Compare 配置工具',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const BcConfigHomePage(),
    );
  }
}
