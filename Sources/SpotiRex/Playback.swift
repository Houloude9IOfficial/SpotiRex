import AppKit
import Foundation

enum PlaybackSource: String, CaseIterable, Codable, Identifiable {
    case spotify = "Spotify"
    case music = "Music"
    case velora = "Velora"

    var id: String { rawValue }
    var displayName: String { self == .music ? "Apple Music" : rawValue }
}

enum SourceChoice: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case spotify = "Spotify"
    case music = "Music"
    case velora = "Velora"

    var id: String { rawValue }
    var pinnedSource: PlaybackSource? { PlaybackSource(rawValue: rawValue) }
    var displayName: String { self == .music ? "Apple Music" : rawValue }
}

struct TrackSnapshot: Equatable {
    let source: PlaybackSource
    let id: String
    let title: String
    let artists: String
    let album: String
    let artworkURL: URL?
    let isPlaying: Bool

    var identity: String { "\(source.rawValue):\(id)" }
}

enum SourceArbiter {
    static func choose(
        snapshots: [PlaybackSource: TrackSnapshot],
        choice: SourceChoice,
        activity: [PlaybackSource: Date],
        current: PlaybackSource?
    ) -> TrackSnapshot? {
        if let pinned = choice.pinnedSource {
            guard let track = snapshots[pinned], track.isPlaying else { return nil }
            return track
        }
        let playing = snapshots.values.filter { $0.isPlaying }
        return playing.max { left, right in
            let lhs = activity[left.source] ?? .distantPast
            let rhs = activity[right.source] ?? .distantPast
            if lhs == rhs { return right.source == current }
            return lhs < rhs
        }
    }
}

struct LocalReadResult {
    let track: TrackSnapshot?
    let status: String
}

final class LocalPlayerReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.crickdevs.spotirex.apple-events", attributes: .concurrent)

    func read(_ source: PlaybackSource) async -> LocalReadResult {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.readSynchronously(source)) }
        }
    }

    func musicArtwork() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                let script = "with timeout of 5 seconds\n tell application \"Music\" to return raw data of artwork 1 of current track\nend timeout"
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: nil)
                    return
                }
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result.data : nil)
            }
        }
    }

    private func readSynchronously(_ source: PlaybackSource) -> LocalReadResult {
        guard source != .velora else { return LocalReadResult(track: nil, status: "Unavailable") }
        let bundleID = source == .spotify ? "com.spotify.client" : "com.apple.Music"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return LocalReadResult(track: nil, status: "App closed")
        }
        let script: String
        if source == .spotify {
            script = """
            with timeout of 5 seconds
                tell application "Spotify"
                    if player state is not playing then return {"inactive"}
                    set t to current track
                    set trackID to ""
                    set artistName to ""
                    set albumName to ""
                    set coverURL to ""
                    try
                        set trackID to (id of t) as text
                    end try
                    try
                        set artistName to (artist of t) as text
                    end try
                    try
                        set albumName to (album of t) as text
                    end try
                    try
                        set coverURL to (artwork url of t) as text
                    end try
                    return {"playing", trackID, (name of t) as text, artistName, albumName, coverURL}
                end tell
            end timeout
            """
        } else {
            script = """
            with timeout of 5 seconds
                tell application "Music"
                    if player state is not playing then return {"inactive"}
                    set t to current track
                    set trackID to ""
                    set artistName to ""
                    set albumName to ""
                    try
                        set trackID to (persistent ID of t) as text
                    end try
                    try
                        set artistName to (artist of t) as text
                    end try
                    try
                        set albumName to (album of t) as text
                    end try
                    return {"playing", trackID, (name of t) as text, artistName, albumName}
                end tell
            end timeout
            """
        }
        guard let appleScript = NSAppleScript(source: script) else {
            return LocalReadResult(track: nil, status: "Script unavailable")
        }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            let number = error["NSAppleScriptErrorNumber"] as? Int
            let status: String
            switch number {
            case -1743: status = "Automation permission denied"
            case -1712: status = "Player did not respond"
            default: status = "Unable to read playback"
            }
            return LocalReadResult(track: nil, status: status)
        }
        guard result.numberOfItems >= 5, result.atIndex(1)?.stringValue == "playing" else {
            return LocalReadResult(track: nil, status: "Not playing")
        }
        func field(_ index: Int) -> String { result.atIndex(index)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let title = field(3)
        guard !title.isEmpty else { return LocalReadResult(track: nil, status: "No track metadata") }
        let url = source == .spotify ? URL(string: field(6)) : nil
        let track = TrackSnapshot(
            source: source,
            id: field(2).isEmpty ? title + field(4) : field(2),
            title: title,
            artists: field(4),
            album: field(5),
            artworkURL: url,
            isPlaying: true
        )
        return LocalReadResult(track: track, status: "Playing")
    }
}
