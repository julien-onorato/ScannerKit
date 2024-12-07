//
//  ScanMode.swift
//  ScannerKit
//
//  Created by Julien Onorato on 03/12/2024.
//

/// The operating mode for ScannerView.
public enum ScanMode {
    /// Scan exactly one code, then stop.
    case once

    /// Scan each code no more than once.
    case oncePerCode

    /// Keep scanning all codes until dismissed.
    case continuous

    /// Keep scanning all codes - except the ones from the ignored list - until dismissed.
    case continuousExcept(ignoredList: Set<String>)
}
