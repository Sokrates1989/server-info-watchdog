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
    memory: 'Memory Usage (%)',
    disk: 'Disk Usage (%)',
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
const statusMessageBottom = document.getElementById('status-message-bottom');
const thresholdsContainer = document.getElementById('thresholds-container');

// Load and initialize action buttons
async function loadActionsComponent() {
    try {
        const response = await fetch('/actions.html');
        const actionsHtml = await response.text();
        
        // Insert actions HTML in both locations
        const actionsTop = document.getElementById('actions-top');
        const actionsBottom = document.getElementById('actions-bottom');
        
        if (actionsTop) {
            actionsTop.innerHTML = actionsHtml;
        }
        if (actionsBottom) {
            actionsBottom.innerHTML = actionsHtml;
        }
        
        // Re-attach event listeners to all action buttons
        attachActionListeners();
        
    } catch (error) {
        console.error('Failed to load actions component:', error);
        // Fallback: create actions manually
        createActionsFallback();
    }
}

// Create fallback actions if fetch fails
function createActionsFallback() {
    const actionsHtml = `
        <div class="card actions">
            <button id="save-btn" class="btn btn-primary">Save Configuration</button>
            <button id="reload-btn" class="btn btn-secondary">Reload from Server</button>
            <button id="logout-btn" class="btn btn-danger">Logout</button>
        </div>
    `;
    
    const actionsTop = document.getElementById('actions-top');
    const actionsBottom = document.getElementById('actions-bottom');
    
    if (actionsTop) actionsTop.innerHTML = actionsHtml;
    if (actionsBottom) actionsBottom.innerHTML = actionsHtml;
    
    attachActionListeners();
}

// Attach event listeners to action buttons
function attachActionListeners() {
    // Get all action buttons (both top and bottom)
    const saveBtns = document.querySelectorAll('#save-btn');
    const reloadBtns = document.querySelectorAll('#reload-btn');
    const logoutBtns = document.querySelectorAll('#logout-btn');
    
    // Attach event listeners to all instances
    saveBtns.forEach(btn => {
        btn.addEventListener('click', saveConfig);
    });
    
    reloadBtns.forEach(btn => {
        btn.addEventListener('click', loadConfig);
    });
    
    logoutBtns.forEach(btn => {
        btn.addEventListener('click', handleLogout);
    });
}

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

async function loadDefaults() {
    const data = await apiCall('/config/defaults');
    defaultConfig = data.defaults;
}

async function saveConfig() {
    try {
        const config = collectFormData();
        await apiCall('/config', 'POST', config);
        showStatus('Configuration saved successfully', 'success');
        // Load config silently without showing "Configuration loaded" message
        await loadConfig(true);
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

    // Define the desired order for consistent display
    const desiredOrder = [
        'cpu',
        'memory', 
        'disk',
        'gluster_unhealthy_peers',
        'gluster_unhealthy_volumes',
        'processes',
        'network_down',
        'network_total',
        'network_up',
        'users',
        'updates',
        'system_restart',
        'linux_server_state_tool',
        'timestampAgeMinutes'
    ];

    // Process thresholds in the desired order
    for (const key of desiredOrder) {
        if (!thresholds[key]) {
            continue; // Skip if threshold doesn't exist
        }
        
        const values = thresholds[key];
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
            <span class="threshold-label">${statusIcon} ${label}</span>
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
    // Handle undefined or null values
    if (value === undefined || value === null) {
        return 'N/A';
    }
    
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
            return `${value} min old`;
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
    // Update both status containers
    [statusMessage, statusMessageBottom].forEach(element => {
        if (element) {
            element.textContent = message;
            element.className = `status ${type}`;
            element.classList.remove('hidden');
        }
    });

    // Hide both after timeout
    setTimeout(() => {
        [statusMessage, statusMessageBottom].forEach(element => {
            if (element) {
                element.classList.add('hidden');
            }
        });
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
    // Load actions component after showing config
    loadActionsComponent();
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
        const response = await apiCall('/system-state');
        if (response.success) {
            return response.data;
        }
    } catch (error) {
        console.error('Failed to load system state:', error);
    }
    return null;
}

// Load configuration with current values
async function loadConfig(silent = false) {
    try {
        console.log('DEBUG: Starting loadConfig...');
        
        // Try to load both config and system state, but don't fail if system state is not available
        const configPromise = apiCall('/config');
        const systemStatePromise = loadSystemState().catch(err => {
            console.warn('System state endpoint not available, loading config only:', err);
            return null;
        });
        
        console.log('DEBUG: Waiting for API responses...');
        const [configResponse, systemState] = await Promise.all([configPromise, systemStatePromise]);
        
        console.log('DEBUG: Config response:', configResponse);
        console.log('DEBUG: System state:', systemState);
        
        if (configResponse.success) {
            const config = configResponse.config || configResponse.data || {};
            console.log('DEBUG: Config data loaded:', config);
            
            // Server settings
            const serverNameEl = document.getElementById('server-name');
            if (serverNameEl) {
                serverNameEl.value = config.serverName || '';
                console.log('DEBUG: Set server name');
            } else {
                console.error('DEBUG: server-name element not found');
            }
            
            const glusterEl = document.getElementById('gluster-handling');
            if (glusterEl) {
                glusterEl.value = config.glusterNotInstalledHandling || 'none';
                console.log('DEBUG: Set gluster handling');
            } else {
                console.error('DEBUG: gluster-handling element not found');
            }
            
            // Telegram chat IDs
            const errorChatEl = document.getElementById('error-chat-ids');
            if (errorChatEl) {
                errorChatEl.value = (config.errorChatIds || []).join(', ');
                console.log('DEBUG: Set error chat IDs');
            } else {
                console.error('DEBUG: error-chat-ids element not found');
            }
            
            const warningChatEl = document.getElementById('warning-chat-ids');
            if (warningChatEl) {
                warningChatEl.value = (config.warningChatIds || []).join(', ');
                console.log('DEBUG: Set warning chat IDs');
            } else {
                console.error('DEBUG: warning-chat-ids element not found');
            }
            
            const infoChatEl = document.getElementById('info-chat-ids');
            if (infoChatEl) {
                infoChatEl.value = (config.infoChatIds || []).join(', ');
                console.log('DEBUG: Set info chat IDs');
            } else {
                console.error('DEBUG: info-chat-ids element not found');
            }
            
            // Message frequency
            const freqInfoEl = document.getElementById('freq-info');
            if (freqInfoEl) {
                freqInfoEl.value = config.messageFrequency?.info || '1h';
                console.log('DEBUG: Set freq info');
            } else {
                console.error('DEBUG: freq-info element not found');
            }
            
            const freqWarningEl = document.getElementById('freq-warning');
            if (freqWarningEl) {
                freqWarningEl.value = config.messageFrequency?.warning || '1d';
                console.log('DEBUG: Set freq warning');
            } else {
                console.error('DEBUG: freq-warning element not found');
            }
            
            const freqErrorEl = document.getElementById('freq-error');
            if (freqErrorEl) {
                freqErrorEl.value = config.messageFrequency?.error || '3d';
                console.log('DEBUG: Set freq error');
            } else {
                console.error('DEBUG: freq-error element not found');
            }
            
            // Thresholds with current values (if available)
            console.log('DEBUG: About to populate thresholds...');
            populateThresholds(config.thresholds || {}, systemState?.current || {});
            
            currentConfig = config;
            if (!silent) {
                showStatus('Configuration loaded', 'success');
            }
            console.log('DEBUG: Configuration loaded successfully');
        } else {
            console.error('DEBUG: Config response not successful:', configResponse);
            showStatus('Failed to load configuration', 'error');
        }
    } catch (error) {
        console.error('DEBUG: Error in loadConfig:', error);
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

    // Event listeners for login form
    loginBtn.addEventListener('click', handleLogin);
    adminTokenInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleLogin();
    });

    // Reset thresholds button
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
