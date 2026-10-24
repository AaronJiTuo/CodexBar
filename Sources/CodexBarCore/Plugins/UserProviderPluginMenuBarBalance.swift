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
        return UsageFormatter.currencyString(balance, currencyCode: cost.currencyCode)
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
