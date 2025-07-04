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
#import "USPAuthUser.h"

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

    _oauthToken = [_defaults stringForKey:@"oauthToken"];
    _oauthTokenSecret = [_defaults stringForKey:@"oauthTokenSecret"];
    
    _appKey = @"";
    _isLoginPresentationInProgress = NO;
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

- (BOOL)isLoggedIn {
  NSString *token  = [_defaults stringForKey:@"oauthToken"];
  NSString *secret = [_defaults stringForKey:@"oauthTokenSecret"];
  NSData   *data   = [_defaults objectForKey:@"userData"];
  return (token.length > 0
          && secret.length > 0
          && data != nil
          && data.length > 0);
}

- (USPAuthUser *)currentUser {
  NSData *data = [self.defaults objectForKey:@"userData"];
  if (!data) return nil;
  NSError *err;
  NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
  if (err || ![dict isKindOfClass:[NSDictionary class]]) return nil;
  return [[USPAuthUser alloc] initWithDictionary:dict];
}

- (void)ensureLoggedInFromViewController:(UIViewController *)fromVC
                              completion:(void (^)(USPAuthUser * _Nullable user,
                                                   NSError * _Nullable error))completion {
  NSParameterAssert(fromVC);
  NSParameterAssert(completion);

  // 1. Evita login duplo
  if (self.isLoginPresentationInProgress) {
    NSError *inProgressErr = [NSError errorWithDomain:NSStringFromClass(self.class)
                                                 code:1001
                                             userInfo:@{NSLocalizedDescriptionKey:@"Login já em andamento."}];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, inProgressErr); });
    return;
  }

  // 2. Cache rápido
  if (self.oauthToken.length > 0 && self.userData.count > 0) {
    USPAuthUser *cached = [[USPAuthUser alloc] initWithDictionary:self.userData];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(cached, nil); });
    return;
  }

  self.isLoginPresentationInProgress = YES;

  // 3. VC de login + barra “bonita”
  LoginWebViewController *loginVC = [[LoginWebViewController alloc] init];
  loginVC.loginCompletion = ^(BOOL success, NSError * _Nullable loginErr) {
    __auto_type weakSelf = self;
    [fromVC dismissViewControllerAnimated:YES completion:^{
      __strong typeof(weakSelf) self = weakSelf;
      self.isLoginPresentationInProgress = NO;

      if (!success) { completion(nil, loginErr); return; }

      // Busca dados e registra token
      [self fetchUserDataWithCompletion:^(NSDictionary *dict, NSError *fetchErr) {
        if (fetchErr || dict.count == 0) {
          NSError *err = fetchErr ?: [NSError errorWithDomain:NSStringFromClass(self.class)
                                                         code:2
                                                     userInfo:@{NSLocalizedDescriptionKey:@"Dados do usuário não encontrados."}];
          completion(nil, err);
          return;
        }

        [self registerTokenWithCompletion:^(NSError *regErr) {
          completion(regErr ? nil : [[USPAuthUser alloc] initWithDictionary:dict], regErr);
        }];
      }];
    }];
  };

  // 4. NavigationController estilizado
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:loginVC];

  if (@available(iOS 13.0, *)) {
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = [UIColor colorNamed:@"BrandPrimary"];   // cor do seu catálogo
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName : UIColor.whiteColor };

    nav.navigationBar.standardAppearance = ap;
    nav.navigationBar.scrollEdgeAppearance = ap;
    nav.navigationBar.compactAppearance  = ap;
    nav.navigationBar.tintColor = UIColor.whiteColor;            // cor do botão “X”
  }

  // 5. Sheet no iPad, fullscreen no iPhone
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
      nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
      nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
  } else {
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
  }

  // 6. Apresentação
  dispatch_async(dispatch_get_main_queue(), ^{
    [fromVC presentViewController:nav animated:YES completion:nil];
  });
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
  NSLog(@"[USPAuth] Iniciando registro de token. wsUserId: %@", wsUserId);

  if (!wsUserId.length) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:5
                                 userInfo:@{NSLocalizedDescriptionKey:@"ID do usuário (wsuserid) não encontrado para registrar o token."}];
    NSLog(@"[USPAuth] ERRO: wsUserId não encontrado. Abortando registro.");
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(e);
    });
    return;
  }

  NSURL *url = [NSURL URLWithString:[kOAuthServiceBaseURL stringByAppendingString:@"/registrar"]];
  NSDictionary *body = @{ @"token": wsUserId, @"app": _appKey };
  NSLog(@"[USPAuth] Enviando POST para %@ com body: %@", url, body);

  [[HTTPClient sharedClient] postJSON:body toURL:url completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable resp, NSError * _Nullable err) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (data) {
        NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"[USPAuth] Resposta do servidor: %@", responseString ?: @"(resposta vazia ou inválida)");
      }

      if (err || resp.statusCode != 200) {
        NSString *msg = err ? err.localizedDescription : [NSString stringWithFormat:@"Status: %ld", (long)resp.statusCode];
        NSLog(@"[USPAuth] ERRO ao registrar token: %@", msg);

        NSError *effectiveError = err ?: [NSError errorWithDomain:@"USPAuthService"
                                                             code:resp.statusCode
                                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Falha ao registrar token. Status: %ld", (long)resp.statusCode]}];
        completion(effectiveError);
        return;
      }

      NSLog(@"[USPAuth] Token registrado com sucesso.");
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
  } else {
    [self.defaults removeObjectForKey:@"oauthToken"];
  }
  [self.defaults synchronize];
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
  } else {
    [self.defaults removeObjectForKey:@"oauthTokenSecret"];
  }
  [self.defaults synchronize];
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
  [self.defaults synchronize];
  NSLog(@"User session cleared.");
}

@end

#endif
