import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../presentation/shell/pinned_sections_provider.dart';
import 'settings_screen.dart'; 

class SettingsAppearanceSection extends ConsumerWidget {
  const SettingsAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final currentPalette = ref.watch(themeEngineProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _ColorPickerRow(
          title: 'Primary Color',
          currentColor: currentPalette.primary,
          options: const {
            'Purple (Default)': Color(0xFF6C63FF),
            'Pink': Colors.pink,
            'Blue': Colors.blue,
            'Cyan': Colors.cyan,
            'Green': Colors.green,
            'Yellow': Colors.yellow,
            'Orange': Colors.orange,
            'Red': Colors.red,
            'Brown': Colors.brown,
            'Monochromatic': Colors.grey,
          },
          onColorSelected: (c) => ref
              .read(themeEngineProvider.notifier)
              .setPrimaryColor(c),
          onCustomSelected: () => SettingsScreen.editThemeColor(
              context, ref, 'Primary', currentPalette.primary),
        ),
        const SizedBox(height: 16),
        _ColorPickerRow(
          title: 'Background Color',
          currentColor: currentPalette.background,
          options: const {
            'Obsidian (Default)': Color(0xFF121212),
            'Black': Colors.black,
            'Soft Dark': Color(0xFF1E1E1E),
            'Soft Blue Dark': Color(0xFF171923),
            'White': Colors.white,
            'Off-White': Color(0xFFF7FAFC),
          },
          onColorSelected: (c) => ref
              .read(themeEngineProvider.notifier)
              .setBackgroundColor(c),
          onCustomSelected: () => SettingsScreen.editThemeColor(
              context, ref, 'Background', currentPalette.background),
        ),
        const SizedBox(height: 8),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Navigation Bar',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        SwitchListTile(
          title: const Text('Floating Pill Layout'),
          subtitle: const Text(
              'Use a floating glass navigation bar instead of edge-to-edge'),
          value: settings.usePillNavigation,
          onChanged: notifier.setUsePillNavigation,
        ),
        ListTile(
          title: const Text('Customize Navigation Bar'),
          subtitle: const Text('Reorder tabs and overflow items'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              builder: (context) => const NavigationBarCustomizationSheet(),
            );
          },
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Battery & motion',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        SwitchListTile(
          title: const Text('Enable Glassmorphism (Blur Effects)'),
          subtitle: const Text(
            'Uses blurry backgrounds for some UI elements. WARNING: Severely impacts performance and battery usage.',
          ),
          value: settings.glassmorphismEnabled,
          onChanged: notifier.setGlassmorphismEnabled,
        ),
        SwitchListTile(
          title: const Text('Tactile Haptic Feedback'),
          subtitle: const Text(
              'Vibrate when dragging events across timeline grid lines'),
          value: settings.hapticsEnabled,
          onChanged: notifier.setHapticsEnabled,
        ),
        SwitchListTile(
          title: const Text('Reduce animations'),
          subtitle: const Text('Turns off decorative page transitions'),
          value: settings.reducedMotion,
          onChanged: notifier.setReducedMotion,
        ),
        ListTile(
          title: const Text('Power saving mode'),
          subtitle: const Text(
            'Manually force or disable reduced animations',
          ),
          trailing: SegmentedButton<PowerSavingMode>(
            segments: const [
              ButtonSegment(value: PowerSavingMode.auto, label: Text('Auto')),
              ButtonSegment(value: PowerSavingMode.alwaysOn, label: Text('On')),
              ButtonSegment(value: PowerSavingMode.alwaysOff, label: Text('Off')),
            ],
            selected: {settings.powerSavingMode},
            onSelectionChanged: (Set<PowerSavingMode> newSelection) {
              notifier.setPowerSavingMode(newSelection.first);
            },
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (!kIsWeb)
          ListTile(
            title: const Text('Device battery saver'),
            subtitle: Text(
              settings.osBatterySaverActive
                  ? 'Currently on — Ephemeron is automatically reducing animations to match'
                  : 'Currently off',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-check',
              onPressed: notifier.refreshBatteryState,
            ),
          ),
        if (kIsWeb)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: WebReminderNotice(),
          ),
      ],
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.title,
    required this.currentColor,
    required this.options,
    required this.onColorSelected,
    required this.onCustomSelected,
  });

  final String title;
  final Color currentColor;
  final Map<String, Color> options;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onCustomSelected;

  @override
  Widget build(BuildContext context) {
    final isCustom = !options.values.any((c) => c.toARGB32() == currentColor.toARGB32());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in options.entries)
                InkWell(
                  onTap: () => onColorSelected(entry.value),
                  borderRadius: BorderRadius.circular(20),
                  child: Tooltip(
                    message: entry.key,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: currentColor.toARGB32() == entry.value.toARGB32()
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.grey.withValues(alpha: 0.5),
                          width: currentColor.toARGB32() == entry.value.toARGB32() ? 2 : 1,
                        ),
                      ),
                      child: currentColor.toARGB32() == entry.value.toARGB32()
                          ? Icon(Icons.check,
                              color: entry.value.computeLuminance() > 0.5
                                  ? Colors.black : Colors.white)
                          : null,
                    ),
                  ),
                ),
              InkWell(
                onTap: onCustomSelected,
                borderRadius: BorderRadius.circular(20),
                child: Tooltip(
                  message: 'Custom Hex',
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: isCustom ? currentColor : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCustom
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey.withValues(alpha: 0.5),
                        width: isCustom ? 2 : 1,
                      ),
                    ),
                    child: isCustom
                        ? Icon(Icons.check,
                            color: currentColor.computeLuminance() > 0.5
                                ? Colors.black : Colors.white)
                        : Icon(Icons.palette_outlined,
                            color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NavigationBarCustomizationSheet extends ConsumerWidget {
  const NavigationBarCustomizationSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSections = ref.watch(allSectionsOrderProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Reorder Sections', style: Theme.of(context).textTheme.titleLarge),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Drag to reorder. The top 5 appear on the bottom bar, the rest in "More".'),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: allSections.length,
              onReorderItem: (oldIndex, newIndex) {
                if (oldIndex < newIndex) newIndex -= 1;
                final item = allSections[oldIndex];
                final newList = List.of(allSections);
                newList.removeAt(oldIndex);
                newList.insert(newIndex, item);
                ref.read(allSectionsOrderProvider.notifier).updateOrder(newList);
              },
              itemBuilder: (context, index) {
                final section = allSections[index];
                final isPinned = index < 5;
                return ListTile(
                  key: ValueKey(section),
                  leading: Icon(isPinned ? section.icon : Icons.more_horiz),
                  title: Text(section.label),
                  trailing: const Icon(Icons.drag_handle),
                  tileColor: isPinned
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WebReminderNotice extends StatelessWidget {
  const WebReminderNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reminders and alarms aren\'t available in the browser — this is a '
                'platform limitation (browsers don\'t support scheduled '
                'notifications), not a bug. Use the Android app for reminders.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
