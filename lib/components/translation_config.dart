import 'package:flutter/material.dart';
import '../utils/kma_package_util.dart';

class TranslationConfig extends StatefulWidget {
  final bool useTranslation;
  final String sourceLanguage;
  final TranslationServiceType translationService;
  final Function(bool) onUseTranslationChanged;
  final Function(String?) onSourceLanguageChanged;
  final Function(TranslationServiceType) onTranslationServiceChanged;

  const TranslationConfig({
    Key? key,
    required this.useTranslation,
    required this.sourceLanguage,
    required this.translationService,
    required this.onUseTranslationChanged,
    required this.onSourceLanguageChanged,
    required this.onTranslationServiceChanged,
  }) : super(key: key);

  @override
  State<TranslationConfig> createState() => _TranslationConfigState();
}

class _TranslationConfigState extends State<TranslationConfig> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '翻译配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('启用自动翻译'),
              value: widget.useTranslation,
              onChanged: widget.onUseTranslationChanged,
            ),
            if (widget.useTranslation) ...[
              const SizedBox(height: 10),
              const Text(
                '翻译服务',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<TranslationServiceType>(
                value: widget.translationService,
                decoration: const InputDecoration(labelText: '翻译服务类型'),
                items: TranslationServiceType.values.map((
                  TranslationServiceType service,
                ) {
                  return DropdownMenuItem<TranslationServiceType>(
                    value: service,
                    child: Text(
                      service == TranslationServiceType.baidu
                          ? '百度翻译'
                          : 'LibreTranslate (本地)',
                    ),
                  );
                }).toList(),
                onChanged: (TranslationServiceType? newValue) {
                  if (newValue != null) {
                    widget.onTranslationServiceChanged(newValue);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: widget.sourceLanguage,
                decoration: const InputDecoration(labelText: '源语言'),
                items: <String>['zh', 'en'].map<DropdownMenuItem<String>>((
                  String value,
                ) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value == 'zh' ? '中文' : '英文'),
                  );
                }).toList(),
                onChanged: widget.onSourceLanguageChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
