@testable import Presentation
import Testing

@Suite struct ThreadScrollSnapshotTests {
    private let atTheEnd = ThreadScrollSnapshot(contentHeight: 1000, visibleBottom: 1000)
    private let grown = ThreadScrollSnapshot(contentHeight: 1300, visibleBottom: 1000)

    @Test func growingContentIsFollowedFromTheEnd() {
        #expect(atTheEnd.shouldFollow(to: grown))
    }

    @Test func nearlyAtTheEndCounts() {
        #expect(ThreadScrollSnapshot(contentHeight: 1000, visibleBottom: 970).shouldFollow(to: grown))
    }

    @Test func someoneReadingFurtherUpIsLeftAlone() {
        #expect(!ThreadScrollSnapshot(contentHeight: 1000, visibleBottom: 400).shouldFollow(to: grown))
    }

    @Test func scrollingWithoutNewContentIsNotFollowed() {
        #expect(!atTheEnd.shouldFollow(to: ThreadScrollSnapshot(contentHeight: 1000, visibleBottom: 800)))
    }
}
