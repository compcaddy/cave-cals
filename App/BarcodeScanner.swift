import SwiftUI
import AVFoundation

struct BarcodeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var editor: EntryDraft?
    @State private var loading = false
    @State private var message: String?
    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        if let editor {
            EntryEditorSheet(draft: editor).id(editor.id)
        } else {
            scanner
        }
    }

    private var scanner: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if permission == .authorized, cameraError == nil, !loading {
                        CameraScanner(onCode: lookup, onError: { cameraError = $0 })
                            .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.8), lineWidth: 2).frame(width: 230, height: 130).allowsHitTesting(false) }
                            .accessibilityLabel("Barcode camera view")
                        Text("Hold Barcode in Frame").font(.cave(.subheadline)).foregroundStyle(.secondary)
                    } else if permission == .denied || permission == .restricted || cameraError != nil {
                        ContentUnavailableView { Label { Text("Camera unavailable") } icon: { CaveIcon(.camera, size: 48) } } description: { Text("Make sure you have granted this app access to your camera.") }
                        if permission == .denied { Button("Open Camera Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                    }
                    if loading { ProgressView("Looking up barcode…") }
                    if let message { Text(message).font(.cave(.subheadline)).foregroundStyle(.secondary) }
                }.padding(20)
            }.caveScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CaptureCancelButton {
                    task?.cancel()
                    dismiss()
                }
            }
            .navigationTitle("Barcode Scan").navigationBarTitleDisplayMode(.inline)
            .task {
                guard AVCaptureDevice.default(for: .video) != nil else { cameraError = "Camera unavailable. Make sure you have granted this app access to your camera."; return }
                if permission == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video); permission = AVCaptureDevice.authorizationStatus(for: .video) }
            }
            .onDisappear { task?.cancel() }
        }
    }

    private func lookup(_ raw: String) {
        guard !loading, editor == nil else { return }
        let cleaned = raw.filter(\.isNumber)
        guard (8...14).contains(cleaned.count) else { return }
        loading = true; message = nil
        task?.cancel()
        task = Task { @MainActor in
            var draft = store.localBarcode(cleaned)
            if draft == nil {
                do { draft = try await OpenFoodFacts.shared.lookup(barcode: cleaned)?.draft }
                catch { if !Task.isCancelled { message = "Lookup is unavailable. Enter calories to save this barcode for next time." } }
            }
            guard !Task.isCancelled else { return }
            loading = false
            if var draft { draft.timestamp = date; draft.entryID = nil; draft.source = "barcode"; editor = draft }
            else {
                if message == nil { message = "Barcode not found. Save it once to use it next time." }
                var manual = EntryDraft(timestamp: date); manual.barcode = cleaned; manual.source = "barcode"; editor = manual
            }
        }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraScanner: UIViewRepresentable {
    var detectsBarcodes = true
    var onCode: (String) -> Void
    var onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(detectsBarcodes: detectsBarcodes, onCode: onCode, onError: onError) }
    func makeUIView(context: Context) -> UIView {
        let view = PreviewView()
        view.preview.session = context.coordinator.session; view.preview.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "ecc.camera")
        private var delivered = false
        let onCode: (String) -> Void
        let onError: (String) -> Void
        let detectsBarcodes: Bool
        init(detectsBarcodes: Bool, onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.detectsBarcodes = detectsBarcodes; self.onCode = onCode; self.onError = onError
        }
        func start() {
            queue.async {
                do {
                    guard let device = AVCaptureDevice.default(for: .video) else { throw ScannerError.noCamera }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureMetadataOutput()
                    self.session.beginConfiguration()
                    guard self.session.canAddInput(input) else { self.session.commitConfiguration(); throw ScannerError.noCamera }
                    self.session.addInput(input)
                    if self.detectsBarcodes {
                        guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); throw ScannerError.noCamera }
                        self.session.addOutput(output)
                        output.setMetadataObjectsDelegate(self, queue: .main)
                        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128].filter { output.availableMetadataObjectTypes.contains($0) }
                    }
                    self.session.commitConfiguration(); self.session.startRunning()
                } catch { DispatchQueue.main.async { self.onError("Camera unavailable. Make sure you have granted this app access to your camera.") } }
            }
        }
        func stop() { queue.async { self.session.stopRunning() } }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            delivered = true; onCode(value); stop()
        }
    }
    private enum ScannerError: Error { case noCamera }
}
