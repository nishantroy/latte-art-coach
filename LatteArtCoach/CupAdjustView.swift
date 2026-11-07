import LatteCore
import SwiftUI

/// Move and resize the cup outline by hand when detection got it wrong:
/// drag to move, pinch to resize. The pour is then re-scored with it.
struct CupAdjustView: View {
  let photo: UIImage
  let analysis: PourAnalysis
  let isManual: Bool
  /// Nil means go back to automatic detection.
  let onSave: (LatteCore.Ellipse?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var cup: LatteCore.Ellipse?
  @State private var dragStart: LatteCore.Ellipse?
  @State private var pinchStart: LatteCore.Ellipse?

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        Text("Drag the outline onto the rim of the coffee, and pinch to resize it.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        GeometryReader { proxy in
          let w = Double(analysis.imageWidth), h = Double(analysis.imageHeight)
          let scale = min(proxy.size.width / w, proxy.size.height / h)
          let size = CGSize(width: w * scale, height: h * scale)
          ZStack(alignment: .topLeading) {
            Image(uiImage: photo).resizable().frame(width: size.width, height: size.height)
            outline(current, scale: scale).allowsHitTesting(false)
          }
          .frame(width: size.width, height: size.height)
          .contentShape(.rect)
          .gesture(drag(scale: scale).simultaneously(with: pinch))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("cup-editor")
        if isManual {
          Button("Find the cup automatically") {
            onSave(nil)
            dismiss()
          }
          .tint(.crema)
        }
      }
      .padding()
      .background(Color.milk)
      .navigationTitle("Cup outline")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Re-score") {
            onSave(current)
            dismiss()
          }
          .disabled(cup == nil)
        }
      }
    }
  }

  private var current: LatteCore.Ellipse { cup ?? analysis.cup }

  private func outline(_ e: LatteCore.Ellipse, scale: Double) -> some View {
    Canvas { context, _ in
      var path = Path()
      for step in 0...120 {
        let t = Double(step) / 120 * 2 * .pi
        let q = e.point(unitX: cos(t), unitY: sin(t))
        let p = CGPoint(x: q.x * scale, y: q.y * scale)
        step == 0 ? path.move(to: p) : path.addLine(to: p)
      }
      context.stroke(path, with: .color(.black.opacity(0.4)), lineWidth: 5)
      context.stroke(path, with: .color(.measure), lineWidth: 2.5)
      let c = CGPoint(x: e.centerX * scale, y: e.centerY * scale)
      context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.measure))
    }
  }

  private func drag(scale: Double) -> some Gesture {
    DragGesture(minimumDistance: 2)
      .onChanged { value in
        let start = dragStart ?? current
        dragStart = start
        var moved = current
        moved.centerX = min(max(0, start.centerX + value.translation.width / scale), Double(analysis.imageWidth))
        moved.centerY = min(max(0, start.centerY + value.translation.height / scale), Double(analysis.imageHeight))
        cup = moved
      }
      .onEnded { _ in dragStart = nil }
  }

  private var pinch: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let start = pinchStart ?? current
        pinchStart = start
        let limit = Double(max(analysis.imageWidth, analysis.imageHeight)) / 2
        let factor = min(max(value.magnification, 0.2), limit / start.semiMajor)
        var resized = current
        resized.semiMajor = start.semiMajor * factor
        resized.semiMinor = start.semiMinor * factor
        cup = resized
      }
      .onEnded { _ in pinchStart = nil }
  }
}
