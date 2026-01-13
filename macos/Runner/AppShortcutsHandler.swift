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

        // 尝试通过AppKit API获取目标应用的菜单
        // 由于安全限制，我们不能直接访问其他应用的NSMenu，所以需要使用Accessibility API
        // 但我们需要确保目标应用被激活，以便访问其菜单
        let originalApp = NSWorkspace.shared.frontmostApplication
        targetApp.activate(options: [.activateAllWindows])

        // 等待短暂时间让应用激活
        usleep(500000)  // 0.5秒

        // 尝试使用Accessibility API获取应用的菜单
        let result = getAppShortcutsViaAccessibility(targetPID: targetPID, appName: actualAppName)

        // 恢复原来的前台应用（可选）
        // if let originalApp = originalApp {
        //   originalApp.activate(options: [.activateAllWindows])
        // }

        return result
    }

    // 通过Accessibility API获取应用快捷键
    private func getAppShortcutsViaAccessibility(targetPID: pid_t, appName: String) -> [[String:
        String]]
    {
        // 由于macOS的安全限制，我们无法直接通过Accessibility API获取非活动应用的特定菜单
        // 因此，我们使用一种不同的方法：尝试获取目标应用的窗口列表，然后从窗口获取菜单

        // 创建目标应用的AXUIElement
        let appElement = AXUIElementCreateApplication(targetPID)

        // 尝试获取应用的窗口列表
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute, &windowsRef)

        if windowsError == .success, let windowsArray = windowsRef as! CFArray? {
            print("获取到 \(CFArrayGetCount(windowsArray)) 个窗口")

            // 遍历所有窗口，尝试从每个窗口获取菜单
            for i in 0..<CFArrayGetCount(windowsArray) {
                let window = unsafeBitCast(
                    CFArrayGetValueAtIndex(windowsArray, i), to: AXUIElement.self)

                // 尝试从窗口获取菜单栏
                var menuBarRef: CFTypeRef?
                let menuBarError = AXUIElementCopyAttributeValue(
                    window, kAXMenuBarAttribute, &menuBarRef)

                if menuBarError == .success, let menuBar = menuBarRef {
                    print("从窗口 \(i) 成功获取菜单栏")

                    // 遍历菜单栏
                    var childrenRef: CFTypeRef?
                    let childrenError = AXUIElementCopyAttributeValue(
                        menuBar as! AXUIElement, kAXChildrenAttribute, &childrenRef)

                    if childrenError == .success, let childrenArray = childrenRef as! CFArray? {
                        print("窗口 \(i) 的菜单栏包含 \(CFArrayGetCount(childrenArray)) 个项目")

                        var shortcuts: [[String: String]] = []

                        for j in 0..<CFArrayGetCount(childrenArray) {
                            print("处理窗口 \(i) 的菜单项 \(j)")
                            let childElement = unsafeBitCast(
                                CFArrayGetValueAtIndex(childrenArray, j), to: AXUIElement.self)
                            let childShortcuts = extractShortcuts(
                                from: childElement, appName: appName)
                            shortcuts.append(contentsOf: childShortcuts)
                        }

                        if !shortcuts.isEmpty {
                            print("从窗口 \(i) 找到 \(shortcuts.count) 个快捷键")
                            return shortcuts
                        }
                    }
                } else {
                    print("从窗口 \(i) 获取菜单栏失败，错误代码: \(menuBarError.rawValue)")
                }
            }
        } else {
            print("无法获取应用窗口列表，错误代码: \(windowsError.rawValue)")
        }

        // 如果通过窗口无法获取菜单，则尝试直接从应用获取（这通常会返回系统菜单）
        print("尝试直接从应用获取菜单栏")
        var menuBarRef: CFTypeRef?
        let menuBarError = AXUIElementCopyAttributeValue(
            appElement, kAXMenuBarAttribute, &menuBarRef)

        if menuBarError == .success, let menuBar = menuBarRef {
            print("从应用直接获取菜单栏成功")

            // 遍历菜单栏
            var childrenRef: CFTypeRef?
            let childrenError = AXUIElementCopyAttributeValue(
                menuBar as! AXUIElement, kAXChildrenAttribute, &childrenRef)

            if childrenError == .success, let childrenArray = childrenRef as! CFArray? {
                print("应用菜单栏包含 \(CFArrayGetCount(childrenArray)) 个项目")

                var shortcuts: [[String: String]] = []

                for i in 0..<CFArrayGetCount(childrenArray) {
                    print("处理应用菜单项 \(i)")
                    let childElement = unsafeBitCast(
                        CFArrayGetValueAtIndex(childrenArray, i), to: AXUIElement.self)
                    let childShortcuts = extractShortcuts(from: childElement, appName: appName)
                    shortcuts.append(contentsOf: childShortcuts)
                }

                print("最终找到 \(shortcuts.count) 个快捷键")
                return shortcuts
            }
        } else {
            print("无法从应用直接获取菜单栏，错误代码: \(menuBarError.rawValue)")
        }

        print("无法获取任何快捷键")
        return []
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

                // 检查多个可能的快捷键属性
                var keyEquivalentValue: CFTypeRef?
                let keyEquivalentError = AXUIElementCopyAttributeValue(
                    element, kAXKeyEquivalentAttribute, &keyEquivalentValue)

                // 检查 AXMenuItemCmdChar 属性，这是菜单项的命令字符
                var cmdCharValue: CFTypeRef?
                let cmdCharError = AXUIElementCopyAttributeValue(
                    element, "AXMenuItemCmdChar" as CFString, &cmdCharValue)

                // 检查 AXMenuItemCmdVirtualKey 属性
                var cmdVirtualKeyValue: CFTypeRef?
                let cmdVirtualKeyError = AXUIElementCopyAttributeValue(
                    element, "AXMenuItemCmdVirtualKey" as CFString, &cmdVirtualKeyValue)

                // 检查 AXMenuItemCmdModifiers 属性
                var cmdModifiersValue: CFTypeRef?
                let cmdModifiersError = AXUIElementCopyAttributeValue(
                    element, "AXMenuItemCmdModifiers" as CFString, &cmdModifiersValue)

                if titleError == .success, let title = titleValue as! String? {
                    print("菜单项标题: \(title)")

                    var shortcut = ""
                    var hasShortcut = false

                    // 首先尝试标准的 keyEquivalent
                    if keyEquivalentError == .success, let key = keyEquivalentValue as! String?,
                        !key.isEmpty
                    {
                        print("发现快捷键字符: \(key)")
                        // 处理修饰符
                        var modifierStr = ""

                        // 检查标准修饰符
                        var modifiersValue: CFTypeRef?
                        let modifiersError = AXUIElementCopyAttributeValue(
                            element, kAXKeyEquivalentModifiersAttribute, &modifiersValue)

                        if modifiersError == .success, let modifiersInt = modifiersValue as! UInt32?
                        {
                            modifierStr = getModifierString(modifiers: Int(modifiersInt))
                            print("快捷键修饰符: \(modifierStr)")
                        }

                        shortcut = "\(modifierStr)\(key)"
                        hasShortcut = true
                    }
                    // 如果标准方法没有找到，尝试使用菜单命令属性
                    else if cmdCharError == .success, let cmdChar = cmdCharValue as! String?,
                        !cmdChar.isEmpty
                    {
                        print("发现命令字符: \(cmdChar)")

                        var modifierStr = ""
                        if cmdModifiersError == .success,
                            let cmdModifiersInt = cmdModifiersValue as! UInt32?
                        {
                            modifierStr = getModifierString(modifiers: Int(cmdModifiersInt))
                            print("命令字符修饰符: \(modifierStr)")
                        }

                        shortcut = "\(modifierStr)\(cmdChar)"
                        hasShortcut = true
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
