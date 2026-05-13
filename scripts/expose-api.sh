#!/bin/bash
# =============================================================================
# API Exposer & Production Orchestrator v1.4
# Designed for: Gemma 4 / SGLang / Blackwell Infrastructure
# Modes: --proxy | --proxy-secure | --proxy-harden
# =============================================================================

set -e

# --- Configuration Defaults ---
API_PORT=30001
WEB_PORT=80
SSL_PORT=443
DOMAIN=""
TARGET_IP="127.0.0.1"
CONTAINER_NAME="sglang-gemma4"
NGINX_CONF_PATH="/etc/nginx/sites-available/sglang"
NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/sglang"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Helpers ---
print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}⚠️  $1 is not installed.${NC}"
        read -p "Would you like to install $1 now? (y/n): " yn
        case $yn in
            y|Y ) 
                print_info "Installing $1..."
                sudo apt-get update && sudo apt-get install -y "$1"
                ;;
            * ) 
                print_warn "$1 will be skipped. Features requiring it will fail."
                return 1 
                ;;
        esac
    fi
    return 0
}

# --- Module: Nginx Configuration Generator ---
# Generates a clean HTTP config to let Certbot handle SSL surgery safely
generate_nginx_config() {
    print_info "Generating hardened Nginx configuration for LLM proxy..."

    cat <<EOF | sudo tee $NGINX_CONF_PATH > /dev/null
# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=llm_llm:10m rate=30r/m;
limit_req_zone \$binary_remote_addr zone=llm_read:10m rate=30r/m;
limit_conn_zone \$binary_remote_addr zone=conn_per_ip:10m;

# Geo block for known scanner patterns
geo \$block_scanner {
    default 0;
    # Block requests targeting common scanner paths
    ~*wp-content.*\.sql 1;
    ~*wp-config.*\.bak 1;
    ~*wp-config.*\.sample 1;
    ~*\.(sql|sql\.gz|sql\.bz2|sql\.xz|sql\.zip)$ 1;
    ~*config\.(inc|env|ini|json|yml|yaml)$ 1;
    ~*config\..*\.bak 1;
    ~*\.env$ 1;
    ~*\.git/ 1;
    ~*\.env\. 1;
    ~*phpmyadmin 1;
    ~*\.ini$ 1;
    ~*\.lock 1;
    ~*\.lock$ 1;
    ~*debug 1;
    ~*console 1;
    ~*shell 1;
    ~*\.log$ 1;
    ~*adminer 1;
    ~*phpinfo 1;
}

server {
    listen $WEB_PORT;
    listen [::]:$WEB_PORT;
    server_name $DOMAIN;

    # --- Security Headers ---
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # --- Block scanner paths before they hit SGLang ---
    if ($block_scanner) {
        return 403;
    }

    # --- Connection limits ---
    limit_conn conn_per_ip 20;

    # --- Rate limit on non-API paths ---
    location / {
        limit_req zone=llm_read burst=5 nodelay;
        limit_req zone=llm_llm burst=5 nodelay;

        proxy_pass http://$TARGET_IP:$API_PORT;
        proxy_http_version 1.1;

        # LLM Streaming Optimizations
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket Support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    # Enable site if not already enabled
    if [ ! -L "$NGINX_ENABLED_PATH" ]; then
        sudo ln -s "$NGINX_CONF_PATH" "$NGINX_ENABLED_PATH"
    fi

    # Test and Reload
    if sudo nginx -t; then
        sudo systemctl reload nginx
        print_success "Nginx hardened configuration applied."
    else
        print_error "Nginx config test failed! Check $NGINX_CONF_PATH"
        exit 1
    fi
}

# --- Module: Security (UFW) ---
setup_ufw() {
    print_info "Hardening system with UFW..."
    check_tool "ufw" || return 1
    sudo ufw allow "$API_PORT"/tcp
    sudo ufw allow "$WEB_PORT"/tcp
    sudo ufw allow "$SSL_PORT"/tcp
    sudo ufw allow ssh
    sudo ufw --force enable
    print_success "Firewall rules applied (SSH, $WEB_PORT, $SSL_PORT, $API_PORT)."
}

# --- Module: SSL (Certbot) ---
setup_ssl() {
    if [ -z "$DOMAIN" ]; then
        print_error "A --domain must be provided for SSL setup."
        return 1
    fi
    
    # FIXED: Ensure BOTH certbot and the nginx plugin are present
    print_info "Verifying Certbot and Nginx plugin..."
    check_tool "certbot" || return 1
    
    # Explicitly check/install the plugin which is often missed
    if ! dpkg -s python3-certbot-nginx &> /dev/null; then
        print_warn "python3-certbot-nginx plugin not found."
        read -p "Would you like to install the Certbot Nginx plugin now? (y/n): " yn
        case $yn in
            y|Y ) 
                print_info "Installing python3-certbot-nginx..."
                sudo apt-get update && sudo apt-get install -y python3-certbot-nginx
                ;;
            * ) 
                print_error "Certbot requires the nginx plugin to perform automatic surgery. Exiting."
                return 1
                ;;
        esac
    fi

    print_info "Requesting SSL certificates for $DOMAIN via Certbot..."
    # Let Certbot perform the surgery on the existing Nginx config
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificates installed and Nginx updated automatically by Certbot."
    else
        print_error "Certbot failed to update Nginx. Check domain DNS/connectivity."
        return 1
    fi
}

# --- Main CLI Logic ---
usage() {
    echo -e "${BLUE}Usage: $0 [mode] [options]${NC}"
    echo "Modes:"
    echo "  --proxy            Nginx Only (Plain HTTP)"
    echo "  --proxy-secure     Nginx + Certbot (HTTPS)"
    echo "  --proxy-harden     Nginx + Certbot + UFW (Full Production)"
    echo ""
    echo "Options:"
    echo "  --domain <domain>  Required for proxy/secure/harden"
    echo "  --api-port <port>  Internal port (default: 30001)"
    echo "  --web-port <port>  External port (default: 80)"
    exit 1
}

# Parsing flags
MODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --proxy)         MODE="proxy"; shift ;;
        --proxy-secure)  MODE="secure"; shift ;;
        --proxy-harden)  MODE="harden"; shift ;;
        --domain)        DOMAIN="$2"; shift 2 ;;
        --api-port)      API_PORT="$2"; shift 2 ;;
        --web-port)      WEB_PORT="$2"; shift 2 ;;
        *)               usage ;;
    esac
done

if [ -z "$MODE" ]; then
    print_error "No mode specified."
    usage
fi

# --- Execution Flow ---

case $MODE in
    "proxy")
        print_info "RUNNING MODE: [PROXY] - Nginx HTTP Forwarding"
        check_tool "nginx" || exit 1
        generate_nginx_config
        ;;

    "secure")
        print_info "RUNNING MODE: [PROXY-SECURE] - Nginx + Certbot"
        if [ -z "$DOMAIN" ]; then print_error "--domain is required"; exit 1; fi
        check_tool "nginx" || exit 1
        generate_nginx_config
        setup_ssl
        ;;

    "harden")
        print_info "RUNNING MODE: [PROXY-HARDEN] - Full Production Lockdown"
        if [ -z "$DOMAIN" ]; then print_error "--domain is required"; exit 1; fi
        check_tool "nginx" || exit 1
        generate_nginx_config
        setup_ssl
        setup_ufw
        ;;
esac

print_success "Deployment orchestration complete."
