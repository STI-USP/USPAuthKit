//
//  OAuth1Controller.h
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Fluxo OAuth 1.0: requestToken → authorize → accessToken
@interface OAuth1Controller : NSObject <WKNavigationDelegate>

/// Inicia login, apontando WKWebView e recebe tokens finais
- (void)loginWithWebView:(WKWebView *)webView
              completion:(void (^)(NSDictionary<NSString*, NSString*> * _Nullable oauthTokens,
                                   NSError * _Nullable error))completion;

/// Métodos estáticos auxiliares (base string, assinatura, parâmetros padrão)
+ (NSURLRequest *)preparedRequestForPath:(NSString *)path
                              parameters:(nullable NSDictionary *)queryParameters
                              HTTPmethod:(NSString *)HTTPmethod
                              oauthToken:(NSString *)oauthToken
                             oauthSecret:(NSString *)oauthTokenSecret;

@end

NS_ASSUME_NONNULL_END
