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

    // How much room is left on the device: the one thing this app needs from
    // the platform that Flutter does not ship. A few lines rather than a
    // package, which would have to survive the versions this project pins.
    let channel = FlutterMethodChannel(
      name: "looper/storage",
      binaryMessenger: engineBridge.applicationBinaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "freeBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(AppDelegate.freeBytes())
    }
  }

  private static func freeBytes() -> NSNumber? {
    guard
      let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
      let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let available = values.volumeAvailableCapacityForImportantUsage
    else {
      return nil
    }
    return NSNumber(value: available)
  }
}
