import Foundation
import os

private let log = Logger(subsystem: "com.dibar", category: "AppState")

/// Favorites: server sync (bulk-replace endpoint) with local overrides that
/// persist per network when sync isn't available.
extension AppState {
    func favoriteChannelIds(on network: Network) -> Set<Int> {
        networkDataCache[network]?.favoriteChannelIds ?? []
    }

    func orderedFavoriteChannels(on network: Network) -> [Channel] {
        guard let data = networkDataCache[network] else { return [] }
        let order = completedFavoriteOrder(
            data.favoriteChannelOrder,
            ids: data.favoriteChannelIds,
            channels: data.channels
        )
        let channelsByID = Dictionary(uniqueKeysWithValues: data.channels.map { ($0.id, $0) })
        return order.compactMap { channelsByID[$0] }
    }

    var favoritesLoadFailed: Bool {
        displayedNetworks.contains { networkDataCache[$0]?.favoritesLoadFailed ?? false }
    }

    var favoriteChannels: [NetworkChannel] {
        displayedNetworks.flatMap { network -> [NetworkChannel] in
            guard let data = networkDataCache[network] else { return [] }
            let visible = favoriteChannelIds(on: network).union(sessionUnfavorited[network] ?? [])
            let order = completedFavoriteOrder(
                data.favoriteChannelOrder,
                ids: visible,
                channels: data.channels
            )
            let channelsByID = Dictionary(uniqueKeysWithValues: data.channels.map { ($0.id, $0) })
            return order.compactMap { id in
                channelsByID[id].map { NetworkChannel(network: network, channel: $0) }
            }
        }
    }

    func loadFavorites(for network: Network? = nil) async {
        let target = network ?? selectedNetwork
        var data = networkDataCache[target] ?? NetworkData()
        var shouldSyncLocalOrder = false
        guard let ak = apiKey else {
            log.warning("loadFavorites(\(target.rawValue)): SKIPPED — no apiKey")
            data.favoritesLoadFailed = true
            networkDataCache[target] = data
            return
        }
        do {
            let serverOrder = try await DIClient.fetchFavoritesOrdered(apiKey: ak, network: target)
            let ids = applyLocalFavoriteOverrides(to: Set(serverOrder), network: target)
            let localOrder = Prefs.intArray(.favoriteOrder, network: target)
            let preferred = (localOrder ?? serverOrder) + serverOrder.filter {
                !(localOrder ?? []).contains($0)
            }
            data.favoriteChannelIds = ids
            data.favoriteChannelOrder = completedFavoriteOrder(
                preferred,
                ids: ids,
                channels: data.channels
            )
            data.favoritesLoadFailed = false
            shouldSyncLocalOrder = localOrder != nil
            log.info("loadFavorites(\(target.rawValue)): \(ids.count) favorites")
        } catch {
            data.favoritesLoadFailed = true
            log.error("loadFavorites(\(target.rawValue)) error: \(error.localizedDescription)")
        }
        networkDataCache[target] = data
        if shouldSyncLocalOrder {
            scheduleFavoriteOrderSync(for: target)
        }
    }

    /// Reloads favorites for exactly the displayed networks whose last load
    /// failed (the Retry row's action; a no-op for the rest).
    func retryFailedFavorites() async {
        for network in displayedNetworks where networkDataCache[network]?.favoritesLoadFailed ?? false {
            await loadFavorites(for: network)
        }
    }

    func toggleFavorite(_ channel: Channel, on network: Network? = nil) {
        toggleFavorite(channelId: channel.id, name: channel.name, on: network)
    }

    /// Id-based variant for rows that don't hold a full Channel (recents).
    func toggleFavorite(channelId: Int, name: String, on network: Network? = nil) {
        let network = network ?? selectedNetwork
        var data = networkDataCache[network] ?? NetworkData()
        let adding = !data.favoriteChannelIds.contains(channelId)
        let visibleBeforeChange = data.favoriteChannelIds
            .union(sessionUnfavorited[network] ?? [])
        data.favoriteChannelOrder = completedFavoriteOrder(
            data.favoriteChannelOrder,
            ids: visibleBeforeChange,
            channels: data.channels
        )
        if adding {
            data.favoriteChannelIds.insert(channelId)
            sessionUnfavorited[network]?.remove(channelId)
            if !data.favoriteChannelOrder.contains(channelId) {
                data.favoriteChannelOrder.append(channelId)
            }
        } else {
            data.favoriteChannelIds.remove(channelId)
            sessionUnfavorited[network, default: []].insert(channelId)
        }
        networkDataCache[network] = data
        log.info("toggleFavorite(\(network.rawValue)): \(adding ? "add" : "remove") \(name)")
        recordLocalFavoriteOverride(channelId: channelId, adding: adding, network: network)
        persistFavoriteOrder(for: network)
    }

    /// Reorder favorites within one site. All Sites displays each site's
    /// independently ordered block because the service has no cross-site list.
    func moveFavorite(_ item: NetworkChannel, toSlotOf target: NetworkChannel) {
        guard item.network == target.network, item.id != target.id,
              var data = networkDataCache[item.network]
        else { return }
        let visible = data.favoriteChannelIds.union(sessionUnfavorited[item.network] ?? [])
        var order = completedFavoriteOrder(
            data.favoriteChannelOrder,
            ids: visible,
            channels: data.channels
        )
        guard let from = order.firstIndex(of: item.channel.id),
              let to = order.firstIndex(of: target.channel.id)
        else { return }
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        data.favoriteChannelOrder = order
        networkDataCache[item.network] = data
        persistFavoriteOrder(for: item.network)
    }

    func sortFavoritesByName() {
        for network in displayedNetworks {
            guard var data = networkDataCache[network] else { continue }
            let visible = data.favoriteChannelIds.union(sessionUnfavorited[network] ?? [])
            data.favoriteChannelOrder = completedFavoriteOrder(
                [],
                ids: visible,
                channels: data.channels
            )
            networkDataCache[network] = data
            persistFavoriteOrder(for: network)
        }
        log.info("sortFavoritesByName")
    }

    /// Local additions/removals that couldn't be synced, persisted per network
    /// and re-applied on top of whatever the server returns.
    private func localFavoriteOverrides(for network: Network) -> (added: Set<Int>, removed: Set<Int>) {
        (Prefs.intSet(.localFavAdded, network: network),
         Prefs.intSet(.localFavRemoved, network: network))
    }

    private func recordLocalFavoriteOverride(channelId: Int, adding: Bool, network: Network) {
        var (added, removed) = localFavoriteOverrides(for: network)
        if adding {
            added.insert(channelId)
            removed.remove(channelId)
        } else {
            removed.insert(channelId)
            added.remove(channelId)
        }
        Prefs.set(added, for: .localFavAdded, network: network)
        Prefs.set(removed, for: .localFavRemoved, network: network)
    }

    private func clearLocalFavoriteOverrides(for network: Network) {
        Prefs.set(nil, for: .localFavAdded, network: network)
        Prefs.set(nil, for: .localFavRemoved, network: network)
    }

    private func applyLocalFavoriteOverrides(to ids: Set<Int>, network: Network) -> Set<Int> {
        let (added, removed) = localFavoriteOverrides(for: network)
        return ids.union(added).subtracting(removed)
    }

    /// Preserve a preferred sequence, then append resolvable missing channels
    /// alphabetically. Unknown ids remain stable at the end until a catalog
    /// refresh can resolve them.
    private func completedFavoriteOrder(
        _ preferred: [Int],
        ids: Set<Int>,
        channels: [Channel]
    ) -> [Int] {
        var seen: Set<Int> = []
        var result = preferred.filter { ids.contains($0) && seen.insert($0).inserted }

        let missingChannels = channels
            .filter { ids.contains($0.id) && !seen.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        result.append(contentsOf: missingChannels.map(\.id))
        seen.formUnion(missingChannels.map(\.id))

        result.append(contentsOf: ids.filter { !seen.contains($0) }.sorted())
        return result
    }

    /// Persist immediately so a drag ending outside a row cannot lose its
    /// order, then debounce the service's bulk-replace endpoint.
    private func persistFavoriteOrder(for network: Network) {
        guard let data = networkDataCache[network] else { return }
        let activeOrder = completedFavoriteOrder(
            data.favoriteChannelOrder,
            ids: data.favoriteChannelIds,
            channels: data.channels
        )
        let channels = data.channels
        Prefs.set(activeOrder, for: .favoriteOrder, network: network)
        scheduleFavoriteOrderSync(for: network)
    }

    private func scheduleFavoriteOrderSync(for network: Network) {
        guard let data = networkDataCache[network] else { return }
        let activeOrder = completedFavoriteOrder(
            data.favoriteChannelOrder,
            ids: data.favoriteChannelIds,
            channels: data.channels
        )
        Prefs.set(activeOrder, for: .favoriteOrder, network: network)

        guard favoritesSyncAvailable, let apiKey, let memberId else { return }
        favoriteOrderSyncTasks[network]?.cancel()
        favoriteOrderSyncTasks[network] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                guard let self else { return }
                // The endpoint replaces the entire list. Re-read immediately
                // before writing so favorites changed on another device are
                // merged rather than silently erased.
                let serverOrder = try await DIClient.fetchFavoritesOrdered(
                    apiKey: apiKey,
                    network: network
                )
                try Task.checkCancellation()
                let (added, removed) = self.localFavoriteOverrides(for: network)
                let finalIDs = Set(serverOrder).union(added).subtracting(removed)
                let preferred = activeOrder + serverOrder.filter { !activeOrder.contains($0) }
                let finalOrder = self.completedFavoriteOrder(
                    preferred,
                    ids: finalIDs,
                    channels: channels
                )
                try await DIClient.setFavorites(
                    channelIds: finalOrder,
                    memberId: memberId,
                    apiKey: apiKey,
                    network: network
                )
                try Task.checkCancellation()
                guard Prefs.intArray(.favoriteOrder, network: network) == activeOrder else { return }
                if var latest = self.networkDataCache[network] {
                    latest.favoriteChannelIds = finalIDs
                    latest.favoriteChannelOrder = finalOrder
                    self.networkDataCache[network] = latest
                }
                Prefs.remove(.favoriteOrder, network: network)
                self.clearLocalFavoriteOverrides(for: network)
            } catch is CancellationError {
                return
            } catch {
                if case DIClientError.httpError(let code) = error, code == 404 || code == 405 {
                    self?.favoritesSyncAvailable = false
                }
                log.error("favorite order sync(\(network.rawValue)) failed: \(error.localizedDescription)")
            }
        }
    }
}
