import CodexBarCore
import Foundation
import Testing

@Suite struct UserProviderPluginMenuBarBalanceLinuxTests {
    @Test
    func `manifest defaults menu bar balance flag to false`() throws {
        let manifest = try ProviderPluginManifest(definition: JSONProviderPluginValue([
            "id": "acme-balance",
            "name": "Acme",
            "endpoints": ["https://api.example.com"],
            "settings": [],
        ]), allowsDynamicID: true)
        #expect(!manifest.menuBarBalanceUsesPrepaidCost)
    }

    @Test
    func `manifest accepts menu bar balance opt in`() throws {
        let manifest = try ProviderPluginManifest(definition: JSONProviderPluginValue([
            "id": "acme-balance",
            "name": "Acme",
            "menuBarBalanceUsesPrepaidCost": true,
            "endpoints": ["https://api.example.com"],
            "settings": [],
        ]), allowsDynamicID: true)
        #expect(manifest.menuBarBalanceUsesPrepaidCost)
    }

    @Test
    func `manifest rejects non boolean menu bar balance flag`() throws {
        #expect(throws: ProviderPluginError.self) {
            try ProviderPluginManifest(definition: JSONProviderPluginValue([
                "id": "acme-balance",
                "name": "Acme",
                "menuBarBalanceUsesPrepaidCost": "yes",
                "endpoints": ["https://api.example.com"],
                "settings": [],
            ]), allowsDynamicID: true)
        }
    }

}
