import XCTest
@testable import ClawdCompanion

final class MenuMascotTests: XCTestCase {
    func testAllPosesRemainCrispAndAnimateAtNativeBarSize() throws {
        for pose in MascotPose.allCases {
            let sequence = MenuMascotPixels.durations(for: pose)
            var distinct = Set<Data>()
            for frame in sequence.indices {
                let image = try XCTUnwrap(MenuMascotPixels.raster(pose: pose, frame: frame, agentCount: 3, scale: 1))
                XCTAssertEqual(image.width, 24)
                XCTAssertEqual(image.height, 18)
                let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
                let mask = Array(stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
                XCTAssertGreaterThan(mask.filter { $0 == 255 }.count, 40)
                XCTAssertTrue(mask.allSatisfy { $0 == 0 || $0 == 255 }, "Pixel edges of \(pose)")
                distinct.insert(pixels)
            }
            XCTAssertGreaterThan(distinct.count, 1, "\(pose) needs moving frames")
        }
    }

    func testAgentGlyphsScaleToTheAvailableSpace() throws {
        func frame(for count: Int) throws -> Data {
            let image = try XCTUnwrap(MenuMascotPixels.raster(pose: .juggling, frame: 0, agentCount: count))
            return try XCTUnwrap(image.dataProvider?.data) as Data
        }
        XCTAssertNotEqual(try frame(for: 1), try frame(for: 2))
        XCTAssertNotEqual(try frame(for: 2), try frame(for: 3))
        XCTAssertEqual(try frame(for: 200), try frame(for: 3))
    }

    func testArcadeSilhouettesInscriptionAndOneShotAtNativeMenuSize() throws {
        func cel(_ pose: MascotPose, _ frame: Int) throws -> Data {
            let image = try XCTUnwrap(MenuMascotPixels.raster(pose: pose, frame: frame, scale: 1))
            return try XCTUnwrap(image.dataProvider?.data) as Data
        }
        let grave = try cel(.grave, 0)
        for (y, row) in GraveInscription.rows.enumerated() {
            for (x, cell) in row.enumerated() {
                let alpha = grave[((6 + y) * 24 + 4 + x) * 4 + 3]
                XCTAssertEqual(alpha, cell == "1" ? 0 : 255)
            }
        }
        let poses: [MascotPose] = [.grave, .virusFight, .virusVictory, .reviving, .happy]
        XCTAssertEqual(try Set(poses.map { try cel($0, $0.stillFrame) }).count, poses.count)
        let revival = try (0..<MascotPose.revivalFrames).map { try cel(.reviving, $0) }
        XCTAssertEqual(revival.first, grave)
        XCTAssertEqual(Set(revival).count, revival.count)
        XCTAssertEqual(revival.last, try cel(.reviving, 999))
        XCTAssertEqual(MenuMascotPixels.durations(for: .reviving).reduce(0, +), MascotPose.revivalDuration)
    }

    func testApprovalMenuRollsInReverseAndOKRemainsReadableAtOnePointScale() throws {
        func frame(_ pose: MascotPose, _ index: Int) throws -> Data {
            let cg = try XCTUnwrap(MenuMascotPixels.raster(pose: pose, frame: index, scale: 1))
            return try XCTUnwrap(cg.dataProvider?.data) as Data
        }
        let unfolding = try (0..<5).map { try frame(.approvalOpening, $0) }
        XCTAssertEqual(Set(unfolding).count, 5)
        for i in unfolding.indices { XCTAssertEqual(unfolding[i], try frame(.approvalClosing, 4 - i)) }
        let held = try frame(.awaitingApproval, 0)
        XCTAssertEqual(held, unfolding[4])
        for (y, row) in ApprovalLettering.rows.enumerated() {
            for (x, char) in row.enumerated() {
                XCTAssertEqual(held[((1 + y) * 24 + 10 + x) * 4 + 3], char == "1" ? 0 : 255)
            }
        }
    }
}
