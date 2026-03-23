from app.auth import auth as auth_module


def test_dev_bypass_returns_synthetic_token_when_secret_matches(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "dev")
    monkeypatch.setenv("DEV_AUTH_BYPASS", "true")
    monkeypatch.setenv("DEV_AUTH_BYPASS_SECRET", "local-dev-secret")
    monkeypatch.setenv("DEV_AUTH_BYPASS_UID", "dev-user-1")
    monkeypatch.setenv("DEV_AUTH_BYPASS_EMAIL", "dev1@example.com")

    decoded = auth_module.verifyFirebaseToken(
        authorization=None,
        x_roam_authorization=None,
        x_dev_auth_bypass="local-dev-secret",
    )

    assert decoded["uid"] == "dev-user-1"
    assert decoded["email"] == "dev1@example.com"
    assert decoded["email_verified"] is True


def test_dev_bypass_falls_back_to_firebase_verification_when_secret_mismatch(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "dev")
    monkeypatch.setenv("DEV_AUTH_BYPASS", "true")
    monkeypatch.setenv("DEV_AUTH_BYPASS_SECRET", "expected-secret")
    monkeypatch.setattr(
        auth_module,
        "verifyFirebaseTokenString",
        lambda token: {"uid": f"firebase-{token}"},
    )

    decoded = auth_module.verifyFirebaseToken(
        authorization="Bearer real-token",
        x_roam_authorization=None,
        x_dev_auth_bypass="wrong-secret",
    )

    assert decoded["uid"] == "firebase-real-token"


def test_prod_ignores_bypass_and_uses_firebase_verification(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "prod")
    monkeypatch.setenv("DEV_AUTH_BYPASS", "true")
    monkeypatch.setenv("DEV_AUTH_BYPASS_SECRET", "expected-secret")
    monkeypatch.setattr(
        auth_module,
        "verifyFirebaseTokenString",
        lambda token: {"uid": f"firebase-{token}"},
    )

    decoded = auth_module.verifyFirebaseToken(
        authorization="Bearer prod-token",
        x_roam_authorization=None,
        x_dev_auth_bypass="expected-secret",
    )

    assert decoded["uid"] == "firebase-prod-token"
