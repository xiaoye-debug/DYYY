#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static NSString * const kDYYYPanelDidChangeNotification = @"DYYYFloatingPanelDidChangeNotification";
static NSString * const kDYYYPanelWallpaperImagePathKey = @"DYYYPanelWallpaperImagePath";
static NSString * const kDYYYPanelWallpaperOpacityKey = @"DYYYPanelWallpaperOpacity";
static CGFloat const kDYYYPanelWallpaperDefaultOpacity = 0.28;
static NSInteger const kDYYYPanelWallpaperImageViewTag = 260929;

// 与“界面设置 -> 修改底栏高度”共用同一个 DYYYTabBarHeight 配置。
extern "C" void DYYYFloatingPanelApplyTabBarDelta(CGFloat delta);
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


#pragma mark - DYYY Liquid Glass

static UIViewController *gDYYYFloatingAdjustPanel = nil;
static NSString * const kDYYYLiquidGlassStyleKey = @"DYYYLiquidGlassStyle";
static NSInteger const kDYYYLiquidGlassViewTag = 260925;

static BOOL DYYYIsLiquidGlassClear(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kDYYYLiquidGlassStyleKey] == 1;
}

static UIVisualEffect *DYYYMakeLiquidGlassEffect(BOOL interactive) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffectStyle style = DYYYIsLiquidGlassClear()
            ? UIGlassEffectStyleClear
            : UIGlassEffectStyleRegular;
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:style];
        effect.interactive = interactive;
        return effect;
    }

    // iOS 15–25 没有 UIGlassEffect，用两档系统材质模拟 Regular / Clear。
    return [UIBlurEffect effectWithStyle:DYYYIsLiquidGlassClear()
        ? UIBlurEffectStyleSystemUltraThinMaterial
        : UIBlurEffectStyleSystemChromeMaterial];
}

static UIView *DYYYMakeLiquidGlassView(CGRect frame, BOOL interactive) {
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:DYYYMakeLiquidGlassEffect(interactive)];
    glass.frame = frame;
    glass.tag = kDYYYLiquidGlassViewTag;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.userInteractionEnabled = NO;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;

    if (@available(iOS 26.0, *)) {
        // 原生 Liquid Glass 不额外叠深色底，避免 Clear 模式被压暗。
    } else {
        glass.backgroundColor = [UIColor colorWithWhite:0.12
                                                   alpha:DYYYIsLiquidGlassClear() ? 0.12 : 0.28];
    }
    return glass;
}

static void DYYYRefreshLiquidGlassViewsInView(UIView *root) {
    if (!root) return;

    for (UIView *subview in [root.subviews copy]) {
        if ([subview isKindOfClass:[UIVisualEffectView class]] &&
            subview.tag == kDYYYLiquidGlassViewTag) {
            UIVisualEffectView *glass = (UIVisualEffectView *)subview;
            BOOL interactive = NO;
            if (@available(iOS 26.0, *)) {
                UIGlassEffect *oldEffect = [glass.effect isKindOfClass:[UIGlassEffect class]]
                    ? (UIGlassEffect *)glass.effect : nil;
                interactive = oldEffect.isInteractive;
            }
            glass.effect = DYYYMakeLiquidGlassEffect(interactive);
            if (@available(iOS 26.0, *)) {
                glass.backgroundColor = UIColor.clearColor;
            } else {
                glass.backgroundColor = [UIColor colorWithWhite:0.12
                                                           alpha:DYYYIsLiquidGlassClear() ? 0.12 : 0.28];
            }
        }
        DYYYRefreshLiquidGlassViewsInView(subview);
    }
}

static void DYYYSetLiquidGlassStyle(NSInteger style) {
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:kDYYYLiquidGlassStyleKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (gDYYYFloatingAdjustPanel) {
        DYYYRefreshLiquidGlassViewsInView(gDYYYFloatingAdjustPanel.view);
    }
}

static void DYYYInstallLiquidGlass(UIView *container, CGFloat radius, BOOL interactive) {
    UIView *glass = DYYYMakeLiquidGlassView(container.bounds, interactive);
    glass.layer.cornerRadius = radius;
    glass.frame = container.bounds;
    [container insertSubview:glass atIndex:0];

    container.backgroundColor = [UIColor clearColor];
    container.layer.cornerRadius = radius;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.layer.masksToBounds = YES;

    if (@available(iOS 26.0, *)) {
        // 原生 Liquid Glass 自带高光与边缘折射；只补一层极淡的动态描边。
        container.layer.borderWidth = 0.5;
        container.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    } else {
        container.layer.borderWidth = 0.7;
        container.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
    }
}

static void DYYYStyleGlassButton(UIButton *button, CGFloat radius) {
    DYYYInstallLiquidGlass(button, radius, YES);
    button.layer.borderWidth = 0.0;
}

@interface DYYYFloatingSliderOverlay : UIView
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, assign) CGFloat minimum;
@property(nonatomic, assign) CGFloat maximum;
@property(nonatomic, assign) CGFloat initialValue;
@property(nonatomic, assign) BOOL isScale;
@property(nonatomic, assign) BOOL isTabBar;
@property(nonatomic, assign) BOOL isWallpaperOpacity;
@property(nonatomic, strong) UISlider *slider;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic, copy) void (^onChange)(CGFloat value);
@end

@implementation DYYYFloatingSliderOverlay

- (void)build {
    self.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = UIColor.clearColor;
    card.layer.cornerRadius = 24.0;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];
    if (self.isWallpaperOpacity) {
        card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
        card.layer.borderWidth = 0.7;
        card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    } else {
        DYYYInstallLiquidGlass(card, 24.0, NO);
    }

    UILabel *title = [[UILabel alloc] init];
    title.text = self.title;
    title.font = [UIFont boldSystemFontOfSize:23];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = self.isWallpaperOpacity ? @"调整插件壁纸的显示透明度" : (self.isScale ? @"默认值 0；左侧为负数，右侧为正数" : @"默认值 0；上移为正数，下移为负数");
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:subtitle];

    UILabel *name = [[UILabel alloc] init];
    name.text = self.isWallpaperOpacity ? @"透明度" : (self.isScale ? @"缩放调整" : @"距离调整");
    name.font = [UIFont boldSystemFontOfSize:17];
    name.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.valueLabel];

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = self.minimum;
    self.slider.maximumValue = self.maximum;
    self.slider.value = MIN(MAX(self.initialValue, self.minimum), self.maximum);
    self.slider.continuous = YES;
    self.slider.minimumTrackTintColor = [UIColor colorWithRed:0.28 green:0.65 blue:1.0 alpha:1.0];
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.slider.thumbTintColor = [UIColor colorWithRed:0.55 green:0.82 blue:1.0 alpha:1.0];
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.slider];

    UILabel *minLabel = [[UILabel alloc] init];
    minLabel.text = [NSString stringWithFormat:@"%+.0f", self.minimum];
    minLabel.font = [UIFont systemFontOfSize:11];
    minLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.38];
    minLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:minLabel];

    UILabel *zeroLabel = [[UILabel alloc] init];
    zeroLabel.text = @"0";
    zeroLabel.font = [UIFont systemFontOfSize:11];
    zeroLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.38];
    zeroLabel.textAlignment = NSTextAlignmentCenter;
    zeroLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:zeroLabel];

    UILabel *maxLabel = [[UILabel alloc] init];
    maxLabel.text = [NSString stringWithFormat:@"+%.0f", self.maximum];
    maxLabel.font = [UIFont systemFontOfSize:11];
    maxLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.38];
    maxLabel.textAlignment = NSTextAlignmentRight;
    maxLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:maxLabel];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认值  0" forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    reset.backgroundColor = UIColor.clearColor;
    reset.layer.cornerRadius = 14;
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:reset];
    DYYYStyleGlassButton(reset, 14.0);

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    close.backgroundColor = UIColor.clearColor;
    close.layer.cornerRadius = 14;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];
    DYYYStyleGlassButton(close, 14.0);

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
        [card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.heightAnchor constraintEqualToConstant:292],

        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [subtitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],

        [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [name.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:18],

        [self.valueLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [self.valueLabel.centerYAnchor constraintEqualToAnchor:name.centerYAnchor],

        [self.slider.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [self.slider.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [self.slider.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:12],

        [minLabel.leadingAnchor constraintEqualToAnchor:self.slider.leadingAnchor],
        [minLabel.topAnchor constraintEqualToAnchor:self.slider.bottomAnchor constant:2],
        [zeroLabel.centerXAnchor constraintEqualToAnchor:self.slider.centerXAnchor],
        [zeroLabel.topAnchor constraintEqualToAnchor:self.slider.bottomAnchor constant:2],
        [maxLabel.trailingAnchor constraintEqualToAnchor:self.slider.trailingAnchor],
        [maxLabel.topAnchor constraintEqualToAnchor:self.slider.bottomAnchor constant:2],

        [reset.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [reset.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [reset.bottomAnchor constraintEqualToAnchor:close.topAnchor constant:-7],
        [reset.heightAnchor constraintEqualToConstant:36],

        [close.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [close.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
        [close.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [close.heightAnchor constraintEqualToConstant:36],
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

@interface DYYYFloatingAdjustPanelViewController : UIViewController <PHPickerViewControllerDelegate>
@end

@implementation DYYYFloatingAdjustPanelViewController {
    UIView *_panel;
    UIScrollView *_scrollView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
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
    self.view.backgroundColor = UIColor.clearColor;

    _panel = [[UIView alloc] initWithFrame:CGRectZero];
    _panel.backgroundColor = UIColor.clearColor;
    _panel.layer.cornerRadius = 30.0;
    _panel.layer.cornerCurve = kCACornerCurveContinuous;
    _panel.layer.masksToBounds = YES;
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_panel];
    UIImageView *wallpaper = [[UIImageView alloc] initWithFrame:_panel.bounds];
    wallpaper.tag = kDYYYPanelWallpaperImageViewTag;
    wallpaper.contentMode = UIViewContentModeScaleAspectFill;
    wallpaper.alpha = kDYYYPanelWallpaperDefaultOpacity;
    wallpaper.clipsToBounds = YES;
    wallpaper.userInteractionEnabled = NO;
    wallpaper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_panel insertSubview:wallpaper atIndex:0];

    DYYYInstallLiquidGlass(_panel, 30.0, NO);
    [self refreshPanelWallpaper];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.layer.cornerRadius = 18;
    close.backgroundColor = UIColor.clearColor;
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.86] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightMedium];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:close];
    DYYYStyleGlassButton(close, 18.0);

    UILabel *title = [[UILabel alloc] init];
    title.text = @"视频页面调整";
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:title];

    UILabel *headerSub = [[UILabel alloc] init];
    headerSub.text = @"双指长按打开 · 调整即时生效";
    headerSub.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    headerSub.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    headerSub.textAlignment = NSTextAlignmentCenter;
    headerSub.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:headerSub];

    UISegmentedControl *glassStyle = [[UISegmentedControl alloc] initWithItems:@[@"Regular", @"Clear"]];
    glassStyle.selectedSegmentIndex = DYYYIsLiquidGlassClear() ? 1 : 0;
    glassStyle.selectedSegmentTintColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    glassStyle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    glassStyle.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    glassStyle.translatesAutoresizingMaskIntoConstraints = NO;
    glassStyle.accessibilityIdentifier = @"DYYYLiquidGlassStyle";
    [glassStyle addTarget:self action:@selector(liquidGlassStyleChanged:) forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:glassStyle];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [_panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_panel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_panel.heightAnchor constraintEqualToConstant:540],

        [close.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:16],
        [close.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:16],
        [close.widthAnchor constraintEqualToConstant:34],
        [close.heightAnchor constraintEqualToConstant:34],

        [title.centerXAnchor constraintEqualToAnchor:_panel.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [headerSub.centerXAnchor constraintEqualToAnchor:_panel.centerXAnchor],
        [headerSub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],

        [glassStyle.centerXAnchor constraintEqualToAnchor:_panel.centerXAnchor],
        [glassStyle.topAnchor constraintEqualToAnchor:headerSub.bottomAnchor constant:8],
        [glassStyle.widthAnchor constraintEqualToConstant:156],
        [glassStyle.heightAnchor constraintEqualToConstant:30],

        [_scrollView.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-10],
        [_scrollView.topAnchor constraintEqualToAnchor:glassStyle.bottomAnchor constant:10],
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
        @[@"插件壁纸", @"DYYYPanelWallpaperImage", @"image"],
        @[@"壁纸透明度", @"DYYYPanelWallpaperOpacity", @"wallpaperOpacity"],
    ];

    UIView *previous = nil;
    for (NSArray *item in items) {
        UIView *row = [self makeRowWithTitle:item[0] key:item[1] type:item[2]];
        [content addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [row.heightAnchor constraintEqualToConstant:58],
        ]];
        if (previous) {
            [row.topAnchor constraintEqualToAnchor:previous.bottomAnchor].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:content.topAnchor].active = YES;
        }
        previous = row;
    }
    [previous.bottomAnchor constraintEqualToAnchor:content.bottomAnchor].active = YES;
}

- (UIView *)makeRowWithTitle:(NSString *)title key:(NSString *)key type:(NSString *)type {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    row.backgroundColor = UIColor.clearColor;
    row.layer.cornerRadius = 18.0;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    row.layer.borderWidth = 0.0;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.accessibilityIdentifier = key;
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    [row addTarget:self action:@selector(rowTouchDown:) forControlEvents:UIControlEventTouchDown];
    [row addTarget:self action:@selector(rowTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    DYYYInstallLiquidGlass(row, 18.0, YES);

    UIView *iconBg = [[UIView alloc] init];
    iconBg.backgroundColor = [UIColor colorWithRed:0.20 green:0.48 blue:1.0 alpha:0.14];
    iconBg.layer.cornerRadius = 15;
    iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:iconBg];

    NSString *symbolName =
        [key isEqualToString:@"DYYYElementScale"] ? @"sidebar.right" :
        [key isEqualToString:@"DYYYNicknameScale"] ? @"person.crop.circle" :
        [key isEqualToString:@"DYYYDescriptionScale"] ? @"text.alignleft" :
        [key isEqualToString:@"DYYYIPLabelScale"] ? @"mappin.and.ellipse" :
        [key isEqualToString:@"DYYYNicknameVerticalOffset"] ? @"arrow.up.and.down.text.horizontal" :
        [key isEqualToString:@"DYYYDescriptionVerticalOffset"] ? @"text.alignleft" :
        [key isEqualToString:@"DYYYIPLabelVerticalOffset"] ? @"location.north.line" :
        @"rectangle.bottomhalf.inset.filled";
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName]];
    icon.tintColor = [UIColor colorWithRed:0.42 green:0.76 blue:1.0 alpha:1.0];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [iconBg addSubview:icon];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:titleLabel];

    UILabel *detail = [[UILabel alloc] init];
    detail.tag = 9001;
    detail.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    detail.textColor = [UIColor colorWithRed:0.48 green:0.80 blue:1.0 alpha:1.0];
    detail.textAlignment = NSTextAlignmentCenter;
    detail.backgroundColor = [UIColor colorWithRed:0.20 green:0.48 blue:1.0 alpha:0.12];
    detail.layer.cornerRadius = 10;
    detail.clipsToBounds = YES;
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:detail];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = [type isEqualToString:@"scale"] ? @"缩放 · 0 为默认" : ([type isEqualToString:@"tabbar"] ? @"高度 · 0 为默认" : @"位置 · 0 为默认");
    sub.font = [UIFont systemFontOfSize:10.5];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.38];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:sub];

    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    arrow.tintColor = [UIColor colorWithWhite:1.0 alpha:0.32];
    arrow.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:arrow];

    [NSLayoutConstraint activateConstraints:@[
        [iconBg.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10],
        [iconBg.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iconBg.widthAnchor constraintEqualToConstant:32],
        [iconBg.heightAnchor constraintEqualToConstant:32],
        [icon.leadingAnchor constraintEqualToAnchor:iconBg.leadingAnchor constant:8],
        [icon.trailingAnchor constraintEqualToAnchor:iconBg.trailingAnchor constant:-8],
        [icon.topAnchor constraintEqualToAnchor:iconBg.topAnchor constant:8],
        [icon.bottomAnchor constraintEqualToAnchor:iconBg.bottomAnchor constant:-8],
        [titleLabel.leadingAnchor constraintEqualToAnchor:iconBg.trailingAnchor constant:11],
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:detail.leadingAnchor constant:-8],
        [sub.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
        [detail.trailingAnchor constraintEqualToAnchor:arrow.leadingAnchor constant:-7],
        [detail.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [detail.heightAnchor constraintEqualToConstant:24],
        [detail.widthAnchor constraintGreaterThanOrEqualToConstant:48],
        [arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [arrow.widthAnchor constraintEqualToConstant:10],
        [arrow.heightAnchor constraintEqualToConstant:16],
    ]];
    [self updateRow:row];
    return row;
}

- (void)rowTouchDown:(UIButton *)row {
    [UIView animateWithDuration:0.08 animations:^{
        row.alpha = 0.72;
        row.transform = CGAffineTransformMakeScale(0.985, 0.985);
    }];
}
- (void)rowTouchUp:(UIButton *)row {
    [UIView animateWithDuration:0.16 animations:^{
        row.alpha = 1.0;
        row.transform = CGAffineTransformIdentity;
    }];
}
- (void)updateRow:(UIButton *)row {
    NSString *key = row.accessibilityIdentifier;
    UILabel *detail = [row viewWithTag:9001];

    if ([key isEqualToString:@"DYYYPanelWallpaperImage"]) {
        NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYPanelWallpaperImagePathKey];
        BOOL exists = path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
        detail.text = exists ? @"已设置" : @"选择";
        return;
    }

    if ([key isEqualToString:@"DYYYPanelWallpaperOpacity"]) {
        CGFloat opacity = DYYYPanelDoubleForKey(key, kDYYYPanelWallpaperDefaultOpacity);
        detail.text = [NSString stringWithFormat:@"%.0f%%", opacity * 100.0];
        return;
    }

    BOOL scale = [key isEqualToString:@"DYYYElementScale"] ||
                 [key isEqualToString:@"DYYYNicknameScale"] ||
                 [key isEqualToString:@"DYYYDescriptionScale"] ||
                 [key isEqualToString:@"DYYYIPLabelScale"];
    CGFloat value = scale ? DYYYPanelScaleDeltaForKey(key) : DYYYPanelDoubleForKey(key, 0.0);
    detail.text = DYYYPanelFormat(value, scale);
}

- (void)rowTapped:(UIButton *)row {
    NSString *key = row.accessibilityIdentifier;

    if ([key isEqualToString:@"DYYYPanelWallpaperImage"]) {
        [self showPanelWallpaperActions];
        return;
    }

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
    BOOL isWallpaperOpacity = [key isEqualToString:@"DYYYPanelWallpaperOpacity"];
    overlay.isWallpaperOpacity = isWallpaperOpacity;

    if (scale) {
        overlay.minimum = -0.5;
        overlay.maximum = 1.0;
        overlay.initialValue = DYYYPanelScaleDeltaForKey(key);
    } else if (overlay.isTabBar) {
        // 这里显示的是“相对默认底栏高度的增量”，但真正写入的是
        // 界面设置使用的 DYYYTabBarHeight 绝对高度值。
        overlay.minimum = -30.0;
        overlay.maximum = 60.0;
        NSString *heightString = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYTabBarHeight"];
        CGFloat currentHeight = heightString.length ? heightString.doubleValue : 49.0;
        overlay.initialValue = currentHeight - 49.0;
    } else if (isWallpaperOpacity) {
        overlay.minimum = 0.05;
        overlay.maximum = 1.0;
        overlay.initialValue = DYYYPanelDoubleForKey(key, kDYYYPanelWallpaperDefaultOpacity);
    } else {
        overlay.minimum = -80.0;
        overlay.maximum = 80.0;
        overlay.initialValue = DYYYPanelDoubleForKey(key, 0.0);
    }

    overlay.onChange = ^(CGFloat value) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        if (scale) {
            NSString *storedScale = [NSString stringWithFormat:@"%.4f", 1.0 + value];
            [defaults setObject:storedScale forKey:key];
        } else if (overlay.isTabBar) {
            // DYYYSettings.xm 的“修改底栏高度”实际保存的是绝对高度，
            // 不是 delta，更不能用 transform 拉伸字体。
            // 这里以 49pt 为默认内容高度：0 = 49pt，+11 = 60pt，-10 = 39pt。
            CGFloat targetHeight = MAX(30.0, MIN(109.0, 49.0 + value));
            [defaults setObject:[NSString stringWithFormat:@"%.1f", targetHeight]
                          forKey:@"DYYYTabBarHeight"];
            [defaults removeObjectForKey:@"DYYYTabBarHeightAdjustment"];
            DYYYFloatingPanelApplyTabBarDelta(value);
        } else if (isWallpaperOpacity) {
            [defaults setObject:@(MAX(0.05, MIN(1.0, value))) forKey:key];
            UIImageView *wallpaper = (UIImageView *)[_panel viewWithTag:kDYYYPanelWallpaperImageViewTag];
            if ([wallpaper isKindOfClass:[UIImageView class]]) wallpaper.alpha = value;
        } else {
            NSString *storedOffset = [NSString stringWithFormat:@"%.3f", value];
            [defaults setObject:storedOffset forKey:key];
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

    UIView *targetView = window;
    UIViewController *root = window.rootViewController;
    NSMutableArray *queue = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];

    while (queue.count) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([NSStringFromClass(vc.class) containsString:@"AWEPlayInteractionViewController"]) {
            if (vc.viewIfLoaded) targetView = vc.view;
            break;
        }

        [queue addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
    }

    __block void (^markNeedsLayout)(UIView *);
    markNeedsLayout = ^(UIView *view) {
        [view setNeedsLayout];
        for (UIView *subview in [view.subviews copy]) {
            markNeedsLayout(subview);
        }
    };

    markNeedsLayout(targetView);

    [UIView performWithoutAnimation:^{
        [targetView layoutIfNeeded];
    }];
}


- (void)liquidGlassStyleChanged:(UISegmentedControl *)control {
    DYYYSetLiquidGlassStyle(control.selectedSegmentIndex);
}

- (NSString *)panelWallpaperPath {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYPanelWallpaperImagePathKey];
    if (stored.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:stored]) {
        return stored;
    }
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    if (!library.length) return nil;
    NSString *path = [library stringByAppendingPathComponent:@"DYYYPanelWallpaper.jpg"];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

- (void)refreshPanelWallpaper {
    UIImageView *wallpaper = (UIImageView *)[_panel viewWithTag:kDYYYPanelWallpaperImageViewTag];
    if (![wallpaper isKindOfClass:[UIImageView class]]) return;
    wallpaper.image = [UIImage imageWithContentsOfFile:[self panelWallpaperPath]];
    wallpaper.alpha = DYYYPanelDoubleForKey(kDYYYPanelWallpaperOpacityKey, kDYYYPanelWallpaperDefaultOpacity);
}

- (void)showPanelWallpaperActions {
    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];
    overlay.tag = 260931;

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
    card.layer.cornerRadius = 24.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.7;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:card];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"插件壁纸";
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"设置或清除插件调整面板的壁纸";
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.48];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    UIButton *choose = [UIButton buttonWithType:UIButtonTypeSystem];
    [choose setTitle:@"选择壁纸" forState:UIControlStateNormal];
    choose.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    choose.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    choose.layer.cornerRadius = 14;
    choose.translatesAutoresizingMaskIntoConstraints = NO;
    [choose addTarget:self action:@selector(panelWallpaperChooseFromMenu:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:choose];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"清除壁纸" forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    clear.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    clear.layer.cornerRadius = 14;
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    clear.hidden = ([self panelWallpaperPath] == nil);
    [clear addTarget:self action:@selector(panelWallpaperClearFromMenu:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:clear];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cancel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    cancel.layer.cornerRadius = 14;
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel addTarget:self action:@selector(panelWallpaperMenuClose:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cancel];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:30],
        [card.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-30],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.heightAnchor constraintEqualToConstant:240],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5],
        [sub.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [choose.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22],
        [choose.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22],
        [choose.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:18],
        [choose.heightAnchor constraintEqualToConstant:42],
        [clear.leadingAnchor constraintEqualToAnchor:choose.leadingAnchor],
        [clear.trailingAnchor constraintEqualToAnchor:choose.trailingAnchor],
        [clear.topAnchor constraintEqualToAnchor:choose.bottomAnchor constant:8],
        [clear.heightAnchor constraintEqualToConstant:42],
        [cancel.leadingAnchor constraintEqualToAnchor:choose.leadingAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:choose.trailingAnchor],
        [cancel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [cancel.heightAnchor constraintEqualToConstant:42],
    ]];

    [self.view addSubview:overlay];
}

- (void)panelWallpaperChooseFromMenu:(UIButton *)button {
    UIView *overlay = button;
    while (overlay && overlay.tag != 260931) overlay = overlay.superview;
    [overlay removeFromSuperview];
    [self showPanelWallpaperPicker];
}

- (void)panelWallpaperClearFromMenu:(UIButton *)button {
    UIView *overlay = button;
    while (overlay && overlay.tag != 260931) overlay = overlay.superview;
    [overlay removeFromSuperview];
    [self clearPanelWallpaper];
}

- (void)panelWallpaperMenuClose:(UIButton *)button {
    UIView *overlay = button;
    while (overlay && overlay.tag != 260931) overlay = overlay.superview;
    [overlay removeFromSuperview];
}

- (void)clearPanelWallpaper {
    NSString *path = [self panelWallpaperPath];
    if (path.length) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDYYYPanelWallpaperImagePathKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self refreshPanelWallpaper];
    [self refreshRows];
}

- (void)showPanelWallpaperPicker {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.selectionLimit = 1;
    configuration.filter = [PHPickerFilter imagesFilter];

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) return;

    [provider loadObjectOfClass:[UIImage class] completionHandler:^(UIImage *image, NSError *error) {
        if (error || ![image isKindOfClass:[UIImage class]]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                UIImage *processedImage = image;
                CGFloat maxSide = 2200.0;
                CGSize size = processedImage.size;
                CGFloat scale = MIN(1.0, maxSide / MAX(size.width, size.height));
                if (scale < 1.0) {
                    size = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
                    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
                    [processedImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
                    processedImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                }

                NSData *data = UIImageJPEGRepresentation(processedImage, 0.88);
                if (!data) return;

                NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
                if (!library.length) return;

                NSString *path = [library stringByAppendingPathComponent:@"DYYYPanelWallpaper.jpg"];
                if (![data writeToFile:path atomically:YES]) return;

                [[NSUserDefaults standardUserDefaults] setObject:path forKey:kDYYYPanelWallpaperImagePathKey];
                [[NSUserDefaults standardUserDefaults] synchronize];

                [self refreshPanelWallpaper];
                [self refreshRows];
            }
        });
    }];
}

- (void)closePanel {
    self.view.hidden = YES;
    self.view.userInteractionEnabled = NO;
}

@end


#ifdef __cplusplus
extern "C" {
#endif

void DYYYShowFloatingAdjustPanel(UIViewController *presentingVC) {
    UIWindow *window = DYYYPanelActiveWindow();
    if (!window) return;

    if (gDYYYFloatingAdjustPanel) {
        if (gDYYYFloatingAdjustPanel.viewIfLoaded.superview == window) {
            gDYYYFloatingAdjustPanel.view.hidden = NO;
            gDYYYFloatingAdjustPanel.view.userInteractionEnabled = YES;
            [window bringSubviewToFront:gDYYYFloatingAdjustPanel.view];
            return;
        }
        gDYYYFloatingAdjustPanel = nil;
    }

    DYYYFloatingAdjustPanelViewController *panel = [[DYYYFloatingAdjustPanelViewController alloc] init];
    gDYYYFloatingAdjustPanel = panel;

    panel.view.frame = window.bounds;
    panel.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:panel.view];
}
#ifdef __cplusplus
}
#endif
