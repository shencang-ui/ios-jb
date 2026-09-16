#import "CLSliderCell.h"
#import "../Shared/CLSharedSupport.h"

// 自定义滑条 cell：
//   第 1 行  标题
//   第 2 行  说明文字 + 取值范围（由 specifier 的 "desc" 属性提供，已含换行）
//   第 3 行  滑条（左侧）+ 数值（右侧固定宽，点击弹窗直接输入）

@interface CLSliderCell ()
- (void)cl_sliderChanged:(UISlider *)slider;
- (void)cl_sliderFinished:(UISlider *)slider;
- (void)cl_editValue;
- (NSString *)cl_stringForValue:(double)value;
@end

@implementation CLSliderCell {
    PSSpecifier *_spec;
    NSString *_key;
    CGFloat _min, _max, _def;
    NSInteger _decimals;
    UILabel *_titleLabel;
    UILabel *_descLabel;
    UILabel *_rangeLabel;
    UILabel *_valueLabel;
    UISlider *_slider;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        _spec = specifier;
        [self cl_setup];
    }
    return self;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    return [self initWithStyle:UITableViewCellStyleDefault
               reuseIdentifier:nil
                     specifier:specifier];
}

+ (CGFloat)preferredHeightForSpecifier:(PSSpecifier *)specifier {
    return 100.0;
}

- (void)cl_setup {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    // 关键：基类 PSTableCell 会按 specifier.cellType（PSSliderCell）自建一套
    // 滑条/文本 UI，其 get/set 均为空（拖动无效）且与自绘控件重叠——全部移除
    for (UIView *v in [NSArray arrayWithArray:self.contentView.subviews]) [v removeFromSuperview];
    for (UIView *v in [NSArray arrayWithArray:self.subviews]) {
        if (v != self.contentView) [v removeFromSuperview];
    }
    for (UIGestureRecognizer *g in [NSArray arrayWithArray:self.gestureRecognizers]) {
        [self removeGestureRecognizer:g];
    }
    // 隐藏基类自带的标准 label
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;
    self.detailTextLabel.text = nil;
    self.detailTextLabel.hidden = YES;
    self.imageView.hidden = YES;

    _key    = [_spec propertyForKey:@"key"];
    _min    = [[_spec propertyForKey:@"min"] doubleValue];
    _max    = [[_spec propertyForKey:@"max"] doubleValue];
    _def    = [[_spec propertyForKey:@"default"] doubleValue];
    _decimals = ((_max - _min) <= 4.0) ? 2 : 0;

    _titleLabel = [UILabel new];
    _titleLabel.text = _spec.name;
    _titleLabel.font = [UIFont systemFontOfSize:16];
    _titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:_titleLabel];

    _descLabel = [UILabel new];
    _descLabel.text = [_spec propertyForKey:@"desc"] ?: @"";
    _descLabel.font = [UIFont systemFontOfSize:12];
    _descLabel.textColor = [UIColor secondaryLabelColor];
    _descLabel.numberOfLines = 1;
    [self.contentView addSubview:_descLabel];

    _rangeLabel = [UILabel new];
    _rangeLabel.text = [_spec propertyForKey:@"rangeText"] ?: @"";
    _rangeLabel.font = [UIFont systemFontOfSize:11];
    _rangeLabel.textColor = [UIColor tertiaryLabelColor];
    _rangeLabel.numberOfLines = 1;
    [self.contentView addSubview:_rangeLabel];

    _valueLabel = [UILabel new];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    _valueLabel.textColor = [UIColor labelColor];
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _valueLabel.userInteractionEnabled = YES;
    [self.contentView addSubview:_valueLabel];
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cl_editValue)];
    [_valueLabel addGestureRecognizer:tap];

    _slider = [UISlider new];
    double current = CL_prefFloat(_key, _def);
    current = MIN(MAX(current, _min), _max);
    _slider.minimumValue = _min;
    _slider.maximumValue = _max;
    _slider.value = (float)current;
    [_slider addTarget:self
                action:@selector(cl_sliderChanged:)
      forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self
                action:@selector(cl_sliderFinished:)
      forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside)];
    [self.contentView addSubview:_slider];

    [self cl_updateValueLabel];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat rightZone = 88; // 数值列固定宽度（留出空间）
    _titleLabel.frame = CGRectMake(16, 7, w - rightZone - 24, 18);
    _descLabel.frame  = CGRectMake(16, 27, w - rightZone - 24, 16);
    _rangeLabel.frame = CGRectMake(16, 44, w - rightZone - 24, 15);
    _slider.frame     = CGRectMake(16, 66, w - rightZone - 16, 26);
    _valueLabel.frame = CGRectMake(w - rightZone - 2, 64, rightZone, 28);
}

- (NSString *)cl_stringForValue:(double)value {
    return _decimals == 2
        ? [NSString stringWithFormat:@"%.2f", value]
        : [NSString stringWithFormat:@"%.0f", value];
}

- (void)cl_updateValueLabel {
    _valueLabel.text = [self cl_stringForValue:_slider.value];
}

- (void)cl_sliderChanged:(UISlider *)slider {
    [self cl_updateValueLabel];
}

- (void)cl_sliderFinished:(UISlider *)slider {
    if (_key.length) CLSetPreferenceValue(_key, @((double)slider.value));
}

// 点击数值 → 弹窗直接输入
- (void)cl_editValue {
    NSString *rangeFmt  = [_spec propertyForKey:@"rangeFmt"] ?: @"Range: %@";
    NSString *cancelTtl = [_spec propertyForKey:@"cancelTitle"] ?: @"Cancel";
    NSString *saveTtl   = [_spec propertyForKey:@"saveTitle"] ?: @"Save";

    NSString *rangeStr = [[self cl_stringForValue:_min]
        stringByAppendingFormat:@" ~ %@", [self cl_stringForValue:_max]];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:_spec.name
                                            message:[NSString stringWithFormat:rangeFmt, rangeStr]
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) wself = self;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [sself cl_stringForValue:sself->_slider.value];
        textField.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:cancelTtl
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:saveTtl
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        double v = [alert.textFields.firstObject.text doubleValue];
        v = MIN(MAX(v, sself->_min), sself->_max);
        sself->_slider.value = (float)v;
        [sself cl_updateValueLabel];
        if (sself->_key.length) CLSetPreferenceValue(sself->_key, @(v));
    }]];
    UIViewController *vc = (UIViewController *)[_spec target];
    if (!vc) return;
    [vc presentViewController:alert animated:YES completion:nil];
}

@end
