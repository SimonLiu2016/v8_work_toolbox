import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import '../services/argocd_service.dart';
import '../services/gitlab_client.dart';
import '../services/jenkins_client.dart';

class OpsDevOpsView extends StatefulWidget {
  const OpsDevOpsView({super.key});

  @override
  State<OpsDevOpsView> createState() => _OpsDevOpsViewState();
}

class _OpsDevOpsViewState extends State<OpsDevOpsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppTheme.bgSidebar,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: AppTheme.accent,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: const [
              Tab(
                icon: Icon(Icons.settings_input_component_rounded),
                text: '连接配置',
              ),
              Tab(icon: Icon(Icons.folder_copy_outlined), text: '项目管理'),
              Tab(icon: Icon(Icons.fork_right_rounded), text: '批量操作'),
              Tab(icon: Icon(Icons.cloud_sync_rounded), text: 'ArgoCD 监控'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _ConnectionConfigTab(),
              _GitLabProjectsTab(),
              _BatchOperationsTab(),
              OpsArgoCdMonitorTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 1: 连接配置
// ============================================================================

class _ConnectionConfigTab extends StatefulWidget {
  const _ConnectionConfigTab();

  @override
  State<_ConnectionConfigTab> createState() => _ConnectionConfigTabState();
}

class _ConnectionConfigTabState extends State<_ConnectionConfigTab> {
  List<DevOpsConnection> _connections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    setState(() => _loading = true);
    final list = await OpsDatabase.instance.loadConnections();
    if (mounted) {
      setState(() {
        _connections = list;
        _loading = false;
      });
    }
  }

  void _showEditDialog([DevOpsConnection? conn]) {
    final nameCtrl = TextEditingController(text: conn?.name ?? '');
    String connType = conn?.connType ?? 'gitlab';
    final config = conn?.getConfigMap() ?? {};
    final urlCtrl = TextEditingController(
      text: config['url']?.toString() ?? '',
    );
    final userCtrl = TextEditingController(
      text: config['username']?.toString() ?? '',
    );
    // 编辑态不回填已存凭据：留空即保存时保持原值（见 change spec「编辑既有凭据时留空表示保持原值」）。
    final passCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    bool passVisible = false;
    bool tokenVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: Text(
              conn == null ? '添加 DevOps 连接' : '编辑连接',
              style: AppTheme.fontTitle,
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: connType,
                      dropdownColor: AppTheme.bgCard,
                      decoration: const InputDecoration(labelText: '服务类型'),
                      items: const [
                        DropdownMenuItem(
                          value: 'gitlab',
                          child: Text('GitLab'),
                        ),
                        DropdownMenuItem(
                          value: 'jenkins',
                          child: Text('Jenkins'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => connType = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '连接标识名称'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: '实例地址 (URL)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(labelText: '用户名'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: !passVisible,
                      decoration: InputDecoration(
                        labelText: connType == 'jenkins'
                            ? 'API Token / 密码'
                            : '密码',
                        helperText: conn == null ? null : '留空则保持原有凭据不变',
                        suffixIcon: IconButton(
                          icon: Icon(
                            passVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          tooltip: passVisible ? '隐藏密码' : '显示密码',
                          onPressed: () =>
                              setDialogState(() => passVisible = !passVisible),
                        ),
                      ),
                    ),
                    if (connType == 'gitlab') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenCtrl,
                        obscureText: !tokenVisible,
                        decoration: InputDecoration(
                          labelText: 'Personal Access Token (可选，推荐)',
                          helperText: conn == null ? null : '留空则保持原有凭据不变',
                          suffixIcon: IconButton(
                            icon: Icon(
                              tokenVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 16,
                              color: AppTheme.textSecondary,
                            ),
                            tooltip: tokenVisible ? '隐藏 Token' : '显示 Token',
                            onPressed: () => setDialogState(
                              () => tokenVisible = !tokenVisible,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                child: const Text('取消'),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                child: const Text('保存'),
                onPressed: () async {
                  final enteredPass = passCtrl.text.trim();
                  final enteredToken = tokenCtrl.text.trim();
                  // 留空 → 沿用已存值；未填写 → 不写入该键。
                  final cfgMap = {
                    'url': urlCtrl.text.trim(),
                    'username': userCtrl.text.trim(),
                    'password': enteredPass.isEmpty
                        ? (config['password']?.toString() ?? '')
                        : enteredPass,
                    if (enteredToken.isNotEmpty ||
                        (conn != null && config['token'] != null))
                      'token': enteredToken.isEmpty
                          ? config['token']?.toString()
                          : enteredToken,
                  };
                  final item = DevOpsConnection(
                    id: conn?.id,
                    connType: connType,
                    name: nameCtrl.text.trim().isEmpty
                        ? urlCtrl.text.trim()
                        : nameCtrl.text.trim(),
                    config: jsonEncode(cfgMap),
                  );
                  await OpsDatabase.instance.saveConnection(item);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadConnections();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _testConnection(DevOpsConnection conn) async {
    final cfg = conn.getConfigMap();
    try {
      if (conn.connType == 'gitlab') {
        final client = GitLabClient(
          GitlabConfig(
            url: cfg['url']?.toString() ?? '',
            username: cfg['username']?.toString() ?? '',
            password: cfg['password']?.toString() ?? '',
            token: cfg['token']?.toString(),
          ),
        );
        await client.testConnection();
      } else if (conn.connType == 'jenkins') {
        final client = JenkinsClient(
          JenkinsConfig(
            url: cfg['url']?.toString() ?? '',
            username: cfg['username']?.toString() ?? '',
            token:
                cfg['password']?.toString() ?? cfg['token']?.toString() ?? '',
          ),
        );
        await client.testConnection();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接测试成功！')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接测试失败: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GitLab / Jenkins 连接实例', style: AppTheme.fontTitle),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加连接'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                onPressed: () => _showEditDialog(),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          if (_connections.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppTheme.space32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: AppTheme.borderRadiusMedium,
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: const Text(
                '尚未添加任何 DevOps 实例，请点击右上角添加。',
                style: AppTheme.fontBodySecondary,
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _connections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final conn = _connections[idx];
                  final cfg = conn.getConfigMap();
                  return Container(
                    padding: const EdgeInsets.all(AppTheme.space16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          conn.connType == 'gitlab'
                              ? Icons.source_rounded
                              : Icons.build_circle_outlined,
                          color: AppTheme.accent,
                          size: 28,
                        ),
                        const SizedBox(width: AppTheme.space16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(conn.name, style: AppTheme.fontTitle),
                              const SizedBox(height: 4),
                              Text(
                                '类型: ${conn.connType.toUpperCase()} | URL: ${cfg['url']} | 用户: ${cfg['username']}',
                                style: AppTheme.fontCaption.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _testConnection(conn),
                          child: const Text('测试连接'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _showEditDialog(conn),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.error,
                            size: 20,
                          ),
                          onPressed: () async {
                            await OpsDatabase.instance.deleteConnection(
                              conn.id,
                            );
                            _loadConnections();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tab 2: 项目管理
// ============================================================================

class _GitLabProjectsTab extends StatefulWidget {
  const _GitLabProjectsTab();

  @override
  State<_GitLabProjectsTab> createState() => _GitLabProjectsTabState();
}

class _GitLabProjectsTabState extends State<_GitLabProjectsTab> {
  List<DevOpsConnection> _gitlabConns = [];
  DevOpsConnection? _selectedConn;
  final _groupCtrl = TextEditingController();
  final _filterCtrl = TextEditingController();
  List<ProjectInfo> _queriedProjects = [];
  final Set<int> _selectedIds = {};
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadInit();
  }

  Future<void> _loadInit() async {
    final conns = await OpsDatabase.instance.loadConnections(
      connType: 'gitlab',
    );
    final selectedSaved = await OpsDatabase.instance.loadSelectedProjects();
    if (mounted) {
      setState(() {
        _gitlabConns = conns;
        if (conns.isNotEmpty) _selectedConn = conns.first;
        for (final sp in selectedSaved) {
          if (sp.projectId != null) _selectedIds.add(sp.projectId!);
        }
      });
    }
  }

  Future<void> _fetchProjects() async {
    if (_selectedConn == null) return;
    final group = _groupCtrl.text.trim();
    if (group.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 GitLab Group 名称')));
      return;
    }

    setState(() => _searching = true);
    final cfg = _selectedConn!.getConfigMap();
    final client = GitLabClient(
      GitlabConfig(
        url: cfg['url']?.toString() ?? '',
        username: cfg['username']?.toString() ?? '',
        password: cfg['password']?.toString() ?? '',
        token: cfg['token']?.toString(),
      ),
    );

    try {
      final list = await client.listGroupProjects(group);
      if (mounted) {
        setState(() {
          _queriedProjects = list;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('获取项目失败: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _saveSelected() async {
    if (_selectedConn == null) return;
    final cfg = _selectedConn!.getConfigMap();
    final gitlabUrl = cfg['url']?.toString() ?? '';
    final group = _groupCtrl.text.trim();

    final projectsToSave = _queriedProjects
        .where((p) => _selectedIds.contains(p.id))
        .map(
          (p) => DevOpsSelectedProject(
            projectName: p.name,
            projectId: p.id,
            groupName: group,
            gitlabUrl: gitlabUrl,
          ),
        )
        .toList();

    await OpsDatabase.instance.saveSelectedProjects(projectsToSave);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${projectsToSave.length} 个项目用于后续批量操作')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filterCtrl.text.trim().toLowerCase();
    final filtered = _queriedProjects.where((p) {
      if (filter.isEmpty) return true;
      return p.name.toLowerCase().contains(filter) ||
          p.pathWithNamespace.toLowerCase().contains(filter);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<DevOpsConnection>(
                  value: _selectedConn,
                  dropdownColor: AppTheme.bgCard,
                  decoration: const InputDecoration(labelText: 'GitLab 实例'),
                  items: _gitlabConns
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedConn = v),
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: TextField(
                  controller: _groupCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Group 名称',
                    hintText: '例如: core-services',
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              ElevatedButton.icon(
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('查询项目'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                onPressed: _searching ? null : _fetchProjects,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.filter_list_rounded),
                    hintText: '按名称或命名空间过滤当前列表...',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    if (_selectedIds.length == filtered.length) {
                      _selectedIds.clear();
                    } else {
                      _selectedIds.addAll(filtered.map((p) => p.id));
                    }
                  });
                },
                child: Text(
                  _selectedIds.length == filtered.length ? '取消全选' : '全选',
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text('确认选中 (${_selectedIds.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                ),
                onPressed: _selectedIds.isEmpty ? null : _saveSelected,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: AppTheme.borderRadiusMedium,
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无匹配的项目，请选择实例并输入 Group 查询。',
                        style: AppTheme.fontBodySecondary,
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: AppTheme.borderSubtle,
                      ),
                      itemBuilder: (context, idx) {
                        final p = filtered[idx];
                        final isChecked = _selectedIds.contains(p.id);
                        return CheckboxListTile(
                          value: isChecked,
                          activeColor: AppTheme.accent,
                          title: Text(p.name, style: AppTheme.fontBody),
                          subtitle: Text(
                            p.pathWithNamespace,
                            style: AppTheme.fontCaption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedIds.add(p.id);
                              } else {
                                _selectedIds.remove(p.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tab 3: 批量操作 (批量建分支 / 修改 pom / 触发 Jenkins)
// ============================================================================

class _BatchOperationsTab extends StatefulWidget {
  const _BatchOperationsTab();

  @override
  State<_BatchOperationsTab> createState() => _BatchOperationsTabState();
}

class _BatchOperationsTabState extends State<_BatchOperationsTab> {
  List<DevOpsSelectedProject> _selectedProjects = [];
  final _branchCtrl = TextEditingController(text: 'feature/');
  final _refBranchCtrl = TextEditingController(text: 'master');
  final _parentVerCtrl = TextEditingController();
  final _childVerCtrl = TextEditingController();
  final _jenkinsJobCtrl = TextEditingController();
  final _logs = <String>[];
  bool _operating = false;

  @override
  void initState() {
    super.initState();
    _loadSelected();
  }

  Future<void> _loadSelected() async {
    final list = await OpsDatabase.instance.loadSelectedProjects();
    if (mounted) setState(() => _selectedProjects = list);
  }

  void _log(String msg) {
    setState(
      () => _logs.insert(
        0,
        '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg',
      ),
    );
  }

  Future<void> _batchCreateBranch() async {
    if (_selectedProjects.isEmpty) return;
    final branch = _branchCtrl.text.trim();
    final refBranch = _refBranchCtrl.text.trim();

    setState(() => _operating = true);
    _log('开始批量创建分支: $branch (基准: $refBranch)...');

    final conns = await OpsDatabase.instance.loadConnections(
      connType: 'gitlab',
    );
    if (conns.isEmpty) {
      _log('错误: 未找到可用的 GitLab 连接配置');
      setState(() => _operating = false);
      return;
    }

    final cfg = conns.first.getConfigMap();
    final client = GitLabClient(
      GitlabConfig(
        url: cfg['url']?.toString() ?? '',
        username: cfg['username']?.toString() ?? '',
        password: cfg['password']?.toString() ?? '',
        token: cfg['token']?.toString(),
      ),
    );

    for (final p in _selectedProjects) {
      if (p.projectId == null) continue;
      try {
        await client.createBranch(p.projectId!, branch, refBranch);
        _log('✓ [${p.projectName}] 创建分支成功');
      } catch (e) {
        _log('✗ [${p.projectName}] 创建分支失败: $e');
      }
    }

    _log('批量分支创建执行完毕');
    setState(() => _operating = false);
  }

  Future<void> _batchUpdatePom() async {
    if (_selectedProjects.isEmpty) return;
    final parentVer = _parentVerCtrl.text.trim();
    final childVer = _childVerCtrl.text.trim();
    final branch = _refBranchCtrl.text.trim();

    setState(() => _operating = true);
    _log('开始批量更新 pom.xml 版本 (分支: $branch)...');

    final conns = await OpsDatabase.instance.loadConnections(
      connType: 'gitlab',
    );
    if (conns.isEmpty) {
      _log('错误: 未找到可用的 GitLab 连接配置');
      setState(() => _operating = false);
      return;
    }

    final cfg = conns.first.getConfigMap();
    final client = GitLabClient(
      GitlabConfig(
        url: cfg['url']?.toString() ?? '',
        username: cfg['username']?.toString() ?? '',
        password: cfg['password']?.toString() ?? '',
        token: cfg['token']?.toString(),
      ),
    );

    for (final p in _selectedProjects) {
      if (p.projectId == null) continue;
      try {
        await client.updatePomVersion(
          p.projectId!,
          parentVer,
          childVer,
          branch,
        );
        _log('✓ [${p.projectName}] pom.xml 版本更新成功并提交');
      } catch (e) {
        _log('✗ [${p.projectName}] 更新失败: $e');
      }
    }

    _log('批量更新 pom.xml 完成');
    setState(() => _operating = false);
  }

  Future<void> _batchTriggerJenkins() async {
    if (_selectedProjects.isEmpty) return;
    final jobName = _jenkinsJobCtrl.text.trim();
    if (jobName.isEmpty) return;

    setState(() => _operating = true);
    _log('开始触发 Jenkins 构建: $jobName...');

    final conns = await OpsDatabase.instance.loadConnections(
      connType: 'jenkins',
    );
    if (conns.isEmpty) {
      _log('错误: 未找到可用的 Jenkins 连接配置');
      setState(() => _operating = false);
      return;
    }

    final cfg = conns.first.getConfigMap();
    final client = JenkinsClient(
      JenkinsConfig(
        url: cfg['url']?.toString() ?? '',
        username: cfg['username']?.toString() ?? '',
        token: cfg['password']?.toString() ?? cfg['token']?.toString() ?? '',
      ),
    );

    for (final p in _selectedProjects) {
      try {
        await client.triggerBuild(jobName, {
          'PROJECT_NAME': p.projectName,
          'BRANCH_NAME': _refBranchCtrl.text.trim(),
        });
        _log('✓ [${p.projectName}] Jenkins 构建已触发');
      } catch (e) {
        _log('✗ [${p.projectName}] 构建触发失败: $e');
      }
    }

    _log('Jenkins 构建任务派发完毕');
    setState(() => _operating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：操作卡片
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前已选中 ${_selectedProjects.length} 个项目',
                    style: AppTheme.fontTitle,
                  ),
                  const SizedBox(height: AppTheme.space16),

                  // 分支操作
                  Container(
                    padding: const EdgeInsets.all(AppTheme.space16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '1. 批量创建分支',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _refBranchCtrl,
                                decoration: const InputDecoration(
                                  labelText: '源分支 (Ref)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _branchCtrl,
                                decoration: const InputDecoration(
                                  labelText: '新分支名称',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.fork_right_rounded, size: 18),
                          label: const Text('执行批量建分支'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                          ),
                          onPressed: _operating ? null : _batchCreateBranch,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.space16),

                  // pom.xml 操作
                  Container(
                    padding: const EdgeInsets.all(AppTheme.space16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '2. 批量修改 Maven pom.xml 版本',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _parentVerCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Parent 版本',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _childVerCtrl,
                                decoration: const InputDecoration(
                                  labelText: '当前模块版本',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit_document, size: 18),
                          label: const Text('执行版本修改并 Commit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.warning,
                          ),
                          onPressed: _operating ? null : _batchUpdatePom,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.space16),

                  // Jenkins 操作
                  Container(
                    padding: const EdgeInsets.all(AppTheme.space16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '3. 批量触发 Jenkins 构建',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _jenkinsJobCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Jenkins Job 任务名称',
                            hintText: '例如: deploy-service-job',
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('触发批量构建'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.info,
                          ),
                          onPressed: _operating ? null : _batchTriggerJenkins,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppTheme.space24),

          // 右侧：实时日志输出控制台
          Expanded(
            flex: 4,
            child: Container(
              height: 520,
              padding: const EdgeInsets.all(AppTheme.space16),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: AppTheme.borderRadiusMedium,
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('流水线执行日志', style: AppTheme.fontTitle),
                      IconButton(
                        icon: const Icon(Icons.clear_all_rounded, size: 18),
                        onPressed: () => setState(() => _logs.clear()),
                        tooltip: '清空日志',
                      ),
                    ],
                  ),
                  const Divider(color: AppTheme.borderSubtle),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, idx) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _logs[idx],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFFB0B0B0),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tab 4: ArgoCD 监控 (YAML Tag 可编辑配置表 + 后台巡检)
// ============================================================================
// ============================================================================
// Tab 4: ArgoCD 监控 (YAML Tag 可编辑配置表 + 后台巡检)
// ============================================================================

class OpsArgoCdMonitorTab extends StatefulWidget {
  const OpsArgoCdMonitorTab();

  @override
  State<OpsArgoCdMonitorTab> createState() => OpsArgoCdMonitorTabState();
}

class OpsArgoCdMonitorTabState extends State<OpsArgoCdMonitorTab> {
  List<ArgoCDEnvironment> _envs = [];
  ArgoCDEnvironment? _selectedEnv;
  List<ArgoCDTag> _tags = [];
  bool _loading = false;
  bool _savingTags = false;
  bool _blink = false;
  StreamSubscription<ArgoCdChangeEvent>? _changeSub;
  Timer? _blinkTimer;

  static const List<MapEntry<String, String>> _intervalOptions = [
    MapEntry('10', '每 10 秒'),
    MapEntry('30', '每 30 秒'),
    MapEntry('60', '每 1 分钟'),
    MapEntry('120', '每 2 分钟'),
    MapEntry('300', '每 5 分钟'),
    MapEntry('600', '每 10 分钟'),
    MapEntry('1800', '每 30 分钟'),
    MapEntry('3600', '每 1 小时'),
  ];

  @override
  void initState() {
    super.initState();
    _loadEnvs();
    _changeSub = ArgoCdService.instance.changes.listen(_onChange);
    _startBlink();
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _blinkTimer?.cancel();
    super.dispose();
  }

  // ==========================================================================
  // 环境加载与选择
  // ==========================================================================

  /// 载入环境列表，并**同时载入当前选中环境的 Tag 配置表**。
  ///
  /// 早期实现只设 `_selectedEnv` 不拉 Tag，导致：进入页面默认选中的环境
  /// 列表为空（显示「暂无 Tag 配置」）；「保存 Tag 配置」写库后重新进入
  /// 仍然为空——因为重新进入只走 `_loadEnvs`，从不读 `argocd_tags`。
  Future<void> _loadEnvs() async {
    final list = await OpsDatabase.instance.loadArgoCdEnvs();
    if (!mounted) return;
    // 沿用当前选中；未选中时取第一个。用局部变量固定目标，
    // 避免 await 期间用户已切到别的环境。
    final target = _selectedEnv ?? (list.isNotEmpty ? list.first : null);
    final tags = target == null
        ? const <ArgoCDTag>[]
        : await OpsDatabase.instance.loadArgoCdTags(target.id);
    if (!mounted) return;
    setState(() {
      _envs = list;
      _selectedEnv = target;
      _tags = tags;
    });
  }

  Future<void> _selectEnv(ArgoCDEnvironment env) async {
    setState(() {
      _selectedEnv = env;
      _tags = [];
    });
    final list = await OpsDatabase.instance.loadArgoCdTags(env.id);
    if (mounted) setState(() => _tags = list);
  }

  // ==========================================================================
  // 变更事件与闪烁动画
  // ==========================================================================

  /// 巡检写回 current_tag 后由事件流触发，仅重新读取配置表，不再重复拉取远程。
  Future<void> _onChange(ArgoCdChangeEvent e) async {
    if (!mounted || e.envId != _selectedEnv?.id) return;
    await _reloadTags();
  }

  Future<void> _reloadTags() async {
    final env = _selectedEnv;
    if (env == null) return;
    final list = await OpsDatabase.instance.loadArgoCdTags(env.id);
    if (mounted) setState(() => _tags = list);
  }

  void _startBlink() {
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted) return;
      setState(() => _blink = !_blink);
    });
  }

  static String _formatInterval(String cronExpr) {
    final secs = int.tryParse(cronExpr) ?? 0;
    if (secs < 60) return '$secs 秒';
    if (secs < 3600) return '${secs ~/ 60} 分钟';
    return '${secs ~/ 3600} 小时';
  }

  // ==========================================================================
  // 三个主操作
  // ==========================================================================

  Future<void> _refreshTags() async {
    final env = _selectedEnv;
    if (env == null) return;
    setState(() => _loading = true);
    try {
      final scan = await ArgoCdService.instance.refreshEnvTags(env, _tags);
      if (!mounted) return;
      final merged = await ArgoCdService.instance.persistMergedTags(
        env.id,
        scan.tags,
        _tags,
      );
      setState(() => _tags = merged);

      // 成功/失败/跳过都必须可见：读取失败曾被静默吞掉，导致整个目录的服务
      // 文件一个都没读到时，界面只显示"刷出 1 个空 Tag"。
      final msg = StringBuffer('已刷新 ${scan.successCount} 个 Tag');
      if (scan.failureCount > 0) {
        msg.write('，${scan.failureCount} 个文件读取失败');
      }
      if (scan.skippedNonServiceFiles > 0) {
        msg.write('，跳过 ${scan.skippedNonServiceFiles} 个非服务文件');
      }
      _toast(msg.toString(), isError: scan.failureCount > 0);
    } catch (e) {
      if (mounted) _toast('刷新失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyCurrentToTarget() {
    setState(() {
      _tags = [
        for (final t in _tags)
          ArgoCDTag(
            id: t.id,
            envId: t.envId,
            projectName: t.projectName,
            currentTag: t.currentTag,
            targetTag: t.currentTag ?? '',
            muted: t.muted,
            enabled: t.enabled,
            lastChecked: t.lastChecked,
          ),
      ];
    });
    _toast('已复制当前 Tag 到目标 Tag');
  }

  Future<void> _saveTags() async {
    final env = _selectedEnv;
    if (env == null) return;
    setState(() => _savingTags = true);
    try {
      await OpsDatabase.instance.saveArgoCdTags(env.id, _tags);
      if (!mounted) return;
      _toast('Tag 配置已保存');
    } catch (e) {
      if (mounted) _toast('保存失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingTags = false);
    }
  }

  /// 逐行编辑配置（目标 Tag / 关闭提醒 / 是否启用）。仅改内存，由「保存 Tag 配置」落库。
  void _updateTag(
    String projectName, {
    String? targetTag,
    bool? muted,
    bool? enabled,
  }) {
    setState(() {
      _tags = [
        for (final t in _tags)
          if (t.projectName == projectName)
            ArgoCDTag(
              id: t.id,
              envId: t.envId,
              projectName: t.projectName,
              currentTag: t.currentTag,
              targetTag: targetTag ?? t.targetTag,
              muted: muted ?? t.muted,
              enabled: enabled ?? t.enabled,
              lastChecked: t.lastChecked,
            )
          else
            t,
      ];
    });
  }

  // ==========================================================================
  // 环境新增 / 编辑 / 删除 / 启停
  // ==========================================================================

  void _showEnvDialog([ArgoCDEnvironment? env]) {
    final nameCtrl = TextEditingController(text: env?.name ?? '');
    final urlCtrl = TextEditingController(text: env?.gitlabUrl ?? '');
    final userCtrl = TextEditingController(text: env?.gitlabUsername ?? '');
    // 编辑态不回填已存凭据：留空即保存时保持原值（见 change spec「编辑既有凭据时留空表示保持原值」）。
    final passCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final pathCtrl = TextEditingController(text: env?.projectsPath ?? '');
    String mode = env?.monitorMode ?? 'monitor';
    String cron = env?.cronExpr ?? '300';
    bool enabled = env?.enabled ?? false;
    bool passVisible = false;
    bool tokenVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: Text(
              env == null ? '新建环境' : '编辑环境',
              style: AppTheme.fontTitle,
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '环境名称'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'GitLab URL',
                        hintText:
                            '如：https://fs-gitlab-aliyun.chowtaifook.sz/repository/config-fs-argocd-sit',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(
                        labelText: 'GitLab 用户名',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passCtrl,
                      obscureText: !passVisible,
                      decoration: InputDecoration(
                        labelText: 'GitLab 密码',
                        helperText: env == null ? null : '留空则保持原有凭据不变',
                        suffixIcon: IconButton(
                          icon: Icon(
                            passVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          tooltip: passVisible ? '隐藏密码' : '显示密码',
                          onPressed: () =>
                              setDialogState(() => passVisible = !passVisible),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: tokenCtrl,
                      obscureText: !tokenVisible,
                      decoration: InputDecoration(
                        labelText: 'Personal Access Token',
                        hintText: '可选，留空则使用用户名密码登录',
                        helperText: env == null ? null : '留空则保持原有凭据不变',
                        suffixIcon: IconButton(
                          icon: Icon(
                            tokenVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          tooltip: tokenVisible ? '隐藏 Token' : '显示 Token',
                          onPressed: () => setDialogState(
                            () => tokenVisible = !tokenVisible,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pathCtrl,
                      decoration: const InputDecoration(
                        labelText: '配置仓项目路径',
                        hintText: '/tree/master/argocd/projects',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: mode,
                      dropdownColor: AppTheme.bgCard,
                      decoration: const InputDecoration(labelText: '监控模式'),
                      items: const [
                        DropdownMenuItem(
                          value: 'monitor',
                          child: Text('监控 — 检测 Tag 变化并通知'),
                        ),
                        DropdownMenuItem(
                          value: 'lock',
                          child: Text('锁定 — 自动恢复为目标 Tag'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => mode = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: cron,
                      dropdownColor: AppTheme.bgCard,
                      decoration: const InputDecoration(labelText: '检查频率'),
                      items: _intervalOptions
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => cron = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      title: const Text('启用', style: AppTheme.fontBody),
                      onChanged: (v) => setDialogState(() => enabled = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                onPressed: () async {
                  final trimmedPath = pathCtrl.text.trim();
                  if (nameCtrl.text.trim().isEmpty ||
                      urlCtrl.text.trim().isEmpty ||
                      trimmedPath.isEmpty) {
                    _toast('环境名称、GitLab URL 与配置仓路径为必填项', isError: true);
                    return;
                  }
                  try {
                    ArgoCdService.parseProjectsPath(
                      trimmedPath,
                      urlCtrl.text.trim(),
                    );
                  } on Exception catch (e) {
                    _toast(
                      e.toString().replaceFirst('Exception: ', ''),
                      isError: true,
                    );
                    return;
                  }
                  // 访问配置仓必须至少有一种凭据；缺失时拦在保存前，而非留到巡检才失败。
                  final enteredPass = passCtrl.text.trim();
                  final enteredToken = tokenCtrl.text.trim();
                  final effectivePass = enteredPass.isEmpty
                      ? (env?.gitlabPassword ?? '')
                      : enteredPass;
                  final effectiveToken = enteredToken.isEmpty
                      ? (env?.gitlabToken ?? '')
                      : enteredToken;
                  if (effectivePass.isEmpty && effectiveToken.isEmpty) {
                    _toast(
                      '请填写 GitLab 密码或 Personal Access Token，否则无法访问配置仓',
                      isError: true,
                    );
                    return;
                  }

                  final saved = ArgoCDEnvironment(
                    id: env?.id,
                    name: nameCtrl.text.trim(),
                    gitlabUrl: urlCtrl.text.trim(),
                    gitlabUsername: userCtrl.text.trim().isEmpty
                        ? null
                        : userCtrl.text.trim(),
                    gitlabPassword: effectivePass.isEmpty
                        ? null
                        : effectivePass,
                    gitlabToken: effectiveToken.isEmpty ? null : effectiveToken,
                    projectsPath: trimmedPath,
                    monitorMode: mode,
                    enabled: enabled,
                    cronExpr: cron,
                  );
                  await OpsDatabase.instance.saveArgoCdEnv(saved);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _loadEnvs();
                  if (!mounted) return;
                  setState(() {
                    _selectedEnv = saved;
                    _tags = [];
                  });
                  final list = await OpsDatabase.instance.loadArgoCdTags(
                    saved.id,
                  );
                  if (mounted) setState(() => _tags = list);
                  _toast(env == null ? '环境已保存' : '环境已更新');
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteEnv(ArgoCDEnvironment env) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('删除监控环境', style: AppTheme.fontTitle),
        content: Text(
          '确认删除环境「${env.name}」？该操作将同时清除其名下全部 Tag 配置行，且不可恢复。',
          style: AppTheme.fontBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await OpsDatabase.instance.deleteArgoCdEnv(env.id);
    if (!mounted) return;
    setState(() {
      _envs.removeWhere((e) => e.id == env.id);
      if (_selectedEnv?.id == env.id) {
        _selectedEnv = null;
        _tags = [];
      }
    });
    _toast('已删除');
  }

  Future<void> _toggleEnv(ArgoCDEnvironment env, bool value) async {
    await OpsDatabase.instance.saveArgoCdEnv(
      ArgoCDEnvironment(
        id: env.id,
        name: env.name,
        gitlabUrl: env.gitlabUrl,
        gitlabUsername: env.gitlabUsername,
        gitlabPassword: env.gitlabPassword,
        gitlabToken: env.gitlabToken,
        projectsPath: env.projectsPath,
        monitorMode: env.monitorMode,
        enabled: value,
        cronExpr: env.cronExpr,
        createdAt: env.createdAt,
      ),
    );
    if (!mounted) return;
    setState(() {
      _envs = [
        for (final e in _envs)
          if (e.id == env.id) env.copyWith(enabled: value) else e,
      ];
    });
    _toast(value ? '监控已启用' : '监控已禁用');
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : null,
      ),
    );
  }

  // ==========================================================================
  // 构建
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final env = _selectedEnv;
    final hasMismatch = _tags.any(
      (t) =>
          (t.targetTag ?? '').isNotEmpty && (t.currentTag ?? '') != t.targetTag,
    );

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部操作栏
          Row(
            children: [
              if (env != null) ...[
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: AppTheme.space12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('刷新 Tag'),
                  onPressed: _loading ? null : _refreshTags,
                ),
                const SizedBox(width: AppTheme.space8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: const Text('复制当前到目标'),
                  onPressed: _copyCurrentToTarget,
                ),
                const SizedBox(width: AppTheme.space8),
                OutlinedButton.icon(
                  icon: _savingTags
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('保存 Tag 配置'),
                  onPressed: _savingTags ? null : _saveTags,
                ),
              ],
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新建环境'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                onPressed: () => _showEnvDialog(),
              ),
            ],
          ),

          // 环境标签列表
          const SizedBox(height: AppTheme.space16),
          Container(
            padding: const EdgeInsets.all(AppTheme.space12),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: AppTheme.borderRadiusMedium,
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: _envs.isEmpty
                ? const Text(
                    '尚未配置任何 ArgoCD 监控环境，点击右上角「新建环境」开始。',
                    style: AppTheme.fontBodySecondary,
                  )
                : Wrap(
                    spacing: AppTheme.space8,
                    runSpacing: AppTheme.space8,
                    children: [for (final e in _envs) _envChip(e)],
                  ),
          ),

          const SizedBox(height: AppTheme.space16),
          Expanded(child: _buildTagTable(env, hasMismatch)),
        ],
      ),
    );
  }

  /// 环境单行条：左侧「名称 + 模式徽章 + 信息概要」，右侧「编辑 + 启停 + 删除」。
  ///
  /// 早期版本把环境标签（chip）与详情卡分成两个区块，信息密度低且占纵向空间；
  /// 现合并为一行。多环境时仍由调用方以 Wrap 排列。
  Widget _envChip(ArgoCDEnvironment env) {
    final selected = _selectedEnv?.id == env.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accentSubtle : AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(
          color: selected ? AppTheme.accent : AppTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 左段：名称 + 模式徽章 + 信息概要
          Expanded(
            child: InkWell(
              onTap: () => _selectEnv(env),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(env.name, style: AppTheme.fontBody),
                      const SizedBox(width: 8),
                      _modeBadge(env.monitorMode),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${env.gitlabUrl}    路径: ${env.projectsPath}    '
                    '频率: ${_formatInterval(env.cronExpr)}    '
                    '状态: ${env.enabled ? '已启用' : '已停用'}',
                    style: AppTheme.fontCaption,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
          // 右段：编辑 + 启停 + 删除
          const SizedBox(width: AppTheme.space12),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('编辑环境'),
            onPressed: () => _showEnvDialog(env),
          ),
          const SizedBox(width: 8),
          Switch(
            value: env.enabled,
            activeThumbColor: AppTheme.bgSidebar,
            activeTrackColor: AppTheme.accent,
            onChanged: (v) => _toggleEnv(env, v),
          ),
          InkWell(
            borderRadius: AppTheme.borderRadiusSmall,
            onTap: () => _deleteEnv(env),
            child: Tooltip(
              message: '删除环境',
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBadge(String mode) {
    final isMonitor = mode == 'monitor';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isMonitor ? AppTheme.accentSubtle : AppTheme.warningSubtle,
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMonitor ? Icons.visibility_rounded : Icons.lock_rounded,
            size: 14,
            color: isMonitor ? AppTheme.accent : AppTheme.warning,
          ),
          const SizedBox(width: 5),
          Text(
            isMonitor ? '监控模式' : '锁定模式',
            style: AppTheme.fontCaption.copyWith(
              color: isMonitor ? AppTheme.accent : AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagTable(ArgoCDEnvironment? env, bool hasMismatch) {
    if (env == null) {
      return Center(
        child: Text('请先选择或创建一个 ArgoCD 环境', style: AppTheme.fontBodySecondary),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tags.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无 Tag 配置', style: AppTheme.fontBodySecondary),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新 Tag'),
              onPressed: _refreshTags,
            ),
          ],
        ),
      );
    }

    Widget statusCell(ArgoCDTag t) {
      final target = t.targetTag ?? '';
      if (target.isEmpty) {
        return _pill('-', AppTheme.textTertiary, AppTheme.bgInput);
      }
      final matched = (t.currentTag ?? '') == target;
      return _pill(
        matched ? '一致' : '不一致',
        matched ? AppTheme.success : AppTheme.error,
        matched ? AppTheme.successSubtle : AppTheme.errorSubtle,
      );
    }

    TableRow dataRow(ArgoCDTag t) {
      final target = t.targetTag ?? '';
      final mismatch = target.isNotEmpty && (t.currentTag ?? '') != target;
      final bg = mismatch
          ? (_blink ? const Color(0x33EF4444) : AppTheme.bgCard)
          : AppTheme.bgCard;

      final cells = <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(
            width: 150,
            child: Text(
              t.projectName,
              style: AppTheme.fontBody,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(
            width: 210,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: AppTheme.borderRadiusSmall,
              ),
              child: Text(
                t.currentTag?.isNotEmpty == true ? t.currentTag! : '-',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(
            width: 210,
            child: TextField(
              key: ValueKey('${t.projectName}_target'),
              controller: TextEditingController(text: target),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '未设定',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
              ),
              onChanged: (v) => _updateTag(t.projectName, targetTag: v),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(
            width: 110,
            child: Row(
              children: [
                Checkbox(
                  value: t.muted,
                  activeColor: AppTheme.warning,
                  onChanged: (v) =>
                      _updateTag(t.projectName, muted: v ?? false),
                ),
                Expanded(
                  child: Text(
                    '关闭提醒',
                    style: AppTheme.fontCaption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(width: 80, child: statusCell(t)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Switch(
            value: t.enabled,
            activeThumbColor: AppTheme.bgSidebar,
            activeTrackColor: AppTheme.accent,
            onChanged: (v) => _updateTag(t.projectName, enabled: v),
          ),
        ),
      ];

      return TableRow(
        decoration: BoxDecoration(color: bg),
        children: cells,
      );
    }

    // 统计行固定，表格区域独占剩余高度并垂直滚动。
    //
    // 曾经是「Column > SingleChildScrollView(默认 vertical) > IntrinsicWidth > Table」：
    // 外层 Column 已由 build() 用 Expanded 约束，内部的垂直滚动器拿不到确定高度，
    // 117 行的 Table 直接溢出且滚不动；IntrinsicWidth 还要测量全部 117×6 的固有宽度，
    // 首帧明显卡顿。列宽已全部固定（合计 944 < 1200 窗口宽），既不需要横滚也不需要
    // IntrinsicWidth。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasMismatch
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              size: 16,
              color: hasMismatch ? AppTheme.warning : AppTheme.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasMismatch
                    ? '存在 Tag 与目标不一致的项目，已高亮闪烁提示。'
                    : '${_tags.length} 个项目 Tag 配置正常。',
                style: AppTheme.fontCaption.copyWith(
                  color: hasMismatch ? AppTheme.warning : AppTheme.success,
                ),
              ),
            ),
            Text('${_tags.length} 个项目', style: AppTheme.fontCaption),
          ],
        ),
        const SizedBox(height: AppTheme.space12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: AppTheme.borderRadiusMedium,
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: ClipRRect(
              borderRadius: AppTheme.borderRadiusMedium,
              child: SingleChildScrollView(
                child: Table(
                  border: TableBorder.all(
                    color: AppTheme.borderSubtle,
                    width: 0.5,
                  ),
                  // 前三列（文字）跟窗口弹性伸缩，后三列（控件）保持固有宽度。
                  // 曾全部用 FixedColumnWidth（合计 944px）：1200 窗口右侧留白 256px，
                  // 更窄窗口则溢出。IntrinsicWidth 也已移除（117 行全量测量会让首帧卡）。
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                    3: IntrinsicColumnWidth(),
                    4: IntrinsicColumnWidth(),
                    5: IntrinsicColumnWidth(),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: AppTheme.bgInput),
                      children: const [
                        Text('项目', style: AppTheme.fontBodySecondary),
                        Text('当前 Tag', style: AppTheme.fontBodySecondary),
                        Text('目标 Tag', style: AppTheme.fontBodySecondary),
                        Text('关闭弹窗提醒',
                            style: AppTheme.fontBodySecondary),
                        Text('状态', style: AppTheme.fontBodySecondary),
                        Text('启用', style: AppTheme.fontBodySecondary),
                      ],
                    ),
                    for (final t in _tags) dataRow(t),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Text(text, style: AppTheme.fontCaption.copyWith(color: color)),
    );
  }
}
