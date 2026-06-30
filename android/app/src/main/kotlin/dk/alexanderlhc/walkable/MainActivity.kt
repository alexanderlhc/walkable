package dk.alexanderlhc.walkable

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge for Android 15: draw behind the system bars. Flutter's
        // FlutterActivity extends a plain Activity, so the androidx.activity
        // enableEdgeToEdge() extension (ComponentActivity-only) isn't available;
        // WindowCompat is the equivalent on a bare Window.
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
