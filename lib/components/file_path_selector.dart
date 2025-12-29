import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class FilePathSelector extends StatefulWidget {
  final TextEditingController iconPathController;
  final TextEditingController previewPathController;
  final TextEditingController outputDirController;
  final Function() onPickIcon;
  final Function() onPickPreview;
  final Function() onPickOutputDir;

  const FilePathSelector({
    Key? key,
    required this.iconPathController,
    required this.previewPathController,
    required this.outputDirController,
    required this.onPickIcon,
    required this.onPickPreview,
    required this.onPickOutputDir,
  }) : super(key: key);

  @override
  State<FilePathSelector> createState() => _FilePathSelectorState();
}

class _FilePathSelectorState extends State<FilePathSelector> {
  @override
  Widget build(BuildContext context) {
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
            _buildFilePathField(
              widget.iconPathController,
              '图标文件路径',
              '选择图标文件 (icns)',
              widget.onPickIcon,
            ),
            _buildFilePathField(
              widget.previewPathController,
              '预览图路径',
              '选择预览图文件 (png)',
              widget.onPickPreview,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.outputDirController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'KMA 包输出目录',
                      hintText: '选择KMA包输出目录',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: widget.onPickOutputDir,
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
    Function() onPressed,
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
        ElevatedButton(onPressed: onPressed, child: const Text('选择')),
      ],
    );
  }
}
