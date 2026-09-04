import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'components/app_components.dart';
import 'theme/app_theme.dart';

class ImageResizeHomePage extends StatefulWidget {
  const ImageResizeHomePage({super.key});

  @override
  State<ImageResizeHomePage> createState() => _ImageResizeHomePageState();
}

class _ImageResizeHomePageState extends State<ImageResizeHomePage> {
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customHeightController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  String _selectedSizeKey = '1024x1024';
  bool _isProcessing = false;
  final List<String> _logMessages = [];

  // 预定义的固定尺寸选项
  final Map<String, String> _sizeOptions = {
    '1024x1024': '1024 × 1024 (正方形)',
    '1280x800': '1280 × 800 (宽屏)',
    '1440x900': '1440 × 900 (宽屏高清)',
    '2560x1600': '2560 × 1600 (高清)',
    '2880x1800': '2880 × 1800 (超高清)',
    'custom': '自定义尺寸',
  };

  @override
  void dispose() {
    _folderController.dispose();
    _customWidthController.dispose();
    _customHeightController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLogMessage(String message) {
    if (!mounted) return;
    setState(() {
      _logMessages.insert(
        0,
        '${DateTime.now().toIso8601String().substring(11, 19)} $message',
      );
    });
  }

  Future<void> _selectFolder() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择包含图片的文件夹',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folderController.text = selectedDirectory;
        _addLogMessage('已选择文件夹: $selectedDirectory');
      }
    } catch (e) {
      _addLogMessage('选择文件夹出错: $e');
    }
  }

  Future<void> _resizeImages() async {
    final folder = _folderController.text.trim();
    if (folder.isEmpty) {
      _addLogMessage('请先选择包含图片的文件夹');
      return;
    }

    int targetWidth;
    int targetHeight;

    if (_selectedSizeKey != 'custom') {
      final parts = _selectedSizeKey.split('x');
      targetWidth = int.tryParse(parts[0]) ?? 0;
      targetHeight = int.tryParse(parts[1]) ?? 0;
    } else {
      targetWidth = int.tryParse(_customWidthController.text.trim()) ?? 0;
      targetHeight = int.tryParse(_customHeightController.text.trim()) ?? 0;
    }

    if (targetWidth <= 0 || targetHeight <= 0) {
      _addLogMessage('请设置有效的正整数尺寸');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.borderRadiusMedium,
            side: const BorderSide(color: AppTheme.borderStrong),
          ),
          title: const Text('确认转换', style: AppTheme.fontTitle),
          content: Text(
            '确定要将 "$folder" 下的所有图片缩放为 $targetWidth×$targetHeight 吗？\n\n新图片将存入该目录下的 "resized_images" 子文件夹。',
            style: AppTheme.fontBody,
          ),
          actions: [
            AppButton.ghost(
              label: '取消',
              size: AppButtonSize.small,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton.primary(
              label: '开始处理',
              size: AppButtonSize.small,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
    });

    int processedCount = 0;
    int errorCount = 0;

    try {
      final sourceDirectory = Directory(folder);
      if (!await sourceDirectory.exists()) {
        _addLogMessage('错误: 源文件夹不存在');
        return;
      }

      final outputDirPath = '$folder/resized_images';
      final outputDirectory = Directory(outputDirPath);
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }

      _addLogMessage('开始转换图片，目标尺寸: $targetWidth×$targetHeight');
      _addLogMessage('输出目录: $outputDirPath');

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

      for (final imageFile in imageFiles) {
        try {
          await _resizeSingleImage(
            imageFile,
            outputDirectory,
            targetWidth,
            targetHeight,
          );
          processedCount++;
          _addLogMessage('✓ 已转换: ${imageFile.uri.pathSegments.last}');
        } catch (e) {
          errorCount++;
          _addLogMessage('✗ 转换失败: ${imageFile.uri.pathSegments.last} - $e');
        }
      }

      _addLogMessage('转换完成！成功: $processedCount, 失败: $errorCount');
    } catch (e) {
      _addLogMessage('转换发生异常: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  bool _isImageFile(String fileName) {
    return fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.bmp') ||
        fileName.endsWith('.gif');
  }

  Future<void> _resizeSingleImage(
    File sourceFile,
    Directory outputDirectory,
    int targetWidth,
    int targetHeight,
  ) async {
    final bytes = await sourceFile.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('无法解码图片数据');
    }

    final resizedImage = img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
    );

    img.Image processedImage;
    if (targetWidth == 1024 && targetHeight == 1024) {
      processedImage = img.Image(
        width: resizedImage.width,
        height: resizedImage.height,
        numChannels: 3,
      );
      for (int y = 0; y < resizedImage.height; y++) {
        for (int x = 0; x < resizedImage.width; x++) {
          final img.Pixel pixel = resizedImage.getPixel(x, y);
          processedImage.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
        }
      }
    } else {
      processedImage = resizedImage;
    }

    final fileName = sourceFile.uri.pathSegments.last;
    final fileExtension = fileName.split('.').last.toLowerCase();
    final outputFileName = fileName.replaceAll(
      RegExp(r'\.[^.]+$'),
      '_${targetWidth}x$targetHeight.$fileExtension',
    );
    final outputFile = File('${outputDirectory.path}/$outputFileName');

    Uint8List outputBytes;
    switch (fileExtension) {
      case 'jpg':
      case 'jpeg':
        outputBytes = img.encodeJpg(processedImage, quality: 90);
        break;
      case 'png':
        outputBytes = img.encodePng(processedImage);
        break;
      case 'bmp':
        outputBytes = img.encodeBmp(processedImage);
        break;
      case 'gif':
        outputBytes = img.encodeGif(processedImage);
        break;
      default:
        outputBytes = img.encodePng(processedImage);
        break;
    }

    await outputFile.writeAsBytes(outputBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgContent,
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.photo_size_select_large, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('图片尺寸修改', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_isProcessing)
                  const AppBadge(
                    label: '正在处理',
                    color: AppTheme.warningSubtle,
                    textColor: AppTheme.warning,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '批量修改目录下图片尺寸，支持预设高清档位与自定义宽高，不覆盖原图',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 文件夹选择卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _folderController,
                          label: '图片文件夹路径',
                          hintText: '点击右侧按钮选择包含图片的源目录...',
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '选择文件夹',
                          icon: Icons.folder_open,
                          size: AppButtonSize.regular,
                          onPressed: _isProcessing ? null : _selectFolder,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space16),
                  Text(
                    '目标尺寸预设',
                    style: AppTheme.fontCaption.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space8),
                  Wrap(
                    spacing: AppTheme.space8,
                    runSpacing: AppTheme.space8,
                    children: _sizeOptions.entries.map((entry) {
                      final isSelected = _selectedSizeKey == entry.key;
                      return InkWell(
                        onTap: _isProcessing
                            ? null
                            : () {
                                setState(() {
                                  _selectedSizeKey = entry.key;
                                });
                              },
                        borderRadius: AppTheme.borderRadiusSmall,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.space12,
                            vertical: AppTheme.space8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.bgSelected : AppTheme.bgInput,
                            borderRadius: AppTheme.borderRadiusSmall,
                            border: Border.all(
                              color: isSelected ? AppTheme.accent : AppTheme.borderSubtle,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 14,
                                color: isSelected ? AppTheme.accent : AppTheme.textTertiary,
                              ),
                              const SizedBox(width: AppTheme.space8),
                              Text(
                                entry.value,
                                style: AppTheme.fontBody.copyWith(
                                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_selectedSizeKey == 'custom') ...[
                    const SizedBox(height: AppTheme.space12),
                    Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: AppTextField(
                            controller: _customWidthController,
                            label: '宽度 (px)',
                            hintText: '例如 800',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: AppTheme.space12),
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text('×', style: AppTheme.fontTitle),
                        ),
                        const SizedBox(width: AppTheme.space12),
                        SizedBox(
                          width: 140,
                          child: AppTextField(
                            controller: _customHeightController,
                            label: '高度 (px)',
                            hintText: '例如 600',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppTheme.space16),
                  AppButton.primary(
                    label: _isProcessing ? '正在转换...' : '开始批量转换',
                    icon: Icons.transform,
                    size: AppButtonSize.regular,
                    isLoading: _isProcessing,
                    onPressed: _isProcessing ? null : _resizeImages,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 执行日志
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: AppTheme.bgInput,
                  borderRadius: AppTheme.borderRadiusMedium,
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal, size: 14, color: AppTheme.textTertiary),
                        const SizedBox(width: AppTheme.space6),
                        Text(
                          '处理日志',
                          style: AppTheme.fontCaption.copyWith(
                            color: AppTheme.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_logMessages.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _logMessages.clear()),
                            child: Text(
                              '清空日志',
                              style: AppTheme.fontCaption.copyWith(color: AppTheme.accentLight),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.space8),
                    const Divider(height: 1, color: AppTheme.borderSubtle),
                    const SizedBox(height: AppTheme.space8),
                    Expanded(
                      child: _logMessages.isEmpty
                          ? Center(
                              child: Text(
                                '暂无日志记录',
                                style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                              ),
                            )
                          : ListView.builder(
                              controller: _logScrollController,
                              itemCount: _logMessages.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    _logMessages[index],
                                    style: AppTheme.fontMono.copyWith(fontSize: 11),
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
      ),
    );
  }
}
