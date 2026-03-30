import json
import logging

import firebase_admin
from firebase_admin import auth as firebaseAuth
from firebase_admin import credentials

from app.common.config import getFirebaseIosProjectId, getFirebaseServiceAccountJson


firebaseApp: firebase_admin.App | None = None
logger = logging.getLogger("roam.auth")


def getFirebaseApp() -> firebase_admin.App:
    global firebaseApp
    if firebaseApp is None:
        info = json.loads(getFirebaseServiceAccountJson())
        serviceAccountProjectId = str(info.get("project_id") or "").strip() or None
        iosProjectId = getFirebaseIosProjectId()
        if iosProjectId and serviceAccountProjectId and iosProjectId != serviceAccountProjectId:
            logger.warning(
                "firebase_project_mismatch",
                extra={
                    "iosProjectId": iosProjectId,
                    "serviceAccountProjectId": serviceAccountProjectId,
                },
            )
        if "private_key" in info:
            info["private_key"] = info["private_key"].replace("\\n", "\n")
        cred = credentials.Certificate(info)
        firebaseApp = firebase_admin.initialize_app(cred)
    return firebaseApp


def ensureFirebaseUser(
    firebaseUid: str,
    email: str | None,
    displayName: str | None,
    photoUrl: str | None,
) -> None:
    """
    Ensure a user exists in Firebase Auth (get-or-create). Idempotent: safe to call
    multiple times for the same uid. On retry after a failed DB commit, get_user will
    find the user and we skip create_user, so the caller can safely retry the DB write.
    """
    getFirebaseApp()
    try:
        firebaseAuth.get_user(firebaseUid)
        return
    except firebaseAuth.UserNotFoundError:
        pass

    createKwargs: dict = {"uid": firebaseUid}
    if email:
        createKwargs["email"] = email
    if displayName:
        createKwargs["display_name"] = displayName
    if photoUrl:
        createKwargs["photo_url"] = photoUrl
    firebaseAuth.create_user(**createKwargs)
