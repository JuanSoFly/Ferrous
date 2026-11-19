import 'package:csslib/parser.dart' as cssparser;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/painting.dart';
import 'package:html/dom.dart' as dom;

class ResolvedCssRule {
  final double? textIndent;
  final String? textAlign;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? marginLeft;
  final double? marginRight;
  final double? marginTop;
  final double? marginBottom;
  final double? paddingLeft;
  final double? paddingRight;
  final double? paddingTop;
  final double? paddingBottom;
  final double? fontSizeScale;
  final double? marginLeftEm;
  final double? marginRightEm;
  final double? marginTopEm;
  final double? marginBottomEm;
  final double? paddingLeftEm;
  final double? paddingRightEm;
  final double? paddingTopEm;
  final double? paddingBottomEm;
  final bool hasExplicitTopMargin;
  final bool hasExplicitBottomMargin;
  final bool isMarginLeftPercentage;
  final bool isMarginRightPercentage;
  final double? marginLeftPercentage;
  final double? marginRightPercentage;
  final bool isPaddingLeftPercentage;
  final bool isPaddingRightPercentage;
  final double? paddingLeftPercentage;
  final double? paddingRightPercentage;

  const ResolvedCssRule({
    this.textIndent,
    this.textAlign,
    this.fontWeight,
    this.fontStyle,
    this.marginLeft,
    this.marginRight,
    this.marginTop,
    this.marginBottom,
    this.paddingLeft,
    this.paddingRight,
    this.paddingTop,
    this.paddingBottom,
    this.fontSizeScale,
    this.marginLeftEm,
    this.marginRightEm,
    this.marginTopEm,
    this.marginBottomEm,
    this.paddingLeftEm,
    this.paddingRightEm,
    this.paddingTopEm,
    this.paddingBottomEm,
    this.hasExplicitTopMargin = false,
    this.hasExplicitBottomMargin = false,
    this.isMarginLeftPercentage = false,
    this.isMarginRightPercentage = false,
    this.marginLeftPercentage,
    this.marginRightPercentage,
    this.isPaddingLeftPercentage = false,
    this.isPaddingRightPercentage = false,
    this.paddingLeftPercentage,
    this.paddingRightPercentage,
  });

  ResolvedCssRule mergeWith(ResolvedCssRule other) {
    return ResolvedCssRule(
      textIndent: other.textIndent ?? textIndent,
      textAlign: other.textAlign ?? textAlign,
      fontWeight: other.fontWeight ?? fontWeight,
      fontStyle: other.fontStyle ?? fontStyle,
      marginLeft: other.marginLeft ?? marginLeft,
      marginRight: other.marginRight ?? marginRight,
      marginTop: other.marginTop ?? marginTop,
      marginBottom: other.marginBottom ?? marginBottom,
      paddingLeft: other.paddingLeft ?? paddingLeft,
      paddingRight: other.paddingRight ?? paddingRight,
      paddingTop: other.paddingTop ?? paddingTop,
      paddingBottom: other.paddingBottom ?? paddingBottom,
      fontSizeScale: other.fontSizeScale ?? fontSizeScale,
      marginLeftEm: other.marginLeftEm ?? marginLeftEm,
      marginRightEm: other.marginRightEm ?? marginRightEm,
      marginTopEm: other.marginTopEm ?? marginTopEm,
      marginBottomEm: other.marginBottomEm ?? marginBottomEm,
      paddingLeftEm: other.paddingLeftEm ?? paddingLeftEm,
      paddingRightEm: other.paddingRightEm ?? paddingRightEm,
      paddingTopEm: other.paddingTopEm ?? paddingTopEm,
      paddingBottomEm: other.paddingBottomEm ?? paddingBottomEm,
      hasExplicitTopMargin: other.hasExplicitTopMargin || hasExplicitTopMargin,
      hasExplicitBottomMargin: other.hasExplicitBottomMargin || hasExplicitBottomMargin,
      isMarginLeftPercentage: other.isMarginLeftPercentage || isMarginLeftPercentage,
      isMarginRightPercentage: other.isMarginRightPercentage || isMarginRightPercentage,
      marginLeftPercentage: other.marginLeftPercentage ?? marginLeftPercentage,
      marginRightPercentage: other.marginRightPercentage ?? marginRightPercentage,
      isPaddingLeftPercentage: other.isPaddingLeftPercentage || isPaddingLeftPercentage,
      isPaddingRightPercentage: other.isPaddingRightPercentage || isPaddingRightPercentage,
      paddingLeftPercentage: other.paddingLeftPercentage ?? paddingLeftPercentage,
      paddingRightPercentage: other.paddingRightPercentage ?? paddingRightPercentage,
    );
  }
}

class CssRuleResolver {
  /// Parses raw CSS text into a lookup map of selector tokens to [ResolvedCssRule].
  static Map<String, ResolvedCssRule> parse(String cssContent, {double baseFontSize = 12.0}) {
    if (cssContent.trim().isEmpty) return const {};

    final rules = <String, ResolvedCssRule>{};
    try {
      final errors = <cssparser.Message>[];
      final styleSheet = cssparser.parse(cssContent, errors: errors);

      for (final topLevel in styleSheet.topLevels) {
        if (topLevel is! css.RuleSet) continue;

        final ruleSet = topLevel;
        double? textIndent;
        String? textAlign;
        FontWeight? fontWeight;
        FontStyle? fontStyle;
        double? marginLeft;
        double? marginRight;
        double? marginTop;
        double? marginBottom;
        double? paddingLeft;
        double? paddingRight;
        double? paddingTop;
        double? paddingBottom;
        double? fontSizeScale;
        double? marginLeftEm;
        double? marginRightEm;
        double? marginTopEm;
        double? marginBottomEm;
        double? paddingLeftEm;
        double? paddingRightEm;
        double? paddingTopEm;
        double? paddingBottomEm;
        bool hasExplicitTopMargin = false;
        bool hasExplicitBottomMargin = false;
        bool isMarginLeftPercentage = false;
        bool isMarginRightPercentage = false;
        double? marginLeftPercentage;
        double? marginRightPercentage;
        bool isPaddingLeftPercentage = false;
        bool isPaddingRightPercentage = false;
        double? paddingLeftPercentage;
        double? paddingRightPercentage;

        for (final declaration in ruleSet.declarationGroup.declarations) {
          if (declaration is! css.Declaration) continue;
          final property = declaration.property.trim().toLowerCase();
          final expr = declaration.expression;
          if (expr == null) continue;

          switch (property) {
            case 'text-align':
              final val = expr.span?.text.trim().toLowerCase();
              if (val != null && {'left', 'right', 'center', 'justify'}.contains(val)) {
                textAlign = val;
              }
              break;

            case 'text-indent':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) textIndent = val.pixels;
              break;

            case 'margin':
              final box = _resolveBoxTerms(expr, baseFontSize);
              if (box.top != null) {
                marginTop = box.top!.pixels;
                marginTopEm = box.top!.emValue;
                hasExplicitTopMargin = true;
              }
              if (box.bottom != null) {
                marginBottom = box.bottom!.pixels;
                marginBottomEm = box.bottom!.emValue;
                hasExplicitBottomMargin = true;
              }
              if (box.left != null) {
                if (box.left!.isPercentage) {
                  isMarginLeftPercentage = true;
                  marginLeftPercentage = box.left!.percentage;
                } else {
                  marginLeft = box.left!.pixels;
                  marginLeftEm = box.left!.emValue;
                }
              }
              if (box.right != null) {
                if (box.right!.isPercentage) {
                  isMarginRightPercentage = true;
                  marginRightPercentage = box.right!.percentage;
                } else {
                  marginRight = box.right!.pixels;
                  marginRightEm = box.right!.emValue;
                }
              }
              break;

            case 'padding':
              final box = _resolveBoxTerms(expr, baseFontSize);
              if (box.top != null) {
                paddingTop = box.top!.pixels;
                paddingTopEm = box.top!.emValue;
              }
              if (box.bottom != null) {
                paddingBottom = box.bottom!.pixels;
                paddingBottomEm = box.bottom!.emValue;
              }
              if (box.left != null) {
                if (box.left!.isPercentage) {
                  isPaddingLeftPercentage = true;
                  paddingLeftPercentage = box.left!.percentage;
                } else {
                  paddingLeft = box.left!.pixels;
                  paddingLeftEm = box.left!.emValue;
                }
              }
              if (box.right != null) {
                if (box.right!.isPercentage) {
                  isPaddingRightPercentage = true;
                  paddingRightPercentage = box.right!.percentage;
                } else {
                  paddingRight = box.right!.pixels;
                  paddingRightEm = box.right!.emValue;
                }
              }
              break;

            case 'margin-left':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) {
                if (val.isPercentage) {
                  isMarginLeftPercentage = true;
                  marginLeftPercentage = val.percentage;
                } else {
                  marginLeft = val.pixels;
                  marginLeftEm = val.emValue;
                }
              }
              break;

            case 'margin-right':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) {
                if (val.isPercentage) {
                  isMarginRightPercentage = true;
                  marginRightPercentage = val.percentage;
                } else {
                  marginRight = val.pixels;
                  marginRightEm = val.emValue;
                }
              }
              break;

            case 'margin-top':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null && !val.isPercentage) {
                marginTop = val.pixels;
                marginTopEm = val.emValue;
                hasExplicitTopMargin = true;
              }
              break;

            case 'margin-bottom':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null && !val.isPercentage) {
                marginBottom = val.pixels;
                marginBottomEm = val.emValue;
                hasExplicitBottomMargin = true;
              }
              break;

            case 'padding-left':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) {
                if (val.isPercentage) {
                  isPaddingLeftPercentage = true;
                  paddingLeftPercentage = val.percentage;
                } else {
                  paddingLeft = val.pixels;
                  paddingLeftEm = val.emValue;
                }
              }
              break;

            case 'padding-right':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) {
                if (val.isPercentage) {
                  isPaddingRightPercentage = true;
                  paddingRightPercentage = val.percentage;
                } else {
                  paddingRight = val.pixels;
                  paddingRightEm = val.emValue;
                }
              }
              break;

            case 'padding-top':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null && !val.isPercentage) {
                paddingTop = val.pixels;
                paddingTopEm = val.emValue;
              }
              break;

            case 'padding-bottom':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null && !val.isPercentage) {
                paddingBottom = val.pixels;
                paddingBottomEm = val.emValue;
              }
              break;

            case 'font-size':
              final scale = _resolveFontSizeScale(expr);
              if (scale != null) fontSizeScale = scale;
              break;

            case 'font-weight':
              final w = _resolveFontWeight(expr);
              if (w != null) fontWeight = w;
              break;

            case 'font-style':
              final s = _resolveFontStyle(expr);
              if (s != null) fontStyle = s;
              break;
          }
        }

        final parsedRule = ResolvedCssRule(
          textIndent: textIndent,
          textAlign: textAlign,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          marginLeft: marginLeft,
          marginRight: marginRight,
          marginTop: marginTop,
          marginBottom: marginBottom,
          paddingLeft: paddingLeft,
          paddingRight: paddingRight,
          paddingTop: paddingTop,
          paddingBottom: paddingBottom,
          fontSizeScale: fontSizeScale,
          marginLeftEm: marginLeftEm,
          marginRightEm: marginRightEm,
          marginTopEm: marginTopEm,
          marginBottomEm: marginBottomEm,
          paddingLeftEm: paddingLeftEm,
          paddingRightEm: paddingRightEm,
          paddingTopEm: paddingTopEm,
          paddingBottomEm: paddingBottomEm,
          hasExplicitTopMargin: hasExplicitTopMargin,
          hasExplicitBottomMargin: hasExplicitBottomMargin,
          isMarginLeftPercentage: isMarginLeftPercentage,
          isMarginRightPercentage: isMarginRightPercentage,
          marginLeftPercentage: marginLeftPercentage,
          marginRightPercentage: marginRightPercentage,
          isPaddingLeftPercentage: isPaddingLeftPercentage,
          isPaddingRightPercentage: isPaddingRightPercentage,
          paddingLeftPercentage: paddingLeftPercentage,
          paddingRightPercentage: paddingRightPercentage,
        );

        // Index each selector in the selector group
        final selectorGroup = ruleSet.selectorGroup;
        if (selectorGroup == null) continue;

        for (final selector in selectorGroup.selectors) {
          final rawSel = selector.span?.text.trim().toLowerCase();
          if (rawSel == null || rawSel.isEmpty) continue;

          // Strip pseudo-classes (:first-child, ::first-letter, etc.)
          final cleanSel = rawSel.replaceAll(RegExp(r':{1,2}[a-zA-Z0-9_-]+(\([^)]*\))?'), '').trim();
          if (cleanSel.isEmpty) continue;

          // Normalize child combinators 'a > b' to 'a b'
          final normalizedSel = cleanSel.replaceAll(RegExp(r'\s*>\s*'), ' ').trim();

          // 1. Index under full normalized selector
          _addOrMergeRule(rules, normalizedSel, parsedRule);

          // 2. Extract trailing class or tag token (e.g. 'div.cepiv' -> '.cepiv', '.atx1 .ctag1' -> '.ctag1')
          final tokens = normalizedSel.split(RegExp(r'\s+'));
          final lastToken = tokens.last;
          if (lastToken != normalizedSel) {
            _addOrMergeRule(rules, lastToken, parsedRule);
          }

          // If last token has a class (e.g. 'div.cepiv'), also index under '.cepiv'
          final classDotIdx = lastToken.indexOf('.');
          if (classDotIdx > 0) {
            final pureClass = lastToken.substring(classDotIdx);
            _addOrMergeRule(rules, pureClass, parsedRule);
          }
        }
      }
    } catch (_) {
      // Graceful fallback on malformed CSS
    }

    return rules;
  }

  static void _addOrMergeRule(Map<String, ResolvedCssRule> map, String key, ResolvedCssRule rule) {
    final existing = map[key];
    if (existing != null) {
      map[key] = existing.mergeWith(rule);
    } else {
      map[key] = rule;
    }
  }

  /// Resolves the single merged [ResolvedCssRule] for a given element.
  static ResolvedCssRule? resolveRule(dom.Element el, Map<String, ResolvedCssRule> rules) {
    if (rules.isEmpty) return _parseInlineStyleOnly(el);

    ResolvedCssRule? merged;

    // 1. Tag name rule (e.g. 'p', 'div', 'h1')
    final tag = el.localName?.toLowerCase();
    if (tag != null && rules.containsKey(tag)) {
      merged = rules[tag];
    }

    // 2. Class-based rules (e.g. '.cepiv', 'div.cepiv')
    final classAttr = el.attributes['class'];
    if (classAttr != null && classAttr.trim().isNotEmpty) {
      for (final cls in classAttr.trim().split(RegExp(r'\s+'))) {
        final dotCls = '.$cls'.toLowerCase();
        final tagCls = tag != null ? '$tag$dotCls' : dotCls;

        if (rules.containsKey(tagCls)) {
          merged = merged != null ? merged.mergeWith(rules[tagCls]!) : rules[tagCls];
        }
        if (rules.containsKey(dotCls)) {
          merged = merged != null ? merged.mergeWith(rules[dotCls]!) : rules[dotCls];
        }
      }
    }

    // 3. ID-based rule
    final id = el.attributes['id'];
    if (id != null && id.trim().isNotEmpty) {
      final hashId = '#${id.trim().toLowerCase()}';
      if (rules.containsKey(hashId)) {
        merged = merged != null ? merged.mergeWith(rules[hashId]!) : rules[hashId];
      }
    }

    // 4. Inline style overrides (highest specificity)
    final inlineRule = _parseInlineStyleOnly(el);
    if (inlineRule != null) {
      merged = merged != null ? merged.mergeWith(inlineRule) : inlineRule;
    }

    return merged;
  }

  /// Resolves total lateral insets (left + right margins + paddings) in pixels,
  /// walking up ancestors to `<body>` to sum nested container margins (e.g. .atx1 > .ctag1).
  static double resolveLateralInsets(
    dom.Element el,
    Map<String, ResolvedCssRule> rules,
    double fontSize,
    double availableWidth, {
    List<dom.Element>? ancestors,
  }) {
    double total = 0.0;
    final visited = <dom.Element>{};
    dom.Element? curr = el;
    while (curr != null) {
      final tag = curr.localName?.toLowerCase();
      if (tag == 'body' || tag == 'html') break;
      visited.add(curr);

      final rule = resolveRule(curr, rules);
      if (rule != null) {
        final fontScale = rule.fontSizeScale ?? 1.0;
        final effectiveFontSize = fontSize * fontScale;

        double left = rule.marginLeftEm != null
            ? rule.marginLeftEm! * effectiveFontSize
            : (rule.marginLeft ?? 0.0);
        if (rule.isMarginLeftPercentage && rule.marginLeftPercentage != null) {
          left = rule.marginLeftPercentage! * availableWidth;
        }

        double right = rule.marginRightEm != null
            ? rule.marginRightEm! * effectiveFontSize
            : (rule.marginRight ?? 0.0);
        if (rule.isMarginRightPercentage && rule.marginRightPercentage != null) {
          right = rule.marginRightPercentage! * availableWidth;
        }

        double padLeft = rule.paddingLeftEm != null
            ? rule.paddingLeftEm! * effectiveFontSize
            : (rule.paddingLeft ?? 0.0);
        if (rule.isPaddingLeftPercentage && rule.paddingLeftPercentage != null) {
          padLeft = rule.paddingLeftPercentage! * availableWidth;
        }

        double padRight = rule.paddingRightEm != null
            ? rule.paddingRightEm! * effectiveFontSize
            : (rule.paddingRight ?? 0.0);
        if (rule.isPaddingRightPercentage && rule.paddingRightPercentage != null) {
          padRight = rule.paddingRightPercentage! * availableWidth;
        }

        total += (left + right + padLeft + padRight);
      }
      curr = curr.parent;
    }

    if (ancestors != null) {
      for (final anc in ancestors.reversed) {
        if (visited.contains(anc)) continue;
        final tag = anc.localName?.toLowerCase();
        if (tag == 'body' || tag == 'html') continue;
        visited.add(anc);

        final rule = resolveRule(anc, rules);
        if (rule != null) {
          final fontScale = rule.fontSizeScale ?? 1.0;
          final effectiveFontSize = fontSize * fontScale;

          double left = rule.marginLeftEm != null
              ? rule.marginLeftEm! * effectiveFontSize
              : (rule.marginLeft ?? 0.0);
          if (rule.isMarginLeftPercentage && rule.marginLeftPercentage != null) {
            left = rule.marginLeftPercentage! * availableWidth;
          }

          double right = rule.marginRightEm != null
              ? rule.marginRightEm! * effectiveFontSize
              : (rule.marginRight ?? 0.0);
          if (rule.isMarginRightPercentage && rule.marginRightPercentage != null) {
            right = rule.marginRightPercentage! * availableWidth;
          }

          double padLeft = rule.paddingLeftEm != null
              ? rule.paddingLeftEm! * effectiveFontSize
              : (rule.paddingLeft ?? 0.0);
          if (rule.isPaddingLeftPercentage && rule.paddingLeftPercentage != null) {
            padLeft = rule.paddingLeftPercentage! * availableWidth;
          }

          double padRight = rule.paddingRightEm != null
              ? rule.paddingRightEm! * effectiveFontSize
              : (rule.paddingRight ?? 0.0);
          if (rule.isPaddingRightPercentage && rule.paddingRightPercentage != null) {
            padRight = rule.paddingRightPercentage! * availableWidth;
          }

          total += (left + right + padLeft + padRight);
        }
      }
    }

    return total;
  }

  /// Resolves vertical margins (top and bottom) for a block element.
  static ({double top, double bottom, bool hasExplicitTop, bool hasExplicitBottom}) resolveVerticalMargins(
    dom.Element el,
    Map<String, ResolvedCssRule> rules, {
    double baseFontSize = 12.0,
  }) {
    final rule = resolveRule(el, rules);
    if (rule == null) {
      return (top: 0.0, bottom: 0.0, hasExplicitTop: false, hasExplicitBottom: false);
    }
    final fontScale = rule.fontSizeScale ?? 1.0;
    final effectiveFontSize = baseFontSize * fontScale;

    double top = rule.marginTopEm != null
        ? rule.marginTopEm! * effectiveFontSize
        : (rule.marginTop ?? 0.0);
    double bottom = rule.marginBottomEm != null
        ? rule.marginBottomEm! * effectiveFontSize
        : (rule.marginBottom ?? 0.0);

    return (
      top: top,
      bottom: bottom,
      hasExplicitTop: rule.hasExplicitTopMargin,
      hasExplicitBottom: rule.hasExplicitBottomMargin,
    );
  }

  static ResolvedCssRule? _parseInlineStyleOnly(dom.Element el) {
    final style = el.attributes['style'];
    if (style == null || style.trim().isEmpty) return null;

    final lower = style.toLowerCase();
    String? textAlign;
    FontWeight? fontWeight;
    FontStyle? fontStyle;
    double? marginLeft;
    double? marginRight;
    double? marginLeftEm;
    double? marginRightEm;
    double? marginTop;
    double? marginBottom;
    double? marginTopEm;
    double? marginBottomEm;
    double? paddingTop;
    double? paddingBottom;
    double? paddingLeft;
    double? paddingRight;
    double? textIndent;
    bool hasExplicitTopMargin = false;
    bool hasExplicitBottomMargin = false;

    if (lower.contains('text-align: center') || lower.contains('text-align:center')) {
      textAlign = 'center';
    } else if (lower.contains('text-align: right') || lower.contains('text-align:right')) {
      textAlign = 'right';
    } else if (lower.contains('text-align: justify') || lower.contains('text-align:justify')) {
      textAlign = 'justify';
    } else if (lower.contains('text-align: left') || lower.contains('text-align:left')) {
      textAlign = 'left';
    }

    if (lower.contains('text-indent: 0') || lower.contains('text-indent:0')) {
      textIndent = 0.0;
    }

    // Check margin-top
    final mtMatch = RegExp(r'margin-top\s*:\s*([\d.]+)(em|px|rem|pt|%)?').firstMatch(lower);
    if (mtMatch != null) {
      final num = double.tryParse(mtMatch.group(1)!);
      final unit = mtMatch.group(2) ?? 'px';
      if (num != null) {
        hasExplicitTopMargin = true;
        if (unit == 'em' || unit == 'rem') {
          marginTopEm = num;
          marginTop = num * 12.0;
        } else {
          marginTop = num;
        }
      }
    }

    // Check margin-bottom
    final mbMatch = RegExp(r'margin-bottom\s*:\s*([\d.]+)(em|px|rem|pt|%)?').firstMatch(lower);
    if (mbMatch != null) {
      final num = double.tryParse(mbMatch.group(1)!);
      final unit = mbMatch.group(2) ?? 'px';
      if (num != null) {
        hasExplicitBottomMargin = true;
        if (unit == 'em' || unit == 'rem') {
          marginBottomEm = num;
          marginBottom = num * 12.0;
        } else {
          marginBottom = num;
        }
      }
    }

    final mlMatch = RegExp(r'margin-left\s*:\s*([\d.]+)(em|px|rem|%)').firstMatch(lower);
    if (mlMatch != null) {
      final num = double.tryParse(mlMatch.group(1)!);
      final unit = mlMatch.group(2)!;
      if (num != null) {
        if (unit == 'em' || unit == 'rem') {
          marginLeft = num * 12.0;
          marginLeftEm = num;
        } else if (unit == 'px') {
          marginLeft = num;
        }
      }
    }

    final mrMatch = RegExp(r'margin-right\s*:\s*([\d.]+)(em|px|rem|%)').firstMatch(lower);
    if (mrMatch != null) {
      final num = double.tryParse(mrMatch.group(1)!);
      final unit = mrMatch.group(2)!;
      if (num != null) {
        if (unit == 'em' || unit == 'rem') {
          marginRight = num * 12.0;
          marginRightEm = num;
        } else if (unit == 'px') {
          marginRight = num;
        }
      }
    }

    if (lower.contains('font-weight: bold') ||
        lower.contains('font-weight:bold') ||
        lower.contains('font-weight: 700') ||
        lower.contains('font-weight:700')) {
      fontWeight = FontWeight.bold;
    } else if (lower.contains('font-weight: normal') ||
        lower.contains('font-weight:normal') ||
        lower.contains('font-weight: 400') ||
        lower.contains('font-weight:400')) {
      fontWeight = FontWeight.normal;
    }

    if (lower.contains('font-style: italic') ||
        lower.contains('font-style:italic') ||
        lower.contains('font-style: oblique') ||
        lower.contains('font-style:oblique')) {
      fontStyle = FontStyle.italic;
    } else if (lower.contains('font-style: normal') ||
        lower.contains('font-style:normal')) {
      fontStyle = FontStyle.normal;
    }

    return ResolvedCssRule(
      textAlign: textAlign,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      marginLeft: marginLeft,
      marginRight: marginRight,
      marginTop: marginTop,
      marginBottom: marginBottom,
      marginTopEm: marginTopEm,
      marginBottomEm: marginBottomEm,
      paddingLeft: paddingLeft,
      paddingRight: paddingRight,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
      marginLeftEm: marginLeftEm,
      marginRightEm: marginRightEm,
      textIndent: textIndent,
      hasExplicitTopMargin: hasExplicitTopMargin,
      hasExplicitBottomMargin: hasExplicitBottomMargin,
    );
  }

  static ({
    ({double pixels, bool isPercentage, double percentage, double? emValue})? top,
    ({double pixels, bool isPercentage, double percentage, double? emValue})? right,
    ({double pixels, bool isPercentage, double percentage, double? emValue})? bottom,
    ({double pixels, bool isPercentage, double percentage, double? emValue})? left,
  }) _resolveBoxTerms(css.Expression expr, double baseFontSize) {
    List<css.Expression> terms = [];
    if (expr is css.Expressions) {
      terms = expr.expressions;
    } else {
      terms = [expr];
    }

    final resolved = <({double pixels, bool isPercentage, double percentage, double? emValue})>[];
    for (final t in terms) {
      final r = _resolveLengthOrPercent(t, baseFontSize);
      if (r != null) resolved.add(r);
    }

    if (resolved.isEmpty) {
      return (top: null, right: null, bottom: null, left: null);
    }

    if (resolved.length == 1) {
      final v = resolved[0];
      return (top: v, right: v, bottom: v, left: v);
    } else if (resolved.length == 2) {
      final tb = resolved[0];
      final lr = resolved[1];
      return (top: tb, right: lr, bottom: tb, left: lr);
    } else if (resolved.length == 3) {
      final t = resolved[0];
      final lr = resolved[1];
      final b = resolved[2];
      return (top: t, right: lr, bottom: b, left: lr);
    } else {
      final t = resolved[0];
      final r = resolved[1];
      final b = resolved[2];
      final l = resolved[3];
      return (top: t, right: r, bottom: b, left: l);
    }
  }

  static ({double pixels, bool isPercentage, double percentage, double? emValue})? _resolveLengthOrPercent(
    css.Expression expr,
    double baseFontSize,
  ) {
    css.Expression target = expr;
    if (expr is css.Expressions && expr.expressions.isNotEmpty) {
      target = expr.expressions.first;
    }

    if (target is css.PercentageTerm) {
      final v = target.value;
      if (v is num) {
        return (pixels: 0.0, isPercentage: true, percentage: v.toDouble() / 100.0, emValue: null);
      }
    }

    if (target is css.EmTerm || target is css.RemTerm) {
      final v = (target as dynamic).value;
      if (v is num) {
        final em = v.toDouble();
        return (pixels: em * baseFontSize, isPercentage: false, percentage: 0.0, emValue: em);
      }
    }

    final text = target.span?.text.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;

    final match = RegExp(r'^([+-]?[\d.]+)(em|rem|px|pt|%)?$').firstMatch(text);
    if (match == null) return null;

    final val = double.tryParse(match.group(1)!);
    if (val == null) return null;

    final unit = match.group(2) ?? 'px';
    if (unit == '%') {
      return (pixels: 0.0, isPercentage: true, percentage: val / 100.0, emValue: null);
    }

    double px = val;
    double? emValue;
    switch (unit) {
      case 'em':
      case 'rem':
        emValue = val;
        px = val * baseFontSize;
        break;
      case 'pt':
        px = val * 1.333;
        break;
      case 'px':
      default:
        px = val;
        break;
    }

    return (pixels: px, isPercentage: false, percentage: 0.0, emValue: emValue);
  }

  /// Rewrites CSS font-size keywords and fixed px/pt declarations into clamped relative em multipliers.
  static String normalizeCssFontSizes(String declarations) {
    if (!declarations.toLowerCase().contains('font-size')) return declarations;

    return declarations.replaceAllMapped(
      RegExp(r'font-size\s*:\s*([^;!}]+)', caseSensitive: false),
      (match) {
        final rawVal = match.group(1)!.trim().toLowerCase();
        final normalized = _convertFontSizeToEm(rawVal);
        return normalized != null ? 'font-size: $normalized' : match.group(0)!;
      },
    );
  }

  static String? _convertFontSizeToEm(String rawVal) {
    switch (rawVal) {
      case 'xx-small':
        return '0.70em';
      case 'x-small':
        return '0.82em';
      case 'small':
        return '0.90em';
      case 'medium':
        return '1.0em';
      case 'large':
        return '1.20em';
      case 'x-large':
        return '1.45em';
      case 'xx-large':
        return '1.75em';
    }

    final match = RegExp(r'^([+-]?[\d.]+)(px|pt|em|rem|%)?$').firstMatch(rawVal);
    if (match != null) {
      final numVal = double.tryParse(match.group(1)!);
      final unit = match.group(2) ?? 'px';
      if (numVal != null) {
        if (unit == 'px') {
          final em = (numVal / 16.0).clamp(0.70, 2.0);
          return '${em.toStringAsFixed(3)}em';
        } else if (unit == 'pt') {
          final em = (numVal * 1.333 / 16.0).clamp(0.70, 2.0);
          return '${em.toStringAsFixed(3)}em';
        } else if (unit == 'em' || unit == 'rem') {
          final em = numVal.clamp(0.70, 2.0);
          return '${em.toStringAsFixed(3)}em';
        } else if (unit == '%') {
          final em = (numVal / 100.0).clamp(0.70, 2.0);
          return '${em.toStringAsFixed(3)}em';
        }
      }
    }
    return null;
  }

  static double? _resolveFontSizeScale(css.Expression expr) {
    css.Expression target = expr;
    if (expr is css.Expressions && expr.expressions.isNotEmpty) {
      target = expr.expressions.first;
    }

    if (target is css.EmTerm) {
      final v = target.value;
      if (v is num) return v.toDouble().clamp(0.70, 2.0);
    }
    if (target is css.RemTerm) {
      final v = target.value;
      if (v is num) return v.toDouble().clamp(0.70, 2.0);
    }
    if (target is css.PercentageTerm) {
      final v = target.value;
      if (v is num) return (v.toDouble() / 100.0).clamp(0.70, 2.0);
    }
    if (target is css.LengthTerm) {
      final v = target.value;
      if (v is num) {
        final spanText = target.span?.text.trim().toLowerCase() ?? '';
        if (spanText.endsWith('pt')) {
          return (v.toDouble() * 1.333 / 16.0).clamp(0.70, 2.0);
        } else {
          return (v.toDouble() / 16.0).clamp(0.70, 2.0);
        }
      }
    }

    final text = target.span?.text.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;

    switch (text) {
      case 'xx-small':
        return 0.70;
      case 'x-small':
        return 0.82;
      case 'small':
        return 0.90;
      case 'medium':
        return 1.0;
      case 'large':
        return 1.20;
      case 'x-large':
        return 1.45;
      case 'xx-large':
        return 1.75;
    }

    final match = RegExp(r'^([+-]?[\d.]+)(em|rem|%|px|pt)?$').firstMatch(text);
    if (match != null) {
      final val = double.tryParse(match.group(1)!);
      if (val != null) {
        final unit = match.group(2);
        if (unit == '%') return (val / 100.0).clamp(0.70, 2.0);
        if (unit == 'em' || unit == 'rem') return val.clamp(0.70, 2.0);
        if (unit == 'px') return (val / 16.0).clamp(0.70, 2.0);
        if (unit == 'pt') return (val * 1.333 / 16.0).clamp(0.70, 2.0);
        if (val >= 0.5 && val <= 3.0) return val.clamp(0.70, 2.0);
      }
    }

    return null;
  }

  static FontWeight? _resolveFontWeight(css.Expression expr) {
    css.Expression target = expr;
    if (expr is css.Expressions && expr.expressions.isNotEmpty) {
      target = expr.expressions.first;
    }
    final text = target.span?.text.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    if (text == 'bold' || text == 'bolder' || text == '700' || text == '800' || text == '900') {
      return FontWeight.bold;
    }
    if (text == 'normal' || text == 'lighter' || text == '400' || text == '300' || text == '200' || text == '100') {
      return FontWeight.normal;
    }
    return null;
  }

  static FontStyle? _resolveFontStyle(css.Expression expr) {
    css.Expression target = expr;
    if (expr is css.Expressions && expr.expressions.isNotEmpty) {
      target = expr.expressions.first;
    }
    final text = target.span?.text.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    if (text == 'italic' || text == 'oblique') {
      return FontStyle.italic;
    }
    if (text == 'normal') {
      return FontStyle.normal;
    }
    return null;
  }
}
