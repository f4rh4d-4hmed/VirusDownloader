import 'package:flutter/material.dart';

/// Representation of an item within [AppAnimatedDropdown].
class AppDropdownItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final Widget? icon;
  final Color? accentColor;

  const AppDropdownItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.accentColor,
  });
}

/// A modern, animated dropdown component with smooth scale/fade transitions,
/// intelligent upward/downward boundary positioning, and polished visuals.
class AppAnimatedDropdown<T> extends StatefulWidget {
  final T? value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isDense;
  final double? width;
  final double? menuWidth;
  final String? tooltip;
  final EdgeInsetsGeometry? contentPadding;
  final String? placeholderLabel;

  const AppAnimatedDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isDense = false,
    this.width,
    this.menuWidth,
    this.tooltip,
    this.contentPadding,
    this.placeholderLabel,
  });

  @override
  State<AppAnimatedDropdown<T>> createState() => _AppAnimatedDropdownState<T>();
}

class _AppAnimatedDropdownState<T> extends State<AppAnimatedDropdown<T>>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isOpen = false;
  bool _openUpwards = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );

    final curved = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(curved);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
  }

  @override
  void dispose() {
    _closeMenuImmediate();
    _animController.dispose();
    super.dispose();
  }

  void _closeMenuImmediate() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    if (widget.onChanged == null || widget.items.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final buttonSize = renderBox.size;
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    final hasSubtitles = widget.items.any((i) => i.subtitle != null && i.subtitle!.isNotEmpty);
    final estimatedItemHeight = hasSubtitles ? 54.0 : 42.0;
    final estimatedMenuHeight = (widget.items.length * estimatedItemHeight) + 16.0;

    final spaceBelow = screenSize.height - (buttonPosition.dy + buttonSize.height) - 12.0;
    final spaceAbove = buttonPosition.dy - 12.0;

    // Determine direction: open upwards if space below is too tight and space above is larger
    _openUpwards = spaceBelow < estimatedMenuHeight && spaceAbove > spaceBelow;

    _overlayEntry = _createOverlayEntry(buttonPosition, buttonSize, estimatedMenuHeight);
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isOpen = true;
    });
    _animController.forward(from: 0.0);
  }

  void _closeMenu() {
    if (!_isOpen) return;
    _animController.reverse().then((_) {
      if (mounted) {
        _closeMenuImmediate();
        setState(() {});
      }
    });
    setState(() {
      _isOpen = false;
    });
  }

  OverlayEntry _createOverlayEntry(Offset buttonPosition, Size buttonSize, double estimatedMenuHeight) {
    return OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final effectiveWidth = widget.menuWidth ??
            (widget.width ?? (buttonSize.width < 210 ? 230.0 : buttonSize.width));

        final screenSize = MediaQuery.of(context).size;
        final spaceToRight = screenSize.width - buttonPosition.dx;
        final openToLeft = (spaceToRight < effectiveWidth + 16.0) ||
            (buttonPosition.dx + (buttonSize.width / 2) > screenSize.width / 2);

        final targetAnchor = _openUpwards
            ? (openToLeft ? Alignment.topRight : Alignment.topLeft)
            : (openToLeft ? Alignment.bottomRight : Alignment.bottomLeft);

        final followerAnchor = _openUpwards
            ? (openToLeft ? Alignment.bottomRight : Alignment.bottomLeft)
            : (openToLeft ? Alignment.topRight : Alignment.topLeft);

        final alignment = _openUpwards
            ? (openToLeft ? Alignment.bottomRight : Alignment.bottomLeft)
            : (openToLeft ? Alignment.topRight : Alignment.topLeft);

        return Stack(
          children: [
            // Barrier to dismiss
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeMenu,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),

            // Dropdown panel anchored to button
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: targetAnchor,
              followerAnchor: followerAnchor,
              offset: Offset(0, _openUpwards ? -6.0 : 6.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  alignment: alignment,
                  child: Material(
                    elevation: 10,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    color: theme.colorScheme.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: effectiveWidth,
                        maxWidth: effectiveWidth > 320 ? effectiveWidth : 320,
                        maxHeight: 320,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.items.map((item) {
                            final isSelected = item.value == widget.value;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  _closeMenu();
                                  if (widget.onChanged != null) {
                                    widget.onChanged!(item.value);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: isSelected
                                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                                        : Colors.transparent,
                                  ),
                                  child: Row(
                                    children: [
                                      if (item.icon != null) ...[
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(6),
                                            color: item.accentColor != null
                                                ? item.accentColor!.withValues(alpha: 0.14)
                                                : theme.colorScheme.surfaceContainerHighest,
                                          ),
                                          alignment: Alignment.center,
                                          child: IconTheme(
                                            data: IconThemeData(
                                              size: 16,
                                              color: item.accentColor ??
                                                  (isSelected
                                                      ? theme.colorScheme.primary
                                                      : theme.colorScheme.onSurfaceVariant),
                                            ),
                                            child: item.icon!,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              item.label,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: isSelected
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.onSurface,
                                              ),
                                            ),
                                            if (item.subtitle != null &&
                                                item.subtitle!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.subtitle!,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  fontSize: 11,
                                                  color: isSelected
                                                      ? theme.colorScheme.primary.withValues(alpha: 0.8)
                                                      : theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    AppDropdownItem<T>? selectedItem;
    if (widget.value != null) {
      try {
        selectedItem = widget.items.firstWhere((i) => i.value == widget.value);
      } catch (_) {}
    }
    
    if (selectedItem == null && widget.placeholderLabel == null && widget.items.isNotEmpty) {
      selectedItem = widget.items.first;
    }

    final isDense = widget.isDense;

    Widget buttonChild = CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: widget.onChanged != null ? _toggleMenu : null,
        borderRadius: BorderRadius.circular(isDense ? 6 : 8),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          padding: widget.contentPadding ??
              (isDense
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isDense ? 6 : 8),
            color: _isOpen
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDense ? 0.35 : 0.6),
            border: Border.all(
              color: _isOpen
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: widget.width != null ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (selectedItem?.icon != null) ...[
                IconTheme(
                  data: IconThemeData(
                    size: isDense ? 14 : 16,
                    color: selectedItem!.accentColor ?? theme.colorScheme.onSurfaceVariant,
                  ),
                  child: selectedItem.icon!,
                ),
                SizedBox(width: isDense ? 6 : 8),
              ],
              widget.width != null
                  ? Expanded(
                      child: Text(
                        selectedItem?.label ?? widget.placeholderLabel ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (isDense
                                ? theme.textTheme.bodySmall
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                          fontWeight: selectedItem != null ? FontWeight.w500 : FontWeight.normal,
                          color: selectedItem != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Text(
                      selectedItem?.label ?? widget.placeholderLabel ?? '',
                      style: (isDense
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                        fontWeight: selectedItem != null ? FontWeight.w500 : FontWeight.normal,
                        color: selectedItem != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
              SizedBox(width: isDense ? 4 : 6),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: isDense ? 14 : 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: buttonChild,
      );
    }

    return buttonChild;
  }
}
