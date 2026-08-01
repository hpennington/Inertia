//
//  InertiaShapes.swift
//  
//
//  Created by Hayden Pennington on 7/5/24.
//

import SwiftUI

/// A shape as it is authored alongside an animation: a ring of corners, each
/// carrying its own colour, measured against the actionable it belongs to —
/// (0, 0) that view's top-left, (1, 1) its bottom-right.
///
/// Nothing holds a shape to that box, though. Coordinates outside 0...1 reach
/// past the actionable and go on being drawn, because the canvas they land on
/// is the container's rather than the view's: a shape three times the size of
/// the card it backs is authored simply by saying 3.
public struct InertiaShape: Codable, Equatable, CustomStringConvertible {
    public var description: String {
        """
        {"vertices": \(vertices.count)}
        """
    }

    public let vertices: [Vertex]

    public init(vertices: [Vertex]) {
        self.vertices = vertices
    }

    /// The same shape restated against the container, which is the frame the
    /// canvas actually fills: `frame` is where the actionable sits inside that
    /// container, and `containerSize` how big it is.
    ///
    /// This is the whole of "relative to the actionable, drawn across the
    /// container" — authored in the view's box, rendered in the container's, so
    /// a shape keeps its relationship to the view it belongs to while being
    /// free to spill out of it. A container with no area yet has nothing to
    /// project onto and leaves the shape alone; the canvas is not drawn at all
    /// in that state.
    func projected(from frame: CGRect, into containerSize: CGSize) -> InertiaShape {
        guard containerSize.width > 0, containerSize.height > 0 else { return self }

        return InertiaShape(
            vertices: vertices.map { vertex in
                Vertex(
                    position: InertiaPoint(
                        x: (frame.origin.x + vertex.position.x * frame.width) / containerSize.width,
                        y: (frame.origin.y + vertex.position.y * frame.height) / containerSize.height
                    ),
                    color: vertex.color
                )
            }
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

public struct TriangleNode: MetalCanvasNode {
    public let id: InertiaID
    public let animationValues: InertiaAnimationValues
    public let vertices: [Vertex]
    public let zIndex: Int
    
    public init(id: InertiaID, animationValues: InertiaAnimationValues, zIndex: Int, size: CGFloat, center: CGPoint, color: CGColor) {
        self.id = id
        self.animationValues = animationValues
        self.zIndex = zIndex
        
        // Define vertices of an isosceles triangle with mirror reflection symmetry along the x-axis
        let height = size * sqrt(3) / 2  // Height of the triangle (from top to base)
        let halfBase = size / 2  // Half of the base length
        
        let rgb = color.components!
        self.vertices = [
            Vertex(position: InertiaPoint(x: center.x, y: center.y + height / 2), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3]))),
            Vertex(position: InertiaPoint(x: center.x - halfBase, y: center.y - height / 2), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3]))),
            Vertex(position: InertiaPoint(x: center.x + halfBase, y: center.y - height / 2), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3]))),
        ]
    }
}

public struct SquareNode: MetalCanvasNode {
    public let id: InertiaID
    public let animationValues: InertiaAnimationValues
    public let vertices: [Vertex]
    public let zIndex: Int
    
    public init(id: InertiaID, animationValues: InertiaAnimationValues, zIndex: Int, size: CGFloat, center: CGPoint = .zero, color: CGColor) {
        self.id = id
        self.animationValues = animationValues
        self.zIndex = zIndex
        
        // Calculate vertices of the square
        let halfSize = size / 2
        let rgb = color.components!
        let topLeft = Vertex(position: InertiaPoint(x: center.x - halfSize, y: center.y - halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        let topRight = Vertex(position: InertiaPoint(x: center.x + halfSize, y: center.y - halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        let bottomLeft = Vertex(position: InertiaPoint(x: center.x - halfSize, y: center.y + halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        let bottomRight = Vertex(position: InertiaPoint(x: center.x + halfSize, y: center.y + halfSize), color: InertiaColor(red: Float(rgb[0]), green: Float(rgb[1]), blue: Float(rgb[2]), alpha: Float(rgb[3])))
        
        // Define vertices for two triangles forming the square
        self.vertices = [
            topLeft, topRight, bottomRight,
            topLeft, bottomLeft, bottomRight
        ]
    }
}
