import SwiftUI
import UIKit

/// Keep the old/new-value semantics used by the app on iOS 16.
private struct ChangeObserver<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void
    @State private var previous: Value
    @State private var appeared = false

    init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
        self.value = value; self.initial = initial; self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onAppear {
            guard !appeared else { return }
            appeared = true
            previous = value
            if initial { action(value, value) }
        }.onChange(of: value) { next in
            let old = previous
            previous = next
            action(old, next)
        }
    }
}

extension View {
    func onChangeCompat<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(ChangeObserver(value: value, initial: initial, action: action))
    }
    func onChangeCompat<V: Equatable>(of value: V, _ action: @escaping () -> Void) -> some View {
        onChangeCompat(of: value) { _, _ in action() }
    }
    @ViewBuilder func presentationBackgroundCompat(_ color: Color) -> some View {
        if #available(iOS 16.4, *) { presentationBackground(color) }
        else { background(color) }
    }
    @ViewBuilder func presentationCornerRadiusCompat(_ radius: CGFloat) -> some View {
        if #available(iOS 16.4, *) { presentationCornerRadius(radius) }
        else { self }
    }
    @ViewBuilder func defaultScrollAnchorCompat(_ anchor: UnitPoint?) -> some View {
        if #available(iOS 17.0, *) { defaultScrollAnchor(anchor) }
        else { self }
    }
    @ViewBuilder func scrollBounceBasedOnSize(axes: Axis.Set = .vertical) -> some View {
        if #available(iOS 16.4, *) { scrollBounceBehavior(.basedOnSize, axes: axes) }
        else { self }
    }
}

struct UnavailableStateView<Title: View, Detail: View, Actions: View>: View {
    let title: Title
    let detail: Detail
    let actions: Actions
    init(@ViewBuilder label: () -> Title, @ViewBuilder description: () -> Detail, @ViewBuilder actions: () -> Actions) {
        title = label(); detail = description(); self.actions = actions()
    }
    var body: some View {
        VStack(spacing: 14) {
            title.font(.title3.weight(.semibold))
            detail.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension UnavailableStateView where Title == Label<Text, Image>, Detail == Text?, Actions == EmptyView {
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = Label(title, systemImage: systemImage)
        detail = description; actions = EmptyView()
    }
    static func search(text: String) -> Self {
        Self("没有搜索结果", systemImage: "magnifyingglass", description: Text("未找到与“\(text)”匹配的内容"))
    }
}

/// Unequal corner radii without the iOS 17 UnevenRoundedRectangle type.
struct CornerRectangle: Shape {
    var topLeadingRadius: CGFloat = 0
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0
    var topTrailingRadius: CGFloat = 0
    var style: RoundedCornerStyle = .continuous
    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let tl = min(limit, max(0, topLeadingRadius)), tr = min(limit, max(0, topTrailingRadius))
        let bl = min(limit, max(0, bottomLeadingRadius)), br = min(limit, max(0, bottomTrailingRadius))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Measures content in its own scroll viewport; supports refreshable and ScrollViewReader.
struct OffsetScrollView<Content: View>: View {
    var onOffsetChange: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content
    @State private var coordinateID = UUID()
    var body: some View {
        ScrollView {
            content().background {
                GeometryReader { geometry in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: -geometry.frame(in: .named(coordinateID)).minY)
                }
            }
        }
        .coordinateSpace(name: coordinateID)
        .onPreferenceChange(ScrollOffsetKey.self, perform: onOffsetChange)
    }
}


@MainActor
private enum SwitchFeedback {
    static var lastImpact = -Double.infinity

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastImpact >= 0.15 else { return }
        lastImpact = now
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

extension Binding where Value: Equatable {
    @MainActor
    private func withFeedback(_ style: @escaping (Value) -> UIImpactFeedbackGenerator.FeedbackStyle) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { value, transaction in
            guard wrappedValue != value else { return }
            self.transaction(transaction).wrappedValue = value
            SwitchFeedback.impact(style(value))
        })
    }

    @MainActor
    func withSelectionFeedback() -> Binding<Value> { withFeedback { _ in .light } }

    @MainActor
    func withSwitchFeedback() -> Binding<Value> where Value == Bool {
        withFeedback { $0 ? .medium : .light }
    }
}
