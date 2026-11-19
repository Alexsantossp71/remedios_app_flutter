import Flutter
import UIKit

// Local key store backed by the iOS Keychain. Registration mirrors the
// Android host (channel `remedios_app/database_key_store`) so the Dart side
// can use the same MethodChannel on every native platform.
//
// Methods:
//   readKey()                       -> String? (hex, 64 chars) or null
//   createKeyIfAbsent(keyHex)       -> Bool
//   deleteKey()                     -> void
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController,
       let binaryMessenger = controller.binaryMessenger as? FlutterBinaryMessenger? {
      registerDatabaseKeyStoreChannel(binaryMessenger!)
    } else if let controller = window?.rootViewController as? FlutterViewController {
      registerDatabaseKeyStoreChannel(controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerDatabaseKeyStoreChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "remedios_app/database_key_store",
      binaryMessenger: messenger
    )
    let keyStore = DatabaseKeyStore()

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "readKey":
        do {
          let key = try keyStore.readKey()
          if let key = key {
            result(key.hexString)
          } else {
            result(nil)
          }
        } catch let error as DatabaseKeyError {
          result(FlutterError(code: error.channelCode, message: error.errorDescription, details: nil))
        } catch {
          result(FlutterError(code: "key_store_error", message: error.localizedDescription, details: nil))
        }

      case "createKeyIfAbsent":
        guard let args = call.arguments as? [String: Any],
              let keyHex = args["keyHex"] as? String,
              keyHex.count == 64 else {
          result(FlutterError(code: "invalid_argument",
                              message: "keyHex must contain exactly 64 hex characters.",
                              details: nil))
          return
        }
        guard let key = Data(hexString: keyHex) else {
          result(FlutterError(code: "invalid_argument",
                              message: "keyHex is not valid hexadecimal.",
                              details: nil))
          return
        }
        do {
          let created = try keyStore.createKeyIfAbsent(key)
          result(created)
        } catch let error as DatabaseKeyError {
          result(FlutterError(code: error.channelCode, message: error.errorDescription, details: nil))
        } catch {
          result(FlutterError(code: "key_store_error", message: error.localizedDescription, details: nil))
        }

      case "deleteKey":
        do {
          try keyStore.deleteKey()
          result(nil)
        } catch let error as DatabaseKeyError {
          result(FlutterError(code: error.channelCode, message: error.errorDescription, details: nil))
        } catch {
          result(FlutterError(code: "key_store_error", message: error.localizedDescription, details: nil))
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// MARK: - Data hex helpers

private extension Data {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
  init?(hexString: String) {
    guard hexString.count % 2 == 0 else { return nil }
    var data = Data(capacity: hexString.count / 2)
    var index = hexString.startIndex
    while index < hexString.endIndex {
      let next = hexString.index(index, offsetBy: 2)
      guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
      data.append(byte)
      index = next
    }
    self = data
  }
}
