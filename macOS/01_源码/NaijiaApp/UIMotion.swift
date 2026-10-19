import AppKit
import QuartzCore
import SwiftUI

/// Short transitions for the compact panel; pixel art retains its original frame timing.
enum UIMotion {
    static let navigationDuration = 0.22
    static let presentationDuration = 0.24
    static let dismissalDuration = 0.14
    static func navigation(_ reduced: Bool) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: reduced ? 0.12 : navigationDuration)
    }
    static func detail(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88)
    }
    static func feedback(_ reduced: Bool) -> Animation { .easeOut(duration: reduced ? 0.08 : 0.12) }
    static func page(forward: Bool = true, reduced: Bool) -> AnyTransition {
        let d: CGFloat = reduced ? 0 : 12
        return .asymmetric(
            insertion: .modifier(active: MotionPresence(progress: 0, x: forward ? d : -d), identity: MotionPresence(progress: 1)),
            removal: .modifier(active: MotionPresence(progress: 0, x: forward ? -d * 0.6 : d * 0.6), identity: MotionPresence(progress: 1)))
    }
    static func pop(reduced: Bool) -> AnyTransition {
        .modifier(active: MotionPresence(progress: 0, y: reduced ? 0 : 10, initialScale: reduced ? 1 : 0.98), identity: MotionPresence(progress: 1))
    }
    static func toast(reduced: Bool) -> AnyTransition {
        .asymmetric(insertion: .modifier(active: MotionPresence(progress: 0, y: reduced ? 0 : 6), identity: MotionPresence(progress: 1)), removal: .opacity)
    }
}

/// Shared by native transitions and the offscreen motion review.
struct MotionPresence: AnimatableModifier {
    var progress: Double
    var x: CGFloat = 0
    var y: CGFloat = 0
    var initialScale: CGFloat = 1
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(min(1, max(0, progress)))
            .offset(x: x * (1 - progress), y: y * (1 - progress))
            .scaleEffect(initialScale + (1 - initialScale) * progress)
    }
}

struct SoftPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.8 : 1)
            .animation(UIMotion.feedback(reduceMotion), value: configuration.isPressed)
    }
}

/// Desired state stays reliable when the user reopens a window during its fade-out.
@MainActor
final class SidebarPresentation {
    private(set) var isPresented = false
    private var generation = 0
    private let reducedMotion: () -> Bool
    init(reducedMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reducedMotion = reducedMotion
    }
    func show(_ window: NSWindow) {
        generation += 1; isPresented = true
        window.ignoresMouseEvents = false
        if !window.isVisible { window.alphaValue = 0 }
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion() ? 0.1 : UIMotion.presentationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            window.animator().alphaValue = 1
        }
    }
    func hide(_ window: NSWindow) {
        guard isPresented else { return }
        generation += 1
        let expectedGeneration = generation
        isPresented = false; window.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion() ? 0.1 : UIMotion.dismissalDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window, self.generation == expectedGeneration, !self.isPresented else { return }
                window.orderOut(nil); window.alphaValue = 1; window.ignoresMouseEvents = false
            }
        }
    }
    func resize(_ window: NSWindow, to frame: NSRect) {
        guard !window.frame.equalTo(frame) else { return }
        guard isPresented, window.isVisible, !reducedMotion() else {
            window.setFrame(frame, display: true); return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = UIMotion.navigationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            window.animator().setFrame(frame, display: true)
        }
    }
}
