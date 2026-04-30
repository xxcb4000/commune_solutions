package be.communesolutions.renderer

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

// Async preload of tenant config + module manifests + screens + data.
// Tries HTTP first when `baseURL` is set, falls back to bundled copies.
// Populates `PlatformAssets` so the rest of the rendering stack stays sync.
object AssetPreloader {
    suspend fun preload(context: Context, tenant: String, baseURL: String?): PreloadResult {
        val tenantPath = ScreenLoader.tenantPath(tenant)
        val tenantBytes = fetchOrFallback(context, tenantPath, baseURL)
            ?: return PreloadResult.Failed("tenant $tenant introuvable")
        PlatformAssets.put(tenantPath, tenantBytes)

        val tenantConfig = try {
            SpikeJson.decodeFromString<DSLScreen>(tenantBytes.decodeToString())
        } catch (e: Exception) {
            Log.e("AssetPreloader", "tenant decode error", e)
            return PreloadResult.Failed("tenant $tenant JSON invalide")
        }
        TenantContext.functionsBaseURL = tenantConfig.functionsBaseURL

        for (ref in tenantConfig.modules ?: emptyList()) {
            preloadModule(context, ref, baseURL)
        }

        ModuleRegistry.loadModules(context, tenantConfig.modules ?: emptyList())
        return PreloadResult.Ready
    }

    private suspend fun preloadModule(context: Context, ref: DSLModuleRef, baseURL: String?) {
        val manifestPath = ScreenLoader.manifestPath(ref.id)
        val manifestBytes = fetchOrFallback(context, manifestPath, baseURL) ?: return
        PlatformAssets.put(manifestPath, manifestBytes)

        val manifest = try {
            SpikeJson.decodeFromString<Manifest>(manifestBytes.decodeToString())
        } catch (e: Exception) {
            Log.e("AssetPreloader", "manifest decode ${ref.id}", e)
            return
        }

        for ((_, relPath) in manifest.screens) {
            val path = ScreenLoader.modulePath("${ref.id}/$relPath")
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
            val path = ScreenLoader.modulePath("${ref.id}/$relPath")
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
}

sealed class PreloadResult {
    data object Ready : PreloadResult()
    data class Failed(val message: String) : PreloadResult()
}
