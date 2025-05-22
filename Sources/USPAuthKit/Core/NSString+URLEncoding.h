//
//  NSString+URLEncoding.h
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (URLEncoding)

/// Escapa e codifica UTF-8 para parâmetros de URL
- (NSString *)utf8AndURLEncode;

/// Gera UUID simplificado como nonce
+ (NSString *)getNonce;

@end

NS_ASSUME_NONNULL_END
