package be.communesolutions.renderer

import android.content.Context
import android.util.Log
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

val SpikeJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
}

class DSLScope(private val bindings: Map<String, JsonElement> = emptyMap()) {
    fun lookup(path: String): JsonElement? {
        if (path.isEmpty()) return null
        val parts = path.split(".")
        val head = parts.first()
        val root = bindings[head] ?: return null
        if (parts.size == 1) return root
        return root.dslGet(parts.drop(1))
    }

    fun adding(key: String, value: JsonElement): DSLScope =
        DSLScope(bindings + (key to value))
}

object Template {
    // Replace {{ path.to.value }} with stringified bindings; passthrough literal text.
    fun resolve(str: String, scope: DSLScope): String {
        val sb = StringBuilder()
        var i = 0
        while (i < str.length) {
            val open = str.indexOf("{{", i)
            if (open == -1) {
                sb.append(str, i, str.length)
                break
            }
            sb.append(str, i, open)
            val close = str.indexOf("}}", open + 2)
            if (close == -1) {
                sb.append(str, open, str.length)
                break
            }
            val key = str.substring(open + 2, close).trim()
            scope.lookup(key)?.let { sb.append(it.dslString()) }
            i = close + 2
        }
        return sb.toString()
    }

    // If the string is exactly one binding, return the typed JsonElement; otherwise stringify.
    fun resolveValue(str: String, scope: DSLScope): JsonElement {
        val trimmed = str.trim()
        if (trimmed.startsWith("{{") && trimmed.endsWith("}}")) {
            val inner = trimmed.substring(2, trimmed.length - 2).trim()
            if (!inner.contains("{{") && !inner.contains("}}")) {
                return scope.lookup(inner) ?: JsonNull
            }
        }
        return JsonPrimitive(resolve(str, scope))
    }
}

// In-memory cache populated by AssetPreloader at startup. Read by ScreenLoader
// for every JSON access; on miss, ScreenLoader falls back to the consuming
// app's assets so the spike still works fully offline.
object PlatformAssets {
    private val cache = mutableMapOf<String, ByteArray>()
    private val lock = Any()

    fun put(path: String, data: ByteArray) {
        synchronized(lock) { cache[path] = data }
    }

    fun get(path: String): ByteArray? = synchronized(lock) { cache[path] }
}

// Loads platform JSONs (tenant config, manifests, screens, data). Reads from
// PlatformAssets cache when populated, falls back to the consuming app's
// `assets/` directory.
//
// Asset layout (deux roots possibles, modules-official prioritaire) :
//   `tenants/<id>/app.json`
//   `modules-official/<id>/manifest.json`     ← officiels (équipe core)
//   `modules-community/<id>/manifest.json`    ← communauté (PRs externes)
//   `<root>/<id>/<module-relative-path>` (screens, data)
object ScreenLoader {
    val MODULE_ROOTS = listOf("modules-official", "modules-community")
    const val TENANT_ROOT = "tenants"

    fun tenantPath(name: String) = "$TENANT_ROOT/$name/app.json"

    /// Tente de localiser le manifest d'un module en testant chaque root
    /// dans l'ordre. Retourne (root, manifest) ou null si non trouvé.
    fun findManifest(context: Context, moduleId: String): Pair<String, Manifest>? {
        for (root in MODULE_ROOTS) {
            val path = "$root/$moduleId/manifest.json"
            decodeFile<Manifest>(context, path)?.let { return root to it }
        }
        return null
    }

    fun loadTenant(context: Context, name: String): DSLScreen? =
        decodeFile(context, tenantPath(name))

    /// `bundlePath` est le chemin complet déjà préfixé par le root
    /// (résolu via ModuleRegistry).
    fun loadScreen(context: Context, bundlePath: String): DSLScreen? =
        decodeFile(context, bundlePath)

    fun loadData(context: Context, bundlePath: String): JsonElement? {
        val bytes = readBytes(context, bundlePath) ?: return null
        return try {
            SpikeJson.parseToJsonElement(bytes.decodeToString())
        } catch (e: Exception) {
            Log.e("ScreenLoader", "decode error $bundlePath", e)
            null
        }
    }

    private inline fun <reified T> decodeFile(context: Context, path: String): T? {
        val bytes = readBytes(context, path) ?: return null
        return try {
            SpikeJson.decodeFromString<T>(bytes.decodeToString())
        } catch (e: Exception) {
            Log.e("ScreenLoader", "decode error $path", e)
            null
        }
    }

    fun readBytes(context: Context, path: String): ByteArray? {
        PlatformAssets.get(path)?.let { return it }
        return try {
            context.assets.open(path).use { it.readBytes() }
        } catch (e: Exception) {
            Log.w("ScreenLoader", "$path missing in cache and assets")
            null
        }
    }

    fun readAssetBytes(context: Context, path: String): ByteArray? {
        return try {
            context.assets.open(path).use { it.readBytes() }
        } catch (e: Exception) {
            null
        }
    }
}

// Per-tenant runtime context (functionsBaseURL for prod CFs).
// Set when the active tenant config loads; read by ButtonBlock.
object TenantContext {
    var functionsBaseURL: String? = null
}

// Holds module manifests loaded at startup and resolves qualified screen IDs
// (e.g. "actualites:feed") to bundle paths. Object = singleton.
object ModuleRegistry {
    private val manifests = mutableMapOf<String, Manifest>()
    private val roots = mutableMapOf<String, String>()  // moduleId -> root

    fun loadModules(context: Context, refs: List<DSLModuleRef>) {
        for (ref in refs) {
            ScreenLoader.findManifest(context, ref.id)?.let { (root, m) ->
                manifests[ref.id] = m
                roots[ref.id] = root
            }
        }
    }

    /// Le root où ce module est packagé (officiel vs communauté). Utilisé
    /// par le preloader pour fetch les screens/data au bon endroit.
    fun rootOf(moduleId: String): String? = roots[moduleId]

    fun screenPath(qualified: String): String? {
        val parts = qualified.split(":", limit = 2)
        if (parts.size != 2) return null
        val manifest = manifests[parts[0]] ?: return null
        val root = roots[parts[0]] ?: return null
        val rel = manifest.screens[parts[1]] ?: return null
        return "$root/${parts[0]}/$rel"
    }

    fun dataPath(moduleId: String, dataName: String): String? {
        val manifest = manifests[moduleId] ?: return null
        val root = roots[moduleId] ?: return null
        val rel = manifest.data?.get(dataName) ?: return null
        return "$root/$moduleId/$rel"
    }

    fun qualify(screenRef: String, currentModule: String?): String {
        if (screenRef.contains(":")) return screenRef
        return if (currentModule != null) "$currentModule:$screenRef" else screenRef
    }

    fun moduleOf(qualified: String): String? {
        val parts = qualified.split(":", limit = 2)
        return if (parts.size == 2) parts[0] else null
    }
}

// NavHost route value. Always carries a qualified screen ID (`<module>:<screen>`).
@Serializable
data class ScreenRoute(
    val qualifiedScreen: String,
    val bindingsJson: String = "{}",
)

fun encodeBindings(bindings: Map<String, JsonElement>): String =
    SpikeJson.encodeToString(JsonObject.serializer(), JsonObject(bindings))

fun decodeBindings(json: String): Map<String, JsonElement> {
    if (json.isBlank() || json == "{}") return emptyMap()
    return runCatching { SpikeJson.parseToJsonElement(json).jsonObject.toMap() }
        .getOrDefault(emptyMap())
}
