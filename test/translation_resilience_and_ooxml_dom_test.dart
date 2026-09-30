import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/ooxml_rewriter.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/translator.dart';

class _MockHttpFailClient extends http.BaseClient {
  int callCount = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    throw http.ClientException('Simulated network connection reset');
  }
}

class _MockHttpSuccessClient extends http.BaseClient {
  int callCount = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    if (request is http.Request) {
      final bodyMap = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = bodyMap['messages'] as List<dynamic>;
      final userMsg = messages.last['content'] as String;
      final items = jsonDecode(userMsg) as List<dynamic>;
      final respItems = items.map((e) => {
        'id': e['id'],
        'text': '已翻译_${e['text']}',
      }).toList();

      final body = jsonEncode({
        'choices': [
          {
            'message': {
              'content': jsonEncode(respItems),
            },
          },
        ],
      });
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    final body = jsonEncode({
      'choices': [
        {
          'message': {
            'content': jsonEncode([
              {'id': 0, 'text': '你好，世界'},
            ]),
          },
        },
      ],
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  setUpAll(() async {
    await AppPaths.init();
    await KeychainService.instance.init();
    await AiConfigStore.instance.init();
  });

  group('DocumentTranslator 弹性分批与异常策略', () {
    test('双约束分批：超过 30 项或超过 1500 字符均触发切批', () async {
      // 构造 65 个短段落（每个 10 字符）
      final shortTexts = List.generate(65, (i) => 'Item $i text');
      final completedBatches = <int>[];

      AiService.instance.setMockHttpClient(_MockHttpSuccessClient());

      final results = await DocumentTranslator.translateStrings(
        shortTexts,
        sourceLang: 'English',
        targetLang: 'Chinese',
        onProgress: (done, total) {
          completedBatches.add(done);
        },
      );

      // 65 条数据，按每批上限 30 条：应拆分为 30, 30, 5 共 3 批
      expect(completedBatches.length, 3);
      expect(completedBatches[0], 30);
      expect(completedBatches[1], 60);
      expect(completedBatches[2], 65);

      // 验证翻译条目全部准确映射
      expect(results.length, 65);
      expect(results[0], '已翻译_Item 0 text');
      expect(results[64], '已翻译_Item 64 text');
    });

    test('网络失败时抛出 DocumentTranslationException，严禁静默吞没', () async {
      final failClient = _MockHttpFailClient();
      AiService.instance.setMockHttpClient(failClient);

      expect(
        () async => await DocumentTranslator.translateStrings(
          ['Paragraph 1', 'Paragraph 2'],
          sourceLang: 'English',
          targetLang: 'Chinese',
        ),
        throwsA(isA<DocumentTranslationException>()),
      );
    });
  });

  group('OoxmlRewriter DOM 回写保真度', () {
    test('DOM 树节点替换：单 run、多 run 以及重复 run 内容准确定位替换', () async {
      const originalXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Single Run Title</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Duplicate</w:t></w:r>
      <w:r><w:t> and </w:t></w:r>
      <w:r><w:t>Duplicate</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tr>
        <w:tc>
          <w:p><w:r><w:t>Table Cell Text</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>''';

      final archive = Archive();
      archive.addFile(
        ArchiveFile.bytes('word/document.xml', utf8.encode(originalXml)),
      );
      archive.addFile(
        ArchiveFile.bytes('word/media/logo.png', Uint8List.fromList([1, 2, 3])),
      );
      final docxBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      // Mock 返回翻译
      AiService.instance.setMockHttpClient(_MockHttpSuccessClient());

      // 执行 rewrite
      final resultBytes = await OoxmlRewriter.rewrite(
        docxBytes,
        sourceLang: 'English',
        targetLang: 'Chinese',
      );

      // 解压并断言 XML DOM 结构
      final resArchive = ZipDecoder().decodeBytes(resultBytes);
      final docEntry = resArchive.findFile('word/document.xml');
      expect(docEntry, isNotNull);

      final xml = utf8.decode(docEntry!.content as List<int>);
      final doc = XmlDocument.parse(xml);
      final paragraphs = doc.findAllElements('w:p').toList();

      expect(paragraphs.length, 3);
      // 第 1 段已翻译
      expect(paragraphs[0].findAllElements('w:t').first.innerText, '已翻译_Single Run Title');
      // 第 2 段（多 run）：首节点为译文，其余节点被清空，无标签破损
      final p2Runs = paragraphs[1].findAllElements('w:t').toList();
      expect(p2Runs[0].innerText, '已翻译_Duplicate and Duplicate');
      expect(p2Runs[1].innerText, '');
      expect(p2Runs[2].innerText, '');
      // 表格内的段落正常保留并翻译
      expect(paragraphs[2].findAllElements('w:t').first.innerText, '已翻译_Table Cell Text');

      // media 文件未受破坏
      final mediaEntry = resArchive.findFile('word/media/logo.png');
      expect(mediaEntry, isNotNull);
      expect(mediaEntry!.content as List<int>, [1, 2, 3]);
    });
  });
}
