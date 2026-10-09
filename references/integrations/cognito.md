# AWS Cognito token verification (`app/core/cognito.py`)

This verifies ID or access tokens issued by a Cognito User Pool. Login and sign-up happen on the client or the Hosted UI; the API only validates the token.

**requirements.txt:** `pyjwt[crypto]==2.15.1`. Add `aioboto3==15.5.0` only if admin user-pool operations are needed.

**Settings and `.env.example`:**
```python
# Cognito
cognito_region: str = "us-east-1"
cognito_user_pool_id: str = ""
cognito_client_id: str = ""
cognito_token_use: str = "access"     # "access" or "id"

@property
def cognito_issuer(self) -> str:
    return f"https://cognito-idp.{self.cognito_region}.amazonaws.com/{self.cognito_user_pool_id}"
```
```
COGNITO_REGION=us-east-1
COGNITO_USER_POOL_ID=
COGNITO_CLIENT_ID=
COGNITO_TOKEN_USE=access
```

**Module:**
```python
from functools import lru_cache
from typing import Annotated, Any

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from app.core.config import Settings, get_settings
from app.core.exceptions import UnauthorizedError


class CognitoUser(BaseModel):
    sub: str
    username: str | None = None
    email: str | None = None
    groups: list[str] = []
    claims: dict[str, Any]


class CognitoVerifier:
    def __init__(self, settings: Settings):
        self.issuer = settings.cognito_issuer
        self.client_id = settings.cognito_client_id
        self.token_use = settings.cognito_token_use
        # PyJWKClient caches the JWKS; fetching is sync, so it runs in a threadpool.
        self.jwks = jwt.PyJWKClient(f"{self.issuer}/.well-known/jwks.json", cache_keys=True)

    async def verify(self, token: str) -> CognitoUser:
        try:
            signing_key = await run_in_threadpool(self.jwks.get_signing_key_from_jwt, token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                issuer=self.issuer,
                audience=self.client_id if self.token_use == "id" else None,
                options={"verify_aud": self.token_use == "id"},
            )
        except jwt.PyJWTError as exc:
            raise UnauthorizedError("Invalid token", code="invalid_token") from exc
        if claims.get("token_use") != self.token_use:
            raise UnauthorizedError("Wrong token use", code="invalid_token")
        if self.token_use == "access" and claims.get("client_id") != self.client_id:
            raise UnauthorizedError("Wrong client", code="invalid_token")
        return CognitoUser(
            sub=claims["sub"],
            username=claims.get("username") or claims.get("cognito:username"),
            email=claims.get("email"),
            groups=claims.get("cognito:groups", []),
            claims=claims,
        )


@lru_cache
def get_cognito_verifier() -> CognitoVerifier:
    return CognitoVerifier(get_settings())


bearer_scheme = HTTPBearer(auto_error=False)


async def get_cognito_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    verifier: Annotated[CognitoVerifier, Depends(get_cognito_verifier)],
) -> CognitoUser:
    if credentials is None:
        raise UnauthorizedError()
    user = await verifier.verify(credentials.credentials)
    request.state.user_sub = user.sub
    return user
```
**Usage:** `user: Annotated[CognitoUser, Depends(get_cognito_user)]` on a route, or `dependencies=[Depends(get_cognito_user)]` on a router.
