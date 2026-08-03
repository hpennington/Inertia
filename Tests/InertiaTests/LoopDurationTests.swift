import XCTest
@testable import Inertia

/// The loop an animation was authored against, which travels with the schema
/// rather than with the editor that recorded it.
final class LoopDurationTests: XCTestCase {
    private func schema(id: InertiaID = "card0", loopDuration: CGFloat) -> InertiaAnimationSchema {
        InertiaAnimationSchema(
            id: id,
            initialValues: .zero,
            invokeType: .auto,
            keyframes: [],
            shapes: [],
            loopDuration: loopDuration
        )
    }

    /// The whole point of moving the value into the schema: it has to come back
    /// off disk as it went on.
    func testSurvivesEncodingRoundTrip() throws {
        let data = try InertiaCoding.encode([schema(loopDuration: 12.5)])
        let decoded = try InertiaCoding.decode([InertiaAnimationSchema].self, from: data)

        XCTAssertEqual(decoded.first?.loopDuration, 12.5)
    }

    /// An animation recorded before the loop was part of the schema still opens,
    /// at the default.
    func testDecodesWithoutTheFieldAtTheDefault() throws {
        let json = """
        [{"id":"card0","initialValues":{"scale":1,"translate":[0,0],"rotate":0,"rotateCenter":0,"opacity":1},"invokeType":"auto","keyframes":[]}]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([InertiaAnimationSchema].self, from: json)

        XCTAssertEqual(decoded.first?.loopDuration, InertiaPlayback.defaultLoopDuration)
    }

    /// A length out of range — hand-edited, or from a peer — is brought back in
    /// rather than trusted.
    func testClampsOnDecode() throws {
        let data = try InertiaCoding.encode([schema(loopDuration: 900)])
        let decoded = try InertiaCoding.decode([InertiaAnimationSchema].self, from: data)

        XCTAssertEqual(decoded.first?.loopDuration, InertiaPlayback.loopDurationRange.upperBound)
    }

    /// A shipped build has no editor to tell it the loop, so the schemas it was
    /// built with have to be what says.
    @MainActor
    func testDataModelSeedsItsLoopFromTheSchemasItIsBuiltWith() {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: ["card0": schema(loopDuration: 7)],
            tree: Tree(id: "animation"),
            actionableIdPairs: []
        )

        XCTAssertEqual(model.loopDuration, 7)
    }

    /// Where a hand-edited file disagrees with itself the longest wins: the loop
    /// is what every track is padded out to, so the shorter answer would cut one
    /// of them short.
    @MainActor
    func testDataModelTakesTheLongestLoopAcrossSchemas() {
        let model = InertiaDataModel(
            containerId: "animation",
            inertiaSchemas: [
                "card0": schema(id: "card0", loopDuration: 4),
                "card1": schema(id: "card1", loopDuration: 9)
            ],
            tree: Tree(id: "animation"),
            actionableIdPairs: []
        )

        XCTAssertEqual(model.loopDuration, 9)
    }
}
