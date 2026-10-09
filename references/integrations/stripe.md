# Payments: Stripe (`app/core/payments.py`)

Stripe is the default payments provider. If the user wants another one (Mercado Pago, Conekta, OpenPay, PayPal…), keep the same shape:
- a `PaymentsGateway` class with the operations they need;
- a cached getter;
- webhook verification.

Read that provider's current official docs (WebFetch) for the SDK or REST calls.

**requirements.txt:** `stripe==16.0.0`, `httpx==0.28.1`. Stripe's `*_async` methods use httpx when it is installed.

**Settings and `.env.example`:**
```python
# Stripe
stripe_secret_key: str = ""
stripe_webhook_secret: str = ""
stripe_api_version: str | None = None    # pin if you depend on a specific API version
```
```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

**Class:**
```python
import logging
from functools import lru_cache
from typing import Any

import stripe

from app.core.config import get_settings

logger = logging.getLogger(__name__)


class PaymentsError(Exception):
    """Payment provider rejected or failed the operation."""


class PaymentsGateway:
    def __init__(self, secret_key: str, webhook_secret: str, api_version: str | None = None):
        self.client = stripe.StripeClient(secret_key, stripe_version=api_version, max_network_retries=2)
        self.webhook_secret = webhook_secret

    async def create_customer(self, email: str, name: str | None = None, metadata: dict[str, str] | None = None):
        try:
            return await self.client.v1.customers.create_async(
                params={"email": email, "name": name, "metadata": metadata or {}}
            )
        except stripe.StripeError as exc:
            raise PaymentsError(str(exc)) from exc

    async def create_payment_intent(
        self, amount_cents: int, currency: str, customer_id: str | None = None, metadata: dict[str, str] | None = None
    ):
        params: dict[str, Any] = {
            "amount": amount_cents,
            "currency": currency,
            "automatic_payment_methods": {"enabled": True},
            "metadata": metadata or {},
        }
        if customer_id:
            params["customer"] = customer_id
        try:
            return await self.client.v1.payment_intents.create_async(params=params)
        except stripe.StripeError as exc:
            raise PaymentsError(str(exc)) from exc

    async def create_checkout_session(self, price_id: str, success_url: str, cancel_url: str, mode: str = "payment"):
        try:
            return await self.client.v1.checkout.sessions.create_async(
                params={
                    "mode": mode,
                    "line_items": [{"price": price_id, "quantity": 1}],
                    "success_url": success_url,
                    "cancel_url": cancel_url,
                }
            )
        except stripe.StripeError as exc:
            raise PaymentsError(str(exc)) from exc

    def parse_webhook(self, payload: bytes, signature: str | None) -> stripe.Event:
        """Raises ValueError / stripe.SignatureVerificationError when invalid -> map to 400 in the service."""
        return self.client.construct_event(payload, signature, self.webhook_secret)


@lru_cache
def get_payments() -> PaymentsGateway:
    s = get_settings()
    return PaymentsGateway(s.stripe_secret_key, s.stripe_webhook_secret, s.stripe_api_version)
```

**Webhook route:** the raw body is needed for signature verification. Pass the raw `Request` into the service, which calls `await request.body()` and `request.headers.get("stripe-signature")`. Don't declare a Pydantic body on that route.

**Amounts:** amounts are integers in the smallest currency unit (cents/centavos). Convert from `Decimal` in the service.
