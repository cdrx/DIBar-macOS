import Foundation

enum MenuBarComponent: String, CaseIterable, Identifiable {
    case station
    case site
    case artist
    case song

    static let defaultOrder: [Self] = [.station, .site, .artist, .song]

    var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .station: return "Channel"
        case .site: return "Site"
        case .artist: return "Artist"
        case .song: return "Song"
        }
    }

    static func decodedOrder(_ raw: String?) -> [Self] {
        var seen = Set<Self>()
        var order = (raw ?? "")
            .split(separator: ",")
            .compactMap { Self(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        order.append(contentsOf: defaultOrder.filter { seen.insert($0).inserted })
        return order
    }

    static func normalizedOrder(_ order: [Self]) -> [Self] {
        decodedOrder(order.map(\.rawValue).joined(separator: ","))
    }

    static func storedOrder() -> [Self] {
        decodedOrder(Prefs.string(.menuBarComponentOrder))
    }

    static func encodedOrder(_ order: [Self]) -> String {
        normalizedOrder(order).map(\.rawValue).joined(separator: ",")
    }

    static func swapping(_ dragged: Self, with target: Self, in order: [Self]) -> [Self] {
        var result = normalizedOrder(order)
        guard let draggedIndex = result.firstIndex(of: dragged),
              let targetIndex = result.firstIndex(of: target),
              draggedIndex != targetIndex
        else { return result }
        result.swapAt(draggedIndex, targetIndex)
        return result
    }
}

/// Menu-bar label composition: which components show is governed by the
/// toggles stored on AppState; this file owns how they join and truncate.
extension AppState {
    var menuBarLine1: String? {
        guard audioPlayer.isPlaying else { return nil }
        return composedMenuBarLines(
            station: audioPlayer.currentChannel?.name,
            site: audioPlayer.currentNetwork?.displayName,
            artist: audioPlayer.currentTrack?.artist,
            song: audioPlayer.currentTrack?.title
        ).line1
    }

    var menuBarLine2: String? {
        guard audioPlayer.isPlaying else { return nil }
        return composedMenuBarLines(
            station: audioPlayer.currentChannel?.name,
            site: audioPlayer.currentNetwork?.displayName,
            artist: audioPlayer.currentTrack?.artist,
            song: audioPlayer.currentTrack?.title
        ).line2
    }

    /// Preview variants for the settings area: live values while playing,
    /// placeholder examples otherwise. Same joining logic as the real label.
    var menuBarPreviewLine1: String? {
        previewMenuBarLines.line1
    }

    var menuBarPreviewLine2: String? {
        previewMenuBarLines.line2
    }

    private var previewMenuBarLines: (line1: String?, line2: String?) {
        menuBarPreviewLines(order: menuBarComponentOrder)
    }

    func menuBarPreviewLines(order: [MenuBarComponent]) -> (line1: String?, line2: String?) {
        Self.composeMenuBarLines(
            order: order,
            station: audioPlayer.isPlaying ? audioPlayer.currentChannel?.name : "Ambient",
            site: audioPlayer.isPlaying ? audioPlayer.currentNetwork?.displayName : "Jazz Radio",
            artist: audioPlayer.isPlaying ? audioPlayer.currentTrack?.artist : "Metallica",
            song: audioPlayer.isPlaying ? audioPlayer.currentTrack?.title : "So What",
            showStation: menuBarShowStation,
            showSite: menuBarShowSite,
            showArtist: menuBarShowArtist,
            showSong: menuBarShowSong
        )
    }

    private func composedMenuBarLines(
        station: String?,
        site: String?,
        artist: String?,
        song: String?
    ) -> (line1: String?, line2: String?) {
        Self.composeMenuBarLines(
            order: menuBarComponentOrder,
            station: station,
            site: site,
            artist: artist,
            song: song,
            showStation: menuBarShowStation,
            showSite: menuBarShowSite,
            showArtist: menuBarShowArtist,
            showSong: menuBarShowSong
        )
    }

    func swapMenuBarComponent(_ dragged: MenuBarComponent, with target: MenuBarComponent) {
        menuBarComponentOrder = MenuBarComponent.swapping(
            dragged,
            with: target,
            in: menuBarComponentOrder
        )
    }

    func restoreDefaultMenuBarComponentOrder() {
        menuBarComponentOrder = MenuBarComponent.defaultOrder
    }

    static func composeMenuBarLines(
        order: [MenuBarComponent],
        station: String?,
        site: String?,
        artist: String?,
        song: String?,
        showStation: Bool,
        showSite: Bool,
        showArtist: Bool,
        showSong: Bool
    ) -> (line1: String?, line2: String?) {
        let values: [MenuBarComponent: String?] = [
            .station: showStation ? station : nil,
            .site: showSite ? site : nil,
            .artist: showArtist ? artist : nil,
            .song: showSong && song != "Loading..." ? song : nil,
        ]
        let normalized = MenuBarComponent.normalizedOrder(order)

        func compose(_ components: ArraySlice<MenuBarComponent>) -> String? {
            let parts = components.compactMap { component -> (MenuBarComponent, String)? in
                guard let value = values[component] ?? nil, !value.isEmpty else { return nil }
                return (component, value)
            }
            guard !parts.isEmpty else { return nil }
            let isArtistSongPair = parts.count == 2
                && Set(parts.map(\.0)) == Set([MenuBarComponent.artist, .song])
            let separator = isArtistSongPair ? " – " : " · "
            return truncateForMenuBar(parts.map(\.1).joined(separator: separator))
        }

        return (
            compose(normalized.prefix(2)),
            compose(normalized.suffix(2))
        )
    }

    // Kept as a focused compatibility helper for existing callers and tests.
    static func composeMenuBarLine1(
        channel: String?,
        site: String?,
        showChannel: Bool,
        showSite: Bool
    ) -> String? {
        composeMenuBarLines(
            order: MenuBarComponent.defaultOrder,
            station: channel,
            site: site,
            artist: nil,
            song: nil,
            showStation: showChannel,
            showSite: showSite,
            showArtist: false,
            showSong: false
        ).line1
    }

    private static func truncateForMenuBar(_ text: String) -> String {
        text.count > 35 ? String(text.prefix(34)) + "…" : text
    }
}
