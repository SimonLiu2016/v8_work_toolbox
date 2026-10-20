import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/artex_engine/models/artex_engine_state.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_image_build_service.dart';

/// 失败分类的提示必须真正「可操作」（task 6.3 的行为契约）。
///
/// 这里不测匹配逻辑（那在 artex_build_failure_test.dart），测的是
/// **每一类失败给出的动作指引是否指向真实存在的东西**——一个指向不存在
/// 的设置项的提示比没有提示更糟。
void main() {
  group('每类失败都有一个用户能执行的动作', () {
    test('dockerUnavailable 指向 Docker Desktop', () {
      expect(
        ArtexBuildFailureKind.dockerUnavailable.hint,
        contains('Docker Desktop'),
      );
    });

    test('mirrorForbidden 指向 Docker Engine 的 registry-mirrors', () {
      expect(
        ArtexBuildFailureKind.mirrorForbidden.hint,
        contains('registry-mirrors'),
      );
    });

    test('networkTimeout 与 chromiumDownload 都提示检查 VPN', () {
      expect(ArtexBuildFailureKind.networkTimeout.hint, contains('VPN'));
      expect(ArtexBuildFailureKind.chromiumDownload.hint, contains('VPN'));
    });

    test('chromiumDownload 额外说明有缓存可重试（避免用户以为全白跑）', () {
      expect(
        ArtexBuildFailureKind.chromiumDownload.hint,
        contains('缓存'),
      );
    });

    test('missingEnv 说明要生成默认 .env', () {
      expect(ArtexBuildFailureKind.missingEnv.hint, contains('.env'));
    });
  });

  group('状态机不变量（spec: 容器启停与状态呈现）', () {
    test('failed 之外的 status 不要求 failure 非空', () {
      const s = ArtexEngineState(status: ArtexEngineStatus.idle);
      expect(s.failure, isNull);
      expect(s.isBusy, isFalse);
    });

    test('只有 running 允许打开工作台', () {
      ArtexEngineStatus.values.where((s) => s != ArtexEngineStatus.running).forEach((s) {
        expect(
          ArtexEngineState(status: s).canOpenWorkspace,
          isFalse,
          reason: '$s 不应允许打开工作台',
        );
      });
      expect(
        const ArtexEngineState(
          status: ArtexEngineStatus.running,
        ).canOpenWorkspace,
        isTrue,
      );
    });

    test('starting 与 stopping 视为忙，禁止重复触发', () {
      expect(
        const ArtexEngineState(
          status: ArtexEngineStatus.starting,
        ).isBusy,
        isTrue,
      );
      expect(
        const ArtexEngineState(
          status: ArtexEngineStatus.stopping,
        ).isBusy,
        isTrue,
      );
    });

    test('cleared() 清掉失败信息并回到 idle', () {
      const s = ArtexEngineState(
        status: ArtexEngineStatus.failed,
        failure: 'x',
        failureDetail: 'y',
        containerLogTail: ['a'],
      );
      final c = s.cleared();
      expect(c.status, ArtexEngineStatus.idle);
      expect(c.failure, isNull);
      expect(c.failureDetail, isNull);
      expect(c.containerLogTail, isEmpty);
    });

    test('cleared() 一并清掉回连候选列表', () {
      const s = ArtexEngineState(
        status: ArtexEngineStatus.failed,
        failureKind: ArtexEngineFailureKind.callbackAddrAmbiguous,
        failure: 'x',
        callbackCandidates: ['192.168.1.3', '10.0.0.5'],
      );
      expect(s.cleared().callbackCandidates, isEmpty);
    });

    test('回连候选列表可经 copyWith 带过去', () {
      const s = ArtexEngineState.initial();
      final withCandidates = s.copyWith(
        callbackCandidates: const ['192.168.1.3'],
      );
      expect(withCandidates.callbackCandidates, ['192.168.1.3']);
    });
  });

  group('新增失败类别有面向用户的标签', () {
    test('回连地址相关的三个类别都有非空 label', () {
      // UI 直接把 label 显示给用户，空标签等于显示空白。
      for (final kind in const [
        ArtexEngineFailureKind.callbackAddrMissing,
        ArtexEngineFailureKind.callbackAddrAmbiguous,
        ArtexEngineFailureKind.hostNetworkRejected,
      ]) {
        expect(kind.label.trim(), isNotEmpty, reason: '$kind 缺少 label');
      }
    });
  });
}
