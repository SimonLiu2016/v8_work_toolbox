import Cocoa
import FlutterMacOS

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

    super.awakeFromNib()
  }
}
