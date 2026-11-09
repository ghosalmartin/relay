import AppKit
import MessagingDomain
import Presentation
import SwiftUI
import UniformTypeIdentifiers

/// The message field. Return sends; Option-Return adds a line, as in Messages.
struct ComposerView: View {
    @Binding var draft: String
    let canSend: Bool
    let files: [PendingFile]
    let replyPreview: String?
    let onCancelReply: () -> Void
    let onSend: () -> Void
    let onFile: (OutgoingAttachment?) -> Void
    let onRemoveFile: (OutgoingAttachment) -> Void
    @FocusState private var isFocused: Bool
    @State private var isChoosingFile = false
    @State private var pasteMonitor: Any?

    private static let sendableTypes: [UTType] = [.image, .movie, .audio, .pdf]

    var body: some View {
        VStack(spacing: 0) {
            if let replyPreview {
                ReplyBannerView(preview: replyPreview, onCancel: onCancelReply)
            }
            ForEach(files) { file in
                PendingAttachmentView(attachment: file.attachment, sizeText: file.sizeText, onRemove: { onRemoveFile(file.attachment) })
            }
            HStack(alignment: .bottom, spacing: 8) {
                attachButton
                messageField
                sendButton
            }
            .padding(12)
        }
        .onAppear {
            isFocused = true
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKey)
        }
        .onDisappear {
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            pasteMonitor = nil
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.sendableTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach { onFile(OutgoingAttachmentReader.read($0)) } }
        }
    }

    private var attachButton: some View {
        Button { isChoosingFile = true } label: {
            Image(systemName: "paperclip").font(.title2)
        }
        .buttonStyle(.borderless)
        .help("Attach a File")
        .accessibilityLabel("Attach a file")
        .accessibilityIdentifier("composer.attach")
    }

    private var messageField: some View {
        TextField("Text Message", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($isFocused)
            .onSubmit(send)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.background, in: .capsule)
            .overlay(Capsule().strokeBorder(.separator))
            .accessibilityIdentifier("composer.field")
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up.circle.fill").font(.title)
        }
        .buttonStyle(.borderless)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Send")
        .accessibilityIdentifier("composer.send")
    }

    /// A text field only accepts text pastes, so a copied picture has to be caught before it gets there.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "v" else { return event }
        let pasted = OutgoingAttachmentReader.pasted(from: .general)
        guard !pasted.isEmpty else { return event }
        pasted.forEach(onFile)
        return nil
    }

    private func send() {
        guard canSend else { return }
        onSend()
        isFocused = true
    }
}
