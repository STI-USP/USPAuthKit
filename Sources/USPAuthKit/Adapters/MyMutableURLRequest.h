//
//  MyMutableURLRequest.h
//  e-Card USP
//
//  Created by Vagner Machado on 10/08/22.
//  Copyright © 2022 USP. All rights reserved.
//

#if __has_include(<UIKit/UIKit.h>)

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MyMutableURLRequest : NSMutableURLRequest

+ (NSMutableURLRequest *)requestWithURL:(NSURL *)URL;

@end

NS_ASSUME_NONNULL_END

#endif
