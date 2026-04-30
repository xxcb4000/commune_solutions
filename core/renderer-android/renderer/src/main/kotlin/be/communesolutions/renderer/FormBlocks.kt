package be.communesolutions.renderer

import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.HttpURLConnection
import java.net.URL

// Per-screen form state: backing snapshot map + helper to project into a
// JsonObject the templating layer can read as `form.<id>`.
class FormState {
    val values: SnapshotStateMap<String, String> = mutableStateMapOf()

    fun toJsonElement(): JsonElement {
        val out = mutableMapOf<String, JsonElement>()
        for ((k, v) in values) out[k] = JsonPrimitive(v)
        return JsonObject(out)
    }
}

val LocalFormState = compositionLocalOf { FormState() }
val LocalCurrentBaseURL = compositionLocalOf<String?> { null }

@Composable
fun FieldBlock(node: DSLNode) {
    val form = LocalFormState.current
    val kind = node.kind ?: "text"
    val id = node.id ?: ""
    val label = node.label ?: ""
    val placeholder = node.placeholder ?: ""

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (label.isNotEmpty() && kind != "yesno") {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        when (kind) {
            "email" -> OutlinedTextField(
                value = form.values[id] ?: "",
                onValueChange = { form.values[id] = it },
                placeholder = { Text(placeholder) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth()
            )
            "secret" -> OutlinedTextField(
                value = form.values[id] ?: "",
                onValueChange = { form.values[id] = it },
                placeholder = { Text(placeholder) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth()
            )
            "text.long" -> OutlinedTextField(
                value = form.values[id] ?: "",
                onValueChange = { form.values[id] = it },
                placeholder = { Text(placeholder) },
                minLines = node.minLines ?: 4,
                modifier = Modifier.fillMaxWidth()
            )
            "yesno" -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Switch(
                    checked = (form.values[id] ?: "false") == "true",
                    onCheckedChange = { form.values[id] = it.toString() }
                )
                Text(label, modifier = Modifier.fillMaxWidth())
            }
            else -> OutlinedTextField(
                value = form.values[id] ?: "",
                onValueChange = { form.values[id] = it },
                placeholder = { Text(placeholder) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
fun ButtonBlock(node: DSLNode, scope: DSLScope) {
    val form = LocalFormState.current
    val currentModule = LocalCurrentModule.current
    val baseURL = LocalCurrentBaseURL.current
    val coroutineScope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(false) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var feedbackError by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Button(
            onClick = onClick@{
                val action = node.action ?: return@onClick
                when (action.type) {
                    "cf" -> {
                        val endpoint = action.endpoint ?: run {
                            feedback = "Endpoint manquant"; feedbackError = true; return@onClick
                        }
                        val mod = currentModule ?: run {
                            feedback = "Module non résolu"; feedbackError = true; return@onClick
                        }
                        val base = baseURL ?: run {
                            feedback = "baseURL non configurée"; feedbackError = true; return@onClick
                        }
                        loading = true
                        feedback = null
                        coroutineScope.launch {
                            val resolved = mutableMapOf<String, JsonElement>()
                            for ((k, v) in action.body ?: emptyMap()) {
                                resolved[k] = if (v is JsonPrimitive && v.isString) {
                                    JsonPrimitive(Template.resolve(v.content, scope))
                                } else v
                            }
                            val ok = withContext(Dispatchers.IO) {
                                postJson("$base/cf/$mod/$endpoint", JsonObject(resolved))
                            }
                            if (ok) {
                                feedback = "Envoyé."
                                feedbackError = false
                                form.values.clear()
                            } else {
                                feedback = "Erreur serveur"
                                feedbackError = true
                            }
                            loading = false
                        }
                    }
                    else -> {
                        feedback = "Action non gérée: ${action.type}"
                        feedbackError = true
                    }
                }
            },
            enabled = !loading,
            modifier = Modifier.fillMaxWidth()
        ) {
            if (loading) {
                CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(20.dp)
                )
            } else {
                Text(node.label ?: "OK")
            }
        }
        feedback?.let {
            Text(
                text = it,
                color = if (feedbackError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

private fun postJson(url: String, body: JsonObject): Boolean {
    return try {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 5000
            readTimeout = 10000
            requestMethod = "POST"
            doOutput = true
            useCaches = false
            setRequestProperty("Content-Type", "application/json")
        }
        try {
            val payload = SpikeJson.encodeToString(JsonObject.serializer(), body)
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            conn.responseCode in 200..299
        } finally {
            conn.disconnect()
        }
    } catch (e: Exception) {
        Log.e("ButtonBlock", "POST failed", e)
        false
    }
}
