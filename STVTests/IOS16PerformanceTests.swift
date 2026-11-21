import XCTest
import SwiftUI
import UIKit
@testable import STV

@MainActor
final class IOS16PerformanceTests: XCTestCase {
    func testNewSearchCancelsPreviousRequest() async throws {
        let pager = Pager()
        let started = expectation(description: "first search started")
        let cancelled = expectation(description: "previous search cancelled")
        pager.reset { _, _ in
            started.fulfill()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { cancelled.fulfill(); throw error }
            return HGPage(items: [], hasMore: false)
        }
        await fulfillment(of: [started], timeout: 2)
        pager.reset { _, _ in HGPage(items: [], hasMore: false) }
        await fulfillment(of: [cancelled], timeout: 2)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(pager.isLoading)
        XCTAssertNil(pager.error)
    }

    func testPosterBoundsAndAspectRatio() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 3600), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2400, height: 3600))
        }
        let result = await Task.detached { CoverStore.preparePoster(original) }.value
        let pixels = try XCTUnwrap(result.cgImage)
        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 640)
        XCTAssertEqual(Double(pixels.width) / Double(pixels.height), 2.0 / 3.0, accuracy: 0.005)
        XCTAssertLessThan(pixels.bytesPerRow * pixels.height, 2 * 1024 * 1024)
        XCTAssertEqual(original.cgImage?.width, 2400)
        print("PERF poster original=2400x3600 thumbnail=\(pixels.width)x\(pixels.height) bytes=\(pixels.bytesPerRow * pixels.height)")
    }

    func testEpisodePagerKeepsVisibleWorkBounded() async throws {
        var creations = 0
        func pager(selection: Int = 0) -> EpisodePager<Text> {
            EpisodePager(count: 200, selection: selection, enabled: true, revision: "unchanged",
                         onSelect: { _ in }, onOffset: { _ in }, onSettled: { _ in }) { index in
                creations += 1
                return Text("Episode \(index)")
            }
        }
        let controller = EpisodePager<Text>.Controller(configuration: pager())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 200)
        XCTAssertGreaterThan(collection.visibleCells.count, 0)
        XCTAssertLessThan(collection.visibleCells.count, 5)
        let initial = creations
        XCTAssertGreaterThan(initial, 0)
        for _ in 0..<100 { controller.update(pager()) }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(creations, initial, "Playback/offset updates must not rebuild visible episode cells")
        controller.update(pager(selection: 150))
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(collection.contentOffset.y, 150 * collection.bounds.height, accuracy: 1)
        XCTAssertLessThan(creations, 12, "Jumping should create nearby cells, not all 200 episodes")
        print("PERF pager episodes=200 initialBuilds=\(initial) afterJumpBuilds=\(creations)")
    }

    func testLocalPlaybackStartupAndRepeatedSwitches() async throws {
        let data = try TDLibStreamTests.fixture("player_landscape.mp4")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        defer { engine.stop() }
        engine.muted = true
        for iteration in 0..<4 {
            let begin = Date()
            try await engine.load(.file(url), stream: nil, start: nil, title: "Fixture \(iteration)")
            engine.play(rate: 1)
            while engine.currentTime < 0.1, Date().timeIntervalSince(begin) < 10 {
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertGreaterThanOrEqual(engine.currentTime, 0.1, "Playback must advance after each replacement")
            print("PERF local playback-progress iteration=\(iteration) elapsed_ms=\(Int(Date().timeIntervalSince(begin) * 1000))")
        }
    }
}
