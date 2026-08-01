//
//  InertiaShapes.swift
//  
//
//  Created by Hayden Pennington on 7/5/24.
//

import SwiftUI

public enum InertiaShapeType: String, Codable {
    case rectangle
    case oval
    case triangle
}

public struct InertiaShapeProperties: Codable, Equatable {
    let id: InertiaID
    let type: InertiaShapeType
    let width: CGFloat
    let height: CGFloat

    public init(id: InertiaID, type: InertiaShapeType, width: CGFloat, height: CGFloat) {
        self.id = id
        self.type = type
        self.width = width
        self.height = height
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

    private func getVertices() -> [Vertex]? {
        guard let shape else {
            return nil
        }
        switch shape.type {
        case .rectangle:
            return SquareNode(id: shape.id, zIndex: 0, size: max(shape.width, shape.height), color: CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)).metalCanvasNode.vertices
        case .oval:
            return SquareNode(id: shape.id, zIndex: 0, size: max(shape.width, shape.height), color: CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)).metalCanvasNode.vertices
        case .triangle:
            return TriangleNode(id: shape.id, size: max(shape.width, shape.height), center: .zero, color: CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)).metalCanvasNode.vertices
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
        
        let rgb = color.components!
        self.metalCanvasNode = MetalCanvasNode(id: id, vertices:  [
            Vertex(position: InertiaPoint(x: center.x, y: center.y + height / 2), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3]))),
            Vertex(position: InertiaPoint(x: center.x - halfBase, y: center.y - height / 2), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3]))),
            Vertex(position: InertiaPoint(x: center.x + halfBase, y: center.y - height / 2), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3]))),
        ], zIndex: 0)
    }
}

public struct SquareNode {
    let id: InertiaID
    let metalCanvasNode: MetalCanvasNode

    public init(id: InertiaID, zIndex: Int, size: CGFloat, center: CGPoint = .zero, color: CGColor) {
        self.id = id
        // Calculate vertices of the square
        let halfSize = size / 2
        let rgb = color.components!
        let topLeft = Vertex(position: InertiaPoint(x: center.x - halfSize, y: center.y - halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        let topRight = Vertex(position: InertiaPoint(x: center.x + halfSize, y: center.y - halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        let bottomLeft = Vertex(position: InertiaPoint(x: center.x - halfSize, y: center.y + halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        let bottomRight = Vertex(position: InertiaPoint(x: center.x + halfSize, y: center.y + halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        
        // Define vertices for two triangles forming the squares
        self.metalCanvasNode = MetalCanvasNode(id: id, vertices: [
            topLeft, topRight, bottomRight,
            topLeft, bottomLeft, bottomRight
        ], zIndex: 0)
    }
}
