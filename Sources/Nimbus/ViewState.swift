import Combine

/// Stand-in for SwiftUI's `@State`.
///
/// The macOS 27 SDK implements `@State` as a compiler macro (SwiftUIMacros), and the
/// standalone Command Line Tools don't ship that plugin, so `@State` fails to compile
/// without full Xcode. `@StateObject` is still an ordinary property wrapper, so a tiny
/// ObservableObject box gives us the same per-view mutable storage:
///
///     @StateObject private var image = ViewState<NSImage?>(nil)
///     image.value = ...
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
