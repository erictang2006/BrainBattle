import QuartzCore
import SwiftUI

/// Graphics only. This view never generates puzzles, computes scores or decides deadlines.
struct CubeSceneView: View {
  let puzzle: CubePuzzle
  var illustration = false
  var interactive = false
  @State private var yaw: Float = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        NativeCubeSurface(
          puzzle: puzzle, illustration: illustration, yaw: yaw,
          reduceMotion: reduceMotion
        )
        .frame(
          width: geometry.size.width,
          height: max(1, geometry.size.height - (interactive ? 56 : 0)))
        if interactive {
          HStack(spacing: 24) {
            Button {
              rotate(-0.15)
            } label: {
              Image(systemName: "rotate.left")
            }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Rotate stack left")
            Button("Reset view") { yaw = 0 }.font(.caption.weight(.semibold)).frame(minHeight: 44)
            Button {
              rotate(0.15)
            } label: {
              Image(systemName: "rotate.right")
            }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Rotate stack right")
          }
          .foregroundStyle(BattleTheme.muted).buttonStyle(.plain)
          .padding(.horizontal, 12)
          .background(.white.opacity(0.85), in: Capsule()).padding(.bottom, 12)
        }
      }
    }
    .background(BattleTheme.lavender.opacity(0.6), in: RoundedRectangle(cornerRadius: 26))
    .clipShape(RoundedRectangle(cornerRadius: 26))
    .sensoryFeedback(.selection, trigger: yaw)
  }
  private func rotate(_ delta: Float) {
    if reduceMotion {
      yaw = min(0.55, max(-0.55, yaw + delta))
    } else {
      withAnimation(.easeInOut(duration: 0.2)) { yaw = min(0.55, max(-0.55, yaw + delta)) }
    }
  }
}

/// Native 3D Core Animation layers avoid RealityKit shader passes unsupported by
/// some Simulator GPUs. All six faces use real 3D transforms and depth ordering.
private struct NativeCubeSurface: UIViewRepresentable {
  let puzzle: CubePuzzle
  let illustration: Bool
  let yaw: Float
  let reduceMotion: Bool

  func makeUIView(context: Context) -> CubeLayerView { CubeLayerView() }
  func updateUIView(_ view: CubeLayerView, context: Context) {
    view.configure(
      puzzle: puzzle, illustration: illustration, yaw: CGFloat(yaw), reduceMotion: reduceMotion)
  }
}

private final class CubeLayerView: UIView {
  private let world = CATransformLayer()
  private var puzzle: CubePuzzle?
  private var illustration = false
  private var yaw: CGFloat = 0
  private var framing = CGRect(x: -3, y: -3, width: 6, height: 6)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    layer.addSublayer(world)
    isAccessibilityElement = true
    accessibilityIdentifier = "cubeScene"
    accessibilityLabel =
      "Three-dimensional cube stack. Count all cubes, including hidden supporting cubes."
  }
  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

  func configure(puzzle: CubePuzzle, illustration: Bool, yaw: CGFloat, reduceMotion: Bool) {
    let changed = self.puzzle != puzzle || self.illustration != illustration
    if changed {
      self.puzzle = puzzle
      self.illustration = illustration
      rebuild(puzzle)
    }
    let rotated = self.yaw != yaw
    self.yaw = yaw
    CATransaction.begin()
    CATransaction.setDisableActions(changed || reduceMotion || !rotated)
    CATransaction.setAnimationDuration(0.2)
    positionScene()
    CATransaction.commit()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    positionScene()
    CATransaction.commit()
  }

  private func positionScene() {
    // Orthographic camera from (-x, +y, -z), matching the public puzzle orientation.
    let scale = max(
      1, min((bounds.width - 44) / framing.width, (bounds.height - 28) / framing.height))
    let rotated = camera(at: yaw)
    world.position = CGPoint(
      x: bounds.midX - framing.midX * scale, y: bounds.midY - framing.midY * scale)
    world.transform = CATransform3DScale(rotated, scale, scale, scale)
  }

  private func camera(at yaw: CGFloat) -> CATransform3D {
    var camera = CATransform3DIdentity
    camera.m11 = 0.707107
    camera.m21 = 0
    camera.m31 = -0.707107
    camera.m12 = -0.366508
    camera.m22 = 0.855186
    camera.m32 = -0.366508
    camera.m13 = -0.604708
    camera.m23 = -0.518321
    camera.m33 = -0.604708
    return CATransform3DConcat(CATransform3DMakeRotation(yaw, 0, 1, 0), camera)
  }

  private func rebuild(_ puzzle: CubePuzzle) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    for layer in world.sublayers ?? [] { layer.removeFromSuperlayer() }
    let centerX =
      puzzle.gridSize.map { CGFloat($0 - 1) / 2 }
      ?? CGFloat(puzzle.cubes.map(\.x).max() ?? 2) / 2
    let centerZ =
      puzzle.gridSize.map { CGFloat($0 - 1) / 2 }
      ?? CGFloat(puzzle.cubes.map(\.z).max() ?? 2) / 2
    // Fit all public cube corners across the bounded rotation range. Framing stays
    // stable while rotating; no scene animation, spin, or zoom consumes display time.
    var projected: [CGPoint] = []
    let corners: [CGFloat] = [-0.5, 0.5]
    if let size = puzzle.gridSize {
      for x in 0..<size {
        for z in 0..<size {
          let tile = CALayer()
          tile.bounds = CGRect(x: 0, y: 0, width: 0.98, height: 0.98)
          tile.position = .zero
          tile.backgroundColor = UIColor(red: 0.91, green: 0.87, blue: 0.96, alpha: 0.55).cgColor
          tile.borderColor = UIColor(red: 0.67, green: 0.59, blue: 0.79, alpha: 0.32).cgColor
          tile.borderWidth = 0.012
          tile.transform = CATransform3DRotate(
            CATransform3DMakeTranslation(
              CGFloat(x) - centerX, 0.51, CGFloat(z) - centerZ), .pi / 2, 1, 0, 0)
          world.addSublayer(tile)
        }
      }
      let transform = camera(at: 0)
      for x in [-0.5, CGFloat(size) - 0.5] {
        for z in [-0.5, CGFloat(size) - 0.5] {
          let px = x - centerX
          let pz = z - centerZ
          projected.append(
            CGPoint(
              x: px * transform.m11 + pz * transform.m31,
              y: px * transform.m12 + 0.51 * transform.m22 + pz * transform.m32))
        }
      }
    }
    for angle in stride(from: -0.55, through: 0.55, by: 0.11) {
      let transform = camera(at: CGFloat(angle))
      for cube in puzzle.cubes {
        for dx in corners {
          for dy in corners {
            for dz in corners {
              let x = CGFloat(cube.x) - centerX + dx
              let y = -CGFloat(cube.y) + dy
              let z = CGFloat(cube.z) - centerZ + dz
              projected.append(
                CGPoint(
                  x: x * transform.m11 + y * transform.m21 + z * transform.m31,
                  y: x * transform.m12 + y * transform.m22 + z * transform.m32))
            }
          }
        }
      }
    }
    if let minX = projected.map(\.x).min(), let maxX = projected.map(\.x).max(),
      let minY = projected.map(\.y).min(), let maxY = projected.map(\.y).max()
    {
      framing = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
    let base =
      illustration
      ? UIColor(red: 0.96, green: 0.61, blue: 0.31, alpha: 1)
      : UIColor(red: 0.60, green: 0.50, blue: 0.81, alpha: 1)
    let half: CGFloat = 0.487
    let sides: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0, 0, half, 0, 0, 0.94), (0, 0, -half, 0, .pi, 0.85),
      (-half, 0, 0, 0, -.pi / 2, 0.92), (half, 0, 0, 0, .pi / 2, 1.02),
      (0, -half, 0, .pi / 2, 0, 1.20), (0, half, 0, -.pi / 2, 0, 0.72),
    ]
    for cube in puzzle.cubes {
      let container = CATransformLayer()
      container.transform = CATransform3DMakeTranslation(
        CGFloat(cube.x) - centerX, -CGFloat(cube.y), CGFloat(cube.z) - centerZ)
      for (x, y, z, rotateX, rotateY, shade) in sides {
        let face = CALayer()
        face.bounds = CGRect(x: 0, y: 0, width: half * 2, height: half * 2)
        face.position = .zero
        face.backgroundColor = tint(base, by: shade).cgColor
        face.borderWidth = 0.012
        face.borderColor = UIColor(red: 0.34, green: 0.25, blue: 0.48, alpha: 0.45).cgColor
        face.allowsEdgeAntialiasing = true
        var transform = CATransform3DMakeTranslation(x, y, z)
        transform = CATransform3DRotate(transform, rotateX, 1, 0, 0)
        transform = CATransform3DRotate(transform, rotateY, 0, 1, 0)
        face.transform = transform
        container.addSublayer(face)
      }
      world.addSublayer(container)
    }
  }

  private func tint(_ color: UIColor, by factor: CGFloat) -> UIColor {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 1
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return UIColor(
      red: min(1, r * factor), green: min(1, g * factor), blue: min(1, b * factor), alpha: 1)
  }
}
