# Email: AWS SES (`app/core/email.py`)

If the user prefers another provider (SendGrid, Resend, Mailgun, SMTP), keep the same `EmailSender.send(...)` interface and implement it with that provider's SDK or REST API (httpx).

**requirements.txt:** `aioboto3==15.5.0`

**Settings and `.env.example`:**
```python
# Email (SES)
ses_region: str = "us-east-1"
email_from: str = "no-reply@example.com"
ses_configuration_set: str | None = None
```
```
SES_REGION=us-east-1
EMAIL_FROM=no-reply@example.com
SES_CONFIGURATION_SET=
```

**Class:**
```python
import logging
from functools import lru_cache

import aioboto3

from app.core.config import get_settings

logger = logging.getLogger(__name__)


class EmailSender:
    def __init__(self, region: str, sender: str, configuration_set: str | None = None,
                 access_key_id: str | None = None, secret_access_key: str | None = None):
        self.sender = sender
        self.configuration_set = configuration_set
        self._session = aioboto3.Session(
            aws_access_key_id=access_key_id, aws_secret_access_key=secret_access_key, region_name=region
        )

    async def send(self, to: list[str], subject: str, html: str, text: str | None = None,
                   reply_to: list[str] | None = None) -> str:
        body = {"Html": {"Data": html, "Charset": "UTF-8"}}
        if text:
            body["Text"] = {"Data": text, "Charset": "UTF-8"}
        params = {
            "FromEmailAddress": self.sender,
            "Destination": {"ToAddresses": to},
            "Content": {"Simple": {"Subject": {"Data": subject, "Charset": "UTF-8"}, "Body": body}},
        }
        if reply_to:
            params["ReplyToAddresses"] = reply_to
        if self.configuration_set:
            params["ConfigurationSetName"] = self.configuration_set
        async with self._session.client("sesv2") as ses:
            response = await ses.send_email(**params)
        logger.info("email sent to=%s message_id=%s", to, response["MessageId"])
        return response["MessageId"]


@lru_cache
def get_email_sender() -> EmailSender:
    s = get_settings()
    return EmailSender(s.ses_region, s.email_from, s.ses_configuration_set,
                       getattr(s, "aws_access_key_id", None), getattr(s, "aws_secret_access_key", None))
```
**Notes:**
- In the SES sandbox, both the sender and every recipient must be verified.
- For templated emails, render HTML with Jinja2 (`jinja2` dependency) in the service.
