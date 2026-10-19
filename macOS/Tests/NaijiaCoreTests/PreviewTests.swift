import Foundation
import CoreGraphics
import NaijiaCore

final class PreviewTests {
    private var macRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private var assetRoot: URL {
        if let path = ProcessInfo.processInfo.environment["NAIJIA_ASSET_ROOT"] {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return macRoot.deletingLastPathComponent().appendingPathComponent("Resources")
    }
    private func resources() throws -> (AssetLibrary, PreviewRules) {
        let project = assetRoot
        return (try AssetLibrary.load(from: project.appendingPathComponent("05_配置与索引/角色记录.json")),
                try PreviewRules.load(from: macRoot.appendingPathComponent("02_配置/正式版规则.json")))
    }

    private func startedGame(_ library: AssetLibrary, _ rules: PreviewRules, id: String = "A101") throws -> DemoGame {
        var initial = DemoState.liveInitial(); initial.usageLedger = nil
        var game = DemoGame(state: initial, rules: rules)
        try game.chooseStarter(characterID: id, library: library)
        try game.draw(cardID: try requireValue(library.character(id)?.idle.cardId), free: true, library: library)
        return game
    }

    func testNewDefaultsKeepExistingLanguagesAndLedgers() throws {
        let (_, rules) = try resources()
        requireEqual(DemoGame(state: .liveInitial(), rules: rules).state.language, "en")
        for language in ["en", "zh-Hans"] {
            var state = DemoState.liveInitial(); state.language = language
            let migrated = DemoGame(state: state, rules: rules)
            requireEqual(migrated.state.language, language); requireEqual(migrated.state.usageLedger, state.usageLedger)
        }
    }

    func testCandyBonusFinishesEggWithoutMintingUsage() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        _ = try game.consume(80_000_000, library: library)
        try game.startWaitingEgg(library: library)
        game.state.inventory?[InventoryItem.milkCandy.rawValue] = 3
        game.state.incubationTokens = Double(game.eggRequirement) - 301
        var ledger = UsageLedger(startedAt: Date(timeIntervalSince1970: 1))
        ledger.initialized = true; ledger.credited = ["real-log-fixture": 12345]
        game.state.usageLedger = ledger
        let original = game.state
        try game.use(.milkCandy, library: library, hatchCharacterID: "A102")
        requireEqual(game.state.incubationTokens, original.incubationTokens)
        requireEqual(game.state.incubationBonusTokens, 150); requireEqual(game.state.phase, .incubating)
        try game.use(.milkCandy, library: library, hatchCharacterID: "A102")
        requireEqual(game.state.incubationBonusTokens, 300); requireEqual(game.state.phase, .incubating)
        let restored = DemoGame(state: try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(game.state)), rules: rules)
        requireEqual(restored.state, game.state)
        _ = try game.consume(1, library: library, hatchCharacterID: "A102")
        requireEqual(game.state.phase, .cultivating); requireEqual(game.state.activeCharacterId, "A102")
        requireEqual(game.state.totalTokens, original.totalTokens + 1)
        requireEqual(game.state.usageLedger, original.usageLedger)
        requireEqual(game.state.coins, original.coins); requireEqual(game.state.freeDraws, original.freeDraws)
        requireEqual(game.state.hatchCounts?["A102"], 1)
        game.state.phase = .incubating; game.state.incubationTokens = Double(game.eggRequirement) - 150
        let beforeCandy = game.state
        try game.use(.milkCandy, library: library, hatchCharacterID: "A102")
        requireEqual(game.state.phase, .cultivating); requireEqual(game.state.hatchCounts?["A102"], 2)
        requireEqual(game.state.totalTokens, beforeCandy.totalTokens); requireEqual(game.state.usageLedger, beforeCandy.usageLedger)
        requireEqual(game.state.coins, beforeCandy.coins); requireEqual(game.state.freeDraws, beforeCandy.freeDraws)
        requireEqual(game.count(.milkCandy), 0)
    }

    func testRepeatHatchesPreserveRaritySharesAndFloor() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        let original = game.hatchProbabilities(library: library)
        game.state.hatchCounts?["A102"] = 1
        let reduced = game.hatchProbabilities(library: library)
        requireTrue(reduced["A102"]! < original["A102"]!)
        requireTrue(reduced["A103"]! > original["A103"]!)
        for grade in 1...4 {
            game.state.eggGrade = grade
            let probabilities = game.hatchProbabilities(library: library)
            let candidates = library.characters.filter { $0.rarityCode >= grade }
            requireEqual(probabilities.values.reduce(0, +), 1, accuracy: 0.0000001)
            for rarity in grade...4 {
                let characters = candidates.filter { $0.rarityCode == rarity }
                requireEqual(characters.reduce(0) { $0 + (probabilities[$1.id] ?? 0) }, Double(characters.count) / Double(candidates.count), accuracy: 0.0000001)
            }
            for roll in [0.0, 0.25, 0.9999999] {
                requireTrue(candidates.contains { $0.id == game.hatchCharacterID(library: library, roll: roll) })
            }
        }
        game.state.eggGrade = 1; game.state.hatchCounts?["A102"] = 4
        let floor = game.hatchProbabilities(library: library)
        game.state.hatchCounts?["A102"] = 100
        requireEqual(game.hatchProbabilities(library: library), floor)
    }

    func testDifficultyTrackPricesAndPetEdges() throws {
        let (_, rules) = try resources()
        requireEqual(DifficultyScale.position(for: 100), 0.2, accuracy: 0.00001)
        for percent in [20.0, 50, 100, 101, 300, 500] {
            requireEqual(DifficultyScale.percent(at: DifficultyScale.position(for: percent)), percent, accuracy: 0.00001)
        }
        for percent in [20, 100, 500] {
            var state = DemoState.liveInitial(); state.difficultyPercent = percent
            let game = DemoGame(state: state, rules: rules)
            requireEqual(game.price(.milkCandy), 150 * percent / 100)
            requireEqual(game.price(.milkStar), 200 * percent / 100)
            requireEqual(game.price(.milkTicket), 100 * percent / 100)
        }
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1280, y: 0, width: 1280, height: 800)]
        for point in [CGPoint(x: -50, y: -50), CGPoint(x: 1380, y: 840), CGPoint(x: -1330, y: 740)] {
            let frame = CGRect(origin: point, size: CGSize(width: 116, height: 116))
            requireEqual(DesktopPetPlacement.constrain(frame, to: screens), frame)
        }
        let lost = DesktopPetPlacement.constrain(CGRect(x: 5000, y: 5000, width: 116, height: 116), to: screens)
        requireEqual(lost.minX, 1382, accuracy: 0.00001); requireEqual(lost.minY, 842, accuracy: 0.00001)
    }

    func testRealAssetMappingsAndVariableActionCounts() throws {
        let (library, rules) = try resources()
        let adult = try requireValue(library.character("A201"))
        let mouse = try requireValue(library.character("A101"))
        requireEqual(mouse.orderedFrames.count, 5); requireEqual(adult.orderedFrames.count, 6)
        requireEqual(adult.orderedFrames[1].cardId, "C20102S")
        requireEqual(adult.rarity, "稀有")
        requireTrue(library.cards.allSatisfy { !$0.gamePoolOpen })
        for index in 0..<10 { requireEqual(rules.threshold(at: index), index * 20_000_000) }
        for grade in 1...4 { requireEqual(rules.eggThresholds[String(grade)], 50_000_000) }
        requireEqual(rules.tokensPerCoin, 1_000_000); requireEqual(rules.freeDrawThreshold, 100_000_000)
    }

    func testFreshAndResetStatesHaveNoGiftsBeforeChoice() throws {
        let (library, rules) = try resources()
        let game = DemoGame(state: .liveInitial(), rules: rules)
        requireEqual(game.onboardingStage, .choosePartner)
        requireEqual(game.state.totalTokens, 0); requireEqual(game.state.coins, 0); requireEqual(game.state.freeDraws, 0)
        requireEqual(game.state.ownedCharacterIds, []); requireEqual(game.state.collection, [:]); requireEqual(game.state.awardedActions, [])
        requireEqual(game.eligibleCards(in: library).count, 0)
        #if DEBUG
        let reset = DevelopmentSimulation.resetting(rules: rules)
        requireEqual(reset.onboardingStage, game.onboardingStage)
        requireEqual(reset.state.ownedCharacterIds, []); requireEqual(reset.state.collection, [:])
        requireEqual(reset.state.totalTokens, 0); requireEqual(reset.state.freeDraws, 0)
        #endif
    }

    func testEveryCommonPartnerGivesOnlyIdleAndOneDraw() throws {
        let (library, rules) = try resources()
        let choices = library.characters.filter { $0.rarityCode == 1 }
        requireEqual(choices.count, 19)
        for character in choices {
            var game = DemoGame(state: .liveInitial(), rules: rules)
            try game.chooseStarter(characterID: character.id, library: library)
            requireEqual(game.state.ownedCharacterIds, [character.id])
            requireEqual(game.state.awardedActions, [character.idle.id])
            requireEqual(game.state.collection, [:]); requireEqual(game.state.coins, 0)
            requireEqual(game.state.freeDraws, 1); requireEqual(game.onboardingStage, .starterCard)
            requireEqual(game.eligibleCards(in: library).map(\.id), character.orderedFrames.prefix(1).compactMap(\.cardId))
        }
    }

    func testStarterChoiceRejectsRareAndCannotRepeat() throws {
        let (library, rules) = try resources()
        var game = DemoGame(state: .liveInitial(), rules: rules)
        let before = game.state
        requireThrows(try game.chooseStarter(characterID: "A201", library: library))
        requireEqual(game.state, before)
        try game.chooseStarter(characterID: "A104", library: library)
        let chosen = game.state
        requireThrows(try game.chooseStarter(characterID: "A101", library: library))
        requireEqual(game.state, chosen)
    }

    func testTutorialMustBeClickedBeforeGrowthAndOnlyIdleCanDraw() throws {
        let (library, rules) = try resources()
        var game = DemoGame(state: .liveInitial(), rules: rules)
        try game.chooseStarter(characterID: "A101", library: library)
        let before = game.state
        requireThrows(try game.consume(20_000_000, library: library))
        requireThrows(try game.draw(cardID: "C10102", free: true, library: library))
        requireThrows(try game.draw(cardID: "C10201", free: true, library: library))
        requireThrows(try game.draw(cardID: "C10101", free: false, library: library))
        requireEqual(game.state, before)
        try game.draw(cardID: "C10101", free: true, library: library)
        requireEqual(game.state.collection, ["C10101": 1]); requireEqual(game.state.freeDraws, 0)
        requireEqual(game.state.totalTokens, 0); requireEqual(game.state.coins, 0)
        requireEqual(game.onboardingStage, .completed)
        let claimed = game.state
        requireThrows(try game.draw(cardID: "C10101", free: true, library: library))
        requireEqual(game.state, claimed)
    }

    func testActionThresholdUnlocksWithoutGivingCard() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        let mouse = try requireValue(library.character("A101"))
        _ = try game.consume(19_999_999, library: library)
        requireFalse(game.unlocked(mouse.orderedFrames[1], character: mouse))
        requireThrows(try game.draw(cardID: "C10102", free: true, library: library))
        let actions = try game.consume(1, library: library)
        requireEqual(actions, [mouse.orderedFrames[1].id])
        requireTrue(game.unlocked(mouse.orderedFrames[1], character: mouse))
        requireEqual(game.eligibleCards(in: library).map(\.id), ["C10101", "C10102"])
        requireEqual(game.state.collection, ["C10101": 1])
        requireEqual(game.state.coins, 20); requireEqual(game.state.freeDraws, 0)
    }

    func testCurrencyAndFreeDrawBoundariesKeepRemainders() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        _ = try game.consume(999_999, library: library)
        requireEqual(game.state.coins, 0)
        _ = try game.consume(1, library: library)
        requireEqual(game.state.coins, 1)
        _ = try game.consume(98_999_999, library: library)
        requireEqual(game.state.coins, 99); requireEqual(game.state.freeDraws, 0)
        _ = try game.consume(1, library: library)
        requireEqual(game.state.coins, 100); requireEqual(game.state.freeDraws, 1)
        _ = try game.consume(100_000_000, library: library)
        _ = try game.consume(500_000, library: library)
        requireEqual(game.state.freeDraws, 2); requireEqual(game.state.coins, 200)
        requireEqual(game.state.totalTokens % rules.freeDrawThreshold, 500_000)
    }

    func testDrawChargesOnceAndCannotUnlockOthers() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        _ = try game.consume(100_000_000, library: library)
        let actions = game.state.awardedActions
        try game.draw(cardID: "C10101", free: false, library: library)
        requireEqual(game.state.coins, 0); requireEqual(game.state.freeDraws, 1)
        try game.draw(cardID: "C10101", free: true, library: library)
        requireEqual(game.state.collection["C10101"], 3)
        requireEqual(game.state.awardedActions, actions)
        requireFalse(game.owns(try requireValue(library.character("A102"))))
        let before = game.state
        requireThrows(try game.draw(cardID: "C10102", free: false, library: library))
        requireEqual(game.state, before)
    }

    func testWaitingEggAndFiftyMillionHatchDoNotGiveCards() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        requireThrows(try game.startWaitingEgg(library: library))
        _ = try game.consume(80_000_000, library: library)
        try game.startWaitingEgg(library: library)
        _ = try game.consume(49_999_999, library: library, hatchCharacterID: "A202")
        requireEqual(game.state.phase, .incubating)
        _ = try game.consume(1, library: library, hatchCharacterID: "A202")
        requireEqual(game.state.phase, .cultivating); requireEqual(game.state.activeCharacterId, "A202")
        requireEqual(game.state.ownedCharacterIds, ["A101", "A202"])
        requireEqual(game.state.characterProgress?["A101"], 80_000_000)
        requireEqual(game.state.collection, ["C10101": 1])
        requireTrue(game.state.awardedActions.contains("B20201"))
        requireEqual(Set(game.eligibleCards(in: library).map(\.characterId)), Set(["A101", "A202"]))
        requireEqual(game.eligibleCards(in: library).filter { $0.characterId == "A202" }.map(\.id), ["C20201"])
        _ = try game.consume(20_000_000, library: library)
        requireEqual(game.eligibleCards(in: library).filter { $0.characterId == "A202" }.count, 2)
        requireEqual(game.state.collection, ["C10101": 1])
    }

    func testUpgradeAndAccelerationKeepRealTokenRewards() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        _ = try game.consume(100_000_000, library: library)
        game.state.coins = 400 // Fund purchases without changing token accounting in this fixture.
        try game.startWaitingEgg(library: library)
        _ = try game.consume(25_000_000, library: library)
        requireTrue(try game.upgrade(roll: 0.1, library: library))
        requireEqual(game.state.eggGrade, 2); requireEqual(game.eggProgress, 0.5, accuracy: 0.00001)
        try game.purchase(.milkCandy)
        try game.use(.milkCandy, library: library)
        let beforeCoins = game.state.coins
        _ = try game.consume(1_000_000, library: library)
        requireEqual(game.state.incubationTokens, 26_000_000); requireEqual(game.state.incubationBonusTokens, 150); requireEqual(game.state.coins, beforeCoins + 1)
        let before = game.state
        requireThrows(try game.use(.milkCandy, library: library)); requireEqual(game.state, before)
        var unavailable = game; unavailable.state.eggGrade = 4
        let beforeUnavailable = unavailable.state
        requireThrows(try unavailable.upgrade(roll: 0, library: library)); requireEqual(unavailable.state, beforeUnavailable)
    }

    func testNewCharacterMappingsAndFirstPose() throws {
        let (library, _) = try resources()
        requireEqual(library.characters.count, 32)
        requireEqual(library.characters.reduce(0) { $0 + $1.orderedFrames.count }, 179)
        requireEqual(library.cards.count, 175)
        let expected: [String: [String]] = [
            "A112": ["C11201", "C11202", "C11203", "C11204"],
            "A113": ["C11301", "C11302", "C11303", "C11304"],
            "A114": ["C11401", "C11402", "C11403", "C11404"],
            "A115": ["C11501", "C11502", "C11503", "C11504"],
            "A203": ["C20301", "C20302", "C20303", "C20304", "C20305S", "C20306S"],
            "A204": ["C20401", "C20402", "C20403", "C20404", "C20405S", "C20406S"],
            "A302": ["C30201S", "C30202S", "C30203S", "C30204SS", "C30205S", "C30206SS"],
            "A401": ["C40101SS", "C40102SS", "C40103SS", "C40104SS", "C40105SSS", "C40106SSS"]
        ]
        for (id, cards) in expected {
            let character = try requireValue(library.character(id))
            requireEqual(Array(character.orderedFrames.prefix(cards.count)).compactMap(\.cardId), cards)
        }
        let cat = try requireValue(library.character("A401"))
        requireEqual(cat.poseOrder.first, "knead"); requireEqual(cat.idle.id, "B40101")
        requireEqual(cat.idle.name, "踩奶"); requireEqual(cat.rarityCode, 4)
        requireEqual(library.character("A301")?.rarityCode, 3)
        requireEqual(library.character("A204")?.rarityCode, 2)
        requireEqual(library.cards.filter { $0.characterId == "A301" }.map(\.id), ["C30105SS"])
    }

    func testAllNewCharactersHatchAndUnlockOnlyTheirFixedCards() throws {
        let (library, rules) = try resources()
        for character in library.characters where character.id != "A101" {
            let id = character.id
            var game = try startedGame(library, rules)
            _ = try game.consume(80_000_000, library: library)
            try game.startWaitingEgg(library: library)
            game.state.eggGrade = character.rarityCode
            let existingCollection = game.state.collection
            _ = try game.consume(50_000_000, library: library, hatchCharacterID: id)
            requireEqual(game.state.activeCharacterId, id)
            requireEqual(game.state.desktopActionId, character.idle.id)
            requireEqual(game.state.ownedCharacterIds, ["A101", id])
            requireEqual(game.state.collection, existingCollection)
            requireEqual(game.eligibleCards(in: library).filter { $0.characterId == id }.map(\.id), character.orderedFrames.prefix(1).compactMap(\.cardId))
            for index in 1..<character.orderedFrames.count {
                _ = try game.consume(20_000_000, library: library)
                let eligible = game.eligibleCards(in: library).filter { $0.characterId == id }.map(\.id)
                requireEqual(eligible, character.orderedFrames.prefix(index + 1).compactMap(\.cardId))
                requireEqual(game.state.collection, existingCollection)
            }
            let finalCard = try requireValue(character.orderedFrames.last?.cardId)
            try game.draw(cardID: finalCard, free: true, library: library)
            requireEqual(game.state.collection[finalCard], 1)
        }
    }

    func testLegendaryUpgradeAndStateRoundTrip() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        _ = try game.consume(80_000_000, library: library)
        try game.startWaitingEgg(library: library)
        game.state.eggGrade = 3; game.state.coins = 200
        _ = try game.consume(25_000_000, library: library)
        requireTrue(try game.upgrade(roll: 0, library: library))
        requireEqual(game.state.eggGrade, 4); requireEqual(game.eggProgress, 0.5, accuracy: 0.00001)
        let saved = try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(game.state))
        game = DemoGame(state: saved, rules: rules)
        requireEqual(game.state.eggGrade, 4)
        let before = game.state
        requireThrows(try game.upgrade(roll: 0, library: library)); requireEqual(game.state, before)
        _ = try game.consume(25_000_000, library: library, hatchCharacterID: "A401")
        requireEqual(game.state.desktopActionId, "B40101")
        requireEqual(game.eligibleCards(in: library).filter { $0.characterId == "A401" }.map(\.id), ["C40101SS"])
        requireEqual(game.state.collection, ["C10101": 1])
    }

    func testExpandedLibraryKeepsOldEggAndPossessions() throws {
        let (library, rules) = try resources()
        var old = try startedGame(library, rules)
        // Before this update the mouse finished at 60M and could already be incubating.
        _ = try old.consume(60_000_000, library: library)
        old.state.phase = .incubating
        old.state.incubationTokens = 49_999_999
        let saved = old.state
        var resumed = DemoGame(state: try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(saved)), rules: rules)
        requireEqual(resumed.state, saved)
        requireEqual(resumed.eligibleCards(in: library).map(\.id), ["C10101", "C10102", "C10103", "C10104"])
        _ = try resumed.consume(1, library: library, hatchCharacterID: "A303")
        requireEqual(resumed.state.activeCharacterId, "A303")
        requireEqual(resumed.state.characterProgress?["A101"], 60_000_000)
        requireEqual(resumed.state.collection, saved.collection)
        requireEqual(resumed.eligibleCards(in: library).filter { $0.characterId == "A303" }.map(\.id), ["C30301S"])
    }

    func testEveryBellyLaughUsesItsFixedHigherCard() throws {
        let (library, _) = try resources()
        let styles = [1: "普通卡", 2: "闪光卡", 3: "黑金卡", 4: "幻影卡"]
        for character in library.characters {
            let laugh = try requireValue(character.orderedFrames.first { $0.name == "捧腹大笑" })
            let card = try requireValue(laugh.cardId.flatMap { library.card($0) })
            requireEqual(card.characterId, character.id)
            requireEqual(card.actionId, laugh.id)
            requireEqual(card.style, styles[character.rarityCode])
        }
        let dragon = try requireValue(library.character("A301"))
        requireTrue(dragon.orderedFrames.prefix(4).allSatisfy { $0.cardId == nil })
    }

    func testOnboardingPersistsAndLegacySavesGetNoNewGifts() throws {
        let (library, rules) = try resources()
        var game = DemoGame(state: .liveInitial(), rules: rules)
        try game.chooseStarter(characterID: "A111", library: library)
        let decoded = try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(game.state))
        let resumed = DemoGame(state: decoded, rules: rules)
        requireEqual(resumed.state, game.state); requireEqual(resumed.onboardingStage, .starterCard)
        requireEqual(resumed.eligibleCards(in: library).map(\.id), ["C11101"])
        var legacy = DemoState(); legacy.onboarding = nil; legacy.starterCharacterId = nil
        let migrated = DemoGame(state: try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(legacy)), rules: rules)
        requireEqual(migrated.onboardingStage, .completed)
        requireEqual(migrated.state.collection, legacy.collection)
        requireEqual(migrated.state.ownedCharacterIds, legacy.ownedCharacterIds)
        requireEqual(migrated.state.coins, legacy.coins); requireEqual(migrated.state.freeDraws, legacy.freeDraws)
    }

    func testProductionGrowthBeyondOneBillionAndOverflowIsAtomic() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        for _ in 0..<10 { _ = try game.consume(100_000_000, library: library) }
        _ = try game.consume(1_000_000, library: library)
        requireEqual(game.state.totalTokens, 1_001_000_000)
        requireEqual(game.state.coins, 1_001); requireEqual(game.state.freeDraws, 10)
        let saved = try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(game.state))
        game = DemoGame(state: saved, rules: rules)
        _ = try game.consume(99_000_000, library: library)
        requireEqual(game.state.totalTokens, 1_100_000_000)
        requireEqual(game.state.coins, 1_100); requireEqual(game.state.freeDraws, 11)
        let before = game.state
        requireThrows(try game.consume(Int.max, library: library)); requireEqual(game.state, before)
        game.state.coins = Int.max
        let fullCoins = game.state
        requireThrows(try game.consume(1_000_000, library: library)); requireEqual(game.state, fullCoins)
        game.state.coins = 0; game.state.cultivationTokens = Int.max
        let fullCultivation = game.state
        requireThrows(try game.consume(1, library: library)); requireEqual(game.state, fullCultivation)
    }


    func testInventoryPurchaseAndUseAreSeparateTransactions() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        game.state.coins = 450
        let initialCards = game.state.collection
        try game.purchase(.milkCandy); try game.purchase(.milkStar); try game.purchase(.milkTicket)
        requireEqual(game.state.coins, 0)
        requireEqual(game.state.collection, initialCards)
        requireFalse(game.state.accelerated); requireEqual(game.state.eggGrade, 1)
        requireEqual(game.count(.milkCandy), 1); requireEqual(game.count(.milkStar), 1); requireEqual(game.count(.milkTicket), 1)
        let unavailable = game.state
        requireThrows(try game.use(.milkCandy, library: library)); requireEqual(game.state, unavailable)
        requireThrows(try game.use(.milkTicket, library: library, cardID: "C10201")); requireEqual(game.state, unavailable)
        try game.use(.milkTicket, library: library, cardID: "C10101")
        requireEqual(game.state.collection["C10101"], 2); requireEqual(game.count(.milkTicket), 0)
        requireEqual(game.state.freeDraws, 0); requireEqual(game.state.coins, 0)
        _ = try game.consume(80_000_000, library: library)
        try game.startWaitingEgg(library: library)
        let coins = game.state.coins
        try game.use(.milkCandy, library: library)
        requireEqual(game.state.incubationBonusTokens, 150); requireEqual(game.count(.milkCandy), 0); requireEqual(game.state.coins, coins)
        requireFalse(try game.use(.milkStar, library: library, roll: 0.9))
        requireEqual(game.state.eggGrade, 1); requireEqual(game.count(.milkStar), 0); requireEqual(game.state.coins, coins)
        game.state.coins = 200; try game.purchase(.milkStar)
        _ = try game.consume(10_000_000, library: library)
        let progress = game.eggProgress
        requireTrue(try game.use(.milkStar, library: library, roll: 0.1))
        requireEqual(game.state.eggGrade, 2); requireEqual(game.eggProgress, progress, accuracy: 0.000001)
        requireEqual(game.count(.milkStar), 0); requireEqual(game.state.coins, 10)
        game.state.inventory?[InventoryItem.milkTicket.rawValue] = Int.max; game.state.coins = 100
        let full = game.state
        requireThrows(try game.purchase(.milkTicket)); requireEqual(game.state, full)
    }

    func testDifficultyScalesAllTokenRequirements() throws {
        let (library, rules) = try resources()
        let mouse = try requireValue(library.character("A101"))
        for percent in [20, 100, 500] {
            var game = try startedGame(library, rules)
            try game.setDifficulty(percent, library: library)
            let action = 20_000_000 / 100 * percent
            let egg = 50_000_000 / 100 * percent
            requireEqual(game.threshold(at: 1), action); requireEqual(game.eggRequirement, egg)
            requireEqual(game.coinRequirement, 1_000_000 / 100 * percent)
            requireEqual(game.freeDrawRequirement, 100_000_000 / 100 * percent)
            _ = try game.consume(action - 1, library: library)
            requireFalse(game.unlocked(mouse.orderedFrames[1], character: mouse))
            _ = try game.consume(1, library: library)
            requireTrue(game.unlocked(mouse.orderedFrames[1], character: mouse))
            requireEqual(game.state.coins, 20)
            _ = try game.consume(action * 3, library: library)
            try game.startWaitingEgg(library: library)
            _ = try game.consume(egg - 1, library: library, hatchCharacterID: "A102")
            requireEqual(game.state.phase, .incubating)
            _ = try game.consume(1, library: library, hatchCharacterID: "A102")
            requireEqual(game.state.activeCharacterId, "A102")
            requireEqual(game.state.coins, 130); requireEqual(game.state.freeDraws, 1)
        }
    }

    func testDifficultyKeepsUnlocksAndRewardRemainders() throws {
        let (library, rules) = try resources()
        var game = try startedGame(library, rules)
        _ = try game.consume(20_000_000, library: library)
        let second = try requireValue(library.character("A101")).orderedFrames[1]
        try game.setDifficulty(500, library: library)
        requireTrue(game.unlocked(second, character: try requireValue(library.character("A101"))))
        requireEqual(game.state.coins, 20); requireEqual(game.state.freeDraws, 0)
        requireEqual(game.state.drawTokenRemainder, 100_000_000)
        try game.setDifficulty(20, library: library)
        requireEqual(game.state.drawTokenRemainder, 4_000_000)
        _ = try game.consume(16_000_000, library: library)
        requireEqual(game.state.freeDraws, 1); requireEqual(game.state.coins, 100)
        let before = game.state
        requireThrows(try game.setDifficulty(19, library: library))
        requireThrows(try game.setDifficulty(501, library: library)); requireEqual(game.state, before)
        game.state.language = "en"
        let saved = try JSONDecoder().decode(DemoState.self, from: JSONEncoder().encode(game.state))
        let restored = DemoGame(state: saved, rules: rules)
        requireEqual(restored.state, game.state)
        #if DEBUG
        let replay = try DevelopmentSimulation.replaying(4_000_000, from: game, library: library)
        requireEqual(replay.difficulty, 20); requireEqual(replay.state.language, "en")
        requireEqual(replay.state.coins, 20)
        let reset = DevelopmentSimulation.resetting(rules: rules)
        requireEqual(reset.difficulty, 100); requireEqual(reset.state.inventory, [:])
        #endif
    }

    func testLegacyMigrationAddsNoInventoryAndKeepsCredit() throws {
        let (library, rules) = try resources()
        var old = try startedGame(library, rules).state
        old.totalTokens = 1_500_001; old.coins = 99
        var json = try requireValue(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["inventory", "difficultyPercent", "language", "coinTokenRemainder", "drawTokenRemainder"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(DemoState.self, from: JSONSerialization.data(withJSONObject: json))
        var migrated = DemoGame(state: decoded, rules: rules)
        requireEqual(migrated.state.coins, 99); requireEqual(migrated.state.inventory, [:])
        requireEqual(migrated.difficulty, 100); requireEqual(migrated.state.language, "zh-Hans")
        _ = try migrated.consume(499_999, library: library)
        requireEqual(migrated.state.coins, 100)
        requireEqual(migrated.state.coinTokenRemainder, 0)
    }

    func testAllHundredAnimationsUseRecordedFrameTiming() throws {
        let (library, _) = try resources()
        let project = assetRoot
        var count = 0; var frames = 0
        for character in library.characters {
            for frame in character.orderedFrames {
                guard let path = frame.animation else {
                    requireTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent(frame.file).path))
                    continue
                }
                let animation = try AnimationAsset.load(from: project.appendingPathComponent(path))
                requireEqual(animation.actionId, frame.id); count += 1; frames += animation.frameCount
                var elapsed = 0
                for index in animation.frames.indices {
                    requireTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent(animation.frames[index].file).path))
                    requireEqual(animation.frameIndex(elapsed: Double(elapsed) / 1000 + 0.000001), index)
                    elapsed += animation.frameDurationsMs[index]
                }
                requireEqual(animation.frameIndex(elapsed: Double(elapsed) / 1000), animation.loop ? 0 : animation.frames.count - 1)
                requireEqual(animation.frameIndex(elapsed: .infinity), 0)
            }
        }
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: project.appendingPathComponent("运行资源清单.json"))) as! [String: Any]
        requireEqual(count, index["animations"] as! Int); requireEqual(frames, index["frames"] as! Int)
        requireTrue(count >= 134); requireTrue(frames >= 702)
    }

    #if DEBUG
    func testDeveloperReplayUsesExactProductionPathAndChosenPartner() throws {
        let (library, rules) = try resources()
        let initial = try startedGame(library, rules, id: "A108")
        var normal = initial
        _ = try normal.consume(100_000_000, library: library)
        _ = try normal.consume(20_000_000, library: library)
        let replayed = try DevelopmentSimulation.replaying(120_000_000, from: initial, library: library)
        requireEqual(replayed.state, normal.state)
        requireEqual(replayed.state.activeCharacterId, "A108")
        requireEqual(replayed.state.collection, ["C10801": 1]); requireEqual(replayed.state.freeDraws, 1)
        let low = try DevelopmentSimulation.replaying(999_999, from: replayed, library: library)
        requireEqual(low.state.awardedActions, ["B10801"]); requireEqual(low.state.coins, 0)
        let reset = DevelopmentSimulation.resetting(rules: rules)
        requireEqual(reset.state.ownedCharacterIds, []); requireEqual(reset.state.collection, [:])
        requireThrows(try DevelopmentSimulation.adding(1_000_000, to: reset, library: library))
    }

    func testDeveloperHatchUsesProductionAndKeepsEarlierPartner() throws {
        let (library, rules) = try resources()
        let initial = try startedGame(library, rules)
        var manual = initial
        _ = try manual.consume(80_000_000, library: library)
        try manual.startWaitingEgg(library: library)
        var automated = try DevelopmentSimulation.preparingIncubation(initial, library: library)
        requireEqual(automated.state, manual.state)
        let remaining = try DevelopmentSimulation.tokensToFinishStage(automated, library: library)
        requireEqual(remaining, 50_000_000)
        _ = try manual.consume(remaining, library: library, hatchCharacterID: "A201")
        automated = try DevelopmentSimulation.adding(remaining, to: automated, library: library, hatchCharacterID: "A201")
        requireEqual(automated.state, manual.state)
        requireEqual(automated.state.ownedCharacterIds, ["A101", "A201"])
        requireEqual(automated.state.collection, ["C10101": 1])
        requireEqual(try DevelopmentSimulation.tokensToFinishStage(automated, library: library), 100_000_000)
    }

    func testDeveloperRejectsInvalidInputsAndSplitsLargeIncrement() throws {
        let (library, rules) = try resources()
        let game = try startedGame(library, rules)
        requireThrows(try DevelopmentSimulation.adding(-1, to: game, library: library))
        let large = try DevelopmentSimulation.adding(250_000_000, to: game, library: library)
        requireEqual(large.state.totalTokens, 250_000_000); requireEqual(large.state.coins, 250)
        requireEqual(large.state.freeDraws, 2); requireEqual(large.state.collection, ["C10101": 1])
        requireEqual(game.state.totalTokens, 0)
        let billion = try DevelopmentSimulation.replaying(1_000_000_000, from: game, library: library)
        let beyond = try DevelopmentSimulation.adding(1_000_000, to: billion, library: library)
        requireEqual(beyond.state.totalTokens, 1_001_000_000)
        requireEqual(beyond.state.coins, 1_001); requireEqual(beyond.state.freeDraws, 10)
        let further = try DevelopmentSimulation.adding(999_000_000, to: beyond, library: library)
        requireEqual(further.state.totalTokens, 2_000_000_000)
        requireEqual(further.state.coins, 2_000); requireEqual(further.state.freeDraws, 20)
        let high = try DevelopmentSimulation.replaying(1_500_000_000, from: game, library: library)
        requireEqual(high.state.totalTokens, 1_500_000_000)
        let maximum = try DevelopmentSimulation.replaying(Int.max, from: game, library: library)
        requireEqual(maximum.state.totalTokens, Int.max)
        requireEqual(maximum.state.coins, Int.max / rules.tokensPerCoin)
        requireEqual(maximum.state.freeDraws, Int.max / rules.freeDrawThreshold)
        requireThrows(try DevelopmentSimulation.adding(1, to: maximum, library: library))
    }

    func testDeveloperTokenInputIsExactAboveOldLimit() throws {
        requireEqual(DevelopmentSimulation.parseTokens("1001M"), 1_001_000_000)
        requireEqual(DevelopmentSimulation.parseTokens("1.5B"), 1_500_000_000)
        requireEqual(DevelopmentSimulation.parseTokens(" 2,000,000,000 "), 2_000_000_000)
        requireEqual(DevelopmentSimulation.parseTokens("1.25K"), 1_250)
        requireEqual(DevelopmentSimulation.parseTokens("0.000001M"), 1)
        requireEqual(DevelopmentSimulation.parseTokens(String(Int.max)), Int.max)
        requireEqual(DevelopmentSimulation.parseTokens("9223372036854.775807M"), Int.max)
        for invalid in ["-1", "NaN", "infM", "", "0.0000001M", "9223372036854775808", "9223372036854.775808M"] {
            requireNil(DevelopmentSimulation.parseTokens(invalid))
        }
    }

    func testLargeDeveloperHatchMatchesProductionBatches() throws {
        let (library, rules) = try resources()
        var initial = try startedGame(library, rules)
        _ = try initial.consume(80_000_000, library: library)
        try initial.startWaitingEgg(library: library)
        initial.state.inventory?[InventoryItem.milkCandy.rawValue] = 1
        try initial.use(.milkCandy, library: library)
        var normal = initial
        for _ in 0..<12 { _ = try normal.consume(100_000_000, library: library, hatchCharacterID: "A401") }
        let fast = try DevelopmentSimulation.adding(1_200_000_000, to: initial, library: library, hatchCharacterID: "A401")
        requireEqual(fast.state, normal.state)
        requireEqual(fast.state.activeCharacterId, "A401")
        requireEqual(fast.state.collection, ["C10101": 1])
    }
    #endif
}

private extension DemoGame {
    var gameProgressForTest: Double { eggProgress }
}

private var failures: [String] { get { CheckLog.shared.messages } set { CheckLog.shared.messages = newValue } }
private final class CheckLog: @unchecked Sendable {
    static let shared = CheckLog()
    var messages: [String] = []
}
private func requireEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a != b { CheckLog.shared.messages.append("\(file):\(line) expected \(b), got \(a)") }
}
private func requireEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    if abs(a - b) > accuracy { CheckLog.shared.messages.append("\(file):\(line) fraction mismatch") }
}
private func requireNotEqual<T: Equatable>(_ a: T, _ b: T) { if a == b { CheckLog.shared.messages.append("Expected different values") } }
private func requireTrue(_ value: Bool) { if !value { CheckLog.shared.messages.append("Expected true") } }
private func requireFalse(_ value: Bool) { if value { CheckLog.shared.messages.append("Expected false") } }
private func requireNil<T>(_ value: T?) { if value != nil { CheckLog.shared.messages.append("Expected nil") } }
private func requireThrows<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); CheckLog.shared.messages.append("Expected an error") } catch {}
}
private func requireValue<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "NaijiaChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Required asset missing"]) }
    return value
}
@main
struct CheckRunner {
    static func main() {
        let suite = PreviewTests()
        var checks: [(String, () throws -> Void)] = [
            ("新存档英文、旧语言与日志保持", suite.testNewDefaultsKeepExistingLanguagesAndLedgers),
            ("奶糖独立150进度、连续使用及孵化边界", suite.testCandyBonusFinishesEggWithoutMintingUsage),
            ("重复孵化递减、权重下限及稀有度概率保持", suite.testRepeatHatchesPreserveRaritySharesAndFloor),
            ("100%刻度、商品价格及多屏边缘拖动", suite.testDifficultyTrackPricesAndPetEdges),
            ("道具购买入库、手动使用与失败原子性", suite.testInventoryPurchaseAndUseAreSeparateTransactions),
            ("20%/100%/500%成长、孵化与奖励倍率", suite.testDifficultyScalesAllTokenRequirements),
            ("难度切换保留解锁、奖励余量和语言", suite.testDifficultyKeepsUnlocksAndRewardRemainders),
            ("旧存档迁移不赠道具、保留奖励余量", suite.testLegacyMigrationAddsNoInventoryAndKeepsCredit),
            ("全部已登记动画按真实帧数和时长播放", suite.testAllHundredAnimationsUseRecordedFrameTiming),
            ("正式数值、固定编号与可变动作数量", suite.testRealAssetMappingsAndVariableActionCounts),
            ("首次与重置在选择前不赠送任何物品", suite.testFreshAndResetStatesHaveNoGiftsBeforeChoice),
            ("全部19位普通伙伴均只赠待机与一次抽卡", suite.testEveryCommonPartnerGivesOnlyIdleAndOneDraw),
            ("初始选择拒绝稀有人物且不可重复领取", suite.testStarterChoiceRejectsRareAndCannotRepeat),
            ("首次抽卡必须点击且只能得到所选待机卡", suite.testTutorialMustBeClickedBeforeGrowthAndOnlyIdleCanDraw),
            ("20M动作边界与只开放卡池不自动送卡", suite.testActionThresholdUnlocksWithoutGivingCard),
            ("1M奶币与100M免费次数边界和余量", suite.testCurrencyAndFreeDrawBoundariesKeepRemainders),
            ("抽卡扣款、重复卡累计与非法抽卡无副作用", suite.testDrawChargesOnceAndCannotUnlockOthers),
            ("50M孵化、保留伙伴且不赠送孵化卡", suite.testWaitingEggAndFiftyMillionHatchDoNotGiveCards),
            ("升级保留比例、奶糖不修改真实Token奖励", suite.testUpgradeAndAccelerationKeepRealTokenRewards),
            ("首次流程持久化且旧存档不重复领礼物", suite.testOnboardingPersistsAndLegacySavesGetNoNewGifts),
            ("32人物179动作175卡固定分配与踩奶默认动作", suite.testNewCharacterMappingsAndFirstPose),
            ("全部伙伴孵化、逐动作解锁与卡片固定分配", suite.testAllNewCharactersHatchAndUnlockOnlyTheirFixedCards),
            ("史诗升传说、存档往返与踩奶卡资格", suite.testLegendaryUpgradeAndStateRoundTrip),
            ("素材扩容保留旧孵蛋、进度与收藏", suite.testExpandedLibraryKeepsOldEggAndPossessions),
            ("32位捧腹大笑固定卡等级与暂缓卡边界", suite.testEveryBellyLaughUsesItsFixedHigherCard),
            ("用户成长超过1000M、重启与溢出无副作用", suite.testProductionGrowthBeyondOneBillionAndOverflowIsAtomic)
        ]
        #if DEBUG
        checks += [
            ("开发重演与正式一致并保留所选普通伙伴", suite.testDeveloperReplayUsesExactProductionPathAndChosenPartner),
            ("开发孵化与正式一致且六动作门槛正确", suite.testDeveloperHatchUsesProductionAndKeepsEarlierPartner),
            ("测试累计突破1000M及大数追加奖励", suite.testDeveloperRejectsInvalidInputsAndSplitsLargeIncrement),
            ("整数与K、M、B大数输入不丢精度", suite.testDeveloperTokenInputIsExactAboveOldLimit),
            ("大数测试孵化与正式分批成长一致", suite.testLargeDeveloperHatchMatchesProductionBatches)
        ]
        #endif
        for (name, check) in checks {
            let before = failures.count
            do { try check() } catch { CheckLog.shared.messages.append(error.localizedDescription) }
            print("\(failures.count == before ? "PASS" : "FAIL") \(name)")
        }
        if !failures.isEmpty { failures.forEach { print($0) }; exit(1) }
        print("\(checks.count) 项行为检查全部通过")
    }
}
