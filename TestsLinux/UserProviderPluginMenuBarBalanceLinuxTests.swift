import Foundation
import Testing
@testable import CodexBarCore

@Suite struct UserProviderPluginMenuBarBalanceLinuxTests {
    @Test
    func `manifest defaults menu bar balance flag to false`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "default-balance.js",
            source: Self.pluginSource(id: "default-balance", menuBarBalanceField: nil))
        #expect(!plugin.manifest.menuBarBalanceUsesPrepaidCost)
    }

    @Test
    func `manifest accepts menu bar balance opt in`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "opt-in-balance.js",
            source: Self.pluginSource(id: "opt-in-balance", menuBarBalanceField: "menuBarBalanceUsesPrepaidCost: true,"))
        #expect(plugin.manifest.menuBarBalanceUsesPrepaidCost)
    }

    @Test
    func `manifest rejects non boolean menu bar balance flag`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = Self.pluginSource(
            id: "invalid-balance",
            menuBarBalanceField: #"menuBarBalanceUsesPrepaidCost: "yes","#)
        let url = try fixture.write(name: "invalid-balance.js", source: source)
        #expect(throws: ProviderPluginError.self) {
            try fixture.loader(transport: RecordingTransport(responseJSON: "{}"))
                .load(fileURL: url)
        }
    }

    @Test
    func `opt in balance formats snapshot currency without registry gaps`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try Self.loadPlugin(
            fixture: fixture,
            name: "cny-balance.js",
            source: """
            defineProvider({
              id: "cny-balance",
              name: "CNY Balance",
              menuBarBalanceUsesPrepaidCost: true,
              endpoints: ["https://cny-balance.example"],
              settings: [],
              fetchUsage() {
                return { cost: { used: 0, currency: "CNY", balance: 9.21 } };
              },
            });
            """)
        let binding = try plugin.approvalBinding(settings: [:])
        try fixture.approvals.record(binding)
        let snapshot = try await plugin.fetchUsage(
            settings: [:],
            secrets: [:],
            approvalStore: fixture.approvals)
        #expect(UserProviderPluginMenuBarBalance.balance(
            for: plugin.manifest.id,
            snapshot: snapshot,
            showsOptionalCredits: true) == "¥9.21")
    }

    private static func loadPlugin(fixture: Fixture, name: String, source: String) throws -> UserProviderPlugin {
        _ = try fixture.write(name: name, source: source)
        return try #require(UserProviderPluginRegistry.refresh(
            loader: fixture.loader(transport: RecordingTransport(responseJSON: "{}"))).first?.plugin)
    }

    private static func pluginSource(id: String, menuBarBalanceField: String?) -> String {
        """
        defineProvider({
          id: "\(id)",
          name: "\(id)",
          \(menuBarBalanceField ?? "")
          endpoints: ["https://\(id).example"],
          settings: [],
          fetchUsage() { return { primary: { usedPercent: 1 } }; },
        });
        """
    }
}

private struct Fixture {
    let root: URL
    let providers: URL
    let cache: URL
    let approvals: ProviderPluginApprovalStore

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserProviderPluginMenuBarBalanceLinuxTests-\(UUID().uuidString)", isDirectory: true)
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

private final class RecordingTransport: ProviderHTTPTransport, @unchecked Sendable {
    private let responseJSON: String

    init(responseJSON: String) {
        self.responseJSON = responseJSON
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = try HTTPURLResponse(
            url: #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (Data(self.responseJSON.utf8), response)
    }
}
