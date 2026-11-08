import CoreGraphics
import Foundation
import MessagingDomain
import Presentation
import Testing

@Suite struct PictureLayoutTests {
    @Test func aLandscapePictureIsLimitedByWidth() {
        #expect(PictureLayout.size(fitting: CGSize(width: 1000, height: 500)) == CGSize(width: 280, height: 140))
    }

    @Test func aPortraitPictureIsNoWiderThanItsScaledShape() {
        #expect(PictureLayout.size(fitting: CGSize(width: 500, height: 1000)) == CGSize(width: 160, height: 320))
    }

    @Test func aPictureWithNoKnownSizeStillGetsSpace() {
        #expect(PictureLayout.size(fitting: .zero) == CGSize(width: 280, height: 280))
    }
}

@Suite struct AttachmentFillTests {
    private let picture = MessagingDomain.Attachment(id: "a", fileName: "", mimeType: "image/png", byteCount: nil)
    private let document = MessagingDomain.Attachment(id: "b", fileName: "", mimeType: "application/pdf", byteCount: nil)

    @Test func aPictureFillsTheBubbleWhileLoadingAndOnceLoaded() {
        #expect(picture.fillsBubble(showing: nil))
        #expect(picture.fillsBubble(showing: .loading))
        #expect(picture.fillsBubble(showing: .loaded(Data())))
    }

    @Test func aFailedPictureIsTextSoItStaysInset() {
        #expect(!picture.fillsBubble(showing: .failed))
    }

    @Test func aFileCardStaysInset() {
        #expect(!document.fillsBubble(showing: .loaded(Data())))
    }
}
