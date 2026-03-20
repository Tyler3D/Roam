"""Upload reel thumbnails and mint short-lived signed GET URLs (GCS)."""
from __future__ import annotations

import json
import logging
from datetime import timedelta
from typing import TYPE_CHECKING
from uuid import UUID

from google.oauth2 import service_account

from app.common.config import getGcsReelBucketName, getGcsServiceAccountJson

if TYPE_CHECKING:
    from google.cloud import storage  # noqa: F401

logger = logging.getLogger("roam.gcsReels")

_CLIENT = None
_CREDENTIALS = None


def _credentials():
    global _CREDENTIALS
    if _CREDENTIALS is not None:
        return _CREDENTIALS
    raw = getGcsServiceAccountJson()
    if not raw:
        return None
    try:
        info = json.loads(raw)
    except json.JSONDecodeError:
        logger.error("GCS_SERVICE_ACCOUNT_JSON is not valid JSON")
        return None
    _CREDENTIALS = service_account.Credentials.from_service_account_info(info)
    return _CREDENTIALS


def _client():
    global _CLIENT
    if _CLIENT is not None:
        return _CLIENT
    creds = _credentials()
    bucket_name = getGcsReelBucketName()
    if not creds or not bucket_name:
        return None
    from google.cloud import storage

    _CLIENT = storage.Client(credentials=creds, project=creds.project_id)
    return _CLIENT


def gcsReelsConfigured() -> bool:
    return _credentials() is not None and bool(getGcsReelBucketName())


def uploadReelThumbnail(*, user_id: UUID, job_id: UUID, data: bytes, content_type: str = "image/jpeg") -> str | None:
    """Return object path relative to bucket, or None if GCS not configured."""
    client = _client()
    bucket_name = getGcsReelBucketName()
    if not client or not bucket_name or not data:
        return None
    path = f"reels/{user_id}/{job_id}/thumb.jpg"
    try:
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(path)
        blob.upload_from_string(data, content_type=content_type)
        return path
    except Exception:
        logger.exception("gcs_upload_failed", extra={"path": path})
        return None


def signedUrlForObject(object_path: str, *, minutes: int = 15) -> str | None:
    if not object_path:
        return None
    client = _client()
    bucket_name = getGcsReelBucketName()
    creds = _credentials()
    if not client or not bucket_name or not creds:
        return None
    try:
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(object_path)
        return blob.generate_signed_url(
            expiration=timedelta(minutes=minutes),
            method="GET",
            credentials=creds,
        )
    except Exception:
        logger.exception("gcs_signed_url_failed", extra={"path": object_path})
        return None
