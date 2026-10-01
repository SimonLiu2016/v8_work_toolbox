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
          // 尺寸由各窗口的 Dart 入口自己声明（windowManager.setSize），
          // 这里不再替它们决定大小。
          //
          // 曾经这里无条件 setFrame(screen.visibleFrame)，即所有子窗口一律铺满
          // 屏幕可见区（实测查词浮窗被撑到 1680×921 = 整块屏幕）。查词浮窗本该是
          // 420×520 的贴口气泡，笔记本/密码/运维同理都该有自己的尺寸。
          //
          // 为什么不在这一侧按窗口种类查表：这个回调只给 FlutterViewController，
          // 包既不把 arguments 存进 CustomWindow 也不挂到 NSWindow 上——原生侧
          // 根本判断不出自己在给哪种窗口定尺寸。所以尺寸必须由持有着
          // arguments 的 Dart 侧声明。
          window.minSize = NSSize(width: 400, height: 400)

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
