#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif
void DYYYFloatingPanelApplyTabBarDelta(CGFloat delta);
#ifdef __cplusplus
}
#endif

static NSString * const kDYYYPanelDidChangeNotification = @"DYYYFloatingPanelDidChangeNotification";

static UIWindow *DYYYPanelActiveWindow(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (!candidate.hidden && candidate.alpha > 0.01 && candidate.windowLevel == UIWindowLevelNormal) {
                    if (candidate.isKeyWindow) return candidate;
                    if (!window) window = candidate;
                }
            }
        }
    }
    return window ?: UIApplication.sharedApplication.keyWindow;
}

static UIViewController *DYYYPanelTopViewController(UIViewController *vc) {
    if (!vc) return nil;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        return DYYYPanelTopViewController(((UINavigationController *)vc).visibleViewController ?: vc);
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        return DYYYPanelTopViewController(((UITabBarController *)vc).selectedViewController ?: vc);
    }
    for (UIViewController *child in vc.childViewControllers.reverseObjectEnumerator) {
        UIViewController *found = DYYYPanelTopViewController(child);
        if (found && found.viewIfLoaded.window) return found;
    }
    return vc;
}

static id DYYYPanelKVC(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try { return [object valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static id DYYYPanelCurrentAweme(void) {
    UIViewController *top = DYYYPanelTopViewController(DYYYPanelActiveWindow().rootViewController);
    if (!top) return nil;

    NSMutableArray *queue = [NSMutableArray arrayWithObject:top];
    while (queue.count) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSString *name = NSStringFromClass(vc.class);
        if ([name containsString:@"AWEPlayVideoViewController"] ||
            [name containsString:@"AWEFeedCellViewController"] ||
            [name containsString:@"AWEAwemeDetail"]) {
            id model = DYYYPanelKVC(vc, @"model");
            if (!model) model = DYYYPanelKVC(vc, @"awemeModel");
            if (model) return model;
        }

        id model = DYYYPanelKVC(vc, @"model");
        if (!model) model = DYYYPanelKVC(vc, @"awemeModel");
        if (model && (DYYYPanelKVC(model, @"author") || DYYYPanelKVC(model, @"desc"))) {
            return model;
        }
        [queue addObjectsFromArray:vc.childViewControllers];
    }
    return nil;
}

static NSString *DYYYPanelString(id object, NSArray<NSString *> *keys, NSString *fallback) {
    for (NSString *key in keys) {
        id value = DYYYPanelKVC(object, key);
        if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    }
    return fallback;
}

static CGFloat DYYYPanelDoubleForKey(NSString *key, CGFloat fallback) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

static CGFloat DYYYPanelScaleDeltaForKey(NSString *key) {
    return DYYYPanelDoubleForKey(key, 1.0) - 1.0;
}

static NSString *DYYYPanelFormat(CGFloat value, BOOL percent) {
    if (fabs(value) < 0.005) return @"0";
    return percent
        ? [NSString stringWithFormat:@"%+.0f%%", value * 100.0]
        : [NSString stringWithFormat:@"%+.1f", value];
}

@interface DYYYFloatingSliderOverlay : UIView
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, assign) CGFloat minimum;
@property(nonatomic, assign) CGFloat maximum;
@property(nonatomic, assign) CGFloat initialValue;
@property(nonatomic, assign) BOOL isScale;
@property(nonatomic, assign) BOOL isTabBar;
@property(nonatomic, strong) UISlider *slider;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic, copy) void (^onChange)(CGFloat value);
@end

@implementation DYYYFloatingSliderOverlay

- (void)build {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = self.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:blurView];

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.12 alpha:0.97]
            : [UIColor colorWithWhite:0.98 alpha:0.97];
    }];
    card.layer.cornerRadius = 26;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    UILabel *title = [[UILabel alloc] init];
    title.text = self.title;
    title.font = [UIFont boldSystemFontOfSize:24];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.labelColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = self.isScale ? @"默认值 0；左侧为负数，右侧为正数" : @"默认值 0；左移为负数，右移为正数";
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:subtitle];

    UILabel *name = [[UILabel alloc] init];
    name.text = self.isScale ? @"缩放调整" : @"距离调整";
    name.font = [UIFont boldSystemFontOfSize:17];
    name.textColor = UIColor.labelColor;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.textColor = UIColor.labelColor;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.valueLabel];

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = self.minimum;
    self.slider.maximumValue = self.maximum;
    self.slider.value = MIN(MAX(self.initialValue, self.minimum), self.maximum);
    self.slider.continuous = YES;
    self.slider.minimumTrackTintColor = UIColor.labelColor;
    self.slider.maximumTrackTintColor = UIColor.tertiaryLabelColor;
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.slider];

    UILabel *minLabel = [[UILabel alloc] init];
    minLabel.text = [NSString stringWithFormat:@"%+.0f", self.minimum];
    minLabel.font = [UIFont systemFontOfSize:12];
    minLabel.textColor = UIColor.secondaryLabelColor;
    minLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:minLabel];

    UILabel *zeroLabel = [[UILabel alloc] init];
    zeroLabel.text = @"0";
    zeroLabel.font = [UIFont systemFontOfSize:12];
    zeroLabel.textColor = UIColor.secondaryLabelColor;
    zeroLabel.textAlignment = NSTextAlignmentCenter;
    zeroLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:zeroLabel];

    UILabel *maxLabel = [[UILabel alloc] init];
    maxLabel.text = [NSString stringWithFormat:@"+%.0f", self.maximum];
    maxLabel.font = [UIFont systemFontOfSize:12];
    maxLabel.textColor = UIColor.secondaryLabelColor;
    maxLabel.textAlignment = NSTextAlignmentRight;
    maxLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:maxLabel];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认值  0" forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    reset.backgroundColor = UIColor.secondarySystemBackgroundColor;
    reset.layer.cornerRadius = 14;
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:reset];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    close.backgroundColor = UIColor.secondarySystemBackgroundColor;
    close.layer.cornerRadius = 14;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
        [card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.heightAnchor constraintEqualToConstant:300],

        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:25],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5],
        [subtitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],

        [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [name.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:30],

        [self.valueLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [self.valueLabel.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],

        [self.slider.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [self.slider.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [self.slider.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:14],

        [minLabel.leadingAnchor constraintEqualToAnchor:self.slider.leadingAnchor],
        [minLabel.topAnchor constraintEqualToAnchor:self.slider.bottomAnchor constant:3],
        [zeroLabel.centerXAnchor constraintEqualToAnchor:self.slider.centerXAnchor],
        [zeroLabel.topAnchor constraintEqualToAnchor:self.slider.bottomAnchor constant:3],
        [maxLabel.trailingAnchor constraintEqualToAnchor:self.slider.trailingAnchor],
        [maxLabel.topAnchor constraintEqualToAnchor:self.slider.bottomAnchor constant:3],

        [reset.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [reset.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [reset.bottomAnchor constraintEqualToAnchor:close.topAnchor constant:-10],
        [reset.heightAnchor constraintEqualToConstant:44],

        [close.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [close.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [close.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
        [close.heightAnchor constraintEqualToConstant:44],
    ]];

    [self refreshValueLabel:self.slider.value];
}

- (void)refreshValueLabel:(CGFloat)value {
    self.valueLabel.text = self.isScale ? DYYYPanelFormat(value, YES) : DYYYPanelFormat(value, NO);
}

- (void)sliderChanged:(UISlider *)slider {
    [self refreshValueLabel:slider.value];
    if (self.onChange) self.onChange(slider.value);
}

- (void)resetTapped {
    self.slider.value = 0.0;
    [self sliderChanged:self.slider];
}

- (void)closeTapped {
    [self removeFromSuperview];
}

@end

@interface DYYYFloatingAdjustPanelViewController : UIViewController
@end

@implementation DYYYFloatingAdjustPanelViewController {
    UIView *_panel;
    UIScrollView *_scrollView;
    UILabel *_userNameLabel;
    UILabel *_userIDLabel;
    UILabel *_bioLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dyyyPanelValueChanged:)
                                                 name:kDYYYPanelDidChangeNotification
                                               object:nil];
    [self buildUI];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dyyyPanelValueChanged:(NSNotification *)notification {
    [self refreshRows];
    [self refreshLiveLayout];
}

- (void)buildUI {
    UIVisualEffectView *backgroundBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    backgroundBlur.frame = self.view.bounds;
    backgroundBlur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backgroundBlur.alpha = 0.18;
    [self.view addSubview:backgroundBlur];

    _panel = [[UIView alloc] initWithFrame:CGRectZero];
    _panel.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.12 alpha:0.80]
            : [UIColor colorWithWhite:0.96 alpha:0.82];
    }];
    _panel.layer.cornerRadius = 24;
    _panel.layer.borderWidth = 0.8;
    _panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    _panel.clipsToBounds = YES;
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_panel];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.backgroundColor = [UIColor colorWithRed:0.95 green:0.22 blue:0.22 alpha:0.62];
    close.layer.cornerRadius = 18;
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:0.45 green:0.02 blue:0.02 alpha:1] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightMedium];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:close];

    UIButton *collapse = [UIButton buttonWithType:UIButtonTypeSystem];
    collapse.backgroundColor = [UIColor colorWithWhite:1 alpha:0.75];
    collapse.layer.cornerRadius = 18;
    [collapse setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    collapse.tintColor = UIColor.labelColor;
    collapse.translatesAutoresizingMaskIntoConstraints = NO;
    [collapse addTarget:self action:@selector(collapsePanel) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:collapse];

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.52];
    card.layer.cornerRadius = 22;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:card];

    UIView *avatar = [[UIView alloc] initWithFrame:CGRectZero];
    avatar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    avatar.layer.cornerRadius = 30;
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:avatar];

    UILabel *avatarText = [[UILabel alloc] init];
    avatarText.text = @"◉";
    avatarText.font = [UIFont systemFontOfSize:30];
    avatarText.textAlignment = NSTextAlignmentCenter;
    avatarText.textColor = UIColor.secondaryLabelColor;
    avatarText.translatesAutoresizingMaskIntoConstraints = NO;
    [avatar addSubview:avatarText];

    _userNameLabel = [[UILabel alloc] init];
    _userNameLabel.font = [UIFont boldSystemFontOfSize:20];
    _userNameLabel.textColor = UIColor.labelColor;
    _userNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_userNameLabel];

    _userIDLabel = [[UILabel alloc] init];
    _userIDLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _userIDLabel.textColor = UIColor.systemTealColor;
    _userIDLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_userIDLabel];

    _bioLabel = [[UILabel alloc] init];
    _bioLabel.font = [UIFont systemFontOfSize:13];
    _bioLabel.textColor = UIColor.secondaryLabelColor;
    _bioLabel.numberOfLines = 1;
    _bioLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_bioLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [_panel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_panel.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor constant:-160],
        [_panel.heightAnchor constraintGreaterThanOrEqualToConstant:500],

        [close.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:18],
        [close.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:18],
        [close.widthAnchor constraintEqualToConstant:36],
        [close.heightAnchor constraintEqualToConstant:36],

        [collapse.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-18],
        [collapse.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:18],
        [collapse.widthAnchor constraintEqualToConstant:36],
        [collapse.heightAnchor constraintEqualToConstant:36],

        [card.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:18],
        [card.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-18],
        [card.topAnchor constraintEqualToAnchor:close.bottomAnchor constant:16],
        [card.heightAnchor constraintEqualToConstant:92],

        [avatar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [avatar.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [avatar.widthAnchor constraintEqualToConstant:60],
        [avatar.heightAnchor constraintEqualToConstant:60],

        [avatarText.centerXAnchor constraintEqualToAnchor:avatar.centerXAnchor],
        [avatarText.centerYAnchor constraintEqualToAnchor:avatar.centerYAnchor],

        [_userNameLabel.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:12],
        [_userNameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:13],
        [_userNameLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [_userIDLabel.leadingAnchor constraintEqualToAnchor:_userNameLabel.leadingAnchor],
        [_userIDLabel.topAnchor constraintEqualToAnchor:_userNameLabel.bottomAnchor constant:3],
        [_userIDLabel.trailingAnchor constraintEqualToAnchor:_userNameLabel.trailingAnchor],

        [_bioLabel.leadingAnchor constraintEqualToAnchor:_userNameLabel.leadingAnchor],
        [_bioLabel.topAnchor constraintEqualToAnchor:_userIDLabel.bottomAnchor constant:4],
        [_bioLabel.trailingAnchor constraintEqualToAnchor:_userNameLabel.trailingAnchor],
    ]];

    UIButton *search = [UIButton buttonWithType:UIButtonTypeSystem];
    [search setImage:[UIImage systemImageNamed:@"magnifyingglass"] forState:UIControlStateNormal];
    search.tintColor = UIColor.whiteColor;
    search.backgroundColor = UIColor.systemTealColor;
    search.layer.cornerRadius = 15;
    search.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:search];

    [NSLayoutConstraint activateConstraints:@[
        [search.centerXAnchor constraintEqualToAnchor:_panel.centerXAnchor],
        [search.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:10],
        [search.widthAnchor constraintEqualToConstant:30],
        [search.heightAnchor constraintEqualToConstant:30],
    ]];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-10],
        [_scrollView.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-10],
    ]];

    UIView *content = [[UIView alloc] initWithFrame:CGRectZero];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor],
    ]];

    NSArray *items = @[
        @[@"右侧栏缩放度", @"DYYYElementScale", @"scale"],
        @[@"昵称缩放控制", @"DYYYNicknameScale", @"scale"],
        @[@"文案缩放控制", @"DYYYDescriptionScale", @"scale"],
        @[@"属地缩放控制", @"DYYYIPLabelScale", @"scale"],
        @[@"昵称Y轴距离", @"DYYYNicknameVerticalOffset", @"offset"],
        @[@"文案Y轴距离", @"DYYYDescriptionVerticalOffset", @"offset"],
        @[@"属地Y轴距离", @"DYYYIPLabelVerticalOffset", @"offset"],
        @[@"修改底栏高度", @"DYYYTabBarHeightAdjustment", @"tabbar"],
    ];

    UIView *previous = nil;
    for (NSArray *item in items) {
        UIView *row = [self makeRowWithTitle:item[0] key:item[1] type:item[2]];
        [content addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [row.heightAnchor constraintEqualToConstant:72],
        ]];
        if (previous) {
            [row.topAnchor constraintEqualToAnchor:previous.bottomAnchor].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:content.topAnchor].active = YES;
        }
        previous = row;
    }
    [previous.bottomAnchor constraintEqualToAnchor:content.bottomAnchor].active = YES;

    [self reloadCurrentVideoInfo];
}

- (UIView *)makeRowWithTitle:(NSString *)title key:(NSString *)key type:(NSString *)type {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    row.layer.cornerRadius = 18;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.accessibilityIdentifier = key;
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:titleLabel];

    UILabel *detail = [[UILabel alloc] init];
    detail.tag = 9001;
    detail.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.textAlignment = NSTextAlignmentRight;
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:detail];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = [type isEqualToString:@"scale"] ? @"0 = 默认大小" : ([type isEqualToString:@"tabbar"] ? @"0 = 默认底栏高度" : @"0 = 默认位置");
    sub.font = [UIFont systemFontOfSize:11];
    sub.textColor = UIColor.tertiaryLabelColor;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:sub];

    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    arrow.tintColor = UIColor.tertiaryLabelColor;
    arrow.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:arrow];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18],
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:13],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:detail.leadingAnchor constant:-8],
        [sub.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3],
        [detail.trailingAnchor constraintEqualToAnchor:arrow.leadingAnchor constant:-10],
        [detail.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [arrow.widthAnchor constraintEqualToConstant:12],
        [arrow.heightAnchor constraintEqualToConstant:18],
    ]];

    [self updateRow:row];
    return row;
}

- (void)updateRow:(UIButton *)row {
    NSString *key = row.accessibilityIdentifier;
    UILabel *detail = [row viewWithTag:9001];
    BOOL scale = [key isEqualToString:@"DYYYElementScale"] ||
                 [key isEqualToString:@"DYYYNicknameScale"] ||
                 [key isEqualToString:@"DYYYDescriptionScale"] ||
                 [key isEqualToString:@"DYYYIPLabelScale"];
    CGFloat value = scale ? DYYYPanelScaleDeltaForKey(key) : DYYYPanelDoubleForKey(key, 0.0);
    detail.text = DYYYPanelFormat(value, scale);
}

- (void)rowTapped:(UIButton *)row {
    NSString *key = row.accessibilityIdentifier;
    NSString *title = @"";
    for (UIView *sub in row.subviews) {
        if ([sub isKindOfClass:[UILabel class]] && sub.tag != 9001) {
            title = ((UILabel *)sub).text ?: @"";
            break;
        }
    }

    DYYYFloatingSliderOverlay *overlay = [[DYYYFloatingSliderOverlay alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.title = title;
    overlay.key = key;

    BOOL scale = [key isEqualToString:@"DYYYElementScale"] ||
                 [key isEqualToString:@"DYYYNicknameScale"] ||
                 [key isEqualToString:@"DYYYDescriptionScale"] ||
                 [key isEqualToString:@"DYYYIPLabelScale"];
    overlay.isScale = scale;
    overlay.isTabBar = [key isEqualToString:@"DYYYTabBarHeightAdjustment"];

    if (scale) {
        overlay.minimum = -0.5;
        overlay.maximum = 1.0;
        overlay.initialValue = DYYYPanelScaleDeltaForKey(key);
    } else if (overlay.isTabBar) {
        overlay.minimum = -30.0;
        overlay.maximum = 60.0;
        overlay.initialValue = DYYYPanelDoubleForKey(key, 0.0);
    } else {
        overlay.minimum = -80.0;
        overlay.maximum = 80.0;
        overlay.initialValue = DYYYPanelDoubleForKey(key, 0.0);
    }

    overlay.onChange = ^(CGFloat value) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        if (scale) {
            [defaults setObject:@(1.0 + value) forKey:key];
        } else if (overlay.isTabBar) {
            [defaults setObject:@(value) forKey:key];
            DYYYFloatingPanelApplyTabBarDelta(value);
        } else {
            [defaults setObject:@(value) forKey:key];
        }

        [defaults synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:kDYYYPanelDidChangeNotification object:key];
    };

    [self.view addSubview:overlay];
    [overlay build];
}

- (void)refreshRows {
    UIView *content = _scrollView.subviews.firstObject;
    for (UIView *view in content.subviews) {
        if ([view isKindOfClass:[UIButton class]]) [self updateRow:(UIButton *)view];
    }
}

- (void)refreshLiveLayout {
    UIWindow *window = DYYYPanelActiveWindow();
    if (!window) return;
    void (^mark)(UIView *) = ^(UIView *view) {
        [view setNeedsLayout];
        for (UIView *sub in view.subviews) [sub setNeedsLayout];
    };
    mark(window);
    [UIView performWithoutAnimation:^{
        [window layoutIfNeeded];
    }];
}

- (void)reloadCurrentVideoInfo {
    id model = DYYYPanelCurrentAweme();
    id author = DYYYPanelKVC(model, @"author");
    _userNameLabel.text = DYYYPanelString(author, @[@"nickname", @"displayName"], @"当前视频");
    NSString *uid = DYYYPanelString(author, @[@"userID", @"uid", @"uniqueID"], @"");
    _userIDLabel.text = uid.length ? [NSString stringWithFormat:@"专属ID:%@", uid] : @"";
    _bioLabel.text = DYYYPanelString(author, @[@"signature", @"bio"], @"实时调整视频页面元素");
}

- (void)collapsePanel {
    _panel.hidden = YES;
}

- (void)closePanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

%hook AWENormalModeTabBar

- (void)setFrame:(CGRect)frame {
    CGFloat delta = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTabBarHeightAdjustment"] doubleValue];
    NSNumber *original = objc_getAssociatedObject(self, @selector(setFrame:));
    if (!original && frame.size.height > 20.0) {
        objc_setAssociatedObject(self, @selector(setFrame:), @(frame.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        original = @(frame.size.height);
    }

    if (original) {
        CGFloat targetHeight = MAX(1.0, original.doubleValue + delta);
        CGFloat bottom = CGRectGetMaxY(frame);
        frame.size.height = targetHeight;
        frame.origin.y = bottom - targetHeight;
    }
    %orig(frame);
}

%end

void DYYYShowFloatingAdjustPanel(UIViewController *presentingVC) {
    if (!presentingVC) return;
    UIViewController *top = DYYYPanelTopViewController(presentingVC);
    if (!top || [top isKindOfClass:NSClassFromString(@"DYYYFloatingAdjustPanelViewController")]) return;

    DYYYFloatingAdjustPanelViewController *panel = [[DYYYFloatingAdjustPanelViewController alloc] init];
    panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [top presentViewController:panel animated:YES completion:nil];
}
