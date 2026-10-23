import XCTest
@testable import SpotiRex

final class PlaybackTests: XCTestCase {
    private func track(_ source: PlaybackSource, _ id: String) -> TrackSnapshot {
        TrackSnapshot(source: source, id: id, title: id, artists: "Artist", album: "Album", artworkURL: nil, isPlaying: true)
    }

    func testAutomaticChoosesMostRecentlyActiveSource() {
        let spotify = track(.spotify, "one")
        let velora = track(.velora, "two")
        let snapshots: [PlaybackSource: TrackSnapshot] = [.spotify: spotify, .velora: velora]
        let now = Date()
        let result = SourceArbiter.choose(snapshots: snapshots, choice: .automatic,
                                          activity: [.spotify: now.addingTimeInterval(-3), .velora: now], current: .spotify)
        XCTAssertEqual(result?.source, .velora)
    }

    func testAutomaticKeepsCurrentSourceOnTie() {
        let snapshots: [PlaybackSource: TrackSnapshot] = [.spotify: track(.spotify, "one"), .music: track(.music, "two")]
        let now = Date()
        let result = SourceArbiter.choose(snapshots: snapshots, choice: .automatic,
                                          activity: [.spotify: now, .music: now], current: .spotify)
        XCTAssertEqual(result?.source, .spotify)
    }

    func testPinnedSourceDoesNotFallBack() {
        let snapshots: [PlaybackSource: TrackSnapshot] = [.spotify: track(.spotify, "one")]
        XCTAssertNil(SourceArbiter.choose(snapshots: snapshots, choice: .velora, activity: [:], current: .spotify))
    }

    func testNoPlayingSourceShowsWaitingState() {
        XCTAssertNil(SourceArbiter.choose(snapshots: [:], choice: .automatic, activity: [:], current: nil))
    }
}
