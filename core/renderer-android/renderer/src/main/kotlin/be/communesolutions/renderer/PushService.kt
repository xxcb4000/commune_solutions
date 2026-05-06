package be.communesolutions.renderer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Notifications push v0 (broadcast). Pendant Android du iOS CommunePushDelegate :
 *   - À chaque token FCM refresh, écrit un doc dans `_push_tokens/<token>`
 *     du Firestore de chaque tenant pour lequel un user est loggué.
 *   - À la réception d'un message FCM avec app au foreground, affiche
 *     une notif système sur le canal "communications".
 *
 * Le multi-tenant dev mode pose une question : le SDK FCM Android lie un
 * token à l'instance default FirebaseApp. En multi-projet, il faudrait
 * `FirebaseMessaging.getInstance(app)` par projet. Pour rester simple en
 * v0, on capture le token de l'instance default et on l'écrit dans tous
 * les Firestore où un user est loggué — en single-commune build (cas réel),
 * il n'y a qu'un projet de toute façon donc le multi-write est no-op.
 */
class CommunePushService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "CommunePush"
        const val CHANNEL_ID = "communications"
        const val CHANNEL_NAME = "Communications de la commune"

        /** Connu des FirebaseApps configurés (renseigné par CommuneFirebase). */
        var configuredAppNames: List<String> = emptyList()

        /** À appeler depuis MainActivity après config Firebase + login user. */
        fun ensureChannelAndPersistToken(context: Context) {
            ensureChannel(context)
            // Délégué au coroutine scope — pas de blocage UI thread.
            CoroutineScope(Dispatchers.IO).launch {
                runCatching {
                    val token = com.google.firebase.messaging.FirebaseMessaging
                        .getInstance().token.await()
                    persist(token)
                }.onFailure { Log.e(TAG, "ensure token failed", it) }
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                )
                channel.description = "Notifications envoyées par votre commune"
                mgr.createNotificationChannel(channel)
            }
        }

        suspend fun persist(token: String) {
            for (appName in configuredAppNames.ifEmpty { listOf("[DEFAULT]") }) {
                val app = runCatching { FirebaseApp.getInstance(appName) }.getOrNull() ?: continue
                val user = FirebaseAuth.getInstance(app).currentUser ?: continue
                val db = FirebaseFirestore.getInstance(app)
                runCatching {
                    db.collection("_push_tokens").document(token).set(
                        mapOf(
                            "uid" to user.uid,
                            "platform" to "android",
                            "tenantId" to appName,
                            "updatedAt" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                        ),
                        com.google.firebase.firestore.SetOptions.merge()
                    ).await()
                    Log.i(TAG, "wrote token to $appName/_push_tokens (${user.uid})")
                }.onFailure {
                    Log.e(TAG, "write to $appName failed: ${it.message}")
                }
            }
        }
    }

    override fun onNewToken(token: String) {
        Log.i(TAG, "FCM token refresh: ${token.take(20)}…")
        CoroutineScope(Dispatchers.IO).launch {
            persist(token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val notif = message.notification ?: return
        val title = notif.title ?: "Commune"
        val body = notif.body ?: ""
        ensureChannel(this)
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_info)  // ressource fallback fournie par Android
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
        if (pendingIntent != null) builder.setContentIntent(pendingIntent)
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(message.messageId?.hashCode() ?: System.currentTimeMillis().toInt(), builder.build())
    }
}
