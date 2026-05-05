package be.communesolutions.renderer

import android.content.Context
import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreSettings
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

// MARK: - Multi-project Firebase setup

/**
 * Public helper for the consuming app to call once at launch. For each name,
 * loads `firebase/<name>/google-services.json` from assets, builds a
 * [FirebaseOptions], and initializes a named [FirebaseApp]. Tenant configs
 * reference the name via their `firebase` field.
 */
object CommuneFirebase {
    private val configured = mutableSetOf<String>()

    /**
     * Configure les FirebaseApp nommés depuis assets/firebase/<name>/google-services.json.
     *
     * Si `emulatorHost` est fourni (ex: "10.0.2.2" pour l'émulateur Android
     * pointant sur le Mac dev), Auth + Firestore sont routés vers les
     * emulators locaux (ports standards 9099 + 8080).
     */
    fun configure(context: Context, names: List<String>, emulatorHost: String? = null) {
        for (name in names) {
            if (configured.contains(name)) continue
            val opts = loadOptions(context, name)
            if (opts == null) {
                Log.w("CommuneFirebase", "missing config for $name")
                continue
            }
            try {
                val app = FirebaseApp.initializeApp(context, opts, name)
                if (!emulatorHost.isNullOrBlank() && app != null) {
                    FirebaseAuth.getInstance(app).useEmulator(emulatorHost, 9099)
                    val fs = FirebaseFirestore.getInstance(app)
                    fs.useEmulator(emulatorHost, 8080)
                    fs.firestoreSettings = FirebaseFirestoreSettings.Builder()
                        .setPersistenceEnabled(false)
                        .build()
                    Log.i("CommuneFirebase", "configured $name with emulator at $emulatorHost")
                } else {
                    Log.i("CommuneFirebase", "configured $name")
                }
                configured.add(name)
            } catch (e: IllegalStateException) {
                // Already initialized — pre-existing app of the same name.
                configured.add(name)
            }
        }
    }

    fun signOutAll() {
        for (name in configured) {
            runCatching {
                FirebaseAuth.getInstance(FirebaseApp.getInstance(name)).signOut()
            }
        }
    }

    private fun loadOptions(context: Context, name: String): FirebaseOptions? {
        return try {
            val raw = context.assets.open("firebase/$name/google-services.json").bufferedReader().use {
                it.readText()
            }
            val root = SpikeJson.parseToJsonElement(raw).jsonObject
            val projectInfo = root["project_info"]?.jsonObject ?: return null
            val client = root["client"]?.jsonArray?.firstOrNull()?.jsonObject ?: return null
            val clientInfo = client["client_info"]?.jsonObject ?: return null
            val apiKey = (client["api_key"]?.jsonArray?.firstOrNull()?.jsonObject?.get("current_key")
                as? JsonPrimitive)?.content ?: return null
            val projectId = (projectInfo["project_id"] as? JsonPrimitive)?.content ?: return null
            val applicationId = (clientInfo["mobilesdk_app_id"] as? JsonPrimitive)?.content ?: return null

            FirebaseOptions.Builder()
                .setProjectId(projectId)
                .setApplicationId(applicationId)
                .setApiKey(apiKey)
                .setStorageBucket((projectInfo["storage_bucket"] as? JsonPrimitive)?.content)
                .setGcmSenderId((projectInfo["project_number"] as? JsonPrimitive)?.content)
                .build()
        } catch (e: Exception) {
            Log.e("CommuneFirebase", "loadOptions $name", e)
            null
        }
    }
}

// MARK: - Auth state observer

@Composable
fun rememberAuthState(app: FirebaseApp): State<FirebaseUser?> {
    val state = remember(app) { mutableStateOf(FirebaseAuth.getInstance(app).currentUser) }
    DisposableEffect(app) {
        val listener = FirebaseAuth.AuthStateListener { auth ->
            state.value = auth.currentUser
        }
        val instance = FirebaseAuth.getInstance(app)
        instance.addAuthStateListener(listener)
        onDispose { instance.removeAuthStateListener(listener) }
    }
    return state
}

// MARK: - Login form

@Composable
fun LoginForm(firebaseApp: FirebaseApp, tenantTitle: String) {
    val context = LocalContext.current
    val prefs = remember {
        context.getSharedPreferences("communeShell", android.content.Context.MODE_PRIVATE)
    }
    val coroutineScope = rememberCoroutineScope()
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp)
            .padding(top = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = "Connexion",
            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
        )
        Text(
            text = tenantTitle,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = email,
            onValueChange = { email = it; error = null },
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it; error = null },
            label = { Text("Mot de passe") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth()
        )
        if (error != null) {
            Text(
                text = error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.fillMaxWidth()
            )
        }
        Button(
            onClick = {
                loading = true
                error = null
                coroutineScope.launch {
                    try {
                        FirebaseAuth.getInstance(firebaseApp)
                            .signInWithEmailAndPassword(email, password)
                            .await()
                    } catch (e: Exception) {
                        error = e.localizedMessage ?: "Erreur d'authentification"
                    } finally {
                        loading = false
                    }
                }
            },
            enabled = !loading && email.isNotEmpty() && password.isNotEmpty(),
            modifier = Modifier.fillMaxWidth()
        ) {
            if (loading) {
                CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.height(20.dp)
                )
            } else {
                Text("Se connecter")
            }
        }
        TextButton(
            onClick = {
                CommuneFirebase.signOutAll()
                prefs.edit().remove("tenant").apply()
                // The CommuneShell-level state has its own copy of `tenant`;
                // updating SharedPreferences alone won't trigger a recompose
                // until the activity restarts. The user is already logged out
                // anyway — Auth state change cascades back to the shell.
            }
        ) {
            Text("Changer de commune")
        }
    }
}
