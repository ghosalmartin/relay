import XCTest

/// End-to-end flows against the scripted client (see UITestLaunch in the app).
/// No phone and no network: the app pairs, syncs and echoes sends on its own.
@MainActor
final class RelayUITests: XCTestCase {
    /// Every instance refers to the same running app.
    private var app: XCUIApplication { XCUIApplication() }

    override func setUp() {
        continueAfterFailure = false
    }

    func testPairingShowsAQRCode() {
        launch("--ui-testing-hold-pairing")

        XCTAssertTrue(app.images["pairing.qr"].waitForExistence(timeout: 5))
    }

    func testPairingLeadsToTheInbox() {
        launch()

        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))
        XCTAssertTrue(conversation("dentist").exists)
    }

    func testSearchNarrowsTheInbox() {
        launch()
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))

        let search = app.searchFields.firstMatch
        search.click()
        search.typeText("dent")

        XCTAssertTrue(conversation("dentist").exists)
        XCTAssertFalse(conversation("sam").exists)
    }

    func testSendingAMessageShowsItInTheThread() {
        launch()
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))
        conversation("sam").click()

        let field = app.textFields["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("On my way\r")

        // A bubble is one accessibility element that also includes the time, so match within its label.
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'On my way'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")
    }

    func testSendButtonIsDisabledForABlankMessage() {
        launch()
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))
        conversation("sam").click()

        let send = app.buttons["composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)

        let field = app.textFields["composer.field"]
        field.click()
        field.typeText("   ")
        XCTAssertFalse(send.isEnabled)
    }

    private func launch(_ extraArguments: String...) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extraArguments
        app.launch()
    }

    private func conversation(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["conversation.\(id)"]
    }
}
