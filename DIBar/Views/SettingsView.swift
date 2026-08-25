import SwiftUI
import ServiceManagement

/// Content of the standalone "DIBar Settings" window.
struct SettingsWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin: Bool?
    @State private var isUpdatingLaunchAtLogin = false
    @State private var showLogoutConfirmation = false
    @State private var draggedMenuBarComponent: MenuBarComponent?
    @State private var dragOriginMenuBarOrder: [MenuBarComponent]?
    @State private var provisionalMenuBarOrder: [MenuBarComponent]?
    @State private var menuBarDropTargetSlot: Int?
    var onCheckForUpdates: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DIBar")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Self.versionLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check for updates…") {
                    onCheckForUpdates()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .help("DIBar checks for new versions automatically once a day. Updates are downloaded from GitHub and installed in place.")

            Divider()

            settingsRow("Quality") {
                qualityMenu
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ToggleChip(
                        title: "play/pause",
                        systemImage: "playpause.fill",
                        width: 28,
                        isOn: Bindable(appState).menuBarShowPlayState
                    )

                    Image("MenuBarIcon")
                        .frame(width: 24, height: 18)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("DIBar logo")

                    menuBarMetadataGrid
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Image(nsImage: MenuBarLabelRenderer.labelImage(
                line1: displayedMenuBarPreviewLines.line1,
                line2: displayedMenuBarPreviewLines.line2,
                glyph: previewGlyph
            ))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)

            Divider()

            settingsRow("Launch at login") {
                if launchAtLogin == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Toggle("", isOn: launchAtLoginBinding)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .disabled(isUpdatingLaunchAtLogin)
                }
            }

            Divider()

            settingsRow("Global shortcuts") {
                Toggle("", isOn: Bindable(appState).globalHotkeysEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .help("System-wide keyboard shortcuts that work in any app.")

            VStack(alignment: .leading, spacing: 5) {
                shortcutRow(label: "play/pause") {
                    KeyCap("⌃"); KeyCap("⌥"); KeyCap("⌘"); KeyCap("P")
                    keySeparator("or")
                    KeyCap(systemImage: "playpause.fill")
                }
                shortcutRow(label: "prev/next fav channel") {
                    KeyCap("⌃"); KeyCap("⌥"); KeyCap("⌘"); KeyCap("←")
                    keySeparator("/")
                    KeyCap("→")
                    keySeparator("or")
                    KeyCap(systemImage: "backward.fill")
                    keySeparator("/")
                    KeyCap(systemImage: "forward.fill")
                }
                shortcutRow(label: "prev/next site") {
                    KeyCap("⌃"); KeyCap("⌥"); KeyCap("⌘"); KeyCap("↑")
                    keySeparator("/")
                    KeyCap("↓")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Divider()

            settingsRow("Notification on song change") {
                Toggle("", isOn: Bindable(appState).notifyTrackChanges)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .help("Shows a notification with the artist and song each time the track changes while the popover is closed.")

            settingsRow("Notification on channel switch") {
                Toggle("", isOn: Bindable(appState).notifySwitchChanges)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .help("Shows the site, channel, and song when you switch channels with a keyboard shortcut.")

            if let hint = appState.notifyPermissionHint {
                notificationPermissionHint(hint)
            }

            Divider()

            settingsRow("Sleep timer quits DIBar") {
                Toggle("", isOn: Bindable(appState).sleepTimerQuitsApp)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .help("When the sleep timer fires, quit DIBar entirely instead of just pausing playback.")

            Divider()

            scrobblingSection

            Divider()

            Button {
                WebBrowserOpener.open(appState.subscriptionURL)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.membershipHeaderLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(appState.membershipDetailLine)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()

            settingsRow("DI.FM account") {
                HStack(spacing: 8) {
                    if let email = appState.accountEmail {
                        Text(email)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HoverTextButton(title: "Log Out", tint: .red) {
                        showLogoutConfirmation = true
                    }
                }
            }
        }
        .frame(width: 320)
        .task {
            guard launchAtLogin == nil else { return }
            launchAtLogin = await Self.readLaunchAtLoginStatus()
        }
        .alert("Log out of DI.FM?", isPresented: $showLogoutConfirmation) {
            Button("Log Out", role: .destructive) {
                appState.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let email = appState.accountEmail {
                Text("You're signed in as \(email). You'll need to sign in again to listen.")
            } else {
                Text("You'll need to sign in with your account again to listen.")
            }
        }
    }

    // MARK: - Launch at Login

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin ?? false },
            set: updateLaunchAtLogin
        )
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }
        launchAtLogin = enabled
        isUpdatingLaunchAtLogin = true

        Task {
            let resolved = await Task.detached(priority: .userInitiated) {
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    return enabled
                } catch {
                    return SMAppService.mainApp.status == .enabled
                }
            }.value
            launchAtLogin = resolved
            isUpdatingLaunchAtLogin = false
        }
    }

    private static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// "1.3.2 · 28 jul 2026" — the date comes from the executable on disk,
    /// so it tracks whatever build is actually running.
    private static let versionLine: String = {
        guard let url = Bundle.main.executableURL,
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
                  .flatMap(\.contentModificationDate)
        else { return appVersion }
        return "\(appVersion) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }()

    private static func readLaunchAtLoginStatus() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            SMAppService.mainApp.status == .enabled
        }.value
    }

    // MARK: - Scrobbling

    private var scrobblingSection: some View {
        VStack(spacing: 0) {
            // Last.fm — also feeds Airbuds (connect Last.fm inside Airbuds)
            settingsRow("Last.fm") {
                lastFMControl
            }
            .help("Sends the songs you listen to (at least half through, or 4 minutes) to your Last.fm profile. Apps like Airbuds can read them from there.")

            if let error = appState.scrobbler.connectionError {
                caption(error, color: .orange)
            } else if appState.scrobbler.lastFMNeedsReconnect {
                caption("Last.fm session expired — connect again", color: .orange)
            }
        }
    }

    @ViewBuilder
    private var lastFMControl: some View {
        let scrobbler = appState.scrobbler
        if !LastFMClient.isConfigured {
            Text("Requires an API key (see ScrobbleClients.swift)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        } else if let username = scrobbler.lastFMUsername, scrobbler.lastFMConnected {
            HStack(spacing: 8) {
                Text(username)
                    .font(.system(size: 11))
                HoverTextButton(title: "Disconnect", tint: .red) {
                    scrobbler.disconnectLastFM()
                }
            }
        } else if scrobbler.lastFMPendingToken != nil {
            Button("Finish connecting") {
                scrobbler.finishLastFMConnect()
            }
            .controlSize(.small)
        } else {
            Button("Connect…") {
                scrobbler.connectLastFM()
            }
            .controlSize(.small)
        }
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    private func notificationPermissionHint(_ hint: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(hint)
            Button("Open System Settings → Notifications") {
                openNotificationSettings()
            }
            .buttonStyle(.plain)
            .underline()
            .cursor(.pointingHand)
        }
        .font(.system(size: 10))
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func openNotificationSettings() {
        let appURL = TrackNotifier.notificationSettingsURL(bundleIdentifier: Bundle.main.bundleIdentifier)
        if !NSWorkspace.shared.open(appURL) {
            _ = NSWorkspace.shared.open(TrackNotifier.notificationSettingsURL(bundleIdentifier: nil))
        }
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(StreamQuality.allCases) { quality in
                Button {
                    guard appState.selectedQuality != quality else { return }
                    appState.selectedQuality = quality
                    Prefs.set(quality.rawValue, for: .quality)
                    appState.restartStreamForQualityChange()
                } label: {
                    // Every item reserves the checkmark slot so names align
                    let check = Text("\(Image(systemName: "checkmark"))")
                        .foregroundStyle(quality == appState.selectedQuality ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
                    Text("\(check) \(quality.displayName)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(appState.selectedQuality.displayName)
                    .font(.system(size: 11))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .cursor(.pointingHand)
    }

    /// Glyph for the preview card: honors the chip, shows the real state when
    /// a station is loaded, and demonstrates "playing" as the idle placeholder.
    private var previewGlyph: MenuBarLabelRenderer.PlaybackGlyph {
        guard appState.menuBarShowPlayState else { return .none }
        if appState.audioPlayer.currentChannel != nil {
            return MenuBarLabelRenderer.glyph(for: appState.audioPlayer)
        }
        return .playing
    }

    private var menuBarMetadataGrid: some View {
        let order = displayedMenuBarOrder
        return HStack(spacing: 8) {
            VStack(spacing: 4) {
                menuBarComponentChip(order[0], in: 0)
                menuBarComponentChip(order[2], in: 2)
            }
            VStack(spacing: 4) {
                menuBarComponentChip(order[1], in: 1)
                menuBarComponentChip(order[3], in: 3)
            }
        }
        .contextMenu {
            Button("Restore Default Order") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    clearMenuBarDrag()
                    appState.restoreDefaultMenuBarComponentOrder()
                }
            }
            .disabled(appState.menuBarComponentOrder == MenuBarComponent.defaultOrder)
        }
    }

    private var displayedMenuBarOrder: [MenuBarComponent] {
        MenuBarComponent.normalizedOrder(
            provisionalMenuBarOrder ?? appState.menuBarComponentOrder
        )
    }

    private var displayedMenuBarPreviewLines: (line1: String?, line2: String?) {
        appState.menuBarPreviewLines(order: displayedMenuBarOrder)
    }

    private func menuBarComponentChip(_ component: MenuBarComponent, in slot: Int) -> some View {
        ToggleChip(
            title: component.settingsTitle,
            width: component == .station ? 60 : 46,
            isOn: menuBarVisibilityBinding(for: component)
        )
        .onDrag {
            let order = MenuBarComponent.normalizedOrder(appState.menuBarComponentOrder)
            draggedMenuBarComponent = component
            dragOriginMenuBarOrder = order
            provisionalMenuBarOrder = order
            menuBarDropTargetSlot = nil
            return NSItemProvider(object: component.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: MenuBarComponentDropDelegate(
            targetSlot: slot,
            appState: appState,
            draggedComponent: $draggedMenuBarComponent,
            originOrder: $dragOriginMenuBarOrder,
            provisionalOrder: $provisionalMenuBarOrder,
            dropTargetSlot: $menuBarDropTargetSlot
        ))
        .overlay {
            Capsule()
                .strokeBorder(
                    Color.accentColor.opacity(menuBarDropTargetSlot == slot ? 0.8 : 0),
                    lineWidth: 2
                )
        }
        .id(slot)
        .help("Click to show or hide; drag to reorder; right-click to restore the default order.")
    }

    private func clearMenuBarDrag() {
        draggedMenuBarComponent = nil
        dragOriginMenuBarOrder = nil
        provisionalMenuBarOrder = nil
        menuBarDropTargetSlot = nil
    }

    private func menuBarVisibilityBinding(for component: MenuBarComponent) -> Binding<Bool> {
        switch component {
        case .station:
            Binding(get: { appState.menuBarShowStation }, set: { appState.menuBarShowStation = $0 })
        case .site:
            Binding(get: { appState.menuBarShowSite }, set: { appState.menuBarShowSite = $0 })
        case .artist:
            Binding(get: { appState.menuBarShowArtist }, set: { appState.menuBarShowArtist = $0 })
        case .song:
            Binding(get: { appState.menuBarShowSong }, set: { appState.menuBarShowSong = $0 })
        }
    }

    /// One line of the shortcuts helper: keycaps left, action label right.
    private func shortcutRow(label: String, @ViewBuilder keys: () -> some View) -> some View {
        HStack(spacing: 3) {
            keys()
            Spacer(minLength: 8)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func keySeparator(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
    }

    /// Caption on the left, control flush right, uniform height and padding.
    private func settingsRow(_ caption: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            control()
        }
        .frame(minHeight: 22)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

private struct MenuBarComponentDropDelegate: DropDelegate {
    let targetSlot: Int
    let appState: AppState
    @Binding var draggedComponent: MenuBarComponent?
    @Binding var originOrder: [MenuBarComponent]?
    @Binding var provisionalOrder: [MenuBarComponent]?
    @Binding var dropTargetSlot: Int?

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let draggedComponent, let originOrder,
                  let sourceSlot = originOrder.firstIndex(of: draggedComponent),
                  originOrder.indices.contains(targetSlot)
            else { return }

            var preview = originOrder
            if sourceSlot != targetSlot {
                preview.swapAt(sourceSlot, targetSlot)
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                provisionalOrder = preview
                dropTargetSlot = sourceSlot == targetSlot ? nil : targetSlot
            }
        }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            guard dropTargetSlot == targetSlot else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                provisionalOrder = originOrder
                dropTargetSlot = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            if let committedOrder = provisionalOrder ?? originOrder {
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.menuBarComponentOrder = MenuBarComponent.normalizedOrder(committedOrder)
                }
            }
            draggedComponent = nil
            originOrder = nil
            provisionalOrder = nil
            dropTargetSlot = nil
        }
        return true
    }
}

// MARK: - Key Cap

/// A single keyboard key rendered as a small rounded keycap.
private struct KeyCap: View {
    var label: String?
    var systemImage: String?

    init(_ label: String) { self.label = label }
    init(systemImage: String) { self.systemImage = systemImage }

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 7, weight: .semibold))
            } else {
                Text(label ?? "")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(.secondary)
        .frame(minWidth: 12, minHeight: 11)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3.5)
                .fill(.quaternary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Toggle Chip

private struct ToggleChip: View {
    let title: String
    var systemImage: String? = nil
    var width: CGFloat? = nil
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: isOn ? .semibold : .regular))
                } else {
                    Text(title)
                        .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                }
            }
                .frame(width: width)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .padding(.horizontal, width == nil ? 8 : 0)
                .padding(.vertical, 3)
                .background(
                    isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.accentColor.opacity(isHovered ? 0.45 : 0), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .cursor(.pointingHand)
        .help(isOn ? "Hide \(title.lowercased()) in the menu bar" : "Show \(title.lowercased()) in the menu bar")
    }
}
