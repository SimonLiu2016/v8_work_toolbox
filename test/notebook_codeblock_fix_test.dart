import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/markdown_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Evernote Import ENML Native Parser Tests', () {
    test('converts ENML with codeblocks and meta language using system python', () async {
      final result = await Process.run('python3', [
        '-c',
        '''
import sys
sys.path.insert(0, 'scripts')
import evernote_import

enml = """<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note>
  <h2>API Config</h2>
  <div style="--en-codeblock:true;--en-meta:{&quot;lang&quot;:&quot;YAML&quot;};">
    server:
      port: 8080
  </div>
</en-note>"""

print(evernote_import.convert_enml_to_markdown(enml))
'''
      ]);

      expect(result.exitCode, equals(0));
      final stdout = result.stdout as String;
      expect(stdout, contains('## API Config'));
      expect(stdout, contains('```yaml'));
      expect(stdout, contains('port: 8080'));
      expect(stdout.contains('<!DOCTYPE'), isFalse);
    });

    test('safe fallback strips HTML tags and never leaks <!DOCTYPE', () async {
      final result = await Process.run('python3', [
        '-c',
        '''
import sys
sys.path.insert(0, 'scripts')
import evernote_import

bad_enml = """<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note><p>Normal text</p></en-note>"""
md = evernote_import.convert_enml_to_markdown(bad_enml)
assert "<!DOCTYPE" not in md
assert "Normal text" in md
print("PASSED")
'''
      ]);

      expect(result.exitCode, equals(0));
      expect((result.stdout as String).trim(), equals('PASSED'));
    });
  });

  group('MarkdownConverter Code Block Roundtrip', () {
    test('preserves multi-line code block and language correctly', () {
      const md = '''
```yaml
# Harness User Config
maven:
  settings_path: ~/Workspace/settings.xml
test_account:
  username: test_user
```
''';
      final delta = MarkdownConverter.markdownToDelta(md);
      expect(delta, contains('"code_block"'));
      expect(delta, contains('"language\\":\\"yaml\\"'));
      expect(delta, contains('Harness User Config'));

      final restored = MarkdownConverter.deltaToMarkdown(delta);
      expect(restored, contains('```yaml'));
      expect(restored, contains('settings_path: ~/Workspace/settings.xml'));
      expect(restored, contains('test_user'));
      expect(restored, contains('```'));
    });
  });
}
