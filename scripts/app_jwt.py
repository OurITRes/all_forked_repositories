#!/usr/bin/env python3
# scripts/app_jwt.py
# Usage: APP_ID and APP_PRIVATE_KEY must be in env
# Prints JWT to stdout
# Requires: PyJWT, cryptography

import os
import time

try:
    import jwt
except Exception as e:
    raise SystemExit(
        "Python package 'PyJWT' is required but not installed.\n"
        "Install it with: python -m pip install PyJWT cryptography\n"
        f"Original import error: {e}"
    )

app_id = os.environ.get("APP_ID", "").strip()
private_key = os.environ.get("APP_PRIVATE_KEY", "")

if not app_id or not private_key:
    raise SystemExit("APP_ID or APP_PRIVATE_KEY not set in environment (export as secrets).")

now = int(time.time())
payload = {"iat": now - 60, "exp": now + (9 * 60), "iss": app_id}
encoded = jwt.encode(payload, private_key, algorithm="RS256")

# jwt.encode may return bytes in some environments
if isinstance(encoded, bytes):
    encoded = encoded.decode("utf-8")

print(encoded)