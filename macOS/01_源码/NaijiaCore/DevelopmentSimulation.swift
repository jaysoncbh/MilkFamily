#if DEBUG
import Foundation

/// Developer inputs enter the same transaction path as local usage increments.
public enum DevelopmentSimulation {
    /// Parse decimal units without rounding large integers through Double.
    public static func parseTokens(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "").uppercased()
        if let tokens = Int(text), tokens >= 0 { return tokens }
        let places: Int
        switch text.last {
        case "K": places = 3
        case "M": places = 6
        case "B": places = 9
        default: return nil
        }
        let parts = text.dropLast().split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        let whole = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard !whole.isEmpty || !fraction.isEmpty,
              (whole + fraction).utf8.allSatisfy({ (48...57).contains($0) }),
              fraction.dropFirst(places).allSatisfy({ $0 == "0" }) else { return nil }
        let digits = (whole.isEmpty ? "0" : whole) + fraction.prefix(places)
            + String(repeating: "0", count: max(0, places - fraction.count))
        return Int(digits)
    }

    public static func adding(_ tokens: Int, to game: DemoGame, library: AssetLibrary, hatchCharacterID: String? = nil) throws -> DemoGame {
        guard tokens >= 0 else { throw DevelopmentError.invalidTokens }
        guard !game.state.totalTokens.addingReportingOverflow(tokens).overflow else { throw GameError.tokenOverflow }
        var next = game
        if tokens > 0 {
            _ = try next.consume(tokens, library: library, hatchCharacterID: hatchCharacterID)
        }
        return next
    }

    public static func replaying(_ tokens: Int, from game: DemoGame, library: AssetLibrary) throws -> DemoGame {
        guard let starterID = game.state.starterCharacterId ?? library.characters.first(where: {
            $0.rarityCode == 1 && game.owns($0)
        })?.id else { throw GameError.finishOnboarding }
        var initial = DemoState.liveInitial()
        initial.usageLedger = nil
        initial.difficultyPercent = game.state.difficultyPercent
        initial.language = game.state.language
        var replayed = DemoGame(state: initial, rules: game.rules)
        try replayed.chooseStarter(characterID: starterID, library: library)
        if game.readyForGrowth, let idleCardID = library.character(starterID)?.idle.cardId {
            try replayed.draw(cardID: idleCardID, free: true, library: library)
        }
        return try adding(tokens, to: replayed, library: library)
    }

    public static func resetting(rules: PreviewRules) -> DemoGame {
        var initial = DemoState.liveInitial()
        initial.usageLedger = nil
        return DemoGame(state: initial, rules: rules)
    }

    public static func preparingIncubation(_ game: DemoGame, library: AssetLibrary) throws -> DemoGame {
        guard game.state.phase == .cultivating, let character = library.character(game.state.activeCharacterId) else {
            throw GameError.eggOnly
        }
        let lastThreshold = game.threshold(at: character.orderedFrames.count - 1)
        var next = try adding(max(0, lastThreshold - game.state.cultivationTokens), to: game, library: library)
        try next.startWaitingEgg(library: library)
        return next
    }

    public static func tokensToFinishStage(_ game: DemoGame, library: AssetLibrary) throws -> Int {
        if game.state.phase == .incubating {
            return Int(ceil(max(0, Double(game.eggRequirement) - game.state.incubationTokens - (game.state.incubationBonusTokens ?? 0))))
        }
        guard let character = library.character(game.state.activeCharacterId) else { throw GameError.noCharacter }
        return max(0, game.threshold(at: character.orderedFrames.count - 1) - game.state.cultivationTokens)
    }
}

public enum DevelopmentError: LocalizedError {
    case invalidTokens
    public var errorDescription: String? { "测试 Token 请填写非负整数，可用 K、M、B" }
}
#endif
