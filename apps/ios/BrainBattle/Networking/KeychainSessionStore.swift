import Foundation
import Security

protocol SessionStoring: Sendable {
  func read() throws -> String?
  func write(_ token: String) throws
}

struct KeychainSessionStore: SessionStoring {
  let account: String
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.brainbattle.native-session",
      kSecAttrAccount as String: account,
    ]
  }
  func read() throws -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
      let token = String(data: data, encoding: .utf8)
    else { throw KeychainError(status: status) }
    return token
  }
  func write(_ token: String) throws {
    let values: [String: Any] = [kSecValueData as String: Data(token.utf8)]
    var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var item = query.merging(values) { _, new in new }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }
}

struct KeychainError: LocalizedError {
  let status: OSStatus
  var errorDescription: String? {
    "The secure guest session could not be accessed (\(status)). Unlock your iPhone and try again."
  }
}
