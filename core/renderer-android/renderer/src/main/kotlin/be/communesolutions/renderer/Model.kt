package be.communesolutions.renderer

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

@Serializable
data class DSLAction(
    val type: String,
    val to: String? = null,
    val with: Map<String, JsonElement>? = null,
)

@Serializable
data class DSLTab(
    val title: String,
    val icon: String,
    val screen: String,
    val bindings: Map<String, JsonElement>? = null,
)

@Serializable
data class DSLNavigation(
    val title: String? = null,
    val displayMode: String? = null,
)

@Serializable
data class DSLNode(
    val type: String,
    val title: String? = null,
    val subtitle: String? = null,
    val value: String? = null,
    val url: String? = null,
    val imageUrl: String? = null,
    val style: String? = null,
    val color: String? = null,
    val height: Double? = null,
    val spacing: Double? = null,
    val padding: Double? = null,
    val aspectRatio: Double? = null,
    val refreshable: Boolean? = null,
    val condition: String? = null,
    @SerialName("in") val iterable: String? = null,
    @SerialName("as") val alias: String? = null,
    val dateField: String? = null,
    val action: DSLAction? = null,
    val children: List<DSLNode>? = null,
    val child: DSLNode? = null,
    val then: DSLNode? = null,
    @SerialName("else") val elseNode: DSLNode? = null,
    val tabs: List<DSLTab>? = null,
)

@Serializable
data class DSLScreen(
    val screen: String? = null,
    val tenant: String? = null,
    val firebase: String? = null,
    val navigation: DSLNavigation? = null,
    val data: Map<String, String>? = null,
    val view: DSLNode,
    val modules: List<DSLModuleRef>? = null,
)

@Serializable
data class DSLModuleRef(
    val id: String,
    val version: String,
)

@Serializable
data class Manifest(
    val id: String,
    val version: String,
    val displayName: String,
    val icon: String? = null,
    val screens: Map<String, String>,
    val data: Map<String, String>? = null,
)

// Helpers on JsonElement to mirror iOS DSLValue's stringValue / boolValue / arrayValue / get(path).
fun JsonElement.dslString(): String = when (this) {
    is JsonNull -> ""
    is JsonPrimitive -> content
    is JsonArray -> joinToString(", ") { it.dslString() }
    is JsonObject -> "[object]"
}

fun JsonElement.dslBool(): Boolean = when (this) {
    is JsonNull -> false
    is JsonPrimitive -> {
        if (isString) content.isNotEmpty() && content != "false" && content != "0"
        else content == "true" || (content.toDoubleOrNull()?.let { it != 0.0 } ?: false)
    }
    is JsonArray -> isNotEmpty()
    is JsonObject -> isNotEmpty()
}

fun JsonElement.dslArray(): List<JsonElement>? = (this as? JsonArray)?.toList()

fun JsonElement.dslGet(path: List<String>): JsonElement? {
    var current: JsonElement = this
    for (part in path) {
        current = when (current) {
            is JsonObject -> current[part] ?: return null
            is JsonArray -> {
                val idx = part.toIntOrNull() ?: return null
                if (idx < 0 || idx >= current.size) return null
                current[idx]
            }
            else -> return null
        }
    }
    return current
}
