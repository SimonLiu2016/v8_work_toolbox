import 'package:flutter/material.dart';

class LanguageSelector extends StatefulWidget {
  final List<String> supportedLanguages;
  final Map<String, String> availableLanguages;
  final Function(List<String>) onLanguagesChanged;

  const LanguageSelector({
    Key? key,
    required this.supportedLanguages,
    required this.availableLanguages,
    required this.onLanguagesChanged,
  }) : super(key: key);

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  @override
  Widget build(BuildContext context) {
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
              children: widget.supportedLanguages.map((lang) {
                return InputChip(
                  label: Text(
                    '$lang (${widget.availableLanguages[lang] ?? lang})',
                  ),
                  onDeleted: () {
                    if (widget.supportedLanguages.length > 1) {
                      List<String> updatedLanguages = List.from(
                        widget.supportedLanguages,
                      );
                      updatedLanguages.remove(lang);
                      widget.onLanguagesChanged(updatedLanguages);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                _showLanguageSelectionDialog(context);
              },
              child: const Text('选择语言'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSelectionDialog(BuildContext context) {
    // 创建一个临时的已选语言列表，用于对话框中的选择状态
    List<String> selectedLanguages = List.from(widget.supportedLanguages);

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
                            selectedLanguages = widget.availableLanguages.keys
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
                  itemCount: widget.availableLanguages.length,
                  itemBuilder: (context, index) {
                    String lang = widget.availableLanguages.keys.elementAt(
                      index,
                    );
                    String langName = widget.availableLanguages[lang]!;
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
                    // 通过回调来更新主状态
                    widget.onLanguagesChanged(selectedLanguages);
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
}
