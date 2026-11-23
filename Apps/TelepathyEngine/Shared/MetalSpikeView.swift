import SwiftUI
import MetalKit
import NeuralCore

#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

struct MetalSpikeView: PlatformViewRepresentable {
    let snapshot: StageTapSnapshot?

#if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.snapshot = snapshot
    }
#else
    func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.snapshot = snapshot
    }
#endif

    func makeCoordinator() -> SpikeRenderer { SpikeRenderer() }

    private func makeView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)
        context.coordinator.snapshot = snapshot
        return view
    }
}

final class SpikeRenderer: NSObject, MTKViewDelegate {
    var snapshot: StageTapSnapshot?
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var vertexCapacity = 0

    private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VIn { float2 pos [[attribute(0)]]; float4 color [[attribute(1)]]; };
    struct VOut { float4 pos [[position]]; float4 color; };
    vertex VOut spike_vertex(VIn in [[stage_in]]) {
      VOut o; o.pos = float4(in.pos, 0, 1); o.color = in.color; return o;
    }
    fragment float4 spike_fragment(VOut in [[stage_in]]) { return in.color; }
    """

    struct Vertex {
        var x: Float
        var y: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    func configure(view: MTKView) {
        device = view.device
        queue = device?.makeCommandQueue()
        guard let device,
              let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vtx = library.makeFunction(name: "spike_vertex"),
              let frag = library.makeFunction(name: "spike_fragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vtx
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        let vdesc = MTLVertexDescriptor()
        vdesc.attributes[0].format = .float2
        vdesc.attributes[0].offset = 0
        vdesc.attributes[0].bufferIndex = 0
        vdesc.attributes[1].format = .float4
        vdesc.attributes[1].offset = 8
        vdesc.attributes[1].bufferIndex = 0
        vdesc.layouts[0].stride = MemoryLayout<Vertex>.stride
        desc.vertexDescriptor = vdesc
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let device,
              let queue,
              let pipeline,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let verts = buildVertices()
        if verts.count >= 2 {
            let bytes = verts.count * MemoryLayout<Vertex>.stride
            if vertexBuffer == nil || vertexCapacity < verts.count {
                vertexBuffer = device.makeBuffer(length: max(bytes, 4096), options: .storageModeShared)
                vertexCapacity = max(verts.count, 4096 / MemoryLayout<Vertex>.stride)
            }
            if let vertexBuffer {
                vertexBuffer.contents().copyMemory(from: verts, byteCount: bytes)
                enc.setRenderPipelineState(pipeline)
                enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                enc.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: verts.count)
            }
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func buildVertices() -> [Vertex] {
        guard let snap = snapshot, snap.frameCount > 1 else { return [] }
        let channels = min(16, snap.channelCount)
        var out: [Vertex] = []
        out.reserveCapacity(channels * snap.frameCount)
        for ch in 0..<channels {
            let yBase = 1.0 - (2.0 * (Float(ch) + 0.5) / Float(channels))
            let scale = 1.6 / Float(channels)
            for f in 0..<snap.frameCount {
                let x = -1.0 + 2.0 * Float(f) / Float(snap.frameCount - 1)
                let v = snap.samples[f * snap.channelCount + ch]
                out.append(Vertex(x: x, y: yBase + v * scale, r: 0.2, g: 0.9, b: 1.0, a: 0.9))
            }
        }
        return out
    }
}
