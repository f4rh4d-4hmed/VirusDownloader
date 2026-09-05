import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final VoidCallback onAddDownload;
  final String? filterMessage;

  const EmptyState({
    super.key,
    required this.onAddDownload,
    this.filterMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFiltered = filterMessage != null && filterMessage!.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFiltered ? Icons.search_off_outlined : Icons.download_outlined,
                size: 56,
                color: theme.colorScheme.primary.withAlpha(200),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isFiltered ? 'No downloads found' : 'No downloads yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? filterMessage!
                  : 'Add a download link to get started.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isFiltered) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAddDownload,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Download'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

