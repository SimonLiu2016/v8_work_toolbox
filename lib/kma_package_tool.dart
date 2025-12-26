import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:aes256gcm/aes256gcm.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:encrypt/encrypt.dart' as encrypt_package;
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';

class KmaPackageToolPage extends StatefulWidget {
  const KmaPackageToolPage({super.key});

  @override
  State<KmaPackageToolPage> createState() => _KmaPackageToolPageState();
}

class _KmaPackageToolPageState extends State<KmaPackageToolPage> {
  // 应用信息表单控制器
  final TextEditingController _bundleIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _localizedNameController =
      TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _updatedAtController = TextEditingController();
  final TextEditingController _iconFormatController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // 语言包列表
  final List<String> _supportedLanguages = ['en'];
  final List<TextEditingController> _languageControllers = [];

  // 可选语言列表
  final Map<String, String> _availableLanguages = {
    'ar': '阿拉伯语',
    'de': '德语',
    'en': '英语',
    'es': '西班牙语',
    'fr': '法语',
    'hi': '印地语',
    'ja': '日语',
    'pt': '葡萄牙语',
    'ru': '俄语',
    'zh': '中文',
    'zh_CN': '简体中文',
    'zh_TW': '繁体中文',
  };

  // 快捷键数据
  final List<Map<String, dynamic>> _shortcuts = [];
  final TextEditingController _shortcutsJsonController =
      TextEditingController();

  // 新增：交互式快捷键输入相关变量
  final List<TextEditingController> _idControllers = [];
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _descriptionControllers = [];
  final List<TextEditingController> _keysControllers = [];
  final List<TextEditingController> _rawControllers = [];
  final List<TextEditingController> _categoryControllers = [];
  final List<TextEditingController> _whenControllers = [];

  // 控制显示模式的变量
  bool _isJsonMode = false;

  // 用于控制快捷键输入行的列表
  int _shortcutRowsCount = 0;

  // 语言包数据
  final Map<String, String> _localeJsons = {};

  // 文件路径控制器（新增输出目录）
  final TextEditingController _iconPathController = TextEditingController();
  final TextEditingController _previewPathController = TextEditingController();
  final TextEditingController _outputDirController = TextEditingController();

  // 密码固定值
  final String _encryptionPassword = '!QAZ2wsx#EDC\$#@!';

  @override
  void initState() {
    super.initState();
    _updatedAtController.text = DateTime.now().toString().split(
      ' ',
    )[0]; // 默认为今天
    _iconFormatController.text = 'icns'; // 默认格式

    // 初始化解压功能的控制器
    _kmaFileController = TextEditingController();
    _extractOutputDirController = TextEditingController();
  }

  @override
  void dispose() {
    _bundleIdController.dispose();
    _nameController.dispose();
    _localizedNameController.dispose();
    _categoryController.dispose();
    _versionController.dispose();
    _updatedAtController.dispose();
    _iconFormatController.dispose();
    _descriptionController.dispose();
    _shortcutsJsonController.dispose();
    _iconPathController.dispose();
    _previewPathController.dispose();
    _outputDirController.dispose();
    _kmaFileController.dispose();
    _extractOutputDirController.dispose();

    // 处理快捷键相关的控制器
    for (var controller in _idControllers) controller.dispose();
    for (var controller in _nameControllers) controller.dispose();
    for (var controller in _descriptionControllers) controller.dispose();
    for (var controller in _keysControllers) controller.dispose();
    for (var controller in _rawControllers) controller.dispose();
    for (var controller in _categoryControllers) controller.dispose();
    for (var controller in _whenControllers) controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KMA 包生成工具'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAppInfoSection(),
            const SizedBox(height: 20),
            _buildFileSection(), // 移动到支持语言之前
            const SizedBox(height: 20),
            _buildLanguageSection(),
            const SizedBox(height: 20),
            _buildShortcutSection(),
            const SizedBox(height: 20),
            _buildGenerateButton(),
            const SizedBox(height: 20),
            _buildPasswordSection(),
            const SizedBox(height: 20),
            _buildExtractSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '应用信息',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              _bundleIdController,
              'Bundle ID',
              'com.example.app',
            ),
            _buildTextField(_nameController, '应用英文名称', 'AppName'),
            _buildTextField(_localizedNameController, '应用中文名称', '应用名称'),
            _buildTextField(_categoryController, '应用类型', 'utility'),
            _buildTextField(_versionController, '版本号', '1.0.0'),
            _buildTextField(_updatedAtController, '更新时间', 'YYYY-MM-DD'),
            _buildTextField(_iconFormatController, '图标格式', 'icns/png'),
            _buildTextField(_descriptionController, '描述', '应用描述'),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持的语言',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              children: _supportedLanguages.map((lang) {
                return InputChip(
                  label: Text('$lang (${_availableLanguages[lang] ?? lang})'),
                  onDeleted: () {
                    if (_supportedLanguages.length > 1) {
                      setState(() {
                        _supportedLanguages.remove(lang);
                        _localeJsons.remove(lang);
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                _showLanguageSelectionDialog();
              },
              child: const Text('选择语言'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '快捷键信息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('交互式'),
                      selected: !_isJsonMode,
                      onSelected: (bool selected) {
                        if (selected) {
                          // 从 JSON 模式切换到交互模式时，解析 JSON 数据
                          if (_isJsonMode) {
                            _parseJsonToInteractive();
                          }
                          setState(() {
                            _isJsonMode = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('JSON'),
                      selected: _isJsonMode,
                      onSelected: (bool selected) {
                        if (selected) {
                          // 从交互模式切换到 JSON 模式时，生成 JSON 数据
                          if (!_isJsonMode) {
                            _generateJsonFromInteractive();
                          }
                          setState(() {
                            _isJsonMode = true;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_isJsonMode) ...[
              // 交互式模式
              ...List.generate(
                _shortcutRowsCount,
                (index) => _buildShortcutRow(index),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _addShortcutRow,
                icon: const Icon(Icons.add),
                label: const Text('添加快捷键'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _removeLastShortcutRow,
                icon: const Icon(Icons.remove),
                label: const Text('删除最后一行'),
              ),
            ] else ...[
              // JSON 模式
              const SizedBox(height: 10),
              SizedBox(
                height: 200,
                child: TextField(
                  controller: _shortcutsJsonController,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText:
                        '输入快捷键 JSON 数据，例如：\n[\n  {\n    "id": "example_shortcut",\n    "name": "Example Shortcut",\n    "description": "An example shortcut",\n    "keys": ["⌘", "C"],\n    "raw": "Cmd+C",\n    "category": "edit",\n    "when": "global"\n  }\n]',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutRow(int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _idControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'ID (英文小写和下划线)',
                      hintText: '如: copy_text',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameControllers[index],
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '快捷键名称',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionControllers[index],
              decoration: const InputDecoration(
                labelText: '描述',
                hintText: '快捷键描述',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keysControllers[index],
                    decoration: const InputDecoration(
                      labelText: '按键组合',
                      hintText: '如: ["⌘", "C"]',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _rawControllers[index],
                    decoration: const InputDecoration(
                      labelText: '原始格式',
                      hintText: '如: Cmd+C',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryControllers[index],
                    decoration: const InputDecoration(
                      labelText: '类型',
                      hintText: '如: edit',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _whenControllers[index],
                    decoration: const InputDecoration(
                      labelText: '使用时机',
                      hintText: '如: global',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    _removeShortcutRow(index);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addShortcutRow() {
    setState(() {
      _shortcutRowsCount++;
      _idControllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
      _descriptionControllers.add(TextEditingController());
      _keysControllers.add(TextEditingController());
      _rawControllers.add(TextEditingController());
      _categoryControllers.add(TextEditingController());
      _whenControllers.add(TextEditingController());
    });
  }

  void _removeShortcutRow(int index) {
    if (_shortcutRowsCount > 0) {
      setState(() {
        _idControllers.removeAt(index);
        _nameControllers.removeAt(index);
        _descriptionControllers.removeAt(index);
        _keysControllers.removeAt(index);
        _rawControllers.removeAt(index);
        _categoryControllers.removeAt(index);
        _whenControllers.removeAt(index);
        _shortcutRowsCount--;
      });
    }
  }

  void _removeLastShortcutRow() {
    if (_shortcutRowsCount > 0) {
      _removeShortcutRow(_shortcutRowsCount - 1);
    }
  }

  void _generateJsonFromInteractive() {
    List<Map<String, dynamic>> shortcutsList = [];

    for (int i = 0; i < _shortcutRowsCount; i++) {
      Map<String, dynamic> shortcut = {
        'id': _idControllers[i].text,
        'name': _nameControllers[i].text,
        'description': _descriptionControllers[i].text,
        'keys': _parseKeysString(_keysControllers[i].text),
        'raw': _rawControllers[i].text,
        'category': _categoryControllers[i].text,
        'when': _whenControllers[i].text,
      };

      // 只有当至少有一个字段不为空时才添加到列表中
      if (shortcut.values.any((value) => value.toString().isNotEmpty)) {
        shortcutsList.add(shortcut);
      }
    }

    _shortcutsJsonController.text = jsonEncode(shortcutsList);
  }

  void _parseJsonToInteractive() {
    if (_shortcutsJsonController.text.isEmpty) return;

    try {
      List<dynamic> parsedJson = jsonDecode(_shortcutsJsonController.text);

      if (parsedJson is List) {
        // 清空当前的行数和控制器
        _clearAllShortcutRows();

        // 添加相应数量的行
        for (int i = 0; i < parsedJson.length; i++) {
          _addShortcutRow();

          Map<String, dynamic> shortcut = parsedJson[i];
          _idControllers[i].text = shortcut['id']?.toString() ?? '';
          _nameControllers[i].text = shortcut['name']?.toString() ?? '';
          _descriptionControllers[i].text =
              shortcut['description']?.toString() ?? '';
          _keysControllers[i].text = _formatKeysList(shortcut['keys']);
          _rawControllers[i].text = shortcut['raw']?.toString() ?? '';
          _categoryControllers[i].text = shortcut['category']?.toString() ?? '';
          _whenControllers[i].text = shortcut['when']?.toString() ?? '';
        }
      }
    } catch (e) {
      _showErrorDialog('JSON 格式错误: $e');
    }
  }

  List<dynamic> _parseKeysString(String keysString) {
    if (keysString.startsWith('[') && keysString.endsWith(']')) {
      try {
        return jsonDecode(keysString);
      } catch (e) {
        // 如果解析失败，返回原字符串
        return [keysString];
      }
    }
    return [keysString];
  }

  String _formatKeysList(dynamic keys) {
    if (keys is List) {
      return jsonEncode(keys);
    }
    return keys?.toString() ?? '';
  }

  void _clearAllShortcutRows() {
    // 清空所有控制器
    for (var controller in _idControllers) controller.dispose();
    for (var controller in _nameControllers) controller.dispose();
    for (var controller in _descriptionControllers) controller.dispose();
    for (var controller in _keysControllers) controller.dispose();
    for (var controller in _rawControllers) controller.dispose();
    for (var controller in _categoryControllers) controller.dispose();
    for (var controller in _whenControllers) controller.dispose();

    // 清空列表
    _idControllers.clear();
    _nameControllers.clear();
    _descriptionControllers.clear();
    _keysControllers.clear();
    _rawControllers.clear();
    _categoryControllers.clear();
    _whenControllers.clear();

    _shortcutRowsCount = 0;
  }

  Widget _buildFileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '文件路径',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildFilePathField(_iconPathController, '图标文件路径', '选择图标文件 (icns)'),
            _buildFilePathField(
              _previewPathController,
              '预览图路径',
              '选择预览图文件 (png)',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _outputDirController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'KMA 包输出目录',
                      hintText: '选择KMA包输出目录',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    String? result = await _pickDirectory();
                    if (result != null) {
                      _outputDirController.text = result;
                    }
                  },
                  child: const Text('选择'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePathField(
    TextEditingController controller,
    String label,
    String hintText,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: true,
            decoration: InputDecoration(labelText: label, hintText: hintText),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: () async {
            String? result = await _pickFile(label);
            if (result != null) {
              controller.text = result;
            }
          },
          child: const Text('选择'),
        ),
      ],
    );
  }

  Future<String?> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    return selectedDirectory;
  }

  Future<String?> _pickFile(String label) async {
    String? filePath;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: label.contains('图标')
            ? ['icns', 'png', 'jpg', 'jpeg']
            : label.contains('预览图')
            ? ['png', 'jpg', 'jpeg', 'gif']
            : ['*'],
        allowMultiple: false,
      );

      if (result != null) {
        filePath = result.files.single.path;
      }
    } catch (e) {
      _showErrorDialog('文件选择失败: $e');
    }

    return filePath;
  }

  Widget _buildGenerateButton() {
    return Center(
      child: ElevatedButton(
        onPressed: _generateKmaPackage,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          backgroundColor: Colors.blue,
        ),
        child: const Text(
          '生成 KMA 包',
          style: TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '加密密码',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_encryptionPassword),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    // 复制到剪贴板功能
                    // 实现复制密码到剪贴板
                  },
                  child: const Text('复制'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '注意：密码已固定为 "!QAZ2wsx#EDC\$#@!"，请妥善保管。',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '解压 KMA 包',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kmaFileController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'KMA 包文件',
                      hintText: '选择要解压的 KMA 包文件',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    String? kmaFilePath = await _pickKmaFile();
                    if (kmaFilePath != null) {
                      _selectedKmaFile = kmaFilePath;
                      _kmaFileController.text = kmaFilePath;
                    }
                  },
                  child: const Text('选择'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _extractOutputDirController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '解压输出目录',
                      hintText: '选择解压后的文件存放目录',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    String? outputDir = await _pickDirectory();
                    if (outputDir != null) {
                      _selectedExtractOutputDir = outputDir;
                      _extractOutputDirController.text = outputDir;
                    }
                  },
                  child: const Text('选择'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: ElevatedButton.icon(
                onPressed: _extractKmaPackage,
                icon: const Icon(Icons.unarchive),
                label: const Text('解压 KMA 包'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 用于解压功能的控制器和变量
  late TextEditingController _kmaFileController;
  late TextEditingController _extractOutputDirController;
  String? _selectedKmaFile;
  String? _selectedExtractOutputDir;

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hintText,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _generateKmaPackage() async {
    try {
      // 验证输入
      if (_bundleIdController.text.isEmpty ||
          _nameController.text.isEmpty ||
          _versionController.text.isEmpty) {
        _showErrorDialog('请填写必要的应用信息：Bundle ID、应用名称和版本号');
        return;
      }

      // 解析快捷键 JSON
      List<Map<String, dynamic>> shortcuts = [];
      if (!_isJsonMode) {
        // 如果在交互模式下，从输入字段生成快捷键数据
        for (int i = 0; i < _shortcutRowsCount; i++) {
          Map<String, dynamic> shortcut = {
            'id': _idControllers[i].text,
            'name': _nameControllers[i].text,
            'description': _descriptionControllers[i].text,
            'keys': _parseKeysString(_keysControllers[i].text),
            'raw': _rawControllers[i].text,
            'category': _categoryControllers[i].text,
            'when': _whenControllers[i].text,
          };

          // 只有当至少有一个字段不为空时才添加到列表中
          if (shortcut.values.any((value) => value.toString().isNotEmpty)) {
            shortcuts.add(shortcut);
          }
        }
      } else {
        // 如果在 JSON 模式下，解析 JSON 字符串
        if (_shortcutsJsonController.text.isNotEmpty) {
          try {
            var parsedJson = jsonDecode(_shortcutsJsonController.text);
            if (parsedJson is List) {
              shortcuts = parsedJson.cast<Map<String, dynamic>>();
            }
          } catch (e) {
            _showErrorDialog('快捷键 JSON 格式错误: $e');
            return;
          }
        }
      }

      // 生成 KMA 包
      String outputPath = await _createKmaPackage(
        bundleId: _bundleIdController.text,
        name: _nameController.text,
        localizedName: _localizedNameController.text,
        category: _categoryController.text,
        version: _versionController.text,
        shortcutCount: shortcuts.length,
        updatedAt: _updatedAtController.text,
        iconFormat: _iconFormatController.text,
        description: _descriptionController.text,
        supportedLanguages: _supportedLanguages,
        shortcuts: shortcuts,
        iconPath: _iconPathController.text,
        previewPath: _previewPathController.text,
      );

      _showSuccessDialog('KMA 包生成成功！\n路径: $outputPath');
    } catch (e) {
      _showErrorDialog('生成 KMA 包时出错: $e');
    }
  }

  Future<String> _createKmaPackage({
    required String bundleId,
    required String name,
    required String localizedName,
    required String category,
    required String version,
    required int shortcutCount, // 这个参数仍然保留，但实际值由调用方传入
    required String updatedAt,
    required String iconFormat,
    required String description,
    required List<String> supportedLanguages,
    required List<Map<String, dynamic>> shortcuts,
    required String iconPath,
    required String previewPath,
  }) async {
    // 创建临时目录
    Directory tempDir = await Directory.systemTemp.createTemp('kma_package_');
    String packageDir = path.join(tempDir.path, 'package');

    try {
      // 创建包目录结构
      await Directory(packageDir).create(recursive: true);

      // 1. 创建 info.json
      Map<String, dynamic> infoJson = {
        'bundleId': bundleId,
        'name': name,
        'localizedName': localizedName,
        'category': category,
        'version': version,
        'shortcutCount': shortcutCount,
        'updatedAt': updatedAt,
        'size': 0, // 将在压缩后更新
        'iconFormat': iconFormat,
        'supportsLanguages': supportedLanguages,
        'description': description,
      };
      await File(
        path.join(packageDir, 'info.json'),
      ).writeAsString(jsonEncode(infoJson));

      // 2. 复制图标文件
      if (iconPath.isNotEmpty && File(iconPath).existsSync()) {
        await File(iconPath).copy(path.join(packageDir, 'icon.$iconFormat'));
      } else {
        // 创建一个简单的占位符文件
        await File(
          path.join(packageDir, 'icon.$iconFormat'),
        ).writeAsString('PLACEHOLDER');
      }

      // 3. 复制预览图
      if (previewPath.isNotEmpty && File(previewPath).existsSync()) {
        await File(previewPath).copy(path.join(packageDir, 'preview.png'));
      } else {
        // 创建一个简单的占位符文件
        await File(
          path.join(packageDir, 'preview.png'),
        ).writeAsString('PLACEHOLDER');
      }

      // 4. 创建 shortcuts.en.json
      await File(
        path.join(packageDir, 'shortcuts.en.json'),
      ).writeAsString(jsonEncode(shortcuts));

      // 5. 创建 locales 目录和语言包
      Directory localesDir = Directory(path.join(packageDir, 'locales'));
      await localesDir.create();

      // 为每种支持的语言创建语言包，除了 'en'（因为它已经作为 shortcuts.en.json 存在）
      for (String lang in supportedLanguages) {
        if (lang != 'en') {
          // 创建语言包 JSON
          // 为简单起见，这里创建一个基础的语言包，实际应用中可能需要用户提供对应的语言包内容
          Map<String, dynamic> localeJson = {
            'appLocalizedName': localizedName,
            'appShortName': name,
            'category': category,
            'shortcuts': _generateEmptyShortcutsForLanguage(
              shortcuts,
            ), // 生成对应语言的快捷键数据
          };

          await File(
            path.join(localesDir.path, '$lang.json'),
          ).writeAsString(jsonEncode(localeJson));
        }
      }

      // 6. 压缩为 ZIP
      String zipPath = path.join(
        tempDir.path,
        '${bundleId}_${version}_$updatedAt.zip',
      );
      await _createZipFromDirectory(packageDir, zipPath);

      // 7. 加密 ZIP 文件
      String encryptedPath = path.join(
        tempDir.path,
        '${bundleId}_${version}_$updatedAt.kma',
      );
      await _encryptFile(zipPath, encryptedPath, _encryptionPassword);

      // 8. 移动到指定的输出目录（而不是弹出对话框让用户选择）
      String outputDir = _outputDirController.text;
      if (outputDir.isNotEmpty) {
        String finalPath = path.join(outputDir, path.basename(encryptedPath));
        await File(encryptedPath).copy(finalPath);
        await tempDir.delete(recursive: true);
        return finalPath;
      } else {
        // 如果用户没有指定输出目录，则使用临时目录
        return encryptedPath;
      }
    } catch (e) {
      await tempDir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _createZipFromDirectory(
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

  Future<void> _encryptFile(
    String inputPath,
    String outputPath,
    String password,
  ) async {
    List<int> fileBytes = await File(inputPath).readAsBytes();

    // 使用 encrypt 包进行 AES-256-GCM 加密
    final key = encrypt_package.Key.fromUtf8(
      _padOrTruncatePassword(password, 32),
    );
    final iv = encrypt_package.IV.fromLength(16); // 16 bytes for AES

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );

    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);

    // 将 IV 附加到加密数据前面，以便解密时使用
    final result = <int>[...iv.bytes, ...encrypted.bytes];

    await File(outputPath).writeAsBytes(result);
  }

  String _padOrTruncatePassword(String password, int length) {
    if (password.length > length) {
      return password.substring(0, length);
    } else if (password.length < length) {
      return password.padRight(length, '0');
    }
    return password;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('错误'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('成功'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _generateEmptyShortcutsForLanguage(
    List<Map<String, dynamic>> shortcuts,
  ) {
    return shortcuts.map((shortcut) {
      return {
        'id': shortcut['id'],
        'name': '',
        'description': '',
        'keys': [],
        'raw': '',
        'category': shortcut['category'],
        'when': shortcut['when'],
      };
    }).toList();
  }

  void _showLanguageSelectionDialog() {
    // 创建一个临时的已选语言列表，用于对话框中的选择状态
    List<String> selectedLanguages = List.from(_supportedLanguages);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('选择语言'),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            selectedLanguages = _availableLanguages.keys
                                .toList();
                          });
                        },
                        child: const Text('全选'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            selectedLanguages = [];
                          });
                        },
                        child: const Text('全不选'),
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                height: 400,
                child: ListView.builder(
                  itemCount: _availableLanguages.length,
                  itemBuilder: (context, index) {
                    String lang = _availableLanguages.keys.elementAt(index);
                    String langName = _availableLanguages[lang]!;
                    bool isSelected = selectedLanguages.contains(lang);
                    return CheckboxListTile(
                      title: Text('$lang ($langName)'),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            if (!selectedLanguages.contains(lang)) {
                              selectedLanguages.add(lang);
                            }
                          } else {
                            selectedLanguages.remove(lang);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    // 将选择结果应用到主状态
                    setState(() {
                      _supportedLanguages.clear();
                      _supportedLanguages.addAll(selectedLanguages);

                      // 更新语言包内容
                      _localeJsons.clear();
                      for (String lang in _supportedLanguages) {
                        _localeJsons[lang] = '{}';
                      }
                    });
                    // 重要：更新主界面状态
                    this.setState(() {});
                    Navigator.pop(context);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _pickKmaFile() async {
    String? filePath;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kma'],
        allowMultiple: false,
      );

      if (result != null) {
        filePath = result.files.single.path;
      }
    } catch (e) {
      _showErrorDialog('文件选择失败: $e');
    }

    return filePath;
  }

  void _extractKmaPackage() async {
    if (_selectedKmaFile == null || _selectedExtractOutputDir == null) {
      _showErrorDialog('请选择 KMA 包文件和解压输出目录');
      return;
    }

    try {
      await KmaPackageUtil.extractKmaPackage(
        inputPath: _selectedKmaFile!,
        outputDir: _selectedExtractOutputDir!,
        password: _encryptionPassword,
      );

      _showSuccessDialog('KMA 包解压成功！\n路径: $_selectedExtractOutputDir');
    } catch (e) {
      _showErrorDialog('解压 KMA 包时出错: $e');
    }
  }
}

// 独立的 KMA 包处理工具类
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

  /// 使用 AES-256-GCM 加密文件
  static Future<void> encryptFile(
    String inputPath,
    String outputPath,
    String password,
  ) async {
    List<int> fileBytes = await File(inputPath).readAsBytes();

    // 使用 encrypt 包进行 AES-256-GCM 加密
    final key = encrypt_package.Key.fromUtf8(
      padOrTruncatePassword(password, 32),
    );
    final iv = encrypt_package.IV.fromLength(16); // 16 bytes for AES

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );

    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);

    // 将 IV 附加到加密数据前面，以便解密时使用
    final result = <int>[...iv.bytes, ...encrypted.bytes];

    await File(outputPath).writeAsBytes(result);
  }

  /// 解密 AES-256-GCM 加密的文件
  static Future<void> decryptFile(
    String inputPath,
    String outputPath,
    String password,
  ) async {
    List<int> fileBytes = await File(inputPath).readAsBytes();

    // 提取 IV（前16字节）和加密数据
    if (fileBytes.length < 16) {
      throw Exception('加密文件格式错误');
    }

    List<int> ivBytes = fileBytes.sublist(0, 16);
    List<int> encryptedData = fileBytes.sublist(16);

    final key = encrypt_package.Key.fromUtf8(
      padOrTruncatePassword(password, 32),
    );
    final iv = encrypt_package.IV(Uint8List.fromList(ivBytes));

    final encrypter = encrypt_package.Encrypter(
      encrypt_package.AES(key, mode: encrypt_package.AESMode.gcm),
    );

    final decrypted = encrypter.decryptBytes(
      encrypt_package.Encrypted(Uint8List.fromList(encryptedData)),
      iv: iv,
    );

    await File(outputPath).writeAsBytes(decrypted);
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

  static String padOrTruncatePassword(String password, int length) {
    if (password.length > length) {
      return password.substring(0, length);
    } else if (password.length < length) {
      return password.padRight(length, '0');
    }
    return password;
  }
}
