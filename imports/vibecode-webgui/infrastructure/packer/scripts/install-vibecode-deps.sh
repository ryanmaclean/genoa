#!/bin/bash
#
# VibeCode Dependency Installation Script for LX Zone
#
# This script installs all required dependencies for running VibeCode
# inside an LX branded zone on OmniOS.
#
# Requirements:
# - Debian 12 or Ubuntu 22.04 LTS inside LX zone
# - Internet connectivity
# - Run as root inside the zone
#
# Installs:
# - Node.js 24 (via NodeSource)
# - PostgreSQL 16 + pgvector extension
# - Valkey (Redis alternative) or Redis
# - Nginx (reverse proxy)
# - PM2 (Node.js process manager)
# - Build tools and system utilities
#
# Usage:
#   # From global zone:
#   zlogin vibecode-production /bin/bash -c "$(cat install-vibecode-deps.sh)"
#
#   # Or copy to zone and run:
#   cp install-vibecode-deps.sh /zones/vibecode-production/root/tmp/
#   zlogin vibecode-production
#   cd /tmp
#   chmod +x install-vibecode-deps.sh
#   ./install-vibecode-deps.sh
#
# Author: Generated for VibeCode deployment
# Date: October 25, 2025
#

set -e  # Exit on error

#######################################
# Configuration
#######################################

NODE_VERSION="24"
POSTGRES_VERSION="16"
INSTALL_VALKEY="true"  # Set to "false" to use Redis instead
VALKEY_VERSION="8.0"

# PostgreSQL Configuration
POSTGRES_USER="vibecode_user"
POSTGRES_DB="vibecode"
POSTGRES_PASSWORD="change_me_in_production"  # Change this!

#######################################
# Color Output
#######################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
    echo ""
}

#######################################
# Validation
#######################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_linux() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "This script must be run on a Linux system (inside LX zone)"
        exit 1
    fi
    source /etc/os-release
    log_success "Running on $PRETTY_NAME"
}

check_internet() {
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connectivity"
        exit 1
    fi
    log_success "Internet connectivity verified"
}

#######################################
# System Update
#######################################

update_system() {
    section "Updating System Packages"

    log_info "Updating package lists..."
    apt update

    log_info "Upgrading existing packages..."
    apt upgrade -y

    log_info "Installing essential utilities..."
    apt install -y \
        curl \
        wget \
        git \
        vim \
        nano \
        htop \
        net-tools \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        build-essential \
        python3 \
        python3-pip

    log_success "System packages updated"
}

#######################################
# Node.js Installation
#######################################

install_nodejs() {
    section "Installing Node.js ${NODE_VERSION}"

    log_info "Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

    log_info "Installing Node.js..."
    apt install -y nodejs

    # Verify installation
    local node_ver=$(node --version)
    local npm_ver=$(npm --version)

    log_success "Node.js installed: $node_ver"
    log_success "npm installed: $npm_ver"

    # Install global npm packages
    log_info "Installing global npm packages..."
    npm install -g pm2 pnpm

    log_success "PM2 installed: $(pm2 --version)"
    log_success "pnpm installed: $(pnpm --version)"

    # Configure PM2 for startup
    log_info "Configuring PM2 startup..."
    pm2 startup systemd -u root --hp /root
}

#######################################
# PostgreSQL Installation
#######################################

install_postgresql() {
    section "Installing PostgreSQL ${POSTGRES_VERSION} with pgvector"

    log_info "Adding PostgreSQL repository..."
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

    log_info "Adding PostgreSQL repository key..."
    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

    log_info "Updating package lists..."
    apt update

    log_info "Installing PostgreSQL ${POSTGRES_VERSION}..."
    apt install -y \
        postgresql-${POSTGRES_VERSION} \
        postgresql-${POSTGRES_VERSION}-pgvector \
        postgresql-client-${POSTGRES_VERSION} \
        libpq-dev

    # Verify installation
    local psql_ver=$(psql --version | cut -d' ' -f3)
    log_success "PostgreSQL installed: $psql_ver"

    # Start and enable service
    systemctl start postgresql
    systemctl enable postgresql

    log_info "Configuring PostgreSQL for VibeCode..."
    configure_postgresql

    log_success "PostgreSQL configuration complete"
}

configure_postgresql() {
    # Create database and user
    log_info "Creating database '$POSTGRES_DB'..."
    su - postgres -c "psql -c \"CREATE DATABASE ${POSTGRES_DB};\"" 2>/dev/null || log_warning "Database may already exist"

    log_info "Creating user '$POSTGRES_USER'..."
    su - postgres -c "psql -c \"CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\"" 2>/dev/null || log_warning "User may already exist"

    log_info "Granting privileges..."
    su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};\""
    su - postgres -c "psql -d ${POSTGRES_DB} -c \"GRANT ALL ON SCHEMA public TO ${POSTGRES_USER};\""

    # Enable pgvector extension
    log_info "Enabling pgvector extension..."
    su - postgres -c "psql -d ${POSTGRES_DB} -c \"CREATE EXTENSION IF NOT EXISTS vector;\""

    # Verify pgvector
    local pgvector_ver=$(su - postgres -c "psql -d ${POSTGRES_DB} -tAc \"SELECT extversion FROM pg_extension WHERE extname = 'vector';\"")
    log_success "pgvector extension enabled: $pgvector_ver"

    # Configure for local connections
    log_info "Configuring authentication..."
    local pg_hba="/etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf"

    # Backup original
    cp "$pg_hba" "${pg_hba}.backup"

    # Allow local connections with md5
    echo "# VibeCode local connection" >> "$pg_hba"
    echo "local   ${POSTGRES_DB}   ${POSTGRES_USER}   md5" >> "$pg_hba"
    echo "host    ${POSTGRES_DB}   ${POSTGRES_USER}   127.0.0.1/32   md5" >> "$pg_hba"

    # Restart PostgreSQL
    systemctl restart postgresql

    log_success "PostgreSQL ready for VibeCode"
}

#######################################
# Valkey/Redis Installation
#######################################

install_valkey() {
    section "Installing Valkey ${VALKEY_VERSION}"

    log_info "Installing build dependencies..."
    apt install -y build-essential tcl pkg-config libssl-dev

    log_info "Cloning Valkey repository..."
    cd /tmp
    if [[ -d valkey ]]; then
        rm -rf valkey
    fi
    git clone https://github.com/valkey-io/valkey.git
    cd valkey
    git checkout ${VALKEY_VERSION}

    log_info "Building Valkey (this may take a few minutes)..."
    make -j$(nproc)

    log_info "Running Valkey tests..."
    make test || log_warning "Some tests failed, continuing anyway..."

    log_info "Installing Valkey..."
    make install

    log_success "Valkey binaries installed"

    # Create valkey user
    log_info "Creating valkey user..."
    useradd -r -s /bin/false valkey 2>/dev/null || log_warning "User 'valkey' may already exist"

    # Create directories
    log_info "Creating directories..."
    mkdir -p /var/lib/valkey /var/log/valkey /etc/valkey
    chown valkey:valkey /var/lib/valkey /var/log/valkey

    # Copy and configure valkey.conf
    log_info "Configuring Valkey..."
    cp valkey.conf /etc/valkey/valkey.conf

    # Modify configuration
    sed -i 's/^bind 127.0.0.1/bind 127.0.0.1/g' /etc/valkey/valkey.conf
    sed -i 's|^dir ./|dir /var/lib/valkey|g' /etc/valkey/valkey.conf
    sed -i 's|^logfile ""|logfile /var/log/valkey/valkey.log|g' /etc/valkey/valkey.conf
    sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/g' /etc/valkey/valkey.conf
    sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/g' /etc/valkey/valkey.conf

    # Create systemd service
    log_info "Creating systemd service..."
    cat > /etc/systemd/system/valkey.service <<'EOF'
[Unit]
Description=Valkey In-Memory Data Store
After=network.target

[Service]
Type=notify
User=valkey
Group=valkey
ExecStart=/usr/local/bin/valkey-server /etc/valkey/valkey.conf
ExecStop=/usr/local/bin/valkey-cli shutdown
Restart=always
RestartSec=5

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/valkey /var/log/valkey

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload

    # Start and enable Valkey
    log_info "Starting Valkey service..."
    systemctl start valkey
    systemctl enable valkey

    # Verify
    sleep 2
    if valkey-cli ping | grep -q PONG; then
        log_success "Valkey is running"
    else
        log_error "Valkey failed to start"
        systemctl status valkey
    fi

    # Cleanup
    cd /
    rm -rf /tmp/valkey

    log_success "Valkey installation complete"
}

install_redis() {
    section "Installing Redis"

    log_info "Installing Redis from repository..."
    apt install -y redis-server

    log_info "Configuring Redis..."
    sed -i 's/^bind 127.0.0.1 ::1/bind 127.0.0.1/g' /etc/redis/redis.conf
    sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/g' /etc/redis/redis.conf
    sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/g' /etc/redis/redis.conf

    # Restart Redis
    systemctl restart redis-server
    systemctl enable redis-server

    # Verify
    sleep 2
    if redis-cli ping | grep -q PONG; then
        log_success "Redis is running"
    else
        log_error "Redis failed to start"
        systemctl status redis-server
    fi

    log_success "Redis installation complete"
}

#######################################
# Nginx Installation
#######################################

install_nginx() {
    section "Installing Nginx"

    log_info "Installing Nginx..."
    apt install -y nginx

    # Verify installation
    local nginx_ver=$(nginx -v 2>&1 | cut -d'/' -f2)
    log_success "Nginx installed: $nginx_ver"

    # Create basic reverse proxy config for VibeCode
    log_info "Creating VibeCode reverse proxy configuration..."
    cat > /etc/nginx/sites-available/vibecode <<'EOF'
# VibeCode Reverse Proxy Configuration
# Proxies requests to Node.js application on port 3000

upstream vibecode_backend {
    server 127.0.0.1:3000;
    keepalive 64;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Increase buffer sizes for large requests
    client_max_body_size 100M;
    client_body_buffer_size 128k;

    # Logging
    access_log /var/log/nginx/vibecode-access.log;
    error_log /var/log/nginx/vibecode-error.log;

    # Root location
    location / {
        proxy_pass http://vibecode_backend;
        proxy_http_version 1.1;

        # Headers
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Buffering
        proxy_buffering off;
        proxy_cache_bypass $http_upgrade;
    }

    # WebSocket support
    location /ws {
        proxy_pass http://vibecode_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/vibecode /etc/nginx/sites-enabled/vibecode

    # Remove default site
    rm -f /etc/nginx/sites-enabled/default

    # Test configuration
    nginx -t

    # Start and enable Nginx
    systemctl start nginx
    systemctl enable nginx

    log_success "Nginx configured as reverse proxy for VibeCode"
}

#######################################
# Firewall Configuration
#######################################

configure_firewall() {
    section "Configuring Firewall"

    log_info "Installing UFW (Uncomplicated Firewall)..."
    apt install -y ufw

    log_info "Configuring firewall rules..."

    # Allow SSH
    ufw allow 22/tcp

    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Allow VibeCode direct access (optional, usually proxied via nginx)
    # ufw allow 3000/tcp

    # PostgreSQL (localhost only)
    ufw allow from 127.0.0.1 to any port 5432

    # Valkey/Redis (localhost only)
    ufw allow from 127.0.0.1 to any port 6379

    # Enable firewall
    log_warning "Enabling firewall (make sure SSH access is working)..."
    ufw --force enable

    log_success "Firewall configured"
    ufw status verbose
}

#######################################
# Additional Tools
#######################################

install_additional_tools() {
    section "Installing Additional Tools"

    log_info "Installing monitoring and debugging tools..."
    apt install -y \
        iotop \
        iftop \
        ncdu \
        jq \
        tmux \
        screen \
        strace \
        sysstat

    log_success "Additional tools installed"
}

#######################################
# Verification
#######################################

verify_installation() {
    section "Verifying Installation"

    echo "=== VibeCode Dependency Verification ==="
    echo ""

    # Node.js
    echo -n "Node.js: "
    if command -v node &> /dev/null; then
        echo -e "${GREEN}$(node --version)${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi

    echo -n "npm: "
    if command -v npm &> /dev/null; then
        echo -e "${GREEN}$(npm --version)${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi

    echo -n "PM2: "
    if command -v pm2 &> /dev/null; then
        echo -e "${GREEN}$(pm2 --version)${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi

    # PostgreSQL
    echo -n "PostgreSQL: "
    if command -v psql &> /dev/null; then
        echo -e "${GREEN}$(psql --version | cut -d' ' -f3)${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi

    echo -n "pgvector: "
    local pgv=$(su - postgres -c "psql -d ${POSTGRES_DB} -tAc \"SELECT extversion FROM pg_extension WHERE extname = 'vector';\"" 2>/dev/null)
    if [[ -n "$pgv" ]]; then
        echo -e "${GREEN}${pgv}${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi

    # Valkey/Redis
    if [[ "$INSTALL_VALKEY" == "true" ]]; then
        echo -n "Valkey: "
        if command -v valkey-cli &> /dev/null; then
            echo -e "${GREEN}$(valkey-cli --version | cut -d' ' -f2)${NC}"
        else
            echo -e "${RED}NOT INSTALLED${NC}"
        fi
    else
        echo -n "Redis: "
        if command -v redis-cli &> /dev/null; then
            echo -e "${GREEN}$(redis-cli --version | cut -d' ' -f2)${NC}"
        else
            echo -e "${RED}NOT INSTALLED${NC}"
        fi
    fi

    # Nginx
    echo -n "Nginx: "
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}$(nginx -v 2>&1 | cut -d'/' -f2)${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi

    echo ""
    echo "=== Service Status ==="
    echo ""

    services=("postgresql" "nginx")
    if [[ "$INSTALL_VALKEY" == "true" ]]; then
        services+=("valkey")
    else
        services+=("redis-server")
    fi

    for service in "${services[@]}"; do
        echo -n "$service: "
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}active${NC}"
        else
            echo -e "${RED}inactive${NC}"
        fi
    done

    echo ""
    echo "=== Network Test ==="
    echo ""
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "Internet: ${GREEN}OK${NC}"
    else
        echo -e "Internet: ${RED}FAILED${NC}"
    fi

    echo ""
}

#######################################
# Summary and Next Steps
#######################################

print_summary() {
    section "Installation Complete!"

    echo "All VibeCode dependencies have been installed successfully."
    echo ""
    echo "=== Connection Details ==="
    echo ""
    echo "PostgreSQL:"
    echo "  Database: ${POSTGRES_DB}"
    echo "  User:     ${POSTGRES_USER}"
    echo "  Password: ${POSTGRES_PASSWORD}"
    echo "  Host:     localhost"
    echo "  Port:     5432"
    echo ""

    if [[ "$INSTALL_VALKEY" == "true" ]]; then
        echo "Valkey:"
        echo "  Host: localhost"
        echo "  Port: 6379"
    else
        echo "Redis:"
        echo "  Host: localhost"
        echo "  Port: 6379"
    fi
    echo ""

    echo "Nginx:"
    echo "  HTTP Port: 80"
    echo "  Config:    /etc/nginx/sites-available/vibecode"
    echo ""

    echo "=== Next Steps ==="
    echo ""
    echo "1. Clone VibeCode repository:"
    echo "   cd /opt"
    echo "   git clone https://github.com/your-org/vibecode-webgui.git"
    echo ""
    echo "2. Configure environment variables:"
    echo "   cd vibecode-webgui"
    echo "   cp .env.example .env"
    echo "   # Edit .env with database credentials"
    echo ""
    echo "3. Install dependencies:"
    echo "   npm install"
    echo "   # or: pnpm install"
    echo ""
    echo "4. Run database migrations:"
    echo "   npm run migrate"
    echo ""
    echo "5. Start application with PM2:"
    echo "   pm2 start npm --name vibecode -- start"
    echo "   pm2 save"
    echo ""
    echo "6. Access VibeCode:"
    echo "   http://$(hostname -I | awk '{print $1}')"
    echo ""
    echo "=== Documentation ==="
    echo ""
    echo "See ZONE-SETUP-GUIDE.md for detailed configuration"
    echo ""
}

#######################################
# Main Execution
#######################################

main() {
    log_info "Starting VibeCode dependency installation..."
    echo ""

    # Pre-flight checks
    check_root
    check_linux
    check_internet
    echo ""

    # Installation steps
    update_system
    install_nodejs
    install_postgresql

    if [[ "$INSTALL_VALKEY" == "true" ]]; then
        install_valkey
    else
        install_redis
    fi

    install_nginx
    configure_firewall
    install_additional_tools

    # Verification and summary
    verify_installation
    print_summary

    log_success "VibeCode dependencies installed successfully!"
}

# Run main function
main "$@"
