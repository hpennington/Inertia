//
//  InertiaVertexRenderer.swift
//
//
//  Created by Hayden Pennington on 7/5/24.
//

import MetalKit
import SwiftUI

public struct InertiaColor: Codable, Equatable, Sendable {
    public let red: Float
    public let green: Float
    public let blue: Float
    public let alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct InertiaPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A single corner of a shape: where it sits, and what colour the shape is
/// there. Positions are normalized to the frame the shape is drawn in — (0, 0)
/// its top-left, (1, 1) its bottom-right — so a shape authored once holds its
/// place through every size that frame is laid out at. Values outside 0...1 are
/// off the edge of it, and clip.
public struct Vertex: Codable, Equatable, Sendable {
    public let position: InertiaPoint
    public let color: InertiaColor

    public init(position: InertiaPoint, color: InertiaColor) {
        self.position = position
        self.color = color
    }
}

public final class InertiaVertexRenderer: MTKView, MTKViewDelegate {
    public var vertices: [Vertex] {
        didSet {
            guard vertices != oldValue else { return }
            scheduleRedraw()
        }
    }

    private let pipelineState: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private let metalBackgroundColor: MTLClearColor

    public init(frame: CGRect, device: MTLDevice, vertices: [Vertex], backgroundColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)) {
        self.metalBackgroundColor = backgroundColor
        self.vertices = vertices
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("commandQueue is not available")
        }
        
        self.commandQueue = commandQueue
        
        guard let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal", subdirectory: "Metal") else {
            fatalError("Shader file not found.")
        }
        
        guard let shaderSource = try? String(contentsOf: shaderURL) else {
            fatalError("Shader source not found.")
        }

        let library = try? device.makeLibrary(source: shaderSource, options: nil)
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Standard source-over. Without the factors, "blending enabled" still
        // writes the source straight through, so a shape's alpha would do
        // nothing and the canvas could not sit behind anything.
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Create a vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position attribute
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // Color attribute
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 4
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 8
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("pipelineState failed")
        }
        
        self.pipelineState = pipelineState
        super.init(frame: frame, device: device)

        self.delegate = self
        // A canvas per actionable, so the renderers cannot each hold a display
        // link open: they draw when their shapes or their bounds change and
        // stay asleep otherwise.
        self.isPaused = true
        self.enableSetNeedsDisplay = true
#if os(iOS)
        self.layer.isOpaque = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isUserInteractionEnabled = false
#else
        self.layer?.isOpaque = false
#endif
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Asks for one more frame. Vertices are held in normalized space, so a
    /// resize changes where every one of them lands and needs the same redraw a
    /// change of shape does.
    private func scheduleRedraw() {
        #if os(macOS)
        needsDisplay = true
        #elseif os(iOS)
        setNeedsDisplay()
        #endif
    }

    #if os(macOS)
    public override func layout() {
        super.layout()
        scheduleRedraw()
    }
    #elseif os(iOS)
    public override func layoutSubviews() {
        super.layoutSubviews()
        scheduleRedraw()
    }
    #endif

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Not `bounds`: `size` is the drawable in pixels, and bounds are the
        // points the vertices are measured against.
        scheduleRedraw()
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        renderPassDescriptor.colorAttachments[0].clearColor = self.metalBackgroundColor
        renderPassDescriptor.colorAttachments[0].loadAction = .clear

        // The view's own box, top-left origin, into clip space — whose origin is
        // the centre and whose y runs upwards. Nothing here reads the bounds:
        // vertices are already a fraction of them, which is what lets one
        // authored shape fill whatever frame it is handed.
        let vertexData: [Float] = self.vertices.flatMap {
            let x = Float($0.position.x * 2 - 1)
            let y = Float(1 - $0.position.y * 2)
            let z = Float(0.0)
            let w = Float(1.0)
            let rgba = $0.color

            return [x, y, z, w, Float(rgba.red), Float(rgba.green), Float(rgba.blue), Float(rgba.alpha)]
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // An emptied shape list still has a pass to encode: the clear is what
        // takes the last frame's shapes back off the screen.
        if !vertexData.isEmpty,
           let vertexBuffer = device?.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: []) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexData.count / 8)
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
