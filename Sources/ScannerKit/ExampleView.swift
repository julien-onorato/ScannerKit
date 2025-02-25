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
                .tint(.blue)
        }
        
    }
}

#Preview {
    ScannerView()
}
