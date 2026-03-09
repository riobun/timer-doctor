import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let overlayController = OverlayWindowController()
  private var overlayChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register overlay channel
    let channel = FlutterMethodChannel(
      name: "timer_doctor/overlay",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "show":
        let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
        self.overlayController.show(text: text)
        result(nil)
      case "hide":
        self.overlayController.hide()
        result(nil)
      case "updateText":
        let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
        self.overlayController.updateText(text)
        result(nil)
      case "updateStyle":
        let args = call.arguments as? [String: Any] ?? [:]
        let fs = (args["fontSize"] as? Double) ?? 14.0
        let tc = (args["textColor"] as? Int) ?? 0xFFFFFFFF
        let bc = (args["bgColor"] as? Int) ?? 0xFF141414
        let bo = (args["bgOpacity"] as? Double) ?? 0.5
        self.overlayController.updateStyle(fontSize: fs, textColor: tc, bgColor: bc, bgOpacity: bo)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    overlayChannel = channel

    super.awakeFromNib()
  }
}
