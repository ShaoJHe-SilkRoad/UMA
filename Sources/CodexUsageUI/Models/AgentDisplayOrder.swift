import Foundation

/// The arrangement the user dragged the agent list into.
///
/// Stored as raw provider identifiers rather than indices, so it survives an
/// agent appearing, disappearing or being renamed. Two rules keep it stable:
/// an identifier the arrangement does not mention is never dropped, and an
/// identifier that is no longer installed is never resurrected.
public enum AgentDisplayOrder {
    /// `items` arranged by `order`.
    ///
    /// Anything `order` does not mention keeps its existing relative position
    /// and follows everything that is mentioned, so a newly discovered agent
    /// appears at the end of the list instead of vanishing from it or jumping
    /// to the top. An empty `order` therefore returns `items` untouched, which
    /// is what an install that has never been arranged must see.
    public static func apply<T>(
        _ items: [T],
        order: [String],
        id: (T) -> String
    ) -> [T] {
        guard !order.isEmpty else { return items }
        var rank: [String: Int] = [:]
        for (index, identifier) in order.enumerated() where rank[identifier] == nil {
            rank[identifier] = index
        }
        // enumerated() keeps the comparison total: items of equal rank, and
        // unranked items among themselves, stay in the order they arrived.
        return items.enumerated()
            .sorted { left, right in
                let leftRank = rank[id(left.element)]
                let rightRank = rank[id(right.element)]
                switch (leftRank, rightRank) {
                case let (lhs?, rhs?):
                    return lhs == rhs ? left.offset < right.offset : lhs < rhs
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return left.offset < right.offset
                }
            }
            .map(\.element)
    }

    /// Which agent the menu bar reading belongs to, chosen from the agents
    /// that have a reading at all, already in display order.
    ///
    /// Before the list is arranged, `preferred` keeps priority and the others
    /// are only a fallback, which is exactly what an install that never
    /// touches the list already sees. Once it is arranged, the arrangement
    /// decides: an agent pinned to the top with nothing to report hands the
    /// reading to the next one down rather than blanking the menu bar.
    public static func menuReading<T: Equatable>(
        amongEligible eligible: [T],
        isArranged: Bool,
        preferred: T
    ) -> T? {
        if !isArranged, eligible.contains(preferred) { return preferred }
        return eligible.first
    }

    /// The arrangement after dragging `moved` onto `target`.
    ///
    /// `displayed` is the list as the user currently sees it, so the result is
    /// a complete arrangement rather than a sparse one: what they see is what
    /// gets written, and a later reorder does not have to reason about which
    /// identifiers were previously implicit.
    ///
    /// Returns nil when nothing would change — dropping an item on itself, or
    /// on a position it already occupies — so a no-op drag writes nothing.
    public static func moving(
        _ moved: String,
        onto target: String,
        in displayed: [String]
    ) -> [String]? {
        guard let from = displayed.firstIndex(of: moved),
              let to = displayed.firstIndex(of: target)
        else { return nil }
        var result = displayed
        result.remove(at: from)
        result.insert(moved, at: to)
        // Covers dropping a row on itself as well as on a neighbour it is
        // already adjacent to: both rebuild the list they started from.
        return result == displayed ? nil : result
    }
}
