#!/bin/bash

# ===== PAPERSPACE DEBUG SCRIPT =====
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

echo_info "🔍 Paperspace Debug Script"
echo_info "Project Directory: $PROJECT_DIR"
echo_info "Current Directory: $PWD"
echo_info "Current User: $(whoami)"

# ===== CHECK 1: SUDO ACCESS =====
check_sudo() {
    echo_info "🔑 Checking sudo access..."
    
    if sudo -n true 2>/dev/null; then
        echo_info "✅ Sudo access: Available (no password needed)"
        return 0
    else
        echo_warn "⚠️ Sudo access: Password required or not available"
        echo_info "Trying to create directories without sudo..."
        return 1
    fi
}

# ===== CHECK 2: DIRECTORIES =====
check_directories() {
    echo_info "📁 Checking directories..."
    
    # Check if /mnt exists and is writable
    if [ -d "/mnt" ]; then
        echo_info "✅ /mnt directory exists"
        if [ -w "/mnt" ]; then
            echo_info "✅ /mnt is writable"
        else
            echo_warn "⚠️ /mnt is not writable by current user"
        fi
    else
        echo_error "❌ /mnt directory does not exist"
    fi
    
    # Check /mnt/gdrive
    if [ -d "/mnt/gdrive" ]; then
        echo_info "✅ /mnt/gdrive exists"
        ls -la /mnt/gdrive/ 2>/dev/null || echo_warn "Cannot list /mnt/gdrive contents"
    else
        echo_warn "⚠️ /mnt/gdrive does not exist"
    fi
    
    # Check project directories
    echo_info "📂 Project directories:"
    ls -la "$PROJECT_DIR"/ 2>/dev/null || echo_error "Cannot access project directory"
}

# ===== CHECK 3: RCLONE =====
check_rclone() {
    echo_info "☁️ Checking rclone..."
    
    if command -v rclone &> /dev/null; then
        echo_info "✅ Rclone installed: $(rclone version | head -1)"
    else
        echo_error "❌ Rclone not installed"
        return 1
    fi
    
    if [ -f "$RCLONE_CONFIG" ]; then
        echo_info "✅ Rclone config exists: $RCLONE_CONFIG"
        
        # Test connection
        if rclone lsd alldrive: --config="$RCLONE_CONFIG" &>/dev/null; then
            echo_info "✅ Rclone connection: Working"
        else
            echo_error "❌ Rclone connection: Failed"
        fi
    else
        echo_error "❌ Rclone config not found: $RCLONE_CONFIG"
    fi
}

# ===== CHECK 4: DOCKER =====
check_docker() {
    echo_info "🐳 Checking Docker..."
    
    if command -v docker &> /dev/null; then
        echo_info "✅ Docker installed: $(docker --version)"
        
        # Check if user in docker group
        if groups | grep -q docker; then
            echo_info "✅ User in docker group"
        else
            echo_warn "⚠️ User not in docker group"
        fi
        
        # Test docker access
        if docker ps &>/dev/null; then
            echo_info "✅ Docker access: Working"
        else
            echo_error "❌ Docker access: Failed"
        fi
    else
        echo_error "❌ Docker not installed"
    fi
}

# ===== CHECK 5: SYSTEMD =====
check_systemd() {
    echo_info "⚙️ Checking systemd services..."
    
    if systemctl is-enabled rclone-mount &>/dev/null; then
        echo_info "✅ rclone-mount service: Enabled"
    else
        echo_warn "⚠️ rclone-mount service: Not enabled"
    fi
    
    if systemctl is-active rclone-mount &>/dev/null; then
        echo_info "✅ rclone-mount service: Active"
    else
        echo_warn "⚠️ rclone-mount service: Not active"
    fi
    
    # Check mount status
    if mountpoint -q /mnt/gdrive 2>/dev/null; then
        echo_info "✅ Google Drive mount: Active"
        df -h | grep gdrive || true
    else
        echo_warn "⚠️ Google Drive mount: Not mounted"
    fi
}

# ===== SAFE DIRECTORY SETUP =====
safe_setup_directories() {
    echo_info "🛠️ Setting up directories safely..."
    
    # Try with sudo first
    if check_sudo; then
        echo_info "Creating directories with sudo..."
        sudo mkdir -p /mnt/gdrive/{data,config} 2>/dev/null || true
        sudo chown -R 33:33 /mnt/gdrive 2>/dev/null || true
        sudo chmod -R 755 /mnt/gdrive 2>/dev/null || true
        echo_info "✅ Directories created with sudo"
    else
        echo_warn "Sudo not available, trying alternative approaches..."
        
        # Check if directories already exist
        if [ -d "/mnt/gdrive" ]; then
            echo_info "✅ /mnt/gdrive already exists"
        else
            echo_error "❌ Cannot create /mnt/gdrive without sudo"
            echo_info "💡 Please run: sudo mkdir -p /mnt/gdrive/{data,config}"
            return 1
        fi
    fi
}

# ===== MINIMAL DEPLOY =====
minimal_deploy() {
    echo_info "🚀 Attempting minimal deployment..."
    
    cd "$PROJECT_DIR"
    
    # Check essential files
    if [ ! -f "docker-compose.yml" ]; then
        echo_error "❌ docker-compose.yml not found"
        return 1
    fi
    
    if [ ! -f ".env" ]; then
        echo_error "❌ .env file not found"
        return 1
    fi
    
    # Stop existing containers
    echo_info "Stopping existing containers..."
    docker compose down 2>/dev/null || true
    
    # Start only database first
    echo_info "Starting database..."
    docker compose up db -d
    
    # Wait for database
    sleep 10
    
    # Start Redis
    echo_info "Starting Redis..."
    docker compose up redis -d
    
    # Start app
    echo_info "Starting Nextcloud app..."
    docker compose up app -d
    
    # Check status
    sleep 5
    docker compose ps
}

# ===== FIX SCRIPT =====
create_simple_fix() {
    echo_info "📝 Creating simplified fix script..."
    
    cat > "$PROJECT_DIR/simple_fix.sh" << 'SIMPLE_EOF'
#!/bin/bash

echo "🔧 Simple Nextcloud Fix"

# Go to project directory
cd ~/nextcloud-server

# Create .env if missing
if [ ! -f .env ]; then
    echo "Creating .env file..."
    MY_IP=$(curl -s ifconfig.me 2>/dev/null || echo "your-ip")
    cat > .env << EOF
COMPOSE_PROJECT_NAME=nextcloud-server
MYSQL_ROOT_PASSWORD=SecureRootPass123!
MYSQL_PASSWORD=SecureUserPass123!
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextclouduser
REDIS_PASSWORD=SecureRedisPass123!
TRUSTED_DOMAINS=localhost,127.0.0.1:8081,$MY_IP,your-domain.com
DOMAIN=your-domain.com
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=AdminPass123!
EOF
    echo "✅ .env created with IP: $MY_IP"
fi

# Setup rclone mount (manual step)
echo "⚠️  MANUAL STEP REQUIRED:"
echo "1. Run: sudo mkdir -p /mnt/gdrive/{data,config}"
echo "2. Run: sudo chown -R 33:33 /mnt/gdrive"
echo "3. Run: sudo systemctl start rclone-mount"
echo "4. Then run: ./simple_fix.sh deploy"

if [ "$1" = "deploy" ]; then
    echo "🚀 Starting deployment..."
    
    # Check mount
    if ! mountpoint -q /mnt/gdrive; then
        echo "❌ /mnt/gdrive not mounted! Please complete manual steps first."
        exit 1
    fi
    
    # Deploy
    docker compose down 2>/dev/null || true
    docker compose up -d
    
    sleep 30
    docker compose ps
    
    echo "✅ Deployment completed!"
    echo "🌐 Access: http://$(curl -s ifconfig.me 2>/dev/null):8081"
fi
SIMPLE_EOF

    chmod +x "$PROJECT_DIR/simple_fix.sh"
    echo_info "✅ Created simple_fix.sh"
}

# ===== MAIN MENU =====
main() {
    case "${1:-check}" in
        "check")
            check_sudo
            check_directories
            check_rclone
            check_docker
            check_systemd
            ;;
        "dirs")
            safe_setup_directories
            ;;
        "deploy")
            minimal_deploy
            ;;
        "fix")
            create_simple_fix
            echo_info "✅ Run: ./simple_fix.sh to continue"
            ;;
        "all")
            check_sudo
            check_directories
            check_rclone
            check_docker
            check_systemd
            safe_setup_directories
            create_simple_fix
            ;;
        *)
            echo_info "🎯 Paperspace Debug Script"
            echo_info "Usage: $0 [option]"
            echo_info ""
            echo_info "Options:"
            echo_info "  check  - Check all components (default)"
            echo_info "  dirs   - Setup directories safely"
            echo_info "  deploy - Minimal deployment"
            echo_info "  fix    - Create simple fix script"
            echo_info "  all    - Run all checks and create fix"
            ;;
    esac
}

main "$@"