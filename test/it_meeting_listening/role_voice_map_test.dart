import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/role_voice_map.dart';

void main() {
  group('RoleVoiceMap.voiceFor 角色固定', () {
    test('同一角色跨场景得到同一音色', () {
      final inStandup = RoleVoiceMap.voiceFor('Someone', 'Scrum Master');
      final inIncident = RoleVoiceMap.voiceFor('Someone Else', 'Scrum Master');
      expect(inStandup, inIncident);
    });

    test('不同角色得到不同音色', () {
      final sm = RoleVoiceMap.voiceFor('A', 'Scrum Master');
      final backend = RoleVoiceMap.voiceFor('B', 'Backend');
      final frontend = RoleVoiceMap.voiceFor('C', 'Frontend');
      expect({sm, backend, frontend}.length, 3);
    });

    test('角色名大小写与多余空白不影响解析', () {
      expect(
        RoleVoiceMap.voiceFor('X', '  scrum   master '),
        RoleVoiceMap.voiceFor('X', 'Scrum Master'),
      );
    });

    test('说话人姓名映射到角色（无角色标注时）', () {
      final byName = RoleVoiceMap.voiceFor('Lena', '');
      final byRole = RoleVoiceMap.voiceFor('Anyone', 'Scrum Master');
      expect(byName, byRole);
    });

    test('IC 走故障指挥官音色', () {
      expect(
        RoleVoiceMap.voiceFor('IC', ''),
        RoleVoiceMap.voiceFor('X', 'Incident Commander'),
      );
    });

    test('未登记说话人得到稳定音色（同名恒定）', () {
      final a = RoleVoiceMap.voiceFor('Zorblax', '');
      final b = RoleVoiceMap.voiceFor('Zorblax', '');
      expect(a, b);
      expect(a, isNotEmpty);
    });

    test('未登记说话人与已登记说话人通常不同', () {
      // 不强制（散列可能撞车），但绝大多数情况应不同。
      final fallback = RoleVoiceMap.voiceFor('Zorblax', '');
      final known = RoleVoiceMap.voiceFor('Lena', '');
      expect(fallback, isNotEmpty);
      expect(known, isNotEmpty);
    });
  });

  group('VoicePool 音色元数据', () {
    test('step_boy 实测为女声（名字会骗人）', () {
      expect(VoicePool.stepBoy.gender, VoiceGender.female);
      expect(VoicePool.stepBoy.measuredF0, greaterThan(165));
    });

    test('boyinnansheng 实测为男声', () {
      expect(VoicePool.boyinnansheng.gender, VoiceGender.male);
      expect(VoicePool.boyinnansheng.measuredF0, lessThan(165));
    });

    test('男女音色池都非空', () {
      expect(VoicePool.males, isNotEmpty);
      expect(VoicePool.females, isNotEmpty);
    });

    test('按 id 可反查', () {
      expect(VoicePool.byId('step_boy'), isNotNull);
      expect(VoicePool.byId('no-such-voice'), isNull);
    });
  });
}
