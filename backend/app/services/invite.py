import logging
import smtplib
from datetime import datetime, timedelta
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any
from urllib.parse import quote

import os

logger = logging.getLogger("roam.invite")


def get_schedule_url(share_code: str) -> str:
    base_url = os.getenv("FRONTEND_URL") or "https://roam-alpha.web.app"
    return f"{base_url}/share/schedule?uid={share_code}"


def send_plan_invites(
    plan_title: str,
    scheduled_at: datetime | None,
    estimated_minutes: int,
    place_name: str | None,
    place_address: str | None,
    share_code: str,
    members: list[dict[str, Any]],
) -> dict[str, list[str]]:
    """Send invites to plan members.

    - Email users: sends an email with plan details + GCal "add to calendar" link.
    - Phone-only external users: sends an SMS via Twilio.
    """
    email_sent: list[str] = []
    sms_sent: list[str] = []

    schedule_url = get_schedule_url(share_code)

    gcal_link = None
    if scheduled_at:
        gcal_link = build_gcal_link(
            title=plan_title,
            start_time=scheduled_at,
            duration_minutes=estimated_minutes,
            location=place_name,
        )

    for member in members:
        email = member.get("email")
        phone = member.get("phone")
        user_id = member.get("userId", "")
        first_name = member.get("firstName", "")

        if email:
            sent = _send_email_invite(
                to_email=email,
                first_name=first_name,
                plan_title=plan_title,
                scheduled_at=scheduled_at,
                place_name=place_name,
                schedule_url=schedule_url,
                gcal_link=gcal_link,
            )
            if sent:
                email_sent.append(user_id)
        elif phone:
            _send_sms(
                phone=phone,
                message=_build_sms_message(
                    first_name=first_name,
                    plan_title=plan_title,
                    scheduled_at=scheduled_at,
                    place_name=place_name,
                    schedule_url=schedule_url,
                ),
            )
            sms_sent.append(user_id)

    return {"email": email_sent, "sms": sms_sent}


def send_single_invite(
    plan_title: str,
    scheduled_at: datetime | None,
    estimated_minutes: int,
    place_name: str | None,
    share_code: str,
    email: str | None,
    phone: str | None,
    first_name: str,
) -> str | None:
    """Send an invite to a single user. Returns the delivery channel used."""
    schedule_url = get_schedule_url(share_code)
    gcal_link = None
    if scheduled_at:
        gcal_link = build_gcal_link(
            title=plan_title,
            start_time=scheduled_at,
            duration_minutes=estimated_minutes,
            location=place_name,
        )

    if email:
        sent = _send_email_invite(
            to_email=email,
            first_name=first_name,
            plan_title=plan_title,
            scheduled_at=scheduled_at,
            place_name=place_name,
            schedule_url=schedule_url,
            gcal_link=gcal_link,
        )
        return "email" if sent else None
    elif phone:
        _send_sms(
            phone=phone,
            message=_build_sms_message(
                first_name=first_name,
                plan_title=plan_title,
                scheduled_at=scheduled_at,
                place_name=place_name,
                schedule_url=schedule_url,
            ),
        )
        return "sms"
    return None


def build_gcal_link(
    title: str,
    start_time: datetime,
    duration_minutes: int = 60,
    location: str | None = None,
    notes: str | None = None,
) -> str:
    end_time = start_time + timedelta(minutes=duration_minutes)

    def fmt(dt: datetime) -> str:
        return dt.strftime("%Y%m%dT%H%M%S")

    params = f"action=TEMPLATE&text={quote(title)}&dates={fmt(start_time)}/{fmt(end_time)}"
    if location:
        params += f"&location={quote(location)}"
    if notes:
        params += f"&details={quote(notes)}"

    return f"https://calendar.google.com/calendar/render?{params}"


# ---------------------------------------------------------------------------
# Email sending
# ---------------------------------------------------------------------------

def _send_email_invite(
    to_email: str,
    first_name: str,
    plan_title: str,
    scheduled_at: datetime | None,
    place_name: str | None,
    schedule_url: str,
    gcal_link: str | None,
) -> bool:
    """Send an invite email with plan details and a GCal link.

    Uses SMTP configured via SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD,
    SMTP_FROM_EMAIL env vars. Falls back to Twilio SendGrid if SENDGRID_API_KEY
    is set. Returns True on success.
    """
    smtp_host = os.getenv("SMTP_HOST")
    smtp_user = os.getenv("SMTP_USER")
    smtp_password = os.getenv("SMTP_PASSWORD")
    from_email = os.getenv("SMTP_FROM_EMAIL") or "noreply@roam.app"

    if not all([smtp_host, smtp_user, smtp_password]):
        sendgrid_key = os.getenv("SENDGRID_API_KEY")
        if sendgrid_key:
            return _send_email_sendgrid(
                api_key=sendgrid_key,
                from_email=from_email,
                to_email=to_email,
                first_name=first_name,
                plan_title=plan_title,
                scheduled_at=scheduled_at,
                place_name=place_name,
                schedule_url=schedule_url,
                gcal_link=gcal_link,
            )
        logger.warning(
            "email_not_configured",
            extra={"to": to_email, "plan": plan_title},
        )
        return False

    subject = f"You're invited: {plan_title}"
    html = _build_invite_email_html(
        first_name=first_name,
        plan_title=plan_title,
        scheduled_at=scheduled_at,
        place_name=place_name,
        schedule_url=schedule_url,
        gcal_link=gcal_link,
    )

    try:
        smtp_port = int(os.getenv("SMTP_PORT") or "587")
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = from_email
        msg["To"] = to_email
        msg.attach(MIMEText(html, "html"))

        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_password)
            server.sendmail(from_email, to_email, msg.as_string())

        logger.info("email_sent", extra={"to": to_email, "plan": plan_title})
        return True
    except Exception:
        logger.exception("email_send_failed", extra={"to": to_email})
        return False


def _send_email_sendgrid(
    api_key: str,
    from_email: str,
    to_email: str,
    first_name: str,
    plan_title: str,
    scheduled_at: datetime | None,
    place_name: str | None,
    schedule_url: str,
    gcal_link: str | None,
) -> bool:
    """Send invite email via SendGrid HTTP API."""
    try:
        import httpx

        html = _build_invite_email_html(
            first_name=first_name,
            plan_title=plan_title,
            scheduled_at=scheduled_at,
            place_name=place_name,
            schedule_url=schedule_url,
            gcal_link=gcal_link,
        )
        resp = httpx.post(
            "https://api.sendgrid.com/v3/mail/send",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "personalizations": [{"to": [{"email": to_email}]}],
                "from": {"email": from_email, "name": "Roam"},
                "subject": f"You're invited: {plan_title}",
                "content": [{"type": "text/html", "value": html}],
            },
            timeout=10,
        )
        if resp.status_code in (200, 202):
            logger.info("sendgrid_sent", extra={"to": to_email})
            return True
        logger.warning(
            "sendgrid_failed",
            extra={"to": to_email, "status": resp.status_code, "body": resp.text[:200]},
        )
        return False
    except Exception:
        logger.exception("sendgrid_error", extra={"to": to_email})
        return False


def _build_invite_email_html(
    first_name: str,
    plan_title: str,
    scheduled_at: datetime | None,
    place_name: str | None,
    schedule_url: str,
    gcal_link: str | None,
) -> str:
    when_line = ""
    if scheduled_at:
        when_line = f'<p style="margin:8px 0;color:#6B6480;">📅 {scheduled_at.strftime("%A, %B %d at %-I:%M %p")}</p>'
    where_line = ""
    if place_name:
        where_line = f'<p style="margin:8px 0;color:#6B6480;">📍 {place_name}</p>'
    gcal_button = ""
    if gcal_link:
        gcal_button = (
            f'<a href="{gcal_link}" style="display:inline-block;margin-top:12px;'
            f'padding:10px 20px;background:#7B6FA8;color:#fff;border-radius:8px;'
            f'text-decoration:none;font-size:14px;">Add to Google Calendar</a>'
        )

    return f"""
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;">
        <h2 style="color:#1E1A2E;margin-bottom:4px;">You're invited!</h2>
        <p style="color:#6B6480;margin-top:0;">Hey {first_name}, you've been invited to a plan on Roam.</p>
        <div style="background:#F5F3FA;border-radius:12px;padding:20px;margin:16px 0;">
            <h3 style="color:#1E1A2E;margin:0 0 8px;">{plan_title}</h3>
            {when_line}
            {where_line}
        </div>
        <a href="{schedule_url}" style="display:inline-block;padding:12px 24px;
           background:#4A4070;color:#fff;border-radius:10px;text-decoration:none;
           font-size:14px;font-weight:600;">View Plan &amp; RSVP</a>
        {gcal_button}
        <p style="margin-top:24px;font-size:12px;color:#A89FC0;">
            Sent from Roam — plan your adventures together.
        </p>
    </div>
    """


# ---------------------------------------------------------------------------
# SMS sending
# ---------------------------------------------------------------------------

def _build_sms_message(
    first_name: str,
    plan_title: str,
    scheduled_at: datetime | None,
    place_name: str | None,
    schedule_url: str,
) -> str:
    parts = [f"Hey {first_name}! You're invited to: {plan_title}"]
    if place_name:
        parts.append(f"at {place_name}")
    if scheduled_at:
        parts.append(f"on {scheduled_at.strftime('%b %d at %-I:%M %p')}")
    parts.append(f"RSVP here: {schedule_url}")
    return " ".join(parts)


def _send_sms(phone: str, message: str) -> bool:
    """Send SMS via Twilio. Returns True on success."""
    account_sid = os.getenv("TWILIO_ACCOUNT_SID")
    auth_token = os.getenv("TWILIO_AUTH_TOKEN")
    from_number = os.getenv("TWILIO_FROM_NUMBER")

    if not all([account_sid, auth_token, from_number]):
        logger.warning("Twilio not configured, skipping SMS", extra={"phone": phone})
        return False

    try:
        from twilio.rest import Client as TwilioClient

        client = TwilioClient(account_sid, auth_token)
        client.messages.create(body=message, from_=from_number, to=phone)
        logger.info("sms_sent", extra={"phone": phone[-4:]})
        return True
    except Exception:
        logger.exception("SMS send failed", extra={"phone": phone[-4:]})
        return False
