import 'package:flutter/material.dart';
import '../controllers/pdf_page_controller.dart';

class PdfPageControls extends StatelessWidget {
  final PdfPageController pageController;

  const PdfPageControls({
    super.key,
    required this.pageController,
  });

  @override
  Widget build(BuildContext context) {
    if (pageController.pageCount <= 1) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: pageController.pageIndex > 0
                    ? () => pageController.renderPage(0, userInitiated: true)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: pageController.pageIndex > 0
                    ? () => pageController.renderPage(pageController.pageIndex - 1, userInitiated: true)
                    : null,
              ),
              Text("${pageController.pageIndex + 1} / ${pageController.pageCount}"),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: pageController.pageIndex < pageController.pageCount - 1
                    ? () => pageController.renderPage(pageController.pageIndex + 1, userInitiated: true)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: pageController.pageIndex < pageController.pageCount - 1
                    ? () => pageController.renderPage(pageController.pageCount - 1, userInitiated: true)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
