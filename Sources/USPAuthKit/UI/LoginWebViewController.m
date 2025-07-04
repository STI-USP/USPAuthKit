//  LoginWebViewController.m
//  NuAuthKit
//
//  Created by Vagner Machado on 22/05/25.
//

#if __has_include(<UIKit/UIKit.h>)

#import "LoginWebViewController.h"
#import "OAuth1Controller.h"
#import "USPAuthService.h"
#import <WebKit/WebKit.h>

@interface LoginWebViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIProgressView *progressView;
@end

@implementation LoginWebViewController {
  OAuth1Controller *_oauthController;
}

#pragma mark - Init
- (instancetype)init {
  if ((self = [super init])) {
    _oauthController = [[OAuth1Controller alloc] init];
  }
  return self;
}

- (void)dealloc {
  @try { [self.webView removeObserver:self forKeyPath:@"estimatedProgress"]; }
  @catch (__unused NSException *e) {}
}

#pragma mark - View Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.tintColor = UIColor.systemBlueColor;
}

- (void)loadView {
  UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
  root.backgroundColor = UIColor.systemBackgroundColor;
  self.view = root;

  // Barra de progresso fina logo abaixo do nav-bar
  self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
  self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
  self.progressView.tintColor = [UIColor colorNamed:@"BrandAccent"] ?: UIColor.systemBlueColor;
  [root addSubview:self.progressView];

  // WebView
  WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
  self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
  self.webView.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:self.webView];

  [NSLayoutConstraint activateConstraints:@[
    [self.progressView.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor],
    [self.progressView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [self.progressView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

    [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor],
    [self.webView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [self.webView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    [self.webView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
  ]];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  // Título + botão Cancelar
  self.title = @"Entrar";
  UIBarButtonItem *cancelBtn = [[UIBarButtonItem alloc] initWithTitle:@"Cancelar" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
  self.navigationItem.rightBarButtonItem = cancelBtn;

  // Observa progresso
  [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self startLoginFlow];
}

#pragma mark - Cancel & Progress
- (void)cancel {
  if (self.loginCompletion) {
    NSError *e = [NSError errorWithDomain:@"LoginWebViewController" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"Login cancelado pelo usuário."}];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      self.loginCompletion(NO, e);
    });
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)contex {
  if ([keyPath isEqualToString:@"estimatedProgress"]) {
    self.progressView.progress = self.webView.estimatedProgress;
    self.progressView.hidden = self.progressView.progress >= 1.0;
  }
}

#pragma mark - OAuth
- (void)startLoginFlow {
  if (!self.webView) {
    if (self.loginCompletion) {
      NSError *setupErr = [NSError errorWithDomain:@"LoginWebViewController" code:-2 userInfo:@{NSLocalizedDescriptionKey : @"Falha na configuração interna da tela de login."}];

      dispatch_async(dispatch_get_main_queue(), ^{
        self.loginCompletion(NO, setupErr);
      });

    }
    return;
  }

  __weak typeof(self) weakSelf = self;
  [_oauthController loginWithWebView:self.webView completion:^(NSDictionary<NSString *,NSString *> * _Nullable tokens, NSError * _Nullable error) {
    __strong typeof(weakSelf) self = weakSelf;
    if (error) {
      if (self.loginCompletion)
        self.loginCompletion(NO, error);
      return;
    }

    USPAuthService *svc = [USPAuthService sharedService];
    svc.oauthToken = tokens[@"oauth_token"];
    svc.oauthTokenSecret = tokens[@"oauth_token_secret"];

    if (self.loginCompletion)
      self.loginCompletion(YES, nil);
  }];
}

@end
#endif
