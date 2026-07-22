//
//  Padawan_AdventuresUITests.swift
//  Padawan AdventuresUITests
//
//  Created by Steve Martin on 7/21/26.
//

import XCTest

final class Padawan_AdventuresUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPlayerSelectThenCanReachMenu() throws {
        let app = XCUIApplication()
        app.launch()

        let newPlayerButton = app.buttons["playerSelect.new"]
        XCTAssertTrue(
            newPlayerButton.waitForExistence(timeout: 10),
            "Expected player select after loading"
        )

        newPlayerButton.tap()

        let nameField = app.textFields["Player name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let playerName = "UITest\(Int(Date().timeIntervalSince1970))"
        nameField.tap()
        nameField.typeText(playerName)

        app.alerts.buttons["OK"].tap()

        let newGame = app.buttons["menu.newGame"]
        XCTAssertTrue(
            newGame.waitForExistence(timeout: 5),
            "Expected menu after creating a player"
        )

        newGame.tap()

        let back = app.buttons["levelSelect.back"]
        XCTAssertTrue(
            back.waitForExistence(timeout: 5),
            "Expected level select after New Game"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
