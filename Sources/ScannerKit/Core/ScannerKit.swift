//
//  ScannerKit.swift
//  ScannerKit
//
//  Created by Julien Onorato on 03/12/2024.
//

#if os(iOS)
import Foundation
import AVFoundation
import SwiftUI

/// A SwiftUI view that is able to scan barcodes, QR codes, and more, and send back what was found.
/// To use, set `codeTypes` to be an array of things to scan for, e.g. `[.qr]`, and set `completion` to
/// a closure that will be called when scanning has finished. This will be sent the string that was detected or a `ScanError`.
/// For testing inside the simulator, set the `simulatedData` property to some test data you want to send back.
@available(macCatalyst 14.0, *)
public struct ScannerzView: UIViewControllerRepresentable {
    
    public let configuration: ScannerConfig
    public let manualSelect: Bool
    public let scanInterval: Double
    public let showViewfinder: Bool
    public var simulatedData = ""
    public var shouldVibrateOnSuccess: Bool
    public var isTorchOn: Bool
    public var isPaused: Bool
    public var videoCaptureDevice: AVCaptureDevice?
    public var completion: (Result<ScanResult, ScanError>) -> Void

    public init(
        configuration: ScannerConfig,
        manualSelect: Bool = false,
        scanInterval: Double = 2.0,
        showViewfinder: Bool = false,
        requiresPhotoOutput: Bool = true,
        simulatedData: String = "",
        shouldVibrateOnSuccess: Bool = true,
        isTorchOn: Bool = false,
        isPaused: Bool = false,
        videoCaptureDevice: AVCaptureDevice? = AVCaptureDevice.bestForVideo,
        completion: @escaping (Result<ScanResult, ScanError>) -> Void
    ) {
        self.configuration = configuration
        self.manualSelect = manualSelect
        self.showViewfinder = showViewfinder
        self.scanInterval = scanInterval
        self.simulatedData = simulatedData
        self.shouldVibrateOnSuccess = shouldVibrateOnSuccess
        self.isTorchOn = isTorchOn
        self.isPaused = isPaused
        self.videoCaptureDevice = videoCaptureDevice
        self.completion = completion
    }

    public func makeUIViewController(context: Context) -> ScannerViewController {
        return ScannerViewController(showViewfinder: showViewfinder, parentView: self)
    }

    public func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.parentView = self
        uiViewController.updateViewController(
            isTorchOn: isTorchOn
        )
    }
    
}

@available(macCatalyst 14.0, *)
#Preview {
    let configuration = ScannerConfig(codeTypes: [.qr], mode: .once, allowTorchToggle: false, overlayForView: "", overlayForCode: "")
    ScannerzView(configuration: configuration) { result in
        // do nothing
    }
}
#endif
