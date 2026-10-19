import AppKit
import SwiftUI
import NaijiaCore

// Explicit allowlist: sharing a material implementation never enables another card.
struct InteractiveCard: View {
    static let sampleIDs = ["C20102S", "C20103S", "C20205S", "C20206S", "C20305S", "C20306S", "C20405S", "C20406S", "C30201S", "C30202S", "C30203S", "C30204SS", "C30205S", "C30206SS", "C40101SS", "C40102SS", "C40103SS", "C40104SS", "C40105SSS", "C40106SSS"]
    @ObservedObject var store: AppStore
    let card: CardAsset
    var staticOnly = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var point = CGPoint.zero
    @State private var appeared = false
    @State private var config: CardMotionConfig?
    @State private var material: NSImage?
    @State private var background: NSImage?
    @State private var skyTexture: NSImage?
    @State private var started = Date()
    private var enabled: Bool { appeared && store.panelVisible && !reduceMotion && !staticOnly && config != nil && material != nil && background != nil && (config?.starTexture == nil || skyTexture != nil) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / (config?.fps ?? 30), paused: !enabled)) { clock in
            CardMotionFace(image: store.image(card.file), config: config,
                           material: material, background: background,
                           time: enabled ? clock.date.timeIntervalSince(started) : 0,
                           x: enabled ? point.x : 0, y: enabled ? point.y : 0, enabled: enabled, skyTexture: skyTexture)
                .rotation3DEffect(.degrees(enabled ? -point.y * (config?.tiltDegrees ?? 6) : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(enabled ? point.x * (config?.tiltDegrees ?? 6) : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        }
        .frame(width: 288, height: 432)
        .overlay { CardPointer { position in
            guard enabled else { return }
            withAnimation(.easeOut(duration: position == .zero ? (config?.returnSeconds ?? 0.28) : 0.10)) { point = position }
        } }
        .padding(12).frame(maxWidth: .infinity)
        .onAppear { appeared = true; load(); started = Date() }
        .onDisappear { appeared = false; point = .zero; config = nil; material = nil; background = nil; skyTexture = nil }
        .onChange(of: card.id) { _, _ in point = .zero; load(); started = Date() }
        .onChange(of: enabled) { _, active in if !active { point = .zero } }
        .accessibilityLabel(L("\(card.name)，\(card.actionName)，\(card.id)"))
    }
    private func load() {
        config = nil; material = nil; background = nil; skyTexture = nil
        guard Self.sampleIDs.contains(card.id) else { return }
        let base = "07_软件开发/macOS/07_卡片动态素材/\(card.style)/\(card.id)/"
        guard let data = try? Data(contentsOf: store.projectRoot.appendingPathComponent(base + "动态配置.json")),
              let value = try? JSONDecoder().decode(CardMotionConfig.self, from: data),
              value.version == 1, value.cardId == card.id, value.style == card.style,
              (0...8).contains(value.tiltDegrees), (1...60).contains(value.fps),
              (0.05...1).contains(value.returnSeconds), (0...1).contains(value.foilOpacity),
              (1...30).contains(value.sparklePeriod), (0...12).contains(value.sparkleCount),
              value.layers.count == 3, value.layers.allSatisfy({ (0...320).contains($0.count) && abs($0.speed) <= 0.25 && abs($0.parallax) <= 0.2 && (0...1).contains($0.opacity) }),
              [(value.metalContrast ?? 0), (value.specularStrength ?? 0), (value.glintStrength ?? 0), (value.portalDepth ?? 0)].allSatisfy({ (0...1).contains($0) }),
              (0...0.5).contains(value.portalScaleSpan ?? 0), (0...0.25).contains(value.portalDrift ?? 0), (0...8).contains(value.portalNearSize ?? 0),
              value.materialMask.hasPrefix(base), value.backgroundMask.hasPrefix(base),
              let m = store.image(value.materialMask), let b = store.image(value.backgroundMask) else { return }
        if let path = value.starTexture {
            guard value.style == "幻影卡", path.hasPrefix(base), !path.contains(".."),
                  let texture = store.image(path),
                  (0...48).contains(value.gemCount ?? 0), (0...1).contains(value.gemStrength ?? 0),
                  (0...0.2).contains(value.skyRotation ?? 0) else { return }
            skyTexture = texture
        }
        config = value; material = m; background = b
    }
}

private struct CardPointer: NSViewRepresentable {
    let moved: (CGPoint) -> Void
    func makeNSView(context: Context) -> PointerView { let view = PointerView(); view.moved = moved; return view }
    func updateNSView(_ view: PointerView, context: Context) { view.moved = moved }
    final class PointerView: NSView {
        var moved: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        private func update(_ event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            moved?(CGPoint(x: max(-1, min(1, p.x / max(1,bounds.width) * 2 - 1)), y: max(-1, min(1,p.y / max(1,bounds.height) * 2 - 1))))
        }
        override func mouseMoved(with event: NSEvent) { update(event) }
        override func mouseEntered(with event: NSEvent) { update(event) }
        override func mouseDown(with event: NSEvent) { update(event) }
        override func mouseDragged(with event: NSEvent) { update(event) }
        override func mouseUp(with event: NSEvent) { moved?(.zero) }
        override func mouseExited(with event: NSEvent) { moved?(.zero) }
    }
}

#if DEBUG
struct CardSamplesPane: View {
    @ObservedObject var store: AppStore
    let onClose: () -> Void
    @State private var selected = "C30201S"
    @State private var staticOnly = false
    @State private var style = "闪光卡"
    private var reviewCards: [CardAsset] { store.library.cards.filter { $0.style == style && InteractiveCard.sampleIDs.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button(action: onClose) { Label(L("返回"), systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Toggle(L("静态"), isOn: $staticOnly).toggleStyle(.checkbox).font(.system(size: 10))
            }
            Picker(L("样卡样式"), selection: $style) {
                ForEach(["闪光卡", "黑金卡", "幻影卡"], id: \.self) { value in Text(L(value)).tag(value) }
            }.pickerStyle(.segmented).labelsHidden()
                .onChange(of: style) { _, _ in selected = reviewCards.first?.id ?? "C30201S" }
            Picker(L("卡片"), selection: $selected) {
                ForEach(reviewCards) { card in Text(L("\(card.name) · \(card.actionName)")).tag(card.id) }
            }.labelsHidden().controlSize(.small)
            if let card = store.library.card(selected) {
                InteractiveCard(store: store, card: card, staticOnly: staticOnly).id(selected)
                HStack {
                    Text(card.id).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("原图")) { NSWorkspace.shared.open(store.projectRoot.appendingPathComponent(card.file)) }.buttonStyle(.plain)
                }
            }
            Text(L("已确认模板 · 全部高级卡动态审查")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
#endif
