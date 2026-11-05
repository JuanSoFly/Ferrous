import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/constants/book_textures.dart';

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
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
            TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              tabs: const [
                Tab(text: 'Text Options'),
                Tab(text: 'Page Layout'),
                Tab(text: 'Book Feel'),
              ],
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

class _TextSettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ReaderThemeRepository>();
    final config = repo.config;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildSectionTitle(theme, 'Font Size', '${config.fontSize.toStringAsFixed(0)} px'),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => repo.setFontSize((config.fontSize - 2).clamp(12.0, 160.0)),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: config.fontSize,
                  min: 12.0,
                  max: 160.0,
                  divisions: ((160 - 12) / 2).round(),
                  onChanged: (val) => repo.setFontSize(val),
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => repo.setFontSize((config.fontSize + 2).clamp(12.0, 160.0)),
              icon: const Icon(Icons.add),
            ),
          ],
        ),

        const SizedBox(height: 24),
        _buildSectionTitle(theme, 'Font Family', config.fontFamily),
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
        _buildSectionTitle(theme, 'Font Weight / Thickness', _fontWeightLabel(config.fontWeight)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            thumbColor: theme.colorScheme.primary,
          ),
          child: Slider(
            value: config.fontWeight.toDouble(),
            min: 100,
            max: 900,
            divisions: 8,
            onChanged: (val) => repo.setFontWeight(val.round()),
          ),
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

  Widget _buildSectionTitle(ThemeData theme, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutSettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ReaderThemeRepository>();
    final config = repo.config;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildSectionTitle(theme, 'Line Spacing', '${(config.lineHeight * 100).round()}%'),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            thumbColor: theme.colorScheme.primary,
          ),
          child: Slider(
            value: config.lineHeight,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            onChanged: (val) => repo.setLineHeight(val),
          ),
        ),

        const SizedBox(height: 12),
        _buildSectionTitle(theme, 'Paragraph Spacing', '${config.paragraphSpacing.round()} px'),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            thumbColor: theme.colorScheme.primary,
          ),
          child: Slider(
            value: config.paragraphSpacing,
            min: 0.0,
            max: 50.0,
            divisions: 20,
            onChanged: (val) => repo.setParagraphSpacing(val),
          ),
        ),

        SwitchListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Paragraph Indentation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          value: config.paragraphIndent,
          activeThumbColor: theme.colorScheme.primary,
          onChanged: (_) => repo.toggleParagraphIndent(),
        ),

        const Divider(height: 24),

        _buildSectionTitle(theme, 'Text Alignment', config.textAlign.toUpperCase()),
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

        const Divider(height: 32),

        SwitchListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Hyphenation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          value: config.hyphenation,
          activeThumbColor: theme.colorScheme.primary,
          onChanged: (_) => repo.toggleHyphenation(),
        ),

        SwitchListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Page Margins', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: const Text('Show standard margins around text', style: TextStyle(fontSize: 11)),
          value: config.pageMargins,
          activeThumbColor: theme.colorScheme.primary,
          onChanged: (_) => repo.togglePageMargins(),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookFeelTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ReaderThemeRepository>();
    final config = repo.config;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        // 1. Realistic Books Page Turn animation toggle
        _buildSectionHeader(theme, 'PAGE TURN ANIMATION', Icons.auto_stories),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: SwitchListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Realistic Books Page Turn',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Realistic 3D curl animation with dynamic paper lighting and shadows when swiping pages',
              style: TextStyle(fontSize: 12),
            ),
            value: config.pageFlip,
            activeThumbColor: theme.colorScheme.primary,
            onChanged: (val) => repo.setPageFlip(val),
          ),
        ),

        const SizedBox(height: 24),

        // 2. Background Paper Texture Options
        _buildSectionHeader(theme, 'REAL BOOK BACKGROUND TEXTURE', Icons.wallpaper),
        const SizedBox(height: 6),
        Text(
          'Choose an authentic book paper texture to make the entire screen look and feel like a real book.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
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
        _buildSectionHeader(theme, 'PHYSICAL BOOK DETAILS', Icons.menu_book),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: SwitchListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Book Spine & Page Edges',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Show realistic book binding gutter shadow and stacked paper leaf edges along the margins',
              style: TextStyle(fontSize: 12),
            ),
            value: config.showBookSpine,
            activeThumbColor: theme.colorScheme.primary,
            onChanged: (_) => repo.toggleBookSpine(),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

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
