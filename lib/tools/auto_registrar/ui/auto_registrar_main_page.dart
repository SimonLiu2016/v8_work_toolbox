import 'package:flutter/material.dart';

import '../../password/vault_store.dart';
import 'account_hub_view.dart';
import 'registrar_task_console_view.dart';

class AutoRegistrarMainPage extends StatefulWidget {
  final VaultStore? vaultStore;

  const AutoRegistrarMainPage({super.key, this.vaultStore});

  @override
  State<AutoRegistrarMainPage> createState() => _AutoRegistrarMainPageState();
}

class _AutoRegistrarMainPageState extends State<AutoRegistrarMainPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final VaultStore _vaultStore;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _vaultStore = widget.vaultStore ?? VaultStore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动注册工具箱'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.rocket_launch_outlined), text: '注册任务工作台'),
            Tab(icon: Icon(Icons.folder_shared_outlined), text: '已注册账号资产库'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const RegistrarTaskConsoleView(),
          AccountHubView(vaultStore: _vaultStore),
        ],
      ),
    );
  }
}
