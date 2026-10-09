//
//  CornerRad.swift
//  Lycorine
//
//  Created by lunginspector on 9/30/26.
//

import SwiftUI

enum cornerRad {
    static var component: CGFloat {
        if #available(iOS 19.0, *) { return 18 } else { return 12 }
    }
    static var platter: CGFloat {
        if #available(iOS 19.0, *) { return 26 } else { return 18 }
    }
}

