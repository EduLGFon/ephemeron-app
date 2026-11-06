// Focused settings controls: section headers, dropdown rows, color presets,
// brightness chips, and custom hex fields. Keeping them separate keeps the
// settings screen focused on composition.
//
// Split across `part` files under `settings_widgets/` (U10b); this file is the
// stable public entry point.
import 'package:flutter/material.dart';

import '../../../core/theme/theme_tokens.dart';

part 'settings_widgets/section_header.dart';
part 'settings_widgets/picker_tile.dart';
part 'settings_widgets/color_preset_picker.dart';
part 'settings_widgets/brightness_selector.dart';
part 'settings_widgets/hex_color_field.dart';
