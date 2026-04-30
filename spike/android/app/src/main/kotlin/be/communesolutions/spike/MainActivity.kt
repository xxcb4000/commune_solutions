package be.communesolutions.spike

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import be.communesolutions.renderer.CommuneShell

class MainActivity : ComponentActivity() {
    // Dev Mac IP serving the platform repo over `tools/dev-server.py`.
    // Falls back to bundled JSONs when unreachable.
    private val devServerURL = "http://192.168.129.8:8765"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Configure both Firebase projects; tenant configs reference one via
        // their `firebase` field.
        be.communesolutions.renderer.CommuneFirebase.configure(
            this,
            listOf("spike-1", "spike-2")
        )
        enableEdgeToEdge()
        setContent {
            SpikeTheme {
                Surface(modifier = Modifier, color = MaterialTheme.colorScheme.background) {
                    // No `tenant` param — CommuneShell auto-picks from
                    // SharedPreferences and shows the picker on first launch.
                    CommuneShell(baseURL = devServerURL)
                }
            }
        }
    }
}

@Composable
fun SpikeTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    MaterialTheme(colorScheme = scheme, content = content)
}
