//
//  ScannerConfig.swift
//  ScannerKit
//
//  Created by Julien Onorato on 03/12/2024.
//

import Foundation
import AVFoundation
import SwiftUI
import CoreHaptics

public struct ScannerConfig {
    public let codeTypes: [AVMetadataObject.ObjectType]
    public let mode: ScanMode
    public let allowTorchToggle: Bool
//    public let successHaptics: CHHapticEvent?

    init(codeTypes: [AVMetadataObject.ObjectType], mode: ScanMode, allowTorchToggle: Bool) {
        self.codeTypes = codeTypes
        self.mode = mode
        self.allowTorchToggle = allowTorchToggle
    }
}
