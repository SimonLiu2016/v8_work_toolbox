import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ops_tool/models/ops_models.dart';
import 'package:V8WorkToolbox/tools/ops_tool/services/argocd_service.dart';
import 'package:V8WorkToolbox/tools/ops_tool/services/gitlab_client.dart';
import 'package:V8WorkToolbox/tools/ops_tool/services/ops_notifier.dart';
import 'package:V8WorkToolbox/tools/ops_tool/services/template_engine.dart';
import 'package:V8WorkToolbox/tools/registry.dart';

void main() {
  group('OpsTool Registry & ToolDefinition Tests', () {
    test('OpsToolDefinition is registered in ToolRegistry', () {
      final tool = ToolRegistry.findById('ops-tool');
      expect(tool, isNotNull);
      expect(tool!.title, '磐石运维工具');
      expect(tool.openInNewWindow, isTrue);
      // 磐石运维归「运维与监控」分类，不再挤在「系统与配置」里（见 change
      // reorganize-tool-categories-and-fix-light-mode-legibility）。
      expect(tool.category, ToolCategory.ops);
    });
  });

  group('TemplateEngine Unit Tests', () {
    test('parseCellRef parses Excel coordinates correctly', () {
      final a1 = TemplateEngine.parseCellRef('A1');
      expect(a1, isNotNull);
      expect(a1!.$1, 0); // Col A -> 0
      expect(a1.$2, -1); // Row 1 -> -1 (headers)

      final b3 = TemplateEngine.parseCellRef('B3');
      expect(b3, isNotNull);
      expect(b3!.$1, 1); // Col B -> 1
      expect(b3.$2, 1); // Row 3 -> 1 (rows[1])
    });

    test('format helpers format numbers properly', () {
      expect(TemplateEngine.fmtNumber(1000), '1,000');
      expect(TemplateEngine.fmtNumber(1234567.89), '1,234,567.89');
      expect(TemplateEngine.fmtPercent(0.125), '12.50%');
    });

    test('extractPlaceholders finds all unique placeholder tags', () {
      const tpl = '你好 {name}，今日 {date}，总额是 {amount}，再次强调 {name}。';
      final placeholders = TemplateEngine.extractPlaceholders(tpl);
      expect(placeholders, containsAll(['name', 'date', 'amount']));
      expect(placeholders.length, 3);
    });

    test('extractExcelValue computes sum, count, avg correctly', () {
      final sheet = SheetData(
        name: '订单明细',
        headers: ['订单号', '金额', '状态'],
        rows: [
          ['O-001', '100', 'SUCCESS'],
          ['O-002', '200', 'SUCCESS'],
          ['O-003', '300', 'PENDING'],
        ],
      );

      // Sum of 金额
      const ruleSum = ExtractionRule(
        placeholder: '总金额',
        sheetName: '订单明细',
        column: '金额',
        aggregation: 'sum',
      );
      final sumVal = TemplateEngine.extractExcelValue([sheet], ruleSum);
      expect(sumVal, '600');

      // Count
      const ruleCount = ExtractionRule(
        placeholder: '订单数',
        sheetName: '订单明细',
        column: '金额',
        aggregation: 'count',
      );
      final countVal = TemplateEngine.extractExcelValue([sheet], ruleCount);
      expect(countVal, '3');

      // Filtered sum
      const ruleFilteredSum = ExtractionRule(
        placeholder: '成功金额',
        sheetName: '订单明细',
        column: '金额',
        filterColumn: '状态',
        filterValue: 'SUCCESS',
        aggregation: 'sum',
      );
      final filteredSumVal = TemplateEngine.extractExcelValue([sheet], ruleFilteredSum);
      expect(filteredSumVal, '300');
    });

    test('resolveTemplate populates built-in variables and rules', () {
      const template = '报告生成于：{当前日期}，总计：{总额}元。';
      final rules = [
        const ExtractionRule(
          placeholder: '总额',
          sheetName: 'Sheet1',
          cellRef: 'B2',
        ),
      ];
      final sheets = [
        const SheetData(
          name: 'Sheet1',
          headers: ['项目', '数值'],
          rows: [
            ['项目A', '8888'],
          ],
        ),
      ];

      final res = TemplateEngine.resolveTemplate(
        template: template,
        rules: rules,
        sheets: sheets,
      );

      expect(res, contains('8888元'));
      expect(res, isNot(contains('{总额}')));
      expect(res, isNot(contains('{当前日期}')));
    });
  });

  group('GitLabClient POM version rewriting tests', () {
    test('updatePomVersions updates parent and child versions without corrupting dependencies', () {
      const samplePom = '''<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.company.framework</groupId>
    <artifactId>parent-pom</artifactId>
    <version>1.0.0-SNAPSHOT</version>
  </parent>
  <groupId>com.company.service</groupId>
  <artifactId>user-service</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>org.slf4j</groupId>
      <artifactId>slf4j-api</artifactId>
      <version>1.7.30</version>
    </dependency>
  </dependencies>
</project>''';

      final updated = GitLabClient.updatePomVersions(
        samplePom,
        '2.0.0-RELEASE',
        '2.0.0-RELEASE',
      );

      expect(updated, contains('<version>2.0.0-RELEASE</version>'));
      // Dependency version should be preserved!
      expect(updated, contains('<version>1.7.30</version>'));
    });
  });

  group('ArgoCD 配置仓路径解析与分页 Tests', () {
    test('parseProjectsPath 解析仓库 / 分支 / 子目录', () {
      final ref = ArgoCdService.parseProjectsPath(
          'repository/config-fs-argocd-sit/tree/master/argocd/projects',
          'https://gitlab.example.com');
      expect(ref.repo, 'repository/config-fs-argocd-sit');
      expect(ref.branch, 'master');
      expect(ref.fileDir, 'argocd/projects');
    });

    test('parseProjectsPath 兼容前导斜杠写法', () {
      final ref = ArgoCdService.parseProjectsPath(
          '/repository/config-fs-argocd-sit/tree/master', 'https://gitlab.example.com');
      expect(ref.repo, 'repository/config-fs-argocd-sit');
      expect(ref.branch, 'master');
      expect(ref.fileDir, '');
    });

    test('parseProjectsPath 无仓库段且 URL 无路径尾段时抛错', () {
      expect(
        () => ArgoCdService.parseProjectsPath('/tree/master/x', 'https://gitlab.example.com'),
        throwsA(isA<Exception>()),
      );
    });

    test('parseProjectsPath 含命名空间的仓库路径', () {
      final ref = ArgoCdService.parseProjectsPath(
          'repository/config-fs-argocd-sit/tree/master/values', 'https://gitlab.example.com');
      expect(ref.repo, 'repository/config-fs-argocd-sit');
      expect(ref.branch, 'master');
      expect(ref.fileDir, 'values');
    });

    test('parseProjectsPath 仓库名为空时从 GitLab URL 尾段回退提取', () {
      // 仓库段为空（以 /tree 开头）时，仓库名回退为 URL 尾段；
      // /tree 之后的目录全部保留为 fileDir。
      final ref = ArgoCdService.parseProjectsPath(
          '/tree/release-2026/config-fs-argocd-sit/projects',
          'https://fs-gitlab-aliyun.chowtaifook.sz/repository/config-fs-argocd-sit/');
      expect(ref.repo, 'repository/config-fs-argocd-sit');
      expect(ref.branch, 'release-2026');
      expect(ref.fileDir, 'config-fs-argocd-sit/projects');
    });

    test('parseProjectsPath 仓库名存在时优先使用路径段而非 URL 回退', () {
      final ref = ArgoCdService.parseProjectsPath(
          'repository/config-fs-argocd-sit/tree/master/config-fs-argocd-sit/projects',
          'https://fs-gitlab-aliyun.chowtaifook.sz/repository/config-fs-argocd-sit');
      expect(ref.repo, 'repository/config-fs-argocd-sit');
      expect(ref.branch, 'master');
      expect(ref.fileDir, 'config-fs-argocd-sit/projects');
    });

    test('parseProjectsPath 无 /tree 段时抛错', () {
      expect(
        () => ArgoCdService.parseProjectsPath('/argocd/projects', 'https://gitlab.example.com'),
        throwsA(isA<Exception>()),
      );
    });

    test('Link 响应头解析下一页 URL', () {
      final header =
          '<https://git.example.com/api/v4/projects/1/repository/tree?per_page=100&page=2>; rel="next", '
          '<https://git.example.com/api/v4/projects/1/repository/tree?per_page=100&page=5>; rel="last"';
      expect(GitLabClient.linkNextUrl(header),
          'https://git.example.com/api/v4/projects/1/repository/tree?per_page=100&page=2');
    });

    test('Link 响应头无 next 时返回 null', () {
      expect(GitLabClient.linkNextUrl(null), isNull);
      expect(GitLabClient.linkNextUrl(''), isNull);
      expect(
          GitLabClient.linkNextUrl(
              '<https://git.example.com/api/v4/x?page=1>; rel="first", <https://git.example.com/api/v4/x?page=3>; rel="last"'),
          isNull);
    });
  });

  group('ArgoCD 项目名推导 Tests', () {
    test('extractProjectName 剥离 values- 前缀与扩展名', () {
      expect(ArgoCdService.extractProjectName('values-dc-order.yaml'), 'dc-order');
      expect(ArgoCdService.extractProjectName('values-pay.yaml'), 'pay');
      expect(ArgoCdService.extractProjectName('values-foo.yml'), 'foo');
      expect(ArgoCdService.extractProjectName('dc-report.yaml'), 'dc-report');
      expect(ArgoCdService.extractProjectName('values-'), '');
    });

    test('extractProjectName 忽略目录前缀，仅取文件名段', () {
      expect(ArgoCdService.extractProjectName('argocd/projects/values-web.yaml'), 'web');
    });
  });

  group('ArgoCD 配置表合并与巡检写回语义 Tests', () {
    final remote = [
      const ArgoCdYamlTag(projectName: 'dc-order', filePath: 'values/values-dc-order.yaml', currentTag: 'v2.0.0'),
      const ArgoCdYamlTag(projectName: 'dc-web', filePath: 'values/values-dc-web.yaml', currentTag: 'v1.1.0'),
      const ArgoCdYamlTag(projectName: 'dc-new', filePath: 'values/values-dc-new.yaml', currentTag: 'v0.1.0'),
    ];

    test('mergeRemoteTags 保留用户已填写的目标 Tag / 关闭提醒 / 启用状态', () {
      final existing = [
        ArgoCDTag(
          id: 'env-1_dc-order',
          envId: 'env-1',
          projectName: 'dc-order',
          currentTag: 'v1.9.0',
          targetTag: 'v1.9.0',
          muted: true,
          enabled: false,
        ),
        ArgoCDTag(
          id: 'env-1_dc-web',
          envId: 'env-1',
          projectName: 'dc-web',
          currentTag: 'v1.0.0',
          targetTag: 'v1.0.0',
          muted: false,
          enabled: true,
        ),
      ];

      final merged = ArgoCdService.mergeRemoteTags('env-1', remote, existing);
      expect(merged, hasLength(3));

      final order = merged.firstWhere((t) => t.projectName == 'dc-order');
      expect(order.currentTag, 'v2.0.0'); // 远程值覆盖
      expect(order.targetTag, 'v1.9.0'); // 用户值保留
      expect(order.muted, isTrue);
      expect(order.enabled, isFalse);
      expect(order.id, 'env-1_dc-order');
      expect(order.lastChecked, isNotNull);

      final web = merged.firstWhere((t) => t.projectName == 'dc-web');
      expect(web.targetTag, 'v1.0.0');
      expect(web.muted, isFalse);
      expect(web.enabled, isTrue);
    });

    test('mergeRemoteTags 对远程新增项目给出安全默认值', () {
      final merged = ArgoCdService.mergeRemoteTags('env-1', remote, const []);
      final fresh = merged.firstWhere((t) => t.projectName == 'dc-new');
      expect(fresh.targetTag, '');
      expect(fresh.muted, isFalse);
      expect(fresh.enabled, isTrue);
      expect(fresh.id, 'env-1_dc-new');
    });

    test('mergeRemoteTags 远程已删除的项目不再出现（id 由 envId_projectName 推导保持稳定）', () {
      final withNew = ArgoCdService.mergeRemoteTags('env-1', remote, const []);
      final merged = ArgoCdService.mergeRemoteTags('env-1',
          [remote.first, remote.last], withNew);
      expect(merged, hasLength(2));
      expect(merged.map((t) => t.id), ['env-1_dc-order', 'env-1_dc-new']);
      // 保留的行的目标 Tag 仍在
      expect(merged.last.targetTag, '');
    });

    test('buildUpsertTag 仅更新当前 Tag，保留用户配置', () {
      final stored = ArgoCDTag(
        id: 'env-1_dc-order',
        envId: 'env-1',
        projectName: 'dc-order',
        currentTag: 'v1.9.0',
        targetTag: 'v1.9.0',
        muted: true,
        enabled: false,
      );

      final tag = ArgoCdService.buildUpsertTag(stored, 'env-1', 'dc-order', 'v2.0.0', 'v1.9.0');
      expect(tag.id, 'env-1_dc-order');
      expect(tag.currentTag, 'v2.0.0');
      expect(tag.targetTag, 'v1.9.0');
      expect(tag.muted, isTrue);
      expect(tag.enabled, isFalse);
      expect(tag.lastChecked, isNotNull);
    });

    test('buildUpsertTag 无已有行时按调用方传入的目标 Tag 建首行', () {
      final tag = ArgoCdService.buildUpsertTag(null, 'env-1', 'dc-pay', 'v3.0.0', 'v3.0.0');
      expect(tag.targetTag, 'v3.0.0');
      expect(tag.muted, isFalse);
      expect(tag.enabled, isTrue);
    });
  });

  group('OpsNotifier 通知通道 Tests', () {
    test('非 macOS 环境为 no-op，不调用 dispatch', () async {
      var called = false;
      await OpsNotifier.showNotification(
        title: 't',
        body: 'b',
        isMac: false,
        dispatch: (_) async => called = true,
      );
      expect(called, isFalse);
    });

    test('macOS 环境走 osascript 文案并转义引号', () async {
      String? args;
      await OpsNotifier.showNotification(
        title: 'ArgoCD Tag 变更',
        body: '行1 "带引号"\n行2',
        isMac: true,
        dispatch: (a) async => args = a,
      );
      expect(args, isNotNull);
      expect(args, contains('display notification'));
      expect(args, contains('V8 运维工具'));
      expect(args, isNot(contains('"带引号"'))); // 引号已转义
      expect(args, isNot(contains('\n'))); // 换行已替换为空格
      expect(args, contains('行1 '));
      expect(args, contains('行2'));
    });

    test('subtitle 会附加为副标题参数', () async {
      String? args;
      await OpsNotifier.showNotification(
        title: 't',
        body: 'b',
        subtitle: '子标题',
        isMac: true,
        dispatch: (a) async => args = a,
      );
      expect(args, contains('subtitle "子标题"'));
    });
  });

  group('ArgoCD Tag Monitoring & Rewriting Tests', () {
    const sampleYaml = '''apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-service
spec:
  template:
    spec:
      containers:
        - name: app
          Image:
            Repository: registry.example.com/demo-service
            Tag: v1.0.5
            PullPolicy: IfNotPresent
''';

    test('extractImageTag extracts Tag correctly', () {
      final tag = ArgoCdService.extractImageTag(sampleYaml);
      expect(tag, 'v1.0.5');
    });

    test('replaceImageTag updates Tag while preserving indentation', () {
      final replaced = ArgoCdService.replaceImageTag(sampleYaml, 'v2.0.0');
      expect(replaced, contains('Tag: v2.0.0'));
      expect(ArgoCdService.extractImageTag(replaced), 'v2.0.0');
    });
  });
  group('ArgoCD 服务文件过滤 Tests', () {
    test('isServiceValueFile 只接受 values- 前缀的 yaml/yml', () {
      expect(ArgoCdService.isServiceValueFile('values-a.yaml'), isTrue);
      expect(ArgoCdService.isServiceValueFile('values-a.yml'), isTrue);
      expect(ArgoCdService.isServiceValueFile('VALUES-A.YAML'), isTrue);
    });

    test('isServiceValueFile 排除非服务文件', () {
      expect(ArgoCdService.isServiceValueFile('Chart.yaml'), isFalse);
      expect(ArgoCdService.isServiceValueFile('demo.yaml'), isFalse);
      expect(ArgoCdService.isServiceValueFile('.gitlab-ci.yml'), isFalse);
      expect(ArgoCdService.isServiceValueFile('values-a.txt'), isFalse);
      expect(ArgoCdService.isServiceValueFile('values'), isFalse);
      // 带目录前缀时只看文件名段
      expect(ArgoCdService.isServiceValueFile('argocd/projects/values-a.yaml'), isTrue);
      expect(ArgoCdService.isServiceValueFile('argocd/projects/Chart.yaml'), isFalse);
    });
  });

  group('ArgoCD Tag 值引号剥离 Tests', () {
    test('双引号 tag 被剥离', () {
      const yaml = 'image:\n  tag: "1.6.24.0-54f4f991"\n';
      expect(ArgoCdService.extractImageTag(yaml), '1.6.24.0-54f4f991');
    });

    test('单引号 tag 被剥离', () {
      const yaml = "image:\n  Tag: 'v1'\n";
      expect(ArgoCdService.extractImageTag(yaml), 'v1');
    });

    test('无引号 tag 保持不变', () {
      const yaml = 'image:\n  tag: v1.0.5\n';
      expect(ArgoCdService.extractImageTag(yaml), 'v1.0.5');
    });
  });

  group('ArgoCD 分页翻页 Tests', () {
    test('真实形态的 Link 头（含 id/path/recursive/ref）解出 next', () {
      const header =
          '<https://host/api/v4/projects/60/repository/tree?id=60&page=2&path=argocd%2Fprojects&per_page=100&recursive=false&ref=master>; rel="next", '
          '<https://host/api/v4/projects/60/repository/tree?id=60&page=1&path=argocd%2Fprojects&per_page=100&recursive=false&ref=master>; rel="first", '
          '<https://host/api/v4/projects/60/repository/tree?id=60&page=2&path=argocd%2Fprojects&per_page=100&recursive=false&ref=master>; rel="last"';
      expect(
        GitLabClient.linkNextUrl(header),
        'https://host/api/v4/projects/60/repository/tree?id=60&page=2&path=argocd%2Fprojects&per_page=100&recursive=false&ref=master',
      );
    });

    test('末页无 next 时返回 null', () {
      const header =
          '<https://host/api/v4/projects/60/repository/tree?id=60&page=1&path=argocd%2Fprojects&per_page=100&recursive=false&ref=master>; rel="first", '
          '<https://host/api/v4/projects/60/repository/tree?id=60&page=1&path=argocd%2Fprojects&per_page=100&recursive=false&ref=master>; rel="last"';
      expect(GitLabClient.linkNextUrl(header), isNull);
    });
  });

  group('GitLabClient 认证语义 Tests', () {
    test('配置了 PAT：ensureToken 后 token 直接生效', () async {
      final client = GitLabClient(GitlabConfig(
        url: 'https://gitlab.example.internal/repository/config',
        username: '',
        password: '',
        token: 'pat-abc123',
      ));
      await client.ensureToken();
      expect(client.debugToken, 'pat-abc123');
    });

    test('配置了 PAT：token 前后空白被 trim（否则 PRIVATE-TOKEN 头带空格会 401）',
        () async {
      final client = GitLabClient(GitlabConfig(
        url: 'https://gitlab.example.internal/repository/config',
        username: '',
        password: '',
        token: '  pat-with-space  ',
      ));
      await client.ensureToken();
      expect(client.debugToken, 'pat-with-space');
    });

    test('未配 PAT 且凭据为空：登录失败并提示配置 PAT', () async {
      final client = GitLabClient(GitlabConfig(
        url: 'https://gitlab.example.internal/repository/config',
        username: '',
        password: '',
      ));
      await expectLater(
        client.ensureToken(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Personal Access Token'),
        )),
      );
    });
  });

  group('GitLabClient URL 构造回归 Tests', () {
    test('tree 列举 URL 只含一个问号且带 path=', () async {
      // 回归点：曾多拼一个 `?` 得到 `tree??path=...`。GitLab 把第二个 `?` 当作
      // 参数名的一部分（Link 头回写 `?%3Fpath=`），导致 path 参数不存在、
      // tree 退化为仓库根目录。此处锁住 `Uri(queryParameters:)` 已自带前导 `?`。
      final query = Uri(queryParameters: {
        'path': 'argocd/projects',
        'ref': 'master',
        'per_page': '100',
      }).toString();
      expect(query.startsWith('?'), isTrue);
      expect(query.contains('??'), isFalse);

      final url = 'https://host/api/v4/projects/60/repository/tree$query';
      expect(url.contains('??'), isFalse);
      expect(url, contains('tree?path=argocd%2Fprojects'));
      expect(url, contains('ref=master'));
      expect(url, contains('per_page=100'));
    });
  });
}
