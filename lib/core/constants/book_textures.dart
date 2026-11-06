import 'package:flutter/material.dart';

/// Information and styling metrics for an authentic book paper texture.
class BookTextureInfo {
  final String id;
  final String name;
  final String subtitle;
  final Color baseColor;
  final Color textColor;
  final Color secondaryTextColor;
  final bool isDark;

  const BookTextureInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.baseColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.isDark = false,
  });
}

/// Catalog of book paper textures designed to make reading feel like a physical book.
class BookTextures {
  BookTextures._();

  static const String none = 'none';
  static const String natural = 'natural';
  static const String parchment = 'parchment';
  static const String linen = 'linen';
  static const String washi = 'washi';
  static const String deckle = 'deckle';
  static const String kraft = 'kraft';
  static const String slate = 'slate';
  static const String obsidian = 'obsidian';

  static const List<BookTextureInfo> all = [
    BookTextureInfo(
      id: natural,
      name: 'Natural Paper',
      subtitle: 'Warm cream book stock with delicate fiber grain',
      baseColor: Color(0xFFF7F3E8),
      textColor: Color(0xFF2C241E),
      secondaryTextColor: Color(0xFF6B5E55),
      isDark: false,
    ),
    BookTextureInfo(
      id: parchment,
      name: 'Vintage Parchment',
      subtitle: 'Aged antique manuscript with golden mottling',
      baseColor: Color(0xFFF2E6C9),
      textColor: Color(0xFF38291A),
      secondaryTextColor: Color(0xFF745D44),
      isDark: false,
    ),
    BookTextureInfo(
      id: linen,
      name: 'Fine Laid / Linen',
      subtitle: 'Classic library paper with subtle woven rib lines',
      baseColor: Color(0xFFF9F7F1),
      textColor: Color(0xFF23211E),
      secondaryTextColor: Color(0xFF635D57),
      isDark: false,
    ),
    BookTextureInfo(
      id: washi,
      name: 'Japanese Washi',
      subtitle: 'Handmade mulberry tea paper with organic botanical fibers',
      baseColor: Color(0xFFEDF2E8),
      textColor: Color(0xFF1A2E22),
      secondaryTextColor: Color(0xFF4A6152),
      isDark: false,
    ),
    BookTextureInfo(
      id: deckle,
      name: 'Deckle Rag Folio',
      subtitle: 'Heavy 100% cotton archival book stock with rich deckle grain',
      baseColor: Color(0xFFFAF6EE),
      textColor: Color(0xFF261C14),
      secondaryTextColor: Color(0xFF5A4A3D),
      isDark: false,
    ),
    BookTextureInfo(
      id: kraft,
      name: 'Craft / Recycled',
      subtitle: 'Earthy fibrous kraft paper with natural specks',
      baseColor: Color(0xFFE5D4B3),
      textColor: Color(0xFF332619),
      secondaryTextColor: Color(0xFF6E563F),
      isDark: false,
    ),
    BookTextureInfo(
      id: slate,
      name: 'Slate Velvet',
      subtitle: 'Deep tactile charcoal paper for night reading',
      baseColor: Color(0xFF1B1917),
      textColor: Color(0xFFECE6DD),
      secondaryTextColor: Color(0xFFA69E94),
      isDark: true,
    ),
    BookTextureInfo(
      id: obsidian,
      name: 'Obsidian Velvet',
      subtitle: 'Pitch black 0-nit tactile night paper with starlight text',
      baseColor: Color(0xFF000000),
      textColor: Color(0xFFD8DCE3),
      secondaryTextColor: Color(0xFF8E95A0),
      isDark: true,
    ),
    BookTextureInfo(
      id: none,
      name: 'Clean / Theme',
      subtitle: 'Standard minimalist background without texture',
      baseColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF1E1E1E),
      secondaryTextColor: Color(0xFF757575),
      isDark: false,
    ),
  ];

  /// Find texture info by id with fallback to natural paper.
  static BookTextureInfo getById(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return all.first;
  }
}
