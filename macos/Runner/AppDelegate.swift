import ApplicationServices
import Carbon
import Cocoa
import FlutterMacOS
import Foundation
import UserNotifications

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
  private var contextServicesChannel: FlutterMethodChannel?
  private var lookupHotKeyRef: EventHotKeyRef?
  private var saveNoteHotKeyRef: EventHotKeyRef?
  private var isTrulyQuitting = false

  // 无人值守托盘指示器
  private var defaultTrayImage: NSImage?
  private var unattendedTimer: Timer?
  private var isUnattendedDimmed = false
  private let defaultToolTip = "V8 工作工具箱 (⌥Space)"

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    // 注意：不要调用 super.applicationDidFinishLaunching(aNotification)
    // 因为 FlutterAppDelegate (直接继承自 NSObject) 并未实现该可选代理方法，
    // 调用 super 会在运行时抛出 NSInvalidArgumentException (unrecognized selector)
    // 导致整个生命周期初始化中断，进而使托盘图标和热键均无法加载。
    AppDelegate.shared = self

    setupStatusItem()
    installCarbonEventHandlerIfNeeded()
    // 默认注册 ⌥Space (modifiers: 2048, keyCode: 49)
    _ = registerHotKey(modifiers: UInt32(optionKey), keyCode: 49)
    // 注册上下文热键 ⌥D / ⌥S
    registerContextHotKeys()
    // 注册桌面全局选区悬浮小图标监听 (Bob / PopClip 模式)
    setupGlobalSelectionMonitor()

    // 延迟初始化通道，确保Flutter引擎完全加载
    DispatchQueue.main.async {
      self.initMethodChannelIfNeeded()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭窗口不退出应用，转入后台驻留
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isTrulyQuitting {
      return .terminateNow
    }
    // 程序坞右键"退出"或 ⌘Q → 仅隐藏窗口，不退出进程（托盘驻留）
    hideMainWindow()
    return .terminateCancel
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
    // 点击红叉隐藏窗口，同时隐藏程序坞图标
    hideMainWindow()
    return false
  }

  // MARK: - Status Item (Menu Bar)
  private var statusMenu: NSMenu?

  private func setupStatusItem() {
    NSLog("[V8Tray] Initializing status item...")
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.isVisible = true

    guard let button = statusItem?.button else {
      NSLog("[V8Tray] ERROR: Failed to obtain statusItem button!")
      return
    }

    // 优先加载高品质专属 TrayIcon Template 资产，若缺失则优雅降级为 SF Symbol
    var trayImage = NSImage(named: "TrayIcon")
    if trayImage == nil, #available(macOS 11.0, *) {
      let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
      trayImage = NSImage(
        systemSymbolName: "wrench.and.screwdriver.fill",
        accessibilityDescription: "V8"
      )?.withSymbolConfiguration(config)
    }

    if let image = trayImage {
      image.isTemplate = true
      defaultTrayImage = image
      button.image = image
      button.imagePosition = .imageOnly
      NSLog("[V8Tray] Tray image set successfully (size: \(image.size.width)x\(image.size.height))")
    } else {
      button.title = "V8"
      NSLog("[V8Tray] Warning: Tray image missing, fallback to title 'V8'")
    }

    button.toolTip = defaultToolTip
    button.target = self
    button.action = #selector(statusItemClicked(_:))

    // 创建标准上下文菜单
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

    // 监听托盘按钮上的右键点击事件
    NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp]) { [weak self] event in
      guard let self = self, let statusButton = self.statusItem?.button else { return event }
      if event.window == statusButton.window, let menu = self.statusMenu {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return nil
      }
      return event
    }

    NSLog("[V8Tray] Status item initialized successfully!")
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    // 按住 Control 键或者右键点击时呼出菜单
    if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
      if let menu = self.statusMenu {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
      }
    } else {
      toggleMainWindow()
    }
  }

  @objc private func showMainWindowFromMenu() {
    showMainWindow()
  }

  @objc private func quitApp() {
    unattendedTimer?.invalidate()
    unattendedTimer = nil
    isTrulyQuitting = true
    NSApp.terminate(nil)
  }

  // MARK: - Unattended Tray Animation & Status
  func setUnattendedStatus(active: Bool, tooltip: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let button = self.statusItem?.button else { return }

      // 始终确保托盘图标为主体原生 V8 Logo
      if let defaultImg = self.defaultTrayImage {
        button.image = defaultImg
      }

      if active {
        button.toolTip = tooltip ?? "V8 工作工具箱 - 无人值守运行中"

        if self.unattendedTimer == nil {
          self.isUnattendedDimmed = false
          self.unattendedTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, let btn = self.statusItem?.button else { return }
            self.isUnattendedDimmed.toggle()
            let targetAlpha: CGFloat = self.isUnattendedDimmed ? 0.35 : 1.0
            NSAnimationContext.runAnimationGroup { context in
              context.duration = 0.4
              context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
              btn.animator().alphaValue = targetAlpha
            }
          }
        }
      } else {
        self.unattendedTimer?.invalidate()
        self.unattendedTimer = nil
        self.isUnattendedDimmed = false

        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.2
          button.animator().alphaValue = 1.0
        }

        button.toolTip = tooltip ?? self.defaultToolTip
      }
    }
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
      hideMainWindow()
    } else {
      showMainWindow()
    }
  }

  func showMainWindow() {
    guard let window = self.mainFlutterWindow else { return }
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideMainWindow() {
    mainFlutterWindow?.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: - macOS Services Handlers

  /// macOS Services: 查词
  @objc func handleLookupService(_ pboard: NSPasteboard,
                                  userData: String?,
                                  error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in
      // 保持静默，不弹出主窗口
      self?.contextServicesChannel?.invokeMethod("lookup", arguments: text)
    }
  }

  /// macOS Services: 保存笔记
  @objc func handleSaveNoteService(_ pboard: NSPasteboard,
                                    userData: String?,
                                    error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let text = pboard.string(forType: .string) ?? ""
    let html = pboard.string(forType: NSPasteboard.PasteboardType("public.html")) ?? ""
    let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    DispatchQueue.main.async { [weak self] in
      // 保持静默，不弹出主窗口
      self?.contextServicesChannel?.invokeMethod("saveNote", arguments: [
        "text": text,
        "html": html,
        "sourceApp": sourceApp,
      ])
    }
  }

  // MARK: - Lookup & SaveNote HotKeys (⌥D, ⌥S)

  func registerContextHotKeys() {
    // ⌥D (keyCode: 2, mod: optionKey)
    registerContextHotKey(
      keyCode: 2,
      modifiers: UInt32(optionKey),
      id: 2,
      refOut: &lookupHotKeyRef,
      action: #selector(handleLookupHotKey)
    )
    // ⌥S (keyCode: 1, mod: optionKey)
    registerContextHotKey(
      keyCode: 1,
      modifiers: UInt32(optionKey),
      id: 3,
      refOut: &saveNoteHotKeyRef,
      action: #selector(handleSaveNoteHotKey)
    )
  }

  private func registerContextHotKey(
    keyCode: UInt32, modifiers: UInt32, id: UInt32,
    refOut: inout EventHotKeyRef?, action: Selector
  ) {
    var keyID = EventHotKeyID(signature: OSType(0x56384354), id: id) // 'V8CT'
    RegisterEventHotKey(keyCode, modifiers, keyID, GetApplicationEventTarget(), 0, &refOut)
  }

  /// 尝试使用 macOS 辅助功能 API 直接获取当前选中文字（无侵入、不占用剪贴板、不产生按键泄漏）
  func getSystemSelectedText() -> String? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedAppValue: AnyObject?
    let appErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)
    guard appErr == .success, let focusedApp = focusedAppValue else { return nil }

    var focusedElementValue: AnyObject?
    let elemErr = AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
    guard elemErr == .success, let focusedElement = focusedElementValue else { return nil }

    var selectedTextValue: AnyObject?
    let textErr = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
    guard textErr == .success, let text = selectedTextValue as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @objc func handleLookupHotKey() {
    // 1. 优先尝试 Accessibility API 静默获取选中文本
    if let selectedText = getSystemSelectedText(), !selectedText.isEmpty {
      DispatchQueue.main.async { [weak self] in
        self?.contextServicesChannel?.invokeMethod("lookup", arguments: selectedText)
      }
      return
    }

    // 2. 降级：释放 Option 修饰键后模拟 ⌘C，防止键码泄漏（如 \D）
    simulateCopyAndInvoke(method: "lookup")
  }

  @objc func handleSaveNoteHotKey() {
    let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

    // 1. 优先尝试 Accessibility API 静默获取选中文本
    if let selectedText = getSystemSelectedText(), !selectedText.isEmpty {
      DispatchQueue.main.async { [weak self] in
        self?.contextServicesChannel?.invokeMethod("saveNote", arguments: [
          "text": selectedText,
          "html": "",
          "sourceApp": sourceApp,
        ])
      }
      return
    }

    // 2. 降级：释放 Option 修饰键后模拟 ⌘C，防止键码泄漏（如 ß）
    simulateCopyAndInvoke(method: "saveNote", extraArgs: ["sourceApp": sourceApp])
  }

  /// 释放 Option 修饰键 → 保存旧剪贴板 → 模拟 ⌘C → 读取 → 恢复 → 静默调用 Flutter
  private func simulateCopyAndInvoke(method: String, extraArgs: [String: String] = [:]) {
    let pb = NSPasteboard.general
    let oldContents = pb.string(forType: .string)
    let oldChangeCount = pb.changeCount

    // 独立事件源，不继承物理键盘的硬件修饰键状态
    let src = CGEventSource(stateID: .privateState)

    // 显式释放 Option 键（0x3A = 左 Option, 0x3D = 右 Option）
    let optKeyUp1 = CGEvent(keyboardEventSource: src, virtualKey: 0x3A, keyDown: false)
    optKeyUp1?.flags = []
    optKeyUp1?.post(tap: .cghidEventTap)
    let optKeyUp2 = CGEvent(keyboardEventSource: src, virtualKey: 0x3D, keyDown: false)
    optKeyUp2?.flags = []
    optKeyUp2?.post(tap: .cghidEventTap)

    // 短暂延迟确保系统消费 Option-Up 事件，然后模拟纯净的 ⌘C
    DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.02) {
      let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true) // 'c'
      keyDown?.flags = .maskCommand
      let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
      keyUp?.flags = .maskCommand
      keyDown?.post(tap: .cghidEventTap)
      keyUp?.post(tap: .cghidEventTap)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        defer {
          if pb.changeCount != oldChangeCount {
            pb.clearContents()
            if let old = oldContents { pb.setString(old, forType: .string) }
          }
        }

        let text = pb.string(forType: .string) ?? ""
        let html = pb.string(forType: NSPasteboard.PasteboardType("public.html")) ?? ""

        // 注意：绝不调用 showMainWindow()，完全静默触发
        var args: [String: String] = ["text": text, "html": html]
        args.merge(extraArgs) { _, new in new }
        self?.contextServicesChannel?.invokeMethod(method, arguments: method == "lookup" ? text : args)
      }
    }
  }

  // MARK: - Popover Frame & Window Configuration

  /// 计算紧随鼠标光标的悬浮弹窗位置，具备边界自动贴靠翻转
  func calculatePopoverFrame(width: CGFloat = 420, height: CGFloat = 520) -> NSRect {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    let visible = screen.visibleFrame

    var x = mouse.x + 8
    var y = mouse.y - height - 12

    // 超出右边界，翻转到光标左侧
    if x + width > visible.maxX {
      x = mouse.x - width - 8
    }
    // 超出下边界，翻转到光标上方
    if y < visible.minY {
      y = mouse.y + 12
    }

    // 严防溢出可视区域
    x = max(visible.minX + 8, min(x, visible.maxX - width - 8))
    y = max(visible.minY + 8, min(y, visible.maxY - height - 8))

    return NSRect(x: x, y: y, width: width, height: height)
  }

  // MARK: - Selection Floating Bubble Panel (Bob / PopClip Style)

  private var selectionBubble: SelectionBubblePanel?
  private var bubbleDismissTimer: Timer?
  private var globalMouseMonitor: Any?

  func setupGlobalSelectionMonitor() {
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
      self?.handleGlobalMouseUp()
    }
  }

  private func handleGlobalMouseUp() {
    // 延迟 120ms 等待宿主应用（PDF/Word/编辑器等）完成选区高亮绘制
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
      guard let self = self else { return }
      // 避免如果当前前台是本应用的主窗口时反复弹出
      if NSApp.isActive && self.mainFlutterWindow?.isKeyWindow == true {
        return
      }

      guard let text = self.getSystemSelectedText(), text.count >= 2, text.count <= 60 else {
        self.hideSelectionBubble()
        return
      }

      self.showSelectionBubble(for: text)
    }
  }

  private func showSelectionBubble(for text: String) {
    if selectionBubble == nil {
      selectionBubble = SelectionBubblePanel()
    }
    selectionBubble?.onClick = { [weak self] in
      DispatchQueue.main.async {
        self?.contextServicesChannel?.invokeMethod("lookup", arguments: text)
      }
    }

    let mouse = NSEvent.mouseLocation
    selectionBubble?.setFrameOrigin(NSPoint(x: mouse.x + 8, y: mouse.y + 8))
    selectionBubble?.orderFront(nil)

    bubbleDismissTimer?.invalidate()
    bubbleDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
      self?.hideSelectionBubble()
    }
  }

  func hideSelectionBubble() {
    selectionBubble?.orderOut(nil)
    bubbleDismissTimer?.invalidate()
    bubbleDismissTimer = nil
  }

  /// 配置查词弹窗：无红绿灯、无边框、半透明卡片样式、悬浮于光标旁
  func configureLookupWindow() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.hideSelectionBubble()
      for window in NSApp.windows where window != self.mainFlutterWindow && !(window is SelectionBubblePanel) {
        let frame = self.calculatePopoverFrame(width: 420, height: 520)
        window.setFrame(frame, display: true, animate: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.makeKeyAndOrderFront(nil)
        break
      }
    }
  }

  // MARK: - Native Notification for Note Capture

  func showNoteNotification(title: String, notebook: String) {
    let notification = NSUserNotification()
    notification.title = "已保存笔记 📝"
    notification.informativeText = "「\(title)」已存入「\(notebook)」"
    notification.soundName = NSUserNotificationDefaultSoundName
    NSUserNotificationCenter.default.deliver(notification)
  }

  // MARK: - Incoming URL Schemes (v8toolbox://)

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      handleIncomingUrl(url)
    }
  }

  private func handleIncomingUrl(_ url: URL) {
    guard url.scheme == "v8toolbox" else { return }
    let host = url.host ?? ""
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryItems = components?.queryItems ?? []

    func getParam(_ name: String) -> String {
      return queryItems.first(where: { $0.name == name })?.value ?? ""
    }

    switch host {
    case "lookup":
      let text = getParam("text")
      let mode = getParam("mode")
      if !text.isEmpty {
        DispatchQueue.main.async { [weak self] in
          // mode 一路带到 Flutter：用户在浏览器点了「问 AI 深度解析」，
          // 这里丢掉它，浮窗就会按普通查词走一遍词典——那正是用户报的 Bug。
          // 空 mode = 词典优先（既有调用方都不带 mode）。
          self?.contextServicesChannel?.invokeMethod("lookup", arguments: [
            "text": text,
            "mode": mode
          ])
        }
      }
    case "vocab":
      // 只加生词，不开窗口、不查词典。独立 host 而不是 lookup 的一个 mode：
      // 这个动作压根没有 UI，走查词窗口的流程再"不打开它"是自相矛盾。
      let text = getParam("text")
      if !text.isEmpty {
        DispatchQueue.main.async { [weak self] in
          self?.contextServicesChannel?.invokeMethod("addToVocab", arguments: text)
        }
      }
    case "savenote":
      let text = getParam("text")
      let pageUrl = getParam("url")
      let title = getParam("title")
      DispatchQueue.main.async { [weak self] in
        self?.contextServicesChannel?.invokeMethod("saveNote", arguments: [
          "text": text,
          "html": "",
          "sourceApp": "browser",
          "url": pageUrl,
          "title": title,
        ])
      }
    default:
      break
    }
  }

  // MARK: - Browser URL via AppleScript

  func getFrontBrowserURL() -> String? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
    let bundleId = frontApp.bundleIdentifier ?? ""

    let script: String
    switch bundleId {
    case "com.google.Chrome", "com.google.Chrome.canary":
      script = "tell application \"Google Chrome\" to get URL of active tab of front window"
    case "com.apple.Safari":
      script = "tell application \"Safari\" to get URL of current tab of front window"
    case "org.mozilla.firefox":
      script = "tell application \"Firefox\" to get URL of active tab of front window"
    case "com.microsoft.edgemac":
      script = "tell application \"Microsoft Edge\" to get URL of active tab of front window"
    default:
      return nil
    }

    var error: NSDictionary?
    let appleScript = NSAppleScript(source: script)
    let result = appleScript?.executeAndReturnError(&error)
    if error != nil { return nil }
    return result?.stringValue
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
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          theEvent,
          UInt32(kEventParamDirectObject),
          UInt32(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        switch hotKeyID.id {
        case 1: AppDelegate.shared?.handleHotKey()          // ⌥Space - 原有行为
        case 2: AppDelegate.shared?.handleLookupHotKey()    // ⌥D
        case 3: AppDelegate.shared?.handleSaveNoteHotKey()  // ⌥S
        default: break
        }
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

      case "setUnattendedStatus":
        let active = (call.arguments as? [String: Any])?["active"] as? Bool ?? false
        let tooltip = (call.arguments as? [String: Any])?["tooltip"] as? String
        strongSelf.setUnattendedStatus(active: active, tooltip: tooltip)
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.launcherChannel = launcher

    // 3. 上下文服务通道（查词 + 保存笔记）
    let contextServices = FlutterMethodChannel(
      name: "v8_work_toolbox/context_services",
      binaryMessenger: messenger
    )
    contextServices.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "getBrowserUrl":
        let url = self.getFrontBrowserURL()
        result(url)
      case "styleLookupWindow":
        self.configureLookupWindow()
        result(true)
      case "getMouseLocation":
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        result([
          "x": mouse.x,
          "y": mouse.y,
          "screenHeight": screen.frame.height,
        ])
      case "showNotification":
        let args = call.arguments as? [String: Any] ?? [:]
        let title = args["title"] as? String ?? ""
        let notebook = args["notebook"] as? String ?? "默认笔记本"
        self.showNoteNotification(title: title, notebook: notebook)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.contextServicesChannel = contextServices

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

// MARK: - SelectionBubblePanel (Bob / PopClip Style Floating Action Button)

class SelectionBubblePanel: NSPanel {
  var onClick: (() -> Void)?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 28, height: 28),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    self.isFloatingPanel = true
    self.level = .floating
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = true
    self.hidesOnDeactivate = false

    let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.cornerRadius = 14
    button.layer?.masksToBounds = true
    button.layer?.backgroundColor = NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1.0).cgColor
    button.target = self
    button.action = #selector(handleButtonClick)

    button.attributedTitle = NSAttributedString(
      string: "V8",
      attributes: [
        .foregroundColor: NSColor.white,
        .font: NSFont.boldSystemFont(ofSize: 11),
      ]
    )

    self.contentView = button
  }

  @objc private func handleButtonClick() {
    self.orderOut(nil)
    onClick?()
  }

  override var canBecomeKey: Bool {
    return false
  }

  override var canBecomeMain: Bool {
    return false
  }
}

