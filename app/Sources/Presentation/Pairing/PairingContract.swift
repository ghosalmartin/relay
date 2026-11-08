import MessagingDomain

public struct PairingState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case signIn
        case preparing
        case confirmEmoji(String)
        case paired
        case failed(message: String)
    }

    /// Where the user signs in. A browser comes first because passkeys don't work in an embedded page.
    public enum SignInMethod: Equatable, Sendable {
        case browser
        case embedded
    }

    public let step: Step
    /// Goes up on each retry, giving the sign-in page a clean start.
    public let attempt: Int
    public let signInMethod: SignInMethod
    /// Why the last paste couldn't be used.
    public let pasteProblem: String?

    public init(step: Step = .signIn, attempt: Int = 0, signInMethod: SignInMethod = .browser, pasteProblem: String? = nil) {
        self.step = step
        self.attempt = attempt
        self.signInMethod = signInMethod
        self.pasteProblem = pasteProblem
    }

    /// What to do in Chrome once signed in, in order.
    public static let browserSteps = [
        "On the page that loads, press ⌥⌘I and choose the Network tab",
        "Reload the page with ⌘R",
        "Right-click the request called config, then choose Copy › Copy as cURL",
    ]

    /// The instructions shown beside the sign-in page, in order.
    public static let instructions = [
        "Sign in with the Google account on your Android phone",
        "Relay shows you an emoji",
        "Tap the matching emoji in Messages on your phone",
    ]
}

public enum PairingIntent: Equatable, Sendable {
    case signedIn(AccountCookies)
    case pasteTapped
    case signInMethodChosen(PairingState.SignInMethod)
    case retryTapped
}

public enum PairingMutation: Equatable, Sendable {
    case started
    case stepReached(PairingState.Step)
    case failed(String)
    case retryRequested
    case signInMethodChosen(PairingState.SignInMethod)
    case pasteRejected
}
