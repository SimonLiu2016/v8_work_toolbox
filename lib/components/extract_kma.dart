import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class ExtractKma extends StatefulWidget {
  final TextEditingController kmaFileController;
  final TextEditingController extractOutputDirController;
  final String? selectedKmaFile;
  final String? selectedExtractOutputDir;
  final Function() onPickKmaFile;
  final Function() onPickExtractOutputDir;
  final Function() onExtractKmaPackage;

  const ExtractKma({
    Key? key,
    required this.kmaFileController,
    required this.extractOutputDirController,
    required this.selectedKmaFile,
    required this.selectedExtractOutputDir,
    required this.onPickKmaFile,
    required this.onPickExtractOutputDir,
    required this.onExtractKmaPackage,
  }) : super(key: key);

  @override
  State<ExtractKma> createState() => _ExtractKmaState();
}

class _ExtractKmaState extends State<ExtractKma> {
  @override
  Widget build(BuildContext context) {
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
                    controller: widget.kmaFileController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'KMA 包文件',
                      hintText: '选择要解压的 KMA 包文件',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: widget.onPickKmaFile,
                  child: const Text('选择'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.extractOutputDirController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '解压输出目录',
                      hintText: '选择解压后的文件存放目录',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: widget.onPickExtractOutputDir,
                  child: const Text('选择'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: ElevatedButton.icon(
                onPressed: widget.onExtractKmaPackage,
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
}
