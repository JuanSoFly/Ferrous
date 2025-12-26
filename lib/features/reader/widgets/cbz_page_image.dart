import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../controllers/cbz_cache_controller.dart';

class CbzPageImage extends StatefulWidget {
  final int pageIndex;
  final String pageName;
  final BoxFit fit;
  final int maxWidth;
  final CbzCacheController cacheController;

  const CbzPageImage({
    super.key,
    required this.pageIndex,
    required this.pageName,
    required this.fit,
    required this.maxWidth,
    required this.cacheController,
  });

  @override
  State<CbzPageImage> createState() => _CbzPageImageState();
}

class _CbzPageImageState extends State<CbzPageImage> {
  ui.Image? _image;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(CbzPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.pageName != widget.pageName ||
        oldWidget.maxWidth != widget.maxWidth) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (!mounted) return;

    // Check cache first via controller
    final cached = widget.cacheController.getCachedImage(widget.pageIndex, widget.maxWidth);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _image = cached.clone();
          _isLoading = false;
          _error = null;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final decodedImage = await widget.cacheController.loadPage(widget.pageIndex, widget.maxWidth);
      
      if (!mounted) {
        decodedImage?.dispose();
        return;
      }

      setState(() {
        _image = decodedImage;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, size: 48),
              const SizedBox(height: 8),
              Text('Page ${widget.pageIndex + 1}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    if (_image == null) {
      return const SizedBox(height: 200);
    }

    return RawImage(
      image: _image,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
