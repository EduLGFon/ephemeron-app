// First-run onboarding: 3 pages max, skip always available.
// Permissions are explained at the moment of need, not all upfront.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/settings_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setOnboarded();
    ref.invalidate(settingsRepositoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [TextButton(onPressed: _finish, child: const Text('Skip'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _index = i),
              children: const [
                _Page(
                  icon: Icons.calendar_month_outlined,
                  title: 'Your time, offline first',
                  body:
                      'Calendar, tasks, habits, countdowns, focus, notes and lists in one fast app. Everything works without any account.',
                ),
                _Page(
                  icon: Icons.alarm_outlined,
                  title: 'Alarms that ring',
                  body:
                      'When you create your first reminder, the app asks for notification and exact-alarm permission so it can ring on time, even in power saving. You can send a test alarm from Settings any time.',
                ),
                _Page(
                  icon: Icons.sync_outlined,
                  title: 'Sync is optional',
                  body:
                      'Connect Google to sync calendar and tasks, or create an email account to sync habits and focus between devices. Google data never touches our server. Skip to stay fully local.',
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.all(4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () {
                if (_index < 2) {
                  _pages.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                } else {
                  _finish();
                }
              },
              child: Text(_index < 2 ? 'Next' : 'Get started'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
