import SwiftUI
import SceneKit

/// A real 3D bar chart of the profile's top games by playtime, on a reflective floor, slowly
/// turning like a trophy shelf. Drag to orbit it. Built with SceneKit so it's genuinely
/// dimensional, not a faked perspective. Colors match the 2D legend rendered beside it.
struct Stats3DView: NSViewRepresentable {
    let values: [Double]
    let accentIndex: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.scene = buildScene()
        context.coordinator.signature = signature
        rebuildBars(in: view.scene, context: context)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        rebuildBars(in: view.scene, context: context)
    }

    final class Coordinator { var signature = "" }

    /// Cheap change token so we only rebuild bars when the data actually moves.
    private var signature: String {
        "\(accentIndex)|" + values.map { String(Int($0)) }.joined(separator: ",")
    }

    // MARK: - Scene

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        let floor = SCNFloor()
        floor.reflectivity = 0.12
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.04, alpha: 1)
        floor.firstMaterial?.lightingModel = .physicallyBased
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)

        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.wantsHDR = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3.4, 9)
        cameraNode.eulerAngles = SCNVector3(-0.32, 0, 0)   // tilt down toward the bars
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 320
        ambient.color = NSColor(calibratedWhite: 0.7, alpha: 1)
        let ambientNode = SCNNode(); ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .omni
        key.intensity = 1400
        let acc = AccentPalette.option(accentIndex)
        key.color = NSColor(hue: acc.hue, saturation: 0.35, brightness: 1, alpha: 1)
        let keyNode = SCNNode(); keyNode.light = key
        keyNode.position = SCNVector3(-5, 9, 6)
        scene.rootNode.addChildNode(keyNode)

        let container = SCNNode()
        container.name = "bars"
        scene.rootNode.addChildNode(container)
        container.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 34)))

        return scene
    }

    private func rebuildBars(in scene: SCNScene?, context: Context) {
        guard let container = scene?.rootNode.childNode(withName: "bars", recursively: false) else { return }
        container.childNodes.forEach { $0.removeFromParentNode() }

        let data = Array(values.prefix(8))
        guard !data.isEmpty else { return }
        let maxV = max(data.max() ?? 1, 1)
        let colors = StatPalette.colors(data.count, accentIndex: accentIndex)
        let spacing: Float = 1.35
        let totalWidth = Float(data.count - 1) * spacing
        let startX = -totalWidth / 2

        for (i, value) in data.enumerated() {
            let h = CGFloat(0.25 + (value / maxV) * 3.4)
            let box = SCNBox(width: 0.8, height: h, length: 0.8, chamferRadius: 0.05)
            let mat = SCNMaterial()
            let nsColor = NSColor(colors[i])
            mat.diffuse.contents = nsColor
            mat.emission.contents = NSColor(colors[i].opacity(0.35))
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 0.25
            mat.roughness.contents = 0.35
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(startX + Float(i) * spacing, Float(h) / 2, 0)
            container.addChildNode(node)
        }
    }
}
