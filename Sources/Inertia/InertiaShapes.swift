//
//  InertiaShapes.swift
//  
//
//  Created by Hayden Pennington on 7/5/24.
//

import SwiftUI

/// The kinds of vector a shape can be described as, rather than spelled out
/// corner by corner. A bare string on the wire, like every other enum here.
public enum InertiaShapeType: String, Codable {
    case rectangle
    case square
    case circle
    case oval
    case triangle
}

public struct InertiaShapeProperties: Codable, Equatable {
    let id: InertiaID
    let type: InertiaShapeType
    let width: CGFloat
    let height: CGFloat
    let color: InertiaColor

    public init(id: InertiaID, type: InertiaShapeType, width: CGFloat, height: CGFloat, color: InertiaColor) {
        self.id = id
        self.type = type
        self.width = width
        self.height = height
        self.color = color
    }
}

/// A shape as it is authored alongside an animation: a ring of corners, each
/// carrying its own colour, measured against the actionable it belongs to —
/// (0, 0) that view's top-left, (1, 1) its bottom-right.
///
/// Nothing holds a shape to that box, though. Coordinates outside 0...1 reach
/// past the actionable and go on being drawn, because the canvas they land on
/// is the container's rather than the view's: a shape three times the size of
/// the card it backs is authored simply by saying 3.
///
/// A shape may also carry an animation of its own, which is what makes it a
/// drawing rather than a backdrop: the corners say what is drawn, the animation
/// says how it moves, and the actionable it was authored against carries both.
public final class InertiaShape: Codable, Equatable, CustomStringConvertible {
    public static func ==(lhs: InertiaShape, rhs: InertiaShape) -> Bool {
        return lhs.vertices == rhs.vertices && lhs.animation == rhs.animation
    }

    public var description: String {
        """
        {"vertices": \(vertices.count), "animated": \(animation != nil)}
        """
    }

    /// The corners as authored, when they were authored one by one. A shape
    /// described by `shape` instead has none of its own and is drawn from that
    /// description, which is what `vertices` resolves.
    public let _vertices: [Vertex]?

    /// The ring of corners the renderer draws, however the shape was authored.
    public var vertices: [Vertex] {
        if let _vertices {
            return _vertices
        } else if let vertices = getVertices() {
            return vertices
        } else {
            return []
        }
    }

    /// The ring of corners a described vector is drawn from, in the actionable's
    /// own units and centred on its top-left corner — the origin the description
    /// is measured from.
    ///
    /// Matches the Kotlin and WebGL runtimes corner for corner, so one authored
    /// vector is the same drawing on all three. A rectangle comes out as the two
    /// triangles of a quad rather than four corners; the fan in `triangles`
    /// re-covers the same area from them.
    ///
    /// A square, a circle and a triangle are the descriptions with one
    /// measurement rather than two, so each is sized by the longer side of the
    /// box it was drawn in — the shape stays square, stays round, stays a
    /// triangle whatever box it was dragged out over.
    private func getVertices() -> [Vertex]? {
        guard let shape else {
            return nil
        }
        let color = shape.color.cgColor
        switch shape.type {
        case .rectangle:
            return RectangleNode(id: shape.id, zIndex: 0, width: shape.width, height: shape.height, color: color).metalCanvasNode.vertices
        case .square:
            return SquareNode(id: shape.id, zIndex: 0, size: max(shape.width, shape.height), color: color).metalCanvasNode.vertices
        case .circle:
            return CircleNode(id: shape.id, zIndex: 0, diameter: max(shape.width, shape.height), color: color).metalCanvasNode.vertices
        case .oval:
            return OvalNode(id: shape.id, zIndex: 0, width: shape.width, height: shape.height, color: color).metalCanvasNode.vertices
        case .triangle:
            return TriangleNode(id: shape.id, size: max(shape.width, shape.height), center: .zero, color: color).metalCanvasNode.vertices
        }
    }

    /// This shape's own track, if it was given one. Read at the same playhead
    /// as everything else in the container, so a shape moves in time with the
    /// animation it was authored beside rather than on a clock of its own.
    public let animation: InertiaAnimationSchema?
    public let shape: InertiaShapeProperties?

    /// `_vertices` is written as `vertices`: the corners are what a shape has
    /// always been on the wire, and the leading underscore is only how the
    /// resolved list and the authored one are told apart in here.
    private enum CodingKeys: String, CodingKey {
        case _vertices = "vertices"
        case animation
        case shape
    }

    public init(shape: InertiaShapeProperties? = nil, vertices: [Vertex]?, animation: InertiaAnimationSchema? = nil) {
        self.shape = shape
        self._vertices = vertices
        self.animation = animation
    }

    /// The same shape restated against `bounds` — the canvas's own box — so
    /// (0, 0) is the canvas's top-left corner and (1, 1) its bottom-right,
    /// which is the space the renderer draws in.
    ///
    /// The corners are resolved on the way through: whatever the shape was
    /// authored as, what comes out is the ring that lands in `bounds`. Its
    /// animation rides along, since normalizing is about where the shape is
    /// drawn and not about what it then does.
    func normalized(to bounds: CGRect) -> InertiaShape {
        guard bounds.width > 0, bounds.height > 0 else { return self }

        return InertiaShape(
            vertices: vertices.map { vertex in
                Vertex(
                    position: InertiaPoint(
                        x: (vertex.position.x - bounds.minX) / bounds.width,
                        y: (vertex.position.y - bounds.minY) / bounds.height
                    ),
                    color: vertex.color
                )
            },
            animation: animation
        )
    }

    /// The shape as the triangle list the renderer draws: a fan around the
    /// first corner, so three corners are a triangle and four a quad. Fewer
    /// than three enclose no area and contribute nothing.
    var triangles: [Vertex] {
        guard vertices.count >= 3 else { return [] }

        return (1..<(vertices.count - 1)).flatMap {
            [vertices[0], vertices[$0], vertices[$0 + 1]]
        }
    }
}

public extension Collection where Element == InertiaShape {
    /// The smallest box holding every corner of these shapes, in the units they
    /// are authored in — multiples of the actionable's own frame, so
    /// `(0, 0, 1, 1)` is exactly the actionable and `(0, 0, 3, 3)` three times
    /// it.
    ///
    /// This is what the canvas is sized and placed by. Sizing it to the shapes
    /// rather than to the container is what keeps a shape whole: a canvas is a
    /// rectangle that rotates with the view it backs, so anything reaching past
    /// its edge is cut — and a canvas fitted to the container was already
    /// cutting a shape bigger than the container, then sweeping that straight
    /// edge through the artwork as the view turned. Fitted to the shapes, there
    /// is nothing outside it to lose.
    ///
    /// Nil when the shapes enclose no area, which is also when there is nothing
    /// to draw.
    var bounds: CGRect? {
        let positions = flatMap { $0.vertices.map(\.position) }
        guard let first = positions.first else { return nil }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for position in positions {
            minX = Swift.min(minX, position.x)
            maxX = Swift.max(maxX, position.x)
            minY = Swift.min(minY, position.y)
            maxY = Swift.max(maxY, position.y)
        }

        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return bounds.width > 0 && bounds.height > 0 ? bounds : nil
    }
}

public struct TriangleNode {
    public let id: InertiaID
    public let metalCanvasNode: MetalCanvasNode
    
    public init(id: InertiaID, size: CGFloat, center: CGPoint, color: CGColor) {
        self.id = id
        // Define vertices of an isosceles triangle with mirror reflection symmetry along the x-axis
        let height = size * sqrt(3) / 2  // Height of the triangle (from top to base)
        let halfBase = size / 2  // Half of the base length
        
        let vertexColor = color.vertexColor
        self.metalCanvasNode = MetalCanvasNode(id: id, vertices:  [
            Vertex(position: InertiaPoint(x: center.x, y: center.y + height / 2), color: vertexColor),
            Vertex(position: InertiaPoint(x: center.x - halfBase, y: center.y - height / 2), color: vertexColor),
            Vertex(position: InertiaPoint(x: center.x + halfBase, y: center.y - height / 2), color: vertexColor),
        ], zIndex: 0)
    }
}

public struct RectangleNode {
    public let id: InertiaID
    public let metalCanvasNode: MetalCanvasNode

    public init(id: InertiaID, zIndex: Int, width: CGFloat, height: CGFloat, center: CGPoint = .zero, color: CGColor) {
        self.id = id
        // Calculate the corners of the rectangle, which is drawn about its centre
        let halfWidth = width / 2
        let halfHeight = height / 2
        let vertexColor = color.vertexColor
        let topLeft = Vertex(position: InertiaPoint(x: center.x - halfWidth, y: center.y - halfHeight), color: vertexColor)
        let topRight = Vertex(position: InertiaPoint(x: center.x + halfWidth, y: center.y - halfHeight), color: vertexColor)
        let bottomLeft = Vertex(position: InertiaPoint(x: center.x - halfWidth, y: center.y + halfHeight), color: vertexColor)
        let bottomRight = Vertex(position: InertiaPoint(x: center.x + halfWidth, y: center.y + halfHeight), color: vertexColor)

        // Define vertices for two triangles forming the rectangle
        self.metalCanvasNode = MetalCanvasNode(id: id, vertices: [
            topLeft, topRight, bottomRight,
            topLeft, bottomLeft, bottomRight
        ], zIndex: zIndex)
    }
}

/// A square is the rectangle whose sides are equal, and is drawn as one.
public struct SquareNode {
    let id: InertiaID
    let metalCanvasNode: MetalCanvasNode

    public init(id: InertiaID, zIndex: Int, size: CGFloat, center: CGPoint = .zero, color: CGColor) {
        self.id = id
        self.metalCanvasNode = RectangleNode(id: id, zIndex: zIndex, width: size, height: size, center: center, color: color).metalCanvasNode
    }
}

public struct OvalNode {
    /// How many corners the ring is cut into. An oval has no corners of its own,
    /// so it is drawn as the many-sided polygon that reads as one at the sizes a
    /// shape is authored at — and the same count on every runtime, so an oval
    /// authored once is the same drawing wherever it is played back.
    public static let segments = 48

    public let id: InertiaID
    public let metalCanvasNode: MetalCanvasNode

    public init(id: InertiaID, zIndex: Int, width: CGFloat, height: CGFloat, center: CGPoint = .zero, color: CGColor) {
        self.id = id
        // Step around the ellipse inscribed in the box, one corner per segment.
        // The ring is convex, so the fan the renderer draws it with covers it
        // exactly from any corner of it.
        let radiusX = width / 2
        let radiusY = height / 2
        let vertexColor = color.vertexColor

        self.metalCanvasNode = MetalCanvasNode(id: id, vertices: (0..<Self.segments).map { segment in
            let angle = 2 * CGFloat.pi * CGFloat(segment) / CGFloat(Self.segments)
            return Vertex(
                position: InertiaPoint(
                    x: center.x + radiusX * cos(angle),
                    y: center.y + radiusY * sin(angle)
                ),
                color: vertexColor
            )
        }, zIndex: zIndex)
    }
}

/// A circle is the oval whose axes are equal, and is drawn as one.
public struct CircleNode {
    public let id: InertiaID
    public let metalCanvasNode: MetalCanvasNode

    public init(id: InertiaID, zIndex: Int, diameter: CGFloat, center: CGPoint = .zero, color: CGColor) {
        self.id = id
        self.metalCanvasNode = OvalNode(id: id, zIndex: zIndex, width: diameter, height: diameter, center: center, color: color).metalCanvasNode
    }
}

private extension InertiaColor {
    /// The described colour as Core Graphics states it, which is the colour the
    /// shape nodes are built from.
    var cgColor: CGColor {
        CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

private extension CGColor {
    /// The colour as a corner carries it. A colour that isn't stated as RGBA —
    /// a grey, most often — is read as the one channel it does have, rather
    /// than indexing past the end of a component list that is shorter than the
    /// four channels a vertex wants.
    var vertexColor: InertiaColor {
        let components = components ?? []
        guard components.count >= 4 else {
            let white = Float(components.first ?? 0)
            return InertiaColor(red: white, green: white, blue: white, alpha: Float(components.last ?? 1))
        }

        return InertiaColor(
            red: Float(components[0]),
            green: Float(components[1]),
            blue: Float(components[2]),
            alpha: Float(components[3])
        )
    }
}
