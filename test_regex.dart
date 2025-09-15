void main() {
  // 测试正则表达式替换
  final String fileName = 'dc-bulk-file-pet.yml';
  final String pattern = r'^(.*)-pet\.yml$';
  final String replacement = r'$1.yml';

  print('原始文件名: $fileName');
  print('匹配模式: $pattern');
  print('替换格式: $replacement');

  // 使用正则表达式进行匹配和替换
  final regExp = RegExp(pattern);
  final match = regExp.firstMatch(fileName);

  if (match != null) {
    print('匹配成功');
    print('捕获组数量: ${match.groupCount}');
    for (int i = 0; i <= match.groupCount; i++) {
      print('捕获组 $i: ${match.group(i)}');
    }

    // 手动替换捕获组
    String result = replacement;
    for (int i = 1; i <= match.groupCount; i++) {
      final groupValue = match.group(i) ?? '';
      result = result.replaceAll('\$$i', groupValue);
    }

    print('替换结果: $result');
  } else {
    print('未匹配');
  }
}
