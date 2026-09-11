#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import "../Shared/CLSharedSupport.h"

#define CLLocalized(key, fallback) \
    ([self.localizations objectForKey:key] ?: fallback)

@interface CLRootListController : PSListController
@property (nonatomic, readonly) NSDictionary *localizations;
- (PSSpecifier *)sliderSpecWithTitle:(NSString *)title key:(NSString *)key
                                  min:(CGFloat)min max:(CGFloat)max
                              default:(CGFloat)def;
- (void)handleRespringPressed;
@end

@implementation CLRootListController

- (NSDictionary *)localizations {
    static NSDictionary *localizations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        // Chinese system → always load zh-Hans.lproj directly by path; other languages fall back to the bundle default
        BOOL isChinese = NO;
        for (NSString *language in NSLocale.preferredLanguages) {
            if ([language hasPrefix:@"zh"]) { isChinese = YES; break; }
        }
        if (!isChinese) {
            NSString *code = NSLocale.currentLocale.languageCode ?: @"";
            isChinese = [code isEqualToString:@"zh"];
        }
        NSString *path = nil;
        if (isChinese) {
            NSString *lproj = [bundle pathForResource:@"zh-Hans.lproj" ofType:nil];
            if (lproj) path = [lproj stringByAppendingPathComponent:@"Localizable.strings"];
            if (!path) path = [bundle pathForResource:@"Localizable" ofType:@"strings"
                                         inDirectory:nil forLocalization:@"zh-Hans"];
        }
        if (!path) path = [bundle pathForResource:@"Localizable" ofType:@"strings"];
        NSDictionary *dict = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        if (!dict.count && isChinese) {
            // last resort: try the resource bundle by name
            NSBundle *resBundle = [NSBundle bundleWithPath:[bundle bundlePath]];
            NSString *lproj = [resBundle pathForResource:@"zh-Hans.lproj" ofType:nil];
            NSString *p2 = lproj ? [lproj stringByAppendingPathComponent:@"Localizable.strings"] : nil;
            dict = p2 ? [NSDictionary dictionaryWithContentsOfFile:p2] : @{};
        }
        localizations = dict ?: @{};
    });
    return localizations;
}

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self buildSpecifiers];
    return _specifiers;
}

- (NSMutableArray<PSSpecifier *> *)buildSpecifiers {
    NSMutableArray<PSSpecifier *> *specs = [NSMutableArray array];

    [specs addObject:[PSSpecifier groupSpecifierWithName:nil]];

    PSSpecifier *enabled = [self toggleSpecWithTitle:
        CLLocalized(@"prefs.clock.enabled", @"iOS 26 Clock")
        key:@"Clock.Enabled"];
    [specs addObject:enabled];

    [specs addObject:[PSSpecifier groupSpecifierWithName:
        CLLocalized(@"prefs.clock.font_section", @"Variable Font")]];

    PSSpecifier *fontEnabled = [self toggleSpecWithTitle:
        CLLocalized(@"prefs.clock.variable_font", @"Variable Font")
        key:@"Clock.VariableFont.Enabled"];
    [specs addObject:fontEnabled];

    [specs addObject:[self sliderSpecWithTitle:
        CLLocalized(@"prefs.clock.font_size", @"Font Size")
        key:@"Clock.VariableFont.SizeScale" min:0.8 max:2.0 default:1.4]];
    [specs addObject:[self sliderSpecWithTitle:
        CLLocalized(@"prefs.clock.font_weight", @"Weight")
        key:@"Clock.VariableFont.Weight" min:1.0 max:1000.0 default:750.0]];
    [specs addObject:[self sliderSpecWithTitle:
        CLLocalized(@"prefs.clock.font_width", @"Width")
        key:@"Clock.VariableFont.Width" min:60.0 max:100.0 default:100.0]];
    [specs addObject:[self sliderSpecWithTitle:
        CLLocalized(@"prefs.clock.font_height", @"Height")
        key:@"Clock.VariableFont.Height" min:100.0 max:500.0 default:350.0]];
    [specs addObject:[self sliderSpecWithTitle:
        CLLocalized(@"prefs.clock.font_softness", @"Softness")
        key:@"Clock.VariableFont.Softness" min:0.0 max:100.0 default:56.0]];

    [specs addObject:[PSSpecifier groupSpecifierWithName:
        CLLocalized(@"prefs.clock.date_section", @"Date Format")]];

    PSSpecifier *dateEnabled = [self toggleSpecWithTitle:
        CLLocalized(@"prefs.clock.date_enabled", @"Custom Date Format")
        key:@"Lockscreen.Clock.DateFormat.Enabled"];
    [specs addObject:dateEnabled];

    PSSpecifier *dateFormat = [PSSpecifier preferenceSpecifierNamed:@"Lockscreen.Clock.DateFormat.Format"
                                                             target:self
                                                                 set:@selector(setDateFormat:)
                                                                 get:@selector(dateFormat)
                                                             detail:nil
                                                               cell:PSTitleValueCell
                                                               edit:nil];
    dateFormat.name = CLLocalized(@"prefs.clock.date_format", @"Date Format");
    dateFormat.buttonAction = @selector(handleDateFormatPressed);
    NSString *currentFormat = CL_prefString(@"Lockscreen.Clock.DateFormat.Format", @"");
    [dateFormat setProperty:currentFormat ?: @"" forKey:@"detailText"];
    [specs addObject:dateFormat];

    [specs addObject:[PSSpecifier groupSpecifierWithName:nil]];

    PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Respring"
                                                            target:self
                                                                set:nil
                                                                get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    respring.name = CLLocalized(@"prefs.clock.respring", @"Respring");
    respring.buttonAction = @selector(handleRespringPressed);
    [specs addObject:respring];

    return specs;
}

- (PSSpecifier *)toggleSpecWithTitle:(NSString *)title key:(NSString *)key {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:key
                                                        target:self
                                                            set:@selector(setPrefValue:specifier:)
                                                            get:@selector(readPrefValue:)
                                                        detail:nil
                                                          cell:PSSwitchCell
                                                          edit:nil];
    spec.name = title;
    return spec;
}

- (PSSpecifier *)sliderSpecWithTitle:(NSString *)title key:(NSString *)key
                                  min:(CGFloat)min max:(CGFloat)max
                              default:(CGFloat)def {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:key
                                                        target:self
                                                            set:@selector(setPrefValue:specifier:)
                                                            get:@selector(readPrefValue:)
                                                        detail:nil
                                                          cell:PSSliderCell
                                                          edit:nil];
    spec.name = title;
    [spec setProperty:@(min) forKey:@"min"];
    [spec setProperty:@(max) forKey:@"max"];
    [spec setProperty:@(def) forKey:@"default"];
    return spec;
}

#pragma mark - preference read/write (domain + live reload)

- (id)readPrefValue:(PSSpecifier *)spec {
    NSString *key = spec.identifier;
    if (!key) return [spec propertyForKey:@"default"];
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                          (__bridge CFStringRef)CLPrefsDomain));
    if (value) return value;
    return [spec propertyForKey:@"default"];
}

- (void)setPrefValue:(id)value specifier:(PSSpecifier *)spec {
    NSString *key = spec.identifier;
    if (!key) return;
    CLSetPreferenceValue(key, value);
}

- (id)dateFormat {
    return CL_prefString(@"Lockscreen.Clock.DateFormat.Format", @"");
}

- (void)setDateFormat:(NSString *)format {
    CLSetPreferenceValue(@"Lockscreen.Clock.DateFormat.Format",
                         format.length ? format : nil);
    PSSpecifier *spec = [self specifierForID:@"Lockscreen.Clock.DateFormat.Format"];
    if (spec) {
        [spec setProperty:format ?: @"" forKey:@"detailText"];
        [self reloadSpecifiers];
    }
}

#pragma mark actions

- (void)handleDateFormatPressed {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:
            CLLocalized(@"prefs.clock.date_format", @"Date Format")
            message:CLLocalized(@"prefs.clock.date_format_hint", @"Example: EEE MMM d")
            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = CL_prefString(@"Lockscreen.Clock.DateFormat.Format", @"");
        textField.placeholder = @"EEE MMM d";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:
        CLLocalized(@"prefs.button.cancel", @"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:
        CLLocalized(@"prefs.button.save", @"Save")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *format = alert.textFields.firstObject.text ?: @"";
            CLSetPreferenceValue(@"Lockscreen.Clock.DateFormat.Format",
                                 format.length ? format : nil);
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleRespringPressed {
    CLPostRespringNotification();
}

@end
