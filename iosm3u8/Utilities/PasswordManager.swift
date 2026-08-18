import CryptoKit
import Foundation
import LocalAuthentication

/// 密码管理：加盐哈希存储（Keychain）+ 校验 + 生物识别
enum PasswordManager {
    private static let hashKey = "app_password_hash"

    static var hasPassword: Bool {
        KeychainHelper.get(hashKey) != nil
    }

    /// 设置/修改密码：存 "salt::hash"
    @discardableResult
    static func setPassword(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        let salt = UUID().uuidString
        let hash = saltedHash(password, salt: salt)
        return KeychainHelper.set("\(salt)::\(hash)", forKey: hashKey)
    }

    static func verify(_ password: String) -> Bool {
        guard let stored = KeychainHelper.get(hashKey) else { return false }
        let parts = stored.components(separatedBy: "::")
        guard parts.count == 2 else { return false }
        return saltedHash(password, salt: parts[0]) == parts[1]
    }

    static func removePassword() {
        KeychainHelper.delete(hashKey)
    }

    /// Face ID / Touch ID 校验
    static func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "使用生物识别解锁 M3U8 下载器"
            )
        } catch {
            return false
        }
    }

    private static func saltedHash(_ password: String, salt: String) -> String {
        let input = "\(salt)::\(password)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
