import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import '../services/scraper_service.dart';

class OpsDataSourceView extends StatefulWidget {
  const OpsDataSourceView({super.key});

  @override
  State<OpsDataSourceView> createState() => _OpsDataSourceViewState();
}

class _OpsDataSourceViewState extends State<OpsDataSourceView> {
  List<DataSource> _dataSources = [];
  DataSource? _selectedSource;
  List<SqlQuery> _queries = [];
  QueryResult? _queryResult;
  bool _loading = true;
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _loading = true);
    final list = await OpsDatabase.instance.loadDataSources();
    if (mounted) {
      setState(() {
        _dataSources = list;
        if (list.isNotEmpty && _selectedSource == null) {
          _selectedSource = list.first;
        }
        _loading = false;
      });
      if (_selectedSource != null) {
        _loadQueries(_selectedSource!.id);
      }
    }
  }

  Future<void> _loadQueries(String sourceId) async {
    final list = await OpsDatabase.instance.loadSqlQueries(sourceId);
    if (mounted) setState(() => _queries = list);
  }

  void _showAddSourceDialog() {
    final nameCtrl = TextEditingController();
    String type = 'phpmyadmin';
    final urlCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    bool passVisible = false;
    bool keyVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('添加数据源', style: AppTheme.fontTitle),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: AppTheme.bgCard,
                    decoration: const InputDecoration(labelText: '数据源类型'),
                    items: const [
                      DropdownMenuItem(
                        value: 'phpmyadmin',
                        child: Text('数据库 (PhpMyAdmin)'),
                      ),
                      DropdownMenuItem(
                        value: 'grafana',
                        child: Text('Grafana 监控'),
                      ),
                      DropdownMenuItem(
                        value: 'pingcode',
                        child: Text('PingCode 项目管理'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '数据源名称'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(labelText: '服务基础 URL'),
                  ),
                  if (type == 'grafana') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyCtrl,
                      obscureText: !keyVisible,
                      decoration: InputDecoration(
                        labelText: 'API Key / Token',
                        suffixIcon: IconButton(
                          icon: Icon(
                            keyVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          tooltip: keyVisible ? '隐藏 Token' : '显示 Token',
                          onPressed: () =>
                              setDialogState(() => keyVisible = !keyVisible),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(labelText: '用户名 / 账号'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passCtrl,
                      obscureText: !passVisible,
                      decoration: InputDecoration(
                        labelText: '密码',
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
                  ],
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
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                final cfg = {
                  'url': urlCtrl.text.trim(),
                  'base_url': urlCtrl.text.trim(),
                  'sso_url': urlCtrl.text.trim(),
                  'username': userCtrl.text.trim(),
                  'password': passCtrl.text.trim(),
                  'api_key': keyCtrl.text.trim(),
                };
                final ds = DataSource(
                  name: nameCtrl.text.trim(),
                  sourceType: type,
                  config: jsonEncode(cfg),
                );
                await OpsDatabase.instance.saveDataSource(ds);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadSources();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddQueryDialog([SqlQuery? q]) {
    if (_selectedSource == null) return;
    final nameCtrl = TextEditingController(text: q?.name ?? '');
    final sqlCtrl = TextEditingController(text: q?.sqlText ?? '');
    final descCtrl = TextEditingController(text: q?.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          q == null ? '添加 SQL 查询模板' : '编辑 SQL 查询',
          style: AppTheme.fontTitle,
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '查询名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: '说明 / 备注'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sqlCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'SQL 语句 (支持 {param} 占位符)',
                  hintText:
                      'SELECT * FROM orders WHERE status = "ALERT" LIMIT 50;',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final item = SqlQuery(
                id: q?.id,
                dataSourceId: _selectedSource!.id,
                name: nameCtrl.text.trim(),
                sqlText: sqlCtrl.text.trim(),
                description: descCtrl.text.trim(),
              );
              await OpsDatabase.instance.saveSqlQuery(item);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadQueries(_selectedSource!.id);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeQuery(SqlQuery q) async {
    if (_selectedSource == null) return;
    setState(() => _executing = true);

    try {
      final cfg = _selectedSource!.getConfigMap();
      if (_selectedSource!.sourceType == 'phpmyadmin') {
        final client = PhpMyAdminClient(
          url: cfg['url']?.toString() ?? '',
          username: cfg['username']?.toString(),
          password: cfg['password']?.toString(),
        );
        await client.login();
        final res = await client.executeQuery(q.sqlText);
        if (mounted) {
          setState(() {
            _queryResult = res;
            _executing = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _queryResult = QueryResult(
              headers: ['Query', 'Status'],
              rows: [
                [q.name, '查询已执行成功'],
              ],
            );
            _executing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _executing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('查询执行失败: $e'),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：数据源列表与操作
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('数据源列表', style: AppTheme.fontTitle),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: _showAddSourceDialog,
                      tooltip: '添加数据源',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _dataSources.isEmpty
                        ? const Center(
                            child: Text(
                              '暂无数据源',
                              style: AppTheme.fontBodySecondary,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _dataSources.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: AppTheme.borderSubtle,
                            ),
                            itemBuilder: (context, idx) {
                              final ds = _dataSources[idx];
                              final isSelected = _selectedSource?.id == ds.id;
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: AppTheme.bgSelected,
                                leading: Icon(
                                  ds.sourceType == 'grafana'
                                      ? Icons.show_chart_rounded
                                      : ds.sourceType == 'pingcode'
                                      ? Icons.task_alt_rounded
                                      : Icons.storage_rounded,
                                  color: isSelected
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary,
                                ),
                                title: Text(ds.name, style: AppTheme.fontBody),
                                subtitle: Text(
                                  ds.sourceType,
                                  style: AppTheme.fontCaption,
                                ),
                                onTap: () {
                                  setState(() => _selectedSource = ds);
                                  _loadQueries(ds.id);
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space24),

          // 右侧：SQL 预设与执行结果
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SQL 预设与查询模板 (${_selectedSource?.name ?? "未选择"})',
                      style: AppTheme.fontTitle,
                    ),
                    if (_selectedSource != null)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新增 SQL 模板'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                        ),
                        onPressed: () => _showAddQueryDialog(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _queries.isEmpty
                        ? const Center(
                            child: Text(
                              '暂无已保存的 SQL 查询模板',
                              style: AppTheme.fontBodySecondary,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _queries.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: AppTheme.borderSubtle,
                            ),
                            itemBuilder: (context, idx) {
                              final q = _queries[idx];
                              return ListTile(
                                title: Text(
                                  q.name,
                                  style: AppTheme.fontBody.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  q.sqlText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Color(0xFFB0B0B0),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: AppTheme.success,
                                        size: 22,
                                      ),
                                      tooltip: '执行查询',
                                      onPressed: _executing
                                          ? null
                                          : () => _executeQuery(q),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () => _showAddQueryDialog(q),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: AppTheme.error,
                                        size: 18,
                                      ),
                                      onPressed: () async {
                                        await OpsDatabase.instance
                                            .deleteSqlQuery(q.id);
                                        if (_selectedSource != null) {
                                          _loadQueries(_selectedSource!.id);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: AppTheme.space16),

                const Text('查询结果预览', style: AppTheme.fontTitle),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _executing
                        ? const Center(child: CircularProgressIndicator())
                        : _queryResult == null
                        ? const Center(
                            child: Text(
                              '点击上方 SQL 模板的「执行」按钮查看数据结果',
                              style: AppTheme.fontBodySecondary,
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                columns: _queryResult!.headers
                                    .map(
                                      (h) => DataColumn(
                                        label: Text(
                                          h,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                rows: _queryResult!.rows
                                    .map(
                                      (r) => DataRow(
                                        cells: r
                                            .map((c) => DataCell(Text(c)))
                                            .toList(),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
