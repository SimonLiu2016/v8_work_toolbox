import 'package:flutter/material.dart';

class AppInfoForm extends StatefulWidget {
  final TextEditingController bundleIdController;
  final TextEditingController nameController;
  final TextEditingController localizedNameController;
  final TextEditingController categoryController;
  final TextEditingController versionController;
  final TextEditingController updatedAtController;
  final TextEditingController iconFormatController;
  final TextEditingController descriptionController;

  const AppInfoForm({
    Key? key,
    required this.bundleIdController,
    required this.nameController,
    required this.localizedNameController,
    required this.categoryController,
    required this.versionController,
    required this.updatedAtController,
    required this.iconFormatController,
    required this.descriptionController,
  }) : super(key: key);

  @override
  State<AppInfoForm> createState() => _AppInfoFormState();
}

class _AppInfoFormState extends State<AppInfoForm> {
  @override
  Widget build(BuildContext context) {
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
              widget.bundleIdController,
              'Bundle ID',
              'com.example.app',
            ),
            _buildTextField(widget.nameController, '应用英文名称', 'AppName'),
            _buildTextField(widget.localizedNameController, '应用中文名称', '应用名称'),
            _buildTextField(widget.categoryController, '应用类型', 'utility'),
            _buildTextField(widget.versionController, '版本号', '1.0.0'),
            _buildTextField(widget.updatedAtController, '更新时间', 'YYYY-MM-DD'),
            _buildTextField(widget.iconFormatController, '图标格式', 'icns/png'),
            _buildTextField(widget.descriptionController, '描述', '应用描述'),
          ],
        ),
      ),
    );
  }

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
}
