package be.communesolutions.renderer

import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// Walks a screen's `data` declarations, pulls every `firestore:<path>` source
// from the tenant's Firebase project, and returns them as JsonElement values
// keyed by the binding name. Path with even segments → single doc (object);
// odd segments → collection (array of objects).
suspend fun loadFirestoreData(
    dsl: DSLScreen,
    app: FirebaseApp
): Map<String, JsonElement> {
    val result = mutableMapOf<String, JsonElement>()
    val firestore = FirebaseFirestore.getInstance(app)
    for ((key, source) in dsl.data ?: emptyMap()) {
        if (!source.startsWith("firestore:")) continue
        val path = source.removePrefix("firestore:")
        val segments = path.split("/").filter { it.isNotEmpty() }
        try {
            val value: JsonElement = if (segments.size % 2 == 0 && segments.size >= 2) {
                val doc = firestore.document(path).get().await()
                val data = doc.data
                if (data != null) toJsonObject(data) else JsonNull
            } else {
                val snap = firestore.collection(path).get().await()
                JsonArray(snap.documents.map { d ->
                    val data = d.data
                    if (data != null) toJsonObject(data) else JsonNull
                })
            }
            result[key] = value
        } catch (e: Exception) {
            Log.e("ScreenView", "firestore fetch failed $path", e)
        }
    }
    return result
}

private fun toJsonObject(map: Map<String, Any?>): JsonObject {
    val out = mutableMapOf<String, JsonElement>()
    for ((k, v) in map) out[k] = toJsonElement(v)
    return JsonObject(out)
}

private fun toJsonElement(value: Any?): JsonElement {
    return when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value)
        is Long -> JsonPrimitive(value)
        is Double -> JsonPrimitive(value)
        is Float -> JsonPrimitive(value.toDouble())
        is List<*> -> JsonArray(value.map { toJsonElement(it) })
        is Map<*, *> -> {
            @Suppress("UNCHECKED_CAST")
            toJsonObject(value as Map<String, Any?>)
        }
        else -> JsonPrimitive(value.toString())
    }
}
