part of '../microsoft_graph_models.dart';

class MsEmailAddress {
  const MsEmailAddress({this.name, this.address});

  final String? name;
  final String? address;

  factory MsEmailAddress.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsEmailAddress();
    return MsEmailAddress(
      name: m['name'] as String?,
      address: m['address'] as String?,
    );
  }
}

class MsIdentity {
  const MsIdentity({
    required this.id,
    this.displayName,
    this.mail,
    this.userPrincipalName,
  });

  final String id;
  final String? displayName;
  final String? mail;
  final String? userPrincipalName;

  factory MsIdentity.fromMap(Map<String, dynamic> m) {
    return MsIdentity(
      id: (m['id'] as String?) ?? '',
      displayName: m['displayName'] as String?,
      mail: m['mail'] as String?,
      userPrincipalName: m['userPrincipalName'] as String?,
    );
  }
}

class MsCalendar {
  const MsCalendar({
    required this.id,
    required this.name,
    this.color,
    this.hexColor,
    this.isDefaultCalendar = false,
    this.canEdit = false,
    this.owner,
  });

  final String id;
  final String name;
  final String? color;
  final String? hexColor;
  final bool isDefaultCalendar;
  final bool canEdit;
  final MsEmailAddress? owner;

  factory MsCalendar.fromMap(Map<String, dynamic> m) {
    return MsCalendar(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      color: m['color'] as String?,
      hexColor: m['hexColor'] as String?,
      isDefaultCalendar: m['isDefaultCalendar'] as bool? ?? false,
      canEdit: m['canEdit'] as bool? ?? false,
      owner: m['owner'] is Map<String, dynamic>
          ? MsEmailAddress.fromMap(m['owner'] as Map<String, dynamic>)
          : null,
    );
  }
}
