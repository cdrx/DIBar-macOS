import Foundation

enum MenuBarComponent: String, CaseIterable, Identifiable {
    case station
    case site
    case artist
    case song

    static let defaultOrder: [Self] = [.station, .site, .artist, .song]

    var id: String { rawValue }

    /// How the component is named in tooltips and to VoiceOver. "Song title"
    /// rather than "Song", which reads as the whole track.
    var settingsTitle: String {
        switch self {
        case .station: return "Channel"
        case .site: return "Site"
        case .artist: return "Artist"
        case .song: return "Song title"
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

    /// Stand-in shown before anything is playing, and in the settings
    /// simulation for a component whose live value is missing.
    var placeholderValue: String {
        switch self {
        case .station: return "Ambient"
        case .site: return "Jazz Radio"
        case .artist: return "Metallica"
        case .song: return "So What"
        }
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

/// One visible component of a menu-bar line, carrying the separator that
/// precedes it. Joining `separatorBefore + text` over a line reproduces the
/// composed line exactly — that identity is what keeps the settings
/// simulation and the rendered status item from drifting apart.
struct MenuBarPart: Equatable {
    let component: MenuBarComponent
    let text: String
    let separatorBefore: String
}

/// One slot of the settings simulation. Unlike `MenuBarPart` this includes
/// hidden components: they keep their place so they can be brought back.
struct MenuBarSlot: Equatable, Identifiable {
    let component: MenuBarComponent
    let text: String
    let isVisible: Bool
    let separatorBefore: String?

    var id: MenuBarComponent { component }
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

    /// Values the settings area composes from: live while playing, worked
    /// examples otherwise, so the simulation is never blank.
    private var menuBarPreviewValues: (station: String?, site: String?, artist: String?, song: String?) {
        (
            audioPlayer.isPlaying ? audioPlayer.currentChannel?.name : MenuBarComponent.station.placeholderValue,
            audioPlayer.isPlaying ? audioPlayer.currentNetwork?.displayName : MenuBarComponent.site.placeholderValue,
            audioPlayer.isPlaying ? audioPlayer.currentTrack?.artist : MenuBarComponent.artist.placeholderValue,
            audioPlayer.isPlaying ? audioPlayer.currentTrack?.title : MenuBarComponent.song.placeholderValue
        )
    }

    /// The settings simulation: both slots of both lines, visible components
    /// carrying the exact text the status item would draw (same separators,
    /// same truncation) and hidden ones carrying their value so they can be
    /// shown struck through rather than vanishing.
    func menuBarSimulationLines(
        order: [MenuBarComponent]
    ) -> (line1: [MenuBarSlot], line2: [MenuBarSlot]) {
        let normalized = MenuBarComponent.normalizedOrder(order)
        let values = menuBarPreviewValues
        let parts = Self.composeMenuBarParts(
            order: normalized,
            station: values.station,
            site: values.site,
            artist: values.artist,
            song: values.song,
            showStation: menuBarShowStation,
            showSite: menuBarShowSite,
            showArtist: menuBarShowArtist,
            showSong: menuBarShowSong
        )

        func slots(_ components: ArraySlice<MenuBarComponent>, _ parts: [MenuBarPart]) -> [MenuBarSlot] {
            // A hidden component contributes no separator to the real label, so
            // take the separator from the slot pair instead of the visible one.
            let separator = Self.menuBarSeparator(for: Array(components))
            let visible = Dictionary(uniqueKeysWithValues: parts.map { ($0.component, $0.text) })
            return components.enumerated().map { offset, component in
                MenuBarSlot(
                    component: component,
                    text: visible[component] ?? menuBarSimulationValue(for: component),
                    isVisible: visible[component] != nil,
                    separatorBefore: offset == 0 ? nil : separator
                )
            }
        }

        return (
            slots(normalized.prefix(2), parts.line1),
            slots(normalized.suffix(2), parts.line2)
        )
    }

    /// Text for a slot the toggles have hidden — never empty, so every slot
    /// stays visible and grabbable.
    private func menuBarSimulationValue(for component: MenuBarComponent) -> String {
        let values = menuBarPreviewValues
        let live: String?
        switch component {
        case .station: live = values.station
        case .site: live = values.site
        case .artist: live = values.artist
        case .song: live = values.song == "Loading..." ? nil : values.song
        }
        if let live, !live.isEmpty { return live }
        return component.placeholderValue
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

    /// " – " reads as a title dash between an artist and a song; everything
    /// else is a list, so it gets " · ". The rule is a property of the pair,
    /// not of either component on its own.
    static func menuBarSeparator(for components: [MenuBarComponent]) -> String {
        components.count == 2 && Set(components) == Set([MenuBarComponent.artist, .song])
            ? " – "
            : " · "
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
        let parts = composeMenuBarParts(
            order: order,
            station: station,
            site: site,
            artist: artist,
            song: song,
            showStation: showStation,
            showSite: showSite,
            showArtist: showArtist,
            showSong: showSong
        )
        func join(_ parts: [MenuBarPart]) -> String? {
            guard !parts.isEmpty else { return nil }
            return parts.map { $0.separatorBefore + $0.text }.joined()
        }
        return (join(parts.line1), join(parts.line2))
    }

    /// The same composition the status item draws, kept as addressable pieces
    /// so the settings simulation can make each one separately draggable.
    static func composeMenuBarParts(
        order: [MenuBarComponent],
        station: String?,
        site: String?,
        artist: String?,
        song: String?,
        showStation: Bool,
        showSite: Bool,
        showArtist: Bool,
        showSong: Bool
    ) -> (line1: [MenuBarPart], line2: [MenuBarPart]) {
        let values: [MenuBarComponent: String?] = [
            .station: showStation ? station : nil,
            .site: showSite ? site : nil,
            .artist: showArtist ? artist : nil,
            .song: showSong && song != "Loading..." ? song : nil,
        ]
        let normalized = MenuBarComponent.normalizedOrder(order)

        func compose(_ components: ArraySlice<MenuBarComponent>) -> [MenuBarPart] {
            let visible = components.compactMap { component -> (MenuBarComponent, String)? in
                guard let value = values[component] ?? nil, !value.isEmpty else { return nil }
                return (component, value)
            }
            guard !visible.isEmpty else { return [] }
            let separator = menuBarSeparator(for: visible.map(\.0))

            // Join first, truncate the whole line, then map the surviving
            // characters back onto the parts. Deriving truncation per part
            // would quietly diverge from what the renderer draws.
            var joined = ""
            var spans: [Range<Int>] = []
            for (offset, part) in visible.enumerated() {
                if offset > 0 { joined += separator }
                let start = joined.count
                joined += part.1
                spans.append(start..<joined.count)
            }
            let truncated = truncateForMenuBar(joined)
            let characters = Array(truncated)

            var parts: [MenuBarPart] = []
            for (offset, part) in visible.enumerated() {
                let span = spans[offset]
                guard span.lowerBound < characters.count else { break }
                let text = String(characters[span.lowerBound..<min(span.upperBound, characters.count)])
                guard !text.isEmpty else { break }
                parts.append(MenuBarPart(
                    component: part.0,
                    text: text,
                    separatorBefore: offset == 0 ? "" : separator
                ))
            }

            // The cut can land inside a separator, orphaning the ellipsis and
            // separator fragment. Hand them to the last surviving part so
            // rejoining still reproduces `truncated` character for character.
            let assembled = parts.map { $0.separatorBefore + $0.text }.joined()
            if assembled != truncated, truncated.hasPrefix(assembled), let last = parts.last {
                parts[parts.count - 1] = MenuBarPart(
                    component: last.component,
                    text: last.text + truncated.dropFirst(assembled.count),
                    separatorBefore: last.separatorBefore
                )
            }
            return parts
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
