import Foundation
import Security

enum Storage {
    static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Farhad's CV AutoFill", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for name: String) -> URL {
        appSupportDir.appendingPathComponent(name)
    }

    static func loadJSON<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func saveJSON<T: Encodable>(_ value: T, to file: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? data.write(to: url(for: file), options: .atomic)
        }
    }

    static func loadText(from file: String) -> String? {
        try? String(contentsOf: url(for: file), encoding: .utf8)
    }

    static func saveText(_ text: String, to file: String) {
        try? text.write(to: url(for: file), atomically: true, encoding: .utf8)
    }

    static func loadData(from file: String) -> Data? {
        try? Data(contentsOf: url(for: file))
    }

    static func saveData(_ data: Data, to file: String) {
        try? data.write(to: url(for: file), options: .atomic)
    }

    static func deleteFile(_ file: String) {
        try? FileManager.default.removeItem(at: url(for: file))
    }
}

enum Keychain {
    static let service = "com.farhadshad.cvautofill"

    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
