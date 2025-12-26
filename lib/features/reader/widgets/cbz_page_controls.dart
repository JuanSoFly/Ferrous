import 'package:flutter/material.dart';
import '../controllers/cbz_page_controller.dart';

class CbzPageControls extends StatelessWidget {
  final CbzPageController pageController;

  const CbzPageControls({
    super.key,
    required this.pageController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pageController,
      builder: (context, _) {
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
                    onPressed: pageController.pageIndex > 0 ? () => pageController.jumpToPage(0) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed:
                        pageController.pageIndex > 0 ? () => pageController.jumpToPage(pageController.pageIndex - 1) : null,
                  ),
                  Text("${pageController.pageIndex + 1} / ${pageController.pageCount}"),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: pageController.pageIndex < pageController.pageCount - 1
                        ? () => pageController.jumpToPage(pageController.pageIndex + 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page),
                    onPressed: pageController.pageIndex < pageController.pageCount - 1
                        ? () => pageController.jumpToPage(pageController.pageCount - 1)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
