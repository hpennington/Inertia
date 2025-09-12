//
//  InertiaUtilities.swift
//  
//
//  Created by Hayden Pennington on 7/5/24.
//

import SwiftUI

internal struct BindableSize: ViewModifier {
    @Binding var size: CGSize
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        size = proxy.size
                    }.onChange(of: proxy.size) { oldValue, newValue in
                        size = newValue
                    }
                }
            )
            .fixedSize()
    }
}
