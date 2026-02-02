"""
Keycloak authentication module for Server Info Watchdog Flask API.

This module provides JWT-based authentication using Keycloak as the identity provider.
It validates access tokens issued by Keycloak and extracts user information and roles.

Usage:
    from utils.keycloak_auth import get_keycloak_auth, KeycloakUser

Dependencies:
    - PyJWT[crypto]
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

try:
    import jwt
    from jwt import PyJWKClient, PyJWKClientError
    JWT_AVAILABLE = True
except ImportError:
    JWT_AVAILABLE = False
    PyJWKClient = None
    PyJWKClientError = Exception


def get_keycloak_enabled() -> bool:
    """
    Check if Keycloak authentication is enabled via environment variable.

    Returns:
        bool: True if KEYCLOAK_ENABLED is set to 'true' (case-insensitive).
    """
    val = os.environ.get("KEYCLOAK_ENABLED", "false")
    return val.lower() in ("true", "1", "yes")


def get_keycloak_url() -> str:
    """
    Get the Keycloak server URL from environment.

    Returns:
        str: Keycloak URL.
    """
    return os.environ.get("KEYCLOAK_URL", "http://localhost:9090")


def get_keycloak_realm() -> str:
    """
    Get the Keycloak realm name from environment.

    Returns:
        str: Realm name.
    """
    return os.environ.get("KEYCLOAK_REALM", "watchdog")


def get_keycloak_client_id() -> str:
    """
    Get the Keycloak client ID from environment.

    Returns:
        str: Client ID.
    """
    return os.environ.get("KEYCLOAK_CLIENT_ID", "watchdog-backend")


def get_keycloak_client_secret() -> Optional[str]:
    """
    Get the Keycloak client secret from environment or Docker secret file.

    Checks KEYCLOAK_CLIENT_SECRET_FILE first (for Docker secrets),
    then falls back to KEYCLOAK_CLIENT_SECRET environment variable.

    Returns:
        Optional[str]: Client secret or None.
    """
    # Check for Docker secret file first
    secret_file = os.environ.get("KEYCLOAK_CLIENT_SECRET_FILE")
    if secret_file and os.path.isfile(secret_file):
        try:
            with open(secret_file, "r") as f:
                secret = f.read().strip()
                if secret:
                    return secret
        except Exception as e:
            print(f"[KEYCLOAK] Warning: Could not read secret file {secret_file}: {e}")
    
    # Fall back to environment variable
    return os.environ.get("KEYCLOAK_CLIENT_SECRET") or None


def get_keycloak_internal_url() -> Optional[str]:
    """
    Get the internal Keycloak URL for Docker networking.

    Returns:
        Optional[str]: Internal URL or None.
    """
    return os.environ.get("KEYCLOAK_INTERNAL_URL") or None


@dataclass
class KeycloakUser:
    """
    Represents an authenticated Keycloak user.

    Attributes:
        sub: User's unique identifier (subject claim)
        username: User's preferred username
        email: User's email address
        email_verified: Whether email is verified
        name: User's full name
        given_name: User's first name
        family_name: User's last name
        roles: List of realm roles assigned to the user
        token_exp: Token expiration timestamp
        raw_token: The raw JWT token payload
    """

    sub: str
    username: str
    email: str = ""
    email_verified: bool = False
    name: str = ""
    given_name: str = ""
    family_name: str = ""
    roles: List[str] = field(default_factory=list)
    token_exp: Optional[datetime] = None
    raw_token: Dict[str, Any] = field(default_factory=dict)

    def has_role(self, role: str) -> bool:
        """
        Check if user has a specific role.

        Args:
            role: Role name to check.

        Returns:
            True if user has the role, False otherwise.
        """
        return role in self.roles

    def has_any_role(self, roles: List[str]) -> bool:
        """
        Check if user has any of the specified roles.

        Args:
            roles: List of role names to check.

        Returns:
            True if user has at least one of the roles.
        """
        return bool(set(self.roles) & set(roles))


class KeycloakAuth:
    """
    Keycloak authentication handler for Flask.

    This class handles JWT token validation using Keycloak's JWKS endpoint.
    """

    def __init__(
        self,
        keycloak_url: str,
        realm: str,
        client_id: str,
        client_secret: Optional[str] = None,
        internal_url: Optional[str] = None,
    ):
        """
        Initialize the Keycloak authentication handler.

        Args:
            keycloak_url: Base URL of the Keycloak server (e.g., http://localhost:9090)
            realm: Name of the Keycloak realm
            client_id: Client ID for the backend application
            client_secret: Client secret (optional, for confidential clients)
            internal_url: Internal URL for JWKS fetching (e.g., http://keycloak:9090 in Docker)
        """
        self.keycloak_url = keycloak_url.rstrip("/")
        self.realm = realm
        self.client_id = client_id
        self.client_secret = client_secret

        # Use internal URL for API calls if provided, otherwise use public URL
        self.internal_url = (internal_url or keycloak_url).rstrip("/")

        # Build OIDC endpoints - issuer uses public URL, JWKS uses internal URL
        self.issuer = f"{self.keycloak_url}/realms/{self.realm}"
        self.jwks_uri = f"{self.internal_url}/realms/{self.realm}/protocol/openid-connect/certs"

        # Initialize JWKS client (lazy loading)
        self._jwks_client: Optional[Any] = None

    @property
    def jwks_client(self) -> Any:
        """
        Get or create the JWKS client for token validation.

        Returns:
            PyJWKClient instance.

        Raises:
            RuntimeError: If JWT library is not available.
        """
        if self._jwks_client is None:
            if not JWT_AVAILABLE or PyJWKClient is None:
                raise RuntimeError("JWT library not available. Install PyJWT[crypto].")
            self._jwks_client = PyJWKClient(self.jwks_uri, cache_keys=True)
        return self._jwks_client

    def _extract_roles(self, token_payload: Dict[str, Any]) -> List[str]:
        """
        Extract realm roles from the token payload.

        Args:
            token_payload: Decoded JWT payload.

        Returns:
            List of role names.
        """
        roles = []

        # Try to get roles from the 'roles' claim (custom mapper)
        if "roles" in token_payload:
            claim_roles = token_payload["roles"]
            if isinstance(claim_roles, list):
                roles.extend(claim_roles)
            elif isinstance(claim_roles, str):
                roles.append(claim_roles)

        # Also check realm_access.roles (default Keycloak structure)
        realm_access = token_payload.get("realm_access", {})
        if isinstance(realm_access, dict) and "roles" in realm_access:
            roles.extend(realm_access["roles"])

        # Also check resource_access for client-specific roles
        resource_access = token_payload.get("resource_access", {})
        if isinstance(resource_access, dict):
            for client_roles in resource_access.values():
                if isinstance(client_roles, dict) and "roles" in client_roles:
                    roles.extend(client_roles["roles"])

        # Remove duplicates while preserving order
        seen = set()
        unique_roles = []
        for role in roles:
            if role not in seen:
                seen.add(role)
                unique_roles.append(role)

        return unique_roles

    def validate_token(self, token: str) -> KeycloakUser:
        """
        Validate a JWT access token and extract user information.

        Args:
            token: JWT access token string.

        Returns:
            KeycloakUser object with user information.

        Raises:
            ValueError: If token is invalid, expired, or verification fails.
        """
        if not JWT_AVAILABLE:
            raise RuntimeError("JWT library not available. Install PyJWT[crypto].")

        try:
            # Get the signing key from JWKS
            signing_key = self.jwks_client.get_signing_key_from_jwt(token)

            # Decode and validate the token
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience="account",
                issuer=self.issuer,
                options={
                    "verify_exp": True,
                    "verify_iat": True,
                    "verify_aud": False,
                    "require": ["exp", "iat"],
                },
            )

            # Extract expiration time
            exp_timestamp = payload.get("exp")
            token_exp = None
            if exp_timestamp:
                token_exp = datetime.fromtimestamp(exp_timestamp, tz=timezone.utc)

            # Build user object
            user_id = payload.get("sub") or payload.get("sid") or payload.get("azp") or ""
            username = payload.get("preferred_username") or payload.get("name") or user_id

            return KeycloakUser(
                sub=user_id,
                username=username,
                email=payload.get("email", ""),
                email_verified=payload.get("email_verified", False),
                name=payload.get("name", ""),
                given_name=payload.get("given_name", ""),
                family_name=payload.get("family_name", ""),
                roles=self._extract_roles(payload),
                token_exp=token_exp,
                raw_token=payload,
            )

        except jwt.ExpiredSignatureError:
            raise ValueError("Token has expired")
        except jwt.InvalidTokenError as e:
            raise ValueError(f"Invalid token: {e}")
        except Exception as e:
            raise ValueError(f"Token validation failed: {e}")


# Global Keycloak auth instance (lazy initialization)
_keycloak_auth: Optional[KeycloakAuth] = None


def get_keycloak_auth() -> Optional[KeycloakAuth]:
    """
    Get or create the global KeycloakAuth instance.

    Returns:
        KeycloakAuth instance if Keycloak is enabled and JWT is available, None otherwise.
    """
    global _keycloak_auth

    if not get_keycloak_enabled():
        return None

    if not JWT_AVAILABLE:
        print("[KEYCLOAK] Warning: PyJWT not available, Keycloak auth disabled")
        return None

    if _keycloak_auth is None:
        _keycloak_auth = KeycloakAuth(
            keycloak_url=get_keycloak_url(),
            realm=get_keycloak_realm(),
            client_id=get_keycloak_client_id(),
            client_secret=get_keycloak_client_secret(),
            internal_url=get_keycloak_internal_url(),
        )

    return _keycloak_auth


# Role constants for watchdog
ROLE_ADMIN = "watchdog:admin"
ROLE_READ = "watchdog:read"


def validate_bearer_token(auth_header: str) -> Optional[KeycloakUser]:
    """
    Validate a Bearer token from Authorization header.

    Args:
        auth_header: Authorization header value (e.g., "Bearer <token>")

    Returns:
        KeycloakUser if valid, None otherwise.
    """
    if not auth_header or not auth_header.startswith("Bearer "):
        return None

    token = auth_header[7:]  # Remove "Bearer " prefix
    keycloak = get_keycloak_auth()

    if keycloak is None:
        return None

    try:
        return keycloak.validate_token(token)
    except Exception as e:
        print(f"[KEYCLOAK] Token validation failed: {e}")
        return None
