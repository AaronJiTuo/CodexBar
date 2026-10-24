import CodexBarCore

extension StatusItemController {
    nonisolated static func pluginMeterPercents(snapshot: UsageSnapshot?, showUsed: Bool)
        -> (primary: Double?, secondary: Double?)
    {
        guard let snapshot, snapshot.primary != nil || snapshot.secondary != nil else {
            return (self.pluginSwitcherMetricPercent(snapshot: snapshot, showUsed: showUsed), nil)
        }
        let lanes = IconRemainingResolver.resolvedPercents(snapshot: snapshot, style: .combined, showUsed: showUsed)
        return (
            lanes.primary.map { min(100, max(0, $0)) },
            lanes.secondary.map { min(100, max(0, $0)) })
    }

    nonisolated static func pluginSwitcherMetricRateWindow(snapshot: UsageSnapshot?) -> RateWindow? {
        let windows = self.pluginSelectableRateWindows(snapshot: snapshot)
        let weekly = windows.filter { $0.windowMinutes == 7 * 24 * 60 }
            .max { $0.usedPercent < $1.usedPercent }
        return weekly ?? windows.first
    }

    nonisolated static func pluginSwitcherMetricPercent(snapshot: UsageSnapshot?, showUsed: Bool) -> Double? {
        guard let window = self.pluginSwitcherMetricRateWindow(snapshot: snapshot) else { return nil }
        let used = min(100, max(0, window.usedPercent))
        return showUsed ? used : 100 - used
    }

    nonisolated static func userPluginMenuBarLayoutWindows(snapshot: UsageSnapshot?) -> MenuBarLayoutWindows {
        let automatic = self.pluginSwitcherMetricRateWindow(snapshot: snapshot)
        return MenuBarLayoutWindows(
            primary: snapshot?.primary,
            secondary: snapshot?.secondary,
            tertiary: snapshot?.tertiary,
            session: snapshot?.primary,
            weekly: automatic?.windowMinutes == 7 * 24 * 60 ? automatic : snapshot?.secondary,
            automatic: automatic,
            spend: nil)
    }

    private nonisolated static func pluginSelectableRateWindows(snapshot: UsageSnapshot?) -> [RateWindow] {
        ([snapshot?.primary, snapshot?.secondary, snapshot?.tertiary].compactMap(\.self) +
            (snapshot?.extraRateWindows ?? []).filter(\.usageKnown).map(\.window))
            .filter(\.usedPercent.isFinite)
    }

    nonisolated static func switcherWeeklyMetricPercent(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        showUsed: Bool,
        preference: MenuBarMetricPreference = .automatic) -> Double?
    {
        let metric = preference == .automatic || preference == .monthlyPlan
            ? MenuBarMetricWindowResolver.rateWindow(
                preference: preference,
                provider: provider,
                snapshot: snapshot,
                supportsAverage: false)
            : nil
        let presentation = ProviderDescriptorRegistry.descriptor(for: provider).presentation
        let window: RateWindow? = if preference == .monthlyPlan {
            metric
        } else if provider == .mistral {
            nil
        } else if preference == .automatic,
                  let metric,
                  presentation.switcherUsesAutomaticMenuBarWindow
                  || (presentation.automaticSelectionPrioritizesExhaustedWindow && metric.usedPercent >= 100)
        {
            metric
        } else {
            snapshot?.switcherWeeklyWindow(for: provider, showUsed: showUsed)
        }
        if let window {
            return showUsed ? window.usedPercent : window.remainingPercent
        }
        guard preference == .automatic,
              let snapshot,
              let usedPercent = presentation.fallbackSwitcherUsedPercent(snapshot: snapshot),
              usedPercent.isFinite else { return nil }
        return showUsed ? usedPercent : max(0, 100 - usedPercent)
    }
}
