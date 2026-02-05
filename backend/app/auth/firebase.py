import firebase_admin
from firebase_admin import auth as firebaseAuth
from firebase_admin import credentials

from app.common.config import (
    getFirebaseClientEmail,
    getFirebasePrivateKey,
    getFirebasePrivateKeyId,
    getFirebaseProjectId,
)


firebaseApp: firebase_admin.App | None = None


def getFirebaseApp() -> firebase_admin.App:
    global firebaseApp
    if firebaseApp is None:
        projectId = getFirebaseProjectId()
        privateKeyId = getFirebasePrivateKeyId()
        privateKey = getFirebasePrivateKey()
        clientEmail = getFirebaseClientEmail()
        missing = [
            name
            for name, value in {
                "FIREBASE_PROJECT_ID": projectId,
                "FIREBASE_PRIVATE_KEY_ID": privateKeyId,
                "FIREBASE_PRIVATE_KEY": privateKey,
                "FIREBASE_CLIENT_EMAIL": clientEmail,
            }.items()
            if not value
        ]
        if missing:
            missingList = ", ".join(missing)
            raise RuntimeError(f"Missing Firebase env vars: {missingList}")

        formattedPrivateKey = privateKey.replace("\\n", "\n")
        cred = credentials.Certificate(
            {
                "type": "service_account",
                "project_id": projectId,
                "private_key_id": privateKeyId,
                "private_key": formattedPrivateKey,
                "client_email": clientEmail,
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        )
        firebaseApp = firebase_admin.initialize_app(cred)
    return firebaseApp


def ensureFirebaseUser(
    firebaseUid: str,
    email: str | None,
    displayName: str | None,
    photoUrl: str | None,
) -> None:
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

