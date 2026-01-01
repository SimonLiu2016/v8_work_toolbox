import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class CompressKma extends StatefulWidget {
  final TextEditingController sourceDirController;
  final TextEditingController outputDirController;
  final String? selectedSourceDir;
  final String? selectedOutputDir;
  final Function() onPickSourceDir;
  final Function() onPickOutputDir;
  final Function() onCompressKmaPackage;

  const CompressKma({
    Key? key,
    required this.sourceDirController,
    required this.outputDirController,
    required this.selectedSourceDir,
    required this.selectedOutputDir,
    required this.onPickSourceDir,
    required this.onPickOutputDir,
    required this.onCompressKmaPackage,
  }) : super(key: key);

  @override
  State<CompressKma> createState() => _CompressKmaState();
}

class _CompressKmaState extends State<CompressKma> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '压缩为 KMA 包',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.sourceDirController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '源文件夹',
                      hintText: '选择要压缩的文件夹',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: widget.onPickSourceDir,
                  child: const Text('选择'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.outputDirController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '输出目录',
                      hintText: '选择输出目录',
                      border: OutlineInputBorder(),
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
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed:
                  widget.selectedSourceDir != null &&
                      widget.selectedOutputDir != null
                  ? widget.onCompressKmaPackage
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('压缩为 KMA 包'),
            ),
          ],
        ),
      ),
    );
  }
}
