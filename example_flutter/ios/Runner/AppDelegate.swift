import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var lifecycleChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "dev.keybay.securityharness/keybay_device_security",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "isSimulator" {
        #if targetEnvironment(simulator)
          result(true)
        #else
          result(false)
        #endif
        return
      }
      guard call.method == "lifecyclePhase" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let phases = ["--keybay-lifecycle-seed": "seed", "--keybay-lifecycle-mutate": "mutate", "--keybay-lifecycle-reopen": "reopen", "--keybay-lifecycle-cleanup": "cleanup"]
      let selected = ProcessInfo.processInfo.arguments.compactMap { phases[$0] }
      result(selected.count == 1 ? selected[0] : nil)
    }
    lifecycleChannel = channel
  }
}
