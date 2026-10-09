//
//  NavigationDropdown.swift
//  Lycorine
//
//  Created by lunginspector on 9/30/26.
//

import SwiftUI

struct NavigationDropdown: View {
    var text: String
    var icon: String
    @Binding var toggle: Bool
    
    var body: some View {
        Button(action: {
            withAnimation {
                toggle.toggle()
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 22, height: 22, alignment: .center)
                Text(text)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(toggle ? 90 : 0))
            }
            .padding(10)
        }
        .foregroundStyle(Color(.label))
    }
}
