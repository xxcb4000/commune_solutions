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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Schedule
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
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
                        startBindings = tab.bindings ?: emptyMap(),
                        brand = node.brand
                    )
                }
            }
        }
    }
}

@Composable
fun SingleNavStack(
    startQualifiedScreen: String,
    startBindings: Map<String, JsonElement>,
    brand: DSLBrand? = null,
) {
    val nav = rememberNavController()
    // Observer du back-stack pour recomposer quand l'utilisateur push / pop.
    val currentEntry by nav.currentBackStackEntryAsState()
    val isAtRoot = currentEntry == null || nav.previousBackStackEntry == null

    NavHost(
        navController = nav,
        startDestination = ScreenRoute(
            qualifiedScreen = startQualifiedScreen,
            bindingsJson = encodeBindings(startBindings)
        )
    ) {
        composable<ScreenRoute> { entry ->
            val route: ScreenRoute = entry.toRoute()
            Column(modifier = Modifier.fillMaxSize()) {
                if (isAtRoot && brand != null) {
                    BrandHeader(brand)
                }
                ScreenView(
                    qualifiedScreen = route.qualifiedScreen,
                    initialBindings = decodeBindings(route.bindingsJson),
                    nav = nav
                )
            }
        }
    }
}

// Pill segmented control : container gris clair, segment sélectionné en
// blanc (avec ombre subtile), texte semi-bold sélectionné / regular muted
// unsélectionné. Switche entre `cases[<option.id>]` localement (state
// non persisté pour le v0).
@Composable
fun SegmentedBlock(node: DSLNode, scope: DSLScope, nav: NavController) {
    val opts = node.options ?: emptyList()
    var selected by remember { mutableStateOf(node.defaultCase ?: opts.firstOrNull()?.id ?: "") }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            for (opt in opts) {
                val isSelected = opt.id == selected
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(50))
                        .background(
                            if (isSelected) MaterialTheme.colorScheme.surface
                            else Color.Transparent
                        )
                        .clickable { selected = opt.id }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = opt.label,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isSelected) MaterialTheme.colorScheme.onSurface
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        node.cases?.get(selected)?.let { child ->
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                DSLView(child, scope, nav)
            }
        }
    }
}

// Brand header rendu en haut de chaque tab racine (parité iOS).
// Cache implicitement la app bar système car le tab root n'a pas de TopAppBar.
// Sur push (détail), `isAtRoot` repasse à false, BrandHeader disparaît.
@Composable
private fun BrandHeader(brand: DSLBrand) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .padding(vertical = 14.dp)
    ) {
        brand.label?.takeIf { it.isNotEmpty() }?.let { label ->
            Text(
                text = label,
                fontSize = 22.sp,
                fontWeight = FontWeight.Black,
                fontFamily = FontFamily.Serif,
                letterSpacing = 0.5.sp,
                color = parseHex(brand.textColor) ?: MaterialTheme.colorScheme.onBackground,
            )
        }
        brand.dots?.takeIf { it.isNotEmpty() }?.let { dots ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                dots.forEach { hex ->
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(parseHex(hex) ?: Color.Gray)
                    )
                }
            }
        }
    }
}

private fun parseHex(hex: String?): Color? {
    if (hex.isNullOrBlank()) return null
    val s = hex.trim().removePrefix("#")
    if (s.length != 6) return null
    val v = s.toLongOrNull(16) ?: return null
    return Color(
        red = ((v shr 16) and 0xFF).toInt() / 255f,
        green = ((v shr 8) and 0xFF).toInt() / 255f,
        blue = (v and 0xFF).toInt() / 255f,
    )
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
            Box(modifier = Modifier.padding(padding).fillMaxSize()) {
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
        "segmented" -> SegmentedBlock(node, scope, nav)
        "calendar" -> CalendarBlock(node, scope, nav)
        "map" -> MapBlock(node, scope)
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
            .fillMaxSize()
            .padding((node.padding ?: 0.0).dp)
    ) {
        node.children?.forEach { child ->
            // If a child is a flex container (scroll / segmented / calendar with child),
            // weight it so it fills remaining vertical space; otherwise let it size to content.
            if (child.type in setOf("scroll", "segmented", "calendar")) {
                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    DSLView(child, scope, nav)
                }
            } else {
                DSLView(child, scope, nav)
            }
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
        Box(modifier = Modifier.fillMaxWidth()) {
            node.child?.let { DSLView(it, scope, nav) }
            if (node.action?.type == "navigate") {
                Icon(
                    imageVector = androidx.compose.material.icons.Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(12.dp)
                        .size(20.dp)
                )
            }
        }
    }
}

@Composable
fun ImageBlock(node: DSLNode, scope: DSLScope) {
    // Two flavors:
    //  • SF Symbol (mapped to Material icon) when `systemName` is set, optionally
    //    rendered inside a 38×38 rounded square when `bg` is set.
    //  • Network image when `url` is set.
    val systemName = node.systemName
    if (!systemName.isNullOrEmpty()) {
        SymbolView(systemName = systemName, node = node)
        return
    }

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
private fun SymbolView(systemName: String, node: DSLNode) {
    val size = (node.height ?: 18.0).dp
    val iconColor = colorFor(node.color)
    val icon: @Composable () -> Unit = {
        Icon(
            imageVector = iconForName(systemName),
            contentDescription = null,
            tint = iconColor,
            modifier = Modifier.size(size)
        )
    }
    val bgName = node.bg
    if (!bgName.isNullOrEmpty()) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(bgColorFor(bgName)),
            contentAlignment = Alignment.Center
        ) {
            icon()
        }
    } else {
        icon()
    }
}

@Composable
fun TextBlock(node: DSLNode, scope: DSLScope) {
    val value = Template.resolve(node.value ?: "", scope)
    val style = node.style

    val displayed = if (style == "caps") value.uppercase(java.util.Locale.getDefault()) else value
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
        val align = when (node.align) {
            "center" -> TextAlign.Center
            "trailing" -> TextAlign.End
            else -> TextAlign.Start
        }
        Text(
            text = displayed,
            style = textStyleFor(style),
            color = colorFor(node.color),
            textAlign = align,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
fun textStyleFor(style: String?): TextStyle = when (style) {
    "display" -> TextStyle(
        fontSize = 36.sp, fontWeight = FontWeight.SemiBold,
        fontFamily = FontFamily.Serif, letterSpacing = (-0.4).sp,
        lineHeight = 40.sp,
    )
    "display-small" -> TextStyle(
        fontSize = 28.sp, fontWeight = FontWeight.SemiBold,
        fontFamily = FontFamily.Serif, letterSpacing = (-0.4).sp,
        lineHeight = 32.sp,
    )
    "serif-title" -> TextStyle(
        fontSize = 22.sp, fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Serif, letterSpacing = (-0.3).sp,
        lineHeight = 26.sp,
    )
    "serif-title2" -> TextStyle(
        fontSize = 18.sp, fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Serif, letterSpacing = (-0.3).sp,
        lineHeight = 22.sp,
    )
    "eyebrow" -> TextStyle(
        fontSize = 13.sp, fontWeight = FontWeight.Light,
        fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic,
        letterSpacing = 0.2.sp,
    )
    "subhead-italic" -> TextStyle(
        fontSize = 14.sp, fontWeight = FontWeight.Light,
        fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic,
        letterSpacing = 0.1.sp,
    )
    "caps" -> TextStyle(
        fontSize = 11.sp, fontWeight = FontWeight.Medium,
        letterSpacing = 0.7.sp,
    )
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

private val CivicAccentSoft = Color(0xFFDDE6F0)
private val CivicTerra = Color(0xFFC8451B)
private val CivicTerraSoft = Color(0xFFF5E5DD)
private val CivicHair = Color(0xFFE6E0D6)
private val CivicPaper = Color(0xFFFAF8F4)
private val CivicPaperDeep = Color(0xFFF2EFE8)

@Composable
fun colorFor(color: String?): Color = when (color) {
    "primary" -> MaterialTheme.colorScheme.onSurface
    "secondary" -> MaterialTheme.colorScheme.onSurfaceVariant
    "tertiary" -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    "accent" -> MaterialTheme.colorScheme.primary
    "civic" -> CivicAccent
    "terra" -> CivicTerra
    "white" -> Color.White
    else -> MaterialTheme.colorScheme.onSurface
}

private fun bgColorFor(name: String?): Color = when (name) {
    "civic-soft" -> CivicAccentSoft
    "terra-soft" -> CivicTerraSoft
    "civic" -> CivicAccent
    "terra" -> CivicTerra
    "paper" -> CivicPaper
    "paper-deep" -> CivicPaperDeep
    else -> Color.LightGray
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

// Custom Compose month-view calendar — civic editorial direction.
// Reads `in: <events binding>` + `dateField: <key>` (ISO yyyy-MM-dd).
// Selected day = filled accent pill (white text); today = accent ring;
// days with events = small accent dot below the number.
// When `child` is set, it is rendered below the grid in a scope augmented with
// `exposes` (default "selectedEvents") = events of the selected day.
private val CivicAccent = Color(0xFF2C4A6B)
private val FrenchLocale = java.util.Locale.forLanguageTag("fr-FR")
private val FrenchWeekdayLabels = listOf("L", "Ma", "Me", "J", "V", "S", "D")

@Composable
fun CalendarBlock(node: DSLNode, scope: DSLScope, nav: NavController) {
    val events = scope.lookup(node.iterable ?: "")?.let { it as? JsonArray } ?: return
    val dateField = node.dateField ?: "date"

    val markedDates = remember(events, dateField) {
        events.mapNotNull { ev ->
            val obj = ev as? JsonObject ?: return@mapNotNull null
            val raw = (obj[dateField] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            runCatching { java.time.LocalDate.parse(raw) }.getOrNull()
        }.toSet()
    }

    val today = remember { java.time.LocalDate.now() }
    var selected by rememberSaveable(stateSaver = LocalDateSaver) { mutableStateOf(today) }
    var visibleMonth by rememberSaveable(stateSaver = YearMonthSaver) {
        mutableStateOf(java.time.YearMonth.from(today))
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 8.dp)
        ) {
            CalendarHeader(
                month = visibleMonth,
                onPrev = { visibleMonth = visibleMonth.minusMonths(1) },
                onNext = { visibleMonth = visibleMonth.plusMonths(1) }
            )
            Spacer(Modifier.height(10.dp))
            Row(modifier = Modifier.fillMaxWidth()) {
                FrenchWeekdayLabels.forEachIndexed { idx, label ->
                    Text(
                        text = label.uppercase(FrenchLocale),
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center,
                        color = if (idx >= 5)
                            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontWeight = FontWeight.Medium,
                            letterSpacing = 0.6.sp,
                        )
                    )
                }
            }
            Spacer(Modifier.height(6.dp))

            val grid = remember(visibleMonth) { monthGrid(visibleMonth) }
            val rows = grid.size / 7
            for (row in 0 until rows) {
                Row(modifier = Modifier.fillMaxWidth().height(44.dp)) {
                    for (col in 0 until 7) {
                        val date = grid[row * 7 + col]
                        DayCell(
                            date = date,
                            inMonth = java.time.YearMonth.from(date) == visibleMonth,
                            isToday = date == today,
                            isSelected = date == selected,
                            hasEvent = date in markedDates,
                            onTap = {
                                selected = date
                                if (java.time.YearMonth.from(date) != visibleMonth) {
                                    visibleMonth = java.time.YearMonth.from(date)
                                }
                            },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
        // Hairline separating the calendar from its child content
        Box(
            modifier = Modifier
                .padding(horizontal = 18.dp)
                .fillMaxWidth()
                .height(0.5.dp)
                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
        )

        node.child?.let { child ->
            val exposed = node.exposes ?: "selectedEvents"
            val selectedKey = selected.toString()  // yyyy-MM-dd
            val filtered = events.filter { ev ->
                val obj = ev as? JsonObject ?: return@filter false
                val raw = (obj[dateField] as? JsonPrimitive)?.contentOrNull ?: return@filter false
                raw == selectedKey
            }
            val isToday = selected == today
            val dayLabel = selected.format(
                java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM", FrenchLocale)
            ).replaceFirstChar { it.titlecase(FrenchLocale) }
            val augmented = scope
                .adding(exposed, JsonArray(filtered))
                .adding("${exposed}Count", JsonPrimitive(filtered.size))
                .adding("${exposed}DayLabel", JsonPrimitive(dayLabel))
                .adding("${exposed}Pre", JsonPrimitive(if (isToday) "Aujourd'hui" else ""))
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                DSLView(child, augmented, nav)
            }
        }
    }
}

@Composable
private fun CalendarHeader(
    month: java.time.YearMonth,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    val monthName = month.month
        .getDisplayName(java.time.format.TextStyle.FULL, FrenchLocale)
        .lowercase(FrenchLocale)
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.Bottom,
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = monthName,
                style = TextStyle(
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Serif,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            )
            Spacer(Modifier.size(width = 6.dp, height = 1.dp))
            Text(
                text = "${month.year}",
                style = TextStyle(
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Light,
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
                modifier = Modifier.padding(bottom = 2.dp)
            )
        }
        IconButton(onClick = onPrev, modifier = Modifier.size(36.dp)) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Mois précédent",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.rotate(180f)
            )
        }
        IconButton(onClick = onNext, modifier = Modifier.size(36.dp)) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Mois suivant",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun DayCell(
    date: java.time.LocalDate,
    inMonth: Boolean,
    isToday: Boolean,
    isSelected: Boolean,
    hasEvent: Boolean,
    onTap: () -> Unit,
    modifier: Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxHeight()
            .clickable(onClick = onTap),
        contentAlignment = Alignment.Center
    ) {
        when {
            isSelected -> Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(CivicAccent)
            )
            isToday -> androidx.compose.foundation.Canvas(modifier = Modifier.size(36.dp)) {
                drawRoundRect(
                    color = CivicAccent,
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(12.dp.toPx(), 12.dp.toPx()),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.5.dp.toPx())
                )
            }
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "${date.dayOfMonth}",
                style = MaterialTheme.typography.bodyMedium,
                color = when {
                    isSelected -> Color.White
                    !inMonth -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)
                    else -> MaterialTheme.colorScheme.onSurface
                },
                fontWeight = when {
                    isSelected -> FontWeight.SemiBold
                    isToday -> FontWeight.Bold
                    else -> FontWeight.Medium
                }
            )
            if (hasEvent) {
                Spacer(Modifier.height(2.dp))
                Box(
                    modifier = Modifier
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(if (isSelected) Color.White.copy(alpha = 0.9f) else CivicAccent)
                )
            }
        }
    }
}

private fun monthGrid(month: java.time.YearMonth): List<java.time.LocalDate> {
    val first = month.atDay(1)
    // ISO Monday=1; we want Monday-first column 0
    val leading = (first.dayOfWeek.value - 1)
    val start = first.minusDays(leading.toLong())
    val raw = (0 until 42).map { start.plusDays(it.toLong()) }
    // Trim 6th row when entirely outside the visible month
    val row6First = raw[35]
    return if (java.time.YearMonth.from(row6First) != month) raw.take(35) else raw
}

private val LocalDateSaver = androidx.compose.runtime.saveable.Saver<java.time.LocalDate, String>(
    save = { it.toString() },
    restore = { java.time.LocalDate.parse(it) }
)

private val YearMonthSaver = androidx.compose.runtime.saveable.Saver<java.time.YearMonth, String>(
    save = { it.toString() },
    restore = { java.time.YearMonth.parse(it) }
)

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
    "mappin.and.ellipse", "mappin" -> Icons.Filled.LocationOn
    "clock" -> Icons.Filled.Schedule
    "phone" -> Icons.Filled.Phone
    "envelope" -> Icons.Filled.Email
    "doc.text" -> Icons.Filled.Description
    "building.columns" -> Icons.Filled.AccountBalance
    "person.2" -> Icons.Filled.Group
    "calendar.badge.plus" -> Icons.Filled.EventAvailable
    "arrow.up.right" -> Icons.AutoMirrored.Filled.OpenInNew
    "checkmark.circle" -> Icons.Filled.CheckCircle
    "chevron.right" -> Icons.AutoMirrored.Filled.KeyboardArrowRight
    else -> Icons.Filled.Apps
}
