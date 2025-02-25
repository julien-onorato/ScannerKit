//
//  Main.swift
//  ScannerKit
//
//  Created by Julien Onorato on 25/02/2025.
//

import UIKit
import SwiftUI
@preconcurrency import AVFoundation

actor CodeScannerProcessor {
    func processScannedCode(_ code: String) async -> String {
        // Perform any asynchronous processing if needed.
        // Here we simply forward the code on the main actor.
        return code
    }
}

@MainActor
final class ScannerViewModel: NSObject, ObservableObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String = ""
    let session = AVCaptureSession()
    let processor = CodeScannerProcessor()
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput)
        else {
            print("Unable to access camera input.")
            return
        }
        session.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            print("Cannot add metadata output.")
            return
        }
        session.addOutput(metadataOutput)
        
        // Set the delegate on the main queue.
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr, .ean13, .code128] // Add more types if needed.
    }
    
    func startSession() async {
        if !session.isRunning {
            await withCheckedContinuation { continuation in
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    
                    // Access session on the main actor
                    await MainActor.run {
                        self.session.startRunning()
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    func stopSession() async {
        if session.isRunning {
            await withCheckedContinuation { continuation in
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    
                    // Access session on the main actor
                    await MainActor.run {
                        self.session.stopRunning()
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let code = metadataObject.stringValue {
            // Use a Task to call our actor method asynchronously.
            Task { [weak self] in
                guard let self = self else { return }
                let processedCode = await self.processor.processScannedCode(code)
                self.scannedCode = processedCode
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Set the correct frame size immediately.
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
        }
        
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
        
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}

public struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Display the camera preview.
            CameraPreview(session: viewModel.session)
                .edgesIgnoringSafeArea(.all)
                .tint(.blue)
            
            // Overlay with the scanned code.
            VStack {
                Spacer()
                Text("Scanned Code: \(viewModel.scannedCode)")
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            Task(priority: .background) {
                await viewModel.startSession()
            }
            
        }
        .onDisappear {
            Task(priority: .background) {
                await viewModel.stopSession()
            }
            
        }
    }
}
