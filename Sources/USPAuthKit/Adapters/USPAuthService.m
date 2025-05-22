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
  NSParameterAssert(completion);
  
  // 1) Cache
  // Check if both token and some user data (even if just an ID) exist.
  if (self.oauthToken.length > 0 && self.userData.count > 0) {
    // Ensure completion is called on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(self.userData, nil);
    });
    return;
  }
  
  // 2) Apresenta login
  LoginWebViewController *loginVC = [[LoginWebViewController alloc] init];
  
  // This wrapper ensures the final completion is on the main thread.
  void (^postDismissCompletion)(NSDictionary<NSString*,id>*, NSError*) = ^(NSDictionary<NSString*,id>* userResult, NSError *errorResult) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(userResult, errorResult);
    });
  };
  
  loginVC.loginCompletion = ^(BOOL success, NSError * _Nullable loginError) {
    // Always dismiss the loginVC first.
    // The dismissal completion block handles the next steps.
    [fromVC dismissViewControllerAnimated:YES completion:^{
      if (!success) {
        postDismissCompletion(nil, loginError);
        return;
      }
      
      // 3) Tokens should have been saved by LoginWebViewController via sharedService setters.
      // Now fetch user data + register token
      [self fetchUserDataWithCompletion:^(NSDictionary * _Nullable user, NSError * _Nullable fetchErr) {
        if (fetchErr) {
          postDismissCompletion(nil, fetchErr);
          return;
        }
        // Ensure user dictionary is not nil before proceeding
        if (!user) {
          NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey:@"Dados do usuário não encontrados após o fetch."}];
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

#pragma mark – Helpers

- (void)fetchUserDataWithCompletion:(void(^)(NSDictionary<NSString*,id>* _Nullable user,
                                             NSError * _Nullable error))completion {
  NSParameterAssert(completion);
  if (!self.oauthToken || !self.oauthTokenSecret) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:1 // Arbitrary code for missing tokens
                                 userInfo:@{NSLocalizedDescriptionKey:@"Tokens OAuth não disponíveis para buscar dados do usuário."}];
    completion(nil, e);
    return;
  }
  
  NSURLRequest *req = [OAuth1Controller preparedRequestForPath:@"/wsusuario/oauth/usuariousp"
                                                    parameters:nil
                                                    HTTPmethod:@"POST"
                                                    oauthToken:self.oauthToken
                                                   oauthSecret:self.oauthTokenSecret];
  if (!req) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:0 // Standard code for request creation failure
                                 userInfo:@{NSLocalizedDescriptionKey:@"Não foi possível criar requisição para buscar dados do usuário."}];
    completion(nil, e);
    return;
  }
  
  [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                   completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable resp, NSError * _Nullable err) {
    if (err) {
      completion(nil, err);
      return;
    }
    if (!data) {
      NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                       code:3 // Arbitrary code for no data
                                   userInfo:@{NSLocalizedDescriptionKey:@"Nenhum dado recebido do servidor."}];
      completion(nil, e);
      return;
    }
    
    NSError *jsonErr;
    NSDictionary *user = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
    
    if (jsonErr || ![user isKindOfClass:NSDictionary.class]) {
      NSError *e = jsonErr ? jsonErr :
      [NSError errorWithDomain:@"USPAuthService"
                          code:4 // Arbitrary code for invalid response
                      userInfo:@{NSLocalizedDescriptionKey:@"Resposta inválida do servidor ao buscar dados do usuário."}];
      completion(nil, e);
      return;
    }
    
    // Persiste em cache
    [self.defaults setObject:data forKey:@"userData"];
    [self.defaults synchronize];
    
    completion(user, nil);
  }] resume];
}

- (void)registerTokenWithCompletion:(void(^)(NSError * _Nullable error))completion {
  NSParameterAssert(completion);
  NSString *wsUserId = self.userData[@"wsuserid"];
  
  if (!wsUserId || wsUserId.length == 0) {
    NSError *e = [NSError errorWithDomain:@"USPAuthService"
                                     code:5 // Arbitrary code for missing wsuserid
                                 userInfo:@{NSLocalizedDescriptionKey:@"ID do usuário (wsuserid) não encontrado para registrar o token."}];
    completion(e);
    return;
  }
  
  NSURL *url = [NSURL URLWithString: [kOAuthServiceBaseURL stringByAppendingString:@"/registrar"]];
  NSDictionary *body = @{ @"token": wsUserId, @"app": @"AppEcard" };
  
  [[HTTPClient sharedClient] postJSON:body
                                toURL:url
                           completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable resp, NSError * _Nullable err) {
    if (err || (resp && resp.statusCode != 200)) {
      NSError *effectiveError = err;
      if (!effectiveError && resp) { // If no transport error, but bad status code
        NSString *desc = [NSString stringWithFormat:@"Falha ao registrar token. Status: %ld", (long)resp.statusCode];
        effectiveError = [NSError errorWithDomain:@"USPAuthService"
                                             code:resp.statusCode
                                         userInfo:@{NSLocalizedDescriptionKey:desc}];
      } else if (!effectiveError) { // Fallback if err and resp are nil (should not happen with valid HTTPClient)
        effectiveError = [NSError errorWithDomain:@"USPAuthService"
                                             code:6 // Arbitrary code for unknown registration error
                                         userInfo:@{NSLocalizedDescriptionKey:@"Falha desconhecida ao registrar token."}];
      }
      completion(effectiveError);
      return;
    }
    
    [self.defaults setBool:YES forKey:@"isRegistered"];
    [self.defaults synchronize];
    
    completion(nil);
  }];
}

#pragma mark – Propriedades set (OAuthToken and Secret)

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
