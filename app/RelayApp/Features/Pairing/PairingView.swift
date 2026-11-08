import Presentation
import SwiftUI

struct PairingView: View {
    @State var viewModel: PairingViewModel

    private static let panelSide: CGFloat = 264

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            instructions
            panel
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: viewModel.runID) { await viewModel.run() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Use Messages on your computer")
                .font(.largeTitle.weight(.semibold))
            ForEach(Array(PairingState.instructions.enumerated()), id: \.offset) { index, step in
                Label {
                    Text(step)
                } icon: {
                    Text("\(index + 1)")
                        .font(.callout.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .background(.tint.opacity(0.15), in: .circle)
                }
            }
            .font(.title3)
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    @ViewBuilder
    private var panel: some View {
        switch viewModel.state.step {
        case .signIn where viewModel.showsWebSignIn && viewModel.state.signInMethod == .browser:
            VStack(alignment: .leading, spacing: 16) {
                BrowserSignInView(problem: viewModel.state.pasteProblem, onPaste: { viewModel.send(.pasteTapped) })
                Button("Sign in here instead") { viewModel.send(.signInMethodChosen(.embedded)) }
                    .buttonStyle(.link)
            }
        case .signIn where viewModel.showsWebSignIn:
            VStack(spacing: 8) {
                GoogleSignInView { viewModel.send(.signedIn($0)) }
                    .id(viewModel.runID)    // a retry starts from a clean sign-in page
                    .frame(minWidth: 360, maxWidth: 520, minHeight: 420, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 12))
                Button("Use Chrome instead (needed for passkeys)") { viewModel.send(.signInMethodChosen(.browser)) }
                    .buttonStyle(.link)
            }
        case .signIn, .preparing, .paired:
            ProgressView().frame(width: Self.panelSide, height: Self.panelSide)
        case .confirmEmoji(let emoji):
            VStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 96))
                    .accessibilityIdentifier("pairing.emoji")
                Text("Tap this emoji on your phone").foregroundStyle(.secondary)
            }
            .frame(width: Self.panelSide, height: Self.panelSide)
        case .failed(let message):
            ContentUnavailableView {
                Label("Pairing didn't work", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { viewModel.send(.retryTapped) }
            }
            .frame(width: Self.panelSide)
        }
    }
}
