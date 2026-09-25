#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString * const kDYYYPanelDidChangeNotification = @"DYYYFloatingPanelDidChangeNotification";

// 与“界面设置 -> 修改底栏高度”共用同一个 DYYYTabBarHeight 配置。
void DYYYApplyTabBarHeightSettingNow(void);
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
    self.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.10 alpha:0.98]
            : [UIColor colorWithWhite:0.98 alpha:0.98];
    }];
    card.layer.cornerRadius = 24;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.18;
    card.layer.shadowRadius = 18;
    card.layer.shadowOffset = CGSizeMake(0, 8);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    UILabel *title = [[UILabel alloc] init];
    title.text = self.title;
    title.font = [UIFont boldSystemFontOfSize:23];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.labelColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = self.isScale ? @"默认值 0；左侧为负数，右侧为正数" : @"默认值 0；上移为正数，下移为负数";
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
    minLabel.font = [UIFont systemFontOfSize:11];
    minLabel.textColor = UIColor.secondaryLabelColor;
    minLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:minLabel];

    UILabel *zeroLabel = [[UILabel alloc] init];
    zeroLabel.text = @"0";
    zeroLabel.font = [UIFont systemFontOfSize:11];
    zeroLabel.textColor = UIColor.secondaryLabelColor;
    zeroLabel.textAlignment = NSTextAlignmentCenter;
    zeroLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:zeroLabel];

    UILabel *maxLabel = [[UILabel alloc] init];
    maxLabel.text = [NSString stringWithFormat:@"+%.0f", self.maximum];
    maxLabel.font = [UIFont systemFontOfSize:11];
    maxLabel.textColor = UIColor.secondaryLabelColor;
    maxLabel.textAlignment = NSTextAlignmentRight;
    maxLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:maxLabel];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认值  0" forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    reset.backgroundColor = UIColor.secondarySystemBackgroundColor;
    reset.layer.cornerRadius = 12;
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:reset];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    close.backgroundColor = UIColor.secondarySystemBackgroundColor;
    close.layer.cornerRadius = 12;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];

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

@interface DYYYFloatingAdjustPanelViewController : UIViewController
@end

static DYYYFloatingAdjustPanelViewController *gDYYYFloatingAdjustPanel = nil;

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
    _panel.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.12 alpha:0.88]
            : [UIColor colorWithWhite:0.96 alpha:0.90];
    }];
    _panel.layer.cornerRadius = 24;
    _panel.layer.borderWidth = 0.8;
    _panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    _panel.layer.shadowColor = UIColor.blackColor.CGColor;
    _panel.layer.shadowOpacity = 0.18;
    _panel.layer.shadowRadius = 16;
    _panel.layer.shadowOffset = CGSizeMake(0, 8);
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_panel];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.backgroundColor = [UIColor colorWithRed:0.95 green:0.22 blue:0.22 alpha:0.70];
    close.layer.cornerRadius = 17;
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:0.45 green:0.02 blue:0.02 alpha:1] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightMedium];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:close];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"视频页面调整";
    title.font = [UIFont boldSystemFontOfSize:21];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.labelColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:title];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [_panel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_panel.heightAnchor constraintEqualToConstant:520],

        [close.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:16],
        [close.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:16],
        [close.widthAnchor constraintEqualToConstant:34],
        [close.heightAnchor constraintEqualToConstant:34],

        [title.centerXAnchor constraintEqualToAnchor:_panel.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],

        [_scrollView.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-10],
        [_scrollView.topAnchor constraintEqualToAnchor:close.bottomAnchor constant:12],
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
    sub.text = [type isEqualToString:@"scale"] ? @"0 = 默认大小" : ([type isEqualToString:@"tabbar"] ? @"0 = 默认高度（49pt）" : @"0 = 默认位置");
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
        // 这里显示的是“相对默认底栏高度的增量”，但真正写入的是
        // 界面设置使用的 DYYYTabBarHeight 绝对高度值。
        overlay.minimum = -30.0;
        overlay.maximum = 60.0;
        NSString *heightString = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYTabBarHeight"];
        CGFloat currentHeight = heightString.length ? heightString.doubleValue : 49.0;
        overlay.initialValue = currentHeight - 49.0;
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
            DYYYApplyTabBarHeightSettingNow();
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
