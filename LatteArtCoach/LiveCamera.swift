@preconcurrency import AVFoundation
import CoreImage
import LatteCore
import SwiftUI

/// What the live check found on the latest camera frame.
struct LiveFrame: Sendable {
  var framing: Framing
  /// The cup, in frame pixels.
  var cup: LatteCore.Ellipse?
  var foam: CGImage?
  /// Size of the frame the geometry is in (portrait).
  var width: Int
  var height: Int
}

/// Runs the camera: a preview, a live framing check on frames a few times a
/// second, and full-resolution photo capture. Session work happens on its
/// own queue.
final class LiveCamera: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate,
  AVCapturePhotoCaptureDelegate
{
  static var isAvailable: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

  let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "camera.session")
  private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInitiated)
  private let ciContext = CIContext(options: [.cacheIntermediates: false])
  /// Touched only on `frameQueue`.
  private var lastCheck = Date.distantPast
  private var pattern: Pattern = .tulip
  private var onFrame: (@Sendable (LiveFrame) -> Void)?
  private var onPhoto: (@Sendable (Data?) -> Void)?

  func start(pattern: Pattern, onFrame: @escaping @Sendable (LiveFrame) -> Void) {
    frameQueue.async {
      self.pattern = pattern
      self.onFrame = onFrame
    }
    sessionQueue.async {
      if self.session.inputs.isEmpty { self.configure() }
      if !self.session.isRunning { self.session.startRunning() }
    }
  }

  func stop() {
    sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
  }

  func capture(_ completion: @escaping @Sendable (Data?) -> Void) {
    sessionQueue.async {
      self.onPhoto = completion
      let settings = AVCapturePhotoSettings()
      settings.photoQualityPrioritization = .balanced
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  private func configure() {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .photo
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
          let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
    else { return }
    session.addInput(input)
    if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
    if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
    // Portrait frames and photos: the app is portrait-only.
    for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
      if let connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
    // Close-up focus on a cup a forearm away.
    if (try? device.lockForConfiguration()) != nil {
      if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
      if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
      device.unlockForConfiguration()
    }
  }

  // MARK: Frames

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    // About five checks a second; the analysis takes tens of milliseconds.
    guard Date().timeIntervalSince(lastCheck) > 0.2, let onFrame,
          let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
          let image = downscaled(buffer)
    else { return }
    lastCheck = Date()
    let check = Framing.check(image, pattern: pattern)
    onFrame(LiveFrame(framing: check.framing, cup: check.cup, foam: check.foamOverlay?.makeCGImage(),
                      width: image.width, height: image.height))
  }

  /// The frame at analysis size, as RGBA.
  private func downscaled(_ buffer: CVPixelBuffer) -> RGBAImage? {
    let source = CIImage(cvPixelBuffer: buffer)
    let scale = Double(PourAnalysis.analysisDimension) / max(source.extent.width, source.extent.height)
    let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    // Through CGImage so rows come out top first, like a decoded photo.
    guard let cg = ciContext.createCGImage(scaled, from: scaled.extent.integral) else { return nil }
    return try? RGBAImage(cgImage: cg)
  }

  // MARK: Photos

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    let data = error == nil ? photo.fileDataRepresentation() : nil
    sessionQueue.async {
      self.onPhoto?(data)
      self.onPhoto = nil
    }
  }
}

/// The in-app camera: live preview with the cup and foam outlined as you
/// frame, and a hint until the shot is good. No score here: the user rates
/// the pour before seeing one.
struct LiveCameraView: View {
  let pattern: Pattern
  let onFinish: (Data?) -> Void
  @State private var camera = LiveCamera()
  @State private var frame: LiveFrame?
  @State private var capturing = false
  @State private var denied = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if denied {
        ContentUnavailableView {
          Label("Camera is off", systemImage: "camera.fill")
        } description: {
          Text("Allow camera access for Lattelier in Settings, or choose a photo instead.")
        } actions: {
          Button("Close") { onFinish(nil) }.buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
      } else {
        GeometryReader { proxy in
          ZStack {
            CameraPreview(session: camera.session)
            if let frame { overlay(frame, in: proxy.size) }
          }
        }
        .ignoresSafeArea()
        controls
      }
    }
    .task {
      if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
        _ = await AVCaptureDevice.requestAccess(for: .video)
      }
      guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { denied = true; return }
      camera.start(pattern: pattern) { live in
        Task { @MainActor in frame = live }
      }
    }
    .onDisappear { camera.stop() }
    .statusBarHidden()
  }

  private var ready: Bool { frame?.framing == .ready }

  private var controls: some View {
    VStack {
      HStack {
        Button { onFinish(nil) } label: {
          Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Close")
        Spacer()
        Label { Text(pattern.displayName) } icon: { PatternGlyph(pattern: pattern).frame(width: 14, height: 14) }
          .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
          .glassEffect(.regular, in: .capsule)
      }
      .padding(.horizontal)
      Spacer()
      Text(frame?.framing.hint ?? "Point the camera down at the cup")
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(ready ? .regular.tint(Color.measure.opacity(0.5)) : .regular, in: .capsule)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: frame?.framing)
        .accessibilityIdentifier("framing-hint")
      Button {
        capturing = true
        camera.capture { data in
          Task { @MainActor in onFinish(data) }
        }
      } label: {
        ZStack {
          Circle().strokeBorder(ready ? Color.measure : .white, lineWidth: 4).frame(width: 78, height: 78)
          Circle().fill(.white).frame(width: 64, height: 64)
          if capturing { ProgressView() }
        }
      }
      .disabled(capturing)
      .accessibilityLabel("Take photo")
      .padding(.vertical, 20)
      .sensoryFeedback(.impact(weight: .light), trigger: ready) { _, now in now }
    }
    .foregroundStyle(.white)
  }

  /// Cup outline and foam, mapped like the preview's aspect fill.
  private func overlay(_ frame: LiveFrame, in size: CGSize) -> some View {
    let w = Double(frame.width), h = Double(frame.height)
    let scale = max(size.width / w, size.height / h)
    let dx = (size.width - w * scale) / 2, dy = (size.height - h * scale) / 2
    return ZStack(alignment: .topLeading) {
      if let foam = frame.foam {
        FoamTint(mask: foam)
          .frame(width: w * scale, height: h * scale)
          .offset(x: dx, y: dy)
      }
      if let cup = frame.cup {
        Canvas { context, _ in
          var outline = Path()
          for step in 0...90 {
            let t = Double(step) / 90 * 2 * .pi
            let q = cup.point(unitX: cos(t), unitY: sin(t))
            let p = CGPoint(x: q.x * scale + dx, y: q.y * scale + dy)
            step == 0 ? outline.move(to: p) : outline.addLine(to: p)
          }
          context.stroke(outline, with: .color(ready ? .measure : .white.opacity(0.8)),
                         style: StrokeStyle(lineWidth: ready ? 3 : 2, dash: ready ? [] : [6, 5]))
        }
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }
}

private struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession

  final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
      super.layoutSubviews()
      // The connection appears once the session has inputs.
      if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90),
         connection.videoRotationAngle != 90 {
        connection.videoRotationAngle = 90
      }
    }
  }

  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
      connection.videoRotationAngle = 90
    }
    return view
  }

  func updateUIView(_ view: PreviewView, context: Context) { view.setNeedsLayout() }
}
