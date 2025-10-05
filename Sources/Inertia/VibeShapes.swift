////
////  InertiaShapes.swift
////  
////
////  Created by Hayden Pennington on 7/5/24.
////
//
//import SwiftUI
//
//public struct TriangleNode: MetalCanvasNode {
//    public let id: InertiaID
//    public let animationValues: InertiaAnimationValues
//    public let vertices: [Vertex]
//    public let zIndex: Int
//    
//    public init(id: InertiaID, animationValues: InertiaAnimationValues, zIndex: Int, size: CGFloat, center: CGPoint, color: CGColor) {
//        self.id = id
//        self.animationValues = animationValues
//        self.zIndex = zIndex
//        
//        // Define vertices of an isosceles triangle with mirror reflection symmetry along the x-axis
//        let height = size * sqrt(3) / 2  // Height of the triangle (from top to base)
//        let halfBase = size / 2  // Half of the base length
//        
//        self.vertices = [
//            Vertex(position: CGPoint(x: center.x, y: center.y + height / 2), color: color),
//            Vertex(position: CGPoint(x: center.x - halfBase, y: center.y - height / 2), color: color),
//            Vertex(position: CGPoint(x: center.x + halfBase, y: center.y - height / 2), color: color),
//        ]
//    }
//}
//
//public struct SquareNode: MetalCanvasNode {
//    public let id: InertiaID
//    public let animationValues: InertiaAnimationValues
//    public let vertices: [Vertex]
//    public let zIndex: Int
//    
//    public init(id: InertiaID, animationValues: InertiaAnimationValues, zIndex: Int, size: CGFloat, center: CGPoint = .zero, color: CGColor) {
//        self.id = id
//        self.animationValues = animationValues
//        self.zIndex = zIndex
//        
//        // Calculate vertices of the square
//        let halfSize = size / 2
//        
//        let topLeft = Vertex(position: CGPoint(x: center.x - halfSize, y: center.y - halfSize), color: color)
//        let topRight = Vertex(position: CGPoint(x: center.x + halfSize, y: center.y - halfSize), color: color)
//        let bottomLeft = Vertex(position: CGPoint(x: center.x - halfSize, y: center.y + halfSize), color: color)
//        let bottomRight = Vertex(position: CGPoint(x: center.x + halfSize, y: center.y + halfSize), color: color)
//        
//        // Define vertices for two triangles forming the square
//        self.vertices = [
//            topLeft, topRight, bottomRight,
//            topLeft, bottomLeft, bottomRight
//        ]
//    }
//}
