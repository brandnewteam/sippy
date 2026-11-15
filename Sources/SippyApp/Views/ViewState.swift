import SwiftUI

/// SwiftUI's `State` property wrapper under a name that isn't a macro.
///
/// From the macOS 27 SDK on, `@State` resolves to a `State()` macro whose
/// compiler plugin (SwiftUIMacros) ships only with Xcode, so Command Line
/// Tools builds fail on every `@State`. The `State` type itself is unchanged:
/// spelling the attribute through this alias applies the property wrapper
/// directly, exactly as `@State` did on earlier SDKs. Use `@ViewState`
/// wherever you'd write `@State`.
typealias ViewState<Value> = State<Value>
