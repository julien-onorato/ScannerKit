//
//  ScanError.swift
//  ScannerKit
//
//  Created by Julien Onorato on 03/12/2024.
//

/// An enum describing the ways ScannerView can hit scanning problems.
public enum ScanError: Error {
    /// The camera could not be accessed.
    case badInput

    /// The camera was not capable of scanning the requested codes.
    case badOutput

    /// Initialization failed.
    case initError(_ error: Error)
  
    /// The camera permission is denied
    case permissionDenied
}
