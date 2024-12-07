//
//  ScannerKitViewController.swift
//  ScannerKit
//
//  Created by Julien Onorato on 03/12/2024.
//

#if os(iOS)
import AVFoundation
import UIKit

@available(macCatalyst 14.0, *)
extension ScannerzView {
    
    public final class ScannerViewController: UIViewController, UINavigationControllerDelegate {
        private var isCapturing = false
        private var handler: ((UIImage?) -> Void)?
        var parentView: ScannerzView!
        var codesFound = Set<String>()
        var didFinishScanning = false
        var lastTime = Date(timeIntervalSince1970: 0)
        private let showViewfinder: Bool
        
        let fallbackVideoCaptureDevice = AVCaptureDevice.default(for: .video)

        public init(showViewfinder: Bool = false, parentView: ScannerzView) {
            self.parentView = parentView
            self.showViewfinder = showViewfinder
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            self.showViewfinder = false
            super.init(coder: coder)
        }

        #if targetEnvironment(simulator)
        override public func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = true

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.text = "You're running in the simulator, which means the camera isn't available. Tap anywhere to send back some simulated data."
            label.textAlignment = .center

            let stackView = UIStackView()
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .vertical
            stackView.spacing = 50
            stackView.addArrangedSubview(label)

            view.addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            // Send back their simulated data, as if it was one of the types they were scanning for
            found(ScanResult(
                string: parentView.simulatedData,
                type: parentView.codeTypes.first ?? .qr, corners: []
            ))
        }
        
        #else
        
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer!

        private lazy var viewFinder: UIImageView? = {
            guard let image = UIImage(named: "viewfinder", in: .module, with: nil) else {
                return nil
            }

            let imageView = UIImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }()

        override public func viewDidLoad() {
            super.viewDidLoad()
            self.addOrientationDidChangeObserver()
            self.setBackgroundColor()
            self.handleCameraPermission()
        }

        override public func viewWillLayoutSubviews() {
            previewLayer?.frame = view.layer.bounds
        }

        @objc func updateOrientation() {
            guard let orientation = view.window?.windowScene?.interfaceOrientation else { return }
            guard let connection = captureSession?.connections.last, connection.isVideoOrientationSupported else { return }
            switch orientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .landscapeLeft:
                connection.videoOrientation = .landscapeLeft
            case .landscapeRight:
                connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            default:
                connection.videoOrientation = .portrait
            }
        }

        override public func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateOrientation()
        }

        override public func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            setupSession()
        }
      
        private func setupSession() {
            guard let captureSession else {
                return
            }
            
            if previewLayer == nil {
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            }

            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            addViewFinder()

            reset()

            if !captureSession.isRunning {
                Task { @MainActor in
                    captureSession.startRunning()
                }
            }
        }

        private func handleCameraPermission() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .restricted:
                    break
                case .denied:
                    self.didFail(reason: .permissionDenied)
                case .notDetermined:
                    self.requestCameraAccess {
                        self.setupCaptureDevice()
                        DispatchQueue.main.async {
                            self.setupSession()
                        }
                    }
                case .authorized:
                    self.setupCaptureDevice()
                    self.setupSession()
                    
                default:
                    break
            }
        }

        private func requestCameraAccess(completion: (() -> Void)?) {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] status in
                guard status else {
                    self?.didFail(reason: .permissionDenied)
                    return
                }
                completion?()
            }
        }
      
        private func addOrientationDidChangeObserver() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateOrientation),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }
      
        private func setBackgroundColor(_ color: UIColor = .black) {
            view.backgroundColor = color
        }
      
        private func setupCaptureDevice() {
            captureSession = AVCaptureSession()

            guard let videoCaptureDevice = parentView.videoCaptureDevice ?? fallbackVideoCaptureDevice else {
                return
            }

            let videoInput: AVCaptureDeviceInput

            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                didFail(reason: .initError(error))
                return
            }

            if captureSession!.canAddInput(videoInput) {
                captureSession!.addInput(videoInput)
            } else {
                didFail(reason: .badInput)
                return
            }
            let metadataOutput = AVCaptureMetadataOutput()

            if captureSession!.canAddOutput(metadataOutput) {
                captureSession!.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = parentView.configuration.codeTypes
            } else {
                didFail(reason: .badOutput)
                return
            }
        }

        private func addViewFinder() {
            guard showViewfinder, let imageView = viewFinder else { return }

            view.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 200),
                imageView.heightAnchor.constraint(equalToConstant: 200),
            ])
        }

        override public func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)

            if captureSession?.isRunning == true {
                Task { @MainActor in
                    self.captureSession?.stopRunning()
                }
            }

            NotificationCenter.default.removeObserver(self)
        }

        override public var prefersStatusBarHidden: Bool {
            true
        }

        override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            .all
        }

        /** Touch the screen for autofocus **/
        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.first?.view == view,
                  let touchPoint = touches.first,
                  let device = parentView.videoCaptureDevice ?? fallbackVideoCaptureDevice,
                  device.isFocusPointOfInterestSupported
            else { return }

            let videoView = view
            let screenSize = videoView!.bounds.size
            let xPoint = touchPoint.location(in: videoView).y / screenSize.height
            let yPoint = 1.0 - touchPoint.location(in: videoView).x / screenSize.width
            let focusPoint = CGPoint(x: xPoint, y: yPoint)

            do {
                try device.lockForConfiguration()
            } catch {
                return
            }

            // Focus to the correct point, make continuous focus and exposure so the point stays sharp when moving the device closer
            device.focusPointOfInterest = focusPoint
            device.focusMode = .continuousAutoFocus
            device.exposurePointOfInterest = focusPoint
            device.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
            device.unlockForConfiguration()
        }
        #endif
        
        func updateViewController(isTorchOn: Bool) {
            guard let videoCaptureDevice = parentView.videoCaptureDevice ?? fallbackVideoCaptureDevice else {
                return
            }
            
            if videoCaptureDevice.hasTorch {
                try? videoCaptureDevice.lockForConfiguration()
                videoCaptureDevice.torchMode = isTorchOn ? .on : .off
                videoCaptureDevice.unlockForConfiguration()
            }
        }
        
        public func reset() {
            codesFound.removeAll()
            didFinishScanning = false
            lastTime = Date(timeIntervalSince1970: 0)
        }

        var isPastScanInterval: Bool {
            Date().timeIntervalSince(lastTime) >= parentView.scanInterval
        }

        func found(_ result: ScanResult) {
            lastTime = Date()

            if parentView.shouldVibrateOnSuccess {
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            }

            parentView.completion(.success(result))
        }

        func didFail(reason: ScanError) {
            parentView.completion(.failure(reason))
        }
        
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

@available(macCatalyst 14.0, *)
extension ScannerzView.ScannerViewController: @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        guard let metadataObject = metadataObjects.first,
              !parentView.isPaused,
              !didFinishScanning,
              !isCapturing,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            
            return
        }
        
        handler = { [weak self] image in
            guard let self else { return }
            let result = ScanResult(string: stringValue, type: readableObject.type, corners: readableObject.corners)
            
            switch parentView.configuration.mode {
            case .once:
                found(result)
                didFinishScanning = true
                
            case .oncePerCode:
                if !codesFound.contains(stringValue) {
                    codesFound.insert(stringValue)
                    found(result)
                }
                
            case .continuous:
                if isPastScanInterval {
                    found(result)
                }
                
            case .continuousExcept(let ignoredList):
                if isPastScanInterval, !ignoredList.contains(stringValue) {
                    found(result)
                }
            }
        }
    }
}

// MARK: - AVCaptureDevice

@available(macCatalyst 14.0, *)
public extension AVCaptureDevice {
    
    /// This returns the Ultra Wide Camera on capable devices and the default Camera for Video otherwise.
    static var bestForVideo: AVCaptureDevice? {
        let deviceHasUltraWideCamera = !AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back).devices.isEmpty
        return deviceHasUltraWideCamera ? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) : AVCaptureDevice.default(for: .video)
    }
    
}
#endif
