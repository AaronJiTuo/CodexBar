import Foundation

public enum UserProviderPluginMenuBarBalance {
    public static func menuBarBalanceUsesPrepaidCost(for instanceID: ProviderInstanceID) -> Bool {
        UserProviderPluginRegistry.plugin(for: instanceID)?.manifest.menuBarBalanceUsesPrepaidCost == true
    }

    public static func balance(
        for instanceID: ProviderInstanceID,
        snapshot: UsageSnapshot?,
        showsOptionalCredits: Bool = true)
        -> String?
    {
        guard let cost = self.prepaidBalanceCost(
            for: instanceID,
            snapshot: snapshot,
            showsOptionalCredits: showsOptionalCredits),
              let balance = cost.balance
        else { return nil }
        return self.formattedBalance(balance, currencyCode: cost.currencyCode)
    }

    /// Menu-bar space is tight; CNY drops the en_US `CN` disambiguation prefix (`¥9.21`, not `CN¥9.21`).
    static func formattedBalance(_ balance: Double, currencyCode: String) -> String {
        let text = UsageFormatter.currencyString(balance, currencyCode: currencyCode)
        guard currencyCode.caseInsensitiveCompare("CNY") == .orderedSame else { return text }
        return text.replacingOccurrences(of: "CN¥", with: "¥")
    }

    public static func balanceAmountsUSD(
        for instanceID: ProviderInstanceID,
        snapshot: UsageSnapshot?,
        showsOptionalCredits: Bool = true)
        -> (remaining: Double?, used: Double?)
    {
        guard let cost = self.prepaidBalanceCost(
            for: instanceID,
            snapshot: snapshot,
            showsOptionalCredits: showsOptionalCredits),
            cost.currencyCode.caseInsensitiveCompare("USD") == .orderedSame
        else { return (nil, nil) }
        return (cost.balance, nil)
    }

    private static func prepaidBalanceCost(
        for instanceID: ProviderInstanceID,
        snapshot: UsageSnapshot?,
        showsOptionalCredits: Bool)
        -> ProviderCostSnapshot?
    {
        guard showsOptionalCredits,
              self.ownsSnapshot(instanceID: instanceID, snapshot: snapshot),
              let cost = snapshot?.providerCost,
              cost.balance != nil,
              self.costAllowsMenuBarPrepaidBalance(cost: cost, instanceID: instanceID)
        else { return nil }
        return cost
    }

    private static func costAllowsMenuBarPrepaidBalance(
        cost: ProviderCostSnapshot,
        instanceID: ProviderInstanceID) -> Bool
    {
        switch cost.pluginMenuBarBalanceUsesPrepaidCost {
        case true: true
        case false: false
        case nil: self.menuBarBalanceUsesPrepaidCost(for: instanceID)
        }
    }

    private static func ownsSnapshot(instanceID: ProviderInstanceID, snapshot: UsageSnapshot?) -> Bool {
        snapshot?.identity?.providerID == nil || snapshot?.identity?.providerID == instanceID
    }
}
