#!/bin/bash

# ===== PAPERSPACE NEXTCLOUD FIX SCRIPT =====
# Script khusus untuk memperbaiki deployment di Paperspace

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect project directory
if [[ "$(basename $PWD)" == "nextcloud-server" ]]; then
    PROJECT_DIR="$PWD"
else
    PROJECT_DIR="$HOME/nextcloud-server"
fi

RCLONE_CONFIG="$PROJECT_DIR/rclone/rclone.conf"
USER_HOME="/home/paperspace"

echo_info "🔧 Paperspace Nextcloud Fix Script"
echo_info "Project Directory: $PROJECT_DIR"
echo_info "Rclone Config: $RCLONE_CONFIG"

# ===== FIX 1: SETUP RCLONE CONFIG =====
setup_rclone_config() {
    echo_info "📋 Setting up rclone configuration..."
    
    # Ensure rclone directory exists
    mkdir -p "$PROJECT_DIR/rclone"
    
    # Check if rclone config already exists
    if [ -f "$RCLONE_CONFIG" ]; then
        echo_info "✅ Rclone config already exists"
        
        # Test the config
        if rclone lsd alldrive: --config="$RCLONE_CONFIG" &>/dev/null; then
            echo_info "✅ Rclone connection test passed"
            return 0
        else
            echo_warn "⚠️ Rclone config exists but connection failed"
        fi
    fi
    
    echo_warn "🔑 Rclone config not found or not working"
    echo_info "Please configure rclone now..."
    echo_info "When prompted, name your remote as 'alldrive'"
    echo_info ""
    
    # Run rclone config and save to project directory
    RCLONE_CONFIG_FILE="$RCLONE_CONFIG" rclone config --config="$RCLONE_CONFIG"
    
    # Test the new config
    if rclone lsd alldrive: --config="$RCLONE_CONFIG" &>/dev/null; then
        echo_info "✅ Rclone configuration successful!"
    else
        echo_error "❌ Rclone configuration failed!"
        return 1
    fi
}

# ===== FIX 2: UPDATE SYSTEMD SERVICE PATH =====
fix_systemd_service() {
    echo_info "⚙️ Fixing systemd service for Paperspace paths..."
    
    # Create corrected systemd service
    sudo tee /etc/systemd/system/rclone-mount.service > /dev/null << SERVICE
[Unit]
Description=Rclone Mount Google Drive for Nextcloud
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStartPre=/bin/mkdir -p /mnt/gdrive
ExecStart=/usr/bin/rclone mount alldrive: /mnt/gdrive \\
    --config=$RCLONE_CONFIG \\
    --allow-other \\
    --allow-non-empty \\
    --dir-cache-time=1000h \\
    --vfs-cache-mode=full \\
    --vfs-cache-max-size=5G \\
    --vfs-cache-max-age=24h \\
    --vfs-read-chunk-size=32M \\
    --vfs-read-chunk-size-limit=2G \\
    --buffer-size=32M \\
    --umask=000 \\
    --uid=33 \\
    --gid=33 \\
    --poll-interval=15s \\
    --drive-chunk-size=32M \\
    --timeout=1h \\
    --log-level=INFO \\
    --log-file=/var/log/rclone-mount.log
ExecStop=/bin/fusermount -u /mnt/gdrive
Restart=always
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE

    # Reload systemd
    sudo systemctl daemon-reload
    sudo systemctl enable rclone-mount
    
    echo_info "✅ Systemd service updated with correct paths"
}

# ===== FIX 3: CREATE .ENV IF MISSING =====
create_env_file() {
    if [ ! -f "$PROJECT_DIR/.env" ]; then
        echo_info "📝 Creating .env file..."
        
        cat > "$PROJECT_DIR/.env" << 'EOF'
# ===== PROJECT CONFIG =====
COMPOSE_PROJECT_NAME=nextcloud-server

# ===== DATABASE CONFIG =====
MYSQL_ROOT_PASSWORD=SecureRootPass123!
MYSQL_PASSWORD=SecureUserPass123!
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextclouduser

# ===== REDIS CONFIG =====
REDIS_PASSWORD=SecureRedisPass123!

# ===== NEXTCLOUD CONFIG =====
TRUSTED_DOMAINS=localhost,127.0.0.1:8081,$(curl -s ifconfig.me 2>/dev/null || echo "your-vps-ip"),your-domain.com
DOMAIN=your-domain.com

# ===== ADMIN USER (untuk first setup) =====
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=AdminPass123!
EOF
        
        echo_info "✅ .env file created with auto-detected IP"
    else
        echo_info "✅ .env file already exists"
    fi
}

# ===== FIX 4: SETUP DIRECTORIES =====
setup_directories() {
    echo_info "📁 Setting up directories with correct permissions..."
    
    # Create mount directories
    sudo mkdir -p /mnt/gdrive/{data,config}
    
    # Set proper permissions for www-data (uid=33, gid=33)
    sudo chown -R 33:33 /mnt/gdrive
    sudo chmod -R 755 /mnt/gdrive
    
    echo_info "✅ Directories setup completed"
}

# ===== FIX 5: TEST DEPLOYMENT =====
test_deployment() {
    echo_info "🧪 Testing deployment components..."
    
    # Test rclone
    if rclone lsd alldrive: --config="$RCLONE_CONFIG" &>/dev/null; then
        echo_info "✅ Rclone: Working"
    else
        echo_error "❌ Rclone: Failed"
        return 1
    fi
    
    # Test docker
    if docker --version &>/dev/null; then
        echo_info "✅ Docker: Installed"
    else
        echo_error "❌ Docker: Not found"
        return 1
    fi
    
    # Test docker-compose files
    if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        echo_info "✅ Docker Compose: File exists"
    else
        echo_error "❌ Docker Compose: File missing"
        return 1
    fi
    
    echo_info "✅ All components ready for deployment"
}

# ===== QUICK DEPLOY =====
quick_deploy() {
    echo_info "🚀 Starting quick deployment..."
    
    cd "$PROJECT_DIR"
    
    # Stop existing if any
    docker compose down -v --remove-orphans 2>/dev/null || true
    sudo systemctl stop rclone-mount 2>/dev/null || true
    sudo fusermount -u /mnt/gdrive 2>/dev/null || true
    
    # Setup directories
    setup_directories
    
    # Start rclone mount
    echo_info "Starting rclone mount..."
    sudo systemctl start rclone-mount
    
    # Wait for mount
    for i in {1..30}; do
        if mountpoint -q /mnt/gdrive; then
            echo_info "✅ Mount ready after $i attempts"
            break
        fi
        sleep 2
    done
    
    if ! mountpoint -q /mnt/gdrive; then
        echo_error "❌ Mount failed!"
        sudo journalctl -u rclone-mount --no-pager -n 10
        return 1
    fi
    
    # Set permissions after mount
    sudo chown -R 33:33 /mnt/gdrive
    sudo chmod -R 755 /mnt/gdrive
    
    # Start containers
    echo_info "Starting containers..."
    docker compose --env-file .env up -d
    
    # Wait and check
    sleep 30
    docker compose ps
    
    echo_info "🎉 Deployment completed!"
    echo_info "🌐 Access: http://$(curl -s ifconfig.me 2>/dev/null || echo 'your-ip'):8081"
}

# ===== MAIN MENU =====
main() {
    case "${1:-menu}" in
        "rclone")
            setup_rclone_config
            ;;
        "systemd")
            fix_systemd_service
            ;;
        "env")
            create_env_file
            ;;
        "test")
            test_deployment
            ;;
        "deploy")
            quick_deploy
            ;;
        "fix")
            echo_info "🔧 Running all fixes..."
            setup_rclone_config || exit 1
            fix_systemd_service
            create_env_file
            setup_directories
            test_deployment
            ;;
        "full")
            echo_info "🚀 Running complete setup and deployment..."
            setup_rclone_config || exit 1
            fix_systemd_service
            create_env_file
            setup_directories
            test_deployment
            quick_deploy
            ;;
        *)
            echo_info "🎯 Paperspace Nextcloud Fix Script"
            echo_info "Usage: $0 [option]"
            echo_info ""
            echo_info "Options:"
            echo_info "  rclone   - Setup rclone Google Drive config"
            echo_info "  systemd  - Fix systemd service paths"
            echo_info "  env      - Create .env file"
            echo_info "  test     - Test all components"
            echo_info "  deploy   - Quick deploy (after fixes)"
            echo_info "  fix      - Run all fixes"
            echo_info "  full     - Complete setup + deploy"
            echo_info ""
            echo_info "Quick start: $0 full"
            ;;
    esac
}

main "$@"