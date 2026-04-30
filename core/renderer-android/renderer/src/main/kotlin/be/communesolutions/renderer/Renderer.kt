package be.communesolutions.renderer

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

// MARK: - Public entry point

/**
 * Top-level shell.
 *
 * On first launch (no tenant chosen yet), shows a native picker. The choice is
 * persisted via SharedPreferences and survives app restarts. After login the
 * shell hands off to TenantHost, which preloads the chosen tenant and renders.
 *
 * Phase 4a: tenant picker is hardcoded; auth is implicit (just selecting).
 * Phase 4b will swap this for Firebase Auth.
 */
@Composable
fun CommuneShell(tenant: String? = null, baseURL: String? = null) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("communeShell", android.content.Context.MODE_PRIVATE) }
    var storedTenant by remember { mutableStateOf(prefs.getString("tenant", "") ?: "") }

    val activeTenant = tenant ?: storedTenant
    val logout = {
        prefs.edit().remove("tenant").apply()
        storedTenant = ""
    }
    if (activeTenant.isEmpty()) {
        TenantPicker { picked ->
            prefs.edit().putString("tenant", picked).apply()
            storedTenant = picked
        }
    } else {
        CompositionLocalProvider(
            LocalLogout provides logout,
            LocalCurrentBaseURL provides baseURL
        ) {
            // Recreate TenantHost (and its preloader state) when tenant changes.
            androidx.compose.runtime.key(activeTenant) {
                TenantHost(tenantId = activeTenant, baseURL = baseURL)
            }
        }
    }
}

@Composable
private fun TenantPicker(onPick: (String) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Commune Solutions",
            style = MaterialTheme.typography.headlineMedium.copy(
                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold
            )
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = "Sélectionnez votre commune",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(24.dp))
        PickerCard(title = "Démo A", subtitle = "Tenant test #1") { onPick("spike") }
        Spacer(Modifier.height(12.dp))
        PickerCard(title = "Démo B", subtitle = "Tenant test #2") { onPick("spike-2") }
        Spacer(Modifier.height(32.dp))
        Text(
            text = "Phase 4a — choix mock. Auth Firebase à venir en 4b.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PickerCard(title: String, subtitle: String, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = null,
                modifier = Modifier
                    .rotate(180f)
                    .size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun TenantHost(tenantId: String, baseURL: String?) {
    val context = LocalContext.current
    var state by remember(tenantId) { mutableStateOf<PreloadResult?>(null) }

    LaunchedEffect(tenantId, baseURL) {
        state = AssetPreloader.preload(context, tenantId, baseURL)
    }

    when (val s = state) {
        null -> LoadingView()
        is PreloadResult.Failed -> FallbackNotFound(s.message)
        PreloadResult.Ready -> AuthGate(tenantId)
    }
}

@Composable
private fun AuthGate(tenantId: String) {
    val context = LocalContext.current
    val tenantConfig = remember(tenantId) { ScreenLoader.loadTenant(context, tenantId) }
    val firebaseName = tenantConfig?.firebase
    val firebaseApp = remember(firebaseName) {
        firebaseName?.let { runCatching { com.google.firebase.FirebaseApp.getInstance(it) }.getOrNull() }
    }

    if (tenantConfig == null || firebaseApp == null) {
        FallbackNotFound("tenant $tenantId — config Firebase manquante")
        return
    }

    val user by rememberAuthState(firebaseApp)
    if (user == null) {
        LoginForm(firebaseApp = firebaseApp, tenantTitle = tenantId)
    } else {
        CompositionLocalProvider(LocalCurrentFirebaseApp provides firebaseApp) {
            RenderTenant(tenantId)
        }
    }
}

@Composable
private fun LoadingView() {
    Column(
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxSize()
    ) {
        androidx.compose.material3.CircularProgressIndicator()
        Spacer(Modifier.height(12.dp))
        Text(
            text = "Chargement des modules…",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun RenderTenant(tenant: String) {
    val context = LocalContext.current
    val tenantConfig = remember(tenant) { ScreenLoader.loadTenant(context, tenant) }

    if (tenantConfig == null) {
        FallbackNotFound("tenant $tenant")
        return
    }

    if (tenantConfig.view.type == "tabbar") {
        TabBarRoot(tenantConfig.view)
    } else {
        SingleNavStack(startQualifiedScreen = "", startBindings = emptyMap())
    }
}

// CompositionLocal carrying the module that owns the screen currently being
// rendered. CardBlock reads this to qualify unqualified `navigate.to` targets.
val LocalCurrentModule = compositionLocalOf<String?> { null }

// Logout callback. CommuneShell installs a real implementation that clears
// the persisted tenant; nested cards trigger it via `action.type == "logout"`.
val LocalLogout = compositionLocalOf<() -> Unit> { {} }

// FirebaseApp owned by the active tenant. ScreenView reads this to query
// Firestore collections referenced by `firestore:<path>` data sources.
val LocalCurrentFirebaseApp = compositionLocalOf<com.google.firebase.FirebaseApp?> { null }

@Composable
fun TabBarRoot(node: DSLNode) {
    var selectedIndex by rememberSaveable { mutableIntStateOf(0) }
    val tabs = node.tabs ?: emptyList()

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selectedIndex == index,
                        onClick = { selectedIndex = index },
                        icon = {
                            Icon(
                                imageVector = iconForName(tab.icon),
                                contentDescription = null
                            )
                        },
                        label = { Text(tab.title) }
                    )
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            tabs.getOrNull(selectedIndex)?.let { tab ->
                // Re-key the nav stack per tab so each maintains a fresh history
                // when switched. (Spike-acceptable: back-stack resets on tab switch.)
                androidx.compose.runtime.key(selectedIndex) {
                    SingleNavStack(
                        startQualifiedScreen = tab.screen,
                        startBindings = tab.bindings ?: emptyMap()
                    )
                }
            }
        }
    }
}

@Composable
fun SingleNavStack(startQualifiedScreen: String, startBindings: Map<String, JsonElement>) {
    val nav = rememberNavController()
    NavHost(
        navController = nav,
        startDestination = ScreenRoute(
            qualifiedScreen = startQualifiedScreen,
            bindingsJson = encodeBindings(startBindings)
        )
    ) {
        composable<ScreenRoute> { entry ->
            val route: ScreenRoute = entry.toRoute()
            ScreenView(
                qualifiedScreen = route.qualifiedScreen,
                initialBindings = decodeBindings(route.bindingsJson),
                nav = nav
            )
        }
    }
}

// MARK: - Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenView(
    qualifiedScreen: String,
    initialBindings: Map<String, JsonElement>,
    nav: NavController
) {
    val context = LocalContext.current
    val resolved = remember(qualifiedScreen) {
        ModuleRegistry.screenPath(qualifiedScreen)?.let { path ->
            ScreenLoader.loadScreen(context, path)
        }
    }
    val currentModule = remember(qualifiedScreen) {
        ModuleRegistry.moduleOf(qualifiedScreen)
    }

    if (resolved == null) {
        FallbackNotFound(qualifiedScreen)
        return
    }

    var firestoreData by remember(qualifiedScreen) {
        mutableStateOf<Map<String, JsonElement>>(emptyMap())
    }
    val firebaseApp = LocalCurrentFirebaseApp.current
    val form = remember(qualifiedScreen) { FormState() }

    LaunchedEffect(qualifiedScreen, firebaseApp) {
        if (firebaseApp != null) {
            firestoreData = loadFirestoreData(resolved, firebaseApp)
        }
    }

    // Form values are a SnapshotStateMap; reading inside the scope-builder
    // makes the scope re-derive on each form change (no explicit remember key
    // needed — Compose tracks the snapshot reads).
    val scope = run {
        var s = DSLScope(initialBindings)
        s = s.adding("form", form.toJsonElement())
        for ((key, source) in resolved.data ?: emptyMap()) {
            if (currentModule == null) continue
            when {
                source.startsWith("@") -> {
                    val dataName = source.drop(1)
                    val path = ModuleRegistry.dataPath(currentModule, dataName)
                    if (path != null) {
                        ScreenLoader.loadData(context, path)?.let { s = s.adding(key, it) }
                    }
                }
                source.startsWith("cf:") -> {
                    val endpoint = source.drop(3)
                    val cacheKey = AssetPreloader.cfCacheKey(currentModule, endpoint)
                    PlatformAssets.get(cacheKey)?.let { bytes ->
                        runCatching { SpikeJson.parseToJsonElement(bytes.decodeToString()) }
                            .getOrNull()
                            ?.let { s = s.adding(key, it) }
                    }
                }
                source.startsWith("firestore:") -> {
                    firestoreData[key]?.let { s = s.adding(key, it) }
                }
            }
        }
        s
    }
    @Suppress("UNUSED_VARIABLE")
    val _formProvider = form  // keep `form` in scope; provided below

    val title = Template.resolve(resolved.navigation?.title ?: "", scope)
    val showBack = nav.previousBackStackEntry != null

    CompositionLocalProvider(
        LocalCurrentModule provides currentModule,
        LocalFormState provides form
    ) {
        Scaffold(
            topBar = {
                if (title.isNotEmpty() || showBack) {
                    TopAppBar(
                        title = { Text(title) },
                        navigationIcon = {
                            if (showBack) {
                                IconButton(onClick = { nav.popBackStack() }) {
                                    Icon(
                                        Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = "Retour"
                                    )
                                }
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors()
                    )
                }
            }
        ) { padding ->
            Box(modifier = Modifier.padding(padding)) {
                DSLView(resolved.view, scope, nav)
            }
        }
    }
}

@Composable
fun FallbackNotFound(screen: String) {
    Column(
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        Icon(
            imageVector = Icons.Filled.WarningAmber,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(12.dp))
        Text("Écran introuvable", style = MaterialTheme.typography.titleMedium)
        Text(
            "$screen.json n'a pas été trouvé.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

// MARK: - Dispatcher

@Composable
fun DSLView(node: DSLNode, scope: DSLScope, nav: NavController) {
    when (node.type) {
        "scroll" -> ScrollContainer(node, scope, nav)
        "vstack" -> VStackContainer(node, scope, nav)
        "hstack" -> HStackContainer(node, scope, nav)
        "header" -> HeaderBlock(node, scope)
        "card" -> CardBlock(node, scope, nav)
        "image" -> ImageBlock(node, scope)
        "text" -> TextBlock(node, scope)
        "markdown" -> MarkdownBlock(node, scope)
        "for" -> ForBlock(node, scope, nav)
        "if" -> IfBlock(node, scope, nav)
        "tabbar" -> TabBarRoot(node)
        "calendar" -> CalendarBlock(node, scope)
        "field" -> FieldBlock(node, scope)
        "button" -> ButtonBlock(node, scope)
        else -> Text(
            "Unknown: ${node.type}",
            color = Color.Red,
            modifier = Modifier
                .background(Color.Red.copy(alpha = 0.1f))
                .padding(8.dp)
        )
    }
}

// MARK: - Layout blocks

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScrollContainer(node: DSLNode, scope: DSLScope, nav: NavController) {
    val refreshable = node.refreshable == true
    val scrollState = rememberScrollState()

    val content: @Composable () -> Unit = {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(scrollState)
        ) {
            node.children?.forEach { child ->
                DSLView(child, scope, nav)
            }
        }
    }

    if (refreshable) {
        var isRefreshing by remember { mutableStateOf(false) }
        val coroutineScope = rememberCoroutineScope()
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                coroutineScope.launch {
                    isRefreshing = true
                    delay(600)
                    isRefreshing = false
                }
            }
        ) {
            content()
        }
    } else {
        content()
    }
}

@Composable
fun VStackContainer(node: DSLNode, scope: DSLScope, nav: NavController) {
    Column(
        verticalArrangement = Arrangement.spacedBy((node.spacing ?: 8.0).dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding((node.padding ?: 0.0).dp)
    ) {
        node.children?.forEach { child ->
            DSLView(child, scope, nav)
        }
    }
}

@Composable
fun HStackContainer(node: DSLNode, scope: DSLScope, nav: NavController) {
    Row(
        horizontalArrangement = Arrangement.spacedBy((node.spacing ?: 8.0).dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding((node.padding ?: 0.0).dp)
    ) {
        node.children?.forEach { child ->
            DSLView(child, scope, nav)
        }
    }
}

// MARK: - Leaf blocks

@Composable
fun HeaderBlock(node: DSLNode, scope: DSLScope) {
    val title = Template.resolve(node.title ?: "", scope)
    val imageUrl = Template.resolve(node.imageUrl ?: "", scope)
    val height = (node.height ?: 240.0).dp

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(0.dp))
    ) {
        if (imageUrl.isNotEmpty()) {
            AsyncImage(
                model = imageUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f))
                    )
                )
        )
        if (title.isNotEmpty()) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(16.dp)
            )
        }
    }
}

@Composable
fun CardBlock(node: DSLNode, scope: DSLScope, nav: NavController) {
    val currentModule = LocalCurrentModule.current
    val logout = LocalLogout.current
    val onClick: (() -> Unit)? = node.action?.let { action ->
        when {
            action.type == "navigate" && !action.to.isNullOrEmpty() -> {
                {
                    val resolved = resolveBindings(action.with ?: emptyMap(), scope)
                    val qualified = ModuleRegistry.qualify(action.to, currentModule)
                    nav.navigate(
                        ScreenRoute(
                            qualifiedScreen = qualified,
                            bindingsJson = encodeBindings(resolved)
                        )
                    )
                }
            }
            action.type == "logout" -> {
                {
                    // Sign out of every configured Firebase project so the next
                    // tenant pick lands on the LoginForm again, then clear the
                    // persisted tenant so CommuneShell shows the picker.
                    CommuneFirebase.signOutAll()
                    logout()
                }
            }
            else -> null
        }
    }

    val baseModifier = Modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(14.dp))
    val clickableModifier = onClick?.let { baseModifier.clickable(onClick = it) } ?: baseModifier

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = clickableModifier
    ) {
        node.child?.let { DSLView(it, scope, nav) }
    }
}

@Composable
fun ImageBlock(node: DSLNode, scope: DSLScope) {
    val urlString = Template.resolve(node.url ?: "", scope)
    val aspect = node.aspectRatio?.toFloat()

    val modifier = Modifier
        .fillMaxWidth()
        .let { if (aspect != null) it.aspectRatio(aspect) else it }

    AsyncImage(
        model = urlString,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = modifier
    )
}

@Composable
fun TextBlock(node: DSLNode, scope: DSLScope) {
    val value = Template.resolve(node.value ?: "", scope)
    val style = node.style

    if (style == "badge") {
        Surface(
            color = MaterialTheme.colorScheme.primary,
            shape = RoundedCornerShape(50)
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
            )
        }
    } else {
        Text(
            text = value,
            style = textStyleFor(style),
            color = colorFor(node.color),
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
fun textStyleFor(style: String?): TextStyle = when (style) {
    "title" -> MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
    "title2" -> MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold)
    "title3" -> MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold)
    "headline" -> MaterialTheme.typography.titleMedium
    "body" -> MaterialTheme.typography.bodyLarge
    "callout" -> MaterialTheme.typography.bodyMedium
    "caption" -> MaterialTheme.typography.bodySmall
    "footnote" -> MaterialTheme.typography.bodySmall
    else -> MaterialTheme.typography.bodyLarge
}

@Composable
fun colorFor(color: String?): Color = when (color) {
    "primary" -> MaterialTheme.colorScheme.onSurface
    "secondary" -> MaterialTheme.colorScheme.onSurfaceVariant
    "tertiary" -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    "accent" -> MaterialTheme.colorScheme.primary
    else -> MaterialTheme.colorScheme.onSurface
}

// MARK: - Markdown

// Compose has no native block-level markdown; we paragraph-split the same way iOS
// does (Text(AttributedString) collapses block structure on Apple platforms too).
@Composable
fun MarkdownBlock(node: DSLNode, scope: DSLScope) {
    val raw = Template.resolve(node.value ?: "", scope)
    val blocks = remember(raw) { parseMarkdownBlocks(raw) }

    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        blocks.forEach { BlockView(it) }
    }
}

private sealed class MdBlock {
    data class Heading(val level: Int, val text: String) : MdBlock()
    data class Bullet(val text: String) : MdBlock()
    data class Paragraph(val text: String) : MdBlock()
}

private fun parseMarkdownBlocks(md: String): List<MdBlock> {
    val result = mutableListOf<MdBlock>()
    val paragraphLines = mutableListOf<String>()

    fun flush() {
        if (paragraphLines.isNotEmpty()) {
            result.add(MdBlock.Paragraph(paragraphLines.joinToString(" ")))
            paragraphLines.clear()
        }
    }

    md.split("\n").forEach { rawLine ->
        val line = rawLine.trim()
        when {
            line.isEmpty() -> flush()
            line.startsWith("### ") -> {
                flush(); result.add(MdBlock.Heading(3, line.substring(4)))
            }
            line.startsWith("## ") -> {
                flush(); result.add(MdBlock.Heading(2, line.substring(3)))
            }
            line.startsWith("# ") -> {
                flush(); result.add(MdBlock.Heading(1, line.substring(2)))
            }
            line.startsWith("- ") || line.startsWith("* ") -> {
                flush(); result.add(MdBlock.Bullet(line.substring(2)))
            }
            else -> paragraphLines.add(line)
        }
    }
    flush()
    return result
}

@Composable
private fun BlockView(block: MdBlock) {
    when (block) {
        is MdBlock.Heading -> Text(
            text = parseInlineMarkdown(block.text),
            style = headingStyle(block.level),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = if (block.level <= 2) 6.dp else 2.dp)
        )
        is MdBlock.Bullet -> Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("•", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = parseInlineMarkdown(block.text),
                modifier = Modifier.fillMaxWidth()
            )
        }
        is MdBlock.Paragraph -> Text(
            text = parseInlineMarkdown(block.text),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun headingStyle(level: Int): TextStyle = when (level) {
    1 -> MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold)
    2 -> MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
    3 -> MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold)
    else -> MaterialTheme.typography.titleMedium
}

private fun parseInlineMarkdown(text: String): AnnotatedString = buildAnnotatedString {
    var i = 0
    while (i < text.length) {
        if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
            val end = text.indexOf("**", i + 2)
            if (end != -1) {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                    append(text.substring(i + 2, end))
                }
                i = end + 2
                continue
            }
        }
        if (text[i] == '*' && i + 1 < text.length && text[i + 1] != ' ') {
            val end = text.indexOf('*', i + 1)
            if (end != -1) {
                withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                    append(text.substring(i + 1, end))
                }
                i = end + 1
                continue
            }
        }
        append(text[i])
        i++
    }
}

// MARK: - Control flow

// Compose-native month-view calendar with markers on dates that have an event.
// Reads `in: <events binding>` and `dateField: <key>` — each event's
// `dateField` is parsed as ISO `yyyy-MM-dd`. Default visible month = month of
// the earliest parseable event date. Material 3 has no markable calendar
// out of the box, so we render a simple grid with a dot under marked days.
@Composable
fun CalendarBlock(node: DSLNode, scope: DSLScope) {
    val events = scope.lookup(node.iterable ?: "")?.let { it as? JsonArray } ?: return
    val dateField = node.dateField ?: "date"
    val markedDates = events.mapNotNull { ev ->
        val obj = ev as? JsonObject ?: return@mapNotNull null
        val raw = (obj[dateField] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
        runCatching { java.time.LocalDate.parse(raw) }.getOrNull()
    }.toSet()

    val month = markedDates.minOrNull()
        ?.let { java.time.YearMonth.from(it) }
        ?: java.time.YearMonth.now()

    val locale = java.util.Locale.forLanguageTag("fr-FR")
    val monthLabel = month
        .format(java.time.format.DateTimeFormatter.ofPattern("MMMM yyyy", locale))
        .replaceFirstChar { it.titlecase(locale) }

    Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
        Text(monthLabel, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(12.dp))
        Row(modifier = Modifier.fillMaxWidth()) {
            for (label in listOf("L", "M", "M", "J", "V", "S", "D")) {
                Text(
                    text = label,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        val firstDay = month.atDay(1)
        // ISO: Monday=1, Sunday=7
        val leadingBlanks = firstDay.dayOfWeek.value - 1
        val daysInMonth = month.lengthOfMonth()
        val totalCells = leadingBlanks + daysInMonth
        val rows = (totalCells + 6) / 7
        for (row in 0 until rows) {
            Row(modifier = Modifier.fillMaxWidth().height(44.dp)) {
                for (col in 0 until 7) {
                    val cellIndex = row * 7 + col
                    val day = cellIndex - leadingBlanks + 1
                    val date = if (day in 1..daysInMonth) month.atDay(day) else null
                    DayCell(
                        date = date,
                        marked = date != null && date in markedDates,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun DayCell(date: java.time.LocalDate?, marked: Boolean, modifier: Modifier) {
    Box(modifier = modifier.fillMaxHeight(), contentAlignment = Alignment.Center) {
        if (date != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "${date.dayOfMonth}",
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(Modifier.height(2.dp))
                if (marked) {
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                    )
                } else {
                    Spacer(Modifier.height(6.dp))
                }
            }
        }
    }
}

@Composable
fun ForBlock(node: DSLNode, scope: DSLScope, nav: NavController) {
    val items = scope.lookup(node.iterable ?: "")?.let { it as? JsonArray }?.toList() ?: emptyList()
    val alias = node.alias ?: "item"

    Column(
        verticalArrangement = Arrangement.spacedBy((node.spacing ?: 16.0).dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        items.forEach { item ->
            node.child?.let {
                DSLView(it, scope.adding(alias, item), nav)
            }
        }
    }
}

@Composable
fun IfBlock(node: DSLNode, scope: DSLScope, nav: NavController) {
    val cond = Template.resolveValue(node.condition ?: "", scope)
    if (cond.dslBool()) {
        node.then?.let { DSLView(it, scope, nav) }
    } else {
        node.elseNode?.let { DSLView(it, scope, nav) }
    }
}

// MARK: - Helpers

private fun resolveBindings(
    raw: Map<String, JsonElement>,
    scope: DSLScope
): Map<String, JsonElement> = raw.mapValues { (_, v) ->
    if (v is JsonPrimitive && v.isString) Template.resolveValue(v.content, scope) else v
}

private fun iconForName(name: String): ImageVector = when (name) {
    "newspaper" -> Icons.Filled.Newspaper
    "info.circle" -> Icons.Filled.Info
    "house" -> Icons.Filled.Home
    "person" -> Icons.Filled.Person
    "magnifyingglass" -> Icons.Filled.Search
    "gearshape" -> Icons.Filled.Settings
    "calendar" -> Icons.Filled.CalendarToday
    "calendar.day" -> Icons.Filled.Event
    "map" -> Icons.Filled.Map
    "chart.bar.fill" -> Icons.Filled.BarChart
    else -> Icons.Filled.Apps
}
