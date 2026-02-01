/**
 * Keycloak Authentication Module for Server Info Watchdog Admin UI.
 *
 * This module provides Keycloak integration for the admin dashboard.
 * It handles login, logout, token refresh, and access token retrieval.
 *
 * Dependencies:
 * - Keycloak JS adapter (loaded dynamically)
 */

/**
 * Keycloak configuration values.
 *
 * @type {{url: string, realm: string, clientId: string}}
 */
const KEYCLOAK_CONFIG = {
  url: window.KEYCLOAK_URL || 'http://localhost:9090',
  realm: window.KEYCLOAK_REALM || 'watchdog',
  clientId: window.KEYCLOAK_CLIENT_ID || 'watchdog-frontend'
};

/**
 * Load a script tag dynamically.
 *
 * @param {string} src - Script URL to load.
 * @returns {Promise<void>} Resolves when the script loads.
 */
function loadScript(src) {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = src;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
    document.head.appendChild(script);
  });
}

/**
 * Ensure the Keycloak JS adapter is loaded.
 *
 * @returns {Promise<boolean>} True if the adapter is loaded.
 */
async function loadKeycloakAdapter() {
  if (typeof Keycloak !== 'undefined') {
    return true;
  }

  const baseUrl = KEYCLOAK_CONFIG.url.replace(/\/$/, '');
  const sources = [
    '/keycloak-adapter.js', // Local bundled adapter first (most reliable)
    `${baseUrl}/js/keycloak.js`,
    `${baseUrl}/auth/js/keycloak.js`,
    'https://cdn.jsdelivr.net/npm/keycloak-js@26.0.0/dist/keycloak.min.js'
  ];

  for (const src of sources) {
    try {
      await loadScript(src);
      if (typeof Keycloak !== 'undefined') {
        return true;
      }
    } catch (error) {
      console.warn('[Keycloak] Adapter load failed:', error.message || error);
    }
  }

  return false;
}

/**
 * Check if the loaded Keycloak adapter is the local fallback stub.
 *
 * @returns {boolean} True when the fallback adapter is active.
 */
function isKeycloakAdapterFallback() {
  return typeof Keycloak !== 'undefined' && Keycloak.__isFallback === true;
}

/** Keycloak instance. */
let keycloak = null;

/** Flag to indicate if Keycloak is enabled. */
let keycloakEnabled = false;

/**
 * Check if Keycloak authentication is enabled.
 *
 * @returns {boolean} True if Keycloak is enabled.
 */
function isKeycloakEnabled() {
  return keycloakEnabled && keycloak !== null;
}

/**
 * Initialize Keycloak authentication.
 *
 * @returns {Promise<boolean>} True if initialization succeeded and user is authenticated.
 */
async function initKeycloak() {
  keycloakEnabled = window.KEYCLOAK_ENABLED === true || window.KEYCLOAK_ENABLED === 'true';
  if (!keycloakEnabled) {
    console.log('[Keycloak] Keycloak authentication is disabled');
    return false;
  }

  const adapterLoaded = await loadKeycloakAdapter();
  if (!adapterLoaded) {
    throw new Error('Keycloak JS adapter is not loaded.');
  }

  try {
    keycloak = new Keycloak(KEYCLOAK_CONFIG);

    keycloak.onTokenExpired = () => {
      keycloak.updateToken(30).catch(() => {
        handleKeycloakLogout();
      });
    };

    const silentSsoEnabled = window.KEYCLOAK_SILENT_SSO === true || window.KEYCLOAK_SILENT_SSO === 'true';
    const initOptions = {
      pkceMethod: 'S256',
      checkLoginIframe: false
    };

    if (silentSsoEnabled) {
      initOptions.onLoad = 'check-sso';
      initOptions.silentCheckSsoRedirectUri = window.location.origin + '/silent-check-sso.html';
    }

    const authenticated = await keycloak.init(initOptions);

    if (authenticated) {
      console.log('[Keycloak] User is authenticated');
      return true;
    }

    console.log('[Keycloak] User is not authenticated');
    return false;
  } catch (error) {
    console.error('[Keycloak] Initialization failed:', error);
    keycloakEnabled = false;
    return false;
  }
}

/**
 * Trigger Keycloak login flow.
 *
 * @returns {Promise<void>}
 */
async function keycloakLogin() {
  if (!isKeycloakEnabled()) {
    throw new Error('Keycloak is not enabled or initialized.');
  }

  await keycloak.login({
    redirectUri: window.location.origin + window.location.pathname
  });
}

/**
 * Trigger Keycloak logout flow.
 *
 * @returns {Promise<void>}
 */
async function keycloakLogout() {
  if (!isKeycloakEnabled()) {
    throw new Error('Keycloak is not enabled or initialized.');
  }

  const logoutOptions = {
    redirectUri: window.location.origin + window.location.pathname
  };

  if (keycloak?.idToken) {
    logoutOptions.idTokenHint = keycloak.idToken;
  }

  await keycloak.logout(logoutOptions);
}

/**
 * Handle logout when token refresh fails.
 */
function handleKeycloakLogout() {
  if (typeof handleLogout === 'function') {
    handleLogout();
  }
}

/**
 * Get the current Keycloak access token.
 *
 * @returns {Promise<string|null>} Access token or null if not authenticated.
 */
async function getKeycloakToken() {
  if (!isKeycloakEnabled() || !keycloak.authenticated) {
    return null;
  }

  try {
    await keycloak.updateToken(30);
    return keycloak.token;
  } catch (error) {
    console.error('[Keycloak] Failed to refresh token:', error);
    return null;
  }
}

/**
 * Check whether the user is authenticated.
 *
 * @returns {boolean} True if authenticated.
 */
function isKeycloakAuthenticated() {
  return isKeycloakEnabled() && keycloak?.authenticated === true;
}

/**
 * Get current user info from the token.
 *
 * @returns {Object|null} User info object or null if not authenticated.
 */
function getKeycloakUser() {
  if (!isKeycloakAuthenticated()) {
    return null;
  }

  const token = keycloak.tokenParsed || {};
  return {
    id: token.sub,
    username: token.preferred_username,
    email: token.email,
    name: token.name || token.preferred_username
  };
}

// Export functions to global scope
window.initKeycloak = initKeycloak;
window.isKeycloakEnabled = isKeycloakEnabled;
window.isKeycloakAuthenticated = isKeycloakAuthenticated;
window.keycloakLogin = keycloakLogin;
window.keycloakLogout = keycloakLogout;
window.getKeycloakToken = getKeycloakToken;
window.getKeycloakUser = getKeycloakUser;
window.isKeycloakAdapterFallback = isKeycloakAdapterFallback;
