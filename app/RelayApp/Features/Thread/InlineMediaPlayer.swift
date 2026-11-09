import AVKit
import MessagingDomain
import Presentation
import SwiftUI

/// Plays a downloaded video or audio clip in the bubble, with a way out for formats AVKit can't play.
struct InlineMediaPlayer: View {
    let attachment: Attachment
    let data: Data
    let onOpen: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView()
                }
            }
            .frame(width: PictureLayout.maxWidth, height: attachment.playerHeight)
            Button("Open in Another App", action: onOpen)
                .buttonStyle(.link)
                .font(.caption)
        }
        .task(id: data) {
            player = AttachmentFileOpener.temporaryFile(holding: data, mimeType: attachment.mimeType).map(AVPlayer.init(url:))
        }
        .onDisappear { player?.pause() }
    }
}
