import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

class ImageResizeHomePage extends StatefulWidget {
  const ImageResizeHomePage({super.key});

  @override
  State<ImageResizeHomePage> createState() => _ImageResizeHomePageState();
}

class _ImageResizeHomePageState extends State<ImageResizeHomePage> {
  final TextEditingController _folderController = TextEditingController();
  String? _selectedSize;
  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customHeightController = TextEditingController();
  bool _isProcessing = false;
  List<String> _logMessages = [];

  // 预定义的固定尺寸选项
  final Map<String, String> _sizeOptions = {
    '1280x800': '1280x800 (宽屏)',
    '1440x900': '1440x900 (宽屏高清)',
    '2560x1600': '2560x1600 (高清)',
    '2880x1800': '2880x1800 (超高清)',
  };

  @override
  void initState() {
    super.initState();
    _selectedSize = _sizeOptions.keys.first; // 默认选择第一个尺寸
  }

  @override
  void dispose() {
    _folderController.dispose();
    _customWidthController.dispose();
    _customHeightController.dispose();
    super.dispose();
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
    });
  }

  Future<void> _selectFolder() async {
    _addLogMessage('正在尝试打开文件夹选择对话框...');

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folderController.text = selectedDirectory;
        _addLogMessage('已选择文件夹: $selectedDirectory');
      } else {
        _addLogMessage('用户取消了文件夹选择');
      }
    } catch (e) {
      _addLogMessage('选择文件夹时出现错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件选择器出现错误: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resizeImages() async {
    if (_folderController.text.isEmpty) {
      _addLogMessage('请先选择图片文件夹');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择图片文件夹'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // 计算目标尺寸
    int targetWidth, targetHeight;
    if (_selectedSize != null && _sizeOptions.containsKey(_selectedSize)) {
      // 使用固定尺寸
      final sizeParts = _selectedSize!.split('x');
      targetWidth = int.tryParse(sizeParts[0]) ?? 0;
      targetHeight = int.tryParse(sizeParts[1]) ?? 0;
    } else {
      // 使用自定义尺寸
      targetWidth = int.tryParse(_customWidthController.text) ?? 0;
      targetHeight = int.tryParse(_customHeightController.text) ?? 0;
    }

    if (targetWidth <= 0 || targetHeight <= 0) {
      _addLogMessage('请设置有效的尺寸');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请设置有效的尺寸'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // 确认对话框
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认转换'),
          content: Text('确定要在 "${_folderController.text}" 中转换所有图片为 ${targetWidth}x$targetHeight 尺寸吗？\n\n转换后的图片将保存在同目录下的 "resized_images" 文件夹中。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (shouldProceed != true) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
    });

    int processedCount = 0;
    int errorCount = 0;

    try {
      final sourceDirectory = Directory(_folderController.text);
      if (!await sourceDirectory.exists()) {
        _addLogMessage('错误: 源文件夹不存在');
        return;
      }

      // 创建输出文件夹
      final outputDirPath = '${_folderController.text}/resized_images';
      final outputDirectory = Directory(outputDirPath);
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }

      _addLogMessage('开始转换图片，目标尺寸: ${targetWidth}x$targetHeight');
      _addLogMessage('输出目录: $outputDirPath');

      // 获取源文件夹中的所有图片文件
      final List<File> imageFiles = [];
      await for (final entity in sourceDirectory.list()) {
        if (entity is File) {
          final String fileName = entity.path.toLowerCase();
          if (_isImageFile(fileName)) {
            imageFiles.add(entity);
          }
        }
      }

      _addLogMessage('找到 ${imageFiles.length} 个图片文件');

      // 转换每张图片
      for (final imageFile in imageFiles) {
        try {
          await _resizeSingleImage(imageFile, outputDirectory, targetWidth, targetHeight);
          processedCount++;
          _addLogMessage('✓ 已转换: ${imageFile.uri.pathSegments.last}');
        } catch (e) {
          errorCount++;
          _addLogMessage('✗ 转换失败: ${imageFile.uri.pathSegments.last} - $e');
        }
      }

      _addLogMessage('转换完成！成功: $processedCount, 失败: $errorCount');
    } catch (e) {
      _addLogMessage('转换过程中出现错误: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  bool _isImageFile(String fileName) {
    return fileName.endsWith('.jpg') ||
           fileName.endsWith('.jpeg') ||
           fileName.endsWith('.png') ||
           fileName.endsWith('.bmp') ||
           fileName.endsWith('.gif');
  }

  Future<void> _resizeSingleImage(File sourceFile, Directory outputDirectory, int targetWidth, int targetHeight) async {
    final bytes = await sourceFile.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('无法解码图片');
    }

    // 调整图片尺寸
    final resizedImage = img.copyResize(image, width: targetWidth, height: targetHeight);

    // 生成输出文件路径
    final fileName = sourceFile.uri.pathSegments.last;
    final fileExtension = fileName.split('.').last.toLowerCase();
    final outputFileName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '_${targetWidth}x${targetHeight}.$fileExtension');
    final outputFile = File('${outputDirectory.path}/$outputFileName');

    // 根据原文件格式保存
    Uint8List outputBytes;
    switch (fileExtension) {
      case 'jpg':
      case 'jpeg':
        outputBytes = img.encodeJpg(resizedImage, quality: 90);
        break;
      case 'png':
        outputBytes = img.encodePng(resizedImage);
        break;
      case 'bmp':
        outputBytes = img.encodeBmp(resizedImage);
        break;
      case 'gif':
        outputBytes = img.encodeGif(resizedImage);
        break;
      default:
        outputBytes = img.encodePng(resizedImage);
        break;
    }

    await outputFile.writeAsBytes(outputBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('批量图片尺寸修改'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文件夹选择部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '选择图片文件夹',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _folderController,
                              decoration: const InputDecoration(
                                hintText: '请选择包含图片的文件夹',
                                border: OutlineInputBorder(),
                              ),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _selectFolder,
                            icon: const Icon(Icons.folder),
                            label: const Text('选择'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // 尺寸选择部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '选择目标尺寸',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // 固定尺寸选择
                      const Text(
                        '固定尺寸:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      ..._sizeOptions.entries.map((entry) {
                        return RadioListTile<String>(
                          title: Text(entry.value),
                          value: entry.key,
                          groupValue: _selectedSize,
                          onChanged: _isProcessing 
                              ? null 
                              : (String? value) {
                                  setState(() {
                                    _selectedSize = value;
                                    // 当选择固定尺寸时，清空自定义尺寸
                                    _customWidthController.clear();
                                    _customHeightController.clear();
                                  });
                                },
                        );
                      }).toList(),
                      
                      const Divider(),
                      
                      // 自定义尺寸选择
                      RadioListTile<String>(
                        title: const Text('自定义尺寸'),
                        value: 'custom',
                        groupValue: _selectedSize,
                        onChanged: _isProcessing 
                            ? null 
                            : (String? value) {
                                setState(() {
                                  _selectedSize = value;
                                });
                              },
                      ),
                      
                      if (_selectedSize == 'custom') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customWidthController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '宽度 (像素)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('×'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _customHeightController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '高度 (像素)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // 转换按钮
              Center(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _resizeImages,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.transform),
                  label: Text(_isProcessing ? '转换中...' : '开始转换'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // 操作日志部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '操作日志',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectionArea(
                        child: Container(
                          height: 200, // 固定高度
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListView.builder(
                              itemCount: _logMessages.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  _logMessages[index],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}