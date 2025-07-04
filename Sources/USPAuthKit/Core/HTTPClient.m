//
//  HTTPClient.m
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#import "HTTPClient.h"
#import "OAuthConfig.h"

@interface HTTPClient ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation HTTPClient

+ (instancetype)sharedClient {
  static HTTPClient *client;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    client = [[HTTPClient alloc] init];
  });
  return client;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    _session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
  }
  return self;
}

- (void)postJSON:(NSDictionary *)body toURL:(NSURL *)url completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))handler {
  NSError *jsonErr;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
  if (!jsonData) {
    if (handler) handler(nil, nil, jsonErr);
    return;
  }
  
  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
  req.HTTPMethod = @"POST";
  [req setValue:@"application/json; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
  [req setValue:@"820ecd52-849f-4815-8eb3-bbf9f4440ac5" forHTTPHeaderField:@"DEV-USP-MOBILE"];

  req.HTTPBody = jsonData;
  
  NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                               completionHandler:
                                ^(NSData *data, NSURLResponse *resp, NSError *err) {
    if (handler) handler(data, (NSHTTPURLResponse*)resp, err);
  }];
  [task resume];
}

@end
