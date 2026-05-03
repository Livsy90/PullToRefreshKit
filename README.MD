# PullToRefreshKit

`PullToRefreshKit` is a SwiftUI package that provides a customizable pull-to-refresh scroll view for iOS.

Unlike SwiftUI's built-in `.refreshable`, this component lets you render a fully custom refresh indicator and react to each stage of the pull-to-refresh lifecycle.

https://github.com/user-attachments/assets/e04e2ee5-6a70-4f8a-ae46-281aa1453140

## Requirements

- iOS 18+

## What It Provides

The package exposes a single main component:

- `PullToRefreshScrollView`

It is a vertical `ScrollView` with:

- a custom refresh header supplied by the caller
- externally controlled refresh state via `Binding<Bool>`
- configurable threshold, indicator height, animation duration, enabled state, and scroll indicator visibility
- lifecycle-driven rendering through `PullToRefreshScrollViewState`

## Refresh Lifecycle

Your custom refresh view receives a `PullToRefreshScrollViewState` value:

- `idle`
- `pulling(progress: CGFloat)`
- `armed(progress: CGFloat)`
- `refreshing`
- `finishing(progress: CGFloat)`

This makes it possible to animate your indicator as the user pulls, releases, waits for loading, and returns to the resting state.

## Installation

Add the package to your project with Swift Package Manager.

```swift
dependencies: [
    .package(url: "https://github.com/Livsy90/PullToRefreshKit.git", branch: "main")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "PullToRefreshKit", package: "PullToRefreshKit")
    ]
)
```

## Usage

```swift
import SwiftUI
import PullToRefreshKit

struct ExampleView: View {
    @State private var items = Array(1...10).map { "Item \($0)" }
    @State private var isRefreshing = false

    var body: some View {
        PullToRefreshScrollView(
            isRefreshing: $isRefreshing,
            onRefresh: reload
        ) { state in
            RefreshHeader(state: state)
        } content: {
            LazyVStack {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .padding()
        }
        .threshold(110)
        .refreshViewHeight(88)
        .showsIndicators(false)
    }

    private func reload() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                items.insert("Updated item", at: 0)
                isRefreshing = false
            }
        }
    }
}

struct RefreshHeader: View {
    let state: PullToRefreshScrollViewState

    var body: some View {
        ProgressView()
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private var isVisible: Bool {
        switch state {
        case .idle:
            false
        default:
            true
        }
    }
}
```

## Important Behavior

`PullToRefreshScrollView` coordinates refresh state through the binding:

- when the user releases after crossing the threshold, `onRefresh` is called
- the component sets `isRefreshing` to `true`
- your refresh logic must set `isRefreshing` back to `false` when loading finishes

If you never reset `isRefreshing` to `false`, the control will remain in the refreshing state.

## Configuration API

The scroll view supports fluent configuration methods:

- `threshold(_:)`
- `refreshViewHeight(_:)`
- `showsIndicators(_:)`
- `pullToRefreshEnabled(_:)`
- `animationDuration(_:)`

## Notes

- The package includes a local demo preview in `PullToRefreshDemoView.swift`, but that view is private and not part of the public API.

## Public API Summary

```swift
public enum PullToRefreshScrollViewState: Equatable

public struct PullToRefreshScrollView<RefreshContent: View, Content: View>: View
```
