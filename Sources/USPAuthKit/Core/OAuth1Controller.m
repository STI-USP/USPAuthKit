//
//  OAuth1Controller.m
//  USPAuthKit
//
//  Created by Christian Hansen on 02/12/12.
//  Adapted by Vagner Machado on 22/05/25.
//

#if __has_include(<UIKit/UIKit.h>)
  @import UIKit; // para UIActivityIndicatorView
#endif
@import WebKit;
#import "OAuth1Controller.h"
#import "NSString+URLEncoding.h"
#include "hmac.h"
#include "Base64Transcoder.h"

// ----------------------------------------------------------------------------
// 1) Funções auxiliares de percent-escaping e query string
// ----------------------------------------------------------------------------

static NSString * CHPercentEscapedQueryStringPairMemberFromStringWithEncoding(NSString *string, NSStringEncoding encoding) {
  static NSString * const kCHCharactersToBeEscaped = @":/?&=;+!@#$()~";
  static NSString * const kCHCharactersToLeaveUnescaped = @"[].";
  return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
    kCFAllocatorDefault,
    (__bridge CFStringRef)string,
    (__bridge CFStringRef)kCHCharactersToLeaveUnescaped,
    (__bridge CFStringRef)kCHCharactersToBeEscaped,
    CFStringConvertNSStringEncodingToEncoding(encoding)
  );
}

@interface CHQueryStringPair : NSObject
@property (nonatomic,strong) id field;
@property (nonatomic,strong) id value;
- (instancetype)initWithField:(id)field value:(id)value;
- (NSString *)URLEncodedStringValueWithEncoding:(NSStringEncoding)stringEncoding;
@end

@implementation CHQueryStringPair
- (instancetype)initWithField:(id)field value:(id)value {
  if (!(self = [super init])) return nil;
  _field = field; _value = value;
  return self;
}
- (NSString *)URLEncodedStringValueWithEncoding:(NSStringEncoding)encoding {
  if (!_value || [_value isEqual:[NSNull null]]) {
    return CHPercentEscapedQueryStringPairMemberFromStringWithEncoding(
      [_field description], encoding
    );
  } else {
    return [NSString stringWithFormat:@"%@=%@",
      CHPercentEscapedQueryStringPairMemberFromStringWithEncoding([_field description], encoding),
      CHPercentEscapedQueryStringPairMemberFromStringWithEncoding([_value description], encoding)
    ];
  }
}
@end

NSArray<CHQueryStringPair*> * CHQueryStringPairsFromDictionary(NSDictionary *dict);
NSArray<CHQueryStringPair*> * CHQueryStringPairsFromKeyAndValue(NSString *key, id value);

NSString * CHQueryStringFromParametersWithEncoding(NSDictionary *parameters, NSStringEncoding encoding) {
  NSMutableArray *pairs = [NSMutableArray array];
  for (CHQueryStringPair *p in CHQueryStringPairsFromDictionary(parameters)) {
    [pairs addObject:[p URLEncodedStringValueWithEncoding:encoding]];
  }
  return [pairs componentsJoinedByString:@"&"];
}

NSArray<CHQueryStringPair*> * CHQueryStringPairsFromDictionary(NSDictionary *dict) {
  return CHQueryStringPairsFromKeyAndValue(nil, dict);
}

NSArray<CHQueryStringPair*> * CHQueryStringPairsFromKeyAndValue(NSString *key, id value) {
  NSMutableArray *components = [NSMutableArray array];
  if ([value isKindOfClass:[NSDictionary class]]) {
    for (NSString *nestedKey in [[value allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
      [components addObjectsFromArray:
        CHQueryStringPairsFromKeyAndValue(
          key ? [NSString stringWithFormat:@"%@[%@]", key, nestedKey] : nestedKey,
          value[nestedKey]
        )
      ];
    }
  } else if ([value isKindOfClass:[NSArray class]]) {
    for (id v in value) {
      [components addObjectsFromArray:
        CHQueryStringPairsFromKeyAndValue([NSString stringWithFormat:@"%@[]", key], v)
      ];
    }
  } else {
    [components addObject:[[CHQueryStringPair alloc] initWithField:key value:value]];
  }
  return components;
}

static inline NSDictionary * CHParametersFromQueryString(NSString *qs) {
  NSMutableDictionary *params = [NSMutableDictionary dictionary];
  NSScanner *scanner = [NSScanner scannerWithString:qs];
  NSString *name, *value;
  while (![scanner isAtEnd]) {
    name = nil; [scanner scanUpToString:@"=" intoString:&name];
    [scanner scanString:@"=" intoString:NULL];
    value = nil; [scanner scanUpToString:@"&" intoString:&value];
    [scanner scanString:@"&" intoString:NULL];
    if (name && value) {
      NSString *decodedName  = [name stringByRemovingPercentEncoding];
      NSString *decodedValue = [value stringByRemovingPercentEncoding];
      params[decodedName] = decodedValue;
    }
  }
  return params;
}

// ----------------------------------------------------------------------------
// 2) Definições de chave e endpoints
// ----------------------------------------------------------------------------

#define OAUTH_CALLBACK       @"localhost"
#define REQUEST_TOKEN_URL    @"/wsusuario/oauth/request_token"
#define AUTHENTICATE_URL     @"/wsusuario/oauth/authorize"
#define ACCESS_TOKEN_URL     @"/wsusuario/oauth/access_token"

#define REQUEST_TOKEN_METHOD @"POST"
#define ACCESS_TOKEN_METHOD  @"POST"
#define CONSUMER_KEY         @"cetilq"
//#if DEV
static NSString *const CONSUMER_SECRET = @"qhKtMXQTtmKA3cAdW5AHoNgce3XbBoPrrl6O5dbU";
static NSString *const AUTH_URL        = @"https://dev.uspdigital.usp.br";
//#else
//static NSString *const CONSUMER_SECRET = @"pOQYX8kg5hTxQiGjSHBcYwcfSgtUmWapVkPm1TCR";
//static NSString *const AUTH_URL        = @"https://uspdigital.usp.br";
//#endif

// ----------------------------------------------------------------------------
// 3) Private extension
// ----------------------------------------------------------------------------

typedef void (^WebViewHandler)(NSDictionary *oauthParams);

@interface OAuth1Controller ()
@property (nonatomic, weak)   WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, copy)   WebViewHandler delegateHandler;
@end

// ----------------------------------------------------------------------------
// 4) Implementation
// ----------------------------------------------------------------------------

@implementation OAuth1Controller

- (void)loginWithWebView:(WKWebView*)webView
              completion:(void (^)(NSDictionary<NSString*,NSString*>*,NSError*))completion
{
  self.webView = webView;
  webView.navigationDelegate = self;

  // loading spinner
  self.loadingIndicator = [[UIActivityIndicatorView alloc]
    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
  self.loadingIndicator.center = webView.center;
  [webView addSubview:self.loadingIndicator];
  [self.loadingIndicator startAnimating];

  // Step 1: request token
  [self obtainRequestTokenWithCompletion:^(NSError *err, NSDictionary *respParams) {
    if (err) { completion(nil, err); return; }
    NSString *tok  = respParams[@"oauth_token"];
    NSString *sec  = respParams[@"oauth_token_secret"];
    // Step 2: authorize
    [self authenticateToken:tok withCompletion:^(NSError *err2, NSDictionary *authParams) {
      if (err2) { completion(nil, err2); return; }
      // Step 3: access token
      [self requestAccessToken:sec
                   oauthToken:authParams[@"oauth_token"]
                oauthVerifier:authParams[@"oauth_verifier"]
                   completion:^(NSError *err3, NSDictionary *accessParams) {
        completion(accessParams, err3);
      }];
    }];
  }];
}

// — Step 1
- (void)obtainRequestTokenWithCompletion:(void (^)(NSError*,NSDictionary*))completion {
  NSString *urlStr = [AUTH_URL stringByAppendingString:REQUEST_TOKEN_URL];
  NSMutableDictionary *params = [self.class standardOauthParameters];
  NSString *baseStr = [self.class baseStringWithMethod:REQUEST_TOKEN_METHOD
                                                  url:urlStr
                                           parameters:params];
  NSString *sig = [self.class signClearText:baseStr
                                 withSecret:[NSString stringWithFormat:@"%@&", CONSUMER_SECRET.utf8AndURLEncode]];
  params[@"oauth_signature"] = sig;

  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
  req.HTTPMethod = REQUEST_TOKEN_METHOD;
  [req setValue:[self.class authorizationHeaderFromParams:params]
 forHTTPHeaderField:@"Authorization"];

  [[[NSURLSession sharedSession]
    dataTaskWithRequest:req
    completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
      if (err) { dispatch_async(dispatch_get_main_queue(), ^{ completion(err,nil); }); return; }
      NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      NSDictionary *parsed = CHParametersFromQueryString(resp);
      dispatch_async(dispatch_get_main_queue(), ^{ completion(nil,parsed); });
  }] resume];
}

// — Step 2
- (void)authenticateToken:(NSString*)oauthToken
           withCompletion:(void (^)(NSError*,NSDictionary*))completion
{
  NSString *cb    = OAUTH_CALLBACK.utf8AndURLEncode;
  NSString *url   = [NSString stringWithFormat:@"%@%@?oauth_token=%@&oauth_callback=%@",
                     AUTH_URL, AUTHENTICATE_URL, oauthToken, cb];
  _delegateHandler = ^(NSDictionary *params) {
    if (!params[@"oauth_verifier"]) {
      NSError *e = [NSError errorWithDomain:@"oauth" code:0
                                   userInfo:@{NSLocalizedDescriptionKey:@"Verifier missing"}];
      completion(e, params);
    } else {
      completion(nil, params);
    }
  };
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
  });
}

// — Step 3
- (void)requestAccessToken:(NSString*)tokenSecret
               oauthToken:(NSString*)oauthToken
            oauthVerifier:(NSString*)oauthVerifier
               completion:(void (^)(NSError*,NSDictionary*))completion
{
  NSString *urlStr = [AUTH_URL stringByAppendingString:ACCESS_TOKEN_URL];
  NSMutableDictionary *params = [self.class standardOauthParameters];
  params[@"oauth_token"]    = oauthToken;
  params[@"oauth_verifier"] = oauthVerifier;
  NSString *baseStr = [self.class baseStringWithMethod:ACCESS_TOKEN_METHOD
                                                  url:urlStr
                                           parameters:params];
  NSString *secret = [NSString stringWithFormat:@"%@&%@",
                      CONSUMER_SECRET.utf8AndURLEncode,
                      tokenSecret.utf8AndURLEncode];
  params[@"oauth_signature"] = [self.class signClearText:baseStr withSecret:secret];

  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
  req.HTTPMethod = ACCESS_TOKEN_METHOD;
  [req setValue:[self.class authorizationHeaderFromParams:params]
 forHTTPHeaderField:@"Authorization"];

  [[[NSURLSession sharedSession]
    dataTaskWithRequest:req
    completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
      if (err) { dispatch_async(dispatch_get_main_queue(), ^{ completion(err,nil); }); return; }
      NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      NSDictionary *parsed = CHParametersFromQueryString(resp);
      dispatch_async(dispatch_get_main_queue(), ^{ completion(nil,parsed); });
  }] resume];
}

+ (NSURLRequest *)preparedRequestForPath:(NSString *)path
                             parameters:(nullable NSDictionary *)queryParameters
                             HTTPmethod:(NSString *)HTTPmethod
                             oauthToken:(NSString *)oauth_token
                            oauthSecret:(NSString *)oauth_token_secret
{
    if (!HTTPmethod.length || !oauth_token.length) return nil;

    // 1) Monta os parâmetros OAuth
    NSMutableDictionary *allParams = [self standardOauthParameters];
    allParams[@"oauth_consumer_key"] = CONSUMER_KEY;
    allParams[@"oauth_token"]        = oauth_token;
    if (queryParameters) {
        [allParams addEntriesFromDictionary:queryParameters];
    }

    // 2) Base string para assinatura
    NSString *urlString   = [AUTH_URL stringByAppendingString:path];
    NSString *paramString = CHQueryStringFromParametersWithEncoding(allParams, NSUTF8StringEncoding);
    NSString *baseString  = [NSString stringWithFormat:@"%@&%@&%@",
      HTTPmethod,
      [urlString utf8AndURLEncode],
      [paramString utf8AndURLEncode]
    ];

    // 3) Gera assinatura HMAC-SHA1
    NSString *secretString = [NSString stringWithFormat:@"%@&%@",
                              CONSUMER_SECRET.utf8AndURLEncode,
                              oauth_token_secret.utf8AndURLEncode];
    NSString *signature = [self signClearText:baseString withSecret:secretString];
    allParams[@"oauth_signature"] = signature;

    // 4) Cria NSURLRequest
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
      [NSURL URLWithString:urlString]];
    request.HTTPMethod = HTTPmethod;

    // 5) Cabeçalho Authorization
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *k in allParams) {
        NSString *v = allParams[k];
        [pairs addObject:
          [NSString stringWithFormat:@"%@=\"%@\"",
            [k utf8AndURLEncode],
            [v utf8AndURLEncode]
          ]
        ];
    }
    NSString *authHeader = [@"OAuth " stringByAppendingString:
                            [pairs componentsJoinedByString:@", "]];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];

    // 6) Se for POST, coloca body
    if ([HTTPmethod isEqualToString:@"POST"] && queryParameters) {
        NSString *bodyString = CHQueryStringFromParametersWithEncoding(queryParameters, NSUTF8StringEncoding);
        request.HTTPBody = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
    }

    return request;
}

// WKWebViewDelegate
- (void)webView:(WKWebView*)webView
decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSString *url = webView.URL.absoluteString;
    NSRange range = [url rangeOfString:@"oauth_verifier="];
    if (range.location != NSNotFound) {
        // Pega tudo após o '?'
        NSString *query = [[url componentsSeparatedByString:@"?"] lastObject];
        NSDictionary *params = CHParametersFromQueryString(query);
        
        // Remove sufixo do Facebook/Tumblr "#_=_"
        NSString *verifier = params[@"oauth_verifier"];
        if ([verifier hasSuffix:@"#_=_"]) {
            NSMutableDictionary *mutableParams = [params mutableCopy];
            mutableParams[@"oauth_verifier"] =
              [verifier stringByReplacingOccurrencesOfString:@"#_=_" withString:@""];
            params = [mutableParams copy];
        }
        
        // Chama o handler e cancela o carregamento
        if (self.delegateHandler) {
            self.delegateHandler(params);
            self.delegateHandler = nil;
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    // Senão, continue normalmente
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)nav {
  [self.loadingIndicator removeFromSuperview];
  self.loadingIndicator = nil;
}

// ----------------------------------------------------------------------------
// 5) Métodos de assinatura e helpers
// ----------------------------------------------------------------------------

+ (NSMutableDictionary*)standardOauthParameters {
  return [@{
    @"oauth_consumer_key":       CONSUMER_KEY,
    @"oauth_nonce":              [NSString getNonce],
    @"oauth_signature_method":   @"HMAC-SHA1",
    @"oauth_timestamp":          [NSString stringWithFormat:@"%lu",(unsigned long)[[NSDate date] timeIntervalSince1970]],
    @"oauth_version":            @"1.0"
  } mutableCopy];
}

+ (NSString*)baseStringWithMethod:(NSString*)method
                             url:(NSString*)url
                      parameters:(NSDictionary*)params
{
  // sort keys
  NSArray *ks = [[params allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
  NSMutableArray *parts = [NSMutableArray array];
  for (NSString *k in ks) {
    [parts addObject:
      [NSString stringWithFormat:@"%@=%@",
        CHPercentEscapedQueryStringPairMemberFromStringWithEncoding(k,NSUTF8StringEncoding),
        CHPercentEscapedQueryStringPairMemberFromStringWithEncoding([params[k] description],NSUTF8StringEncoding)
      ]
    ];
  }
  NSString *paramString = [parts componentsJoinedByString:@"&"];
  return [@[method, url.utf8AndURLEncode, paramString.utf8AndURLEncode] componentsJoinedByString:@"&"];
}

+ (NSString*)authorizationHeaderFromParams:(NSDictionary*)params {
  NSMutableArray *pairs = [NSMutableArray array];
  for (NSString *k in params) {
    [pairs addObject:
      [NSString stringWithFormat:@"%@=\"%@\"",
        CHPercentEscapedQueryStringPairMemberFromStringWithEncoding(k,NSUTF8StringEncoding),
        CHPercentEscapedQueryStringPairMemberFromStringWithEncoding([params[k] description],NSUTF8StringEncoding)
      ]
    ];
  }
  return [@"OAuth " stringByAppendingString:[pairs componentsJoinedByString:@", "]];
}

+ (NSString*)signClearText:(NSString*)text withSecret:(NSString*)secret {
  // HMAC-SHA1 + Base64
  NSData *keyData = [secret dataUsingEncoding:NSUTF8StringEncoding];
  NSData *msgData = [text dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char result[20];
  hmac_sha1((unsigned char*)msgData.bytes, (unsigned int)msgData.length,
            (unsigned char*)keyData.bytes, (unsigned int)keyData.length, result);
  char base64Buff[32];
  size_t outLen = sizeof(base64Buff);
  Base64EncodeData(result, 20, base64Buff, &outLen);
  return [[NSString alloc] initWithBytes:base64Buff length:outLen encoding:NSUTF8StringEncoding];
}

@end
