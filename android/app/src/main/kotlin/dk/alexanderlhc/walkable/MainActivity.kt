package dk.alexanderlhc.walkable

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The Battery Saver receiver while Dart listens; see configureFlutterEngine.
    private var powerSaveReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge for Android 15: draw behind the system bars. Flutter's
        // FlutterActivity extends a plain Activity, so the androidx.activity
        // enableEdgeToEdge() extension (ComponentActivity-only) isn't available;
        // WindowCompat is the equivalent on a bare Window.
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "walkable/power")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "locationPowerSaveMode" -> result.success(locationPowerSaveMode())
                    // Battery Saver's settings page, or the battery page where
                    // a phone has none. Each is resolved before launching:
                    // OEM builds drop or rename Settings activities.
                    "openBatterySaverSettings" -> result.success(
                        openFirstResolvable(
                            Settings.ACTION_BATTERY_SAVER_SETTINGS,
                            Intent.ACTION_POWER_USAGE_SUMMARY,
                        )
                    )
                    "manufacturer" -> result.success(Build.MANUFACTURER)
                    else -> result.notImplemented()
                }
            }
        // Emits locationPowerSaveMode() on listen and each time Battery Saver
        // switches on or off, so a walk in progress notices it mid-walk. The
        // receiver lives only while Dart listens (a walk is recording), and as
        // a context-registered receiver it keeps receiving with the screen off
        // for as long as the foreground service keeps the process alive.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "walkable/power/locationPowerSaveMode",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                unregisterPowerSaveReceiver()
                val r = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        events.success(locationPowerSaveMode())
                    }
                }
                ContextCompat.registerReceiver(
                    applicationContext,
                    r,
                    IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
                    // A system broadcast: other apps need not reach it.
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                powerSaveReceiver = r
                // The broadcast isn't sticky: report the mode now too, so a
                // switch between Dart's start check and this listen isn't lost.
                events.success(locationPowerSaveMode())
            }

            override fun onCancel(arguments: Any?) = unregisterPowerSaveReceiver()
        })
    }

    // The engine can go without Dart cancelling its stream; don't leave the
    // receiver behind on the application context.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        unregisterPowerSaveReceiver()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun unregisterPowerSaveReceiver() {
        powerSaveReceiver?.let { applicationContext.unregisterReceiver(it) }
        powerSaveReceiver = null
    }

    // How Battery Saver treats location right now: one of
    // PowerManager.LOCATION_MODE_*. Always NO_CHANGE (0) while Battery Saver
    // is off, and before Android 9 (no API).
    private fun locationPowerSaveMode(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.locationPowerSaveMode
        } else {
            0
        }

    // Starts the first of [actions] some activity handles. Returns whether one
    // started.
    private fun openFirstResolvable(vararg actions: String): Boolean {
        for (action in actions) {
            val intent = Intent(action)
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                return true
            }
        }
        return false
    }
}
