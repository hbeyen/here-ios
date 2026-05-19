import Foundation

/// Input/Output split for view models. Views send intents into `input` and
/// observe state from `output`. Keeps the view → view-model contract
/// explicit and easy to mock.
///
/// Adapted from Says-iOS (`ViewModelType.swift`). Says paired this with
/// Combine `PassthroughSubject` for inputs; here-ios prefers async/await,
/// so `Input` is typically a struct of async closures (or @MainActor methods
/// on the view model itself) and `Output` is a `@Published`-backed struct
/// or the view model's own `@Observable` state.
@MainActor
protocol ViewModelType {
  associatedtype Input
  associatedtype Output

  var input: Input { get }
  var output: Output { get }
}
