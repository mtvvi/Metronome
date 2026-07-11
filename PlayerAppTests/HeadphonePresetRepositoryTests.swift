import XCTest
@testable import PlayerApp

final class HeadphonePresetRepositoryTests: XCTestCase {
    func testSearchIndexesBrandModelVariantAndSourceMetadata() async throws {
        let preset = HeadphonePreset(
            id: "one",
            headphoneName: "Acme Reference X (Leather)",
            sourceDescription: "Independent Lab",
            brand: "Acme",
            model: "Reference X",
            variant: "Leather",
            target: "Neutral",
            measurement: "Over-ear rig",
            attribution: AutoEqAttribution(),
            equalizerPreset: EQPreset(name: "Acme", bands: [])
        )
        let repository = JSONHeadphonePresetRepository(presets: [preset])

        let brandResults = try await repository.search(matching: "acme")
        let variantResults = try await repository.search(matching: "leather")
        let measurementResults = try await repository.search(matching: "lab")
        XCTAssertEqual(brandResults.map(\.id), ["one"])
        XCTAssertEqual(variantResults.map(\.id), ["one"])
        XCTAssertEqual(measurementResults.map(\.id), ["one"])
    }
}
