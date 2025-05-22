// USPAuthService.m
// NuAuthKit
//
// Created by Vagner Machado on 22/05/25.
//
// Fluxo completo:
//  • tenta cache
//  • apresenta login
//  • faz OAuth1, grava tokens (via LoginWebViewController setting them on sharedService)
//  • fetch de usuário
//  • register token no backend
//  • devolve userData ou erro
//

#if __has_include(<UIKit/UIKit.h>)

#import "USPAuthService.h"
#import "HTTPClient.h"
#import "OAuthConfig.h"
#import "OAuth1Controller.h"
#import "LoginWebViewController.h"

@interface USPAuthService ()

@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, assign) BOOL isLoginPresentationInProgress;

@end

@implementation USPAuthService

// Public properties for OAuth tokens, managed by setters
@synthesize oauthToken = _oauthToken;
@synthesize oauthTokenSecret = _oauthTokenSecret;

+ (instancetype)sharedService {
  static USPAuthService *svc;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    svc = [[self alloc] init];
  });
  return svc;
}

- (instancetype)init {
  if (self = [super init]) {
    _defaults = [NSUserDefaults standardUserDefaults];
    _isLoginPresentationInProgress = NO;
    
    _oauthToken = [_defaults stringForKey:@"oauthToken"];
    _oauthTokenSecret = [_defaults stringForKey:@"oauthTokenSecret"];
  }
  return self;
}

- (NSDictionary<NSString*,id>*)userData {
  NSData *data = [self.defaults objectForKey:@"userData"];
  if (!data) return @{};
  NSError *jsonError;
  NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (jsonError || ![parsed isKindOfClass:NSDictionary.class]) {
    NSLog(@"Error parsing cached userData: %@", jsonError);
    return @{};
  }
  return parsed;
}

- (void)ensureLoggedInFromViewController:(UIViewController*)fromVC
                              completion:(void(^)(NSDictionary<NSString*,id>* _Nullable user,
                                                  NSError * _Nullable error))completion
{
  NSParameterAssert(fromVC);
  NSParameterAssert(completion); // Completion é obrigatório
  
  // Se já existe um processo de login em andamento, retorna um erro.
  if (self.isLoginPresentationInProgress) {
    NSLog(@"USPAuthService: Tentativa de iniciar novo login enquanto um já está em progresso.");
    NSError *inProgressError = [NSError errorWithDomain:NSStringFromClass([self class])
                                                   code:1001 // Código de erro para "em progresso"
                                               userInfo:@{NSLocalizedDescriptionKey:@"Processo de login já em andamento."}];
    if (completion) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, inProgressError);
      });
    }
    return;
  }
  
  // 1) Cache?
  if (self.oauthToken.length > 0 && self.userData.count > 0) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion) completion(self.userData, nil);
    });
    return;
  }
  
  self.isLoginPresentationInProgress = YES; // Define a flag ANTES de apresentar
  
  // 2) Apresenta login
  LoginWebViewController *loginVC = [[LoginWebViewController alloc] init];
  
  // Este wrapper garante que a flag seja resetada e a completion final seja na main thread.
  void (^postDismissCompletion)(NSDictionary<NSString*,id>*, NSError*) = ^(NSDictionary<NSString*,id>* userResult, NSError *errorResult) {
    self.isLoginPresentationInProgress = NO; // Reseta a flag em todos os caminhos de conclusão
    if (completion) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(userResult, errorResult);
      });
    }
  };
  
  loginVC.loginCompletion = ^(BOOL success, NSError * _Nullable loginError) {
    // A flag isLoginPresentationInProgress só é resetada DENTRO do postDismissCompletion,
    // que é chamado APÓS o dismissViewControllerAnimated:completion: terminar.
    [fromVC dismissViewControllerAnimated:YES completion:^{
      if (!success) {
        postDismissCompletion(nil, loginError);
        return;
      }
      
      // 3) Tokens devem ter sido salvos. Agora fetch user data + register token
      [self fetchUserDataWithCompletion:^(NSDictionary * _Nullable user, NSError * _Nullable fetchErr) {
        if (fetchErr) {
          postDismissCompletion(nil, fetchErr);
          return;
        }
        if (!user || user.count == 0) { // Verifica se user é nil ou vazio
          NSError *e = [NSError errorWithDomain:NSStringFromClass([self class])
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey:@"Dados do usuário não encontrados após o fetch ou resposta vazia."}];
          postDismissCompletion(nil, e);
          return;
        }
        
        [self registerTokenWithCompletion:^(NSError * _Nullable regErr) {
          if (regErr) {
            postDismissCompletion(nil, regErr);
            return;
          }
          postDismissCompletion(user, nil);
        }];
      }];
    }];
  };
  
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:loginVC];
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [fromVC presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Helpers

- (void)fetchUserDataWithCompletion:(void(^)(NSDictionary<NSString*,id>* _Nullable user,
                                             NSError * _Nullable error))completion {
  NSParameterAssert(completion);
  if (!self.oauthToken || !self.oauthTokenSecret) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:@"Tokens OAuth não disponíveis para buscar dados do usuário."}];
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(nil, e);
    });
    return;
  }
  
  NSURLRequest *req = [OAuth1Controller preparedRequestForPath:@"/wsusuario/oauth/usuariousp"
                                                    parameters:nil
                                                    HTTPmethod:@"POST"
                                                    oauthToken:self.oauthToken
                                                   oauthSecret:self.oauthTokenSecret];
  if (!req) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:0
                                 userInfo:@{NSLocalizedDescriptionKey:@"Não foi possível criar requisição para buscar dados do usuário."}];
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(nil, e);
    });
    return;
  }
  
  [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                   completionHandler:^(NSData * _Nullable data,
                                                       NSURLResponse * _Nullable resp,
                                                       NSError * _Nullable err) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (err) {
        completion(nil, err);
        return;
      }
      if (!data) {
        NSError *e = [NSError errorWithDomain:NSStringFromClass([self class])
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:@"Nenhum dado recebido do servidor."}];
        completion(nil, e);
        return;
      }
      
      NSError *jsonErr;
      NSDictionary *user = [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:&jsonErr];
      if (jsonErr || ![user isKindOfClass:NSDictionary.class] || user.count == 0) {
        NSError *e = jsonErr ?: [NSError errorWithDomain:NSStringFromClass([self class])
                                                    code:4
                                                userInfo:@{NSLocalizedDescriptionKey:@"Resposta inválida do servidor ao buscar dados do usuário ou dados vazios."}];
        completion(nil, e);
        return;
      }
      
      [self.defaults setObject:data forKey:@"userData"];
      [self.defaults synchronize];
      completion(user, nil);
    });
  }] resume];
}

- (void)registerTokenWithCompletion:(void(^)(NSError * _Nullable error))completion {
  NSParameterAssert(completion);
  NSString *wsUserId = self.userData[@"wsuserid"];
  
  if (!wsUserId.length) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:5
                                 userInfo:@{NSLocalizedDescriptionKey:@"ID do usuário (wsuserid) não encontrado para registrar o token."}];
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(e);
    });
    return;
  }
  
  NSURL *url = [NSURL URLWithString:[kOAuthServiceBaseURL stringByAppendingString:@"/registrar"]];
  NSDictionary *body = @{ @"token": wsUserId, @"app": @"AppEcard" };
  
  [[HTTPClient sharedClient] postJSON:body
                                toURL:url
                           completion:^(NSData * _Nullable data,
                                        NSHTTPURLResponse * _Nullable resp,
                                        NSError * _Nullable err) {
    dispatch_async(dispatch_get_main_queue(), ^{
      // erro de transporte ou status HTTP != 200
      if (err || resp.statusCode != 200) {
        NSError *effectiveError = err ?: [NSError errorWithDomain:@"USPAuthService"
                                                             code:resp.statusCode
                                                         userInfo:@{NSLocalizedDescriptionKey:
                                                                      [NSString stringWithFormat:@"Falha ao registrar token. Status: %ld",
                                                                       (long)resp.statusCode]}];
        completion(effectiveError);
        return;
      }
      
      // sucesso
      [self.defaults setBool:YES forKey:@"isRegistered"];
      [self.defaults synchronize];
      completion(nil);
    });
  }];  
}


#pragma mark - Propriedades set (OAuthToken and Secret)

- (void)setOauthToken:(NSString *)oauthToken {
  _oauthToken = [oauthToken copy];
  if (_oauthToken) {
    [self.defaults setObject:_oauthToken forKey:@"oauthToken"];
    [self.defaults synchronize];
  } else {
    [self.defaults removeObjectForKey:@"oauthToken"];
  }
}

- (NSString *)oauthToken {
  if (!_oauthToken) {
    _oauthToken = [self.defaults stringForKey:@"oauthToken"];
  }
  return _oauthToken;
}

- (void)setOauthTokenSecret:(NSString *)oauthTokenSecret {
  _oauthTokenSecret = [oauthTokenSecret copy];
  if (_oauthTokenSecret) {
    [self.defaults setObject:_oauthTokenSecret forKey:@"oauthTokenSecret"];
    [self.defaults synchronize];
  } else {
    [self.defaults removeObjectForKey:@"oauthTokenSecret"];
  }
}

- (NSString *)oauthTokenSecret {
  if (!_oauthTokenSecret) {
    _oauthTokenSecret = [self.defaults stringForKey:@"oauthTokenSecret"];
  }
  return _oauthTokenSecret;
}

- (void)logout {
  self.oauthToken = nil;
  self.oauthTokenSecret = nil;
  [self.defaults removeObjectForKey:@"userData"];
  [self.defaults removeObjectForKey:@"isRegistered"];
  NSLog(@"User session cleared.");
}

@end

#endif
