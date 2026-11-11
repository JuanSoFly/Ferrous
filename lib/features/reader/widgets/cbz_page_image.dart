import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:reader_app/core/errors/exceptions.dart';
import '../controllers/cbz_cache_controller.dart';

enum CbzPageState { idle, loading, loaded, error }

class CbzPageImage extends StatefulWidget {
  final int pageIndex;
  final String pageName;
  final BoxFit fit;
  final int maxWidth;
  final CbzCacheController cacheController;
  final double fallbackAspectRatio;
  final VoidCallback? onPageLoaded;

  const CbzPageImage({
    super.key,
    required this.pageIndex,
    required this.pageName,
    required this.fit,
    required this.maxWidth,
    required this.cacheController,
    this.fallbackAspectRatio = 0.70,
    this.onPageLoaded,
  });

  @override
  State<CbzPageImage> createState() => _CbzPageImageState();
}

class _CbzPageImageState extends State<CbzPageImage> {
  ui.Image? _image;
  CbzPageState _state = CbzPageState.idle;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final cached = widget.cacheController.getCachedImage(widget.pageIndex, widget.maxWidth);
    if (cached != null) {
      _image = cached.clone();
      _state = CbzPageState.loaded;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPageLoaded?.call();
      });
    } else {
      _loadPage();
    }
  }

  @override
  void didUpdateWidget(CbzPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.pageName != widget.pageName ||
        oldWidget.maxWidth != widget.maxWidth) {
      _loadGeneration++;
      _image?.dispose();
      _image = null;

      final cached = widget.cacheController.getCachedImage(widget.pageIndex, widget.maxWidth);
      if (cached != null) {
        setState(() {
          _image = cached.clone();
          _state = CbzPageState.loaded;
          _error = null;
        });
      } else {
        _loadPage();
      }
    }
  }

  Future<void> _loadPage() async {
    final currentGen = ++_loadGeneration;
    final pageIndex = widget.pageIndex;
    final maxWidth = widget.maxWidth;

    final cached = widget.cacheController.getCachedImage(pageIndex, maxWidth);
    if (cached != null) {
      if (mounted && _loadGeneration == currentGen) {
        setState(() {
          _image?.dispose();
          _image = cached.clone();
          _state = CbzPageState.loaded;
          _error = null;
        });
      }
      return;
    }

    if (mounted && _loadGeneration == currentGen) {
      setState(() {
        _state = CbzPageState.loading;
        _error = null;
      });
    }

    try {
      final decodedImage = await widget.cacheController.loadPage(
        pageIndex,
        maxWidth,
        isImmediate: true,
      );

      if (!mounted || _loadGeneration != currentGen) {
        decodedImage?.dispose();
        return;
      }

      if (decodedImage != null) {
        setState(() {
          _image?.dispose();
          _image = decodedImage;
          _state = CbzPageState.loaded;
          _error = null;
        });
        widget.onPageLoaded?.call();
      } else {
        final specificErr = widget.cacheController.getPageError(pageIndex);
        setState(() {
          _state = CbzPageState.error;
          _error = specificErr != null
              ? 'Page ${pageIndex + 1}: $specificErr'
              : 'Page ${pageIndex + 1} could not be loaded';
        });
      }
    } catch (e) {
      if (!mounted || _loadGeneration != currentGen) return;
      final specificErr = (e is ArchiveExtractionException)
          ? e.message
          : widget.cacheController.getPageError(pageIndex) ?? e.toString();
      setState(() {
        _state = CbzPageState.error;
        _error = 'Page ${pageIndex + 1}: $specificErr';
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == CbzPageState.loading || _state == CbzPageState.idle) {
      final estimatedAr = widget.cacheController.getEstimatedAspectRatio(
        widget.pageIndex,
        fallback: widget.fallbackAspectRatio,
      ) ?? widget.fallbackAspectRatio;
      return AspectRatio(
        aspectRatio: estimatedAr,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_state == CbzPageState.error || _image == null) {
      final estimatedAr = widget.cacheController.getEstimatedAspectRatio(
        widget.pageIndex,
        fallback: widget.fallbackAspectRatio,
      ) ?? widget.fallbackAspectRatio;
      return AspectRatio(
        aspectRatio: estimatedAr,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Failed to load Page ${widget.pageIndex + 1}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _loadPage,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tap to reload page'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RawImage(
      image: _image,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
