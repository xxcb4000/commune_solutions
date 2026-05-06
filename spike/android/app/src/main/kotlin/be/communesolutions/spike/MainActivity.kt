package be.communesolutions.spike

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import be.communesolutions.renderer.CommunePushService
import be.communesolutions.renderer.CommuneShell

class MainActivity : ComponentActivity() {
    // Dev Mac IP serving the platform repo over `tools/dev-server.py`.
    // Falls back to bundled JSONs when unreachable.
    private val devServerURL = "http://192.168.129.8:8765"

    private val notifPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) CommunePushService.ensureChannelAndPersistToken(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Single-commune build : `BuildConfig.COMMUNE_TENANT_ID` est baké
        // par Gradle quand `-PcommuneId=<id>` est passé (cf
        // `tools/build-commune-app.sh`). Vide = mode dev multi-tenant
        // (les deux Firebase configs + picker).
        val bakedTenant = BuildConfig.COMMUNE_TENANT_ID.takeIf { it.isNotBlank() }
        val firebaseProjects = BuildConfig.COMMUNE_FIREBASE_PROJECTS
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .ifEmpty { listOf("spike-1", "spike-2") }

        // Si non vide, Auth + Firestore SDK pointent sur les emulators
        // locaux. Set par tools/dev-emulators.sh via `-PfirebaseEmulatorHost`.
        // Pour l'émulateur Android pointant sur le Mac dev, utiliser 10.0.2.2.
        val emulatorHost = BuildConfig.FIREBASE_EMULATOR_HOST.takeIf { it.isNotBlank() }

        be.communesolutions.renderer.CommuneFirebase.configure(this, firebaseProjects, emulatorHost)

        // Notifications push v0 — permission runtime (Android 13+) puis
        // persistance du token FCM dans Firestore (à tous les Firebase apps
        // configurés). En multi-tenant dev, le token sera réécrit après
        // chaque login utilisateur via le state listener du SDK.
        CommunePushService.configuredAppNames = firebaseProjects
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (granted) {
                CommunePushService.ensureChannelAndPersistToken(this)
            } else {
                notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        } else {
            CommunePushService.ensureChannelAndPersistToken(this)
        }

        enableEdgeToEdge()
        setContent {
            SpikeTheme {
                Surface(modifier = Modifier, color = MaterialTheme.colorScheme.background) {
                    // bakedTenant != null → single-commune mode (no picker)
                    // bakedTenant == null → multi-tenant dev (picker actif
                    //   ou tenant en SharedPreferences)
                    CommuneShell(tenant = bakedTenant, baseURL = devServerURL)
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
