//
//  NSString+URLEncoding.m
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#import "NSString+URLEncoding.h"

@implementation NSString (URLEncoding)

- (NSString *)utf8AndURLEncode {
    return (NSString *)CFBridgingRelease(
        CFURLCreateStringByAddingPercentEscapes(NULL,
            (CFStringRef)self,
            NULL,
            (CFStringRef)@"!*'\"();:@&=+$,/?%#[]% ",
            kCFStringEncodingUTF8)
    );
}

+ (NSString *)getNonce {
    NSString *uuid = [[NSUUID UUID].UUIDString lowercaseString];
    return [[uuid substringToIndex:10] stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

@end
