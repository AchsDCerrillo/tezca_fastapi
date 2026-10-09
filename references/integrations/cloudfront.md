# AWS CloudFront (`app/core/cloudfront.py`)

Two jobs: build (optionally signed) URLs for files served through a distribution, and invalidate cached paths.

**requirements.txt:** `aioboto3==15.5.0`, `cryptography==<latest>`. Check the version: `pip index versions cryptography`.

**Settings and `.env.example`:**
```python
# CloudFront
cloudfront_domain: str = ""                    # d111111abcdef8.cloudfront.net or cdn.example.com
cloudfront_distribution_id: str = ""
cloudfront_key_pair_id: str | None = None      # public key id, only for signed URLs
cloudfront_private_key: str | None = None      # PEM contents (\n-escaped) or load from Secrets Manager
```
```
CLOUDFRONT_DOMAIN=
CLOUDFRONT_DISTRIBUTION_ID=
CLOUDFRONT_KEY_PAIR_ID=
CLOUDFRONT_PRIVATE_KEY=
```
Also needs `aws_region` / AWS credentials (see s3.md).

**Class:**
```python
import time
from datetime import datetime, timedelta, timezone
from functools import lru_cache

import aioboto3
from botocore.signers import CloudFrontSigner
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

from app.core.config import get_settings


class CloudFrontCDN:
    def __init__(
        self,
        domain: str,
        distribution_id: str,
        key_pair_id: str | None,
        private_key_pem: str | None,
        region: str,
        access_key_id: str | None = None,
        secret_access_key: str | None = None,
    ):
        self.domain = domain
        self.distribution_id = distribution_id
        self._signer = None
        if key_pair_id and private_key_pem:
            key = serialization.load_pem_private_key(private_key_pem.replace("\\n", "\n").encode(), password=None)
            self._signer = CloudFrontSigner(
                key_pair_id, lambda message: key.sign(message, padding.PKCS1v15(), hashes.SHA1())
            )
        self._session = aioboto3.Session(
            aws_access_key_id=access_key_id, aws_secret_access_key=secret_access_key, region_name=region
        )

    def url(self, path: str) -> str:
        return f"https://{self.domain}/{path.lstrip('/')}"

    def signed_url(self, path: str, expires_in: int = 3600) -> str:
        if self._signer is None:
            raise RuntimeError("CloudFront signing is not configured (key pair id / private key missing)")
        expires = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
        return self._signer.generate_presigned_url(self.url(path), date_less_than=expires)

    async def invalidate(self, paths: list[str]) -> str:
        async with self._session.client("cloudfront") as cf:
            response = await cf.create_invalidation(
                DistributionId=self.distribution_id,
                InvalidationBatch={
                    "Paths": {"Quantity": len(paths), "Items": ["/" + p.lstrip("/") for p in paths]},
                    "CallerReference": str(time.time_ns()),
                },
            )
        return response["Invalidation"]["Id"]


@lru_cache
def get_cloudfront() -> CloudFrontCDN:
    s = get_settings()
    return CloudFrontCDN(
        domain=s.cloudfront_domain,
        distribution_id=s.cloudfront_distribution_id,
        key_pair_id=s.cloudfront_key_pair_id,
        private_key_pem=s.cloudfront_private_key,
        region=s.aws_region,
        access_key_id=s.aws_access_key_id,
        secret_access_key=s.aws_secret_access_key,
    )
```
**Notes:**
- CloudFront signed URLs require SHA1 + PKCS1v15; that is the AWS spec.
- Usually paired with S3: upload with `S3Storage`, then serve with `get_cloudfront().signed_url(key)`.
