import SwiftUI
import NaijiaCore

struct StarterSelectionPane: View {
    @ObservedObject var store: AppStore
    @State private var selectedID: String?
    @State private var choosing = false
    @State private var confirmation: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: CharacterAsset? { store.starterChoices.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("选择伙伴")).font(.system(size: 16, weight: .semibold))
                Text(L("普通伙伴 · 待机＋1 次抽卡")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ZStack {
                Rectangle().fill(.secondary.opacity(0.035))
                if let selected {
                    PixelSparkles(active: true, reducedMotion: reduceMotion).allowsHitTesting(false)
                    HStack(spacing: 18) {
                        Sprite(store: store, file: selected.idle.file, animated: true).frame(width: 82, height: 84)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(L(selected.name)).font(.system(size: 17, weight: .semibold))
                            Badge(text: L("普通"))
                        }
                    }
                    .id(selected.id).transition(UIMotion.pop(reduced: reduceMotion))
                } else {
                    VStack(spacing: 8) {
                        LockedPixel().frame(width: 48, height: 52)
                        Text(L("请选择")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }.frame(height: 92).overlay(Rectangle().strokeBorder(.secondary.opacity(0.15), lineWidth: 0.5))
                .animation(UIMotion.detail(reduceMotion), value: selectedID)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(store.starterChoices) { character in
                    let isSelected = selectedID == character.id
                    Button { selectedID = character.id } label: {
                        VStack(spacing: 3) {
                            Sprite(store: store, file: character.idle.file).frame(height: 43)
                            Text(L(character.name)).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                        }.padding(5).frame(maxWidth: .infinity)
                            .background(.secondary.opacity(isSelected ? 0.13 : 0.05), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                if isSelected { Rectangle().fill(.primary).frame(width: 4, height: 4).padding(4) }
                            }
                    }.buttonStyle(SoftPressButtonStyle()).disabled(choosing)
                        .accessibilityLabel(L("选择\(character.name)，普通伙伴"))
                }
            }
            Button {
                guard let selected else { return }
                choosing = true
                confirmation = Task { @MainActor in
                    if !reduceMotion { try? await Task.sleep(for: .milliseconds(450)) }
                    guard !Task.isCancelled else { return }
                    store.chooseStarter(selected)
                    choosing = false
                }
            } label: {
                Text(L(choosing ? "确认中…" : (selected.map { "选择\($0.name)" } ?? "选择伙伴")))
                    .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.bordered).disabled(selected == nil || choosing)
        }
        .onDisappear { confirmation?.cancel() }
    }
}

struct StarterShopGuide: View {
    let onOpenShop: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            PixelSparkles(active: true).frame(width: 28, height: 32).allowsHitTesting(false)
            Text(L("领取待机卡")).font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 0)
            Button(L("去小铺"), action: onOpenShop).buttonStyle(.bordered).controlSize(.small)
        }.padding(8).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Four-pixel steps and square particles keep movement consistent with the existing sprites.
struct PixelSparkles: View {
    var active: Bool
    var reducedMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active || reducedMotion || systemReduceMotion)) { timeline in
            Canvas { context, size in
                let step = reducedMotion || systemReduceMotion ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate * 8) % 6
                let points: [(Double, Double)] = [(0.12, 0.26), (0.83, 0.20), (0.21, 0.77), (0.88, 0.71), (0.51, 0.13), (0.62, 0.86)]
                for (index, point) in points.enumerated() {
                    let phase = (step + index) % 6
                    let x = (size.width * point.0 / 4).rounded() * 4
                    let y = (size.height * point.1 / 4).rounded() * 4 - Double(phase) * 4
                    let side: Double = phase < 3 ? 4 : 2
                    context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color((index % 2 == 0 ? mint : .yellow).opacity(phase < 4 ? 0.7 : 0.25)))
                }
            }
        }.accessibilityHidden(true)
    }
}
