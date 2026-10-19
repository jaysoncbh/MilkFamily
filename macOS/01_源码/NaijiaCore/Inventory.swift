import Foundation

public enum InventoryItem: String, Codable, CaseIterable, Identifiable, Sendable {
    case milkCandy, milkStar, milkTicket
    public var id: String { rawValue }
    public var name: String {
        switch self { case .milkCandy: "奶糖"; case .milkStar: "奶星石"; case .milkTicket: "奶卡券" }
    }
    public var imagePath: String {
        let file: String
        switch self { case .milkCandy: file = "I01_奶糖"; case .milkStar: file = "I02_奶星石"; case .milkTicket: file = "I03_奶卡券" }
        return "07_软件开发/macOS/05_道具素材/游戏素材/\(file).png"
    }
    public func price(_ rules: PreviewRules) -> Int {
        switch self { case .milkCandy: rules.accelerationPrice; case .milkStar: rules.eggUpgradePrice; case .milkTicket: rules.paidDrawPrice }
    }
}

public extension DemoGame {
    func count(_ item: InventoryItem) -> Int { state.inventory?[item.rawValue, default: 0] ?? 0 }

    mutating func purchase(_ item: InventoryItem) throws {
        guard readyForGrowth else { throw GameError.finishOnboarding }
        let price = price(item)
        guard state.coins >= price else { throw GameError.insufficientCoins }
        let quantity = count(item).addingReportingOverflow(1)
        guard !quantity.overflow else { throw GameError.tokenOverflow }
        state.coins -= price
        state.inventory?[item.rawValue] = quantity.partialValue
    }

    func canUse(_ item: InventoryItem, library: AssetLibrary) -> Bool {
        guard count(item) > 0, readyForGrowth else { return false }
        switch item {
        case .milkCandy: return state.phase == .incubating
        case .milkStar: return state.phase == .incubating && library.characters.contains { $0.rarityCode > state.eggGrade }
        case .milkTicket: return !eligibleCards(in: library).isEmpty
        }
    }

    /// Apply an owned item once. Failures never consume an item; a failed upgrade roll does.
    @discardableResult
    mutating func use(_ item: InventoryItem, library: AssetLibrary, roll: Double = 1, cardID: String? = nil, hatchCharacterID: String? = nil) throws -> Bool {
        guard count(item) > 0 else { throw GameError.noItem }
        guard canUse(item, library: library) else { throw GameError.itemUnavailable }
        var next = self
        let success: Bool
        switch item {
        case .milkCandy:
            // Virtual egg progress is separate from actual usage, currency and draw accounting.
            next.state.incubationBonusTokens = (next.state.incubationBonusTokens ?? 0) + 150
            try next.finishEggIfReady(library: library, hatchCharacterID: hatchCharacterID)
            success = true
        case .milkStar:
            guard roll.isFinite, (0..<1).contains(roll) else { throw GameError.invalidAmount }
            success = roll < rules.eggUpgradeSuccessRate
            if success {
                let fraction = next.eggProgress
                let bonusFraction = (next.state.incubationBonusTokens ?? 0) / Double(next.eggRequirement)
                next.state.eggGrade += 1
                next.state.incubationBonusTokens = bonusFraction * Double(next.eggRequirement)
                next.state.incubationTokens = fraction * Double(next.eggRequirement) - (next.state.incubationBonusTokens ?? 0)
            }
        case .milkTicket:
            guard let cardID, eligibleCards(in: library).contains(where: { $0.id == cardID }) else { throw GameError.lockedCard }
            let quantity = next.state.collection[cardID, default: 0].addingReportingOverflow(1)
            guard !quantity.overflow else { throw GameError.tokenOverflow }
            next.state.collection[cardID] = quantity.partialValue; success = true
        }
        next.state.inventory?[item.rawValue] = count(item) - 1
        self = next
        return success
    }
}
