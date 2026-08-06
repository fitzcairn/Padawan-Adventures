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

        let tapToStart = app.staticTexts["loading.status"]
        XCTAssertTrue(
            tapToStart.waitForExistence(timeout: 30),
            "Expected loading status after launch"
        )
        // Bootstrap warms every level's treasure + enemy sprites plus the expanded
        // phonics catalog; cold simulator runs routinely exceed 10s.
        let ready = NSPredicate(format: "label == %@", "Tap to start")
        let readyExpectation = XCTNSPredicateExpectation(predicate: ready, object: tapToStart)
        XCTAssertEqual(
            XCTWaiter.wait(for: [readyExpectation], timeout: 60),
            .completed,
            "Expected tap-to-start after loading"
        )
        tapToStart.tap()

        let newPlayerButton = app.buttons["playerSelect.new"]
        XCTAssertTrue(
            newPlayerButton.waitForExistence(timeout: 5),
            "Expected player select after tap to start"
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

        let skip = app.staticTexts["cutscene.skip"]
        XCTAssertTrue(
            skip.waitForExistence(timeout: 5),
            "Expected cutscene after New Game"
        )
        skip.tap()

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
