//
//  ScanResult.swift
//  ScannerKit
//
//  Created by Julien Onorato on 03/12/2024.
//

import AVFoundation
import SwiftUI

/// The result from a successful scan: the string that was scanned, and also the type of data that was found.
/// The type is useful for times when you've asked to scan several different code types at the same time, because
/// It will report the exact code type that was found.
@available(macCatalyst 14.0, *)
public struct ScanResult {
    /// The contents of the code.
    public let string: String

    /// The type of code that was matched.
    public let type: AVMetadataObject.ObjectType
  
    /// The corner coordinates of the scanned code.
    public let corners: [CGPoint]
}
