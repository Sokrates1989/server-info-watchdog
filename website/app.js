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

function populateThresholds(thresholds, currentValues = null) {
    thresholdsContainer.innerHTML = '';

    for (const [key, values] of Object.entries(thresholds)) {
        const label = THRESHOLD_LABELS[key] || key;
        const currentValue = currentValues ? currentValues[key] : null;
        const currentValueStr = currentValue !== null ? formatCurrentValue(key, currentValue) : 'N/A';
        
        // Determine status based on current value vs thresholds
        let statusClass = '';
        let statusIcon = '';
        if (currentValue !== null) {
            const warningThreshold = parseFloat(values.warning);
            const errorThreshold = parseFloat(values.error);
            const current = parseFloat(currentValue);
            
            if (!isNaN(current) && !isNaN(warningThreshold) && !isNaN(errorThreshold)) {
                if (current >= errorThreshold) {
                    statusClass = 'status-error';
                    statusIcon = '🔴';
                } else if (current >= warningThreshold) {
                    statusClass = 'status-warning';
                    statusIcon = '🟡';
                } else {
                    statusClass = 'status-ok';
                    statusIcon = '🟢';
                }
            }
        }
        
        const item = document.createElement('div');
        item.className = 'threshold-item';
        item.innerHTML = `
            <span class="threshold-label">${label} ${statusIcon}</span>
            <div class="current-value">
                <span class="input-label">Current:</span>
                <span class="current-number ${statusClass}">${currentValueStr}</span>
            </div>
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

function formatCurrentValue(key, value) {
    // Format based on the metric type
    switch(key) {
        case 'cpu':
        case 'disk':
        case 'memory':
            return `${value}%`;
        case 'network_up':
        case 'network_down':
        case 'network_total':
            return formatBytes(value);
        case 'timestampAgeMinutes':
            return `${value} min`;
        case 'system_restart':
            return `${value} days`;
        case 'processes':
        case 'users':
        case 'updates':
        case 'linux_server_state_tool':
        case 'gluster_unhealthy_peers':
        case 'gluster_unhealthy_volumes':
            return value.toString();
        default:
            return value.toString();
    }
}

function formatBytes(bits) {
    if (bits === 0) return '0 bps';
    const units = ['bps', 'Kbps', 'Mbps', 'Gbps'];
    const k = 1000;
    const i = Math.floor(Math.log(bits) / Math.log(k));
    return parseFloat((bits / Math.pow(k, i)).toFixed(2)) + ' ' + units[i];
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

// Load and display version information
async function loadVersion() {
    try {
        const response = await fetch('/version.json');
        if (response.ok) {
            const versionData = await response.json();
            const webVersionElement = document.getElementById('webVersion');
            if (webVersionElement) {
                webVersionElement.textContent = versionData.version || 'unknown';
            }
        }
    } catch (error) {
        console.error('Failed to load version:', error);
        const webVersionElement = document.getElementById('webVersion');
        if (webVersionElement) {
            webVersionElement.textContent = 'unknown';
        }
    }
}

// Load current system state
async function loadSystemState() {
    try {
        const response = await apiCall('/v1/admin/system-state');
        if (response.success) {
            return response.data;
        }
    } catch (error) {
        console.error('Failed to load system state:', error);
    }
    return null;
}

// Load configuration with current values
async function loadConfig() {
    try {
        const [configResponse, systemState] = await Promise.all([
            apiCall('/v1/admin/config'),
            loadSystemState()
        ]);
        
        if (configResponse.success) {
            const config = configResponse.data;
            
            // Server settings
            document.getElementById('server-name').value = config.serverName || '';
            document.getElementById('gluster-handling').value = config.glusterNotInstalledHandling || 'none';
            
            // Telegram chat IDs
            document.getElementById('error-chat-ids').value = (config.errorChatIds || []).join(', ');
            document.getElementById('warning-chat-ids').value = (config.warningChatIds || []).join(', ');
            document.getElementById('info-chat-ids').value = (config.infoChatIds || []).join(', ');
            
            // Message frequency
            document.getElementById('freq-info').value = config.messageFrequency?.info || '1h';
            document.getElementById('freq-warning').value = config.messageFrequency?.warning || '1d';
            document.getElementById('freq-error').value = config.messageFrequency?.error || '3d';
            
            // Thresholds with current values
            populateThresholds(config.thresholds || {}, systemState?.current || {});
            
            currentConfig = config;
        }
    } catch (error) {
        console.error('Failed to load config:', error);
        showStatus('Failed to load configuration', 'error');
    }
}

// Initialize
function init() {
    // Load version immediately
    loadVersion();
    
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
    
    // Add refresh current values button
    const refreshCurrentBtn = document.getElementById('refresh-current-btn');
    if (refreshCurrentBtn) {
        refreshCurrentBtn.addEventListener('click', () => {
            loadConfig();
            showStatus('Current values refreshed', 'success');
        });
    }
}

// Start
document.addEventListener('DOMContentLoaded', init);
