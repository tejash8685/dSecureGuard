import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deviceChannel: FlutterMethodChannel?
  private var pendingNotification: [String: Any]?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "dharmaj/device", binaryMessenger: controller.binaryMessenger)
      deviceChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "requestNotificationPermission":
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { result(granted) }
          }
        case "showActivationNotification":
          let args = call.arguments as? [String: Any] ?? [:]
          let content = UNMutableNotificationContent()
          content.title = args["title"] as? String ?? "Activation update"
          content.body = args["body"] as? String ?? "Your activation request has been updated."
          content.sound = .default
          var details: [String: Any] = ["activation_notification": true]
          for key in ["status", "productId", "productCode"] {
            if let value = args[key], !(value is NSNull) { details[key] = value }
          }
          content.userInfo = details
          let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
          UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
              if error != nil { result(FlutterError(code: "NOTIFICATION_FAILED", message: "Notification could not be shown.", details: nil)) }
              else { result(nil) }
            }
          }
        case "getActivationNotification":
          result(self?.pendingNotification)
          self?.pendingNotification = nil
        case "startRequestMonitor":
          // iOS cannot run the Android foreground polling service.
          result(false)
        case "stopRequestMonitor":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.content.userInfo["activation_notification"] as? Bool == true {
      completionHandler([.alert, .sound])
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    if info["activation_notification"] as? Bool == true {
      var details: [String: Any] = ["status": info["status"] as? String ?? "Pending"]
      for key in ["productId", "productCode"] { if let value = info[key] { details[key] = value } }
      DispatchQueue.main.async { [weak self] in
        self?.pendingNotification = details
        self?.deviceChannel?.invokeMethod("activationNotificationTapped", arguments: details)
        completionHandler()
      }
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }
}
