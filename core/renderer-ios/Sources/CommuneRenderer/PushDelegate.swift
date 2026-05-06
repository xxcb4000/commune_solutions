import Foundation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

// Notifications push v0 (broadcast). L'app demande la permission au premier
// lancement, capture le token APNs natif puis le token FCM dérivé. À chaque
// (login utilisateur + token capturé), on écrit un doc dans `_push_tokens/`
// du Firestore du tenant actif. Les CFs admin lisent cette collection pour
// fan-out un push aux citoyens. Le client mobile n'a pas accès en lecture
// (rules : write conditional sur uid, read réservée admin).
//
// L'AppDelegate vit dans le renderer pour être partagé entre le spike (multi
// -tenant) et les builds commune (single-tenant). SpikeApp l'instancie via
// `@UIApplicationDelegateAdaptor`.
public final class CommunePushDelegate: NSObject, UIApplicationDelegate,
                                         MessagingDelegate, UNUserNotificationCenterDelegate {

    // Dernier token FCM capturé. Persisté à chaque (login + token) → Firestore
    // du tenant actif. Re-utilisable si plusieurs tenants se connectent
    // séquentiellement (le SDK FCM regénère un token par projet Firebase actif).
    private var latestFCMToken: String?

    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase est déjà configuré par CommuneFirebase.configure() dans
        // SpikeApp.init avant que l'AppDelegate ne soit appelé.
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // Demande la permission notif au premier launch. Sur user refus, le
        // token APNs ne sera pas capturé — pas grave, le user ne reçoit pas
        // de push, c'est son choix. Pas de re-prompt.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[CommunePush] permission error: \(error.localizedDescription)")
                return
            }
            print("[CommunePush] permission granted=\(granted)")
            if granted {
                Task { @MainActor in
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        // Écoute les changements d'auth sur chaque Firebase app configurée
        // pour réessayer la persistance du token dès qu'un user se logge.
        // (Au premier launch : token capturé AVANT login → persistance differée.)
        for (name, app) in FirebaseApp.allApps ?? [:] {
            if name == "__FIRAPP_DEFAULT" { continue }  // évite double-listen sur le default
            _ = Auth.auth(app: app).addStateDidChangeListener { [weak self] _, user in
                if user != nil {
                    self?.tokenSyncOpportunity()
                }
            }
        }
        return true
    }

    // APNs nous donne le token natif device → on le passe au SDK FCM qui
    // génère ensuite le token FCM applicatif (différent par projet Firebase).
    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("[CommunePush] APNs token set (\(deviceToken.count) bytes)")
    }

    public func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[CommunePush] APNs register failed: \(error.localizedDescription)")
    }

    // FCM token capturé / refresh. On le mémorise et on tente l'écriture
    // dans Firestore si un user est déjà loggué sur un tenant actif.
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        latestFCMToken = fcmToken
        print("[CommunePush] FCM token: \(fcmToken.prefix(20))…")
        Task { await persistTokenIfPossible() }
    }

    // Notification reçue avec app au premier plan : montrer la bannière
    // (sinon par défaut iOS la masque vu que l'app est ouverte).
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .badge, .sound]
    }

    // Tap sur une notif (foreground ou background). v0 : juste log. Les
    // deep-links (ouvrir un écran cible) sont phase 18.5.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        print("[CommunePush] tap notif: \(userInfo)")
    }

    // Appelée par AuthGate quand l'état auth change pour qu'on tente
    // d'écrire le token dans Firestore. Idempotent (overwrite via set merge).
    public func tokenSyncOpportunity() {
        Task { await persistTokenIfPossible() }
    }

    @MainActor
    private func persistTokenIfPossible() async {
        guard let token = latestFCMToken else { return }
        // Le FCM token est lié à l'app [DEFAULT] (singleton iOS). On le
        // persiste dans le Firestore du projet correspondant, identifié via
        // le projectID matching parmi les apps named (qui portent l'auth state).
        // Si aucun app named ne matche, on est en single-commune build avec
        // le default seul → on écrit dessus directement.
        let defaultProjectID = FirebaseApp.app()?.options.projectID
        var matched = false
        for (name, app) in FirebaseApp.allApps ?? [:] {
            if name == "__FIRAPP_DEFAULT" { continue }
            guard app.options.projectID == defaultProjectID else { continue }
            guard let user = Auth.auth(app: app).currentUser else { continue }
            await write(token: token, app: app, uid: user.uid, tenantId: name)
            matched = true
        }
        if !matched, let defaultApp = FirebaseApp.app(),
           let user = Auth.auth(app: defaultApp).currentUser {
            await write(token: token, app: defaultApp, uid: user.uid, tenantId: "[DEFAULT]")
        }
    }

    private func write(token: String, app: FirebaseApp, uid: String, tenantId: String) async {
        let db = Firestore.firestore(app: app)
        // Doc ID = token (1 doc par device-FCM-token, écrasé sur refresh).
        // Token contient des `:` qui sont OK en doc ID Firestore.
        do {
            try await db.collection("_push_tokens").document(token).setData([
                "uid": uid,
                "platform": "ios",
                "tenantId": tenantId,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
            print("[CommunePush] wrote token to \(tenantId)/_push_tokens (\(uid))")
        } catch {
            print("[CommunePush] write failed (\(tenantId)): \(error.localizedDescription)")
        }
    }
}
