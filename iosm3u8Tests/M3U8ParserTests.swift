import XCTest
@testable import iosm3u8

final class M3U8ParserTests: XCTestCase {

    private func url(_ s: String) -> URL {
        URL(string: s)!
    }

    func testParseMediaPlaylist() throws {
        let text = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:9.009,
        https://example.com/seg0.ts
        #EXTINF:9.009,
        https://example.com/seg1.ts
        #EXT-X-ENDLIST
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://example.com/index.m3u8"))
        XCTAssertEqual(playlist.segments.count, 2)
        XCTAssertEqual(playlist.segments[0].sequence, 0)
        XCTAssertEqual(playlist.segments[1].sequence, 1)
        XCTAssertEqual(playlist.segments[0].duration, 9.009, accuracy: 0.001)
        XCTAssertEqual(playlist.targetDuration, 10)
        XCTAssertTrue(playlist.isEndList)
        XCTAssertNil(playlist.key)
        XCTAssertEqual(playlist.segments[0].fileName, "0.ts")
    }

    func testRelativeURLResolution() throws {
        let text = """
        #EXTM3U
        #EXTINF:5,
        seg/0.ts
        #EXTINF:5,
        /absolute/1.ts
        #EXTINF:5,
        //cdn.example.com/v/2.ts
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://cdn.example.com/video/index.m3u8"))
        XCTAssertEqual(playlist.segments[0].url.absoluteString, "https://cdn.example.com/video/seg/0.ts")
        XCTAssertEqual(playlist.segments[1].url.absoluteString, "https://cdn.example.com/absolute/1.ts")
        XCTAssertEqual(playlist.segments[2].url.absoluteString, "https://cdn.example.com/v/2.ts")
    }

    func testAESKeyParsing() throws {
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="key.key",IV=0x00000000000000000000000000000001
        #EXTINF:4,
        a.ts
        #EXT-X-ENDLIST
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://example.com/v/index.m3u8"))
        let key = try XCTUnwrap(playlist.key)
        XCTAssertEqual(key.method, "AES-128")
        XCTAssertEqual(key.uri?.absoluteString, "https://example.com/v/key.key")
        XCTAssertEqual(key.ivHex, "0x00000000000000000000000000000001")
    }

    func testKeyWithQuotedCommaInURI() throws {
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="keys/a=1,b=2.key",IV=0x02
        #EXTINF:4,
        a.ts
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://example.com/v/index.m3u8"))
        let key = try XCTUnwrap(playlist.key)
        XCTAssertEqual(key.uri?.absoluteString, "https://example.com/v/keys/a=1,b=2.key")
        XCTAssertEqual(key.ivHex, "0x02")
    }

    func testKeyRotationPerSegment() throws {
        // 密钥轮换：不同分片段使用不同 #EXT-X-KEY，且可切回明文（METHOD=NONE）
        let text = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="key1.key",IV=0x00000000000000000000000000000001
        #EXTINF:4,
        a.ts
        #EXT-X-KEY:METHOD=AES-128,URI="key2.key"
        #EXTINF:4,
        b.ts
        #EXTINF:4,
        c.ts
        #EXT-X-KEY:METHOD=NONE
        #EXTINF:4,
        d.ts
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://example.com/v/index.m3u8"))
        XCTAssertEqual(playlist.segments.count, 4)

        // 分片 a：key1，带显式 IV
        let seg0Key = try XCTUnwrap(playlist.segments[0].key)
        XCTAssertEqual(seg0Key.uri?.lastPathComponent, "key1.key")
        XCTAssertEqual(seg0Key.ivHex, "0x00000000000000000000000000000001")

        // 分片 b/c：轮换为 key2（延续到下一个 KEY 之前）
        let seg1Key = try XCTUnwrap(playlist.segments[1].key)
        XCTAssertEqual(seg1Key.uri?.lastPathComponent, "key2.key")
        XCTAssertEqual(playlist.segments[2].key?.uri?.lastPathComponent, "key2.key")

        // 分片 d：METHOD=NONE 切回明文
        let seg3Key = try XCTUnwrap(playlist.segments[3].key)
        XCTAssertEqual(seg3Key.method, "NONE")
        XCTAssertNil(seg3Key.uri)
    }

    func testUnencryptedSegmentsHaveNilKey() throws {
        let text = """
        #EXTM3U
        #EXTINF:4,
        a.ts
        #EXT-X-KEY:METHOD=AES-128,URI="key.key"
        #EXTINF:4,
        b.ts
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://example.com/v/index.m3u8"))
        XCTAssertNil(playlist.segments[0].key)
        XCTAssertEqual(playlist.segments[1].key?.uri?.lastPathComponent, "key.key")
    }

    func testMasterPlaylistVariants() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        hls/720p/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1920x1080
        hls/1080p/index.m3u8
        """
        let variants = try M3U8Parser.parseMaster(text, baseURL: url("https://example.com/master.m3u8"))
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants[0].bandwidth, 1_280_000)
        XCTAssertEqual(variants[0].resolution, "1280x720")
        XCTAssertEqual(variants[0].codecs, "avc1.4d401f,mp4a.40.2")
        XCTAssertEqual(variants[0].url.absoluteString, "https://example.com/hls/720p/index.m3u8")
        XCTAssertEqual(variants[1].bandwidth, 2_560_000)
        XCTAssertEqual(variants[1].resolution, "1920x1080")
    }

    func testByteRange() throws {
        let text = """
        #EXTM3U
        #EXT-X-BYTERANGE:75232@0
        #EXTINF:4.0,
        segment.ts
        #EXT-X-BYTERANGE:82112@75232
        #EXTINF:4.0,
        segment.ts
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://example.com/seg.m3u8"))
        XCTAssertEqual(playlist.segments.count, 2)
        XCTAssertEqual(playlist.segments[0].byteRange?.length, 75232)
        XCTAssertEqual(playlist.segments[0].byteRange?.offset, 0)
        XCTAssertEqual(playlist.segments[1].byteRange?.length, 82112)
        XCTAssertEqual(playlist.segments[1].byteRange?.offset, 75232)
    }

    func testSegmentFilter() throws {
        let segs = [
            Segment(index: 0, url: url("https://e.com/seg0.ts"), duration: 1, sequence: 0, byteRange: nil, state: .pending, fileName: "0.ts"),
            Segment(index: 1, url: url("https://e.com/seg1.ts"), duration: 1, sequence: 1, byteRange: nil, state: .pending, fileName: "1.ts"),
            Segment(index: 2, url: url("https://e.com/ad.ts"), duration: 1, sequence: 2, byteRange: nil, state: .pending, fileName: "2.ts"),
        ]
        let filtered = M3U8Parser.applyFilter(segs, filter: "seg\\d+\\.ts$")
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].index, 0)
        XCTAssertEqual(filtered[1].index, 1)
    }

    func testNonPlaylistThrows() {
        XCTAssertThrowsError(
            try M3U8Parser.parseMedia("hello world", baseURL: url("https://e.com/a.m3u8"))
        )
        XCTAssertThrowsError(
            try M3U8Parser.parseMaster("not a playlist", baseURL: url("https://e.com/a.m3u8"))
        )
    }

    func testMediaSequenceOffset() throws {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:2,
        a.ts
        #EXTINF:2,
        b.ts
        """
        let playlist = try M3U8Parser.parseMedia(text, baseURL: url("https://e.com/live.m3u8"))
        XCTAssertEqual(playlist.segments[0].sequence, 100)
        XCTAssertEqual(playlist.segments[1].sequence, 101)
        XCTAssertFalse(playlist.isEndList)
    }
}
