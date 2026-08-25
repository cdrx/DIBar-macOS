import XCTest
import UserNotifications
@testable import DIBar

final class ModelsTests: XCTestCase {
    // MARK: - Notification authorization

    func testNotificationAuthorizationStatusMapping() {
        XCTAssertEqual(TrackNotifier.authorizationState(for: .authorized), .allowed)
        XCTAssertEqual(TrackNotifier.authorizationState(for: .provisional), .allowed)
        XCTAssertEqual(TrackNotifier.authorizationState(for: .notDetermined), .notDetermined)
        XCTAssertEqual(TrackNotifier.authorizationState(for: .denied), .denied)
    }

    func testNotificationSettingsURLTargetsDIBar() {
        XCTAssertEqual(
            TrackNotifier.notificationSettingsURL(bundleIdentifier: "com.di-fm-menubar.app").absoluteString,
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.di-fm-menubar.app"
        )
        XCTAssertEqual(
            TrackNotifier.notificationSettingsURL(bundleIdentifier: nil).absoluteString,
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }

    // MARK: - Sleep timer input

    func testSleepTimerInputSanitizesCharactersAndExtraPeriods() {
        XCTAssertEqual(SleepTimerInput.sanitized("a1.2x.3"), "1.23")
        XCTAssertEqual(SleepTimerInput.sanitized(".1"), ".1")
        XCTAssertEqual(SleepTimerInput.sanitized("12"), "12")
    }

    func testSleepTimerInputAcceptsPositiveDecimalsOnly() {
        XCTAssertEqual(SleepTimerInput.minutes(from: "0.1"), 0.1)
        XCTAssertEqual(SleepTimerInput.minutes(from: ".1"), 0.1)
        XCTAssertEqual(SleepTimerInput.minutes(from: "1."), 1)
        XCTAssertNil(SleepTimerInput.minutes(from: ""))
        XCTAssertNil(SleepTimerInput.minutes(from: "."))
        XCTAssertNil(SleepTimerInput.minutes(from: "0"))
    }

    func testSleepTimerInputRetainsMaximumAndNormalizesStorage() {
        XCTAssertEqual(SleepTimerInput.effectiveMinutes(from: "900"), 720)
        XCTAssertEqual(SleepTimerInput.storedValue(for: 720), "720")
        XCTAssertEqual(SleepTimerInput.storedValue(for: 0.1), "0.1")
    }

    @MainActor
    func testDecimalSleepTimerBuildsSixSecondDeadline() {
        let timer = SleepTimer()
        let before = Date()
        timer.start(minutes: 0.1)
        let interval = timer.endDate?.timeIntervalSince(before)
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval!, 6, accuracy: 0.1)
        timer.cancel()
    }

    @MainActor
    func testWebBrowserSelectionPrefersDefaultAndFallsBackToSafari() {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        XCTAssertEqual(
            WebBrowserOpener.browserApplicationURL(resolvedDefault: chrome, safariIsAvailable: true),
            chrome
        )
        XCTAssertEqual(
            WebBrowserOpener.browserApplicationURL(resolvedDefault: nil, safariIsAvailable: true),
            WebBrowserOpener.safariURL
        )
        XCTAssertNil(
            WebBrowserOpener.browserApplicationURL(resolvedDefault: nil, safariIsAvailable: false)
        )
    }

    // MARK: - Menu-bar line composition

    @MainActor
    func testMenuBarLineOneUsesChannelThenSite() {
        XCTAssertEqual(
            AppState.composeMenuBarLine1(
                channel: "Ambient", site: "DI.FM",
                showChannel: true, showSite: true
            ),
            "Ambient · DI.FM"
        )
    }

    @MainActor
    func testMenuBarLineOneHonorsIndependentChannelAndSiteToggles() {
        XCTAssertEqual(
            AppState.composeMenuBarLine1(
                channel: "Ambient", site: "DI.FM",
                showChannel: true, showSite: false
            ),
            "Ambient"
        )
        XCTAssertEqual(
            AppState.composeMenuBarLine1(
                channel: "Ambient", site: "DI.FM",
                showChannel: false, showSite: true
            ),
            "DI.FM"
        )
        XCTAssertNil(
            AppState.composeMenuBarLine1(
                channel: "Ambient", site: "DI.FM",
                showChannel: false, showSite: false
            )
        )
    }

    @MainActor
    func testMenuBarLineOneSkipsEmptyValuesAndTruncatesCombinedLabel() {
        XCTAssertEqual(
            AppState.composeMenuBarLine1(
                channel: "", site: "DI.FM",
                showChannel: true, showSite: true
            ),
            "DI.FM"
        )
        let composed = AppState.composeMenuBarLine1(
            channel: String(repeating: "A", count: 30), site: "Long Site Name",
            showChannel: true, showSite: true
        )
        XCTAssertEqual(composed?.count, 35)
        XCTAssertTrue(composed?.hasSuffix("…") == true)
    }

    func testMenuBarComponentOrderNormalizesStoredValues() {
        XCTAssertEqual(MenuBarComponent.decodedOrder(nil), MenuBarComponent.defaultOrder)
        XCTAssertEqual(
            MenuBarComponent.decodedOrder("song,station,song,unknown"),
            [.song, .station, .site, .artist]
        )
        XCTAssertEqual(
            MenuBarComponent.encodedOrder([.artist, .song, .site, .station]),
            "artist,song,site,station"
        )
    }

    func testMenuBarComponentOrderPersistsThroughPrefs() {
        let saved = Prefs.string(.menuBarComponentOrder)
        defer { Prefs.set(saved, for: .menuBarComponentOrder) }

        Prefs.set("song,artist,site,station", for: .menuBarComponentOrder)
        XCTAssertEqual(MenuBarComponent.storedOrder(), [.song, .artist, .site, .station])
    }

    func testMenuBarComponentSwapExchangesFixedSlots() {
        XCTAssertEqual(
            MenuBarComponent.swapping(.station, with: .song, in: MenuBarComponent.defaultOrder),
            [.song, .site, .artist, .station]
        )
    }

    @MainActor
    func testReorderedMenuBarLinesUseSemanticSeparators() {
        let lines = AppState.composeMenuBarLines(
            order: [.song, .artist, .station, .site],
            station: "Ambient", site: "DI.FM",
            artist: "Metallica", song: "So What",
            showStation: true, showSite: true,
            showArtist: true, showSong: true
        )
        XCTAssertEqual(lines.line1, "So What – Metallica")
        XCTAssertEqual(lines.line2, "Ambient · DI.FM")
    }

    @MainActor
    func testReorderedMenuBarLinesSkipHiddenAndLoadingComponents() {
        let lines = AppState.composeMenuBarLines(
            order: [.song, .artist, .station, .site],
            station: "Ambient", site: "DI.FM",
            artist: "Metallica", song: "Loading...",
            showStation: false, showSite: true,
            showArtist: true, showSong: true
        )
        XCTAssertEqual(lines.line1, "Metallica")
        XCTAssertEqual(lines.line2, "DI.FM")
    }

    // MARK: - NowPlaying.formatTime

    func testFormatTime() {
        XCTAssertEqual(NowPlaying.formatTime(0), "0:00")
        XCTAssertEqual(NowPlaying.formatTime(5), "0:05")
        XCTAssertEqual(NowPlaying.formatTime(65), "1:05")
        XCTAssertEqual(NowPlaying.formatTime(600), "10:00")
    }

    // MARK: - TrackArt

    func testStoragePathStripsCdnHost() {
        let url = URL(string: "https://cdn-images.audioaddict.com/8/f/a/cover.jpg")!
        XCTAssertEqual(TrackArt.storagePath(from: url), "/8/f/a/cover.jpg")
    }

    func testStoragePathKeepsForeignHostsInFull() {
        let url = URL(string: "https://example.com/art.jpg")!
        XCTAssertEqual(TrackArt.storagePath(from: url), "https://example.com/art.jpg")
    }

    func testUrlFromStoredPathRestoresCdnHost() {
        XCTAssertEqual(
            TrackArt.url(fromStored: "/8/f/a/cover.jpg")?.absoluteString,
            "https://cdn-images.audioaddict.com/8/f/a/cover.jpg"
        )
    }

    func testUrlFromStoredFullURLPassesThrough() {
        XCTAssertEqual(
            TrackArt.url(fromStored: "https://example.com/art.jpg")?.absoluteString,
            "https://example.com/art.jpg"
        )
    }

    func testUrlFromStoredEmptyIsNil() {
        XCTAssertNil(TrackArt.url(fromStored: nil))
        XCTAssertNil(TrackArt.url(fromStored: ""))
    }

    func testStorageRoundTrip() {
        let original = URL(string: "https://cdn-images.audioaddict.com/8/f/a/cover.jpg")!
        let stored = TrackArt.storagePath(from: original)
        XCTAssertEqual(TrackArt.url(fromStored: stored), original)
    }

    func testThumbnailURLAddsSizeQuery() {
        let url = URL(string: "https://cdn-images.audioaddict.com/8/f/a/cover.jpg")!
        XCTAssertEqual(
            TrackArt.thumbnailURL(url, pixelSize: 64)?.absoluteString,
            "https://cdn-images.audioaddict.com/8/f/a/cover.jpg?size=64x64"
        )
    }

    func testThumbnailURLReplacesExistingQuery() {
        let url = URL(string: "https://cdn-images.audioaddict.com/cover.jpg?size=300x300")!
        XCTAssertEqual(
            TrackArt.thumbnailURL(url, pixelSize: 64)?.absoluteString,
            "https://cdn-images.audioaddict.com/cover.jpg?size=64x64"
        )
    }

    // MARK: - AuthResponse email

    func testAuthResponseDecodesTopLevelEmail() throws {
        let json = Data("""
        {"listen_key": "abc", "email": "user@example.com"}
        """.utf8)
        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(response.resolvedEmail, "user@example.com")
    }

    func testAuthResponseFallsBackToMemberEmail() throws {
        let json = Data("""
        {"listen_key": "abc", "member": {"id": 1, "email": "member@example.com"}}
        """.utf8)
        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(response.resolvedEmail, "member@example.com")
    }

    func testAuthResponseEmailMissingIsNil() throws {
        let json = Data("""
        {"listen_key": "abc"}
        """.utf8)
        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertNil(response.resolvedEmail)
    }

    // MARK: - MembershipSubscription dates

    private func subscription(
        expiresOn: String? = nil,
        firstTrialAt: String? = nil,
        createdAt: String? = nil
    ) -> MembershipSubscription {
        MembershipSubscription(
            status: "active", autoRenew: true, trial: false,
            expiresOn: expiresOn, firstTrialAt: firstTrialAt,
            createdAt: createdAt, networkId: 1
        )
    }

    func testExpiresOnParsesDateOnly() {
        let date = subscription(expiresOn: "2026-01-31").expiresOnDate
        XCTAssertNotNil(date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 1)
        XCTAssertEqual(parts.day, 31)
    }

    func testInternetDateParsesWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(subscription(firstTrialAt: "2025-06-01T12:34:56.789Z").firstTrialDate)
        XCTAssertNotNil(subscription(firstTrialAt: "2025-06-01T12:34:56Z").firstTrialDate)
        XCTAssertNil(subscription(firstTrialAt: "not a date").firstTrialDate)
    }

    func testStartedDatePrefersFirstTrial() {
        let both = subscription(
            firstTrialAt: "2025-06-01T00:00:00Z",
            createdAt: "2025-07-01T00:00:00Z"
        )
        XCTAssertEqual(both.startedDate, both.firstTrialDate)

        let createdOnly = subscription(createdAt: "2025-07-01T00:00:00Z")
        XCTAssertEqual(createdOnly.startedDate, createdOnly.createdAtDate)
    }
}
