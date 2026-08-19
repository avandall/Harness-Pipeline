"""Secret Vault Proxy (Layer 5 - Security).

Keeps raw credentials in host environment memory and injects them only into tool requests.
"""

import os
from typing import Dict, Optional


class SecretVaultProxy:
    """Manages secure key injection and sanitization."""

    def __init__(self, secrets: Optional[Dict[str, str]] = None):
        self._vault: Dict[str, str] = secrets or {}

    def set_secret(self, key: str, value: str) -> None:
        """Register a secret into the in-memory vault."""
        self._vault[key] = value

    def get_secret(self, key: str) -> Optional[str]:
        """Fetch a secret from vault or environment fallback."""
        return self._vault.get(key) or os.getenv(key)

    def sanitize_output(self, text: str) -> str:
        """Sanitize raw secret occurrences from text before returning to model context."""
        sanitized = text
        for secret_val in self._vault.values():
            if secret_val and len(secret_val) > 4:
                sanitized = sanitized.replace(secret_val, "[REDACTED_SECRET]")
        return sanitized
