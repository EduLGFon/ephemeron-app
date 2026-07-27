import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_palettes.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'nav_section.dart';

void showOverflowSheet(
  BuildContext context,
  WidgetRef ref,
  List<NavSection> overflow,
  StatefulNavigationShell navigationShell,
  AppPalette palette,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: palette.surface.withValues(alpha: 0.8),
    barrierColor: Colors.black54,
    elevation: 0,
    builder: (sheetContext) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              for (int i = 0; i < overflow.length; i++)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(overflow[i].icon,
                        color: palette.primary, size: 20),
                  ),
                  title: Text(overflow[i].label,
                      style: TextStyle(
                          color: palette.text, fontWeight: FontWeight.w500)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    navigationShell.goBranch(overflow[i].branchIndex);
                  },
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Divider(
                    height: 1, color: palette.text.withValues(alpha: 0.1)),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: palette.text.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.settings_outlined,
                      color: palette.text.withValues(alpha: 0.7), size: 20),
                ),
                title: Text('Settings',
                    style: TextStyle(
                        color: palette.text, fontWeight: FontWeight.w500)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    },
  );
}
