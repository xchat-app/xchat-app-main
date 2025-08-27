import Cocoa
import FlutterMacOS

public class OXCCommonPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ox_common", binaryMessenger: registrar.messenger)
    let instance = OXCCommonPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasImages":
        result(ClipboardHelper.hasImages())
    case "getImages":
        result(ClipboardHelper.getImages())
    case "copyImageToClipboard":
        guard let imagePath = (call.arguments as? [String: String])?["imagePath"] else {
            result(false)
            return
        }
        result(ClipboardHelper.copyImageToClipboard(imagePath: imagePath))
    case "copyImageToClipboardFromBytes":
        guard let arguments = call.arguments as? [String: Any],
              let imageData = arguments["imageData"] as? FlutterStandardTypedData else {
            result(false)
            return
        }
        result(ClipboardHelper.copyImageToClipboardFromBytes(imageData: imageData.data))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
