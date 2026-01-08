/**
 * Server Info Watchdog Admin UI
 * 
 * JavaScript for managing watchdog configuration through the admin API.
 */

// State
let adminToken = '';
let currentConfig = null;
let defaultConfig = null;

// Threshold labels for display
const THRESHOLD_LABELS = {
    timestampAgeMinutes: 'Timestamp Age (minutes)',
    cpu: 'CPU Usage (%)',
    disk: 'Disk Usage (%)',
    memory: 'Memory Usage (%)',
    network_up: 'Network Upstream (bits/s)',
    network_down: 'Network Downstream (bits/s)',
    network_total: 'Network Total (bits/s)',
    processes: 'Process Count',
    users: 'Logged In Users',
    updates: 'Available Updates',
    system_restart: 'System Restart Required',
    linux_server_state_tool: 'Tool Commits Behind',
    gluster_unhealthy_peers: 'Gluster Unhealthy Peers',
    gluster_unhealthy_volumes: 'Gluster Unhealthy Volumes'
};

// DOM Elements
const loginSection = document.getElementById('login-section');
const configSection = document.getElementById('config-section');
const adminTokenInput = document.getElementById('admin-token');
const loginBtn = document.getElementById('login-btn');
const loginError = document.getElementById('login-error');
const saveBtn = document.getElementById('save-btn');
const reloadBtn = document.getElementById('reload-btn');
const logoutBtn = document.getElementById('logout-btn');
const resetThresholdsBtn = document.getElementById('reset-thresholds-btn');
const statusMessage = document.getElementById('status-message');
const thresholdsContainer = document.getElementById('thresholds-container');

// API Functions
async function apiCall(endpoint, method = 'GET', body = null) {
    const options = {
        method,
        headers: {
            'X-Watchdog-Admin-Token': adminToken,
            'Content-Type': 'application/json'
        }
    };

    if (body) {
        options.body = JSON.stringify(body);
    }

    const response = await fetch(`/v1/admin${endpoint}`, options);
    const data = await response.json();

    if (!response.ok) {
        // Handle 401 Unauthorized specifically to trigger logout
        if (response.status === 401) {
            handleLogout();
            throw new Error('Session expired or invalid token');
        }
        throw new Error(data.error || `HTTP ${response.status}`);
    }

    return data;
}

async function loadConfig() {
    const data = await apiCall('/config');
    currentConfig = data.config;
    populateForm(currentConfig);
    showStatus('Configuration loaded', 'success');
}

async function loadDefaults() {
    const data = await apiCall('/config/defaults');
    defaultConfig = data.defaults;
}

async function saveConfig() {
    try {
        const config = collectFormData();
        await apiCall('/config', 'POST', config);
        showStatus('Configuration saved successfully', 'success');
        await loadConfig();
    } catch (error) {
        showStatus(`Failed to save config: ${error.message}`, 'error');
    }
}

// UI Functions
function populateForm(config) {
    // Server settings
    document.getElementById('server-name').value = config.serverName || '';
    document.getElementById('gluster-handling').value = config.glusterNotInstalledHandling || 'error';

    // Chat IDs
    document.getElementById('error-chat-ids').value = (config.errorChatIds || []).join(',');
    document.getElementById('warning-chat-ids').value = (config.warningChatIds || []).join(',');
    document.getElementById('info-chat-ids').value = (config.infoChatIds || []).join(',');

    // Message frequency
    document.getElementById('freq-info').value = config.messageFrequency?.info || '1h';
    document.getElementById('freq-warning').value = config.messageFrequency?.warning || '1d';
    document.getElementById('freq-error').value = config.messageFrequency?.error || '3d';

    // Thresholds
    populateThresholds(config.thresholds || {});
}

function populateThresholds(thresholds) {
    thresholdsContainer.innerHTML = '';

    for (const [key, values] of Object.entries(thresholds)) {
        const label = THRESHOLD_LABELS[key] || key;
        const item = document.createElement('div');
        item.className = 'threshold-item';
        item.innerHTML = `
            <span class="threshold-label">${label}</span>
            <div class="input-group">
                <span class="input-label">Warning:</span>
                <input type="text" id="thresh-${key}-warning" value="${values.warning || ''}" />
            </div>
            <div class="input-group">
                <span class="input-label">Error:</span>
                <input type="text" id="thresh-${key}-error" value="${values.error || ''}" />
            </div>
        `;
        thresholdsContainer.appendChild(item);
    }
}

function collectFormData() {
    const config = {
        serverName: document.getElementById('server-name').value.trim(),
        glusterNotInstalledHandling: document.getElementById('gluster-handling').value,
        errorChatIds: parseChatIds(document.getElementById('error-chat-ids').value),
        warningChatIds: parseChatIds(document.getElementById('warning-chat-ids').value),
        infoChatIds: parseChatIds(document.getElementById('info-chat-ids').value),
        messageFrequency: {
            info: document.getElementById('freq-info').value.trim() || '1h',
            warning: document.getElementById('freq-warning').value.trim() || '1d',
            error: document.getElementById('freq-error').value.trim() || '3d'
        },
        thresholds: collectThresholds()
    };

    return config;
}

function collectThresholds() {
    const thresholds = {};
    const items = thresholdsContainer.querySelectorAll('.threshold-item');

    items.forEach(item => {
        const warningInput = item.querySelector('input[id$="-warning"]');
        const errorInput = item.querySelector('input[id$="-error"]');

        if (warningInput && errorInput) {
            const key = warningInput.id.replace('thresh-', '').replace('-warning', '');
            thresholds[key] = {
                warning: warningInput.value.trim(),
                error: errorInput.value.trim()
            };
        }
    });

    return thresholds;
}

function parseChatIds(str) {
    if (!str) return [];
    return str.split(',').map(id => id.trim()).filter(id => id);
}

function showStatus(message, type = 'success') {
    statusMessage.textContent = message;
    statusMessage.className = `status ${type}`;
    statusMessage.classList.remove('hidden');

    setTimeout(() => {
        statusMessage.classList.add('hidden');
    }, 5000);
}

function showLogin() {
    loginSection.classList.remove('hidden');
    configSection.classList.add('hidden');
    adminToken = '';
    localStorage.removeItem('watchdog_admin_token');
}

function showConfig() {
    loginSection.classList.add('hidden');
    configSection.classList.remove('hidden');
}

// Event Handlers
async function handleLogin() {
    const token = adminTokenInput.value.trim();
    if (!token) {
        loginError.textContent = 'Please enter a token';
        loginError.classList.remove('hidden');
        return;
    }

    const previousToken = adminToken;
    adminToken = token;
    loginError.classList.add('hidden');

    try {
        // Try to load config with the new token
        await loadConfig();
        // If we reach here, the token is valid
        await loadDefaults();
        localStorage.setItem('watchdog_admin_token', token);
        showConfig();
    } catch (error) {
        console.error('Login failed:', error);
        loginError.textContent = error.message === 'Unauthorized' 
            ? 'Invalid token' 
            : `Login failed: ${error.message}`;
        loginError.classList.remove('hidden');
        
        // Restore previous state
        adminToken = previousToken;
        if (!adminToken) {
            showLogin();
        }
    }
}

function handleLogout() {
    showLogin();
    adminTokenInput.value = '';
}

function handleResetThresholds() {
    if (defaultConfig && defaultConfig.thresholds) {
        populateThresholds(defaultConfig.thresholds);
        showStatus('Thresholds reset to defaults (not saved yet)', 'warning');
    }
}

// Initialize
function init() {
    // Check for saved token
    const savedToken = localStorage.getItem('watchdog_admin_token');
    if (savedToken) {
        adminToken = savedToken;
        adminTokenInput.value = savedToken;
        handleLogin();
    }

    // Event listeners
    loginBtn.addEventListener('click', handleLogin);
    adminTokenInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleLogin();
    });

    saveBtn.addEventListener('click', saveConfig);
    reloadBtn.addEventListener('click', loadConfig);
    logoutBtn.addEventListener('click', handleLogout);
    resetThresholdsBtn.addEventListener('click', handleResetThresholds);
}

// Start
document.addEventListener('DOMContentLoaded', init);
