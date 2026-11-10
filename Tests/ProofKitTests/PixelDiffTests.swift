import XCTest
@testable import ProofKit

final class PixelDiffTests: XCTestCase {
    func image(_ w: Int, _ h: Int, paint: [(Int, Int, UInt8)] = []) -> [UInt8] {
        var p = [UInt8](repeating: 255, count: w * h * 4)
        for (x, y, v) in paint { let i = (y * w + x) * 4; p[i] = v; p[i + 1] = v; p[i + 2] = v }
        return p
    }

    func testCountsChangesBelowTheStatusBarAndIgnoresNoise() {
        let a = image(10, 10)
        let b = image(10, 10, paint: [(2, 5, 0), (3, 6, 0), (1, 0, 0), (7, 7, 240)])  // (1,0) is in the status bar, (7,7) is noise
        let r = PixelDiff.compare(a, b, width: 10, height: 10, skipTop: 1)
        XCTAssertEqual(r.changed, 2)
        XCTAssertEqual(r.compared, 90)
        XCTAssertEqual(r.box, [2, 5, 2, 2])
        XCTAssertNil(PixelDiff.compare(a, a, width: 10, height: 10, skipTop: 1).box)
    }

    func testHighlightMarksChangesRed() {
        let mask = [true, false]
        let out = PixelDiff.highlight([10, 10, 10, 255, 30, 30, 30, 255], mask: mask)
        XCTAssertEqual(Array(out[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(out[4], out[5])
    }

    #if canImport(CoreGraphics)
    func testDiffsPNGFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let w = 40, h = 100
        XCTAssertTrue(PixelDiff.write(image(w, h), width: w, height: h, to: dir + "/a.png"))
        XCTAssertTrue(PixelDiff.write(image(w, h, paint: [(10, 50, 0), (11, 50, 0)]), width: w, height: h, to: dir + "/b.png"))
        XCTAssertTrue(PixelDiff.write(image(w, 50), width: w, height: 50, to: dir + "/small.png"))

        let r = try XCTUnwrap(PixelDiff.diff(before: dir + "/a.png", after: dir + "/b.png", output: dir + "/d.png"))
        XCTAssertEqual(r.box, [10, 50, 2, 1])
        XCTAssertEqual(r.image, dir + "/d.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/d.png"))
        XCTAssertTrue(r.text.hasPrefix("pixels: 0.1% changed (box 10,50 2x1)"), r.text)

        let same = try XCTUnwrap(PixelDiff.diff(before: dir + "/a.png", after: dir + "/a.png", output: dir + "/same.png"))
        XCTAssertEqual(same.text, "pixels: no changes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/same.png"))
        XCTAssertTrue(try XCTUnwrap(PixelDiff.diff(before: dir + "/a.png", after: dir + "/small.png", output: dir + "/x.png")).sizeMismatch)
        XCTAssertNil(PixelDiff.diff(before: dir + "/missing.png", after: dir + "/a.png", output: dir + "/x.png"))
    }
    #endif
}
