import XCTest
@testable import iosm3u8

final class AESDecrypterTests: XCTestCase {

    private let key = Data("0123456789abcdef".utf8)   // 16 字节
    private let iv = Data("fedcba9876543210".utf8)    // 16 字节

    func testRoundTripDecrypt() throws {
        let plain = Data("Hello, HLS AES-128 world!".utf8)   // 29 字节 → PKCS7 补到 32
        let encrypted = try AESDecrypter.encrypt(plain, key: key, iv: iv)
        XCTAssertEqual(encrypted.count % 16, 0)
        XCTAssertGreaterThan(encrypted.count, plain.count)

        let decrypted = try AESDecrypter.decrypt(encrypted, key: key, iv: iv)
        XCTAssertEqual(decrypted, plain)
    }

    func testRoundTripExactBlock() throws {
        // 恰好 16 字节：PKCS7 仍会补一整块
        let plain = Data("0123456789abcdef".utf8)
        let encrypted = try AESDecrypter.encrypt(plain, key: key, iv: iv)
        XCTAssertEqual(encrypted.count, 32)
        XCTAssertEqual(try AESDecrypter.decrypt(encrypted, key: key, iv: iv), plain)
    }

    func testDecryptFileStreaming() throws {
        // 1.5MB 明文，跨多个 1MB 分块，验证 CBC 链跨块正确
        var plain = Data(repeating: 0xAB, count: 1_500_000)
        plain.replaceSubrange(0..<16, with: Data("0123456789abcdef".utf8))

        let encrypted = try AESDecrypter.encrypt(plain, key: key, iv: iv)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("seg.ts")
        try encrypted.write(to: file)

        try AESDecrypter.decryptFile(at: file, key: key, iv: iv)

        let result = try Data(contentsOf: file)
        XCTAssertEqual(result, plain)
    }

    func testIVFromHex() throws {
        let iv = try XCTUnwrap(AESDecrypter.ivData(fromHex: "0x00000000000000000000000000000001"))
        XCTAssertEqual(iv.count, 16)
        XCTAssertEqual(iv[15], 1)
        XCTAssertEqual(iv[0], 0)

        let plain = try XCTUnwrap(AESDecrypter.ivData(fromHex: "000102030405060708090A0B0C0D0E0F"))
        XCTAssertEqual(plain[0], 0x00)
        XCTAssertEqual(plain[15], 0x0F)
    }

    func testIVFromHexInvalid() {
        XCTAssertNil(AESDecrypter.ivData(fromHex: "0x1234"))               // 太短
        XCTAssertNil(AESDecrypter.ivData(fromHex: "0xZZ000000000000000000000000000001")) // 非法字符
    }

    func testDefaultIVBySequence() {
        let iv = AESDecrypter.defaultIV(forSequence: 5)
        XCTAssertEqual(iv.count, 16)
        XCTAssertEqual(iv.prefix(12), Data(repeating: 0, count: 12))
        XCTAssertEqual(iv[12], 0)
        XCTAssertEqual(iv[13], 0)
        XCTAssertEqual(iv[14], 0)
        XCTAssertEqual(iv[15], 5)

        let big = AESDecrypter.defaultIV(forSequence: 0x01020304)
        XCTAssertEqual(big[12], 0x01)
        XCTAssertEqual(big[13], 0x02)
        XCTAssertEqual(big[14], 0x03)
        XCTAssertEqual(big[15], 0x04)
    }

    func testInvalidKeyLengthThrows() {
        let badKey = Data("short".utf8)
        let data = Data(repeating: 0, count: 16)
        XCTAssertThrowsError(try AESDecrypter.decrypt(data, key: badKey, iv: iv))
        XCTAssertThrowsError(try AESDecrypter.encrypt(data, key: badKey, iv: iv))
    }

    func testInvalidLengthThrows() {
        let data = Data(repeating: 0, count: 15)   // 非 16 倍数
        XCTAssertThrowsError(try AESDecrypter.decrypt(data, key: key, iv: iv))
    }
}
