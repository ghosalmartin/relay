import SwiftUI
import RelayKit
import CoreImage.CIFilterBuiltins

@main
struct RelayApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.phase {
                case .pairing(let qr): PairingView(qrURL: qr)
                case .connecting: ProgressView("Connecting to your phone…").padding(40)
                case .ready: ConversationsView(model: model)
                case .failed(let why):
                    ContentUnavailableView("Disconnected", systemImage: "iphone.slash",
                                           description: Text(why))
                }
            }
            .task { await model.start() }
        }
    }
}

/// Spike-level app state. M2 replaces the in-memory arrays with the local store.
@MainActor @Observable
final class AppModel {
    enum Phase { case pairing(String?), connecting, ready, failed(String) }

    var phase: Phase = .connecting
    var conversations: [String: GM.Conversation] = [:]
    var phoneOnline = true

    private var session: GMSession?
    private let keychain = Keychain(service: "dev.featurenotabug.relay")

    var sortedConversations: [GM.Conversation] {
        conversations.values.sorted { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
    }

    func start() async {
        do {
            let auth = keychain.read("auth")
            let s = try GMSession(auth: auth)
            session = s
            Task { await consume(s.events) }
            if auth == nil {
                phase = .pairing(nil)
                try await s.startQRPairing()
                Task { await refreshQRLoop() }
            } else {
                try await s.connect()
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func refreshQRLoop() async {
        while case .pairing = phase {
            try? await Task.sleep(for: .seconds(30))
            guard case .pairing = phase else { return }
            try? await session?.refreshQR()
        }
    }

    private func consume(_ events: AsyncStream<GMEvent>) async {
        for await event in events {
            switch event {
            case .qr(let url): phase = .pairing(url)
            case .authUpdated(let data): keychain.write("auth", data)
            case .pairSuccess:
                // libgm wants a fresh client built from the saved session after pairing.
                phase = .connecting
                session?.disconnect()
                session = nil
                await start()
                return
            case .conversation(let c): conversations[c.conversationID] = c
            case .ready: phase = .ready
            case .phoneNotResponding: phoneOnline = false
            case .phoneRespondingAgain: phoneOnline = true
            case .loggedOut:
                keychain.delete("auth")
                conversations.removeAll()
                await start()
                return
            case .fatal(let why): phase = .failed(why)
            default: break
            }
        }
    }
}

struct PairingView: View {
    let qrURL: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair with your phone").font(.title2.bold())
            Text("In Messages on your Android phone, tap your profile picture → Device pairing → QR code scanner.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 360)
            if let qrURL, let image = Self.qr(qrURL) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 240, height: 240)
            } else {
                ProgressView().frame(width: 240, height: 240)
            }
        }
        .padding(40)
    }

    static func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let out = filter.outputImage?.transformed(by: .init(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: out.extent.size)
    }
}

struct ConversationsView: View {
    let model: AppModel
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            List(model.sortedConversations, id: \.conversationID, selection: $selection) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.headline).lineLimit(1)
                    Text(c.latestMessage.displayContent).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Messages")
            .safeAreaInset(edge: .bottom) {
                if !model.phoneOnline {
                    Label("Phone isn't responding", systemImage: "exclamationmark.triangle")
                        .font(.caption).padding(8)
                }
            }
        } detail: {
            Text(selection == nil ? "Select a conversation" : "Thread view lands in M2")
                .foregroundStyle(.secondary)
        }
    }
}
