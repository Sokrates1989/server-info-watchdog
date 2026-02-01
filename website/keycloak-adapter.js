/**
 * Fallback Keycloak adapter for when CDN is blocked.
 * This is a minimal stub that provides the Keycloak interface.
 * In production, the real Keycloak JS should be used.
 */

window.Keycloak = function(config) {
  this.config = config || {};
  this.realm = config.realm || 'watchdog';
  this.clientId = config.clientId || 'watchdog-frontend';
  this.url = config.url || 'http://localhost:9090';
  this.authenticated = false;
  this.tokenParsed = null;
  this.token = null;
  this.refreshToken = null;
  this.idToken = null;
};

window.Keycloak.__isFallback = true;

window.Keycloak.prototype = {
  init: function(options) {
    return new Promise((resolve, reject) => {
      console.warn('[Keycloak] Using fallback adapter - real Keycloak adapter not loaded');
      
      // Check if we have tokens in URL (callback from Keycloak)
      const urlParams = new URLSearchParams(window.location.search);
      const code = urlParams.get('code');
      const sessionState = urlParams.get('session_state');
      
      if (code && sessionState) {
        console.log('[Keycloak] Detected callback from Keycloak, but fallback adapter cannot handle tokens');
        // Clear the URL params
        window.history.replaceState({}, document.title, window.location.pathname);
        // Show error - we need real adapter
        resolve({ authenticated: false });
        return;
      }
      
      // For check-sso, just return not authenticated
      resolve({ authenticated: false });
    });
  },
  
  login: function(options) {
    const loginUrl = `${this.url}/realms/${this.realm}/protocol/openid-connect/auth?` +
      `client_id=${this.clientId}&` +
      `response_type=code&` +
      `redirect_uri=${encodeURIComponent(window.location.origin)}&` +
      `scope=openid`;
    window.location.href = loginUrl;
  },
  
  logout: function(options) {
    const logoutUrl = `${this.url}/realms/${this.realm}/protocol/openid-connect/logout?` +
      `redirect_uri=${encodeURIComponent(window.location.origin)}`;
    window.location.href = logoutUrl;
  },
  
  updateToken: function(minValidity) {
    return Promise.resolve(false);
  },
  
  isAuthenticated: function() {
    return this.authenticated;
  },
  
  tokenParsed: null,
  token: null,
  refreshToken: null,
  idToken: null
};

console.info('[Keycloak] Fallback adapter loaded');
