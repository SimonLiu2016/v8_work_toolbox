//
//  AppShortcutsHandler.swift
//  Runner
//
import Carbon
import Cocoa
import FlutterMacOS

// MARK: - App Shortcuts Handler
class AppShortcutsHandler {

    private let kAXRoleAttribute = "AXRole" as CFString
    private let kAXTitleAttribute = "AXTitle" as CFString
    private let kAXKeyEquivalentAttribute = "AXKeyEquivalent" as CFString
    private let kAXKeyEquivalentModifiersAttribute = "AXKeyEquivalentModifiers" as CFString
    private let kAXChildrenAttribute = "AXChildren" as CFString
    private let kAXMenuBarAttribute = "AXMenuBar" as CFString
    private let kAXWindowsAttribute = "AXWindows" as CFString
    private let kAXMenuBarItem = "AXMenuBarItem" as CFString
    private let kAXMenuRole = "AXMenu" as CFString
    private let kAXMenuItemRole = "AXMenuItem" as CFString

    // 获取当前运行的应用列表
    func getRunningApps() -> [[String: String]] {
        var apps: [[String: String]] = []

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            // 只显示有bundleId且可见的应用
            if app.activationPolicy == .regular {
                let appInfo: [String: String] = [
                    "name": app.localizedName ?? bundleId,
                    "bundleId": bundleId,
                    "path": app.bundleURL?.path ?? "",
                ]
                apps.append(appInfo)
            }
        }

        return apps
    }

    // 查找指定名称的应用
    private func findApp(by name: String) -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications

        // 首先尝试精确匹配
        for app in runningApps {
            if app.activationPolicy == .regular,
                let appName = app.localizedName,
                appName == name
            {
                print("找到应用 \(appName): \(name), Bundle ID: \(app.bundleIdentifier ?? "")")
                return app
            }
        }

        // 如果精确匹配失败，尝试模糊匹配
        for app in runningApps {
            if app.activationPolicy == .regular,
                let appName = app.localizedName,
                appName.localizedCaseInsensitiveContains(name)
            {
                print(
                    "找到系统应用 \(app.bundleIdentifier ?? "Unknown"): \(appName), Bundle ID: \(app.bundleIdentifier ?? "")"
                )
                return app
            }
        }

        print("未找到应用: \(name)")
        return nil
    }

    // 获取指定应用的快捷键
    func getAppShortcuts(for appName: String) -> [[String: String]] {
        print("开始获取应用 '\(appName)' 的快捷键")

        // 首先查找目标应用
        guard let targetApp = findApp(by: appName) else {
            print("未找到应用: \(appName)")
            return []
        }

        let actualAppName = targetApp.localizedName ?? ""
        print("找到应用，显示名称: \(actualAppName), Bundle ID: \(targetApp.bundleIdentifier ?? "")")

        // 获取应用的进程ID
        let targetPID = targetApp.processIdentifier
        if targetPID == -1 {
            print("无法获取应用进程ID: \(appName)")
            return []
        }

        print("获取到进程ID: \(targetPID)")

        // 尝试使用NSApp方法获取菜单栏，对于当前应用
        if targetPID == getpid() {
            // 如果是我们自己，直接获取菜单
            return getMainMenuShortcuts()
        } else {
            // 对于其他应用，使用Accessibility API
            return getAppShortcutsViaAccessibility(targetPID: targetPID, appName: actualAppName)
        }
    }

    // 通过Accessibility API获取应用快捷键
    private func getAppShortcutsViaAccessibility(targetPID: pid_t, appName: String) -> [[String:
        String]]
    {
        // 使用Accessibility API获取UI元素
        let appElement = AXUIElementCreateApplication(targetPID)

        // 尝试激活应用以确保其菜单栏可见
        let targetApp = NSRunningApplication(processIdentifier: targetPID)
        targetApp?.activate(options: [.activateAllWindows])

        // 等待短暂时间让应用激活
        usleep(500000)  // 0.5秒

        // 尝试获取菜单栏 - 先尝试从NSApp方式（如果应用是当前应用）
        if targetPID == getpid() {
            return getMainMenuShortcuts()
        }

        // 使用当前应用名称作为备用名称
        let currentAppName = ProcessInfo.processInfo.processName

        // 对于其他应用，使用Accessibility API获取菜单
        // 首先尝试获取应用的窗口，然后从窗口获取菜单栏
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute, &windowsRef)

        var menuBarRef: CFTypeRef?
        var menuBarError: AXError = .invalidUIElement

        if windowsError == .success, let windowsArray = windowsRef as! CFArray? {
            // 尝试从第一个窗口获取菜单栏
            if CFArrayGetCount(windowsArray) > 0 {
                let window = unsafeBitCast(
                    CFArrayGetValueAtIndex(windowsArray, 0), to: AXUIElement.self)
                menuBarError = AXUIElementCopyAttributeValue(
                    window, kAXMenuBarAttribute, &menuBarRef)
                print("从窗口获取菜单栏")
            }
        }

        // 如果从窗口获取失败，尝试直接从应用获取菜单栏
        if menuBarError != .success || menuBarRef == nil {
            print("从窗口获取菜单栏失败，尝试从应用直接获取")
            menuBarError = AXUIElementCopyAttributeValue(
                appElement, kAXMenuBarAttribute, &menuBarRef)
        }

        if menuBarError != .success || menuBarRef == nil {
            print("无法获取菜单栏，错误代码: \(menuBarError.rawValue)")
            return []
        }

        print("成功获取菜单栏引用")

        // 遍历菜单栏
        var childrenRef: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(
            menuBarRef as! AXUIElement, kAXChildrenAttribute, &childrenRef)

        if childrenError != .success || childrenRef == nil {
            print("无法获取菜单栏子元素")
            return []
        }

        var shortcuts: [[String: String]] = []

        if let childrenArray = childrenRef as! CFArray? {
            print("菜单栏包含 \(CFArrayGetCount(childrenArray)) 个项目")

            for i in 0..<CFArrayGetCount(childrenArray) {
                print("处理菜单项 \(i)")
                let childElement = unsafeBitCast(
                    CFArrayGetValueAtIndex(childrenArray, i), to: AXUIElement.self)
                let childShortcuts = extractShortcuts(from: childElement, appName: appName)
                shortcuts.append(contentsOf: childShortcuts)
            }
        }

        print("最终找到 \(shortcuts.count) 个快捷键")
        return shortcuts
    }

    // 从主菜单获取快捷键（适用于当前应用）
    private func getMainMenuShortcuts() -> [[String: String]] {
        var shortcuts: [[String: String]] = []

        // 这里使用AppKit API来获取菜单项
        let mainMenu = NSApp.mainMenu
        for menuItem in mainMenu?.items ?? [] {
            if let submenu = menuItem.submenu {
                // 递归遍历子菜单
                shortcuts.append(
                    contentsOf: traverseMenu(
                        submenu,
                        appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                            ?? "Current App"))
            } else {
                // 提取单个菜单项的快捷键
                if let shortcut = extractShortcutFromNSMenuItem(
                    menuItem,
                    appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? "Current App")
                {
                    shortcuts.append(shortcut)
                }
            }
        }

        return shortcuts
    }

    // 遍历NSMenu
    private func traverseMenu(_ menu: NSMenu, appName: String) -> [[String: String]] {
        var shortcuts: [[String: String]] = []

        for menuItem in menu.items {
            if menuItem.hasSubmenu, let submenu = menuItem.submenu {
                // 递归遍历子菜单
                shortcuts.append(contentsOf: traverseMenu(submenu, appName: appName))
            } else {
                // 提取菜单项的快捷键
                if let shortcut = extractShortcutFromNSMenuItem(menuItem, appName: appName) {
                    shortcuts.append(shortcut)
                }
            }
        }

        return shortcuts
    }

    // 从NSMenuItem提取快捷键
    private func extractShortcutFromNSMenuItem(_ menuItem: NSMenuItem, appName: String) -> [String:
        String]?
    {
        let title = menuItem.title
        let key = menuItem.keyEquivalent
        let modifiers = menuItem.keyEquivalentModifierMask

        if !key.isEmpty {
            // 将修饰符转换为字符串表示
            let modifierStr = getModifierStringFromNSEventModifierFlags(modifiers)
            let shortcutStr = "\(modifierStr)\(key)"

            let shortcutDict: [String: String] = [
                "description": title,
                "shortcut": shortcutStr,
                "category": appName,
            ]

            print("添加快捷键: \(title) -> \(shortcutStr)")
            return shortcutDict
        }

        return nil
    }

    // 从NSEventModifierFlags获取修饰符字符串
    private func getModifierStringFromNSEventModifierFlags(_ modifiers: NSEvent.ModifierFlags)
        -> String
    {
        var modifierStrings: [String] = []

        if modifiers.contains(.command) {
            modifierStrings.append("⌘")
        }
        if modifiers.contains(.option) {
            modifierStrings.append("⌥")
        }
        if modifiers.contains(.shift) {
            modifierStrings.append("⇧")
        }
        if modifiers.contains(.control) {
            modifierStrings.append("^")
        }

        return modifierStrings.joined(separator: "")
    }

    // 递归提取快捷键
    private func extractShortcuts(from element: AXUIElement, appName: String) -> [[String: String]]
    {
        var shortcuts: [[String: String]] = []

        // 检查是否是菜单项
        var roleValue: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &roleValue)

        if roleError == .success, let role = roleValue as! String? {
            print("遍历元素角色: \(role)")

            if role == (kAXMenuItemRole as String) {
                // 获取菜单项的标题和快捷键
                var titleValue: CFTypeRef?
                let titleError = AXUIElementCopyAttributeValue(
                    element, kAXTitleAttribute, &titleValue)

                var keyEquivalentValue: CFTypeRef?
                let keyEquivalentError = AXUIElementCopyAttributeValue(
                    element, kAXKeyEquivalentAttribute, &keyEquivalentValue)

                var modifiersValue: CFTypeRef?
                let modifiersError = AXUIElementCopyAttributeValue(
                    element, kAXKeyEquivalentModifiersAttribute, &modifiersValue)

                if titleError == .success, let title = titleValue as! String? {
                    print("菜单项标题: \(title)")

                    var shortcut = ""
                    var hasShortcut = false

                    if keyEquivalentError == .success, let key = keyEquivalentValue as! String?,
                        !key.isEmpty
                    {
                        print("发现快捷键字符: \(key)")
                        // 处理修饰符
                        var modifierStr = ""
                        if modifiersError == .success, let modifiersInt = modifiersValue as! UInt32?
                        {
                            modifierStr = getModifierString(modifiers: Int(modifiersInt))
                            print("快捷键修饰符: \(modifierStr)")
                        }

                        shortcut = "\(modifierStr)\(key)"
                        hasShortcut = true
                    } else {
                        print("无快捷键字符")
                    }

                    if hasShortcut {
                        let shortcutDict: [String: String] = [
                            "description": title,
                            "shortcut": shortcut,
                            "category": appName,
                        ]

                        shortcuts.append(shortcutDict)
                        print("添加快捷键: \(title) -> \(shortcut)")
                    } else {
                        print("跳过无快捷键的菜单项: \(title)")
                    }
                } else {
                    print("无法获取菜单项标题")
                }
            } else if role == (kAXMenuRole as String) || role == (kAXMenuBarItem as String) {
                print("进入子菜单或菜单栏项")
                // 如果是子菜单或菜单栏项，递归处理其子元素
                var submenuItems: CFTypeRef?
                let submenuError = AXUIElementCopyAttributeValue(
                    element, kAXChildrenAttribute, &submenuItems)

                if submenuError == .success, let array = submenuItems as! CFArray? {
                    print("子菜单包含 \(CFArrayGetCount(array)) 个项目")
                    let items = (0..<CFArrayGetCount(array)).compactMap { idx in
                        let element = CFArrayGetValueAtIndex(array, idx)
                        return unsafeBitCast(element, to: AXUIElement.self)
                    }
                    for item in items {
                        let itemShortcuts = extractShortcuts(from: item, appName: appName)
                        shortcuts.append(contentsOf: itemShortcuts)
                    }
                } else {
                    print("无法获取子菜单项目")
                }
            } else {
                print("跳过非菜单项元素，角色: \(role)")
            }
        } else {
            print("无法获取元素角色")
        }

        return shortcuts
    }

    // 获取修饰符字符串
    private func getModifierString(modifiers: Int) -> String {
        var modifierStrings: [String] = []

        if modifiers & Int(controlKey) != 0 {
            modifierStrings.append("^")  // Control
        }
        if modifiers & Int(optionKey) != 0 {
            modifierStrings.append("⌥")  // Option/Alt
        }
        if modifiers & Int(shiftKey) != 0 {
            modifierStrings.append("⇧")  // Shift
        }
        if modifiers & Int(cmdKey) != 0 {
            modifierStrings.append("⌘")  // Command
        }

        return modifierStrings.joined(separator: "")
    }
}
