//
//  SectionPlatter.swift
//  Lycorine
//
//  Created by lunginspector on 9/30/26.
//

import SwiftUI

struct SectionPlatter: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 19.0, *) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRad.platter))
        } else {
            content
        }
    }
}
