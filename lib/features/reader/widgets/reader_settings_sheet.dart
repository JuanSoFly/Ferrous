import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:google_fonts/google_fonts.dart';

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Text'),
                Tab(text: 'Layout'),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('Font Size', config.fontSize.toStringAsFixed(0)),
        Row(
          children: [
            IconButton(
              onPressed: () => repo.setFontSize((config.fontSize - 2).clamp(12.0, 160.0)),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Slider(
                value: config.fontSize,
                min: 12.0,
                max: 160.0,
                divisions: ((160 - 12) / 2).round(),
                label: config.fontSize.round().toString(),
                onChanged: (val) => repo.setFontSize(val),
              ),
            ),
            IconButton(
              onPressed: () => repo.setFontSize((config.fontSize + 2).clamp(12.0, 160.0)),
              icon: const Icon(Icons.add),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('Font Family', config.fontFamily),
        Wrap(
          spacing: 8,
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
              label: Text(font, style: _getFontStyle(font)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) repo.setFontFamily(font);
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('Font Thickness', _fontWeightLabel(config.fontWeight)),
        Slider(
          value: config.fontWeight.toDouble(),
          min: 100,
          max: 900,
          divisions: 8,
          label: _fontWeightLabel(config.fontWeight),
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

  Widget _buildSectionTitle(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(color: Colors.grey)),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('Line Spacing', '${(config.lineHeight * 100).round()}%'),
        Slider(
          value: config.lineHeight,
          min: 0.0, // Requested 0%
          max: 2.0, // Requested 200%
          divisions: 20,
          label: '${(config.lineHeight * 100).round()}%',
          onChanged: (val) => repo.setLineHeight(val),
        ),

        _buildSectionTitle('Paragraph Spacing', '${config.paragraphSpacing.round()}'), // Using logical pixels roughly mapped
        Slider(
          value: config.paragraphSpacing,
          min: 0.0,
          max: 50.0, // Arbitrary max for "100%" feel? Requested 0-100%. User said 0% to 100% "with toggled Paragraph indentation". 
          // Let's assume 0.0 to 2.0 multiplier or just pixels. 0-100 px is a lot.
          // Let's stick to pixels for now, 0 to 40.
          divisions: 20,
           label: config.paragraphSpacing.toStringAsFixed(1),
          onChanged: (val) => repo.setParagraphSpacing(val),
        ),

        SwitchListTile(
          title: const Text('Paragraph Indentation'),
          value: config.paragraphIndent,
          onChanged: (_) => repo.toggleParagraphIndent(),
        ),

        const Divider(),

        _buildSectionTitle('Text Align', config.textAlign.toUpperCase()),
        Wrap(
          spacing: 8,
          children: [
            _AlignButton(icon: Icons.format_align_left, value: 'left', groupValue: config.textAlign, onChanged: repo.setTextAlign),
            _AlignButton(icon: Icons.format_align_center, value: 'center', groupValue: config.textAlign, onChanged: repo.setTextAlign),
            _AlignButton(icon: Icons.format_align_right, value: 'right', groupValue: config.textAlign, onChanged: repo.setTextAlign),
            _AlignButton(icon: Icons.format_align_justify, value: 'justify', groupValue: config.textAlign, onChanged: repo.setTextAlign),
          ],
        ),

        SwitchListTile(
          title: const Text('Hyphenation'),
          value: config.hyphenation,
          onChanged: (_) => repo.toggleHyphenation(),
        ),

        const Divider(),

        SwitchListTile(
          title: const Text('Page Margins'),
          subtitle: const Text('Toggle standard margins'),
          value: config.pageMargins,
          onChanged: (_) => repo.togglePageMargins(),
        ),

        SwitchListTile(
          title: const Text('Page Flipping'),
          subtitle: const Text('Animate page turns'),
          value: config.pageFlip,
          onChanged: (_) => repo.togglePageFlip(),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(color: Colors.grey)),
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
    return IconButton.filledTonal(
      onPressed: () => onChanged(value),
      isSelected: isSelected,
      icon: Icon(icon), 
      // style: IconButton.styleFrom(
      //   backgroundColor: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      // ), // isSelected handles tonal style usually
    );
  }
}
