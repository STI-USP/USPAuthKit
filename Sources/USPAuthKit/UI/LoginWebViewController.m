// LoginWebViewController.m
// NuAuthKit
//
// Created by Vagner Machado on 22/05/25.
//

#if __has_include(<UIKit/UIKit.h>)

#import "LoginWebViewController.h"
#import "OAuth1Controller.h"
#import "USPAuthService.h"
#import <WebKit/WebKit.h>

@interface LoginWebViewController ()
// No need for WKNavigationDelegate conformance here if OAuth1Controller handles it fully.
// However, OAuth1Controller currently sets itself as the delegate.
@end

@implementation LoginWebViewController {
  WKWebView        *_webView;
  OAuth1Controller *_oauthController;
}

- (instancetype)init {
  if ((self = [super init])) {
    _oauthController = [[OAuth1Controller alloc] init];
  }
  return self;
}

- (void)loadView {
  UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
  v.backgroundColor = [UIColor systemBackgroundColor];
  self.view = v;
  
  UINavigationBar *bar = [[UINavigationBar alloc] init];
  bar.translatesAutoresizingMaskIntoConstraints = NO;
  
  UINavigationItem *navItem = [[UINavigationItem alloc] initWithTitle:@"Login"];
  navItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                initWithTitle:@"Cancelar"
                                style:UIBarButtonItemStylePlain
                                target:self
                                action:@selector(cancel)];
  [bar setItems:@[navItem]];
  [v addSubview:bar];
  
  WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
  _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
  _webView.translatesAutoresizingMaskIntoConstraints = NO;
  [v addSubview:_webView];
  
  [NSLayoutConstraint activateConstraints:@[
    [bar.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor],
    [bar.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],
    [bar.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],
    
    [_webView.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
    [_webView.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],
    [_webView.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],
    [_webView.bottomAnchor constraintEqualToAnchor:v.bottomAnchor]
  ]];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  // View is loaded, safe to start operations that might involve the view hierarchy
  // if they weren't tied to appearance.
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self startLoginFlow];
}

- (void)cancel {
  if (self.loginCompletion) {
    NSError *cancelErr = [NSError errorWithDomain:@"LoginWebViewController"
                                             code:NSUserCancelledError
                                         userInfo:@{NSLocalizedDescriptionKey:@"Login cancelado pelo usuário."}];
    // Call completion on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      self.loginCompletion(NO, cancelErr);
    });
  }
}

- (void)startLoginFlow {
  if (!_webView) {
    NSLog(@"Error: WebView is not initialized in LoginWebViewController.");
    if (self.loginCompletion) {
      NSError *setupError = [NSError errorWithDomain:@"LoginWebViewController"
                                                code:-2 // Arbitrary internal error code
                                            userInfo:@{NSLocalizedDescriptionKey:@"Falha na configuração interna da tela de login."}];
      dispatch_async(dispatch_get_main_queue(), ^{
        self.loginCompletion(NO, setupError);
      });
    }
    return;
  }
  
  [_oauthController loginWithWebView:_webView
                          completion:^(NSDictionary<NSString*,NSString*> * _Nullable tokens, NSError * _Nullable error) {
    if (error) {
      if (self.loginCompletion) {
        self.loginCompletion(NO, error);
      }
    } else {
      // Update USPAuthService with the new tokens
      USPAuthService *authService = [USPAuthService sharedService];
      authService.oauthToken = tokens[@"oauth_token"];
      authService.oauthTokenSecret = tokens[@"oauth_token_secret"];
      
      if (self.loginCompletion) {
        self.loginCompletion(YES, nil);
      }
    }
  }];
}

@end

#endif
