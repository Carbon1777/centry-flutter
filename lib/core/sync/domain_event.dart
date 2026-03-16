import 'package:flutter/foundation.dart';

enum DomainChangeType { insert, update, delete, unknown }

@immutable
abstract class DomainEvent {
  final String table;
  final DomainChangeType changeType;
  final DateTime receivedAt;
  final Map<String, dynamic> raw;

  const DomainEvent({
    required this.table,
    required this.changeType,
    required this.receivedAt,
    required this.raw,
  });
}

@immutable
abstract class UserDomainEvent extends DomainEvent {
  final String userId;

  const UserDomainEvent({
    required this.userId,
    required super.changeType,
    required super.receivedAt,
    required super.raw,
  }) : super(table: 'users');
}

@immutable
class UserUpserted extends UserDomainEvent {
  final Map<String, dynamic>? userRow;

  const UserUpserted({
    required super.userId,
    required super.changeType,
    required super.receivedAt,
    required super.raw,
    required this.userRow,
  });
}

@immutable
class UserDeleted extends UserDomainEvent {
  final Map<String, dynamic>? oldRow;

  const UserDeleted({
    required super.userId,
    required super.receivedAt,
    required super.raw,
    required this.oldRow,
  }) : super(changeType: DomainChangeType.delete);
}
