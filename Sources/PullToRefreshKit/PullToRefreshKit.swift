import SwiftUI

/// Describes the visual lifecycle of a custom pull-to-refresh interaction.
///
/// Use this state inside the `refreshContent` builder to render your own indicator.
/// The component transitions through these cases as the user pulls, releases,
/// waits for loading to finish, and returns to the resting state.
public enum PullToRefreshScrollViewState: Equatable {
    /// The scroll view is at rest and no indicator should be visible.
    case idle
    /// The user is pulling down but has not yet reached the refresh threshold.
    ///
    /// The associated `progress` value is normalized to the `0...1` range.
    case pulling(progress: CGFloat)
    /// The pull distance has reached the refresh threshold and the gesture is ready
    /// to trigger a refresh once the user releases.
    ///
    /// The associated `progress` value is typically `1`.
    case armed(progress: CGFloat)
    /// A refresh is currently in progress.
    case refreshing
    /// The refresh just finished and the indicator is animating away.
    ///
    /// The associated `progress` value is normalized to the `0...1` range and
    /// describes how much of the finishing animation remains visible.
    case finishing(progress: CGFloat)
}

/// A vertical `ScrollView` with a fully custom pull-to-refresh indicator.
///
/// Unlike SwiftUI's built-in `.refreshable`, this component lets you provide a custom
/// view that reacts to the refresh lifecycle through `PullToRefreshScrollViewState`.
/// The indicator is embedded into the scroll content so it behaves more like the
/// native refresh control and scrolls away with the content while refreshing.
///
/// Refresh state is coordinated through the `isRefreshing` binding:
/// the control sets it to `true` when a refresh is triggered, and the caller must set it
/// back to `false` when loading finishes.
public struct PullToRefreshScrollView<RefreshContent: View, Content: View>: View {
    private var threshold: CGFloat = 96
    private var refreshViewHeight: CGFloat = 80
    private var showsIndicators: Bool = true
    private var isEnabled: Bool = true
    private var animationDuration: Duration = .milliseconds(350)
    private let onRefresh: () -> Void
    private let refreshContent: (PullToRefreshScrollViewState) -> RefreshContent
    private let content: () -> Content

    @Binding private var isRefreshing: Bool

    @State private var scrollPhase: ScrollPhase = .idle
    @State private var pullDistance: CGFloat = .zero
    @State private var displayProgress: CGFloat = .zero
    @State private var isArmed = false
    @State private var isFinishing = false
    @State private var finishTask: Task<Void, Never>?
    @State private var didSendArmedFeedback = false

    /// Creates a pull-to-refresh scroll view with a custom indicator.
    ///
    /// - Parameters:
    ///   - isRefreshing: Refresh state binding. The control sets this to `true` when the
    ///     user triggers refresh, and your code must set it back to `false` when loading
    ///     is finished.
    ///   - onRefresh: Called once the user releases after crossing the refresh threshold.
    ///   - refreshContent: A view builder that receives the current refresh lifecycle state
    ///     and returns a custom indicator view.
    ///   - content: A view builder that creates the scrollable content.
    public init(
        isRefreshing: Binding<Bool>,
        onRefresh: @escaping () -> Void,
        @ViewBuilder refreshContent: @escaping (PullToRefreshScrollViewState) -> RefreshContent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isRefreshing = isRefreshing
        self.onRefresh = onRefresh
        self.refreshContent = refreshContent
        self.content = content
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                refreshContent(currentState)
                    .frame(height: indicatorVisibleHeight, alignment: .bottom)
                    .frame(height: effectiveRefreshViewHeight, alignment: .bottom)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .allowsHitTesting(false)

                content()
            }
            .padding(.top, contentTopInset)
        }
        .scrollIndicators(showsIndicators ? .visible : .hidden)
        .animation(.snappy(duration: effectiveAnimationDuration), value: contentTopInset)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            handleScrollOffsetChange(newValue)
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            scrollPhase = newPhase

            if isEnabled, oldPhase == .interacting, newPhase != .interacting, isArmed, !isRefreshing {
                triggerRefresh()
                return
            }

            if newPhase == .idle, !isRefreshing, !isFinishing, pullDistance == 0 {
                reset()
            }
        }
        .onChange(of: isRefreshing) { _, newValue in
            if newValue {
                finishTask?.cancel()
                finishTask = nil
                isFinishing = false
                isArmed = false
                pullDistance = effectiveRefreshViewHeight
                displayProgress = 1
            } else {
                startFinishingAnimation()
            }
        }
        .onDisappear {
            finishTask?.cancel()
            finishTask = nil
        }
    }

    private var currentState: PullToRefreshScrollViewState {
        if isRefreshing {
            return .refreshing
        }

        if isFinishing {
            return .finishing(progress: displayProgress)
        }

        if isArmed {
            return .armed(progress: displayProgress)
        }

        if displayProgress > 0 {
            return .pulling(progress: displayProgress)
        }

        return .idle
    }

    private var effectiveThreshold: CGFloat {
        max(threshold, 1)
    }

    private var effectiveRefreshViewHeight: CGFloat {
        max(refreshViewHeight, 0)
    }

    private var effectiveAnimationDuration: TimeInterval {
        max(animationDuration.timeInterval, 0.01)
    }

    private var contentTopInset: CGFloat {
        (isRefreshing || isFinishing) ? 0 : -effectiveRefreshViewHeight
    }

    private var indicatorVisibleHeight: CGFloat {
        if isRefreshing {
            return effectiveRefreshViewHeight
        }

        if isFinishing {
            return max(effectiveRefreshViewHeight * displayProgress, 0)
        }

        return min(max(pullDistance, 0), effectiveRefreshViewHeight)
    }

    private func handleScrollOffsetChange(_ offset: CGFloat) {
        guard isEnabled else {
            reset()
            return
        }

        guard !isRefreshing, !isFinishing else { return }

        let overscroll = max(-offset, 0)
        let progress = min(overscroll / effectiveThreshold, 1)
        let isNowArmed = progress >= 1

        pullDistance = overscroll
        displayProgress = progress
        isArmed = isNowArmed

        if isNowArmed, !didSendArmedFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            didSendArmedFeedback = true
        } else if !isNowArmed {
            didSendArmedFeedback = false
        }

        guard overscroll == 0, scrollPhase == .idle else { return }
        reset()
    }

    private func triggerRefresh() {
        guard !isRefreshing else { return }

        finishTask?.cancel()
        finishTask = nil

        isArmed = false
        isFinishing = false
        didSendArmedFeedback = false
        pullDistance = effectiveRefreshViewHeight
        displayProgress = 1
        isRefreshing = true
        onRefresh()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func startFinishingAnimation() {
        finishTask?.cancel()

        isFinishing = true
        isArmed = false
        pullDistance = .zero
        displayProgress = 1

        finishTask = Task { @MainActor in
            let frameDelay: Duration = .milliseconds(16)
            let step = max((frameDelay.timeInterval / effectiveAnimationDuration), 0.06)

            while !Task.isCancelled, displayProgress > 0 {
                try? await Task.sleep(for: frameDelay)
                displayProgress = max(displayProgress - step, 0)
            }

            reset()
            finishTask = nil
        }
    }

    private func reset() {
        pullDistance = .zero
        displayProgress = .zero
        isArmed = false
        isFinishing = false
        didSendArmedFeedback = false
    }
}

public extension PullToRefreshScrollView {
    /// Sets the pull distance required to arm the refresh interaction.
    ///
    /// Larger values require a longer pull before release can trigger refresh.
    ///
    /// - Parameter threshold: The distance, in points, required to arm the refresh.
    /// - Returns: A modified scroll view with the updated threshold.
    func threshold(_ threshold: CGFloat) -> Self {
        var view = self
        view.threshold = threshold
        return view
    }

    /// Sets the reserved height for the refresh indicator area.
    ///
    /// This height is used while refreshing and during the finishing animation.
    ///
    /// - Parameter refreshViewHeight: The indicator area height, in points.
    /// - Returns: A modified scroll view with the updated indicator height.
    func refreshViewHeight(_ refreshViewHeight: CGFloat) -> Self {
        var view = self
        view.refreshViewHeight = refreshViewHeight
        return view
    }

    /// Controls whether scroll indicators are visible.
    ///
    /// - Parameter showsIndicators: `true` to show the system scroll indicators;
    ///   `false` to hide them.
    /// - Returns: A modified scroll view with the updated indicator visibility.
    func showsIndicators(_ showsIndicators: Bool) -> Self {
        var view = self
        view.showsIndicators = showsIndicators
        return view
    }

    /// Enables or disables the pull-to-refresh interaction.
    ///
    /// When disabled, the scroll view still scrolls normally, but the refresh indicator
    /// and refresh trigger logic remain inactive.
    ///
    /// - Parameter isEnabled: `true` to enable pull-to-refresh.
    /// - Returns: A modified scroll view with updated interaction availability.
    func pullToRefreshEnabled(_ isEnabled: Bool) -> Self {
        var view = self
        view.isEnabled = isEnabled
        return view
    }

    /// Sets the duration used by internal indicator finishing transitions.
    ///
    /// - Parameter animationDuration: The duration used for the finishing animation.
    /// - Returns: A modified scroll view with the updated animation timing.
    func animationDuration(_ animationDuration: Duration) -> Self {
        var view = self
        view.animationDuration = animationDuration
        return view
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
