#!/bin/bash
# =============================================================================
# SGLang Orchestrator - API & Nginx Management Module (lib_api.sh) v3.0
# Wraps expose-api.sh + adds audit/monitor capabilities
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NGINX_CONF_PATH="/etc/nginx/sites-available/sglang"
NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/sglang"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; return 1; }

# --- Core: Generate nginx config (HTTP proxy only) ---
generate_nginx_config() {
    local api_port=${1:-30001}
    local domain=${2:-""}
    log "Generating Nginx config for port $api_port..."
    
    local expose_script="$PROJECT_ROOT/scripts/expose-api.sh"
    if [ -f "$expose_script" ]; then
        bash "$expose_script" --proxy --api-port "$api_port" ${domain:+--domain "$domain"}
    else
        error "expose-api.sh not found at $expose_script"
        return 1
    fi
}

# --- Core: Full harden (HTTP + SSL + UFW) ---
full_harden() {
    local api_port=${1:-30001}
    local domain=${2:-""}
    if [ -z "$domain" ]; then
        error "Domain required for full harden. Usage: full_harden <api_port> <domain>"
        return 1
    fi
    log "Running full production harden (Nginx + SSL + UFW)..."
    
    local expose_script="$PROJECT_ROOT/scripts/expose-api.sh"
    if [ -f "$expose_script" ]; then
        bash "$expose_script" --proxy-harden --api-port "$api_port" --domain "$domain"
    else
        error "expose-api.sh not found at $expose_script"
        return 1
    fi
}

# --- Audit: Check if nginx config exists and is valid ---
audit_nginx_config() {
    echo ""
    echo "============================================================"
    echo " Nginx Configuration Audit"
    echo "============================================================"
    
    # 1. Check if config file exists
    if [ -f "$NGINX_CONF_PATH" ]; then
        success "Config file exists: $NGINX_CONF_PATH"
    else
        error "Config file NOT found: $NGINX_CONF_PATH"
        return 1
    fi
    
    # 2. Check if enabled (symlink)
    if [ -L "$NGINX_ENABLED_PATH" ]; then
        success "Site enabled: $NGINX_ENABLED_PATH -> $(readlink $NGINX_ENABLED_PATH)"
    else
        warn "Site NOT enabled (not symlinked)"
    fi
    
    # 3. Validate nginx config syntax
    echo ""
    echo "--- Nginx Syntax Test ---"
    if sudo nginx -t 2>&1; then
        success "Nginx config syntax is VALID"
    else
        error "Nginx config has SYNTAX ERRORS!"
        return 1
    fi
    
    # 4. Show nginx service status
    echo ""
    echo "--- Nginx Service Status ---"
    if systemctl is-active --quiet nginx; then
        success "Nginx service is RUNNING"
    else
        warn "Nginx service is NOT running"
    fi
    
    # 5. Show current config summary
    echo ""
    echo "--- Config Summary ---"
    echo "  Domain:          $(grep -oP 'server_name \K[^;]+' $NGINX_CONF_PATH 2>/dev/null || echo 'N/A')"
    echo "  API Port:        $(grep -oP 'listen \K[0-9]+' $NGINX_CONF_PATH 2>/dev/null | head -1 || echo 'N/A')"
    echo "  Rate Limit:      $(grep 'limit_req_zone' $NGINX_CONF_PATH 2>/dev/null | head -1 | grep -oP 'rate=\K[^;]+' || echo 'N/A')"
    echo "  Conn Limit:      $(grep 'limit_conn conn_per_ip' $NGINX_CONF_PATH 2>/dev/null | grep -oP '\d+' || echo 'N/A')/IP"
    echo "  Scanner Block:   $(grep -c '~\*' $NGINX_CONF_PATH 2>/dev/null || echo 0) patterns"
    echo "  SSL Active:      $(test -f /etc/letsencrypt/live/$(grep -oP 'server_name \K[^;]+' $NGINX_CONF_PATH 2>/dev/null | head -1)/fullchain.pem 2>/dev/null && echo 'Yes' || echo 'No (HTTP only)')"
    echo "  Security Headers: $(grep -c 'add_header X-' $NGINX_CONF_PATH 2>/dev/null || echo 0) headers"
    
    # 6. Show scanner patterns
    echo ""
    echo "--- Scanner Block Patterns ---"
    grep '~\*' $NGINX_CONF_PATH 2>/dev/null | sed 's/^/  /'
    
    # 7. Security header audit
    echo ""
    echo "--- Security Header Check ---"
    local missing_headers=0
    for header in "X-Content-Type-Options" "X-Frame-Options" "X-XSS-Protection" "Referrer-Policy"; do
        if grep -q "$header" $NGINX_CONF_PATH 2>/dev/null; then
            success "$header: present"
        else
            error "$header: MISSING"
            ((missing_headers++))
        fi
    done
    
    # 8. Rate limit audit
    echo ""
    echo "--- Rate Limit Audit ---"
    local rate
    rate=$(grep 'limit_req_zone' $NGINX_CONF_PATH 2>/dev/null | grep -oP 'rate=\K[^;]+')
    if [ -n "$rate" ]; then
        rps=$(echo "$rate" | grep -oP '[0-9]+')
        unit=$(echo "$rate" | grep -oP '[a-z]+')
        if [ "$unit" = "r/m" ]; then
            warn "Rate limit: $rate — only $((rps / 60)) requests/second. May be too restrictive for streaming."
        else
            success "Rate limit: $rate"
        fi
    else
        error "No rate limiting configured!"
    fi
    
    # 9. Proxy settings for streaming
    echo ""
    echo "--- Proxy Streaming Config ---"
    if grep -q 'proxy_buffering off' $NGINX_CONF_PATH 2>/dev/null; then
        success "proxy_buffering: off (good for streaming)"
    else
        error "proxy_buffering NOT disabled — will break streaming responses"
    fi
    if grep -q 'proxy_read_timeout 3600' $NGINX_CONF_PATH 2>/dev/null; then
        success "proxy_read_timeout: 3600s (good for long LLM generation)"
    else
        error "proxy_read_timeout too low or missing — streaming may timeout"
    fi
    
    echo ""
    echo "============================================================"
}

# --- Monitor: Show recent nginx access/error for scanner hits ---
monitor_scanner_hits() {
    echo ""
    echo "============================================================"
    echo " Recent Scanner/Block Hits (last 20)"
    echo "============================================================"
    
    local access_log="/var/log/nginx/access.log"
    local error_log="/var/log/nginx/error.log"
    
    if [ ! -f "$access_log" ]; then
        error "Access log not found: $access_log"
        return 1
    fi
    
    # Count recent 403s (likely scanner hits)
    local count_403
    count_403=$(grep -c '" 403 ' "$access_log" 2>/dev/null || echo 0)
    echo "  Total 403s in log: $count_403"
    
    # Show last 20 blocked requests
    echo ""
    echo "--- Last 20 Blocked Requests ---"
    grep '" 403 ' "$access_log" 2>/dev/null | tail -20 | while read -r line; do
        local ip
        ip=$(echo "$line" | awk '{print $1}')
        local path
        path=$(echo "$line" | awk '{print $7}')
        local code
        code=$(echo "$line" | grep -oP '"\K\d{3}')
        local ts
        ts=$(echo "$line" | cut -d'[' -f2 | cut -d']' -f1)
        printf "  %-18s %-45s [403] %s\n" "$ip" "$path" "$ts"
    done
    
    # Show top offending IPs
    echo ""
    echo "--- Top 10 Offending IPs (403s) ---"
    grep '" 403 ' "$access_log" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | while read -r cnt ip; do
        printf "  %4d hits from %s\n" "$cnt" "$ip"
    done
    
    echo ""
    echo "============================================================"
}

# --- Manage: Reload, restart, or stop nginx ---
manage_nginx() {
    local action=${1:-"restart"}
    case $action in
        test)
            log "Testing nginx config..."
            if sudo nginx -t 2>&1; then
                success "Config is valid"
            else
                error "Config is invalid"
                return 1
            fi
            ;;
        reload)
            log "Reloading nginx..."
            sudo systemctl reload nginx
            success "Nginx reloaded"
            ;;
        restart)
            log "Restarting nginx..."
            sudo systemctl restart nginx
            success "Nginx restarted"
            ;;
        *)
            error "Usage: manage_nginx [test|reload|restart]"
            return 1
            ;;
    esac
}
