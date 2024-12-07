//
//  ScannerView.swift
//  ScannerKit
//
//  Created by Julien Onorato on 07/12/2024.
//


import SwiftUI
import AVFoundation

@available(iOS 15.0, macCatalyst 14.0, *)
public struct ScannerView: View {
    @StateObject private var viewModel: ScannerViewModel
    
    public init(
        configuration: ScannerConfig,
        manualSelect: Bool = false,
        scanInterval: Double = 2.0,
        showViewfinder: Bool = false,
        simulatedData: String = "",
        shouldVibrateOnSuccess: Bool = true,
        isTorchOn: Bool = false,
        isPaused: Bool = false,
        videoCaptureDevice: AVCaptureDevice? = AVCaptureDevice.bestForVideo,
        completion: @escaping (Result<ScanResult, ScanError>) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(
            configuration: configuration,
            manualSelect: manualSelect,
            scanInterval: scanInterval,
            showViewfinder: showViewfinder,
            simulatedData: simulatedData,
            shouldVibrateOnSuccess: shouldVibrateOnSuccess,
            isTorchOn: isTorchOn,
            isPaused: isPaused,
            videoCaptureDevice: videoCaptureDevice,
            completion: completion
        ))
    }
    
    public var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: viewModel.captureSession)
                .ignoresSafeArea()
            
            // Viewfinder overlay
            if viewModel.showViewfinder {
                Image(systemName: "viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .foregroundColor(.white)
                    .opacity(0.7)
            }
            
            // Error and permission handling
            if viewModel.permissionDenied {
                PermissionDeniedView()
            }
            
            // Simulator support
            #if targetEnvironment(simulator)
            SimulatorOverlay(simulatedData: viewModel.simulatedData, 
                             completion: viewModel.simulateCodeScan)
            #endif
        }
        .onAppear(perform: viewModel.checkPermissions)
        .onDisappear(perform: viewModel.stopScanning)
        .gesture(
            TapGesture().onEnded { location in
//                viewModel.focusCamera(at: location)
            }
        )
    }
}

@available(iOS 15.0, macCatalyst 14.0, *)
@MainActor
class ScannerViewModel: NSObject, ObservableObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    @Published var permissionDenied = false
    
    let configuration: ScannerConfig
    let manualSelect: Bool
    let scanInterval: Double
    let showViewfinder: Bool
    let simulatedData: String
    let shouldVibrateOnSuccess: Bool
    let isTorchOn: Bool
    let isPaused: Bool
    let videoCaptureDevice: AVCaptureDevice?
    let completion: (Result<ScanResult, ScanError>) -> Void
    
    let captureSession = AVCaptureSession()
    private var codesFound = Set<String>()
    private var lastScanTime = Date(timeIntervalSince1970: 0)
    
    init(
        configuration: ScannerConfig,
        manualSelect: Bool = false,
        scanInterval: Double = 2.0,
        showViewfinder: Bool = false,
        simulatedData: String = "",
        shouldVibrateOnSuccess: Bool = true,
        isTorchOn: Bool = false,
        isPaused: Bool = false,
        videoCaptureDevice: AVCaptureDevice? = AVCaptureDevice.bestForVideo,
        completion: @escaping (Result<ScanResult, ScanError>) -> Void
    ) {
        self.configuration = configuration
        self.manualSelect = manualSelect
        self.scanInterval = scanInterval
        self.showViewfinder = showViewfinder
        self.simulatedData = simulatedData
        self.shouldVibrateOnSuccess = shouldVibrateOnSuccess
        self.isTorchOn = isTorchOn
        self.isPaused = isPaused
        self.videoCaptureDevice = videoCaptureDevice
        self.completion = completion
        
        super.init()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }
    
    private func setupCaptureSession() {
        // Camera setup logic
        guard let videoCaptureDevice = videoCaptureDevice ?? AVCaptureDevice.default(for: .video) else {
            completion(.failure(.initError(NSError(domain: "ScannerView", code: -1))))
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                metadataOutput.metadataObjectTypes = configuration.codeTypes
            }
            
            // Start capture session
            DispatchQueue.main.async {
                self.captureSession.startRunning()
            }
        } catch {
            completion(.failure(.initError(error)))
        }
    }
    
    func stopScanning() {
        if captureSession.isRunning {
            DispatchQueue.main.async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func focusCamera(at location: CGPoint) {
        // Camera focus logic
        guard let device = videoCaptureDevice ?? AVCaptureDevice.default(for: .video),
              device.isFocusPointOfInterestSupported else { return }
        
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = location
            device.focusMode = .continuousAutoFocus
            device.exposurePointOfInterest = location
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        } catch {
            print("Error focusing camera: \(error.localizedDescription)")
        }
    }
    
    func simulateCodeScan() {
        let result = ScanResult(
            string: simulatedData,
            type: configuration.codeTypes.first ?? .qr,
            corners: []
        )
        processFoundCode(result)
    }
    
    private func processFoundCode(_ result: ScanResult) {
        guard !isPaused else { return }
        
        let currentTime = Date()
        let timeSinceLastScan = currentTime.timeIntervalSince(lastScanTime)
        
        switch configuration.mode {
        case .once:
            completeScanning(with: result)
        case .oncePerCode:
            if !codesFound.contains(result.string) {
                codesFound.insert(result.string)
                completeScanning(with: result)
            }
        case .continuous:
            if timeSinceLastScan >= scanInterval {
                completeScanning(with: result)
            }
        case .continuousExcept(let ignoredList):
            if timeSinceLastScan >= scanInterval && !ignoredList.contains(result.string) {
                completeScanning(with: result)
            }
        }
    }
    
    private func completeScanning(with result: ScanResult) {
        lastScanTime = Date()
        
        if shouldVibrateOnSuccess {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
        
        completion(.success(result))
    }
    
    // AVCaptureMetadataOutputObjectsDelegate method
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }
        
        let result = ScanResult(
            string: stringValue, 
            type: metadataObject.type, 
            corners: metadataObject.corners
        )
        processFoundCode(result)
    }
}

// CameraPreview for rendering capture session
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.frame = uiView.bounds
    }
}

// Permission Denied View
struct PermissionDeniedView: View {
    var body: some View {
        VStack {
            Text("Camera Access Needed")
                .font(.headline)
            Text("Please enable camera access in Settings")
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}

// Simulator Overlay
#if targetEnvironment(simulator)
struct SimulatorOverlay: View {
    let simulatedData: String
    let completion: () -> Void
    
    var body: some View {
        VStack {
            Text("Simulator Mode")
            Text("Tap to simulate scan of: \(simulatedData)")
            Button("Simulate Scan") {
                completion()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
}
#endif

// Preview
@available(iOS 15.0, macCatalyst 14.0, *)
#Preview {
    let configuration = ScannerConfig(
        codeTypes: [.qr], 
        mode: .once,
        allowTorchToggle: false
    )
    
    ScannerView(configuration: configuration) { result in
        // Preview handler
        switch result {
        case .success(let scanResult):
            print("Scanned: \(scanResult.string)")
        case .failure(let error):
            print("Error: \(error)")
        }
    }
}
