"""Upload reel thumbnails and mint short-lived signed GET URLs (GCS)."""
from __future__ import annotations

import json
import logging
from datetime import timedelta
from typing import TYPE_CHECKING
from uuid import UUID

from google.cloud import storage
from google.oauth2 import service_account

from app.common.config import getGcsReelBucketName, getGcsServiceAccountJson

if TYPE_CHECKING:
    pass

logger = logging.getLogger("roam.gcsReels")

_CLIENT: storage.Client | None = None
_CREDENTIALS: service_account.Credentials | None = None


def _credentials() -> service_account.Credentials:
    global _CREDENTIALS
    if _CREDENTIALS is not None:
        return _CREDENTIALS
    info = json.loads(getGcsServiceAccountJson())
    _CREDENTIALS = service_account.Credentials.from_service_account_info(
        info,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )
    return _CREDENTIALS


def _client() -> storage.Client:
    global _CLIENT
    if _CLIENT is not None:
        return _CLIENT
    creds = _credentials()
    _CLIENT = storage.Client(credentials=creds, project=creds.project_id)
    return _CLIENT


def uploadReelThumbnail(*, user_id: UUID, job_id: UUID, data: bytes, content_type: str = "image/jpeg") -> str | None:
    """Return object path relative to bucket, or None if upload fails."""
    if not data:
        return None
    bucket_name = getGcsReelBucketName()
    path = f"reels/{user_id}/{job_id}/thumb.jpg"
    try:
        bucket = _client().bucket(bucket_name)
        blob = bucket.blob(path)
        blob.upload_from_string(data, content_type=content_type)
        logger.info(
            "gcs_thumbnail_uploaded jobId=%s userId=%s bucket=%s objectPath=%s bytes=%d contentType=%s",
            job_id,
            user_id,
            bucket_name,
            path,
            len(data),
            content_type,
        )
        return path
    except Exception:
        logger.exception(
            "gcs_upload_failed bucket=%s objectPath=%s jobId=%s userId=%s",
            bucket_name,
            path,
            job_id,
            user_id,
        )
        return None


def signedUrlForObject(object_path: str, *, minutes: int = 15) -> str | None:
    if not object_path:
        return None
    try:
        bucket = _client().bucket(getGcsReelBucketName())
        blob = bucket.blob(object_path)
        return blob.generate_signed_url(
            expiration=timedelta(minutes=minutes),
            method="GET",
            credentials=_credentials(),
        )
    except Exception:
        logger.exception("gcs_signed_url_failed", extra={"path": object_path})
        return None
