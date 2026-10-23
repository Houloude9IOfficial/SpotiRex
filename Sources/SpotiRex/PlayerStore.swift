import AppKit
import SwiftUI

@MainActor
final class PlayerStore: ObservableObject {
    @Published var choice: SourceChoice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: "sourceChoice")
            selectTrack()
        }
    }
    @Published var alwaysMinimal: Bool {
        didSet { UserDefaults.standard.set(alwaysMinimal, forKey: "alwaysMinimal") }
    }
    @Published private(set) var currentTrack: TrackSnapshot?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent = Color(red: 0.17, green: 0.52, blue: 0.53)
    @Published private(set) var now = Date()
    @Published private(set) var richUntil = Date.distantPast
    @Published private(set) var statuses: [PlaybackSource: String] = [:]
    let velora = VeloraClient()

    private let localReader = LocalPlayerReader()
    private var snapshots: [PlaybackSource: TrackSnapshot] = [:]
    private var activity: [PlaybackSource: Date] = [:]
    private var artworkCache: [String: Data] = [:]
    private var pollingTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var isRefreshing = false
    private weak var playerWindow: NSWindow?
    private var wakeActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var pointerMonitor: Any?

    var isMinimal: Bool { alwaysMinimal || now >= richUntil }

    init() {
        choice = SourceChoice(rawValue: UserDefaults.standard.string(forKey: "sourceChoice") ?? "Auto") ?? .automatic
        alwaysMinimal = UserDefaults.standard.bool(forKey: "alwaysMinimal")
        velora.onUpdate = { [weak self] in
            Task { await self?.refresh() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self else { return }
                    if notification.name == NSWindow.didBecomeKeyNotification,
                       notification.object as? NSWindow === self.playerWindow { self.revealRich() }
                    self.updateDisplayAwake()
                }
            })
        }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                if event.window === self?.playerWindow { self?.revealRich() }
            }
            return event
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func registerWindow(_ window: NSWindow?) {
        playerWindow = window
        window?.acceptsMouseMovedEvents = true
        updateDisplayAwake()
    }

    func notePointerActivity() { revealRich() }

    func revealRich() {
        guard !alwaysMinimal else { return }
        richUntil = Date().addingTimeInterval(10)
        now = Date()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let spotify = localReader.read(.spotify)
        async let music = localReader.read(.music)
        async let veloraResult = velora.read()
        apply(await veloraResult, from: .velora)
        apply(await music, from: .music)
        apply(await spotify, from: .spotify)
    }

    private func apply(_ result: LocalReadResult, from source: PlaybackSource) {
        let old = snapshots[source]
        if let track = result.track {
            snapshots[source] = track
            if old?.identity != track.identity || old?.isPlaying != track.isPlaying {
                activity[source] = Date()
            }
        } else {
            snapshots.removeValue(forKey: source)
        }
        statuses[source] = result.status
        selectTrack()
    }

    private func selectTrack() {
        let selected = SourceArbiter.choose(snapshots: snapshots, choice: choice, activity: activity, current: currentTrack?.source)
        let previousIdentity = currentTrack?.identity
        currentTrack = selected
        if selected?.identity != previousIdentity {
            artworkTask?.cancel()
            artwork = nil
            accent = Color(red: 0.17, green: 0.52, blue: 0.53)
            if let selected {
                revealRich()
                artworkTask = Task { [weak self] in await self?.loadArtwork(for: selected) }
            }
        }
    }

    private func loadArtwork(for track: TrackSnapshot) async {
        let data: Data?
        if let cached = artworkCache[track.identity] {
            data = cached
        } else if track.source == .music {
            data = await localReader.musicArtwork()
        } else if let url = track.artworkURL,
                  url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            data = try? await URLSession.shared.data(for: request).0
        } else {
            data = nil
        }
        guard !Task.isCancelled, currentTrack?.identity == track.identity,
              let data, data.count <= 8_000_000, let image = NSImage(data: data) else { return }
        artworkCache[track.identity] = data
        artwork = image
        accent = Self.accentColor(from: data)
    }

    private static func accentColor(from data: Data) -> Color {
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            return Color(red: 0.17, green: 0.52, blue: 0.53)
        }
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 12)) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 12)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                count += 1
            }
        }
        guard count > 0 else { return .teal }
        return Color(red: min(0.75, red / count), green: min(0.75, green / count), blue: min(0.75, blue / count))
    }

    private func updateDisplayAwake() {
        let visible = playerWindow?.isVisible == true && playerWindow?.isMiniaturized == false && !NSApp.isHidden
        if visible && wakeActivity == nil {
            wakeActivity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "SpotiRex player window is visible")
        } else if !visible, let wakeActivity {
            ProcessInfo.processInfo.endActivity(wakeActivity)
            self.wakeActivity = nil
        }
    }
}
