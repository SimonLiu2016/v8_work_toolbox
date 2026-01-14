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

        // 激活目标应用以确保其菜单可用
        targetApp.activate(options: [.activateAllWindows])

        // 等待短暂时间让应用激活
        usleep(500000)  // 0.5秒

        // 使用Accessibility API获取应用的快捷键
        return getAppShortcutsViaAccessibility(
            targetPID: targetApp.processIdentifier, appName: actualAppName)
    }

    // 通过Accessibility API获取应用快捷键，但使用AppKit的属性名和方法
    private func getAppShortcutsViaAccessibility(targetPID: pid_t, appName: String) -> [[String:
        String]]
    {
        // 创建目标应用的AXUIElement
        let appElement = AXUIElementCreateApplication(targetPID)

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

                // 使用AppKit标准属性名来获取快捷键信息
                var keyEquivalentValue: CFTypeRef?
                let keyEquivalentError = AXUIElementCopyAttributeValue(
                    element, kAXKeyEquivalentAttribute, &keyEquivalentValue)

                // 检查 AXMenuItemCmdChar 属性，这是菜单项的命令字符
                var cmdCharValue: CFTypeRef?
                let cmdCharError = AXUIElementCopyAttributeValue(
                    element, "AXMenuItemCmdChar" as CFString, &cmdCharValue)

                // 检查 AXMenuItemCmdModifiers 属性
                var cmdModifiersValue: CFTypeRef?
                let cmdModifiersError = AXUIElementCopyAttributeValue(
                    element, "AXMenuItemModifiers" as CFString, &cmdModifiersValue)

                if titleError == .success, let title = titleValue as! String? {
                    print("菜单项标题: \(title)")

                    var shortcut = ""
                    var hasShortcut = false

                    // 如果标准方法没有找到，尝试使用菜单命令属性
                    if cmdCharError == .success, let cmdChar = cmdCharValue as! String?,
                        !cmdChar.isEmpty
                    {
                        print("发现命令字符: \(cmdChar)")

                        var modifierStr = ""
                        if cmdModifiersError == .success,
                            let cmdModifiersInt = cmdModifiersValue as! UInt32?
                        {
                            modifierStr = getModifierStringFromCmdModifiers(
                                modifiers: Int(cmdModifiersInt))
                            print("命令字符修饰符: \(modifierStr), 原始值: \(cmdModifiersInt)")
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

    // 获取命令修饰符字符串
    private func getModifierStringFromCmdModifiers(modifiers: Int) -> String {
        var modifierStrings: [String] = []

        // 根据实际观察到的值来映射修饰键
        // 从日志中我们看到原始值为2、28等，需要找到对应的修饰键
        // 根据实际测试，这些值可能对应以下组合：
        // 值2 -> Shift键
        // 值28 -> 多个修饰键组合（28 = 16 + 8 + 4）

        // 尝试使用实际观察到的值映射
        if modifiers & 1 != 0 {  // Command
            modifierStrings.append("⌘")
        }
        if modifiers & 2 != 0 {  // Shift
            modifierStrings.append("⇧")
        }
        if modifiers & 4 != 0 {  // Option/Alt
            modifierStrings.append("⌥")
        }
        if modifiers & 8 != 0 {  // Control
            modifierStrings.append("^")
        }
        if modifiers & 16 != 0 {  // 可能是其他修饰键
            modifierStrings.append("•")  // 使用通用符号，稍后可调整
        }
        if modifiers & 32 != 0 {  // 可能是其他修饰键
            modifierStrings.append("fn")
        }

        return modifierStrings.joined(separator: "")
    }
}
