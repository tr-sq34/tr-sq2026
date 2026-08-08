import 'package:flutter/material.dart';

import '../pagination/paged_controller.dart';

class PagedListFooter<T> extends StatelessWidget {
  const PagedListFooter({super.key, required this.controller});
  final PagedController<T> controller;

  @override
  Widget build(BuildContext context) {
    if (controller.state == PagedLoadState.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return const SizedBox(height: 12);
  }
}
