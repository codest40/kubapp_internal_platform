# app/sre/send_alert.py

import os
import sys
import requests
import smtplib
from email.message import EmailMessage

# Allow importing logger from the same folder
sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from logger import logger

ALERT_WEBHOOK = os.getenv("ALERT_WEBHOOK_URL")
ALERT_EMAIL_TO = os.environ.get("EMAIL_TO")
ALERT_EMAIL_FROM = os.environ.get("EMAIL_FROM")
ALERT_EMAIL_PASS = os.environ.get("EMAIL_PASS")

if not ALERT_EMAIL_PASS or not ALERT_EMAIL_FROM or not ALERT_EMAIL_TO:
  print("[SEND ALERT] Env Variables NOT Detected ❌")

def alert_email(subject: str, body: str):
    if not ALERT_EMAIL_TO or not ALERT_EMAIL_FROM or not ALERT_EMAIL_PASS:
        logger.error("❌ Email credentials not configured")
        return

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = ALERT_EMAIL_FROM
    msg["To"] = ALERT_EMAIL_TO
    msg.set_content(body)

    with smtplib.SMTP_SSL("smtp.server.com", 465) as smtp:
        smtp.login(ALERT_EMAIL_FROM, ALERT_EMAIL_PASS)
        smtp.send_message(msg)

    logger.info("✅ Email sent successfully")

def send_alert(message: str, use_fallback_db=False):
    """
    Send alert via webhook first, then email as fallback.
    Logs everything.
    
    Args:
        message (str): The alert message
        use_fallback_db (bool): True if alert is triggered during SQLite fallback
    """
    if use_fallback_db:
        logger.warning(f"⚠️ Alert triggered during SQLite fallback: {message}")
        return

    logger.error(f"🚨 ALERT: {message}")

    # Webhook alert
    if ALERT_WEBHOOK and ALERT_WEBHOOK.startswith("http"):
        try:
            response = requests.post(
                ALERT_WEBHOOK,
                json={"text": message},
                timeout=5,
            )
            response.raise_for_status()
            logger.info("✅ Webhook alert sent successfully")
            return
        except Exception as e:
            logger.error(f"❌ Webhook alert failed: {e}")

    # Email alert
    if ALERT_EMAIL_TO:
        alert_email(
            subject="EdgePaaS Alert",
            body=message,
        )
        logger.info("✅ Email alert sent successfully")
        return

    logger.error("❌ No alert channel configured")
