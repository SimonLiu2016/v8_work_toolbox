import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/services/password_health.dart';
import 'package:V8WorkToolbox/tools/password/vault_models.dart';

void main() {
  late PasswordHealth health;

  setUp(() {
    health = PasswordHealth();
  });

  group('强度评分', () {
    test('空密码 0 分', () {
      expect(health.score(''), 0);
    });

    test('常见弱密码得分极低', () {
      expect(health.score('password'), lessThan(PasswordHealth.weakThreshold));
      expect(health.score('123456'), lessThan(PasswordHealth.weakThreshold));
      expect(health.score('qwerty'), lessThan(PasswordHealth.weakThreshold));
    });

    test('强密码得分高', () {
      final score = health.score('X#9kL\$mQ2!vB@7nP4zW');
      expect(score, greaterThanOrEqualTo(PasswordHealth.strongThreshold));
    });

    test('长度提升得分', () {
      final short = health.score('aB1!');
      final long = health.score('aB1!xY9#mK4\$pQ7z');
      expect(long, greaterThan(short));
    });

    test('纯数字受罚', () {
      final digits = health.score('9876543210');
      final mixed = health.score('98765fG!10');
      expect(digits, lessThan(mixed));
    });

    test('连续序列受罚', () {
      final seq = health.score('abcdefgh1!A');
      final nonSeq = health.score('axcpeqgh1!A');
      expect(seq, lessThan(nonSeq));
    });

    test('键盘行走受罚', () {
      final walk = health.score('qwerty99A!');
      final noWalk = health.score('qpwoei99A!');
      expect(walk, lessThan(noWalk));
    });

    test('分档标签', () {
      expect(health.band(0), 'weak');
      expect(health.band(39), 'weak');
      expect(health.band(40), 'medium');
      expect(health.band(69), 'medium');
      expect(health.band(70), 'strong');
      expect(health.band(100), 'strong');
    });

    test('得分范围 0–100', () {
      for (final pwd in ['', 'a', 'password123', 'X#9kL\$mQ2!vB@7nP4zWxY8&']) {
        final s = health.score(pwd);
        expect(s, inInclusiveRange(0, 100));
      }
    });
  });

  group('重复检测聚类', () {
    test('同密码条目聚为一组，单例不报', () {
      final dups = health.findDuplicates({
        'id1': 'shared-pass',
        'id2': 'shared-pass',
        'id3': 'unique-pass',
        'id4': 'shared-pass',
        'id5': '',
      });

      expect(dups.length, 1);
      expect(dups['shared-pass'], containsAll(['id1', 'id2', 'id4']));
    });

    test('空密码不参与聚类', () {
      final dups = health.findDuplicates({'id1': '', 'id2': ''});
      expect(dups, isEmpty);
    });
  });

  group('年龄标记', () {
    VaultItem makeItem(String id, int daysOld) {
      final now = DateTime.now();
      final pwdDate = now.subtract(Duration(days: daysOld));
      return VaultItem(
        id: id,
        type: VaultEntryType.login,
        title: 'Item$id',
        createdAt: pwdDate,
        updatedAt: pwdDate,
        passwordUpdatedAt: pwdDate,
        secretRef: 'sec_$id',
      );
    }

    test('超过 180 天的 login 条目被标记', () {
      final items = [
        makeItem('old', 200),
        makeItem('fresh', 30),
        makeItem('edge', 181),
      ];
      final aged = health.findAged(items);
      expect(aged.map((e) => e.id), containsAll(['old', 'edge']));
      expect(aged.map((e) => e.id), isNot(contains('fresh')));
    });

    test('note/totp 类型不参与年龄标记', () {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 300));
      final note = VaultItem(
        id: 'note1',
        type: VaultEntryType.note,
        title: 'Note',
        createdAt: old,
        updatedAt: old,
        passwordUpdatedAt: old,
        secretRef: 'sec_note1',
      );
      expect(health.findAged([note]), isEmpty);
    });
  });
}
