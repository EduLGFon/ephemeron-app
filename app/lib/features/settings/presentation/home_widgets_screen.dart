import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../../data/services/home_widget_service.dart';

class HomeWidgetsScreen extends StatelessWidget {
  const HomeWidgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home-screen widgets')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Pin a widget to your home screen.'),
            subtitle: Text('Android only; availability depends on your launcher.'),
          ),
          for (final w in homeWidgets)
            ListTile(
              title: Text(w.provider.replaceFirst('WidgetProvider', '')),
              subtitle: Text(w.keyPrefix),
              trailing: TextButton(
                onPressed: () async {
                  try {
                    await HomeWidget.requestPinWidget(
                      androidName: w.provider,
                      qualifiedAndroidName: 'com.spotnik.ephemeron.${w.provider}',
                    );
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pinning not supported here.')),
                      );
                    }
                  }
                },
                child: const Text('Pin'),
              ),
            ),
        ],
      ),
    );
  }
}