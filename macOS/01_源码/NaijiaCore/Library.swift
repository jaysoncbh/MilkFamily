import Foundation

public struct AssetLibrary: Decodable, Sendable {
    public let characters: [CharacterAsset]
    public let cards: [CardAsset]

    public func character(_ id: String) -> CharacterAsset? { characters.first { $0.id == id } }
    public func card(_ id: String) -> CardAsset? { cards.first { $0.id == id } }

    /// Validate a replacement before changing the active library or dropping its image cache.
    public func validateRuntimeResources(at root: URL) throws {
        let base = root.standardizedFileURL
        func resource(_ path: String) throws -> URL {
            let url = base.appendingPathComponent(path).standardizedFileURL
            guard url.path.hasPrefix(base.path + "/"), FileManager.default.isReadableFile(atPath: url.path) else {
                throw LibraryError.missingResource(path)
            }
            return url
        }
        for character in characters {
            for frame in character.orderedFrames {
                _ = try resource(frame.file)
                if let path = frame.animation {
                    let animation = try AnimationAsset.load(from: resource(path))
                    guard animation.actionId == frame.id else { throw LibraryError.missingResource(path) }
                    for item in animation.frames { _ = try resource(item.file) }
                }
            }
        }
        for card in cards { _ = try resource(card.file) }
        for item in InventoryItem.allCases { _ = try resource(item.imagePath) }
    }

    public static func load(from url: URL) throws -> AssetLibrary {
        let library = try JSONDecoder().decode(AssetLibrary.self, from: Data(contentsOf: url))
        guard !library.characters.isEmpty else { throw LibraryError.empty }
        guard Set(library.characters.map(\.id)).count == library.characters.count,
              Set(library.cards.map(\.id)).count == library.cards.count,
              Set(library.characters.flatMap { $0.orderedFrames.map(\.id) }).count == library.characters.reduce(0, { $0 + $1.orderedFrames.count }) else { throw LibraryError.duplicate }
        for character in library.characters {
            guard !character.poseOrder.isEmpty,
                  Set(character.poseOrder).count == character.poseOrder.count,
                  character.poseOrder.allSatisfy({ character.frames[$0] != nil }) else {
                throw LibraryError.invalidPoseOrder(character.id)
            }
            for frame in character.orderedFrames {
                if let cardID = frame.cardId {
                    guard let card = library.card(cardID), card.actionId == frame.id,
                          card.characterId == character.id, card.style == frame.cardStyle else {
                        throw LibraryError.invalidCardMapping(frame.id)
                    }
                }
            }
        }
        return library
    }
}

public struct CharacterAsset: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let rarityCode: Int
    public let rarity: String
    public let aliases: [String]?
    public let poseOrder: [String]
    public let frames: [String: FrameAsset]
    public var orderedFrames: [FrameAsset] { poseOrder.compactMap { frames[$0] } }
    public var idle: FrameAsset { orderedFrames[0] }
}

public struct FrameAsset: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let file: String
    public let original: String
    public let cardId: String?
    public let cardStyle: String?
    public let cardFile: String?
    public let animation: String?
}

public struct AnimationAsset: Decodable, Sendable {
    public struct Frame: Decodable, Sendable { public let file: String }
    public let actionId: String
    public let frameCount: Int
    public let frameDurationsMs: [Int]
    public let loop: Bool
    public let frames: [Frame]

    public static func load(from url: URL) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.frameCount > 0, value.frames.count == value.frameCount,
              value.frameDurationsMs.count == value.frameCount,
              value.frameDurationsMs.allSatisfy({ (16...10_000).contains($0) }) else { throw LibraryError.empty }
        return value
    }

    public func frameIndex(elapsed: Double) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        let total = Double(frameDurationsMs.reduce(0, +))
        let milliseconds = elapsed * 1000
        guard milliseconds.isFinite else { return frames.count - 1 }
        if !loop && milliseconds >= total { return frames.count - 1 }
        var remaining = milliseconds.truncatingRemainder(dividingBy: total)
        for (index, duration) in frameDurationsMs.enumerated() {
            if remaining < Double(duration) { return index }
            remaining -= Double(duration)
        }
        return 0
    }
}

public struct CardAsset: Decodable, Identifiable, Sendable {
    public let id: String
    public let characterId: String
    public let actionId: String
    public let actionName: String
    public let name: String
    public let rarity: String
    public let style: String
    public let file: String
    public let gamePoolOpen: Bool
}

public enum LibraryError: LocalizedError {
    case empty, duplicate, invalidPoseOrder(String), invalidCardMapping(String), missingResource(String)
    public var errorDescription: String? {
        switch self {
        case .empty: "人物清单为空"
        case .duplicate: "素材编号重复"
        case .invalidPoseOrder(let id): "\(id) 的动作顺序无效"
        case .invalidCardMapping(let id): "\(id) 的卡片分配不一致"
        case .missingResource(let path): "素材包不完整，缺少：\(path)"
        }
    }
}
