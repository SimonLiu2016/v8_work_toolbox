import ApplicationServices
import Carbon
import Cocoa
import FlutterMacOS
import Foundation

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {

  static weak var shared: AppDelegate?

  private let channelName = "app_manager_channel"
  private let launcherChannelName = "v8_work_toolbox/launcher"
  private var channelInitialized = false

  private var statusItem: NSStatusItem?
  private var hotKeyRef: EventHotKeyRef?
  private var hotKeyHandlerInstalled = false
  private var launcherChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    super.applicationDidFinishLaunching(aNotification)
    AppDelegate.shared = self

    setupStatusItem()
    installCarbonEventHandlerIfNeeded()
    // 默认注册 ⌥Space (modifiers: 2048, keyCode: 49)
    _ = registerHotKey(modifiers: UInt32(optionKey), keyCode: 49)

    // 延迟初始化通道，确保Flutter引擎完全加载
    DispatchQueue.main.async {
      self.initMethodChannelIfNeeded()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭窗口不退出应用，转入后台驻留
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // 点击程序坞图标时，若窗口隐藏则重新唤起展示
    if !flag {
      showMainWindow()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override var mainFlutterWindow: NSWindow? {
    didSet {
      mainFlutterWindow?.delegate = self
      // 确保在窗口设置完成后初始化通道
      DispatchQueue.main.async {
        if !self.channelInitialized {
          self.initMethodChannelIfNeeded()
        }
      }
    }
  }

  // MARK: - Window Delegate
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // 点击红叉只隐藏窗口，不退出进程
    sender.orderOut(nil)
    return false
  }

  // MARK: - Status Item (Menu Bar)
  private var statusMenu: NSMenu?

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem?.isVisible = true
    guard let button = statusItem?.button else { return }

    // 使用系统标准 SF 符号与原生标题双保险，保证深浅色菜单栏稳定可见
    if #available(macOS 11.0, *) {
      let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
      let symbolImage = NSImage(
        systemSymbolName: "wrench.and.screwdriver.fill",
        accessibilityDescription: "V8"
      )?.withSymbolConfiguration(config)
      symbolImage?.isTemplate = true
      button.image = symbolImage
      button.imagePosition = .imageLeading
    }
    button.title = " V8"
    button.toolTip = "V8 工作工具箱 (⌥Space)"

    // 创建右键/次级操作菜单
    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "打开主窗口 (⌥Space)",
      action: #selector(showMainWindowFromMenu),
      keyEquivalent: "o"
    )
    openItem.target = self
    menu.addItem(openItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "退出 V8 工作工具箱",
      action: #selector(quitApp),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)

    self.statusMenu = menu

    // 绑定点击事件：左键直接唤起/隐藏窗口，右键呼出菜单
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp {
      if let menu = self.statusMenu {
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
      }
    } else {
      toggleMainWindow()
    }
  }

  @objc private func showMainWindowFromMenu() {
    showMainWindow()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  // MARK: - Window Toggle Logic
  func handleHotKey() {
    DispatchQueue.main.async { [weak self] in
      self?.toggleMainWindow()
    }
  }

  func toggleMainWindow() {
    guard let window = self.mainFlutterWindow else { return }
    if window.isVisible && NSApp.isActive {
      window.orderOut(nil)
    } else {
      showMainWindow()
    }
  }

  func showMainWindow() {
    guard let window = self.mainFlutterWindow else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideMainWindow() {
    mainFlutterWindow?.orderOut(nil)
  }

  // MARK: - Carbon HotKey
  private func installCarbonEventHandlerIfNeeded() {
    guard !hotKeyHandlerInstalled else { return }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { (nextHandler, theEvent, userData) -> OSStatus in
        AppDelegate.shared?.handleHotKey()
        return noErr
      },
      1,
      &eventType,
      nil,
      nil
    )

    hotKeyHandlerInstalled = (handlerStatus == noErr)
  }

  func registerHotKey(modifiers: UInt32, keyCode: UInt32) -> Bool {
    unregisterHotKey()
    installCarbonEventHandlerIfNeeded()

    let hotKeyID = EventHotKeyID(signature: OSType(0x56385442), id: 1) // 'V8TB', 1
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    return status == noErr
  }

  @discardableResult
  func unregisterHotKey() -> Bool {
    if let ref = hotKeyRef {
      let status = UnregisterEventHotKey(ref)
      hotKeyRef = nil
      return status == noErr
    }
    return true
  }

  // MARK: - Flutter Method Channels
  private func initMethodChannelIfNeeded() {
    guard !channelInitialized else { return }

    guard let controller = self.mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      print("无法获取FlutterViewController")
      return
    }

    let messenger = controller.engine.binaryMessenger

    // 1. 应用/文件管理通道 (保持兼容原有功能)
    let channel = FlutterMethodChannel(name: self.channelName, binaryMessenger: messenger)
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
      case "recyclePaths":
        guard let arguments = call.arguments as? [String: Any],
              let paths = arguments["paths"] as? [String] else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "paths array required", details: nil))
          return
        }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.recycle(urls) { (trashedURLs, error) in
          if let error = error {
            result(FlutterError(code: "RECYCLE_ERROR", message: error.localizedDescription, details: nil))
          } else {
            result(["success": true, "count": trashedURLs.count])
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 2. 启动器/全局快捷键与窗口控制通道
    let launcher = FlutterMethodChannel(name: self.launcherChannelName, binaryMessenger: messenger)
    launcher.setMethodCallHandler { [weak self] call, result in
      guard let strongSelf = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate unavailable", details: nil))
        return
      }

      switch call.method {
      case "registerHotKey":
        guard let args = call.arguments as? [String: Any],
              let modifiers = args["modifiers"] as? Int,
              let keyCode = args["keyCode"] as? Int else {
          result(FlutterError(code: "INVALID_ARGS", message: "modifiers and keyCode required", details: nil))
          return
        }
        let success = strongSelf.registerHotKey(modifiers: UInt32(modifiers), keyCode: UInt32(keyCode))
        result(success)

      case "unregisterHotKey":
        let success = strongSelf.unregisterHotKey()
        result(success)

      case "showWindow":
        strongSelf.showMainWindow()
        result(true)

      case "hideWindow":
        strongSelf.hideMainWindow()
        result(true)

      case "toggleWindow":
        strongSelf.toggleMainWindow()
        result(true)

      case "isWindowVisible":
        let isVis = strongSelf.mainFlutterWindow?.isVisible ?? false
        result(isVis)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.launcherChannel = launcher

    channelInitialized = true
    print("MethodChannels已初始化")
  }

  // MARK: - Existing App Shortcuts & Inspection Methods

  private func selectAppPackage(completion: @escaping FlutterResult) {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = false
    openPanel.title = "选择应用程序包"
    openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
    openPanel.showsHiddenFiles = false
    openPanel.canCreateDirectories = false

    openPanel.begin { response in
      if response == .OK, let appURL = openPanel.url {
        if appURL.path.lowercased().hasSuffix(".app") {
          do {
            let contents = try FileManager.default.contentsOfDirectory(
              at: appURL,
              includingPropertiesForKeys: nil,
              options: [.skipsHiddenFiles]
            )
            let filePaths = contents.map { $0.path }
            completion([
              "appPath": appURL.path,
              "filePaths": filePaths,
            ])
          } catch {
            completion(
              FlutterError(
                code: "PARSE_FAILED",
                message: "解析.app包失败：\(error.localizedDescription)",
                details: nil
              ))
          }
        } else {
          completion(
            FlutterError(
              code: "INVALID_APP_BUNDLE",
              message: "选择的不是有效的.app应用程序包",
              details: nil
            ))
        }
      } else {
        completion(
          FlutterError(
            code: "USER_CANCEL",
            message: "用户取消了选择",
            details: nil
          ))
      }
    }
  }

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

  private let appShortcutsHandler = AppShortcutsHandler()

  private func getAppShortcuts(for appName: String) -> [[String: String]] {
    return appShortcutsHandler.getAppShortcuts(for: appName)
  }

  private func getRunningApps() -> [[String: String]] {
    return appShortcutsHandler.getRunningApps()
  }
}
