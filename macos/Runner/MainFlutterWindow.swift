import Cocoa
import FlutterMacOS

// Local key store backed by the macOS Keychain. Registration mirrors the
// Android/iOS hosts (channel `remedios_app/database_key_store`) so the Dart
// side can use the same MethodChannel on every native platform.
//
// Methods:
//   readKey()                       -> String? (hex, 64 chars) or null
//   createKeyIfAbsent(keyHex)       -> Bool
//   deleteKey()                     -> void
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerDatabaseKeyStoreChannel(flutterViewController.binaryMessenger)

    super.awakeFromNib()
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
