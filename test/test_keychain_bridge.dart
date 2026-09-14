import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

/// 测试用内存 Keychain 桥（flutter test 无平台通道，真实 Keychain 不可用）
///
/// 用法（任一测试文件 setUp 中）：
///   TestKeychainBridge.install();
class TestKeychainBridge implements KeychainBridge {
  static final Map<String, String> store = {};

  static void install() {
    store.clear();
  }

  static KekManager makeManager() => KekManager(bridge: TestKeychainBridge());

  @override
  Future<String?> read({required String service, required String account}) async {
    return store['$service/$account'];
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    store['$service/$account'] = value;
  }

  @override
  Future<void> delete({required String service, required String account}) async {
    store.remove('$service/$account');
  }
}
