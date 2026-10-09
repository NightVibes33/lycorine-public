//
//  CreditsView.swift
//  Lycorine
//
//  Created by ruter on 01.10.26.
//

import SwiftUI
import UIKit

struct CreditsView: View {
    var body: some View {
        VStack {
            LinkCreditCell(image: Image("hrtowii"), name: "hrtowii", description: "Project Lead & Main Developer", url: "https://github.com/hrtowii")
            LinkCreditCell(image: Image("rooootdev"), name: "roooot", description: "Developer", url: "https://github.com/rooootdev")
            LinkCreditCell(image: Image("lunginspector"), name: "lunginspector", description: "UI & Design", url: "https://github.com/lunginspector")
            LinkCreditCell(image: Image("skadz"), name: "Skadz", description: "Development Cheerleader & Code Toucher", url: "https://github.com/skadz108")
        }
    }
}
