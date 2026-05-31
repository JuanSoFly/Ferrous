import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:google_fonts/google_fonts.dart';

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DefaultTabController(
        length: 2,
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
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TextSettingsTab(),
                  _LayoutSettingsTab(),
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
