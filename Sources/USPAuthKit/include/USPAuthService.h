//
//  USPAuthService.h
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#if __has_include(<UIKit/UIKit.h>)

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
@class USPAuthUser;

NS_ASSUME_NONNULL_BEGIN

/// Gerencia login/logout via OAuth1 e registro/invalidação/consulta de token no backend USP
@interface USPAuthService : NSObject

/// Tokens do OAuth1
@property (nonatomic, copy, nullable) NSString  *oauthToken;
@property (nonatomic, copy, nullable) NSString  *oauthTokenSecret;

/// Dados do usuário retornados pela API (JSON desserializado)
@property (nonatomic, readonly) NSDictionary<NSString*, id> *userData;

/// Singleton
+ (instancetype)sharedService;

/// Garante que o user esteja logado:
/// • se já houver cache, devolve imediatamente
/// • senão, apresenta o LoginWebViewController e, ao final, devolve o user
- (void)ensureLoggedInFromViewController:(UIViewController*)fromVC
                              completion:(void(^)(USPAuthUser * _Nullable user,
                                                  NSError * _Nullable error))completion;
/// Garante que o usuário está logado (cache válido + tokens presentes)
- (BOOL)isLoggedIn;

/// Retorna o usuário atual (ou nil se não estiver logado)
- (nullable USPAuthUser*)currentUser;

/// Apresenta o fluxo de login num WKWebView. Chama completion com sucesso ou erro.
- (void)loginInWebView:(WKWebView*)webView
           completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Logout: invalida no servidor e limpa credenciais locais
- (void)logout;

/// Registro do token no backend USP
- (void)registerToken;

/// Invalidação do token no backend USP
- (void)invalidateToken;

/// Consulta status do token no backend USP
- (void)checkToken;

@end

NS_ASSUME_NONNULL_END

#endif
