import QuartzCore
import SwiftUI

/// Graphics only. This view never generates puzzles, computes scores or decides deadlines.
struct CubeSceneView: View {
  let puzzle: CubePuzzle
  var illustration = false
  var interactive = false
  var revealCount: Int? = nil
  @State private var yaw: Float = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        NativeCubeSurface(
          puzzle: puzzle, illustration: illustration, yaw: yaw,
          reduceMotion: reduceMotion, revealCount: revealCount
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
  let revealCount: Int?

  func makeUIView(context: Context) -> CubeLayerView { CubeLayerView() }
  func updateUIView(_ view: CubeLayerView, context: Context) {
    view.configure(
      puzzle: puzzle, illustration: illustration, yaw: CGFloat(yaw), reduceMotion: reduceMotion,
      revealCount: revealCount)
  }
}

final class CubeLayerView: UIView {
  // Composite the ground below the entire cube scene. A floor tile's center
  // depth must never let it paint over a cube face that overlaps it on screen.
  private let ground = CATransformLayer()
  private let world = CATransformLayer()
  private var puzzle: CubePuzzle?
  private var illustration = false
  private var yaw: CGFloat = 0
  private var revealCount: Int?
  private var cubeFaces: [[CALayer]] = []
  private var framing = CGRect(x: -3, y: -3, width: 6, height: 6)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    ground.name = "cube-ground"
    world.name = "cube-world"
    layer.addSublayer(ground)
    layer.addSublayer(world)
    isAccessibilityElement = true
    accessibilityIdentifier = "cubeScene"
    accessibilityLabel =
      "Three-dimensional cube stack. Count all cubes, including hidden supporting cubes."
  }
  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

  func configure(
    puzzle: CubePuzzle, illustration: Bool, yaw: CGFloat, reduceMotion: Bool, revealCount: Int?
  ) {
    let changed = self.puzzle != puzzle || self.illustration != illustration
    if changed {
      self.puzzle = puzzle
      self.illustration = illustration
      rebuild(puzzle)
    }
    let rotated = self.yaw != yaw
    self.yaw = yaw
    let counting = self.revealCount != revealCount
    self.revealCount = revealCount
    CATransaction.begin()
    CATransaction.setDisableActions(changed || reduceMotion || !(rotated || counting))
    CATransaction.setAnimationDuration(0.2)
    if changed || rotated { updateFacing() }
    if changed || counting { updateReveal() }
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
    ground.position = world.position
    ground.transform = world.transform
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
    for tile in ground.sublayers ?? [] { tile.removeFromSuperlayer() }
    cubeFaces = []
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
          ground.addSublayer(tile)
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
      cubeFaces.append(container.sublayers ?? [])
    }
  }

  private func updateFacing() {
    let transform = camera(at: yaw)
    let normals: [(CGFloat, CGFloat, CGFloat)] = [
      (0, 0, 1), (0, 0, -1), (-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0),
    ]
    for faces in cubeFaces {
      for (face, normal) in zip(faces, normals) {
        // Use outward normals rather than CALayer's default double-sided drawing.
        // The existing screen-coordinate camera includes a reflection, so winding
        // based backface culling alone would hide the wrong faces.
        let depth = normal.0 * transform.m13 + normal.1 * transform.m23 + normal.2 * transform.m33
        face.isHidden = depth <= 0
      }
    }
  }

  private func updateReveal() {
    for (index, faces) in cubeFaces.enumerated() {
      let complete = revealCount == nil || revealCount! >= cubeFaces.count
      let active = !complete && index == (revealCount ?? 0) - 1
      let counted = index < (revealCount ?? 0)
      // Fade individual faces: CATransformLayer itself does not composite opacity.
      // Ghost faces make an interior/support cube visible while it is counted.
      for face in faces {
        face.opacity = complete || active ? 1 : counted ? 0.22 : 0.08
        face.borderWidth = active ? 0.026 : 0.012
        face.borderColor =
          active
          ? UIColor.white.withAlphaComponent(0.95).cgColor
          : UIColor(red: 0.34, green: 0.25, blue: 0.48, alpha: 0.45).cgColor
      }
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

/// Ordered render coordinates only, used exclusively with authorized finalized data.
struct CubeRevealPlan {
  let puzzle: CubePuzzle
  let answer: Int
  var interval: Double { min(0.28, 5.0 / Double(answer)) }
  init?(_ reveal: AnswerReveal) {
    let cubes = reveal.puzzle.cubes
    guard reveal.correctAnswer > 0, reveal.correctAnswer == cubes.count,
      Set(cubes).count == cubes.count
    else { return nil }
    // Count supporting layers first, then back-to-front in the fixed camera.
    let ordered = cubes.sorted {
      if $0.y != $1.y { return $0.y < $1.y }
      if $0.x + $0.z != $1.x + $1.z { return $0.x + $0.z > $1.x + $1.z }
      if $0.x != $1.x { return $0.x > $1.x }
      return $0.z > $1.z
    }
    puzzle = CubePuzzle(cubes: ordered, gridSize: reveal.puzzle.gridSize)
    answer = reveal.correctAnswer
  }
  func initialCount(reduceMotion: Bool) -> Int { reduceMotion ? answer : 0 }
}

struct CubeAnswerRevealView: View {
  let reveal: AnswerReveal
  var animationDurationLimit: Double = 5
  var missingAnswerText = "No answer was submitted."
  var finished: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var counted = 0
  @State private var didFinish = false
  private var plan: CubeRevealPlan? { CubeRevealPlan(reveal) }

  var body: some View {
    VStack(spacing: 14) {
      if let plan {
        Text(didFinish ? "Every cube accounted for." : "Let’s count them together.")
          .font(.system(.headline, design: .rounded, weight: .bold))
        ZStack(alignment: .topLeading) {
          CubeSceneView(puzzle: plan.puzzle, revealCount: counted)
          Text("\(counted)").font(.system(size: 34, weight: .heavy, design: .rounded))
            .monospacedDigit().padding(14).background(
              .white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18)
            )
            .padding(12).accessibilityIdentifier("revealCount")
        }.frame(height: 240)
        Text("Including the hidden and supporting cubes.")
          .font(.caption).foregroundStyle(BattleTheme.muted)
        if didFinish {
          Text("Correct answer: \(reveal.correctAnswer)")
            .font(.system(.title2, design: .rounded, weight: .bold)).accessibilityIdentifier(
              "correctAnswer")
          Text(reveal.submittedAnswer.map { "Your answer: \($0)" } ?? missingAnswerText)
            .font(.subheadline).foregroundStyle(BattleTheme.muted)
        } else {
          Button("Skip reveal") { finish(plan) }.frame(minHeight: 44)
            .accessibilityIdentifier("skipReveal")
        }
      } else {
        Text("The answer reveal could not be loaded.").foregroundStyle(BattleTheme.muted)
      }
    }
    .task {
      guard let plan else {
        didFinish = true
        finished()
        return
      }
      counted = plan.initialCount(reduceMotion: reduceMotion)
      if counted == plan.answer {
        finish(plan)
        return
      }
      while counted < plan.answer && !Task.isCancelled {
        let interval = min(plan.interval, max(0, animationDurationLimit) / Double(plan.answer))
        do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        guard !Task.isCancelled, !didFinish else { return }
        counted += 1
      }
      if !Task.isCancelled { finish(plan) }
    }
    .onChange(of: reduceMotion) { _, reduced in if reduced, let plan { finish(plan) } }
    .onChange(of: scenePhase) { _, phase in if phase != .active, let plan { finish(plan) } }
  }
  private func finish(_ plan: CubeRevealPlan) {
    counted = plan.answer
    guard !didFinish else { return }
    didFinish = true
    finished()
  }
}
