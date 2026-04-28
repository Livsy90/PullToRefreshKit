import SwiftUI

private struct PullToRefreshDemoView: View {
    @State private var items = Array(1...16).map { "Row \($0)" }
    @State private var isRefreshing = false

    var body: some View {
        PullToRefreshScrollView(
            isRefreshing: $isRefreshing,
            onRefresh: reload
        ) { state in
            DemoRefreshHeader(state: state)
        } content: {
            LazyVStack(spacing: 14) {
                ForEach(items, id: \.self) { item in
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white.opacity(0.14))
                        .frame(height: 78)
                        .overlay(alignment: .leading) {
                            Text(item)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .threshold(110)
        .refreshViewHeight(88)
        .showsIndicators(false)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.16),
                    Color(red: 0.10, green: 0.22, blue: 0.35),
                    Color(red: 0.03, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func reload() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                items.insert("Updated \(Date.now.formatted(date: .omitted, time: .standard))", at: 0)
                isRefreshing = false
            }
        }
    }
}

private struct DemoRefreshHeader: View {
    let state: PullToRefreshScrollViewState

    @State private var spinningRotation: Double = .zero
    private let indicatorSize: CGFloat = 40

    var body: some View {
        Circle()
            .trim(from: 0, to: arcProgress)
            .stroke(
                AngularGradient(
                    colors: [.cyan, .mint, .white, .cyan],
                    center: .center
                ),
                style: .init(lineWidth: 8, lineCap: .round)
            )
            .frame(width: indicatorSize, height: indicatorSize)
            .rotationEffect(.degrees(rotation))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .drawingGroup()
            .accessibilityHidden(true)
            .onAppear {
                updateAnimationState()
            }
            .onChange(of: state) { _, _ in
                updateAnimationState()
            }
    }

    private var progress: CGFloat {
        switch state {
        case .idle:
            0
        case .pulling(let progress), .armed(let progress):
            progress
        case .refreshing:
            1
        case .finishing(let progress):
            progress
        }
    }

    private var arcProgress: CGFloat {
        switch state {
        case .refreshing:
            0.999
        default:
            progress
        }
    }

    private var rotation: Double {
        switch state {
        case .idle:
            0
        case .pulling(let progress):
            Double(progress) * 150
        case .armed:
            180
        case .refreshing:
            spinningRotation
        case .finishing(let progress):
            Double(progress) * 360
        }
    }

    private func updateAnimationState() {
        guard state == .refreshing else {
            spinningRotation = 0
            return
        }

        spinningRotation = 0

        Task { @MainActor in
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                spinningRotation = 360
            }
        }
    }
}

#Preview {
    PullToRefreshDemoView()
}
