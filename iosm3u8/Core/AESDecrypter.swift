import CommonCrypto
import Foundation

/// AES-128-CBC 解密器（CommonCrypto）
/// - 用于 HLS 标准 AES-128 加密分片
/// - 流式分块解密：跨块传递上一块末尾密文作为 IV（CBC 链），末尾剥离 PKCS7 填充
/// - IV 支持列表显式值（0x...）与按分片序号派生两种
enum AESDecrypter {

    enum DecryptError: LocalizedError {
        case invalidKeyLength
        case invalidLength
        case invalidPadding
        case fileError
        case cccryptFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidKeyLength: return "AES 密钥长度必须为 16 字节（128 位）"
            case .invalidLength: return "密文长度不是 16 的倍数"
            case .invalidPadding: return "PKCS7 填充无效"
            case .fileError: return "解密文件读写失败"
            case .cccryptFailed(let code): return "CCCrypt 失败（\(code)）"
            }
        }
    }

    /// 一次性解密（输入须为 16 的倍数），自动剥离 PKCS7 填充
    static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        let raw = try decryptBlock(data, key: key, iv: iv)
        return stripPKCS7(raw)
    }

    /// 加密（PKCS7 填充）——测试与工具用途
    static func encrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16 else { throw DecryptError.invalidKeyLength }
        var out = [UInt8](repeating: 0, count: data.count + 16)
        var outLen = 0
        let status = data.withUnsafeBytes { inBuf in
            key.withUnsafeBytes { keyBuf in
                iv.withUnsafeBytes { ivBuf in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBuf.baseAddress, key.count,
                        ivBuf.baseAddress,
                        inBuf.baseAddress, data.count,
                        &out, out.count,
                        &outLen
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw DecryptError.cccryptFailed(Int32(status)) }
        return Data(out.prefix(outLen))
    }

    /// 流式解密整文件（原地覆盖）
    /// - 分块 1MB（16 的倍数），边解密边写临时文件
    /// - 每块使用上一块末尾 16 字节密文作为下一块 IV（CBC 链）
    /// - 末尾按 PKCS7 剥离填充后原子替换
    static func decryptFile(at url: URL, key: Data, iv: Data) throws {
        guard key.count == 16 else { throw DecryptError.invalidKeyLength }
        let chunkSize = 1 << 20

        guard let input = try? FileHandle(forReadingFrom: url) else { throw DecryptError.fileError }
        defer { try? input.close() }

        let tempURL = url.appendingPathExtension("dec")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: tempURL) else { throw DecryptError.fileError }
        defer { try? output.close() }

        var runningIV = iv
        var leftover = Data()

        while true {
            let data = input.readData(ofLength: chunkSize)
            if data.isEmpty {
                guard leftover.isEmpty else { throw DecryptError.invalidLength }
                break
            }
            var combined = leftover
            combined.append(data)
            let alignedLength = combined.count - (combined.count % 16)
            guard alignedLength > 0 else {
                leftover = combined
                continue
            }
            let aligned = combined.prefix(alignedLength)
            let decrypted = try decryptBlock(Data(aligned), key: key, iv: runningIV)
            try output.write(contentsOf: decrypted)
            runningIV = Data(combined[alignedLength - 16 ..< alignedLength])
            leftover = Data(combined.suffix(combined.count - alignedLength))
        }

        // 剥离 PKCS7 填充：读取最后 1 字节
        let size = output.offsetInFile
        guard size > 0 else { throw DecryptError.invalidLength }
        try output.seek(toOffset: size - 1)
        guard let last = output.readData(ofLength: 1).first else { throw DecryptError.invalidLength }
        let pad = Int(last)
        guard pad >= 1, pad <= 16, pad <= size else { throw DecryptError.invalidPadding }
        try output.truncate(atOffset: size - UInt64(pad))

        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            throw DecryptError.fileError
        }
    }

    /// 原始 CBC 解密（kCCOptionNone，输入须为 16 的倍数，不剥离填充）
    static func decryptBlock(_ data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16 else { throw DecryptError.invalidKeyLength }
        guard data.count % 16 == 0 else { throw DecryptError.invalidLength }

        var out = [UInt8](repeating: 0, count: data.count)
        var outLen = 0
        let status = data.withUnsafeBytes { inBuf in
            key.withUnsafeBytes { keyBuf in
                iv.withUnsafeBytes { ivBuf in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0),
                        keyBuf.baseAddress, key.count,
                        ivBuf.baseAddress,
                        inBuf.baseAddress, data.count,
                        &out, out.count,
                        &outLen
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw DecryptError.cccryptFailed(Int32(status)) }
        return Data(out.prefix(outLen))
    }

    /// 剥离 PKCS7 填充
    static func stripPKCS7(_ data: Data) -> Data {
        guard let last = data.last, last >= 1, last <= 16, Int(last) <= data.count else {
            return data
        }
        return data.dropLast(Int(last))
    }

    /// 从 #EXT-X-KEY IV 十六进制串解析（支持 0x 前缀），须为 16 字节
    static func ivData(fromHex hex: String) -> Data? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        guard s.count == 32 else { return nil }
        return Data(hexString: s)
    }

    /// HLS 默认 IV：前 12 字节为 0，后 4 字节为分片序号（大端）
    static func defaultIV(forSequence sequence: Int64) -> Data {
        var seq = UInt64(truncatingIfNeeded: sequence).bigEndian
        var bytes = [UInt8](repeating: 0, count: 12)
        bytes.append(contentsOf: withUnsafeBytes(of: &seq) { Array($0) })
        return Data(bytes)
    }
}

// MARK: - Data 十六进制解析

extension Data {
    init?(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self = Data(bytes)
    }
}
