package be.communesolutions.renderer

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// `map` primitive — Android stub for the spike. Renders a placeholder card
// showing the place count. Real implementation will use `maps-compose`
// (Google Maps) in a follow-up session when the Android device is available.
//
// Same DSL contract as iOS: `in: <places>`, `latField`, `lngField`,
// `categoryField`, `from: <single>`, `height`, `action`.
@Composable
fun MapBlock(node: DSLNode, scope: DSLScope) {
    val height = (node.height ?: 280.0).dp
    val placeCount = if (node.from != null) {
        if (scope.lookup(node.from) != null) 1 else 0
    } else {
        scope.lookup(node.iterable ?: "")?.dslArray()?.size ?: 0
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFFEFEAE0)),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Filled.Map,
                contentDescription = null,
                tint = Color(0xFF2C4A6B),
                modifier = Modifier.size(40.dp)
            )
            Spacer(Modifier.size(8.dp))
            Text(
                text = "Carte — $placeCount lieu${if (placeCount > 1) "x" else ""}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
                color = Color(0xFF1F2937)
            )
            Text(
                text = "(stub Android — port maps-compose à venir)",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF6B7280)
            )
        }
    }
}
