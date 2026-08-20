import Foundation

nonisolated struct TargetPolicy: Codable, Equatable, Sendable {
    var proofreadingDisabled = false
    var allowDespiteTerminal = false
}

/// Per-app overrides keyed by bundle id. Resolution lives in FocusGuard;
/// this is the persisted table, plus display names so a not-currently-
/// running app keeps its row in Settings > Apps.
@MainActor final class AppPolicyStore {
    static let shared = AppPolicyStore()

    private static let policiesKey = "appPolicies"
    private static let namesKey = "appPolicyDisplayNames"

    private let defaults: UserDefaults
    private(set) var policies: [String: TargetPolicy]
    private(set) var displayNames: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        policies = defaults.data(forKey: Self.policiesKey)
            .flatMap { try? JSONDecoder().decode([String: TargetPolicy].self, from: $0) } ?? [:]
        displayNames = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    func policy(for bundleID: String?) -> TargetPolicy {
        bundleID.flatMap { policies[$0] } ?? TargetPolicy()
    }

    func setPolicy(_ policy: TargetPolicy, for bundleID: String, displayName: String?) {
        // Default-policy rows are dropped so toggling back leaves no ghosts;
        // the display name stays so the row survives in the pane.
        policies[bundleID] = policy == TargetPolicy() ? nil : policy
        if let displayName {
            displayNames[bundleID] = displayName
        }
        if let data = try? JSONEncoder().encode(policies) {
            defaults.set(data, forKey: Self.policiesKey)
        }
        defaults.set(displayNames, forKey: Self.namesKey)
    }
}
