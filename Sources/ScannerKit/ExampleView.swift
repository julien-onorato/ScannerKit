//
//  ExampleView.swift
//  ScannerKit
//
//  Created by Julien Onorato on 25/02/2025.
//

import SwiftUI

public struct ExampleView: View {
    public init() { }
    
    public var body: some View {
        ZStack {
            ScannerView()
            
            Text("Scan a QR code")
            
            Color.blue
                .frame(width: 100, height: 100)
        }
        
    }
}

#Preview {
    ScannerView()
}
