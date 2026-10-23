import AppKit
import SwiftUI

@main
struct SpotiRexApp: App {
    @StateObject private var store = PlayerStore()

    var body: some Scene {
        Window("SpotiRex", id: "player") {
            PlayerView()
                .environmentObject(store)
                .background(WindowProbe { window in store.registerWindow(window) })
                .task { store.start() }
        }
        .defaultSize(width: 1040, height: 680)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

private struct PlayerView: View {
    @EnvironmentObject private var store: PlayerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.035, green: 0.055, blue: 0.075)
                RadialGradient(colors: [store.accent.opacity(0.43), .clear], center: .init(x: 0.30, y: 0.48), startRadius: 10, endRadius: max(geometry.size.width, geometry.size.height) * 0.75)
                RadialGradient(colors: [store.accent.opacity(0.17), .clear], center: .init(x: 0.82, y: 0.85), startRadius: 10, endRadius: geometry.size.width * 0.55)
                if let track = store.currentTrack {
                    trackContent(track, size: geometry.size)
                        .padding(.horizontal, max(38, geometry.size.width * 0.065))
                        .padding(.vertical, 56)
                        .transition(.opacity)
                } else {
                    waitingContent
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.currentTrack?.identity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.isMinimal)
        }
        .frame(minWidth: 640, minHeight: 420)
        .preferredColorScheme(.dark)
    }

    private func trackContent(_ track: TrackSnapshot, size: CGSize) -> some View {
        let coverSide = min(size.height * 0.62, size.width * 0.42, 520)
        return HStack(alignment: .center, spacing: max(34, size.width * 0.065)) {
            artwork(side: coverSide)
            VStack(alignment: .leading, spacing: 0) {
                if !store.isMinimal {
                    Text(track.source.displayName.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(3.2)
                        .foregroundStyle(.white.opacity(0.68))
                        .padding(.bottom, 31)
                        .transition(.opacity)
                }
                Text(track.title)
                    .font(.system(size: titleSize(for: track.title, width: size.width), weight: .semibold, design: .rounded))
                    .tracking(-2)
                    .foregroundStyle(.white)
                    .lineLimit(6)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !track.artists.isEmpty {
                    Text(track.artists)
                        .font(.system(size: min(29, max(20, size.width * 0.027)), weight: .regular))
                        .foregroundStyle(.white.opacity(0.69))
                        .lineLimit(3)
                        .padding(.top, 18)
                }
                if !store.isMinimal {
                    if !track.album.isEmpty && track.album.caseInsensitiveCompare(track.title) != .orderedSame {
                        Text(track.album)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.49))
                            .lineLimit(2)
                            .padding(.top, 33)
                    }
                    Text("PLAYING")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.top, 28)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func titleSize(for title: String, width: CGFloat) -> CGFloat {
        if title.count > 75 { return width < 800 ? 29 : 37 }
        if title.count > 45 { return width < 800 ? 34 : 48 }
        return min(66, max(38, width * 0.054))
    }

    private func artwork(side: CGFloat) -> some View {
        Group {
            if let artwork = store.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [store.accent.opacity(0.8), Color(red: 0.08, green: 0.12, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "waveform").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35)))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Album artwork")
    }

    private var waitingContent: some View {
        VStack(spacing: 18) {
            if let url = Bundle.main.url(forResource: "SpotiRexIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Text("SpotiRex")
                .font(.system(size: 35, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Waiting for music")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: PlayerStore

    var body: some View {
        Form {
            Picker("Source", selection: $store.choice) {
                ForEach(SourceChoice.allCases) { choice in Text(choice.displayName).tag(choice) }
            }
            Toggle("Always show minimal view", isOn: $store.alwaysMinimal)
            Text("Otherwise, source details appear on a new track or when you move the pointer over the window, then fade after 10 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Connections") {
                ForEach(PlaybackSource.allCases) { source in
                    HStack {
                        Text(source.displayName)
                        Spacer()
                        Text(store.statuses[source] ?? "Checking…")
                            .foregroundStyle(.secondary)
                    }
                }
                if store.velora.isConnected {
                    Button("Disconnect Velora") { store.velora.disconnect() }
                } else {
                    Button(store.velora.isAuthorizing ? "Waiting for Velora approval…" : "Connect Velora (read only)") {
                        Task { await store.velora.requestReadAccess() }
                    }
                    .disabled(store.velora.isAuthorizing)
                }
                Text("Enable the Local API in Velora first. SpotiRex requests read access only; approve it in Velora.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                Text("macOS asks for Automation access before SpotiRex can read Spotify or Music. No playback commands are sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .frame(width: 470, height: 500)
    }
}

private struct WindowProbe: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onWindowChange = onWindowChange
        DispatchQueue.main.async { onWindowChange(nsView.window) }
    }

    final class ProbeView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { onWindowChange?(window) }
    }
}
