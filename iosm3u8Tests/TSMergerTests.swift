import XCTest
@testable import iosm3u8

final class TSMergerTests: XCTestCase {

    func testAppendInOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("merged.ts")
        FileManager.default.createFile(atPath: out.path, contents: nil)

        var merger = IncrementalMerger(outputURL: out)

        let seg0 = dir.appendingPathComponent("0.ts")
        try Data(repeating: 0xAA, count: 100).write(to: seg0)
        let seg1 = dir.appendingPathComponent("1.ts")
        try Data(repeating: 0xBB, count: 200).write(to: seg1)

        // 乱序尝试：index 1 先来应失败
        XCTAssertFalse(merger.append(segmentFile: seg1, index: 1))
        XCTAssertEqual(merger.nextIndex, 0)

        XCTAssertTrue(merger.append(segmentFile: seg0, index: 0))
        XCTAssertEqual(merger.nextIndex, 1)
        XCTAssertTrue(merger.append(segmentFile: seg1, index: 1))
        XCTAssertEqual(merger.nextIndex, 2)

        let result = try Data(contentsOf: out)
        XCTAssertEqual(result.count, 300)
        XCTAssertEqual(result.prefix(100), Data(repeating: 0xAA, count: 100))
        XCTAssertEqual(result.suffix(200), Data(repeating: 0xBB, count: 200))
    }

    func testMissingFileReturnsFalse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("merged.ts")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        var merger = IncrementalMerger(outputURL: out)

        let missing = dir.appendingPathComponent("nope.ts")
        XCTAssertFalse(merger.append(segmentFile: missing, index: 0))
        XCTAssertEqual(merger.nextIndex, 0)
    }

    func testResumeFromIndex() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("merged.ts")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        var merger = IncrementalMerger(outputURL: out, nextIndex: 1)

        let seg0 = dir.appendingPathComponent("0.ts")
        try Data(repeating: 0x01, count: 10).write(to: seg0)
        let seg1 = dir.appendingPathComponent("1.ts")
        try Data(repeating: 0x02, count: 20).write(to: seg1)

        // 已合并到 index 1：此时 append(0) 应失败，append(1) 成功
        XCTAssertFalse(merger.append(segmentFile: seg0, index: 0))
        XCTAssertTrue(merger.append(segmentFile: seg1, index: 1))
        XCTAssertEqual(merger.nextIndex, 2)

        let result = try Data(contentsOf: out)
        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result, Data(repeating: 0x02, count: 20))
    }
}
