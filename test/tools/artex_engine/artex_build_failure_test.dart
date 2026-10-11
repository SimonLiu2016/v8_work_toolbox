import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_image_build_service.dart';

/// 镜像构建失败诊断的匹配表（task 6.3 / 6.4 / 6.5）。
///
/// 这些用例里的字符串**不是编的**——全部来自 2026-10-10 spike 的真实输出
/// 或 docker 的标准错误文案。测试为验证诊断逻辑，不为适配实现。
void main() {
  group('已知失败模式各归其类（task 6.3）', () {
    test('Docker 守护进程不可达', () {
      const out =
          'Cannot connect to the Docker daemon at unix:///Users/simon/.docker/run/docker.sock. '
          'Is the docker daemon running?';
      expect(
        classifyBuildFailure(out),
        ArtexBuildFailureKind.dockerUnavailable,
      );
      expect(
        ArtexBuildFailureKind.dockerUnavailable.hint,
        contains('Docker Desktop'),
      );
    });

    test('镜像加速器 403（spike 实际踩到的）', () {
      // spike 第一次构建就是死在这条：阿里云 mirror 对 docker/dockerfile 返回 403。
      const out =
          '#3 resolve image config for docker-image://docker.io/docker/dockerfile:1\n'
          '#3 ERROR: unexpected status from HEAD request to '
          'https://vjqci0ng.mirror.aliyuncs.com/v2/docker/dockerfile/manifests/1?ns=docker.io: 403 Forbidden\n'
          'failed to solve: failed to resolve source metadata for docker.io/docker/dockerfile:1';
      expect(classifyBuildFailure(out), ArtexBuildFailureKind.mirrorForbidden);
      expect(
        ArtexBuildFailureKind.mirrorForbidden.hint,
        contains('registry-mirrors'),
      );
    });

    test('网络超时', () {
      const out =
          'Error response from daemon: Get "https://registry-1.docker.io/v2/": '
          'net/http: request canceled while waiting for connection '
          '(Client.Timeout exceeded while awaiting headers)';
      expect(classifyBuildFailure(out), ArtexBuildFailureKind.networkTimeout);
      expect(ArtexBuildFailureKind.networkTimeout.hint, contains('VPN'));
    });

    test('缺少 POSTGRES_PASSWORD', () {
      const out =
          'error while interpolating services.artex.environment.ARTEX_PG_DSN: '
          'required variable POSTGRES_PASSWORD is missing a value';
      expect(classifyBuildFailure(out), ArtexBuildFailureKind.missingEnv);
    });
  });

  group('playwright 专项识别（task 6.4）', () {
    test('playwright install 失败归为 chromiumDownload 而不是泛网络错', () {
      const out =
          '#24 12.3 Failed to install browsers\n'
          'Error: Failed to download chromium via playwright install';
      expect(
        classifyBuildFailure(out),
        ArtexBuildFailureKind.chromiumDownload,
      );
      // 提示必须说明：已完成的层有缓存，重试不从零开始
      expect(
        ArtexBuildFailureKind.chromiumDownload.hint,
        contains('缓存'),
      );
    });

    test('azureedge 下载地址失败同样识别', () {
      const out = 'Get "https://playwright.azureedge.net/...": dial tcp: i/o timeout';
      expect(
        classifyBuildFailure(out),
        ArtexBuildFailureKind.chromiumDownload,
      );
    });

    test('nodesource 失败同样识别（不受 APT_MIRROR 控制）', () {
      const out = '+ curl -fsSL https://deb.nodesource.com/setup_20.x\ncurl: (6) no such host';
      expect(
        classifyBuildFailure(out),
        ArtexBuildFailureKind.chromiumDownload,
      );
    });
  });

  group('未知错误回退（task 6.5）', () {
    test('未命中任何模式时归为 unknown，保留原始输出可诊断', () {
      const out = 'some totally unexpected docker failure';
      final kind = classifyBuildFailure(out);
      expect(kind, ArtexBuildFailureKind.unknown);
      expect(kind.label, contains('构建失败'));
    });

    test('空输出也归为 unknown 而不抛', () {
      expect(classifyBuildFailure(''), ArtexBuildFailureKind.unknown);
    });

    test('大小写不敏感', () {
      expect(
        classifyBuildFailure('CANNOT CONNECT TO THE DOCKER DAEMON'),
        ArtexBuildFailureKind.dockerUnavailable,
      );
    });
  });

  group('每一类都有可操作提示', () {
    test('所有失败类别的 hint 非空', () {
      for (final kind in ArtexBuildFailureKind.values) {
        expect(
          kind.hint.trim(),
          isNotEmpty,
          reason: '${kind.name} 缺少用户可操作的提示',
        );
        expect(kind.label.trim(), isNotEmpty);
      }
    });
  });
}
