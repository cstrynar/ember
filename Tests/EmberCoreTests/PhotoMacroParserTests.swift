import XCTest
@testable import EmberCore

final class PhotoMacroParserTests: XCTestCase {

    // MARK: - Well-formed, multi-item, wrapped in prose + a ```json fence

    func testWellFormedMultiItemWithProseAndFence() {
        let text = """
        Here's my estimate for the plate:

        ```json
        {
          "items": [
            { "name": "Grilled chicken breast", "serving": "1 breast (~170g)",
              "calories": 280, "protein_g": 52, "carb_g": 0, "fat_g": 6 },
            { "name": "Brown rice", "serving": "1 cup cooked",
              "calories": 215, "protein_g": 5, "carb_g": 45, "fat_g": 2 },
            { "name": "Steamed broccoli", "serving": "1 cup",
              "calories": 55, "protein_g": 4, "carb_g": 11, "fat_g": 1 }
          ],
          "assumptions": "Assumed no added oil; portion estimated from plate size.",
          "uncertainty": "medium"
        }
        ```

        Let me know if the portions look off.
        """

        guard case let .success(result) = PhotoMacroParser.parse(text) else {
            return XCTFail("expected .success")
        }

        XCTAssertEqual(result.items, [
            EstimatedFoodItem(name: "Grilled chicken breast", serving: "1 breast (~170g)",
                              macros: Macros(calories: 280, proteinG: 52, carbG: 0, fatG: 6)),
            EstimatedFoodItem(name: "Brown rice", serving: "1 cup cooked",
                              macros: Macros(calories: 215, proteinG: 5, carbG: 45, fatG: 2)),
            EstimatedFoodItem(name: "Steamed broccoli", serving: "1 cup",
                              macros: Macros(calories: 55, proteinG: 4, carbG: 11, fatG: 1)),
        ])
        XCTAssertEqual(result.assumptions,
                       "Assumed no added oil; portion estimated from plate size.")
        XCTAssertEqual(result.uncertainty, .medium)
    }

    // MARK: - Single-item, bare JSON, alias keys honored

    func testSingleItemBareJSONWithAliasKeys() {
        // Uses the aliases `kcal`, `protein`, `carbs`, `fat`, and `note` (not the primary keys).
        let text = """
        { "items": [ { "name": "Banana", "serving": "1 medium",
          "kcal": 105, "protein": 1, "carbs": 27, "fat": 0 } ],
          "note": "Ripe banana assumed.", "uncertainty": "low" }
        """

        guard case let .success(result) = PhotoMacroParser.parse(text) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0],
                       EstimatedFoodItem(name: "Banana", serving: "1 medium",
                                         macros: Macros(calories: 105, proteinG: 1,
                                                        carbG: 27, fatG: 0)))
        XCTAssertEqual(result.assumptions, "Ripe banana assumed.")
        XCTAssertEqual(result.uncertainty, .low)
    }

    func testMissingMacroNumbersDefaultToZeroAndNegativesClampToZero() {
        let text = """
        { "items": [ { "name": "Mystery soup", "serving": "1 bowl",
          "calories": -50, "protein_g": 3 } ] }
        """
        guard case let .success(result) = PhotoMacroParser.parse(text) else {
            return XCTFail("expected .success")
        }
        // calories clamps to 0; carb/fat absent default to 0; protein kept.
        XCTAssertEqual(result.items[0].macros,
                       Macros(calories: 0, proteinG: 3, carbG: 0, fatG: 0))
    }

    func testNamelessItemsAreDroppedNotFatal() {
        // One blank-name junk item plus one good item -> good item survives.
        let text = """
        { "items": [
            { "name": "   ", "calories": 10 },
            { "name": "Apple", "serving": "1 medium", "calories": 95,
              "protein_g": 0, "carb_g": 25, "fat_g": 0 }
        ], "uncertainty": "high" }
        """
        guard case let .success(result) = PhotoMacroParser.parse(text) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].name, "Apple")
        XCTAssertEqual(result.uncertainty, .high)
    }

    // MARK: - Malformed / garbage degrade gracefully (typed failure, no throw)

    func testNonJSONProseFailsAsNotJSON() {
        let estimate = PhotoMacroParser.parse("I can't tell what's on this plate, sorry.")
        XCTAssertEqual(estimate, .failure(.notJSON))
    }

    func testEmptyStringFailsAsNotJSON() {
        XCTAssertEqual(PhotoMacroParser.parse(""), .failure(.notJSON))
    }

    func testJSONWithNoUsableItemsFailsAsNoItems() {
        // `items` present but empty.
        XCTAssertEqual(PhotoMacroParser.parse("""
        { "items": [], "assumptions": "couldn't identify food", "uncertainty": "high" }
        """), .failure(.noItems))

        // `items` absent entirely.
        XCTAssertEqual(PhotoMacroParser.parse("""
        { "assumptions": "no food found" }
        """), .failure(.noItems))

        // All items nameless -> dropped to empty.
        XCTAssertEqual(PhotoMacroParser.parse("""
        { "items": [ { "calories": 10 }, { "name": "" } ] }
        """), .failure(.noItems))
    }

    func testTruncatedJSONFailsAsNotJSON() {
        // No closing brace -> the brace scan finds no balanced object.
        let estimate = PhotoMacroParser.parse("""
        { "items": [ { "name": "Pizza", "calories": 285
        """)
        XCTAssertEqual(estimate, .failure(.notJSON))
    }

    func testBalancedButWrongShapeFailsAsMalformed() {
        // A balanced object whose `items` is the wrong type for the DTO -> decode throws.
        let estimate = PhotoMacroParser.parse("""
        { "items": "not an array" }
        """)
        XCTAssertEqual(estimate, .failure(.malformed))
    }

    // MARK: - Uncertainty fallback

    func testUnrecognizedUncertaintyMapsToUnknown() {
        let text = """
        { "items": [ { "name": "Toast", "serving": "1 slice", "calories": 80 } ],
          "uncertainty": "kinda sure" }
        """
        guard case let .success(result) = PhotoMacroParser.parse(text) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(result.uncertainty, .unknown)
    }

    func testAbsentUncertaintyMapsToUnknown() {
        let text = """
        { "items": [ { "name": "Toast", "serving": "1 slice", "calories": 80 } ] }
        """
        guard case let .success(result) = PhotoMacroParser.parse(text) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(result.uncertainty, .unknown)
        XCTAssertEqual(result.assumptions, "") // absent assumptions -> empty string
    }

    // MARK: - asFoodItem mapping (the Stage-3 seam)

    func testAsFoodItemCarriesNameServingAndMacros() {
        let item = EstimatedFoodItem(name: "Oatmeal", serving: "1 cup cooked",
                                     macros: Macros(calories: 150, proteinG: 5,
                                                    carbG: 27, fatG: 3))
        let food = item.asFoodItem(id: "abc-123")
        XCTAssertEqual(food.id, "abc-123")
        XCTAssertEqual(food.name, "Oatmeal")
        XCTAssertEqual(food.servingDescription, "1 cup cooked")
        XCTAssertEqual(food.macrosPerServing, Macros(calories: 150, proteinG: 5,
                                                     carbG: 27, fatG: 3))
        XCTAssertEqual(food.source, .custom) // default
    }
}
