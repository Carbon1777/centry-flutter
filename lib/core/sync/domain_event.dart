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
    required DomainChangeType changeType,
    required DateTime receivedAt,
    required Map<String, dynamic> raw,
  }) : super(
         table: 'users',
         changeType: changeType,
         receivedAt: receivedAt,
         raw: raw,
       );
}

@immutable
class UserUpserted extends UserDomainEvent {
  final Map<String, dynamic>? userRow;

  const UserUpserted({
    required String userId,
    required DomainChangeType changeType,
    required DateTime receivedAt,
    required Map<String, dynamic> raw,
    required this.userRow,
  }) : super(
         userId: userId,
         changeType: changeType,
         receivedAt: receivedAt,
         raw: raw,
       );
}

@immutable
class UserDeleted extends UserDomainEvent {
  final Map<String, dynamic>? oldRow;

  const UserDeleted({
    required String userId,
    required DateTime receivedAt,
    required Map<String, dynamic> raw,
    required this.oldRow,
  }) : super(
         userId: userId,
         changeType: DomainChangeType.delete,
         receivedAt: receivedAt,
         raw: raw,
       );
}
