// Shared bottom padding for modal sheets that must stay above the
// on-screen keyboard.
import 'package:flutter/material.dart';

EdgeInsets sheetPadding(BuildContext context) => EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
    );