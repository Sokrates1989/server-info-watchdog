# 🔧 Setup Directory

This directory contains setup helpers and configuration templates.

## 📁 Structure

```
setup/
├── .env.template          # Environment configuration template
├── modules/               # Helper scripts
│   ├── docker_helpers.sh  # Bash Docker utilities
│   ├── docker_helpers.ps1 # PowerShell Docker utilities
│   ├── menu_handlers.sh   # Bash menu handlers
│   └── menu_handlers.ps1  # PowerShell menu handlers
└── README.md
```

## 🚀 Quick Start

1. Copy `.env.template` to `.env` in the project root:
   ```bash
   cp setup/.env.template .env
   ```

2. Edit `.env` with your configuration (especially Telegram settings)

3. Run quick-start:
   ```bash
   ./quick-start.sh      # Linux/Mac
   .\quick-start.ps1     # Windows
   ```

## 📝 Configuration Options

See `.env.template` for all available configuration options including:
- Docker image settings
- Telegram bot configuration
- Chat IDs for different alert levels
- Threshold settings
