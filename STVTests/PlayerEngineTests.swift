import XCTest
@testable import STV

final class PlayerEngineTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(PlayerTech.audioName(codec: "eac3", channels: 6), "E-AC3 5.1")
        XCTAssertEqual(PlayerTech.channelLabel(2), "2.0")
        XCTAssertEqual(MediaTrack.title(name: "UND (aac)", language: "und", codec: "aac", channels: 2, index: 0), "轨道 1 · AAC 2.0")
        XCTAssertEqual(MediaTrack.title(name: "Director Commentary", language: "und", codec: "", channels: 0, index: 1), "Director Commentary")
        XCTAssertTrue(MediaTrack.title(name: "", language: "jpn", codec: "aac", channels: 6, index: 1).hasSuffix("AAC 5.1"))
    }

    func testEngineSettingDefaultsToAVPlayer() {
        let d = UserDefaults.standard
        let old = d.object(forKey: PlayerEngineSettings.key)
        defer { d.set(old, forKey: PlayerEngineSettings.key) }
        d.set("aether", forKey: PlayerEngineSettings.key)
        XCTAssertEqual(PlayerEngineSettings.preferred, .avplayer)
        d.removeObject(forKey: PlayerEngineSettings.key)
        XCTAssertEqual(PlayerEngineSettings.preferred, .avplayer)
    }
}
