import logging

from app.api.app import app

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logging.getLogger("roam").setLevel(logging.INFO)

__all__ = ["app"]

