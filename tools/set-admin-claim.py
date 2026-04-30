#!/usr/bin/env python3
"""Set custom claim `admin: true` sur les users dashboard.

Phase 11.3 step 4 : le dashboard écrit dans Firestore (`_config/modules`,
collections de contenu plus tard). Les rules Firestore exigent
`request.auth.token.admin == true`. Ce script délivre ce claim aux users
qui doivent pouvoir éditer.

Auth : Application Default Credentials (`gcloud auth application-default
login` requis avant). Pas de service account JSON committed dans le repo.

Usage :
    source core/cloud-functions/venv/bin/activate
    python3 tools/set-admin-claim.py
"""
from __future__ import annotations
import sys

import firebase_admin
from firebase_admin import auth

# (project_id, email) — le user doit déjà exister (créé via Firebase Auth)
TARGETS = [
    ("commune-spike-1", "demo-a@test.be"),
    ("commune-spike-2", "demo-b@test.be"),
]


def grant(project_id: str, email: str):
    # Une app Firebase distincte par project (Admin SDK nécessite le projectId
    # explicite quand on n'utilise pas un service account file).
    app_name = project_id
    app = firebase_admin.initialize_app(
        options={"projectId": project_id}, name=app_name
    )
    try:
        user = auth.get_user_by_email(email, app=app)
        existing = user.custom_claims or {}
        if existing.get("admin") is True:
            print(f"  ✓ {project_id}/{email}: déjà admin (uid={user.uid})")
            return
        new_claims = {**existing, "admin": True}
        auth.set_custom_user_claims(user.uid, new_claims, app=app)
        print(f"  ✓ {project_id}/{email}: admin claim posé (uid={user.uid})")
    except auth.UserNotFoundError:
        print(f"  ⚠ {project_id}/{email}: user introuvable, skip")
    except Exception as e:
        print(f"  ✗ {project_id}/{email}: {type(e).__name__}: {e}")
        sys.exit(1)


def main():
    for project_id, email in TARGETS:
        grant(project_id, email)


if __name__ == "__main__":
    main()
