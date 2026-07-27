import 'package:flutter/material.dart';
import '../../core/theme/theme_palettes.dart';
import 'nav_section.dart';

class PremiumNavigationBar extends StatelessWidget {
  final bool isPill;
  final List<NavSection> pinned;
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final AppPalette palette;

  const PremiumNavigationBar({
    super.key,
    required this.isPill,
    required this.pinned,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    Widget navBar = Container(
      height: 72,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
        borderRadius: isPill ? BorderRadius.circular(36) : BorderRadius.zero,
        border: Border.all(
          color: palette.text.withValues(alpha: palette.isAmoled ? 0.0 : 0.1),
          width: 1,
        ),
        boxShadow: isPill
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: isPill ? BorderRadius.circular(36) : BorderRadius.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (int i = 0; i < pinned.length; i++)
              NavItem(
                icon: pinned[i].icon,
                selectedIcon: pinned[i].selectedIcon,
                label: pinned[i].label,
                isSelected: selectedIndex == i,
                palette: palette,
                onTap: () => onDestinationSelected(i),
              ),
            NavItem(
              icon: Icons.more_horiz,
              selectedIcon: Icons.more_horiz,
              label: 'More',
              isSelected: selectedIndex == pinned.length,
              palette: palette,
              onTap: () => onDestinationSelected(pinned.length),
            ),
          ],
        ),
      ),
    );

    if (isPill) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomPadding > 0 ? bottomPadding : 16,
        ),
        child: navBar,
      );
    } else {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: navBar,
      );
    }
  }
}

class NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected
                  ? palette.primary
                  : palette.text.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? palette.primary
                    : palette.text.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
