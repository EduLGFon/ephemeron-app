// Whether the home_widget plugin has a native host on this platform.
// The plugin ships Android/iOS implementations only. On Linux, Windows,
// macOS, and Web there is no widget host: every channel call fails with
// MissingPluginException. Guard before calling, do not just catch, because
// HomeWidget.renderFlutterWidget fires an unawaited saveWidgetData that
// escapes try/catch and surfaces as an unhandled async error.
import 'package:flutter/foundation.dart';

/// True on Android and iOS; false on desktop, web, and other targets.
bool get isHomeWidgetSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
