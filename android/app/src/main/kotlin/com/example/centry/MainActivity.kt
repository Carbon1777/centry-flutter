package com.example.centry

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "centry/notification_intents"
    private var methodChannel: MethodChannel? = null
    private var pendingIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val channelId = "centry_invites_v6"
            val channelTitle = "Инвайты и приглашения"
            val channelDescription = "Приглашения в планы и важные действия"

            val channel = NotificationChannel(
                channelId,
                channelTitle,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = channelDescription
                enableVibration(true)
                enableLights(true)
            }

            manager.createNotificationChannel(channel)
        }

        pendingIntent = intent
        logIntent("onCreate", intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        Log.d("CENTRY_PUSH", "configureFlutterEngine: channel ready")

        pendingIntent?.let {
            sendIntentToFlutter(it, source = "onCreate")
            pendingIntent = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        logIntent("onNewIntent", intent)

        if (methodChannel == null) {
            pendingIntent = intent
            return
        }

        sendIntentToFlutter(intent, source = "onNewIntent")
    }

    private fun sendIntentToFlutter(intent: Intent, source: String) {
        try {
            val map = HashMap<String, Any?>()

            map["source"] = source
            map["intent_action"] = intent.action
            map["intent_data"] = intent.dataString

            val extras = intent.extras
            if (extras != null) {
                map["extras"] = bundleToMap(extras)
            } else {
                map["extras"] = emptyMap<String, Any?>()
            }

            Log.d("CENTRY_PUSH", "sendIntentToFlutter source=$source action=${intent.action} data=${intent.dataString} extras=${map["extras"]}")
            methodChannel?.invokeMethod("notification_intent", map)
        } catch (t: Throwable) {
            Log.e("CENTRY_PUSH", "sendIntentToFlutter error", t)
        }
    }

    private fun logIntent(source: String, intent: Intent?) {
        if (intent == null) {
            Log.d("CENTRY_PUSH", "$source intent=null")
            return
        }
        val extrasMap = try {
            intent.extras?.let { bundleToMap(it) }
        } catch (_: Throwable) {
            null
        }
        Log.d(
            "CENTRY_PUSH",
            "$source action=${intent.action} data=${intent.dataString} extras=$extrasMap"
        )
    }

    private fun bundleToMap(bundle: Bundle): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        for (key in bundle.keySet()) {
            val v = bundle.get(key)
            out[key] = when (v) {
                null -> null
                is String -> v
                is Int -> v
                is Long -> v
                is Boolean -> v
                is Double -> v
                is Float -> v
                is Bundle -> bundleToMap(v)
                is Array<*> -> v.map { it?.toString() }
                is IntArray -> v.toList()
                is LongArray -> v.toList()
                is BooleanArray -> v.toList()
                is DoubleArray -> v.toList()
                is FloatArray -> v.toList()
                else -> v.toString()
            }
        }
        return out
    }
}
