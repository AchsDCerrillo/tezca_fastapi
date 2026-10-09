# Security: password hashing + own JWT auth (`app/core/security.py`)

Use this when the API issues its own tokens. For AWS Cognito-issued tokens, see `cognito.md`. A project can have both.

**requirements.txt:** `pyjwt==2.15.1`, `pwdlib[argon2]==0.3.1`

**Settings and `.env.example`:**
```python
# Security
jwt_secret_key: str = "change-me"             # generate: python -c "import secrets;print(secrets.token_urlsafe(64))"
jwt_algorithm: str = "HS256"
jwt_access_token_minutes: int = 30
jwt_refresh_token_days: int = 14
```
```
JWT_SECRET_KEY=
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_MINUTES=30
JWT_REFRESH_TOKEN_DAYS=14
```
In prod, refuse to start with the default secret. Add a `model_validator` in `Settings` that raises if `environment == "prod"` and `jwt_secret_key == "change-me"`.

**Module:**
```python
import uuid
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Annotated, Any, Literal

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from pydantic import BaseModel
from starlette import status
from starlette.exceptions import HTTPException

from app.core.config import Settings, get_settings

TokenType = Literal["access", "refresh"]


class TokenPayload(BaseModel):
    sub: str
    type: TokenType
    exp: int
    iat: int
    jti: str
    scopes: list[str] = []


class SecurityService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.password_hash = PasswordHash.recommended()   # argon2

    # Passwords
    def hash_password(self, password: str) -> str:
        return self.password_hash.hash(password)

    def verify_password(self, password: str, hashed: str) -> bool:
        return self.password_hash.verify(password, hashed)

    # Tokens
    def create_token(self, subject: str, token_type: TokenType = "access", scopes: list[str] | None = None,
                     extra: dict[str, Any] | None = None) -> str:
        now = datetime.now(timezone.utc)
        ttl = (timedelta(minutes=self.settings.jwt_access_token_minutes) if token_type == "access"
               else timedelta(days=self.settings.jwt_refresh_token_days))
        payload = {"sub": subject, "type": token_type, "iat": int(now.timestamp()),
                   "exp": int((now + ttl).timestamp()), "jti": uuid.uuid4().hex, "scopes": scopes or [], **(extra or {})}
        return jwt.encode(payload, self.settings.jwt_secret_key, algorithm=self.settings.jwt_algorithm)

    def decode_token(self, token: str, expected_type: TokenType = "access") -> TokenPayload:
        try:
            data = jwt.decode(token, self.settings.jwt_secret_key, algorithms=[self.settings.jwt_algorithm])
        except jwt.ExpiredSignatureError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired") from exc
        except jwt.InvalidTokenError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc
        payload = TokenPayload.model_validate(data)
        if payload.type != expected_type:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Wrong token type")
        return payload


@lru_cache
def get_security() -> SecurityService:
    return SecurityService(get_settings())


bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_token(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    security: Annotated[SecurityService, Depends(get_security)],
) -> TokenPayload:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    payload = security.decode_token(credentials.credentials)
    request.state.user_id = payload.sub      # services read it from request.state
    return payload


def require_scopes(*required: str):
    async def checker(token: Annotated[TokenPayload, Depends(get_current_token)]) -> TokenPayload:
        if not set(required).issubset(token.scopes):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return token
    return checker
```

**Protecting routes:**
- One route: `token: Annotated[TokenPayload, Depends(get_current_token)]`.
- A whole router: `APIRouter(..., dependencies=[Depends(get_current_token)])`.

**Passwords and users:**
- The user table stores `password_hash`, never the password itself. Never expose `password_hash` in a response model.
- Login lives in a feature (`app/auth/`) whose service uses `SecurityService` and the user repository.
