//
//  ScannerView.swift
//  ScannerKit
//
//  Created by Julien Onorato on 14/12/2024.
//

import SwiftUI
import AVFoundation

@available(iOS 15.0, *)
public struct ScannerView: View {
    @StateObject private var viewModel: ScannerViewModel
    
    public init(
        configuration: ScannerConfig,
        manualSelect: Bool = false,
        scanInterval: Double = 2.0,
        showViewfinder: Bool = false,
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
        }
        .onAppear(perform: viewModel.checkPermissions)
        .onDisappear(perform: viewModel.stopScanning)
        .gesture(
            TapGesture().onEnded { location in
                viewModel.focusCamera(at: .zero)
            }
        )
    }
}

@available(iOS 15.0, *)
class ScannerViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var permissionDenied = false
    
    let configuration: ScannerConfig
    let manualSelect: Bool
    let scanInterval: Double
    let showViewfinder: Bool
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
        self.shouldVibrateOnSuccess = shouldVibrateOnSuccess
        self.isTorchOn = isTorchOn
        self.isPaused = isPaused
        self.videoCaptureDevice = videoCaptureDevice
        self.completion = completion
        
        super.init()
    }
    
    @MainActor
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
    
    @MainActor
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
            Task {
                startCaptureSession()
            }
        } catch {
            completion(.failure(.initError(error)))
        }
    }
    
    func startCaptureSession() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    func stopScanning() {
        if captureSession.isRunning {
            self.captureSession.stopRunning()
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
