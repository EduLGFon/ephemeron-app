// Main settings screen: one scrollable page grouped into appearance, behavior,
// accounts and sync, security, data and widgets, and navigation.
import 'package:ephemeron/core/security/app_lock.dart';
import 'package:ephemeron/core/theme/theme_tokens.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alarms/application/alarm_providers.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../sync/application/sync_providers.dart';
import '../application/settings_providers.dart';
import '../data/settings_repository.dart';
import 'backup_section.dart';
import 'home_widgets_screen.dart';
import 'nav_order_sheet.dart';
import 'settings_widgets.dart';

part 'settings_screen/settings_screen_state.dart';
part 'settings_screen/appearance_sections.dart';
part 'settings_screen/general_sections.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}
