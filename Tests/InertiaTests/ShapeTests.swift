import XCTest
@testable import Inertia

/// The shapes an actionable's canvas draws: how they are authored alongside an
/// animation, and how they reach the renderer.
final class ShapeTests: XCTestCase {
    /// The two kinds of entry `example/demo.inertia/animations/animation.json`
    /// holds: a card with a shape behind it, and one without the key at all.
    private let demoJSON = """
    [
      {
        "id" : "card0",
        "initialValues" : {"opacity": 1, "rotate": 0, "rotateCenter": 0, "scale": 1, "translate": [0, 0]},
        "invokeType" : "trigger",
        "keyframes" : [],
        "shapes" : [
          {
            "vertices" : [
              {"position": {"x": 0, "y": 0}, "color": {"red": 0.35, "green": 0.1, "blue": 0.85, "alpha": 0.6}},
              {"position": {"x": 1, "y": 0}, "color": {"red": 0.1, "green": 0.55, "blue": 0.95, "alpha": 0.6}},
              {"position": {"x": 1, "y": 1}, "color": {"red": 0.1, "green": 0.85, "blue": 0.75, "alpha": 0.6}},
              {"position": {"x": 0, "y": 1}, "color": {"red": 0.35, "green": 0.1, "blue": 0.85, "alpha": 0.6}}
            ]
          }
        ]
      },
      {
        "id" : "card1",
        "initialValues" : {"opacity": 1, "rotate": 0, "rotateCenter": 0, "scale": 1, "translate": [0, 0]},
        "invokeType" : "auto",
        "keyframes" : []
      }
    ]
    """

    private func corner(_ x: Double, _ y: Double) -> Vertex {
        Vertex(
            position: InertiaPoint(x: x, y: y),
            color: InertiaColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
    }

    private func decodeDemo() throws -> [InertiaID: InertiaAnimationSchema] {
        let data = try XCTUnwrap(demoJSON.data(using: .utf8))
        let schemas = try XCTUnwrap(decodeInertiaSchemas(json: data))
        return schemas.reduce(into: [:]) { $0[$1.id] = $1 }
    }

    func testShapesAreDecodedWithTheirVertices() throws {
        let card0 = try XCTUnwrap(decodeDemo()["card0"])

        XCTAssertEqual(card0.shapes.count, 1)
        XCTAssertEqual(card0.shapes.first?.vertices.count, 4)
        XCTAssertEqual(card0.shapes.first?.vertices.first?.position, InertiaPoint(x: 0, y: 0))
        XCTAssertEqual(card0.shapes.first?.vertices.first?.color.alpha, 0.6)
    }

    /// An animation authored before shapes existed — or one that simply wants
    /// none — has to keep loading, or a single old file takes the whole
    /// container's schemas down with it.
    func testAnimationWithoutShapesStillDecodes() throws {
        let card1 = try XCTUnwrap(decodeDemo()["card1"])

        XCTAssertEqual(card1.shapes, [])
    }

    /// Saving is the same schemas encoded straight back out, so a shape only
    /// lasts a session if it makes the round trip. Reading it and writing
    /// nothing is how an authored canvas gets quietly emptied by the first
    /// keyframe anyone records.
    func testShapesAreWrittenBackOut() throws {
        let decoded = try decodeDemo()
        let encoded = try JSONEncoder().encode(["card0", "card1"].compactMap { decoded[$0] })
        let reread = try XCTUnwrap(decodeInertiaSchemas(json: encoded))
            .reduce(into: [InertiaID: InertiaAnimationSchema]()) { $0[$1.id] = $1 }

        XCTAssertEqual(reread["card0"]?.shapes, decoded["card0"]?.shapes)
        XCTAssertEqual(reread["card1"]?.shapes, [])
    }

    /// A shape is a ring of corners; the renderer draws triangles. Four corners
    /// are the two triangles of a quad, sharing the corner the fan turns about.
    func testShapeIsTriangulatedAsAFan() throws {
        let corners = (0..<4).map { corner(Double($0), Double($0)) }

        let triangles = InertiaShape(vertices: corners).triangles

        XCTAssertEqual(triangles.count, 6)
        XCTAssertEqual(triangles.map(\.position.x), [0, 1, 2, 0, 2, 3])
    }

    /// A shape that fits the actionable exactly gives a canvas that is the
    /// actionable: the unit box, at its origin.
    func testBoundsOfAShapeFillingTheActionable() {
        let shape = InertiaShape(vertices: [corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 1)])

        XCTAssertEqual([shape].bounds, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The point of fitting the canvas to the shapes: one reaching past the
    /// actionable grows the canvas instead of being cut off at its edge — at the
    /// actionable's own edge, or at the container's, which is what stopped a
    /// shape at the window before. 1.2 is a fifth of the actionable's width past
    /// its right edge, and -0.5 half its width before its left, so the canvas
    /// spans 1.7 of it.
    func testBoundsGrowToHoldShapesOutsideTheActionable() throws {
        let shape = InertiaShape(vertices: [corner(-0.5, 0), corner(1.2, 0), corner(1.2, 3)])

        let bounds = try XCTUnwrap([shape].bounds)

        XCTAssertEqual(bounds.minX, -0.5, accuracy: 0.0001)
        XCTAssertEqual(bounds.width, 1.7, accuracy: 0.0001)
        XCTAssertEqual(bounds.height, 3, accuracy: 0.0001)
    }

    /// Several shapes share one canvas, so the box has to hold all of them.
    func testBoundsSpanEveryShape() {
        let left = InertiaShape(vertices: [corner(-1, 0), corner(0, 0), corner(0, 1)])
        let right = InertiaShape(vertices: [corner(1, 0), corner(2, 0), corner(2, 0.5)])

        XCTAssertEqual([left, right].bounds, CGRect(x: -1, y: 0, width: 3, height: 1))
    }

    /// Shapes enclosing no area have no canvas, which is also the state in which
    /// there is nothing to draw.
    func testBoundsOfEmptyOrDegenerateShapesAreNil() {
        XCTAssertNil([InertiaShape]().bounds)
        XCTAssertNil([InertiaShape(vertices: [])].bounds)
        XCTAssertNil([InertiaShape(vertices: [corner(1, 0), corner(1, 1)])].bounds)
    }

    /// Whatever box the canvas ends up being, the renderer is handed the shape
    /// in the canvas's own 0...1 space — so the corner that defined the far edge
    /// of the bounds lands exactly on it.
    func testShapeIsNormalizedIntoTheCanvasBounds() {
        let shape = InertiaShape(vertices: [corner(-0.5, 0), corner(1.5, 0), corner(1.5, 2)])

        let normalized = shape.normalized(to: CGRect(x: -0.5, y: 0, width: 2, height: 2))

        XCTAssertEqual(normalized.vertices[0].position, InertiaPoint(x: 0, y: 0))
        XCTAssertEqual(normalized.vertices[1].position, InertiaPoint(x: 1, y: 0))
        XCTAssertEqual(normalized.vertices[2].position, InertiaPoint(x: 1, y: 1))
    }

    /// Fewer than three corners enclose nothing, and handing the renderer a
    /// partial triangle would have it read past the end of the list.
    func testShapeWithTooFewCornersDrawsNothing() {
        XCTAssertEqual(InertiaShape(vertices: []).triangles, [])
        XCTAssertEqual(InertiaShape(vertices: [corner(0, 0), corner(1, 1)]).triangles, [])
    }

    // MARK: - Shapes that carry an animation

    /// The other way a shape is authored: a drawn vector, described rather than
    /// spelled out corner by corner, with a track of its own attached — which is
    /// what makes it move independently of the actionable it is drawn behind.
    private let drawnJSON = """
    [
      {
        "id" : "card2",
        "initialValues" : {"opacity": 1, "rotate": 0, "rotateCenter": 0, "scale": 1, "translate": [0, 0]},
        "invokeType" : "auto",
        "keyframes" : [],
        "shapes" : [
          {
            "shape": {"id": "123", "width": 2, "height": 2, "type": "rectangle"},
            "animation": {
              "id" : "shape0",
              "initialValues" : {"opacity": 1, "rotate": 0, "rotateCenter": 0, "scale": 1, "translate": [0, 0]},
              "invokeType" : "auto",
              "keyframes" : [
                {"id": "a", "duration": 0.001, "values": {"opacity": 1, "rotate": 0, "rotateCenter": 0, "scale": 1, "translate": [0.8, 0.9]}},
                {"id": "b", "duration": 1.3, "values": {"opacity": 1, "rotate": 0, "rotateCenter": 0, "scale": 1, "translate": [-0.02, -0.05]}}
              ],
              "shapes" : []
            }
          }
        ]
      }
    ]
    """

    private func decodeDrawn() throws -> InertiaShape {
        let data = try XCTUnwrap(drawnJSON.data(using: .utf8))
        let schemas = try XCTUnwrap(decodeInertiaSchemas(json: data))
        return try XCTUnwrap(schemas.first?.shapes.first)
    }

    /// A shape given a track keeps it: without this the vector is decoded and
    /// drawn, and then sits still because the only animation that reached the
    /// runtime was the actionable's.
    func testShapeCarriesItsOwnAnimation() throws {
        let animation = try XCTUnwrap(decodeDrawn().animation)

        XCTAssertEqual(animation.id, "shape0")
        XCTAssertEqual(animation.invokeType, .auto)
        XCTAssertEqual(animation.keyframes.count, 2)
        XCTAssertEqual(animation.keyframes.last?.values.translate.width, -0.02)
    }

    /// A described shape has no corners on the wire; the ones it is drawn from
    /// are worked out from the description. A rectangle is the two triangles of
    /// a quad, so it reaches the renderer as six corners.
    func testDescribedShapeIsDrawnFromItsDescription() throws {
        let shape = try decodeDrawn()

        XCTAssertNil(shape._vertices)
        XCTAssertEqual(shape.vertices.count, 6)
        XCTAssertNotNil([shape].bounds)
    }

    /// Normalizing is about where a shape lands on the canvas, not about what it
    /// then does — so the track has to come through it. It is the last thing to
    /// touch a shape before the renderer, and a shape that lost its animation
    /// here would be drawn in the right place and never move.
    func testNormalizingKeepsTheShapesAnimation() throws {
        let shape = try decodeDrawn()
        let bounds = try XCTUnwrap([shape].bounds)

        let normalized = shape.normalized(to: bounds)

        XCTAssertEqual(normalized.animation?.id, "shape0")
        XCTAssertEqual(normalized.vertices.count, shape.vertices.count)
    }

    /// The same round trip the authored corners make: a track attached to a
    /// shape only lasts a session if saving writes it back out.
    func testShapeAnimationIsWrittenBackOut() throws {
        let shape = try decodeDrawn()

        let encoded = try JSONEncoder().encode([shape])
        let reread = try JSONDecoder().decode([InertiaShape].self, from: encoded)

        XCTAssertEqual(reread.first, shape)
        XCTAssertEqual(reread.first?.animation?.keyframes.count, 2)
        XCTAssertEqual(reread.first?.shape?.type, .rectangle)
    }
}
