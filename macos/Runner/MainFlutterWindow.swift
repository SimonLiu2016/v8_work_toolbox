import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 设置最小尺寸与默认尺寸
    self.minSize = NSSize(width: 900, height: 600)
    var defaultFrame = self.frame
    defaultFrame.size = NSSize(width: 1100, height: 700)
    self.setFrame(defaultFrame, display: true)
    self.center()

    // 沉浸式透明标题栏与全尺寸内容视图（消除原生灰色标题条）
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 为 desktop_multi_window 创建的每个子窗口引擎注册全部 Flutter 插件并配置沉浸式窗口
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)

      DispatchQueue.main.async {
        if let window = controller.view.window {
          window.minSize = NSSize(width: 960, height: 640)
          if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
          } else {
            var frame = window.frame
            frame.size = NSSize(width: 1200, height: 750)
            window.setFrame(frame, display: true)
            window.center()
          }

          // 沉浸式透明标题栏与全尺寸内容视图（与主窗口完全一致）
          window.titlebarAppearsTransparent = true
          window.titleVisibility = .hidden
          window.styleMask.insert(.fullSizeContentView)
          window.isMovableByWindowBackground = true
        }
      }
    }

    super.awakeFromNib()
  }
}
