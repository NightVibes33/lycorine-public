//
//  TranslucentButtonStyle.swift
//  PartyUI
//
//  Created by lunginspector on 3/3/26.
//

import SwiftUI

struct TranslucentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 19.0, *) {
            configuration.label
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color(.label))
                .fontWeight(.medium)
                .padding()
                .glassEffect(isEnabled ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRad.component))
        } else {
            configuration.label
        }
    }
}
