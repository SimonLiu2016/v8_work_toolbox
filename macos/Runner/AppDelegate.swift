import ApplicationServices
import Carbon
import Cocoa
import FlutterMacOS
import Foundation

@main
class AppDelegate: FlutterAppDelegate {

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    super.applicationDidFinishLaunching(aNotification)

    // 延迟初始化通道，确保Flutter引擎完全加载
    DispatchQueue.main.async {
      self.initMethodChannelIfNeeded()
    }
  }

  private let channelName = "app_manager_channel"
  private var channelInitialized = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override var mainFlutterWindow: NSWindow? {
    didSet {
      // 确保在窗口设置完成后初始化通道
      DispatchQueue.main.async {
        if !self.channelInitialized {
          self.initMethodChannelIfNeeded()
        }
      }
    }
  }

  private func initMethodChannelIfNeeded() {
    guard !channelInitialized else { return }

    guard let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      print("无法获取FlutterViewController")
      return
    }

    let channel = FlutterMethodChannel(
      name: self.channelName, binaryMessenger: controller.engine.binaryMessenger)

    // 处理Flutter端的方法调用
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "selectAppPackage":
        self?.selectAppPackage(completion: result)
      case "readInfoPlist":
        guard let args = call.arguments as? [String: String], let appPath = args["appPath"] else {
          result(FlutterError(code: "INVALID_ARGS", message: "参数错误", details: nil))
          return
        }
        self?.readInfoPlist(appPath: appPath, completion: result)
      case "getAppShortcuts":
        guard let arguments = call.arguments as? [String: Any],
          let appName = arguments["appName"] as? String
        else {
          result(
            FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
          return
        }

        if let strongSelf = self {
          let shortcuts = strongSelf.getAppShortcuts(for: appName)
          result(shortcuts)
        } else {
          result([])
        }
      case "getRunningApps":
        if let strongSelf = self {
          let runningApps = strongSelf.getRunningApps()
          result(runningApps)
        } else {
          result([])
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    channelInitialized = true
    print("MethodChannel已初始化")
  }

  private func initMethodChannel() {
    // 为了向后兼容，调用新的方法
    initMethodChannelIfNeeded()
  }

  // 选择.app包并解析其内部文件
  private func selectAppPackage(completion: @escaping FlutterResult) {
    print("开始选择app包")
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = true  // 允许选择文件
    openPanel.canChooseDirectories = true  // 允许选择目录
    openPanel.allowsMultipleSelection = false
    openPanel.title = "选择应用程序包"
    openPanel.directoryURL = URL(fileURLWithPath: "/Applications")  // 默认打开/Applications目录

    // 设置为仅显示目录
    openPanel.showsHiddenFiles = false
    openPanel.canCreateDirectories = false

    print("即将显示openPanel")
    openPanel.begin { response in
      print("收到选择响应: \(response)")
      if response == .OK, let appURL = openPanel.url {
        print("选择的URL: \(appURL.path)")
        // 验证是否为.app包
        if appURL.path.lowercased().hasSuffix(".app") {
          print("验证为.app包，开始解析")
          // 解析.app包内的文件列表
          do {
            let contents = try FileManager.default.contentsOfDirectory(
              at: appURL,
              includingPropertiesForKeys: nil,
              options: [.skipsHiddenFiles]
            )
            let filePaths = contents.map { $0.path }
            print("解析完成，返回结果")
            // 返回结果给Flutter：包含.app路径和内部文件列表
            completion([
              "appPath": appURL.path,
              "filePaths": filePaths,
            ])
          } catch {
            print("解析.app包失败: \(error.localizedDescription)")
            completion(
              FlutterError(
                code: "PARSE_FAILED",
                message: "解析.app包失败：\(error.localizedDescription)",
                details: nil
              ))
          }
        } else {
          print("选择的不是有效的.app包")
          completion(
            FlutterError(
              code: "INVALID_APP_BUNDLE",
              message: "选择的不是有效的.app应用程序包",
              details: nil
            ))
        }
      } else {
        print("用户取消选择")
        // 用户取消选择
        completion(
          FlutterError(
            code: "USER_CANCEL",
            message: "用户取消了选择",
            details: nil
          ))
      }
    }
    print("openPanel已开始")
  }

  // 读取.app包内的Info.plist文件
  private func readInfoPlist(appPath: String, completion: @escaping FlutterResult) {
    let appURL = URL(fileURLWithPath: appPath)
    let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")

    do {
      let data = try Data(contentsOf: infoPlistURL)
      guard
        let plist = try PropertyListSerialization.propertyList(
          from: data,
          format: nil
        ) as? [String: Any]
      else {
        completion(
          FlutterError(
            code: "PLIST_PARSE_FAILED",
            message: "Info.plist格式错误",
            details: nil
          ))
        return
      }

      // 提取关键信息返回给Flutter
      completion([
        "name": plist["CFBundleName"] ?? "未知",
        "bundleId": plist["CFBundleIdentifier"] ?? "未知",
        "version": plist["CFBundleShortVersionString"] ?? "未知",
      ])
    } catch {
      completion(
        FlutterError(
          code: "READ_FAILED",
          message: "读取Info.plist失败：\(error.localizedDescription)",
          details: nil
        ))
    }
  }

  // MARK: - App Shortcuts Methods

  private let appShortcutsHandler = AppShortcutsHandler()

  private func getAppShortcuts(for appName: String) -> [[String: String]] {
    return appShortcutsHandler.getAppShortcuts(for: appName)
  }

  private func getRunningApps() -> [[String: String]] {
    return appShortcutsHandler.getRunningApps()
  }

}
