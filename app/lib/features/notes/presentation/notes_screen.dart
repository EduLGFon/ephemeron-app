// Notes screen: nested folders with breadcrumbs, note list with counts,
// FTS search with snippets, trash, new note / new folder.
//
// Split across `notes_screen/` parts; this file stays the stable import
// path for callers.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ephemeron/core/ui/dialogs.dart';

import 'package:ephemeron/core/ui/empty_state.dart';
import 'package:ephemeron/core/ui/app_sheet.dart';
import 'package:ephemeron/core/ui/escape_to_close.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/drift/app_database.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../application/notes_providers.dart';
import 'note_editor_screen.dart';

part 'notes_screen/notes_screen_view.dart';
part 'notes_screen/breadcrumbs.dart';
part 'notes_screen/search_results.dart';
part 'notes_screen/trash_screen.dart';
part 'notes_screen/error_state.dart';
