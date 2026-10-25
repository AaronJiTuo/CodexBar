@testable import CodexBar
import AppKit
import CodexBarCore
import Foundation
import Testing

@Suite struct UserPluginMenuBarBalanceTests {
    @Test
    func `opt in plugin balance renders in brand title`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "prepaid-meter.js",
            source: """
            defineProvider({
              id: "prepaid-meter",
              name: "Prepaid Meter",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://prepaid-meter.example"],
              settings: [],
              fetchUsage() {
                return {
                  cost: { used: 0, currency: "CNY", balance: 9.21 },
                  identity: { loginMethod: "API key" },
                };
              },
            });
            """)
        #expect(plugin.manifest.menuBarBalanceUsesPrepaidCost)
        let binding = try plugin.approvalBinding(settings: [:])
        try fixture.approvals.record(binding)
        let snapshot = try await plugin.fetchUsage(
            settings: [:],
            secrets: [:],
            approvalStore: fixture.approvals)
        let instanceID = plugin.manifest.id
        #expect(UserProviderPluginMenuBarBalance.balance(for: instanceID, snapshot: snapshot) == "CN¥9.21")
        #expect(StatusItemController.userPluginMenuBarBrandTitle(
            instanceID: instanceID,
            snapshot: snapshot,
            showUsed: false,
            showsOptionalCredits: true) == "CN¥9.21")
        #expect(StatusItemController.pluginSwitcherMetricPercent(snapshot: snapshot, showUsed: false) == nil)
    }

    @MainActor
    @Test
    func `undeclared plugin keeps legacy menu bar path without stored layout`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "legacy-meter.js",
            source: """
            defineProvider({
              id: "legacy-meter",
              name: "Legacy Meter",
              endpoints: ["https://legacy-meter.example"],
              settings: [],
              fetchUsage() { return { primary: { usedPercent: 50, windowMinutes: 300 } }; },
            });
            """)
        let settings = testSettingsStore(suiteName: "UserPluginMenuBarBalanceTests-legacy-path")
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarLayout = MenuBarLayout(lines: [[.balance]])
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        #expect(!controller.userPluginUsesStoredMenuBarLayout(plugin))
        #expect(controller.applyStoredMenuBarLayoutForUserPluginIfNeeded(
            plugin: plugin,
            snapshot: nil,
            statusItem: controller.statusItem) == nil)
    }

    @Test
    func `undeclared plugin keeps balance out of menu bar text`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "hidden-balance.js",
            source: """
            defineProvider({
              id: "hidden-balance",
              name: "Hidden Balance",
              endpoints: ["https://hidden-balance.example"],
              settings: [],
              fetchUsage() {
                return { cost: { used: 0, currency: "USD", balance: 12.34 } };
              },
            });
            """)
        let binding = try plugin.approvalBinding(settings: [:])
        try fixture.approvals.record(binding)
        let snapshot = try await plugin.fetchUsage(
            settings: [:],
            secrets: [:],
            approvalStore: fixture.approvals)
        let instanceID = plugin.manifest.id
        #expect(UserProviderPluginMenuBarBalance.balance(for: instanceID, snapshot: snapshot) == nil)
        #expect(StatusItemController.userPluginMenuBarBrandTitle(
            instanceID: instanceID,
            snapshot: snapshot,
            showUsed: false,
            showsOptionalCredits: true) == "—")
    }

    @Test
    func `legacy provider cost snapshot decodes without plugin balance opt in field`() throws {
        let json = """
        {"used":1,"limit":10,"currencyCode":"USD","updatedAt":0}
        """
        let decoded = try JSONDecoder().decode(ProviderCostSnapshot.self, from: Data(json.utf8))
        #expect(decoded.pluginMenuBarBalanceUsesPrepaidCost == nil)
        #expect(decoded.balance == nil)
    }

    @Test
    func `stored layout windows use plugin automatic quota selection`() throws {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 65, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: .distantPast)
        let windows = StatusItemController.userPluginMenuBarLayoutWindows(snapshot: snapshot)
        #expect(windows.automatic?.usedPercent == 65)
        #expect(StatusItemController.pluginSwitcherMetricPercent(snapshot: snapshot, showUsed: false) == 35)
        let automatic = MenuBarLayoutRenderWindow(windows.automatic)
        let instanceID = try #require(ProviderInstanceID(rawValue: "fixture-meter"))
        #expect(StatusItemController.userPluginMenuBarLayoutAutomaticText(
            instanceID: instanceID,
            snapshot: snapshot,
            automatic: automatic,
            showsOptionalCredits: true) == nil)
    }

    @MainActor
    @Test
    func `opt in plugin layout reset dates use plugin automatic windows`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "reset-meter.js",
            source: """
            defineProvider({
              id: "reset-meter",
              name: "Reset Meter",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://reset-meter.example"],
              settings: [],
              fetchUsage() { return { primary: { usedPercent: 10, windowMinutes: 300 } }; },
            });
            """)
        let settings = testSettingsStore(suiteName: "UserPluginMenuBarBalanceTests-reset-dates")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarLayout = MenuBarLayout(lines: [[.windowResetCountdown(window: .automatic)]])
        settings.selectedMenuProvider = plugin.manifest.id
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        let now = Date()
        let resetAt = now.addingTimeInterval(3605)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: resetAt,
                resetDescription: nil),
            updatedAt: now)
        store.snapshots[plugin.manifest.id] = snapshot
        #expect(controller.userPluginUsesStoredMenuBarLayout(plugin))
        let dates = controller.userPluginMenuBarLayoutResetDates(snapshot: snapshot, now: now, absolute: false)
        #expect(dates == [resetAt])
        controller.scheduleMenuBarCountdownRefreshIfNeeded(now: now)
        #expect(controller._test_isMenuBarCountdownRefreshScheduled())
    }

    @MainActor
    @Test
    func `stored layout observation signature tracks automatic balance fallback`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "balance-only-meter.js",
            source: """
            defineProvider({
              id: "balance-only-meter",
              name: "Balance Only",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://balance-only-meter.example"],
              settings: [],
              fetchUsage() {
                return { cost: { used: 0, currency: "CNY", balance: 9.21 } };
              },
            });
            """)
        let settings = testSettingsStore(suiteName: "UserPluginMenuBarBalanceTests-automatic-balance")
        settings.statusChecksEnabled = false
        settings.mergeIcons = true
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarLayout = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])
        settings.selectedMenuProvider = plugin.manifest.id
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        let updatedAt = Date()
        func snapshot(balance: Double) -> UsageSnapshot {
            UsageSnapshot(
                providerCost: ProviderCostSnapshot(
                    used: 0,
                    limit: 0,
                    currencyCode: "CNY",
                    balance: balance,
                    pluginMenuBarBalanceUsesPrepaidCost: true,
                    updatedAt: updatedAt),
                updatedAt: updatedAt,
                identity: ProviderIdentitySnapshot(
                    providerID: plugin.manifest.id,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: nil))
        }
        store.snapshots[plugin.manifest.id] = snapshot(balance: 9.21)
        let first = controller.storeIconObservationSignature()
        store.snapshots[plugin.manifest.id] = snapshot(balance: 8.21)
        let second = controller.storeIconObservationSignature()
        #expect(first != second)
        #expect(first.contains("layoutBalance="))
        #expect(second.contains("layoutBalance="))
    }

    @MainActor
    @Test
    func `stored layout observation signature tracks session window duration labels`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "duration-meter.js",
            source: """
            defineProvider({
              id: "duration-meter",
              name: "Duration Meter",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://duration-meter.example"],
              settings: [],
              fetchUsage() { return {}; },
            });
            """)
        let settings = testSettingsStore(suiteName: "UserPluginMenuBarBalanceTests-window-duration")
        settings.statusChecksEnabled = false
        settings.mergeIcons = true
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarLayoutShowWindowLabels = true
        settings.menuBarLayout = MenuBarLayout(lines: [[.percent(window: .session)]])
        settings.selectedMenuProvider = plugin.manifest.id
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        func snapshot(windowMinutes: Int) -> UsageSnapshot {
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: windowMinutes,
                    resetsAt: nil,
                    resetDescription: nil),
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: plugin.manifest.id,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: nil))
        }
        store.snapshots[plugin.manifest.id] = snapshot(windowMinutes: 300)
        let fiveHour = controller.storeIconObservationSignature()
        store.snapshots[plugin.manifest.id] = snapshot(windowMinutes: 60)
        let oneHour = controller.storeIconObservationSignature()
        #expect(fiveHour != oneHour)
        #expect(fiveHour.contains("layoutWindowMeta=session=minutes=300"))
        #expect(oneHour.contains("layoutWindowMeta=session=minutes=60"))
    }

    @MainActor
    @Test
    func `stored layout observation signature tracks secondary lane percent`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "observe-meter.js",
            source: """
            defineProvider({
              id: "observe-meter",
              name: "Observe Meter",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://observe-meter.example"],
              settings: [],
              fetchUsage() { return {}; },
            });
            """)
        let settings = testSettingsStore(suiteName: "UserPluginMenuBarBalanceTests-observe")
        settings.statusChecksEnabled = false
        settings.mergeIcons = true
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarLayout = MenuBarLayout(lines: [[.lanePercent(lane: .secondary)]])
        settings.selectedMenuProvider = plugin.manifest.id
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        let base = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 40, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: Date())
        store.snapshots[plugin.manifest.id] = base
        let first = controller.storeIconObservationSignature()
        store.snapshots[plugin.manifest.id] = UsageSnapshot(
            primary: base.primary,
            secondary: RateWindow(usedPercent: 55, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: Date())
        let second = controller.storeIconObservationSignature()
        #expect(first != second)
        #expect(first.contains("secondary=60.000"))
        #expect(second.contains("secondary=45.000"))
    }

    @MainActor
    @Test
    func `user plugin layout render data avoids codex tint and uses plugin identity`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "identity-meter.js",
            source: """
            defineProvider({
              id: "identity-meter",
              name: "Identity Meter",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://identity-meter.example"],
              settings: [],
              fetchUsage() {
                return {
                  identity: { accountEmail: "meter@example.com" },
                  cost: { used: 0, currency: "USD", balance: 3 },
                };
              },
            });
            """)
        let settings = testSettingsStore(suiteName: "UserPluginMenuBarBalanceTests-identity")
        settings.hidePersonalInfo = false
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        let binding = try plugin.approvalBinding(settings: [:])
        try fixture.approvals.record(binding)
        let snapshot = try await plugin.fetchUsage(settings: [:], secrets: [:], approvalStore: fixture.approvals)
        store.snapshots[plugin.manifest.id] = snapshot
        let data = controller.userPluginMenuBarLayoutRenderData(plugin: plugin, snapshot: snapshot)
        #expect(data.provider == .synthetic)
        #expect(data.providerName == "Identity Meter")
        #expect(data.accountLabel == "meter@example.com")
        let button = try #require(controller.statusItem.button)
        let options = controller.menuBarLayoutRenderOptionsForUserPlugin(
            instanceID: plugin.manifest.id,
            button: button,
            now: Date())
        #expect(options.colorByProvider == false)
        #expect(options.isStale == false)
        store.errors[plugin.manifest.id] = "offline"
        let staleOptions = controller.menuBarLayoutRenderOptionsForUserPlugin(
            instanceID: plugin.manifest.id,
            button: button,
            now: Date())
        #expect(staleOptions.isStale)
    }

    @Test
    func `automatic layout text stays nil while a quota window is active`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "mixed-meter.js",
            source: """
            defineProvider({
              id: "mixed-meter",
              name: "Mixed Meter",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://mixed-meter.example"],
              settings: [],
              fetchUsage() {
                return {
                  primary: { usedPercent: 40, windowMinutes: 10080 },
                  cost: { used: 0, currency: "USD", balance: 4.50 },
                };
              },
            });
            """)
        let binding = try plugin.approvalBinding(settings: [:])
        try fixture.approvals.record(binding)
        let snapshot = try await plugin.fetchUsage(
            settings: [:],
            secrets: [:],
            approvalStore: fixture.approvals)
        let automatic = MenuBarLayoutRenderWindow(snapshot.primary)
        #expect(StatusItemController.userPluginMenuBarLayoutAutomaticText(
            instanceID: plugin.manifest.id,
            snapshot: snapshot,
            automatic: automatic,
            showsOptionalCredits: true) == nil)
        #expect(UserProviderPluginMenuBarBalance.balance(
            for: plugin.manifest.id,
            snapshot: snapshot,
            showsOptionalCredits: true) == "$4.50")
    }

    private static func loadPlugin(fixture: Fixture, name: String, source: String) throws -> UserProviderPlugin {
        _ = try fixture.write(name: name, source: source)
        return try #require(UserProviderPluginRegistry.refresh(
            loader: fixture.loader(transport: EmptyJSONTransport())).first?.plugin)
    }
}

private struct Fixture {
    let root: URL
    let providers: URL
    let cache: URL
    let approvals: ProviderPluginApprovalStore

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserPluginMenuBarBalanceTests-\(UUID().uuidString)", isDirectory: true)
        self.providers = self.root.appendingPathComponent("providers", isDirectory: true)
        self.cache = self.root.appendingPathComponent("cache", isDirectory: true)
        self.approvals = ProviderPluginApprovalStore(fileURL: self.root.appendingPathComponent("approvals.json"))
        try FileManager.default.createDirectory(at: self.providers, withIntermediateDirectories: true)
    }

    func write(name: String, source: String) throws -> URL {
        let url = self.providers.appendingPathComponent(name)
        try Data(source.utf8).write(to: url, options: .atomic)
        return url
    }

    func loader(transport: any ProviderHTTPTransport) -> UserProviderPluginLoader {
        UserProviderPluginLoader(
            providersDirectory: self.providers,
            cacheDirectory: self.cache,
            transport: transport)
    }

    func remove() {
        UserProviderPluginRegistry.refresh(loader: UserProviderPluginLoader(
            providersDirectory: self.root.appendingPathComponent("empty"),
            cacheDirectory: self.cache))
        try? FileManager.default.removeItem(at: self.root)
    }
}

private final class EmptyJSONTransport: ProviderHTTPTransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = try HTTPURLResponse(
            url: #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (Data("{}".utf8), response)
    }
}
