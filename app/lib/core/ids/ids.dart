import 'package:uuid/uuid.dart';

// UUIDv7 generator (time-ordered) for primary keys.
const Uuid _uuid = Uuid();

String newId() => _uuid.v7();
