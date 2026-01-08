import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_package;
import 'package:cryptography/cryptography.dart' as crypto_package;
import 'dart:math' as math;

// 导入新组件
import 'components/app_info_form.dart';
import 'components/language_selector.dart';
import 'components/shortcut_input.dart';
import 'components/file_path_selector.dart';
import 'components/password_display.dart';
import 'components/translation_config.dart';
import 'components/extract_kma.dart';
import 'components/compress_kma.dart';
import 'components/rate_limit_config.dart';
import 'utils/kma_package_util.dart';

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

  // 翻译器配置
  final String _baiduAppId = '20221103001434737'; // 百度翻译API App ID
  final String _baiduAppKey = 'arHn_8TPwN2_vZmJAyvc'; // 百度翻译API密钥
  bool _useTranslation = true; // 是否使用翻译功能
  String _sourceLanguage = 'en'; // 源语言，默认为英文
  TranslationServiceType _translationService =
      TranslationServiceType.baidu; // 翻译服务类型，默认为百度
  int _maxQps = 8; // 最大QPS，默认值
  int _intervalMs = 1000; // 时间窗口毫秒数，默认值

  // 日志控制台相关
  final List<String> _logEntries = [];
  final ScrollController _logScrollController = ScrollController();
  final TextEditingController _logController = TextEditingController();

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

    // 初始化压缩功能的控制器
    _sourceDirController = TextEditingController();
    _compressOutputDirController = TextEditingController();

    // 初始化限流配置
    TranslationUtil.setRateLimitConfig(_maxQps, _intervalMs);

    // 添加初始日志
    _addLog('KMA 包生成工具已启动');
    _addLog('默认源语言设置为: 英文');
  }

  // 添加日志条目
  void _addLog(String message) {
    String timestamp = DateTime.now().toString().split('.')[0];
    String logEntry = '[$timestamp] $message';

    setState(() {
      _logEntries.add(logEntry);
      _logController.text = _logEntries.join('\n');
      _logController.selection = TextSelection.fromPosition(
        TextPosition(offset: _logController.text.length),
      );
    });

    // 滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
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
    _sourceDirController.dispose();
    _compressOutputDirController.dispose();

    // 处理快捷键相关的控制器
    for (var controller in _idControllers) controller.dispose();
    for (var controller in _nameControllers) controller.dispose();
    for (var controller in _descriptionControllers) controller.dispose();
    for (var controller in _keysControllers) controller.dispose();
    for (var controller in _rawControllers) controller.dispose();
    for (var controller in _categoryControllers) controller.dispose();
    for (var controller in _whenControllers) controller.dispose();

    // 处理日志相关的控制器
    _logController.dispose();

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
            _buildTranslationConfigSection(),
            const SizedBox(height: 20),
            _buildRateLimitConfigSection(),
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
            const SizedBox(height: 20),
            _buildCompressSection(),
            const SizedBox(height: 20),
            _buildLogConsole(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoSection() {
    return AppInfoForm(
      bundleIdController: _bundleIdController,
      nameController: _nameController,
      localizedNameController: _localizedNameController,
      categoryController: _categoryController,
      versionController: _versionController,
      updatedAtController: _updatedAtController,
      iconFormatController: _iconFormatController,
      descriptionController: _descriptionController,
      iconPathController: _iconPathController,
      previewPathController: _previewPathController,
    );
  }

  Widget _buildLanguageSection() {
    return LanguageSelector(
      supportedLanguages: _supportedLanguages,
      availableLanguages: _availableLanguages,
      onLanguagesChanged: _onLanguagesChanged,
    );
  }

  void _onLanguagesChanged(List<String> newLanguages) {
    setState(() {
      _supportedLanguages.clear();
      _supportedLanguages.addAll(newLanguages);
    });
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
                  '快捷键',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '总计: $_shortcutRowsCount 个',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ShortcutInput(
              isJsonMode: _isJsonMode,
              shortcutRowsCount: _shortcutRowsCount,
              idControllers: _idControllers,
              nameControllers: _nameControllers,
              descriptionControllers: _descriptionControllers,
              keysControllers: _keysControllers,
              rawControllers: _rawControllers,
              categoryControllers: _categoryControllers,
              whenControllers: _whenControllers,
              shortcutsJsonController: _shortcutsJsonController,
              onModeChange: _onModeChange,
              onAddRow: _addShortcutRow,
              onRemoveRow: _removeShortcutRow,
              onRemoveLastRow: _removeLastShortcutRow,
              onGenerateJsonFromInteractive: _generateJsonFromInteractive,
              onParseJsonToInteractive: _parseJsonToInteractive,
            ),
          ],
        ),
      ),
    );
  }

  void _onModeChange(bool isJsonMode) {
    setState(() {
      _isJsonMode = isJsonMode;
    });
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
    return FilePathSelector(
      iconPathController: _iconPathController,
      previewPathController: _previewPathController,
      outputDirController: _outputDirController,
      onPickIcon: _pickIcon,
      onPickPreview: _pickPreview,
      onPickOutputDir: _pickOutputDir,
    );
  }

  void _pickIcon() async {
    String? result = await _pickFile('图标文件路径');
    if (result != null) {
      _iconPathController.text = result;
    }
  }

  void _pickPreview() async {
    String? result = await _pickFile('预览图路径');
    if (result != null) {
      _previewPathController.text = result;
    }
  }

  void _pickOutputDir() async {
    String? result = await _pickDirectory();
    if (result != null) {
      _outputDirController.text = result;
    }
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

  void _onPickSourceDir() async {
    String? sourceDir = await _pickDirectory();
    if (sourceDir != null) {
      _selectedSourceDir = sourceDir;
      _sourceDirController.text = sourceDir;

      // 自动设置输出目录为源目录的父目录
      String outputDir = path.dirname(sourceDir);
      _selectedCompressOutputDir = outputDir;
      _compressOutputDirController.text = outputDir;

      _addLog('已选择源文件夹: $sourceDir');
      _addLog('已自动设置输出目录: $outputDir');
    }
  }

  void _onPickCompressOutputDir() async {
    String? outputDir = await _pickDirectory();
    if (outputDir != null) {
      _selectedCompressOutputDir = outputDir;
      _compressOutputDirController.text = outputDir;
      _addLog('已选择输出目录: $outputDir');
    }
  }

  Future<void> _compressToKmaPackage() async {
    if (_selectedSourceDir == null || _selectedCompressOutputDir == null) {
      _showErrorDialog('请选择源文件夹和输出目录');
      return;
    }

    try {
      _addLog('开始压缩文件夹为 KMA 包...');
      _addLog('源文件夹: ${_selectedSourceDir}');
      _addLog('输出目录: ${_selectedCompressOutputDir}');

      // 生成输出文件名，使用源文件夹名称
      String sourceDirName = path.basename(_selectedSourceDir!);
      String outputPath = path.join(
        _selectedCompressOutputDir!,
        '\$sourceDirName.kma',
      );

      _addLog('输出文件路径: \$outputPath');

      // 调用 KmaPackageUtil 的 createKmaPackage 方法
      await KmaPackageUtil.createKmaPackage(
        sourceDir: _selectedSourceDir!,
        outputPath: outputPath,
        password: _encryptionPassword,
      );

      _addLog('KMA 包压缩成功！路径: \$outputPath');
      _showSuccessDialog('KMA 包压缩成功！\n路径: \$outputPath');
    } catch (e) {
      _addLog('压缩 KMA 包时出错: \$e');
      _showErrorDialog('压缩 KMA 包时出错: \$e');
    }
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
    return PasswordDisplay(encryptionPassword: _encryptionPassword);
  }

  Widget _buildTranslationConfigSection() {
    return TranslationConfig(
      useTranslation: _useTranslation,
      sourceLanguage: _sourceLanguage,
      translationService: _translationService,
      onUseTranslationChanged: _onUseTranslationChanged,
      onSourceLanguageChanged: _onSourceLanguageChanged,
      onTranslationServiceChanged: _onTranslationServiceChanged,
    );
  }

  Widget _buildRateLimitConfigSection() {
    return RateLimitConfig(
      maxQps: _maxQps,
      intervalMs: _intervalMs,
      onRateLimitChanged: _onRateLimitChanged,
    );
  }

  void _onUseTranslationChanged(bool value) {
    setState(() {
      _useTranslation = value;
    });
  }

  void _onSourceLanguageChanged(String? newValue) {
    setState(() {
      _sourceLanguage = newValue!;
    });
  }

  void _onTranslationServiceChanged(TranslationServiceType newValue) {
    setState(() {
      _translationService = newValue;
      // 同时更新TranslationUtil中的当前服务类型
      TranslationUtil.currentService = newValue;
    });
  }

  void _onRateLimitChanged(int maxQps, int intervalMs) {
    setState(() {
      _maxQps = maxQps;
      _intervalMs = intervalMs;
      // 更新TranslationUtil中的限流配置
      TranslationUtil.setRateLimitConfig(maxQps, intervalMs);
    });
  }

  Widget _buildExtractSection() {
    return ExtractKma(
      kmaFileController: _kmaFileController,
      extractOutputDirController: _extractOutputDirController,
      selectedKmaFile: _selectedKmaFile,
      selectedExtractOutputDir: _selectedExtractOutputDir,
      onPickKmaFile: _onPickKmaFile,
      onPickExtractOutputDir: _onPickExtractOutputDir,
      onExtractKmaPackage: _extractKmaPackage,
    );
  }

  Widget _buildCompressSection() {
    return CompressKma(
      sourceDirController: _sourceDirController,
      outputDirController: _compressOutputDirController,
      selectedSourceDir: _selectedSourceDir,
      selectedOutputDir: _selectedCompressOutputDir,
      onPickSourceDir: _onPickSourceDir,
      onPickOutputDir: _onPickCompressOutputDir,
      onCompressKmaPackage: _compressToKmaPackage,
    );
  }

  void _onPickKmaFile() async {
    String? kmaFilePath = await _pickKmaFile();
    if (kmaFilePath != null) {
      _selectedKmaFile = kmaFilePath;
      _kmaFileController.text = kmaFilePath;
    }
  }

  void _onPickExtractOutputDir() async {
    String? outputDir = await _pickDirectory();
    if (outputDir != null) {
      _selectedExtractOutputDir = outputDir;
      _extractOutputDirController.text = outputDir;
    }
  }

  // 用于解压功能的控制器和变量
  late TextEditingController _kmaFileController;
  late TextEditingController _extractOutputDirController;
  String? _selectedKmaFile;
  String? _selectedExtractOutputDir;

  // 用于压缩功能的控制器和变量
  late TextEditingController _sourceDirController;
  late TextEditingController _compressOutputDirController;
  String? _selectedSourceDir;
  String? _selectedCompressOutputDir;

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
      _addLog('开始生成 KMA 包...');

      // 验证输入
      if (_bundleIdController.text.isEmpty ||
          _nameController.text.isEmpty ||
          _versionController.text.isEmpty) {
        _showErrorDialog('请填写必要的应用信息：Bundle ID、应用名称和版本号');
        _addLog('输入验证失败：缺少必要的应用信息');
        return;
      }

      _addLog('输入验证通过');

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
            _addLog('成功解析快捷键 JSON');
          } catch (e) {
            _showErrorDialog('快捷键 JSON 格式错误: $e');
            _addLog('快捷键 JSON 格式错误: $e');
            return;
          }
        }
      }

      _addLog('快捷键数量: ${shortcuts.length}');

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

      _addLog('KMA 包生成成功！路径: $outputPath');
      _showSuccessDialog('KMA 包生成成功！\n路径: $outputPath');
    } catch (e) {
      _addLog('生成 KMA 包时出错: $e');
      _showErrorDialog('生成 KMA 包时出错: $e');
    }
  }

  Future<String> _createKmaPackage({
    required String bundleId,
    required String name,
    required String localizedName,
    required String category,
    required String version,
    required int shortcutCount,
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
      _addLog('开始创建 KMA 包...');
      _addLog('临时目录: ${tempDir.path}');
      _addLog('包目录: $packageDir');

      // 创建包目录结构
      await Directory(packageDir).create(recursive: true);
      _addLog('已创建包目录结构');

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
      String infoJsonPath = path.join(packageDir, 'info.json');
      await File(infoJsonPath).writeAsString(jsonEncode(infoJson));
      _addLog('已创建 info.json: $infoJsonPath');

      // 2. 复制图标文件
      if (iconPath.isNotEmpty && File(iconPath).existsSync()) {
        String iconDestPath = path.join(packageDir, 'icon.$iconFormat');
        await File(iconPath).copy(iconDestPath);
        _addLog('已复制图标文件: $iconDestPath');
      } else {
        String placeholderPath = path.join(packageDir, 'icon.$iconFormat');
        await File(placeholderPath).writeAsString('PLACEHOLDER');
        _addLog('已创建图标占位文件: $placeholderPath');
      }

      // 3. 复制预览图
      if (previewPath.isNotEmpty && File(previewPath).existsSync()) {
        String previewDestPath = path.join(packageDir, 'preview.png');
        await File(previewPath).copy(previewDestPath);
        _addLog('已复制预览图: $previewDestPath');
      } else {
        String placeholderPath = path.join(packageDir, 'preview.png');
        await File(placeholderPath).writeAsString('PLACEHOLDER');
        _addLog('已创建预览图占位文件: $placeholderPath');
      }

      // 4. 创建 shortcuts.en.json
      List<Map<String, dynamic>> shortcutsForEnJson = shortcuts;

      // 如果源语言不是英文，需要将快捷键翻译成英文
      if (_useTranslation && _sourceLanguage != 'en') {
        _addLog('翻译快捷键列表为英文...');
        Map<String, dynamic> translatedShortcutsForEn =
            await TranslationUtil.translateShortcuts(
              shortcuts,
              _sourceLanguage, // 从源语言
              'en', // 翻译到英文
              _addLog, // 日志回调
            );
        shortcutsForEnJson = translatedShortcutsForEn['shortcuts'];
        _addLog('快捷键已翻译为英文');
      } else {
        _addLog('源语言与目标语言相同，无需翻译快捷键');
      }

      String shortcutsPath = path.join(packageDir, 'shortcuts.en.json');
      await File(shortcutsPath).writeAsString(jsonEncode(shortcutsForEnJson));
      _addLog('已创建 shortcuts.en.json: $shortcutsPath');

      // 5. 创建 locales 目录和语言包
      Directory localesDir = Directory(path.join(packageDir, 'locales'));
      await localesDir.create();
      _addLog('已创建 locales 目录: ${localesDir.path}');

      // 为每种支持的语言创建语言包，除了 'en'（因为它已经作为 shortcuts.en.json 存在）
      for (String lang in supportedLanguages) {
        if (lang != 'en') {
          Map<String, dynamic> localeJson;

          if (_useTranslation) {
            // 使用翻译功能生成语言包
            _addLog('开始翻译语言包: $lang');

            // 如果目标语言和源语言相同，则不需要翻译
            if (lang == _sourceLanguage) {
              // 源语言和目标语言相同，直接使用原文
              localeJson = {
                'appLocalizedName': localizedName,
                'appShortName': name,
                'category': category,
                'shortcuts': shortcuts, // 直接使用原始快捷键
              };
              _addLog('目标语言与源语言相同，使用原始内容: $lang');
            } else {
              // 需要翻译
              // 翻译应用信息
              Map<String, dynamic> translatedAppInfo =
                  await TranslationUtil.translateAppInfo(
                    localizedName,
                    name,
                    category,
                    _sourceLanguage,
                    lang,
                    _addLog, // 日志回调
                  );

              // 翻译快捷键信息
              Map<String, dynamic> translatedShortcuts =
                  await TranslationUtil.translateShortcuts(
                    shortcuts,
                    _sourceLanguage, // 使用配置的源语言
                    lang,
                    _addLog, // 日志回调
                  );

              localeJson = {
                'appLocalizedName': translatedAppInfo['appLocalizedName'],
                'appShortName': translatedAppInfo['appShortName'],
                'category': translatedAppInfo['category'],
                'shortcuts': translatedShortcuts['shortcuts'],
              };
            }

            _addLog('完成翻译语言包: $lang');
          } else {
            // 不使用翻译功能，创建基础语言包
            localeJson = {
              'appLocalizedName': localizedName,
              'appShortName': name,
              'category': category,
              'shortcuts': _generateEmptyShortcutsForLanguage(
                shortcuts,
              ), // 生成对应语言的快捷键数据
            };
            _addLog('创建基础语言包 (非翻译模式): $lang');
          }

          String localePath = path.join(localesDir.path, '$lang.json');
          await File(localePath).writeAsString(jsonEncode(localeJson));
          _addLog('已创建语言包: $localePath');
        }
      }

      // 6. 压缩为 ZIP
      String zipPath = path.join(
        tempDir.path,
        '${bundleId}_${version}_$updatedAt.zip',
      );
      await KmaPackageUtil.createZipFromDirectory(packageDir, zipPath);
      _addLog('已创建 ZIP 文件: $zipPath');

      // 7. 加密 ZIP 文件
      String encryptedPath = path.join(
        tempDir.path,
        '${bundleId}_${version}_$updatedAt.kma',
      );
      await KmaPackageUtil.encryptFile(
        zipPath,
        encryptedPath,
        _encryptionPassword,
        _addLog,
      );
      _addLog('已创建加密 KMA 文件: $encryptedPath');

      // 8. 移动到指定的输出目录
      String outputDir = _outputDirController.text;
      _addLog('输出目录: $outputDir');

      if (outputDir.isNotEmpty) {
        // 确保输出目录存在
        Directory outputDirectory = Directory(outputDir);
        if (!await outputDirectory.exists()) {
          _addLog('输出目录不存在，尝试创建: $outputDir');
          await outputDirectory.create(recursive: true);
        }

        String finalPath = path.join(outputDir, path.basename(encryptedPath));
        _addLog('目标路径: $finalPath');

        // 检查源文件是否存在
        File sourceFile = File(encryptedPath);
        if (!await sourceFile.exists()) {
          _addLog('错误：源文件不存在: $encryptedPath');
          throw Exception('源加密文件不存在: $encryptedPath');
        }

        _addLog('开始复制文件从 $encryptedPath 到 $finalPath');
        await sourceFile.copy(finalPath);
        await tempDir.delete(recursive: true);
        _addLog('成功生成 KMA 包: $finalPath');
        return finalPath;
      } else {
        // 如果没有指定输出目录，返回加密文件路径
        await tempDir.delete(recursive: true);
        _addLog('返回临时 KMA 文件: $encryptedPath');
        return encryptedPath;
      }
    } catch (e) {
      _addLog('创建 KMA 包时发生错误: $e');
      await tempDir.delete(recursive: true);
      rethrow;
    }
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

  void _copyPasswordToClipboard() {
    Clipboard.setData(ClipboardData(text: _encryptionPassword));
    _showSuccessDialog('密码已复制到剪贴板');
  }

  Widget _buildLogConsole() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '运行日志',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                controller: _logController,
                maxLines: null,
                expands: true,
                readOnly: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(8.0),
                  hintText: '系统运行日志将显示在这里...',
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'Monospace'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _logEntries.clear();
                      _logController.clear();
                    });
                  },
                  child: const Text('清空日志'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
