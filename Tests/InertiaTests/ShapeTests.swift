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

    /// A shape is authored against the actionable's box but drawn on the
    /// container's canvas, so a corner at (1, 1) has to come out at the
    /// actionable's bottom-right corner as a fraction of the container.
    func testShapeIsProjectedFromTheActionableOntoTheContainer() {
        let shape = InertiaShape(vertices: [corner(0, 0), corner(1, 1)])

        let projected = shape.projected(
            from: CGRect(x: 100, y: 50, width: 200, height: 100),
            into: CGSize(width: 400, height: 200)
        )

        XCTAssertEqual(projected.vertices[0].position, InertiaPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(projected.vertices[1].position, InertiaPoint(x: 0.75, y: 0.75))
    }

    /// The point of projecting rather than clipping: a shape larger than the
    /// actionable keeps going, and only runs out at the container's edge.
    ///
    /// Every coordinate is a multiple of the actionable's own size — 1.2 is a
    /// fifth of its width past its right edge, 3 is three times its width — so
    /// what a shape is measuring against never changes with the container it
    /// happens to be drawn on.
    func testShapeMayReachOutsideTheActionable() {
        let actionable = CGRect(x: 0, y: 0, width: 100, height: 100)
        let container = CGSize(width: 300, height: 300)

        let overhang = InertiaShape(vertices: [corner(1.2, 1.2)]).projected(from: actionable, into: container)
        let treble = InertiaShape(vertices: [corner(3, 3)]).projected(from: actionable, into: container)

        // 120 points across a 300-point container.
        XCTAssertEqual(overhang.vertices[0].position, InertiaPoint(x: 0.4, y: 0.4))
        XCTAssertEqual(treble.vertices[0].position, InertiaPoint(x: 1, y: 1))
    }

    /// The same shape on a bigger actionable is bigger, and does not care that
    /// the container is the same size in both cases.
    func testShapeScalesWithTheActionableNotTheContainer() {
        let container = CGSize(width: 400, height: 400)
        let shape = InertiaShape(vertices: [corner(1.2, 0)])

        let small = shape.projected(from: CGRect(x: 0, y: 0, width: 100, height: 100), into: container)
        let large = shape.projected(from: CGRect(x: 0, y: 0, width: 200, height: 200), into: container)

        XCTAssertEqual(small.vertices[0].position.x, 0.3)
        XCTAssertEqual(large.vertices[0].position.x, 0.6)
    }

    /// Fewer than three corners enclose nothing, and handing the renderer a
    /// partial triangle would have it read past the end of the list.
    func testShapeWithTooFewCornersDrawsNothing() {
        XCTAssertEqual(InertiaShape(vertices: []).triangles, [])
        XCTAssertEqual(InertiaShape(vertices: [corner(0, 0), corner(1, 1)]).triangles, [])
    }
}
