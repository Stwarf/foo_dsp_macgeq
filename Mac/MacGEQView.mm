#import "stdafx.h"
#import "dsp_sample.h"

#import <Cocoa/Cocoa.h>

@class MacGEQSurfaceView;

@protocol MacGEQSurfaceDelegate
- (void)surfaceSettingsChanged:(MacGEQSurfaceView *)surface;
@end

@interface MacGEQSurfaceView : NSView
@property (nonatomic) macgeq::EqSettings settings;
@property (nonatomic, weak) id<MacGEQSurfaceDelegate> delegate;
@end

@interface MacGEQViewController : NSViewController <MacGEQSurfaceDelegate>
@property (nonatomic) dsp_preset_edit_callback_v2::ptr callback;
@property (nonatomic) MacGEQSurfaceView *surface;
@property (nonatomic) NSButton *enabledButton;
@property (nonatomic) NSPopUpButton *bandModePopup;
@property (nonatomic) NSSlider *preampSlider;
@property (nonatomic) NSTextField *preampValue;
@property (nonatomic) BOOL compactChrome;
@end

@implementation MacGEQSurfaceView {
    NSInteger _dragBand;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _dragBand = -1;
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (void)setSettings:(macgeq::EqSettings)settings {
    _settings = settings;
    [self setNeedsDisplay:YES];
}

- (NSRect)plotRect {
    const CGFloat width = self.bounds.size.width;
    const CGFloat height = self.bounds.size.height;
    const CGFloat rightLabelWidth = width < 360.0 ? 38.0 : 58.0;
    const CGFloat bottomLabelHeight = height < 150.0 ? 18.0 : 28.0;
    const CGFloat topPad = height < 150.0 ? 12.0 : 28.0;
    const CGFloat sidePad = width < 420.0 ? 14.0 : 28.0;
    return NSInsetRect(NSMakeRect(sidePad, bottomLabelHeight, MAX(width - sidePad * 2.0 - rightLabelWidth, 40.0), MAX(height - bottomLabelHeight - topPad, 40.0)), 0, 0);
}

- (CGFloat)yForGain:(float)gain inRect:(NSRect)plot {
    const float clipped = std::clamp(gain, -20.0f, 20.0f);
    return plot.origin.y + ((CGFloat)(clipped + 20.0f) / 40.0) * plot.size.height;
}

- (float)gainForY:(CGFloat)y inRect:(NSRect)plot {
    const CGFloat position = std::clamp((y - plot.origin.y) / MAX(plot.size.height, 1.0), 0.0, 1.0);
    return (float)(position * 40.0 - 20.0);
}

- (CGFloat)xForBand:(NSUInteger)band count:(NSUInteger)count inRect:(NSRect)plot {
    if (count <= 1) return NSMidX(plot);
    return plot.origin.x + ((CGFloat)band / (CGFloat)(count - 1)) * plot.size.width;
}

- (NSUInteger)bandAtPoint:(NSPoint)point {
    const NSUInteger count = macgeq::active_band_count(self.settings.bandMode);
    const NSRect plot = [self plotRect];
    NSUInteger best = 0;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < count; ++i) {
        const CGFloat distance = fabs(point.x - [self xForBand:i count:count inRect:plot]);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

- (NSString *)labelForFrequency:(float)frequency {
    if (frequency >= 1000.0f) {
        const float khz = frequency / 1000.0f;
        if (fabsf(khz - roundf(khz)) < 0.05f) return [NSString stringWithFormat:@"%.0f kHz", khz];
        return [NSString stringWithFormat:@"%.1f kHz", khz];
    }
    return [NSString stringWithFormat:@"%.0f Hz", frequency];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.16 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    const NSRect plot = [self plotRect];
    const NSUInteger count = macgeq::active_band_count(self.settings.bandMode);
    const auto &freqs = macgeq::band_frequencies(self.settings.bandMode);
    const CGFloat bandSpacing = count > 1 ? plot.size.width / (CGFloat)(count - 1) : plot.size.width;
    const CGFloat tickHalfWidth = std::clamp(bandSpacing * 0.10, 2.0, 7.0);
    const CGFloat railWidth = bandSpacing < 18.0 ? 2.0 : 3.0;
    const CGFloat handleWidth = std::clamp(bandSpacing * 0.48, 12.0, 40.0);
    const CGFloat handleHeight = std::clamp(self.bounds.size.height * 0.018, 7.0, 12.0);
    const CGFloat bandFontSize = std::clamp(bandSpacing * 0.28, 7.0, 14.0);
    const BOOL showEveryOther = bandSpacing < 25.0;
    const BOOL showLabels = self.bounds.size.height >= 105.0 && bandSpacing >= 11.0;

    NSDictionary *freqAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:bandFontSize],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.86 alpha:1.0]
    };
    NSDictionary *dbAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:std::clamp(self.bounds.size.height * 0.035, 11.0, 20.0)],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.86 alpha:1.0]
    };

    [[NSColor colorWithCalibratedWhite:0.34 alpha:1.0] setStroke];
    for (NSUInteger i = 0; i < count; ++i) {
        const CGFloat x = [self xForBand:i count:count inRect:plot];
        NSBezierPath *rail = [NSBezierPath bezierPath];
        rail.lineWidth = railWidth;
        [rail moveToPoint:NSMakePoint(x, plot.origin.y)];
        [rail lineToPoint:NSMakePoint(x, NSMaxY(plot))];
        [rail stroke];

        for (NSUInteger tick = 0; tick <= 40; ++tick) {
            const CGFloat y = plot.origin.y + ((CGFloat)tick / 40.0) * plot.size.height;
            NSBezierPath *tickPath = [NSBezierPath bezierPath];
            tickPath.lineWidth = tick % 5 == 0 ? 2.0 : 1.0;
            [tickPath moveToPoint:NSMakePoint(x - tickHalfWidth, y)];
            [tickPath lineToPoint:NSMakePoint(x + tickHalfWidth, y)];
            [tickPath stroke];
        }

        const CGFloat handleY = [self yForGain:self.settings.gainsDb[i] inRect:plot];
        [[NSColor colorWithCalibratedRed:0.02 green:0.45 blue:1.0 alpha:1.0] setStroke];
        NSBezierPath *active = [NSBezierPath bezierPath];
        active.lineWidth = railWidth;
        [active moveToPoint:NSMakePoint(x, plot.origin.y)];
        [active lineToPoint:NSMakePoint(x, handleY)];
        [active stroke];

        [[NSColor colorWithCalibratedWhite:0.62 alpha:1.0] setFill];
        NSBezierPath *handle = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x - handleWidth / 2.0, handleY - handleHeight / 2.0, handleWidth, handleHeight) xRadius:handleHeight / 2.0 yRadius:handleHeight / 2.0];
        [handle fill];

        if (showLabels && (!showEveryOther || i % 2 == 0 || i == count - 1)) {
            NSString *label = [self labelForFrequency:freqs[i]];
            NSSize size = [label sizeWithAttributes:freqAttrs];
            [label drawAtPoint:NSMakePoint(x - size.width / 2.0, 5.0) withAttributes:freqAttrs];
        }

        [[NSColor colorWithCalibratedWhite:0.34 alpha:1.0] setStroke];
    }

    const CGFloat labelX = NSMaxX(plot) + (self.bounds.size.width < 360.0 ? 8.0 : 18.0);
    NSArray<NSString *> *labels = @[ @"+20dB", @"0dB", @"-20dB" ];
    const CGFloat ys[] = { [self yForGain:20.0f inRect:plot], [self yForGain:0.0f inRect:plot], [self yForGain:-20.0f inRect:plot] };
    for (NSUInteger i = 0; i < labels.count; ++i) {
        NSSize size = [labels[i] sizeWithAttributes:dbAttrs];
        [labels[i] drawAtPoint:NSMakePoint(labelX, ys[i] - size.height / 2.0) withAttributes:dbAttrs];
    }
}

- (void)updateBandAtPoint:(NSPoint)point {
    const NSUInteger band = _dragBand >= 0 ? (NSUInteger)_dragBand : [self bandAtPoint:point];
    macgeq::EqSettings settings = self.settings;
    settings.gainsDb[band] = std::clamp([self gainForY:point.y inRect:[self plotRect]], -20.0f, 20.0f);
    self.settings = settings;
    [self.delegate surfaceSettingsChanged:self];
}

- (void)mouseDown:(NSEvent *)event {
    const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _dragBand = (NSInteger)[self bandAtPoint:point];
    [self updateBandAtPoint:point];
}

- (void)mouseDragged:(NSEvent *)event {
    [self updateBandAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    _dragBand = -1;
}

@end

@implementation MacGEQViewController

- (instancetype)initCompact:(BOOL)compact {
    self = [super initWithNibName:nil bundle:nil];
    if (self) self.compactChrome = compact;
    return self;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 760, 360)];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0].CGColor;
    self.view = root;

    NSStackView *outer = [NSStackView stackViewWithViews:@[]];
    outer.orientation = NSUserInterfaceLayoutOrientationVertical;
    outer.alignment = NSLayoutAttributeWidth;
    outer.spacing = self.compactChrome ? 4.0 : 8.0;
    outer.edgeInsets = NSEdgeInsetsMake(8, 10, 8, 10);
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:outer];

    [NSLayoutConstraint activateConstraints:@[
        [outer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [outer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [outer.topAnchor constraintEqualToAnchor:root.topAnchor],
        [outer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];

    NSStackView *top = [NSStackView stackViewWithViews:@[]];
    top.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    top.alignment = NSLayoutAttributeCenterY;
    top.spacing = 8.0;
    [outer addArrangedSubview:top];

    self.enabledButton = [NSButton checkboxWithTitle:@"On" target:self action:@selector(onControlChanged:)];
    [top addArrangedSubview:self.enabledButton];

    self.bandModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.bandModePopup addItemWithTitle:@"31 bands"];
    [self.bandModePopup addItemWithTitle:@"18 bands"];
    self.bandModePopup.target = self;
    self.bandModePopup.action = @selector(onControlChanged:);
    [top addArrangedSubview:self.bandModePopup];

    NSTextField *preampLabel = [NSTextField labelWithString:@"Preamp"];
    [top addArrangedSubview:preampLabel];

    self.preampSlider = [NSSlider sliderWithValue:0.0 minValue:-24.0 maxValue:12.0 target:self action:@selector(onControlChanged:)];
    self.preampSlider.continuous = YES;
    [self.preampSlider.widthAnchor constraintGreaterThanOrEqualToConstant:90.0].active = YES;
    [top addArrangedSubview:self.preampSlider];

    self.preampValue = [NSTextField labelWithString:@"0.0 dB"];
    self.preampValue.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    [self.preampValue.widthAnchor constraintGreaterThanOrEqualToConstant:56.0].active = YES;
    [top addArrangedSubview:self.preampValue];

    NSTextField *title = [NSTextField labelWithString:@"Equalizer"];
    title.font = [NSFont boldSystemFontOfSize:18.0];
    title.alignment = NSTextAlignmentCenter;
    title.textColor = [NSColor colorWithCalibratedWhite:0.76 alpha:1.0];
    [outer addArrangedSubview:title];

    self.surface = [[MacGEQSurfaceView alloc] initWithFrame:NSMakeRect(0, 0, 760, 260)];
    self.surface.delegate = self;
    self.surface.translatesAutoresizingMaskIntoConstraints = NO;
    [self.surface setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [self.surface.heightAnchor constraintGreaterThanOrEqualToConstant:110.0].active = YES;
    [outer addArrangedSubview:self.surface];

    NSStackView *bottom = [NSStackView stackViewWithViews:@[]];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottom.alignment = NSLayoutAttributeCenterY;
    bottom.distribution = NSStackViewDistributionEqualCentering;
    bottom.spacing = 8.0;
    [outer addArrangedSubview:bottom];

    NSArray<NSArray *> *buttons = @[
        @[ @"Zero all", NSStringFromSelector(@selector(onZeroAll:)) ],
        @[ @"Auto level", NSStringFromSelector(@selector(onAutoLevel:)) ],
        @[ @"Load preset", NSStringFromSelector(@selector(onLoadPreset:)) ],
        @[ @"Save preset", NSStringFromSelector(@selector(onSavePreset:)) ],
    ];
    for (NSArray *buttonInfo in buttons) {
        NSButton *button = [NSButton buttonWithTitle:buttonInfo[0] target:self action:NSSelectorFromString(buttonInfo[1])];
        button.bezelStyle = NSBezelStyleRounded;
        [bottom addArrangedSubview:button];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadSettings];
}

- (void)loadSettings {
    macgeq::EqSettings settings = macgeq::get_settings();
    self.enabledButton.state = settings.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self.bandModePopup selectItemAtIndex:settings.bandMode == macgeq::BandMode::Visual ? 1 : 0];
    self.preampSlider.doubleValue = settings.preampDb;
    self.surface.settings = settings;
    [self refreshLabels];
}

- (void)saveSettings {
    macgeq::EqSettings settings = self.surface.settings;
    settings.enabled = self.enabledButton.state == NSControlStateValueOn;
    settings.bandMode = self.bandModePopup.indexOfSelectedItem == 1 ? macgeq::BandMode::Visual : macgeq::BandMode::ThirtyOne;
    settings.preampDb = self.preampSlider.floatValue;
    self.surface.settings = settings;
    macgeq::set_settings(settings);

    if (self.callback.is_valid()) {
        dsp_preset_impl preset;
        macgeq::make_preset(preset);
        self.callback->set_preset(preset);
    }
    [self refreshLabels];
}

- (void)refreshLabels {
    self.preampValue.stringValue = [NSString stringWithFormat:@"%.1f dB", self.preampSlider.doubleValue];
}

- (IBAction)onControlChanged:(id)sender {
    (void)sender;
    [self saveSettings];
}

- (void)surfaceSettingsChanged:(MacGEQSurfaceView *)surface {
    (void)surface;
    [self saveSettings];
}

- (IBAction)onZeroAll:(id)sender {
    (void)sender;
    macgeq::EqSettings settings = self.surface.settings;
    for (float &gain : settings.gainsDb) gain = 0.0f;
    settings.preampDb = 0.0f;
    self.preampSlider.floatValue = 0.0f;
    self.surface.settings = settings;
    [self saveSettings];
}

- (IBAction)onAutoLevel:(id)sender {
    (void)sender;
    macgeq::EqSettings settings = self.surface.settings;
    const size_t count = macgeq::active_band_count(settings.bandMode);
    float maxBoost = 0.0f;
    for (size_t i = 0; i < count; ++i) maxBoost = std::max(maxBoost, settings.gainsDb[i]);
    self.preampSlider.floatValue = -maxBoost;
    [self saveSettings];
}

- (IBAction)onLoadPreset:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"plist" ];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;

    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfURL:panel.URL];
    NSArray *gains = dict[@"gains"];
    if (![gains isKindOfClass:[NSArray class]]) return;

    macgeq::EqSettings settings = self.surface.settings;
    NSNumber *mode = dict[@"bandMode"];
    NSNumber *preamp = dict[@"preamp"];
    NSNumber *enabled = dict[@"enabled"];
    if ([mode respondsToSelector:@selector(integerValue)]) settings.bandMode = mode.integerValue == 1 ? macgeq::BandMode::Visual : macgeq::BandMode::ThirtyOne;
    if ([preamp respondsToSelector:@selector(floatValue)]) settings.preampDb = preamp.floatValue;
    if ([enabled respondsToSelector:@selector(boolValue)]) settings.enabled = enabled.boolValue;
    const NSUInteger limit = MIN((NSUInteger)macgeq::band_count, gains.count);
    for (NSUInteger i = 0; i < limit; ++i) settings.gainsDb[i] = [gains[i] floatValue];
    macgeq::set_settings(settings);
    [self loadSettings];
}

- (IBAction)onSavePreset:(id)sender {
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ @"plist" ];
    panel.nameFieldStringValue = @"Mac Graphic EQ.plist";
    if ([panel runModal] != NSModalResponseOK) return;

    macgeq::EqSettings settings = self.surface.settings;
    NSMutableArray *gains = [NSMutableArray arrayWithCapacity:macgeq::band_count];
    for (size_t i = 0; i < macgeq::band_count; ++i) [gains addObject:@(settings.gainsDb[i])];
    NSDictionary *dict = @{
        @"enabled": @(settings.enabled),
        @"bandMode": @(settings.bandMode == macgeq::BandMode::Visual ? 1 : 0),
        @"preamp": @(settings.preampDb),
        @"gains": gains
    };
    [dict writeToURL:panel.URL atomically:YES];
}

@end

service_ptr ConfigureMacGEQDSP(fb2k::hwnd_t parent, dsp_preset_edit_callback_v2::ptr callback) {
    (void)parent;
    MacGEQViewController *controller = [[MacGEQViewController alloc] initCompact:NO];
    controller.callback = callback;
    return fb2k::wrapNSObject(controller);
}

namespace {

class macgeq_ui_element : public ui_element_mac {
public:
    service_ptr instantiate(service_ptr arg) override {
        (void)arg;
        return fb2k::wrapNSObject([[MacGEQViewController alloc] initCompact:YES]);
    }

    bool match_name(const char * name) override {
        return pfc::stricmp_ascii(name, "macgeq") == 0
            || pfc::stricmp_ascii(name, "graphic-eq") == 0
            || pfc::stricmp_ascii(name, "Mac Graphic EQ") == 0;
    }

    fb2k::stringRef get_name() override {
        return fb2k::makeString("Mac Graphic EQ");
    }

    GUID get_guid() override {
        return macgeq::ui_guid;
    }
};

static service_factory_single_t<macgeq_ui_element> g_macgeq_ui_element_factory;

}
