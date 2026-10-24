@testable import CodexBar
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
        let automatic = MenuBarLayoutRenderWindow(snapshot?.primary)
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
