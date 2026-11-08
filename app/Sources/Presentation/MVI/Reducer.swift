/// The heart of every screen: given the current state and something that happened,
/// produce the next state. Pure — no async, no I/O, no clock — so every rule is a plain unit test.
///
/// The flow, for every feature:
///
///     View ──Intent──▶ ViewModel ──calls──▶ Use case
///       ▲                  │                    │
///       └──── State ◀── Reducer ◀──Mutation─────┘
///
/// - `Intent`: what the user did (tapped send, typed, selected a row).
/// - `Mutation`: what happened as a result (history loaded, send failed).
/// - `State`: everything the view renders. Views read it; they never compute it.
public protocol Reducer {
    associatedtype State
    associatedtype Mutation

    static func reduce(_ state: State, _ mutation: Mutation) -> State
}
