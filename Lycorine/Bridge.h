//
//  Bridge.h
//  Lycorine
//
//  Created by Skadz on 10/1/26.
//

@import UIKit;

#ifndef Bridge_h
#define Bridge_h

@interface UIImage (Private)
+ (nullable UIImage *)_applicationIconImageForBundleIdentifier:(NSString*)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#endif /* Bridge_h */
