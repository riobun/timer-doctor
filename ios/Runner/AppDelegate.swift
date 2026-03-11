import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PipOverlayPlugin")
    let channel = FlutterMethodChannel(
      name: "timer_doctor/overlay",
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      guard #available(iOS 15.0, *) else {
        result(FlutterMethodNotImplemented)
        return
      }

      let pip = PipService.shared
      let args = call.arguments as? [String: Any] ?? [:]

      switch call.method {
      case "show":
        pip.show(text: args["text"] as? String ?? "")
        result(nil)
      case "hide":
        pip.hide()
        result(nil)
      case "updateText":
        pip.updateText(args["text"] as? String ?? "")
        result(nil)
      case "updateStyle":
        pip.updateStyle(
          fontSize: args["fontSize"] as? Double ?? 14,
          textColorArgb: args["textColor"] as? Int ?? 0xFFFFFFFF,
          bgColorArgb: args["bgColor"] as? Int ?? 0xFF141414,
          bgOpacity: args["bgOpacity"] as? Double ?? 0.85
        )
        result(nil)
      case "checkPermission":
        result(true)  // PiP needs no special permission
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
