# SpotiRex

SpotiRex is a native macOS now-playing display for the local Spotify and Music apps and Velora's local API. It reads playback metadata and artwork; it has no playback controls.

## Build and open

Requires macOS 14 or later and Xcode with Swift 5.10 or later.

```sh
swift test
./Scripts/build-app.sh
open dist/SpotiRex.app
```

The script produces a locally signed app at `dist/SpotiRex.app`. It is for local use; distribution signing and notarization are separate work.

## Sources

- **Spotify and Music:** Open the corresponding Mac app. On first access, allow SpotiRex's macOS Automation request. The Settings window links to Automation permissions if access was denied. These readers observe only playback in the local apps. Spotify account playback on another device is outside this app's scope.
- **Velora:** Enable **Local API** in Velora's desktop settings. In SpotiRex Settings, choose **Connect Velora (read only)** and approve the request in Velora. SpotiRex stores the resulting read token in macOS Keychain. Revoking it in Velora disconnects SpotiRex; the connection can be approved again. Velora's local API uses port `39031` on `127.0.0.1`.
- **Source:** Auto displays the most recently observed playing source. Choosing Spotify, Music, or Velora pins that source; an inactive pinned source shows the waiting view.

The rich view shows source, artwork, title, artist credit, album, and status when provided. After 10 seconds without pointer activity it shows artwork, title, and artist credit only. A new track, window focus, or pointer activity reveals details again. **Always show minimal view** keeps the simplified view permanently. Artist/collaborator text is shown exactly as supplied by each source.

SpotiRex holds a display-awake activity while its player window is visible, including fullscreen, and releases it when the window is hidden, minimized, or closed. macOS can still lock or sleep for reasons other than idle display sleep.

## Verification boundary

Local Spotify playback, artwork, source selection, the 10-second transition, Always minimal, and display-awake release were verified with the built app on this Mac. Velora HTTP response mapping, bearer authentication, paused state, and revoked-token behavior are covered by tests against a mock transport. Live Velora approval/playback and Music artwork require those sources to be available during device validation.
