import 'package:ephemeron/data/services/home_widget_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('background callback does not throw', () async {
    await homeWidgetBackgroundCallback(null);
    await homeWidgetBackgroundCallback(Uri.parse('ephemeron://toggle/task/x'));
  });
}