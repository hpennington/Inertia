//
//  VertexRenderer.swift
//
//
//  Created by Hayden Pennington on 7/5/24.
//

import MetalKit
import SwiftUI

public struct Vertex {
    let position: CGPoint
    let color: CGColor
}

public final class VertexRenderer: MTKView, MTKViewDelegate {
    public var vertices: [Vertex] {
        didSet {
            needsRedraw = true
        }
    }
    
    private let pipelineState: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private var needsRedraw = true
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
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        
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
        #if os(iOS)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isUserInteractionEnabled = false
        #endif
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.bounds.size = size
        self.needsRedraw = true
    }
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        guard needsRedraw else {
            return
        }
        
        needsRedraw = false
        
        renderPassDescriptor.colorAttachments[0].clearColor = self.metalBackgroundColor
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        let vertices: [Float] = self.vertices.flatMap {
            let x = Float($0.position.x / frame.width / 2)
            let y = Float($0.position.y / frame.height / 2)
            let z = Float(0.0)
            let w = Float(1.0)
            let rgba = $0.color.components ?? [1.0, 1.0, 1.0, 1.0]
            
            return [x, y, z, w, Float(rgba[0]), Float(rgba[1]), Float(rgba[2]), Float(rgba[3])]
        }
        
        guard !vertices.isEmpty else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        let vertexBuffer = device?.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
        
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 8)
        
        renderEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
