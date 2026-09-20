import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/allowlist_consolidation_service.dart';

void main() {
  // 用户真实案例：三条语义相同的 deploy 规则
  const deployA =
      r'^rm -rf /Applications/V8WorkToolbox\.app && mv /tmp/deploy/V8WorkToolbox\.app /Applications/ && echo "=== deployed ===" && shasum -a 256 /Applications/V8WorkToolbox\.app/Contents/MacOS/V8WorkToolbox \| cut -c1-16 && stat -f "%Sm  %N" /Applications/V8WorkToolbox\.app/Contents/MacOS/V8WorkToolbox && du -sh /Applications/V8WorkToolbox\.app$';
  const deployB =
      r'^rm -rf /Applications/V8WorkToolbox\.app && cp -a build/macos/Build/Products/Release/V8WorkToolbox\.app /Applications/ && echo "deployed" && du -sh /Applications/V8WorkToolbox\.app$';
  const deployC =
      r'^rm -rf /Applications/V8WorkToolbox\.app && mv /tmp/deploy/V8WorkToolbox\.app /Applications/ && echo "=== DEPLOYED ===" && shasum -a 256 /Applications/V8WorkToolbox\.app/Contents/Frameworks/App\.framework/Versions/A/App \| cut -c1-24 && stat -f "%Sm  %N" /Applications/V8WorkToolbox\.app/Contents/Frameworks/App\.framework/Versions/A/App && du -sh /Applications/V8WorkToolbox\.app$';

  group('extractAnchors', () {
    test('提取首个动词与反转义路径', () {
      final a = AllowlistConsolidationService.extractAnchors(deployA);
      expect(a.verb, 'rm');
      expect(a.paths, contains('/Applications/V8WorkToolbox.app'));
      expect(a.paths, contains('/tmp/deploy/V8WorkToolbox.app'));
    });

    test('转义空格与点号被还原', () {
      final a = AllowlistConsolidationService.extractAnchors(
          r'^rm\ \-rf\ /Applications/My\ App\.app$');
      expect(a.paths, contains('/Applications/My App.app'));
    });

    test('无路径规则返回空路径集', () {
      final a = AllowlistConsolidationService.extractAnchors(r'^git push .*$');
      expect(a.verb, 'git');
      expect(a.paths, isEmpty);
    });
  });

  group('isSameCluster / clusterRules', () {
    test('三条 deploy 规则同簇（尾部差异不影响锚点）', () {
      final clusters = AllowlistConsolidationService.clusterRules([deployA, deployB, deployC]);
      expect(clusters.length, 1);
      expect(clusters.first.toSet(), {0, 1, 2});
    });

    test('不同 App 目标路径不同簇', () {
      const other =
          r'^rm -rf /Applications/OtherApp\.app && mv /tmp/deploy/OtherApp\.app /Applications/$';
      final clusters = AllowlistConsolidationService.clusterRules([deployA, other]);
      expect(clusters, isEmpty);
    });

    test('不同动词不同簇', () {
      const reader = r'^cat /Applications/V8WorkToolbox\.app/Contents/Info\.plist$';
      final clusters = AllowlistConsolidationService.clusterRules([deployA, reader]);
      expect(clusters, isEmpty);
    });

    test('单规则不成簇，untouched 覆盖全部', () {
      const gitRule = r'^git push origin main$';
      final rules = [deployA, deployB, gitRule];
      final clusters = AllowlistConsolidationService.clusterRules(rules);
      final untouched = AllowlistConsolidationService.untouchedIndices(rules, clusters);
      expect(clusters.length, 1);
      expect(untouched, [2]);
    });
  });

  group('localPreTidy', () {
    test('去重保序', () {
      final out = AllowlistConsolidationService.localPreTidy([' a ', 'b', 'a', ' c ']);
      expect(out, ['a', 'b', 'c']);
    });

    test('连接符边界前缀合并保留更通用的短规则', () {
      final out = AllowlistConsolidationService.localPreTidy([
        r'^git fetch$',
        r'^git fetch$ && git rebase origin/main$',
        r'^git fetch$ && git gc$',
      ]);
      expect(out, [r'^git fetch$']);
    });

    test('锚点不同则不做前缀合并（行尾锚点挡住）', () {
      final out = AllowlistConsolidationService.localPreTidy([
        r'^git fetch$',
        r'^git fetch origin main$',
        r'^git fetch --all$',
      ]);
      expect(out.length, 3);
    });

    test('空行被剔除', () {
      final out = AllowlistConsolidationService.localPreTidy(['', '  ', 'x']);
      expect(out, ['x']);
    });
  });

  group('validateMergedRule（三重校验闸门）', () {
    test('合法合并通过', () {
      const merged =
          r'^rm -rf /Applications/V8WorkToolbox\.app && (mv|cp -a) \S+V8WorkToolbox\.app /Applications/';
      final reason = AllowlistConsolidationService.validateMergedRule(merged, [deployA, deployB]);
      expect(reason, isNull);
    });

    test('回验失败被拦截（漏掉一条原规则）', () {
      // 只允许 mv，deployB 用 cp -a → 回验失败
      const merged =
          r'^rm -rf /Applications/V8WorkToolbox\.app && mv \S+V8WorkToolbox\.app /Applications/';
      final reason = AllowlistConsolidationService.validateMergedRule(merged, [deployA, deployB]);
      expect(reason, ConsolidationRejection.coverageLost);
    });

    test('黑名单交叉被拦截（吞掉 curl | bash）', () {
      // 宽规则放行"下载脚本并执行"，命中危险样本
      const merged = r'^curl https://scripts\.example\.com/.* \| bash$';
      final reason = AllowlistConsolidationService.validateMergedRule(merged, [
        r'^curl https://scripts\.example\.com/setup\.sh \| bash$',
        r'^curl https://scripts\.example\.com/deploy\.sh \| bash$',
      ]);
      expect(reason, ConsolidationRejection.denylistCrossed);
    });

    test('黑名单交叉被拦截（吞掉 git push --force）', () {
      const merged = r'^git push .*$';
      final reason = AllowlistConsolidationService.validateMergedRule(merged, [
        r'^git push origin main$',
      ]);
      expect(reason, ConsolidationRejection.denylistCrossed);
    });

    test('非法正则被拦截', () {
      final reason = AllowlistConsolidationService.validateMergedRule(
        r'^rm -rf /[unclosed$',
        [r'^rm -rf /tmp/x$'],
      );
      expect(reason, ConsolidationRejection.invalidRegex);
    });

    test('空规则被拦截', () {
      final reason = AllowlistConsolidationService.validateMergedRule('   ', [deployA]);
      expect(reason, ConsolidationRejection.invalidRegex);
    });
  });

  group('representativeCommand', () {
    test('去锚点并反转义', () {
      final rep = AllowlistConsolidationService.representativeCommand(
          r'^rm\ \-rf\ /Applications/V8WorkToolbox\.app$');
      expect(rep, 'rm -rf /Applications/V8WorkToolbox.app');
    });
  });

  group('applyPlan', () {
    test('未覆盖规则保留 + 宽规则追加', () {
      const gitRule = r'^git fetch$';
      final plan = ConsolidationPlan(
        tidiedRules: const [deployA, deployB, deployC, gitRule],
        untouched: const [3],
        groups: const [
          MergeGroup(
            summary: 'deploy',
            mergedRule: r'^rm -rf /Applications/V8WorkToolbox\.app && (mv|cp -a).*$',
            covers: [0, 1, 2],
            coveredRules: [],
          ),
        ],
      );
      final out = AllowlistConsolidationService.applyPlan(plan);
      expect(out, contains(gitRule));
      expect(out.length, 2);
      expect(out.last, contains('mv|cp -a'));
    });
  });
}
