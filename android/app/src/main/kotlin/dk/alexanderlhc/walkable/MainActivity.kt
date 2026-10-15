package dk.alexanderlhc.walkable

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    // How Battery Saver treats location right now: one of
                    // PowerManager.LOCATION_MODE_*. Always NO_CHANGE (0) while
                    // Battery Saver is off, and before Android 9 (no API).
                    "locationPowerSaveMode" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            pm.locationPowerSaveMode
                        } else {
                            0
                        }
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
