import XCTest

/// End-to-end flows against the scripted client (see UITestLaunch in the app).
/// No phone and no network: the app pairs, syncs and echoes sends on its own.
final class RelayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testPairingShowsAQRCodeThenTheInbox() {
        XCTAssertTrue(app.images["pairing.qr"].waitForExistence(timeout: 5))
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 5))
        XCTAssertTrue(conversation("dentist").exists)
    }

    func testSearchNarrowsTheInbox() {
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))

        let search = app.searchFields.firstMatch
        search.click()
        search.typeText("dent")

        XCTAssertTrue(conversation("dentist").exists)
        XCTAssertFalse(conversation("sam").exists)
    }

    func testSendingAMessageShowsItInTheThread() {
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))
        conversation("sam").click()

        let field = app.textFields["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("On my way\r")

        XCTAssertTrue(app.staticTexts["On my way"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "")
    }

    func testSendButtonIsDisabledForABlankMessage() {
        XCTAssertTrue(conversation("sam").waitForExistence(timeout: 8))
        conversation("sam").click()

        let send = app.buttons["composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)

        app.textFields["composer.field"].typeText("   ")
        XCTAssertFalse(send.isEnabled)
    }

    private func conversation(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["conversation.\(id)"]
    }
}
