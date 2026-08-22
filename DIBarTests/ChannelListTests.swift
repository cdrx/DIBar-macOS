import XCTest
@testable import DIBar

// AppState is @MainActor, so its statics are too.
@MainActor
final class ChannelListTests: XCTestCase {
    private func channel(id: Int, name: String) -> Channel {
        Channel(id: id, key: name.lowercased(), name: name, description: nil)
    }

    // MARK: - Network ordering

    func testNetworksDeclaredAlphabeticallyByDisplayName() {
        let names = Network.allCases.map(\.displayName)
        XCTAssertEqual(names, names.sorted())
    }

    // MARK: - NetworkChannel

    func testNetworkChannelIdMatchesRecentStationIdFormat() {
        let item = NetworkChannel(network: .jazzradio, channel: channel(id: 42, name: "Smooth"))
        let recent = RecentStation(network: .jazzradio, channelId: 42, channelKey: "smooth", name: "Smooth")
        XCTAssertEqual(item.id, recent.id)
    }

    func testNetworkChannelTooltipIncludesSiteAndTrimmedDescription() {
        let item = NetworkChannel(
            network: .jazzradio,
            channel: Channel(
                id: 42,
                key: "smooth",
                name: "Smooth Jazz",
                description: "  Relaxed contemporary jazz.\n"
            )
        )
        XCTAssertEqual(item.tooltipText, """
            Smooth Jazz · Jazz Radio

            Relaxed contemporary jazz.
            """)
    }

    // MARK: - Merged channel list

    private var cache: [Network: NetworkData] {
        var di = NetworkData()
        di.channels = [channel(id: 1, name: "Chillout"), channel(id: 2, name: "Ambient")]
        var zen = NetworkData()
        // Same channel id and name on another network — must stay distinct
        zen.channels = [channel(id: 1, name: "Chillout"), channel(id: 3, name: "Sleep")]
        return [.di: di, .zenradio: zen]
    }

    func testMergeAcrossNetworksKeepsCollidingIdsDistinct() {
        let merged = AppState.filteredChannels(cache: cache, networks: [.di, .zenradio], searchText: "")
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(Set(merged.map(\.id)).count, 4)
    }

    func testMergeSortsByNameWithNetworkTieBreak() {
        let merged = AppState.filteredChannels(cache: cache, networks: [.di, .zenradio], searchText: "")
        XCTAssertEqual(merged.map(\.channel.name), ["Ambient", "Chillout", "Chillout", "Sleep"])
        // DI.FM < Zen Radio for the two same-named Chillouts
        XCTAssertEqual(merged[1].network, .di)
        XCTAssertEqual(merged[2].network, .zenradio)
    }

    func testSearchFiltersMergedList() {
        let merged = AppState.filteredChannels(cache: cache, networks: [.di, .zenradio], searchText: "chill")
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.allSatisfy { $0.channel.name == "Chillout" })
    }

    // MARK: - Favorite toggling (id-based overload)

    // A fresh AppState has no apiKey, so toggles take the offline path and
    // persist local overrides — snapshot and restore those prefs.
    func testToggleFavoriteByIdMatchesChannelOverload() {
        let savedAdded = Prefs.intSet(.localFavAdded, network: .zenradio)
        let savedRemoved = Prefs.intSet(.localFavRemoved, network: .zenradio)
        let savedOrder = Prefs.intArray(.favoriteOrder, network: .zenradio)
        defer {
            Prefs.set(savedAdded, for: .localFavAdded, network: .zenradio)
            Prefs.set(savedRemoved, for: .localFavRemoved, network: .zenradio)
            if let savedOrder {
                Prefs.set(savedOrder, for: .favoriteOrder, network: .zenradio)
            } else {
                Prefs.remove(.favoriteOrder, network: .zenradio)
            }
        }

        let state = AppState()
        let ch = channel(id: 999_901, name: "Test Station")

        state.toggleFavorite(channelId: ch.id, name: ch.name, on: .zenradio)
        XCTAssertTrue(state.favoriteChannelIds(on: .zenradio).contains(ch.id))

        // The Channel overload must undo the id-based toggle symmetrically
        state.toggleFavorite(ch, on: .zenradio)
        XCTAssertFalse(state.favoriteChannelIds(on: .zenradio).contains(ch.id))
        XCTAssertTrue(state.sessionUnfavorited[.zenradio]?.contains(ch.id) ?? false)
    }

    func testFavoriteChannelsFollowPerNetworkManualOrder() {
        let state = AppState()
        state.selectedNetwork = .di
        var data = NetworkData()
        data.channels = [
            channel(id: 1, name: "Alpha"),
            channel(id: 2, name: "Beta"),
            channel(id: 3, name: "Gamma"),
        ]
        data.favoriteChannelIds = [1, 2, 3]
        data.favoriteChannelOrder = [3, 1, 2]
        state.networkDataCache[.di] = data

        XCTAssertEqual(state.favoriteChannels.map(\.channel.id), [3, 1, 2])
        XCTAssertEqual(state.orderedFavoriteChannels(on: .di).map(\.id), [3, 1, 2])
    }

    func testMoveFavoritePersistsTheNewOrder() {
        let savedOrder = Prefs.intArray(.favoriteOrder, network: .di)
        defer {
            if let savedOrder {
                Prefs.set(savedOrder, for: .favoriteOrder, network: .di)
            } else {
                Prefs.remove(.favoriteOrder, network: .di)
            }
        }

        let state = AppState()
        state.selectedNetwork = .di
        var data = NetworkData()
        data.channels = [
            channel(id: 1, name: "Alpha"),
            channel(id: 2, name: "Beta"),
            channel(id: 3, name: "Gamma"),
        ]
        data.favoriteChannelIds = [1, 2, 3]
        data.favoriteChannelOrder = [1, 2, 3]
        state.networkDataCache[.di] = data

        let items = state.favoriteChannels
        state.moveFavorite(items[0], toSlotOf: items[2])

        XCTAssertEqual(state.favoriteChannels.map(\.channel.id), [2, 3, 1])
        XCTAssertEqual(Prefs.intArray(.favoriteOrder, network: .di), [2, 3, 1])
    }

    func testRefavoritingASessionGhostRestoresItsSlot() {
        let savedAdded = Prefs.intSet(.localFavAdded, network: .di)
        let savedRemoved = Prefs.intSet(.localFavRemoved, network: .di)
        let savedOrder = Prefs.intArray(.favoriteOrder, network: .di)
        defer {
            Prefs.set(savedAdded, for: .localFavAdded, network: .di)
            Prefs.set(savedRemoved, for: .localFavRemoved, network: .di)
            if let savedOrder {
                Prefs.set(savedOrder, for: .favoriteOrder, network: .di)
            } else {
                Prefs.remove(.favoriteOrder, network: .di)
            }
        }

        let state = AppState()
        var data = NetworkData()
        data.channels = [
            channel(id: 1, name: "Alpha"),
            channel(id: 2, name: "Beta"),
            channel(id: 3, name: "Gamma"),
        ]
        data.favoriteChannelIds = [1, 2, 3]
        data.favoriteChannelOrder = [1, 2, 3]
        state.networkDataCache[.di] = data

        state.toggleFavorite(channelId: 2, name: "Beta", on: .di)
        state.toggleFavorite(channelId: 2, name: "Beta", on: .di)

        XCTAssertEqual(state.favoriteChannels.map(\.channel.id), [1, 2, 3])
    }

    func testSingleNetworkMatchesOldBehavior() {
        let merged = AppState.filteredChannels(cache: cache, networks: [.di], searchText: "")
        XCTAssertEqual(merged.map(\.channel.name), ["Ambient", "Chillout"])
        XCTAssertTrue(merged.allSatisfy { $0.network == .di })
    }

    // MARK: - Playing station reveal

    func testPlayingRevealSwitchesFromWrongConcreteNetwork() {
        let request = PlayingRevealRequest.resolve(
            channelID: 42,
            playingNetwork: .jazzradio,
            selectedNetwork: .di,
            allNetworksSelected: false
        )

        XCTAssertEqual(request?.network, .jazzradio)
        XCTAssertEqual(request?.itemID, "jazzradio-42")
        XCTAssertEqual(request?.requiresNetworkSwitch, true)
    }

    func testPlayingRevealStaysOnMatchingConcreteNetwork() {
        let request = PlayingRevealRequest.resolve(
            channelID: 42,
            playingNetwork: .jazzradio,
            selectedNetwork: .jazzradio,
            allNetworksSelected: false
        )

        XCTAssertEqual(request?.requiresNetworkSwitch, false)
    }

    func testPlayingRevealKeepsAllSitesSelected() {
        let request = PlayingRevealRequest.resolve(
            channelID: 42,
            playingNetwork: .jazzradio,
            selectedNetwork: .di,
            allNetworksSelected: true
        )

        XCTAssertEqual(request?.requiresNetworkSwitch, false)
    }

    func testPlayingRevealNeedsAChannelAndNetwork() {
        XCTAssertNil(PlayingRevealRequest.resolve(
            channelID: nil,
            playingNetwork: .jazzradio,
            selectedNetwork: .di,
            allNetworksSelected: false
        ))
        XCTAssertNil(PlayingRevealRequest.resolve(
            channelID: 42,
            playingNetwork: nil,
            selectedNetwork: .di,
            allNetworksSelected: false
        ))
    }
}
