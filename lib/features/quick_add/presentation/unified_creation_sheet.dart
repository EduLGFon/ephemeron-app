import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../presentation/shell/nav_section.dart';
import '../../../core/settings/session_restore.dart';

Future<void> showUnifiedCreationSheet(BuildContext context, {NavSection? currentSection}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: SingleChildScrollView(
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: RepaintBoundary(child: UnifiedCreationSheet(currentSection: currentSection)),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      );
    },
  );
}

class UnifiedCreationSheet extends ConsumerStatefulWidget {
  const UnifiedCreationSheet({this.currentSection, super.key});
  final NavSection? currentSection;

  @override
  ConsumerState<UnifiedCreationSheet> createState() => _UnifiedCreationSheetState();
}

class _UnifiedCreationSheetState extends ConsumerState<UnifiedCreationSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SessionRestore.saveOpenMenu('quick_add');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    SessionRestore.clearOpenMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            style: TextStyle(color: palette.text, fontSize: 18, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'What would you like to do?',
              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
          ),
          TextField(
            controller: _descController,
            style: TextStyle(color: palette.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Description',
              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 16),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildIconButton(Icons.calendar_today_outlined, palette),
              const SizedBox(width: 8),
              _buildIconButton(Icons.flag_outlined, palette),
              const SizedBox(width: 8),
              _buildIconButton(Icons.local_offer_outlined, palette),
              const SizedBox(width: 8),
              _buildIconButton(Icons.drive_file_move_outlined, palette),
              const SizedBox(width: 8),
              _buildIconButton(Icons.more_horiz, palette),
              const Spacer(),
              _buildIconButton(Icons.mic_none, palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, AppPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: palette.text.withValues(alpha: 0.7),
        onPressed: () {},
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }
}
