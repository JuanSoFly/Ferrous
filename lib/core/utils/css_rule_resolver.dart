import 'package:csslib/parser.dart' as cssparser;
import 'package:csslib/visitor.dart' as css;
import 'package:html/dom.dart' as dom;

class ResolvedCssRule {
  final double? textIndent;
  final String? textAlign;
  final double? marginLeft;
  final double? marginRight;
  final double? marginTop;
  final double? marginBottom;
  final double? paddingLeft;
  final double? paddingRight;
  final double? fontSizeScale;
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
    this.marginLeft,
    this.marginRight,
    this.marginTop,
    this.marginBottom,
    this.paddingLeft,
    this.paddingRight,
    this.fontSizeScale,
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
      marginLeft: other.marginLeft ?? marginLeft,
      marginRight: other.marginRight ?? marginRight,
      marginTop: other.marginTop ?? marginTop,
      marginBottom: other.marginBottom ?? marginBottom,
      paddingLeft: other.paddingLeft ?? paddingLeft,
      paddingRight: other.paddingRight ?? paddingRight,
      fontSizeScale: other.fontSizeScale ?? fontSizeScale,
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
        double? marginLeft;
        double? marginRight;
        double? marginTop;
        double? marginBottom;
        double? paddingLeft;
        double? paddingRight;
        double? fontSizeScale;
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

            case 'margin-left':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) {
                if (val.isPercentage) {
                  isMarginLeftPercentage = true;
                  marginLeftPercentage = val.percentage;
                } else {
                  marginLeft = val.pixels;
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
                }
              }
              break;

            case 'margin-top':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null && !val.isPercentage) marginTop = val.pixels;
              break;

            case 'margin-bottom':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null && !val.isPercentage) marginBottom = val.pixels;
              break;

            case 'padding-left':
              final val = _resolveLengthOrPercent(expr, baseFontSize);
              if (val != null) {
                if (val.isPercentage) {
                  isPaddingLeftPercentage = true;
                  paddingLeftPercentage = val.percentage;
                } else {
                  paddingLeft = val.pixels;
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
                }
              }
              break;

            case 'font-size':
              final scale = _resolveFontSizeScale(expr);
              if (scale != null) fontSizeScale = scale;
              break;
          }
        }

        final parsedRule = ResolvedCssRule(
          textIndent: textIndent,
          textAlign: textAlign,
          marginLeft: marginLeft,
          marginRight: marginRight,
          marginTop: marginTop,
          marginBottom: marginBottom,
          paddingLeft: paddingLeft,
          paddingRight: paddingRight,
          fontSizeScale: fontSizeScale,
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
    double availableWidth,
  ) {
    double total = 0.0;
    dom.Element? curr = el;
    while (curr != null) {
      final tag = curr.localName?.toLowerCase();
      if (tag == 'body' || tag == 'html') break;

      final rule = resolveRule(curr, rules);
      if (rule != null) {
        double left = rule.marginLeft ?? 0.0;
        if (rule.isMarginLeftPercentage && rule.marginLeftPercentage != null) {
          left = rule.marginLeftPercentage! * availableWidth;
        }

        double right = rule.marginRight ?? 0.0;
        if (rule.isMarginRightPercentage && rule.marginRightPercentage != null) {
          right = rule.marginRightPercentage! * availableWidth;
        }

        double padLeft = rule.paddingLeft ?? 0.0;
        if (rule.isPaddingLeftPercentage && rule.paddingLeftPercentage != null) {
          padLeft = rule.paddingLeftPercentage! * availableWidth;
        }

        double padRight = rule.paddingRight ?? 0.0;
        if (rule.isPaddingRightPercentage && rule.paddingRightPercentage != null) {
          padRight = rule.paddingRightPercentage! * availableWidth;
        }

        total += (left + right + padLeft + padRight);
      }
      curr = curr.parent;
    }

    return total;
  }

  /// Resolves vertical margins (top and bottom) for a block element.
  static ({double top, double bottom}) resolveVerticalMargins(
    dom.Element el,
    Map<String, ResolvedCssRule> rules,
  ) {
    final rule = resolveRule(el, rules);
    if (rule == null) return (top: 0.0, bottom: 0.0);
    return (
      top: rule.marginTop ?? 0.0,
      bottom: rule.marginBottom ?? 0.0,
    );
  }

  static ResolvedCssRule? _parseInlineStyleOnly(dom.Element el) {
    final style = el.attributes['style'];
    if (style == null || style.trim().isEmpty) return null;

    final lower = style.toLowerCase();
    String? textAlign;
    double? marginLeft;
    double? marginRight;
    double? textIndent;

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

    final mlMatch = RegExp(r'margin-left\s*:\s*([\d.]+)(em|px|rem|%)').firstMatch(lower);
    if (mlMatch != null) {
      final num = double.tryParse(mlMatch.group(1)!);
      final unit = mlMatch.group(2)!;
      if (num != null) {
        if (unit == 'em' || unit == 'rem') {
          marginLeft = num * 12.0;
        } else if (unit == 'px') {
          marginLeft = num;
        }
      }
    }

    return ResolvedCssRule(
      textAlign: textAlign,
      marginLeft: marginLeft,
      marginRight: marginRight,
      textIndent: textIndent,
    );
  }

  static ({double pixels, bool isPercentage, double percentage})? _resolveLengthOrPercent(
    css.Expression expr,
    double baseFontSize,
  ) {
    final text = expr.span?.text.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;

    final match = RegExp(r'^([+-]?[\d.]+)(em|rem|px|pt|%)?$').firstMatch(text);
    if (match == null) return null;

    final val = double.tryParse(match.group(1)!);
    if (val == null) return null;

    final unit = match.group(2) ?? 'px';
    if (unit == '%') {
      return (pixels: 0.0, isPercentage: true, percentage: val / 100.0);
    }

    double px = val;
    switch (unit) {
      case 'em':
      case 'rem':
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

    return (pixels: px, isPercentage: false, percentage: 0.0);
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
    final text = expr.span?.text.trim().toLowerCase();
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
      }
    }

    return null;
  }
}
