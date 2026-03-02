import 'package:flutter/foundation.dart';

/// A tiny in-process signal used to request a Friends list refresh.
///
/// Why it exists:
/// - We want server-first facts, but the Friends screen is often kept alive
///   (tab navigation / IndexedStack), so it does not refetch automatically.
/// - Realtime on `public.friendships` may be unavailable depending on project
///   realtime/publication settings.
///
/// The app-level notification router (app.dart) bumps this signal after:
/// - accepting/declining a friend request (invitee)
/// - receiving the result notification (inviter)
///
/// FriendsScreen listens and refetches via repository.
class FriendsRefreshBus {
  FriendsRefreshBus._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void bump() {
    tick.value = tick.value + 1;
  }
}
