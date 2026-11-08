import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'package:reader_app/features/settings/app_themes.dart';

// ==========================================
// E-INK HARDWARE SLIDER & MECHANICAL CONTROLS
// ==========================================

class _KindleSliderTrackShape extends SliderTrackShape {
  final double trackHeight;
  const _KindleSliderTrackShape({this.trackHeight = 4.0});

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Paint inactivePaint = Paint()
      ..color = const Color(0xFFEAE6DF)
      ..style = PaintingStyle.fill;

    final Paint activePaint = Paint()
      ..color = const Color(0xFF1A1A18)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = const Color(0xFF1A1A18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Inactive track (full width)
    context.canvas.drawRect(trackRect, inactivePaint);

    // Active track (left to thumbCenter.dx)
    final Rect activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx.clamp(trackRect.left, trackRect.right),
      trackRect.bottom,
    );
    context.canvas.drawRect(activeRect, activePaint);

    // Hard border around track
    context.canvas.drawRect(trackRect, borderPaint);
  }
}

class _KindleSliderThumbShape extends SliderComponentShape {
  final double width;
  final double height;

  const _KindleSliderThumbShape({this.width = 14, this.height = 18});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Rect thumbRect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );

    final RRect rrect = RRect.fromRectAndRadius(thumbRect, const Radius.circular(1));

    // Fill #1A1A18
    final Paint fillPaint = Paint()
      ..color = const Color(0xFF1A1A18)
      ..style = PaintingStyle.fill;
    context.canvas.drawRRect(rrect, fillPaint);

    // Border 1px solid #EAE6DF
    final Paint borderPaint = Paint()
      ..color = const Color(0xFFEAE6DF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    context.canvas.drawRRect(rrect, borderPaint);
  }
}

class _KindleStepButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _KindleStepButton({required this.icon, required this.onPressed});

  @override
  State<_KindleStepButton> createState() => _KindleStepButtonState();
}

class _KindleStepButtonState extends State<_KindleStepButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _isPressed ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(
          widget.icon,
          size: 20,
          color: _isPressed ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
        ),
      ),
    );
  }
}

class KindleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const KindleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: const Color(0xFF1A1A18),
            width: 1.5,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 100),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: value ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
              borderRadius: BorderRadius.circular(1),
              border: Border.all(
                color: value ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MAIN READER SETTINGS SHEET
// ==========================================

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surface,
        borderRadius: isEInk
            ? const BorderRadius.vertical(top: Radius.circular(2))
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: isEInk
            ? const Border(
                top: BorderSide(color: Color(0xFF1A1A18), width: 2),
                left: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                right: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
              )
            : null,
      ),
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            if (!isEInk) ...[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              const SizedBox(height: 4),
            ],
            Container(
              decoration: isEInk
                  ? const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                      ),
                    )
                  : null,
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.symmetric(horizontal: 16),
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: isEInk
                      ? BorderRadius.zero
                      : const BorderRadius.vertical(top: Radius.circular(3)),
                ),
                labelColor: isEInk ? const Color(0xFF1A1A18) : null,
                unselectedLabelColor: isEInk ? const Color(0xFF4A4945) : null,
                labelStyle: isEInk
                    ? GoogleFonts.robotoSlab(fontWeight: FontWeight.w700, fontSize: 14)
                    : null,
                unselectedLabelStyle: isEInk
                    ? GoogleFonts.robotoSlab(fontWeight: FontWeight.w500, fontSize: 14)
                    : null,
                tabs: const [
                  Tab(text: 'Text Options'),
                  Tab(text: 'Page Layout'),
                  Tab(text: 'Book Feel'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TextSettingsTab(),
                  _LayoutSettingsTab(),
                  _BookFeelTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 1. TEXT SETTINGS TAB
// ==========================================

class _TextSettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ReaderThemeRepository>();
    final config = repo.config;
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildSectionTitle(theme, 'Font Size', '${config.fontSize.toStringAsFixed(0)} px', isEInk: isEInk),
        const SizedBox(height: 8),
        Row(
          children: [
            if (isEInk)
              _KindleStepButton(
                icon: Icons.remove,
                onPressed: () => repo.setFontSize((config.fontSize - 2).clamp(12.0, 160.0)),
              )
            else
              IconButton.filledTonal(
                onPressed: () => repo.setFontSize((config.fontSize - 2).clamp(12.0, 160.0)),
                icon: const Icon(Icons.remove),
              ),
            Expanded(
              child: _buildSlider(
                context: context,
                theme: theme,
                isEInk: isEInk,
                value: config.fontSize,
                min: 12.0,
                max: 160.0,
                divisions: ((160 - 12) / 2).round(),
                onChanged: (val) => repo.setFontSize(val),
              ),
            ),
            if (isEInk)
              _KindleStepButton(
                icon: Icons.add,
                onPressed: () => repo.setFontSize((config.fontSize + 2).clamp(12.0, 160.0)),
              )
            else
              IconButton.filledTonal(
                onPressed: () => repo.setFontSize((config.fontSize + 2).clamp(12.0, 160.0)),
                icon: const Icon(Icons.add),
              ),
          ],
        ),

        const SizedBox(height: 24),
        _buildSectionTitle(theme, 'Font Family', config.fontFamily, isEInk: isEInk),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'Roboto',
            'Roboto Slab',
            'Merriweather',
            'Lora',
            'Open Sans',
            'Source Sans 3',
            'Literata',
          ].map((font) {
            final isSelected = config.fontFamily == font;
            if (isEInk) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => repo.setFontFamily(font),
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: const Color(0xFF1A1A18),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      font,
                      style: (_getFontStyle(font) ?? const TextStyle()).copyWith(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ChoiceChip(
              label: Text(font, style: _getFontStyle(font)?.copyWith(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
              selected: isSelected,
              backgroundColor: theme.colorScheme.surfaceContainerLow,
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
              onSelected: (selected) {
                if (selected) repo.setFontFamily(font);
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 24),
        _buildSectionTitle(theme, 'Font Weight / Thickness', _fontWeightLabel(config.fontWeight), isEInk: isEInk),
        _buildSlider(
          context: context,
          theme: theme,
          isEInk: isEInk,
          value: config.fontWeight.toDouble(),
          min: 100,
          max: 900,
          divisions: 8,
          onChanged: (val) => repo.setFontWeight(val.round()),
        ),
      ],
    );
  }

  String _fontWeightLabel(int weight) {
    switch (weight) {
      case 100: return 'Thin';
      case 200: return 'Extra Light';
      case 300: return 'Light';
      case 400: return 'Normal';
      case 500: return 'Medium';
      case 600: return 'Semi Bold';
      case 700: return 'Bold';
      case 800: return 'Extra Bold';
      case 900: return 'Black';
      default: return weight.toString();
    }
  }

  TextStyle? _getFontStyle(String font) {
    try {
      return GoogleFonts.getFont(font);
    } catch (_) {
      return null;
    }
  }
}

// ==========================================
// 2. LAYOUT SETTINGS TAB
// ==========================================

class _LayoutSettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ReaderThemeRepository>();
    final config = repo.config;
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildSectionTitle(theme, 'Line Spacing', '${(config.lineHeight * 100).round()}%', isEInk: isEInk),
        _buildSlider(
          context: context,
          theme: theme,
          isEInk: isEInk,
          value: config.lineHeight,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          onChanged: (val) => repo.setLineHeight(val),
        ),

        const SizedBox(height: 12),
        _buildSectionTitle(theme, 'Paragraph Spacing', '${config.paragraphSpacing.round()} px', isEInk: isEInk),
        _buildSlider(
          context: context,
          theme: theme,
          isEInk: isEInk,
          value: config.paragraphSpacing,
          min: 0.0,
          max: 50.0,
          divisions: 20,
          onChanged: (val) => repo.setParagraphSpacing(val),
        ),

        _buildSwitchTile(
          context: context,
          theme: theme,
          isEInk: isEInk,
          title: 'Paragraph Indentation',
          value: config.paragraphIndent,
          onChanged: (_) => repo.toggleParagraphIndent(),
        ),

        Divider(
          height: 24,
          thickness: isEInk ? 1 : 0.5,
          color: isEInk ? const Color(0xFF9E9A90) : null,
        ),

        _buildSectionTitle(theme, 'Text Alignment', config.textAlign.toUpperCase(), isEInk: isEInk),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _AlignButton(icon: Icons.format_align_left, value: 'left', groupValue: config.textAlign, onChanged: repo.setTextAlign),
              _AlignButton(icon: Icons.format_align_center, value: 'center', groupValue: config.textAlign, onChanged: repo.setTextAlign),
              _AlignButton(icon: Icons.format_align_right, value: 'right', groupValue: config.textAlign, onChanged: repo.setTextAlign),
              _AlignButton(icon: Icons.format_align_justify, value: 'justify', groupValue: config.textAlign, onChanged: repo.setTextAlign),
            ],
          ),
        ),

        Divider(
          height: 32,
          thickness: isEInk ? 1 : 0.5,
          color: isEInk ? const Color(0xFF9E9A90) : null,
        ),

        _buildSwitchTile(
          context: context,
          theme: theme,
          isEInk: isEInk,
          title: 'Hyphenation',
          value: config.hyphenation,
          onChanged: (_) => repo.toggleHyphenation(),
        ),

        _buildSwitchTile(
          context: context,
          theme: theme,
          isEInk: isEInk,
          title: 'Page Margins',
          subtitle: 'Show standard margins around text',
          value: config.pageMargins,
          onChanged: (_) => repo.togglePageMargins(),
        ),
      ],
    );
  }
}

// ==========================================
// 3. BOOK FEEL TAB
// ==========================================

class _BookFeelTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ReaderThemeRepository>();
    final config = repo.config;
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        // 1. Realistic Books Page Turn animation toggle
        _buildSectionHeader(theme, 'PAGE TURN ANIMATION', Icons.auto_stories, isEInk: isEInk),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
            border: Border.all(
              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isEInk ? 1.5 : 1,
            ),
          ),
          child: _buildSwitchTile(
            context: context,
            theme: theme,
            isEInk: isEInk,
            title: 'Realistic Books Page Turn',
            subtitle: 'Realistic 3D curl animation with dynamic paper lighting and shadows when swiping pages',
            value: config.pageFlip,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isEInk ? 2 : 16)),
            onChanged: (val) => repo.setPageFlip(val),
          ),
        ),

        const SizedBox(height: 24),

        // 2. Background Paper Texture Options
        _buildSectionHeader(theme, 'REAL BOOK BACKGROUND TEXTURE', Icons.wallpaper, isEInk: isEInk),
        const SizedBox(height: 6),
        Text(
          'Choose an authentic book paper texture to make the entire screen look and feel like a real book.',
          style: TextStyle(
            fontSize: 12,
            color: isEInk ? const Color(0xFF4A4945) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 12),

        ...BookTextures.all.map((texture) {
          final isSelected = config.paperTexture == texture.id;
          return _TextureCard(
            texture: texture,
            isSelected: isSelected,
            onTap: () => repo.setPaperTexture(texture.id),
          );
        }),

        const SizedBox(height: 20),

        // 3. Physical Book Details & Depth
        _buildSectionHeader(theme, 'PHYSICAL BOOK DETAILS', Icons.menu_book, isEInk: isEInk),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
            border: Border.all(
              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isEInk ? 1.5 : 1,
            ),
          ),
          child: _buildSwitchTile(
            context: context,
            theme: theme,
            isEInk: isEInk,
            title: 'Book Spine & Page Edges',
            subtitle: 'Show realistic book binding gutter shadow and stacked paper leaf edges along the margins',
            value: config.showBookSpine,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isEInk ? 2 : 16)),
            onChanged: (_) => repo.toggleBookSpine(),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon, {bool isEInk = false}) {
    final color = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ==========================================
// TEXTURE CARD WIDGET
// ==========================================

class _TextureCard extends StatelessWidget {
  final BookTextureInfo texture;
  final bool isSelected;
  final VoidCallback onTap;

  const _TextureCard({
    required this.texture,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    if (isEInk) {
      final Color swatchColor = texture.id == BookTextures.none
          ? const Color(0xFFEAE6DF)
          : texture.baseColor;

      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(
            color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFF9E9A90),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        color: isSelected ? const Color(0xFFD5D0C5) : const Color(0xFFE0DCD3),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Sharp 2px-radius square ink stamp
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: swatchColor,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: const Color(0xFF1A1A18),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.menu_book,
                      size: 18,
                      color: texture.id == BookTextures.none
                          ? const Color(0xFF1A1A18)
                          : (texture.isDark ? Colors.white70 : const Color(0xFF1A1A18)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title and description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        texture.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: const Color(0xFF1A1A18),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        texture.subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4A4945),
                        ),
                      ),
                    ],
                  ),
                ),

                if (isSelected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Color(0xFFEAE6DF),
                      size: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Swatch circle showing the actual paper color
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: texture.baseColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.menu_book,
                    size: 18,
                    color: texture.textColor.withValues(alpha: 0.65),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texture.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      texture.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ALIGN BUTTON WIDGET
// ==========================================

class _AlignButton extends StatelessWidget {
  final IconData icon;
  final String value;
  final String groupValue;
  final Function(String) onChanged;

  const _AlignButton({
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    if (isEInk) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(2),
          child: Container(
            width: 64,
            height: 42,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: const Color(0xFF1A1A18),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isSelected ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
              size: 20,
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 42,
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          size: 20,
        ),
      ),
    );
  }
}

// ==========================================
// SHARED HELPER BUILDERS
// ==========================================

Widget _buildSectionTitle(ThemeData theme, String title, String value, {bool isEInk = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isEInk ? const Color(0xFF1A1A18) : null,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

Widget _buildSlider({
  required BuildContext context,
  required ThemeData theme,
  required bool isEInk,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required ValueChanged<double> onChanged,
}) {
  if (isEInk) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        trackShape: const _KindleSliderTrackShape(trackHeight: 4),
        thumbShape: const _KindleSliderThumbShape(width: 14, height: 18),
        overlayShape: SliderComponentShape.noOverlay,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }

  return SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: 4,
      activeTrackColor: theme.colorScheme.primary,
      inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      thumbColor: theme.colorScheme.primary,
    ),
    child: Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
    ),
  );
}

Widget _buildSwitchTile({
  required BuildContext context,
  required ThemeData theme,
  required bool isEInk,
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool>? onChanged,
  ShapeBorder? shape,
}) {
  if (isEInk) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A18),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF4A4945)),
            )
          : null,
      trailing: KindleSwitch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: onChanged != null ? () => onChanged(!value) : null,
    );
  }

  return SwitchListTile(
    shape: shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 11)) : null,
    value: value,
    activeThumbColor: theme.colorScheme.primary,
    onChanged: onChanged,
  );
}
