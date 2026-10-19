import Foundation

public struct PreviewRules: Decodable, Sendable {
    public let unlockThresholds: [Int]
    public let tokensPerCoin: Int
    public let freeDrawThreshold: Int
    public let paidDrawPrice: Int
    public let eggThresholds: [String: Int]
    public let eggUpgradePrice: Int
    public let eggUpgradeSuccessRate: Double
    public let accelerationPrice: Int

    public static func load(from url: URL) throws -> PreviewRules {
        let rules = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard rules.tokensPerCoin > 0, rules.freeDrawThreshold > 0,
              rules.paidDrawPrice > 0, rules.eggUpgradePrice > 0,
              rules.accelerationPrice > 0,
              (0...1).contains(rules.eggUpgradeSuccessRate),
              rules.unlockThresholds.first == 0,
              zip(rules.unlockThresholds, rules.unlockThresholds.dropFirst()).allSatisfy({ $0 <= $1 }),
              (1...4).allSatisfy({ (rules.eggThresholds[String($0)] ?? 0) > 0 }) else {
            throw GameError.invalidRules
        }
        return rules
    }
    public func threshold(at index: Int) -> Int {
        if index < unlockThresholds.count { return unlockThresholds[index] }
        let step = max(1_000_000, (unlockThresholds.last ?? 0) - (unlockThresholds.dropLast().last ?? 0))
        return (unlockThresholds.last ?? 0) + (index - unlockThresholds.count + 1) * step
    }
}

public enum Phase: String, Codable, Sendable { case cultivating, incubating }
public enum OnboardingStage: String, Codable, Sendable { case choosePartner, starterCard, completed }

public struct DemoState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var totalTokens = 3_200_000
    public var cultivationTokens = 3_200_000
    public var activeCharacterId = "A201"
    public var selectedActionId = "B20101"
    public var desktopCharacterId = "A201"
    public var desktopActionId = "B20101"
    public var awardedActions = ["B20101", "B20102"]
    public var collection = ["C20101": 1, "C20102S": 1]
    public var coins = 320
    public var freeDraws = 3
    public var phase = Phase.cultivating
    public var eggGrade = 1
    public var incubationTokens: Double = 0
    public var accelerated = false
    public var desktopVisible = true
    public var petSize: Double = 116
    public var pinned = true
    public var appearance = "dark"
    public var ownedCharacterIds: [String]? = ["A201"]
    public var characterProgress: [String: Int]? = ["A201": 3_200_000]
    public var usageLedger: UsageLedger?
    public var onboarding: OnboardingStage?
    public var starterCharacterId: String?
    public var inventory: [String: Int]?
    public var difficultyPercent: Int?
    public var language: String?
    public var coinTokenRemainder: Int?
    public var drawTokenRemainder: Int?
    public var incubationBonusTokens: Double?
    public var hatchCounts: [String: Int]?

    public init() {}

    public static func liveInitial() -> DemoState {
        var state = DemoState()
        state.totalTokens = 0; state.cultivationTokens = 0
        state.coins = 0; state.freeDraws = 0
        // Valid references for the empty state; no partner is owned until the user chooses.
        state.activeCharacterId = "A101"; state.desktopCharacterId = "A101"
        state.selectedActionId = "B10101"; state.desktopActionId = "B10101"
        state.awardedActions = []; state.collection = [:]
        state.ownedCharacterIds = []; state.characterProgress = [:]
        state.onboarding = .choosePartner
        state.usageLedger = UsageLedger()
        state.language = "en"
        state.incubationBonusTokens = 0
        state.hatchCounts = [:]
        return state
    }
}

public struct DemoGame: Sendable {
    public var state: DemoState
    public let rules: PreviewRules
    public init(state: DemoState = DemoState(), rules: PreviewRules) {
        var migrated = state
        if migrated.ownedCharacterIds == nil {
            migrated.ownedCharacterIds = Array(Set([state.activeCharacterId] + (state.collection["C20101"] != nil ? ["A201"] : []))).sorted()
        }
        if migrated.characterProgress == nil {
            migrated.characterProgress = [state.activeCharacterId: state.cultivationTokens]
            if state.activeCharacterId != "A201", state.collection["C20101"] != nil { migrated.characterProgress?["A201"] = 3_200_000 }
        }
        // Older saves keep their existing possessions and skip the new first-run gift.
        if migrated.onboarding == nil { migrated.onboarding = .completed }
        if migrated.inventory == nil { migrated.inventory = [:] }
        if migrated.difficultyPercent == nil { migrated.difficultyPercent = 100 }
        if migrated.language == nil { migrated.language = "zh-Hans" }
        if migrated.incubationBonusTokens == nil { migrated.incubationBonusTokens = 0 }
        if migrated.hatchCounts == nil {
            // Old saves did not count hatches. Infer one for owned companions except the known starter.
            migrated.hatchCounts = Dictionary(uniqueKeysWithValues: Set(migrated.ownedCharacterIds ?? [])
                .filter { $0 != migrated.starterCharacterId }.map { ($0, 1) })
        }
        migrated.accelerated = false // Legacy speed boosts no longer apply; existing progress is preserved.
        let percent = (20...500).contains(migrated.difficultyPercent ?? 100) ? migrated.difficultyPercent! : 100
        migrated.difficultyPercent = percent
        let coinRate = max(1, rules.tokensPerCoin / 100 * percent + rules.tokensPerCoin % 100 * percent / 100)
        let drawRate = max(1, rules.freeDrawThreshold / 100 * percent + rules.freeDrawThreshold % 100 * percent / 100)
        migrated.coinTokenRemainder = max(0, migrated.coinTokenRemainder ?? state.totalTokens) % coinRate
        migrated.drawTokenRemainder = max(0, migrated.drawTokenRemainder ?? state.totalTokens) % drawRate
        self.state = migrated; self.rules = rules
    }

    public var difficulty: Int { state.difficultyPercent ?? 100 }
    public func tokenRequirement(_ base: Int) -> Int {
        guard base > 0 else { return 0 }
        let result = (base / 100).multipliedReportingOverflow(by: difficulty)
        guard !result.overflow else { return Int.max }
        let total = result.partialValue.addingReportingOverflow((base % 100) * difficulty / 100)
        return total.overflow ? Int.max : max(1, total.partialValue)
    }
    public func threshold(at index: Int) -> Int { tokenRequirement(rules.threshold(at: index)) }
    public func price(_ item: InventoryItem) -> Int { tokenRequirement(item.price(rules)) }
    public var paidDrawPrice: Int { tokenRequirement(rules.paidDrawPrice) }
    public var coinRequirement: Int { tokenRequirement(rules.tokensPerCoin) }
    public var freeDrawRequirement: Int { tokenRequirement(rules.freeDrawThreshold) }

    public mutating func setDifficulty(_ percent: Int, library: AssetLibrary) throws {
        var next = self
        try next.applyDifficulty(percent, library: library)
        self = next
    }

    private mutating func applyDifficulty(_ percent: Int, library: AssetLibrary) throws {
        guard (20...500).contains(percent) else { throw GameError.invalidDifficulty }
        guard percent != difficulty else { return }
        let coinFraction = Double(state.coinTokenRemainder ?? 0) / Double(coinRequirement)
        let drawFraction = Double(state.drawTokenRemainder ?? 0) / Double(freeDrawRequirement)
        state.difficultyPercent = percent
        state.coinTokenRemainder = min(coinRequirement - 1, Int(coinFraction * Double(coinRequirement)))
        state.drawTokenRemainder = min(freeDrawRequirement - 1, Int(drawFraction * Double(freeDrawRequirement)))
        // Difficulty changes never re-lock earned actions or retroactively mint currency.
        for character in library.characters where owns(character) {
            for (index, frame) in character.orderedFrames.enumerated() where progress(for: character) >= threshold(at: index) {
                if !state.awardedActions.contains(frame.id) { state.awardedActions.append(frame.id) }
            }
        }
        try finishEggIfReady(library: library)
    }

    public var onboardingStage: OnboardingStage { state.onboarding ?? .completed }
    public var readyForGrowth: Bool { onboardingStage == .completed }

    public mutating func chooseStarter(characterID: String, library: AssetLibrary) throws {
        guard onboardingStage == .choosePartner else { throw GameError.starterAlreadyChosen }
        guard let character = library.character(characterID), character.rarityCode == 1,
              character.idle.cardId.flatMap({ library.card($0) }) != nil else { throw GameError.invalidStarter }
        state.activeCharacterId = character.id; state.desktopCharacterId = character.id
        state.selectedActionId = character.idle.id; state.desktopActionId = character.idle.id
        state.ownedCharacterIds = [character.id]; state.characterProgress = [character.id: 0]
        state.awardedActions = [character.idle.id]
        state.starterCharacterId = character.id
        state.freeDraws = 1
        state.onboarding = .starterCard
    }

    public func owns(_ character: CharacterAsset) -> Bool { state.ownedCharacterIds?.contains(character.id) == true }
    public func progress(for character: CharacterAsset) -> Int {
        character.id == state.activeCharacterId ? state.cultivationTokens : state.characterProgress?[character.id, default: 0] ?? 0
    }

    public func unlocked(_ frame: FrameAsset, character: CharacterAsset) -> Bool {
        guard owns(character),
              let index = character.orderedFrames.firstIndex(where: { $0.id == frame.id }) else { return false }
        return state.awardedActions.contains(frame.id) || progress(for: character) >= threshold(at: index)
    }
    public var eggRequirement: Int { tokenRequirement(rules.eggThresholds[String(state.eggGrade)] ?? 50_000_000) }
    public var eggProgress: Double { min(1, (state.incubationTokens + (state.incubationBonusTokens ?? 0)) / Double(eggRequirement)) }
    public var remainingEggTokens: Int {
        let remaining = max(0, Double(eggRequirement) - state.incubationTokens - (state.incubationBonusTokens ?? 0))
        return remaining >= Double(Int.max) ? Int.max : Int(ceil(remaining))
    }

    /// Preserve each rarity's previous probability; only redistribute choices within that rarity.
    public func hatchProbabilities(library: AssetLibrary) -> [String: Double] {
        let candidates = library.characters.filter { $0.rarityCode >= state.eggGrade }
        guard !candidates.isEmpty else { return [:] }
        var probabilities: [String: Double] = [:]
        for group in Dictionary(grouping: candidates, by: \.rarityCode).values {
            let weights = group.map { 1 / (1 + 0.25 * Double(min(4, max(0, state.hatchCounts?[$0.id] ?? 0)))) }
            let total = weights.reduce(0, +)
            let rarityShare = Double(group.count) / Double(candidates.count)
            for (character, weight) in zip(group, weights) { probabilities[character.id] = rarityShare * weight / total }
        }
        return probabilities
    }

    public func hatchCharacterID(library: AssetLibrary, roll: Double = Double.random(in: 0..<1)) -> String? {
        guard roll.isFinite, (0..<1).contains(roll) else { return nil }
        let probabilities = hatchProbabilities(library: library)
        var cumulative = 0.0
        let candidates = library.characters.filter { probabilities[$0.id] != nil }
        for character in candidates {
            cumulative += probabilities[character.id] ?? 0
            if roll < cumulative { return character.id }
        }
        return candidates.last?.id
    }

    @discardableResult
    mutating func finishEggIfReady(library: AssetLibrary, hatchCharacterID: String? = nil) throws -> [String] {
        guard state.phase == .incubating, eggProgress >= 1 else { return [] }
        let chosenID = hatchCharacterID ?? self.hatchCharacterID(library: library)
        guard let hatched = library.characters.first(where: { $0.id == chosenID && $0.rarityCode >= state.eggGrade }) else {
            throw GameError.noCharacter
        }
        state.activeCharacterId = hatched.id; state.selectedActionId = hatched.idle.id
        state.desktopCharacterId = hatched.id; state.desktopActionId = hatched.idle.id
        state.cultivationTokens = state.characterProgress?[hatched.id, default: 0] ?? 0
        if state.ownedCharacterIds?.contains(hatched.id) != true { state.ownedCharacterIds?.append(hatched.id) }
        state.characterProgress?[hatched.id] = state.cultivationTokens
        let count = max(0, state.hatchCounts?[hatched.id] ?? 0)
        state.hatchCounts?[hatched.id] = count == Int.max ? count : count + 1
        state.phase = .cultivating; state.incubationTokens = 0; state.incubationBonusTokens = 0
        state.accelerated = false; state.eggGrade = 1
        return award(hatched)
    }

    // Gameplay eligibility follows owned, unlocked actions. Art acceptance flags remain untouched.
    public func eligibleCards(in library: AssetLibrary) -> [CardAsset] {
        guard onboardingStage != .choosePartner else { return [] }
        return library.cards.filter { card in
            guard let character = library.character(card.characterId),
                  let frame = character.orderedFrames.first(where: { $0.id == card.actionId }),
                  frame.cardId == card.id, unlocked(frame, character: character) else { return false }
            if onboardingStage == .starterCard {
                return character.id == state.starterCharacterId && frame.id == character.idle.id
            }
            return true
        }
    }

    public mutating func draw(cardID: String, free: Bool, library: AssetLibrary) throws {
        guard library.card(cardID) != nil else { throw GameError.noCard }
        guard eligibleCards(in: library).contains(where: { $0.id == cardID }) else { throw GameError.lockedCard }
        guard onboardingStage != .starterCard || free else { throw GameError.finishOnboarding }
        let quantity = state.collection[cardID, default: 0].addingReportingOverflow(1)
        guard !quantity.overflow else { throw GameError.tokenOverflow }
        if free {
            guard state.freeDraws > 0 else { throw GameError.noFreeDraw }
            state.freeDraws -= 1
        } else {
            guard state.coins >= paidDrawPrice else { throw GameError.insufficientCoins }
            state.coins -= paidDrawPrice
        }
        state.collection[cardID] = quantity.partialValue
        if onboardingStage == .starterCard { state.onboarding = .completed }
    }

    @discardableResult
    public mutating func consume(_ amount: Int, library: AssetLibrary, hatchCharacterID: String? = nil) throws -> [String] {
        var next = self
        let actions = try next.applyUsage(amount, library: library, hatchCharacterID: hatchCharacterID)
        self = next
        return actions
    }

    private mutating func applyUsage(_ amount: Int, library: AssetLibrary, hatchCharacterID: String?) throws -> [String] {
        guard amount > 0 else { throw GameError.invalidAmount }
        guard readyForGrowth else { throw GameError.finishOnboarding }
        guard let character = library.character(state.activeCharacterId) else { throw GameError.noCharacter }
        let total = state.totalTokens.addingReportingOverflow(amount)
        guard !total.overflow else { throw GameError.tokenOverflow }
        let coinRemainder = (state.coinTokenRemainder ?? 0) + amount % coinRequirement
        let drawRemainder = (state.drawTokenRemainder ?? 0) + amount % freeDrawRequirement
        let coins = state.coins.addingReportingOverflow(amount / coinRequirement + coinRemainder / coinRequirement)
        let draws = state.freeDraws.addingReportingOverflow(amount / freeDrawRequirement + drawRemainder / freeDrawRequirement)
        let cultivation = state.cultivationTokens.addingReportingOverflow(state.phase == .cultivating ? amount : 0)
        guard !coins.overflow, !draws.overflow, !cultivation.overflow else { throw GameError.tokenOverflow }
        state.totalTokens = total.partialValue
        state.coins = coins.partialValue
        state.freeDraws = draws.partialValue
        state.coinTokenRemainder = coinRemainder % coinRequirement
        state.drawTokenRemainder = drawRemainder % freeDrawRequirement
        if state.phase == .incubating {
            let eggTokens = min(amount, remainingEggTokens)
            state.incubationTokens += Double(eggTokens)
            var actions = try finishEggIfReady(library: library, hatchCharacterID: hatchCharacterID)
            let surplus = amount - eggTokens
            if surplus > 0, state.phase == .cultivating,
               let hatched = library.character(state.activeCharacterId) {
                let progress = state.cultivationTokens.addingReportingOverflow(surplus)
                guard !progress.overflow else { throw GameError.tokenOverflow }
                state.cultivationTokens = progress.partialValue
                state.characterProgress?[hatched.id] = state.cultivationTokens
                actions += award(hatched)
            }
            return actions
        }
        state.cultivationTokens = cultivation.partialValue
        state.characterProgress?[character.id] = state.cultivationTokens
        return award(character)
    }

    private mutating func award(_ character: CharacterAsset) -> [String] {
        var newlyAwarded: [String] = []
        for (index, frame) in character.orderedFrames.enumerated() {
            guard state.cultivationTokens >= threshold(at: index),
                  !state.awardedActions.contains(frame.id) else { continue }
            state.awardedActions.append(frame.id)
            newlyAwarded.append(frame.id)
        }
        return newlyAwarded
    }

    public mutating func startWaitingEgg(library: AssetLibrary) throws {
        guard readyForGrowth else { throw GameError.finishOnboarding }
        guard let character = library.character(state.activeCharacterId),
              character.orderedFrames.allSatisfy({ unlocked($0, character: character) }) else {
            throw GameError.incompleteCultivation
        }
        state.phase = .incubating
    }

    @discardableResult
    public mutating func upgrade(roll: Double, library: AssetLibrary) throws -> Bool {
        guard roll.isFinite, (0..<1).contains(roll) else { throw GameError.invalidAmount }
        guard state.phase == .incubating else { throw GameError.eggOnly }
        guard library.characters.contains(where: { $0.rarityCode >= state.eggGrade + 1 }) else { throw GameError.unavailableGrade }
        guard state.coins >= price(.milkStar) else { throw GameError.insufficientCoins }
        let progress = eggProgress
        let bonusFraction = (state.incubationBonusTokens ?? 0) / Double(eggRequirement)
        state.coins -= price(.milkStar)
        if roll < rules.eggUpgradeSuccessRate {
            state.eggGrade += 1
            state.incubationBonusTokens = bonusFraction * Double(eggRequirement)
            state.incubationTokens = progress * Double(eggRequirement) - (state.incubationBonusTokens ?? 0)
            return true
        }
        return false
    }

}

public enum GameError: LocalizedError {
    case invalidRules, invalidAmount, tokenOverflow, noCard, noCharacter, noFreeDraw, insufficientCoins
    case eggOnly, unavailableGrade, alreadyAccelerated, incompleteCultivation
    case invalidStarter, starterAlreadyChosen, finishOnboarding, lockedCard
    case noItem, itemUnavailable, invalidDifficulty
    public var errorDescription: String? {
        switch self {
        case .invalidRules: "玩法规则无效"
        case .invalidAmount: "用量必须为正整数"
        case .tokenOverflow: "Token 数值过大，无法继续增加"
        case .noCard: "这张卡的素材暂不可用"
        case .noCharacter: "当前等级还没有可用伙伴"
        case .noFreeDraw: "免费次数已用完"
        case .insufficientCoins: "奶币不足"
        case .eggOnly: "这件商品在孵蛋时使用"
        case .unavailableGrade: "下一等级还没有伙伴素材"
        case .alreadyAccelerated: "已经加速"
        case .incompleteCultivation: "先解锁全部动作"
        case .invalidStarter: "请选择一位普通伙伴"
        case .starterAlreadyChosen: "初始伙伴已经选定"
        case .finishOnboarding: "先选择伙伴，再去小铺领取待机卡"
        case .lockedCard: "该动作卡尚未解锁"
        case .noItem: "仓库里没有这件道具"
        case .itemUnavailable: "这件道具现在无法使用"
        case .invalidDifficulty: "难度范围为20%–500%"
        }
    }
}
