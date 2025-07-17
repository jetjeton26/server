#!/bin/bash

# ===== WARNA OUTPUT =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# ===== VARIABEL =====
PROJECT_DIR="$HOME/nextcloud-server"
RCLONE_CONFIG="$PROJECT_DIR/rclone/rclone.conf"
MOUNT_DIR="/mnt/gdrive"

# ===== FUNGSI UTILITAS =====
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo_error "Command '$1' not found. Please install it first."
        return 1
    fi
    return 0
}

wait_for_mount() {
    local retries=30
    echo_info "Waiting for rclone mount to be ready..."
    
    for ((i=1; i<=retries; i++)); do
        if mountpoint -q "$MOUNT_DIR"; then
            echo_info "✅ Mount ready after $i attempts"
            return 0
        fi
        echo_debug "Attempt $i/$retries: Mount not ready, waiting..."
        sleep 2
    done
    
    echo_error "❌ Mount failed after $retries attempts"
    return 1
}

# ===== INSTALASI PRASYARAT =====
install_prerequisites() {
    echo_info "�� Installing prerequisites..."
    
    # Update system
    sudo apt update && sudo apt upgrade -y
    
    # Install basic tools
    sudo apt install -y curl gnupg lsb-release ca-certificates \
        apt-transport-https software-properties-common fuse
    
    # Install rclone if not exists
    if ! check_command rclone; then
        echo_info "Installing rclone..."
        curl https://rclone.org/install.sh | sudo bash
    fi
    
    # Install Docker if not exists
    if ! check_command docker; then
        echo_info "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        echo_warn "Please log out and log back in for Docker group changes to take effect"
    fi
    
    # Enable Docker
    sudo systemctl enable docker
    sudo systemctl start docker
}

# ===== SETUP DIREKTORI =====
setup_directories() {
    echo_info "📁 Setting up directories..."
    
    # Create project directories
    mkdir -p "$PROJECT_DIR/rclone"
    
    # Create mount directories
    sudo mkdir -p "$MOUNT_DIR"/{data,config}
    
    # Set proper permissions for www-data (uid=33, gid=33)
    sudo chown -R 33:33 "$MOUNT_DIR"
    sudo chmod -R 755 "$MOUNT_DIR"
    
    echo_info "✅ Directories created and permissions set"
}

# ===== KONFIGURASI RCLONE =====
setup_rclone() {
    echo_info "☁️ Setting up rclone..."
    
    if [ ! -f "$RCLONE_CONFIG" ]; then
        echo_warn "Rclone config not found. Please run 'rclone config' to set up Google Drive."
        echo_info "Make sure to name your remote as 'alldrive'"
        return 1
    fi
    
    # Test rclone connection
    if ! rclone lsd alldrive: --config="$RCLONE_CONFIG" &>/dev/null; then
        echo_error "❌ Rclone connection test failed"
        return 1
    fi
    
    echo_info "✅ Rclone configuration verified"
    return 0
}

# ===== SETUP SYSTEMD SERVICE =====
setup_systemd_service() {
    echo_info "⚙️ Setting up rclone systemd service..."
    
    # Stop existing service if running
    sudo systemctl stop rclone-mount 2>/dev/null || true
    
    # Create service file
    sudo tee /etc/systemd/system/rclone-mount.service > /dev/null << SERVICE
[Unit]
Description=Rclone Mount Google Drive for Nextcloud
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStartPre=/bin/mkdir -p $MOUNT_DIR
ExecStart=/usr/bin/rclone mount alldrive: $MOUNT_DIR \\
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
ExecStop=/bin/fusermount -u $MOUNT_DIR
Restart=always
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable rclone-mount
    
    echo_info "✅ Systemd service configured"
}

# ===== DEPLOY BERSIH =====
clean_deploy() {
    echo_warn "🧹 Performing clean deployment..."
    
    # Stop all containers
    cd "$PROJECT_DIR"
    if [ -f docker-compose.yml ]; then
        docker compose down -v --remove-orphans 2>/dev/null || true
    fi
    
    # Stop and unmount rclone
    sudo systemctl stop rclone-mount 2>/dev/null || true
    sudo fusermount -u "$MOUNT_DIR" 2>/dev/null || true
    
    # Clean Docker resources
    docker volume prune -f
    docker system prune -f
    
    # Clean mount directories
    sudo rm -rf "$MOUNT_DIR"/data/* 2>/dev/null || true
    sudo rm -rf "$MOUNT_DIR"/config/* 2>/dev/null || true
    
    echo_info "✅ Clean deployment completed"
}

# ===== DEPLOY NEXTCLOUD =====
deploy_nextcloud() {
    echo_info "🚀 Deploying Nextcloud..."
    
    cd "$PROJECT_DIR"
    
    # Check if config files exist
    if [ ! -f docker-compose.yml ]; then
        echo_error "❌ docker-compose.yml not found in $PROJECT_DIR"
        return 1
    fi
    
    if [ ! -f .env ]; then
        echo_error "❌ .env file not found in $PROJECT_DIR"
        return 1
    fi
    
    # Start rclone mount
    echo_info "Starting rclone mount..."
    sudo systemctl start rclone-mount
    
    # Wait for mount to be ready
    if ! wait_for_mount; then
        echo_error "❌ Failed to mount Google Drive"
        return 1
    fi
    
    # Set permissions again after mount
    sudo chown -R 33:33 "$MOUNT_DIR"
    sudo chmod -R 755 "$MOUNT_DIR"
    
    # Start containers
    echo_info "Starting Docker containers..."
    docker compose --env-file .env up -d
    
    # Wait for containers to be ready
    echo_info "Waiting for containers to be ready..."
    sleep 30
    
    # Check container status
    echo_info "Container status:"
    docker compose ps
    
    # Test Nextcloud accessibility
    if curl -f http://localhost:8081/status.php &>/dev/null; then
        echo_info "✅ Nextcloud is accessible"
    else
        echo_warn "⚠️ Nextcloud might not be ready yet, check logs"
    fi
    
    echo_info "✅ Deployment completed!"
}

# ===== VERIFIKASI SYSTEM =====
verify_deployment() {
    echo_info "🔍 Verifying deployment..."
    
    # Check rclone mount
    if mountpoint -q "$MOUNT_DIR"; then
        echo_info "✅ Rclone mount: Active"
    else
        echo_error "❌ Rclone mount: Failed"
    fi
    
    # Check containers
    cd "$PROJECT_DIR"
    local containers=$(docker compose ps --services)
    for container in $containers; do
        if docker compose ps "$container" | grep -q "Up"; then
            echo_info "✅ Container $container: Running"
        else
            echo_error "❌ Container $container: Not running"
        fi
    done
    
    # Check Google Drive connectivity
    if rclone lsd alldrive: --config="$RCLONE_CONFIG" &>/dev/null; then
        echo_info "✅ Google Drive: Connected"
    else
        echo_error "❌ Google Drive: Connection failed"
    fi
    
    # Test file upload to mount
    local test_file="$MOUNT_DIR/data/test_$(date +%s).txt"
    if echo "Test upload" | sudo tee "$test_file" &>/dev/null; then
        echo_info "✅ File upload to mount: Success"
        sudo rm -f "$test_file"
    else
        echo_error "❌ File upload to mount: Failed"
    fi
}

# ===== TAMPILKAN INFO =====
show_info() {
    echo_info "📋 Deployment Information:"
    echo "🌐 Nextcloud URL: http://$(hostname -I | awk '{print $1}'):8081"
    echo "📁 Project Directory: $PROJECT_DIR"
    echo "☁️ Mount Directory: $MOUNT_DIR"
    echo "📝 Logs: docker compose logs -f"
    echo "🔍 Status: docker compose ps"
    echo "📊 Mount Status: df -h | grep gdrive"
}

# ===== MAIN FUNCTION =====
main() {
    echo_info "🎯 Nextcloud Deployment Script Started"
    echo_info "======================================="
    
    case "${1:-deploy}" in
        "install")
            install_prerequisites
            ;;
        "setup")
            setup_directories
            setup_rclone || exit 1
            setup_systemd_service
            ;;
        "clean")
            clean_deploy
            ;;
        "deploy")
            deploy_nextcloud
            ;;
        "verify")
            verify_deployment
            ;;
        "full")
            install_prerequisites
            setup_directories
            setup_rclone || exit 1
            setup_systemd_service
            clean_deploy
            deploy_nextcloud
            verify_deployment
            show_info
            ;;
        *)
            echo_info "Usage: $0 [install|setup|clean|deploy|verify|full]"
            echo_info "  install - Install prerequisites"
            echo_info "  setup   - Setup directories and services"
            echo_info "  clean   - Clean existing deployment"
            echo_info "  deploy  - Deploy Nextcloud containers"
            echo_info "  verify  - Verify deployment status"
            echo_info "  full    - Run complete deployment (default)"
            exit 1
            ;;
    esac
    
    echo_info "🎉 Script completed successfully!"
}

# Run main function with all arguments
main "$@"
