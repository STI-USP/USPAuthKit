//
//  HTTPClient.h
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HTTPClient : NSObject

/// Singleton
+ (instancetype)sharedClient;

/// Envia um dicionário como JSON via POST
- (void)postJSON:(NSDictionary *)body
            toURL:(NSURL *)url
       completion:(void (^)(NSData * _Nullable data,
                            NSHTTPURLResponse * _Nullable response,
                            NSError * _Nullable error))handler;

@end

NS_ASSUME_NONNULL_END
