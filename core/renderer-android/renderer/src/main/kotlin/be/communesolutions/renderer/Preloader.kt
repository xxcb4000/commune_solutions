package be.communesolutions.renderer

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import java.net.HttpURLConnection
import java.net.URL

// Async preload of tenant config + module manifests + screens + data.
// Tries HTTP first when `baseURL` is set, falls back to bundled copies.
// Populates `PlatformAssets` so the rest of the rendering stack stays sync.
//
// Phase 11.3 : la liste des modules activés et la nav (`view`) viennent de
// Firestore (`_config/modules`) plutôt que du JSON bundle. Si Firestore
// répond, on patch le JSON tenant en mémoire avant de l'exposer à
// ScreenLoader. Sinon : fallback transparent sur le JSON.
object AssetPreloader {
    suspend fun preload(context: Context, tenant: String, baseURL: String?): PreloadResult {
        val tenantPath = ScreenLoader.tenantPath(tenant)
        var tenantBytes = fetchOrFallback(context, tenantPath, baseURL)
            ?: return PreloadResult.Failed("tenant $tenant introuvable")

        val bootstrap = try {
            SpikeJson.decodeFromString<DSLScreen>(tenantBytes.decodeToString())
        } catch (e: Exception) {
            Log.e("AssetPreloader", "tenant decode error", e)
            return PreloadResult.Failed("tenant $tenant JSON invalide")
        }
        TenantContext.functionsBaseURL = bootstrap.functionsBaseURL

        // Try Firestore override of runtime config (modules + view).
        val firebaseName = bootstrap.firebase
        val projectId = firebaseName?.let {
            runCatching { FirebaseApp.getInstance(it).options.projectId }.getOrNull()
        }
        val runtime = projectId?.let { fetchFirestoreRuntimeConfig(it) }
        if (runtime != null) {
            val patched = applyRuntimeConfig(runtime, tenantBytes)
            if (patched != null) {
                tenantBytes = patched
                Log.i("AssetPreloader", "tenant runtime config from Firestore ($projectId)")
            }
        } else {
            Log.i("AssetPreloader", "tenant runtime config from bundle (Firestore unavailable)")
        }

        PlatformAssets.put(tenantPath, tenantBytes)

        // Re-decode in case we patched.
        val tenantConfig = try {
            SpikeJson.decodeFromString<DSLScreen>(tenantBytes.decodeToString())
        } catch (e: Exception) {
            Log.e("AssetPreloader", "tenant re-decode error", e)
            return PreloadResult.Failed("tenant $tenant JSON invalide après merge")
        }

        for (ref in tenantConfig.modules ?: emptyList()) {
            preloadModule(context, ref, baseURL)
        }

        ModuleRegistry.loadModules(context, tenantConfig.modules ?: emptyList())
        return PreloadResult.Ready
    }

    private suspend fun preloadModule(context: Context, ref: DSLModuleRef, baseURL: String?) {
        // Try chaque root (modules-official prioritaire, puis modules-community)
        // jusqu'à trouver le manifest. Le root résolu est ensuite réutilisé
        // pour fetcher screens + data au bon endroit.
        var resolvedRoot: String? = null
        var manifestBytes: ByteArray? = null
        for (root in ScreenLoader.MODULE_ROOTS) {
            val path = "$root/${ref.id}/manifest.json"
            val bytes = fetchOrFallback(context, path, baseURL)
            if (bytes != null) {
                PlatformAssets.put(path, bytes)
                resolvedRoot = root
                manifestBytes = bytes
                break
            }
        }
        if (resolvedRoot == null || manifestBytes == null) return

        val manifest = try {
            SpikeJson.decodeFromString<Manifest>(manifestBytes.decodeToString())
        } catch (e: Exception) {
            Log.e("AssetPreloader", "manifest decode ${ref.id}", e)
            return
        }

        for ((_, relPath) in manifest.screens) {
            val path = "$resolvedRoot/${ref.id}/$relPath"
            val bytes = fetchOrFallback(context, path, baseURL) ?: continue
            PlatformAssets.put(path, bytes)

            // Walk the screen's data declarations and eagerly fetch any
            // `cf:<endpoint>` source so the renderer can stay synchronous.
            val screen = runCatching {
                SpikeJson.decodeFromString<DSLScreen>(bytes.decodeToString())
            }.getOrNull() ?: continue
            for ((_, source) in screen.data ?: emptyMap()) {
                if (source.startsWith("cf:")) {
                    val endpoint = source.drop(3)
                    val cfBytes = fetchCF(ref.id, endpoint, baseURL)
                    if (cfBytes != null) {
                        PlatformAssets.put(cfCacheKey(ref.id, endpoint), cfBytes)
                    }
                }
            }
        }
        for ((_, relPath) in manifest.data ?: emptyMap()) {
            val path = "$resolvedRoot/${ref.id}/$relPath"
            fetchOrFallback(context, path, baseURL)?.let { PlatformAssets.put(path, it) }
        }
    }

    fun cfCacheKey(moduleId: String, endpoint: String): String = "cf:$moduleId/$endpoint"

    private suspend fun fetchCF(moduleId: String, endpoint: String, baseURL: String?): ByteArray? {
        if (baseURL.isNullOrEmpty()) return null
        return withContext(Dispatchers.IO) { fetchHttp("$baseURL/cf/$moduleId/$endpoint") }
            ?.also { Log.i("AssetPreloader", "CF $moduleId/$endpoint") }
            ?: run {
                Log.w("AssetPreloader", "CF failed $moduleId/$endpoint")
                null
            }
    }

    private suspend fun fetchOrFallback(context: Context, path: String, baseURL: String?): ByteArray? {
        if (!baseURL.isNullOrEmpty()) {
            val httpResult = withContext(Dispatchers.IO) { fetchHttp("$baseURL/$path") }
            if (httpResult != null) {
                Log.i("AssetPreloader", "HTTP $path")
                return httpResult
            }
            Log.i("AssetPreloader", "HTTP failed $path → bundle")
        }
        return ScreenLoader.readAssetBytes(context, path)?.also {
            Log.i("AssetPreloader", "bundle $path")
        }
    }

    private fun fetchHttp(url: String): ByteArray? {
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 3000
                readTimeout = 5000
                requestMethod = "GET"
                // Bypass HttpURLConnection / response cache so the spike
                // picks up dev-server edits between launches.
                useCaches = false
                setRequestProperty("Cache-Control", "no-cache")
            }
            try {
                if (conn.responseCode != 200) return null
                conn.inputStream.use { it.readBytes() }
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            null
        }
    }

    // MARK: - Firestore runtime config

    // GET _config/modules via REST. Public read côté rules, pas d'auth requis :
    // utile car le preloader tourne avant le login. Format de réponse :
    // Firestore typed JSON (stringValue, arrayValue, mapValue) reconverti en
    // JsonElement plain via `unwrapFirestoreValue`.
    private suspend fun fetchFirestoreRuntimeConfig(projectId: String): JsonObject? {
        val url = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/_config/modules"
        val bytes = withContext(Dispatchers.IO) {
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3000
                    readTimeout = 5000
                    requestMethod = "GET"
                    useCaches = false
                }
                try {
                    if (conn.responseCode != 200) {
                        Log.i("AssetPreloader", "Firestore _config/modules HTTP ${conn.responseCode}")
                        null
                    } else {
                        conn.inputStream.use { it.readBytes() }
                    }
                } finally {
                    conn.disconnect()
                }
            } catch (e: Exception) {
                Log.i("AssetPreloader", "Firestore _config/modules fetch error: ${e.message}")
                null
            }
        } ?: return null

        return try {
            val json = SpikeJson.parseToJsonElement(bytes.decodeToString()) as? JsonObject ?: return null
            val fields = json["fields"] as? JsonObject ?: return null
            val out = mutableMapOf<String, JsonElement>()
            for ((k, v) in fields) {
                unwrapFirestoreValue(v)?.let { out[k] = it }
            }
            JsonObject(out)
        } catch (e: Exception) {
            Log.w("AssetPreloader", "Firestore _config/modules parse error", e)
            null
        }
    }

    private fun unwrapFirestoreValue(v: JsonElement): JsonElement? {
        val obj = v as? JsonObject ?: return null
        (obj["stringValue"] as? JsonPrimitive)?.contentOrNull?.let { return JsonPrimitive(it) }
        (obj["booleanValue"] as? JsonPrimitive)?.booleanOrNull?.let { return JsonPrimitive(it) }
        (obj["integerValue"] as? JsonPrimitive)?.contentOrNull?.toLongOrNull()?.let { return JsonPrimitive(it) }
        (obj["doubleValue"] as? JsonPrimitive)?.doubleOrNull?.let { return JsonPrimitive(it) }
        if (obj["nullValue"] != null) return JsonNull
        (obj["arrayValue"] as? JsonObject)?.let { arr ->
            val values = arr["values"] as? JsonArray ?: return JsonArray(emptyList())
            return JsonArray(values.mapNotNull { unwrapFirestoreValue(it) })
        }
        (obj["mapValue"] as? JsonObject)?.let { map ->
            val fields = map["fields"] as? JsonObject ?: return JsonObject(emptyMap())
            val out = mutableMapOf<String, JsonElement>()
            for ((k, mv) in fields) {
                unwrapFirestoreValue(mv)?.let { out[k] = it }
            }
            return JsonObject(out)
        }
        return null
    }

    // Patche le JSON tenant : remplace les clés `modules` et `view` par les
    // valeurs venues de Firestore. Garde les autres clés (tenant, firebase,
    // functionsBaseURL) intactes — elles restent du bootstrap.
    private fun applyRuntimeConfig(runtime: JsonObject, tenantBytes: ByteArray): ByteArray? {
        return try {
            val tenantJson = SpikeJson.parseToJsonElement(tenantBytes.decodeToString()) as? JsonObject ?: return null
            val merged = tenantJson.toMutableMap()
            runtime["modules"]?.let { merged["modules"] = it }
            runtime["view"]?.let { merged["view"] = it }
            SpikeJson.encodeToString(JsonObject.serializer(), JsonObject(merged)).encodeToByteArray()
        } catch (e: Exception) {
            Log.w("AssetPreloader", "applyRuntimeConfig error", e)
            null
        }
    }
}

sealed class PreloadResult {
    data object Ready : PreloadResult()
    data class Failed(val message: String) : PreloadResult()
}
