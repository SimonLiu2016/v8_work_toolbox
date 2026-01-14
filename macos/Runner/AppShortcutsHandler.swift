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
    private let kAXMenuItemCmdCharAttribute = "AXMenuItemCmdChar" as CFString
    private let kAXMenuItemCmdModifiersAttribute = "AXMenuItemCmdModifiers" as CFString

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
                let _ = AXUIElementCopyAttributeValue(
                    element, kAXKeyEquivalentAttribute, &keyEquivalentValue)

                // 检查 AXMenuItemCmdChar 属性，这是菜单项的命令字符
                var cmdCharValue: CFTypeRef?
                let cmdCharError = AXUIElementCopyAttributeValue(
                    element, kAXMenuItemCmdCharAttribute as CFString, &cmdCharValue)

                // 检查 AXMenuItemCmdModifiers 属性
                var cmdModifiersValue: CFTypeRef?
                let cmdModifiersError = AXUIElementCopyAttributeValue(
                    element, kAXMenuItemCmdModifiersAttribute as CFString, &cmdModifiersValue)

                if titleError == .success, let title = titleValue as! String? {
                    print("菜单项标题: \(title)")

                    var shortcut = ""
                    var hasShortcut = false

                    // 如果标准方法没有找到，尝试使用菜单命令属性
                    if cmdCharError == .success, let cmdChar = cmdCharValue as! String?,
                        !cmdChar.isEmpty
                    {
                        print("发现命令字符: \(cmdChar)")

                        // 处理特殊字符键的显示问题
                        var displayChar = cmdChar

                        // 检查并转换特殊字符
                        if let specialChar = convertSpecialCharacter(cmdChar) {
                            displayChar = specialChar
                        }

                        var modifierStr = ""
                        if cmdModifiersError == .success,
                            let cmdModifiersInt = cmdModifiersValue as! UInt32?
                        {
                            modifierStr = getModifierStringFromCmdModifiers(
                                modifiers: Int(cmdModifiersInt))
                            print("命令字符修饰符: \(modifierStr), 原始值: \(cmdModifiersInt)")
                        }

                        shortcut = "\(modifierStr)\(displayChar)"
                        hasShortcut = true
                    }

                    if hasShortcut {
                        // 过滤系统菜单项，只保留应用特有的快捷键
                        if !isSystemMenuItem(title: title) {
                            let shortcutDict: [String: String] = [
                                "description": title,
                                "shortcut": shortcut,
                                "category": appName,
                            ]

                            shortcuts.append(shortcutDict)
                            print("添加快捷键: \(title) -> \(shortcut)")
                        } else {
                            print("跳过系统菜单项: \(title)")
                        }
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

        // kAXMenuItemCmdModifiersAttribute 使用特殊的掩码
        // 基础4位掩码（低4位）：
        // bit 0 (1): Shift 键存在 -> ⇧ (正向逻辑)
        // bit 1 (2): Option 键存在 -> ⌥ (正向逻辑)
        // bit 2 (4): Control 键存在 -> ^ (正向逻辑)
        // bit 3 (8): Command 键不存在 -> ⌘ (反向逻辑! 如果该位为0则有Command键)
        //
        // 高位可能包含其他修饰键：
        // bit 4 (16): 可能是 Fn 键
        // 值 24 专门表示 Fn 键

        // 检查 Fn 键 (bit 4 - 16)
        if modifiers & 16 != 0 {
            modifierStrings.append("fn")  // Function key
        }

        // 检查 Control 键 (bit 2)
        if modifiers & 4 != 0 {
            modifierStrings.append("^")  // Control
        }

        // 检查 Option 键 (bit 1)
        if modifiers & 2 != 0 {
            modifierStrings.append("⌥")  // Option/Alt
        }

        // 检查 Shift 键 (bit 0)
        if modifiers & 1 != 0 {
            modifierStrings.append("⇧")  // Shift
        }

        // 检查 Command 键 (bit 3) - 逻辑相反
        // 如果 bit 3 为 0 (即 modifiers & 8 == 0)，则表示有 Command 键
        if modifiers & 8 == 0 {
            modifierStrings.append("⌘")  // Command (反向逻辑)
        }

        return modifierStrings.joined(separator: "")
    }

    // 转换特殊字符键为可读符号
    private func convertSpecialCharacter(_ char: String) -> String? {
        // 检查字符的Unicode值来确定是否为特殊键
        if let firstChar = char.unicodeScalars.first {
            let scalarValue = firstChar.value

            // 添加调试输出，特别是针对您提到的菜单项
            print(
                "调试: 检测到字符 '\(char)' (scalarValue: \(scalarValue)), Unicode: U+\(String(format: "%04X", scalarValue))"
            )

            switch scalarValue {
            case 0x19: return "↑"  // 上箭头
            case 0x1A: return "↓"  // 下箭头
            case 0x1C: return "←"  // 左箭头
            case 0x1D: return "→"  // 右箭头
            case 63232: return "▲"  // 向上实心三角形 (U+F700)
            case 63233: return "▼"  // 向下实心三角形 (U+F701)
            case 63234: return "◀"  // 向左实心三角形 (U+F702)
            case 63235: return "▶"  // 向右实心三角形 (U+F703)
            case 0x7F: return "⌫"  // 删除键
            case 0x08: return "⌦"  // 向前删除键
            case 0x0D: return "⏎"  // 回车键
            case 0x0A: return "↵"  // 换行符
            case 0x1B: return "⎋"  // ESC键
            case 0x20: return "␣"  // 空格键
            case 0x09: return "⇥"  // Tab键
            default:
                // 检查是否为F1-F12键
                // 在某些情况下，功能键可能以特定方式编码
                if char.count == 1 {  // 单字符
                    switch char {
                    case "\u{F704}": return "F1"
                    case "\u{F705}": return "F2"
                    case "\u{F706}": return "F3"
                    case "\u{F707}": return "F4"
                    case "\u{F708}": return "F5"
                    case "\u{F709}": return "F6"
                    case "\u{F70A}": return "F7"
                    case "\u{F70B}": return "F8"
                    case "\u{F70C}": return "F9"
                    case "\u{F70D}": return "F10"
                    case "\u{F70E}": return "F11"
                    case "\u{F70F}": return "F12"
                    default:
                        return nil
                    }
                }
                return nil
            }
        }
        return nil
    }

    // 判断是否为系统菜单项
    private func isSystemMenuItem(title: String) -> Bool {
        let systemMenuItems = [
            "关于",
            "关于本机",
            "系统信息",
            "系统设置",
            "系统偏好设置",
            "App Store",
            "强制退出",
            "强制退出…",
            "睡眠",
            "重新启动",
            "重新启动…",
            "关机",
            "关机…",
            "锁定屏幕",
            "注销",
            "退出登录",
            "退出",
            "偏好设置",
            "服务",
        ]

        for item in systemMenuItems {
            if title.hasPrefix(item) || title.localizedCaseInsensitiveContains(item) {
                return true
            }
        }

        return false
    }
}
