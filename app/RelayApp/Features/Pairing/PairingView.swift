import Presentation
import SwiftUI

struct PairingView: View {
    @State var viewModel: PairingViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 48) {
            instructions
            code
        }
        .padding(48)
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
        .frame(maxWidth: 360, alignment: .leading)
    }

    @ViewBuilder
    private var code: some View {
        switch viewModel.state.step {
        case .preparing, .paired:
            ProgressView().frame(width: QRCodeView.side, height: QRCodeView.side)
        case .scanCode(let code):
            QRCodeView(text: code)
                .accessibilityIdentifier("pairing.qr")
        case .confirmEmoji(let emoji):
            VStack(spacing: 12) {
                Text(emoji).font(.system(size: 96))
                Text("Tap this emoji on your phone").foregroundStyle(.secondary)
            }
            .frame(width: QRCodeView.side, height: QRCodeView.side)
        case .failed(let message):
            ContentUnavailableView {
                Label("Pairing didn't work", systemImage: "qrcode")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { viewModel.send(.retryTapped) }
            }
            .frame(width: QRCodeView.side)
        }
    }
}
