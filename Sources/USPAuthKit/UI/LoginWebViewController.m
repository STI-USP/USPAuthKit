// LoginWebViewController.m
// NuAuthKit
//
// Created by Vagner Machado on 22/05/25.
//

#if __has_include(<UIKit/UIKit.h>)

#import "LoginWebViewController.h"
#import "OAuth1Controller.h"
#import "USPAuthService.h" // Import to access sharedService for setting tokens
#import <WebKit/WebKit.h>

@interface LoginWebViewController ()
// No need for WKNavigationDelegate conformance here if OAuth1Controller handles it fully.
// However, OAuth1Controller currently sets itself as the delegate.
@end

@implementation LoginWebViewController {
    WKWebView        *_webView;
    OAuth1Controller *_oauthController;
    // No need for an explicit loading indicator here if OAuth1Controller manages its own
}

- (instancetype)init {
    if ((self = [super init])) {
        _oauthController = [[OAuth1Controller alloc] init];
    }
    return self;
}

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds]; // Use bounds for initial frame
    v.backgroundColor = [UIColor systemBackgroundColor];
    self.view = v;
    
    UINavigationBar *bar = [[UINavigationBar alloc] init]; // No need for new if using system one
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    
    UINavigationItem *navItem = [[UINavigationItem alloc] initWithTitle:@"Login"]; // Set a title
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
    // OAuth1Controller will set itself as the navigationDelegate to the _webView
    [v addSubview:_webView];
    
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],
        // Let the navigation bar determine its own intrinsic height or a standard height
        // [bar.heightAnchor constraintEqualToConstant:44],

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
    // It's generally better to start network operations or modal flows once the VC is fully on screen.
    [self startLoginFlow];
}

- (void)cancel {
    // USPAuthService will handle the dismissal when its loginCompletion is called.
    if (self.loginCompletion) {
        NSError *cancelErr = [NSError errorWithDomain:@"LoginWebViewController"
                                                 code:NSUserCancelledError // Standard error code for user cancellation
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
        // This completion from OAuth1Controller is already dispatched to the main queue.
        if (error) {
            if (self.loginCompletion) {
                self.loginCompletion(NO, error);
            }
        } else {
            // **** CRUCIAL STEP: Update USPAuthService with the new tokens ****
            USPAuthService *authService = [USPAuthService sharedService];
            authService.oauthToken = tokens[@"oauth_token"];         // Setter persists to NSUserDefaults
            authService.oauthTokenSecret = tokens[@"oauth_token_secret"]; // Setter persists
            
            if (self.loginCompletion) {
                self.loginCompletion(YES, nil);
            }
        }
    }];
}

@end

#endif
