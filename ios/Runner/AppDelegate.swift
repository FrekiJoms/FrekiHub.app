import Flutter
import UIKit
import ActivityKit

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FrekiHubSession") else { return }
    FlutterMethodChannel(name: "frekihub/session", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
      let defaults = SessionStorage.defaults
      switch call.method {
      case "pending":
        if let id = defaults.string(forKey: "pendingId") { result(["id": id, "ended": defaults.object(forKey: "pendingEnd") ?? 0]) } else { result(nil) }
      case "acknowledge":
        defaults.removeObject(forKey: "pendingId"); defaults.removeObject(forKey: "pendingEnd"); result(nil)
      case "start":
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let args = call.arguments as? [String: Any], let id = args["id"] as? String, let started = args["started"] as? Int64 else { result(false); return }
        if defaults.string(forKey: "pendingId") == id { result(true); return }
        if let existing = Activity<SessionAttributes>.activities.first(where: { $0.attributes.id == id }) {
          let state = SessionAttributes.ContentState(started: Date(timeIntervalSince1970: Double(started) / 1000), todaySeconds: args["todaySeconds"] as? Int ?? 0)
          Task { await existing.update(using: state); result(true) }; return
        }
        do {
          let state = SessionAttributes.ContentState(started: Date(timeIntervalSince1970: Double(started) / 1000), todaySeconds: args["todaySeconds"] as? Int ?? 0)
          let attributes = SessionAttributes(id: id, day: args["day"] as? String ?? "")
          _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
          result(true)
        } catch { result(false) }
      case "stop":
        Task { for activity in Activity<SessionAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }; result(nil) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if url.scheme == "frekihub", url.host == "clock-out", let activity = Activity<SessionAttributes>.activities.first {
      SessionStorage.defaults.set(activity.attributes.id, forKey: "pendingId")
      SessionStorage.defaults.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: "pendingEnd")
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
