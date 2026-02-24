import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'config/supabase_config.dart';
import 'app/app.dart';
import 'push/push_notifications.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (kDebugMode) {
      debugPrint('[main] start');
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('[FlutterError] ${details.exceptionAsString()}');
        if (details.stack != null) debugPrint(details.stack.toString());
      }
    };

    if (!kIsWeb) {
      try {
        await Firebase.initializeApp();
        if (kDebugMode) {
          debugPrint('[Firebase] initialized');
        }
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        if (kDebugMode) {
          debugPrint('[Firebase] onBackgroundMessage handler attached');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Firebase] init failed: $e');
        }
      }
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    if (kDebugMode) {
      debugPrint('[Supabase] initialized');
    }

    runApp(const App());
  }, (error, stack) {
    if (kDebugMode) {
      debugPrint('[ZoneError] $error');
      debugPrint(stack.toString());
    }
  });
}
