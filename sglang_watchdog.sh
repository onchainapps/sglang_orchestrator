#!/bin/bash
# SGLang Watchdog - Auto-restart on hang/crash
# Deploy on the machine running SGLang containers
# 
# Usage: bash sglang_watchdog.sh [container_name_pattern]
# Default pattern: "sglang-"
#
# Install as cron job (runs every 2 min):
#   */2 * * * * /path/to/sglang_watchdog.sh >> /var/log/sglang-watchdog.log 2>&1

CONTAINER_PATTERN="${1:-sglang-}"
HEALTH_ENDPOINT="/v1/models"
HEALTH_TIMEOUT=10
LOG_PREFIX="[SGLang-Watchdog]"

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Checking containers matching '$CONTAINER_PATTERN'"

# Find running SGLang containers
CONTAINERS=$(docker ps --filter "name=$CONTAINER_PATTERN" --format "{{.ID}}|{{.Names}}|{{.Ports}}" 2>/dev/null)

if [ -z "$CONTAINERS" ]; then
    echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - No running containers found. Restarting..."
    
    # Find the most recently stopped container to restart
    STOPPED=$(docker ps -a --filter "name=$CONTAINER_PATTERN" --filter "status=exited" --format "{{.ID}}|{{.Names}}" --sort "CreatedAt" 2>/dev/null | head -1)
    
    if [ -n "$STOPPED" ]; then
        CID=$(echo "$STOPPED" | cut -d'|' -f1)
        CNAME=$(echo "$STOPPED" | cut -d'|' -f2)
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Found stopped container: $CNAME ($CID)"
        docker start "$CID" 2>/dev/null
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Container $CNAME restarted"
    else
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - ERROR: No containers found (running or stopped). Manual intervention needed."
    fi
    exit 1
fi

echo "$CONTAINERS" | while IFS='|' read -r CID CNAME CPORTS; do
    # Extract port from ports mapping (format: 0.0.0.0:30001->30001)
    PORT=$(echo "$CPORTS" | grep -oP '\d+:\K\d+(?=-\>)' | head -1)
    
    if [ -z "$PORT" ]; then
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - WARN: Could not determine port for $CNAME"
        continue
    fi
    
    echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Checking $CNAME on port $PORT..."
    
    # Health check - is the API responding?
    HEALTH=$(curl -s --connect-timeout "$HEALTH_TIMEOUT" --max-time "$((HEALTH_TIMEOUT * 2))" "http://localhost:${PORT}${HEALTH_ENDPOINT}" 2>&1)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$HEALTH_TIMEOUT" --max-time "$((HEALTH_TIMEOUT * 2))" "http://localhost:${PORT}${HEALTH_ENDPOINT}" 2>&1)
    
    if [ "$HTTP_CODE" = "000" ] || [ "$HTTP_CODE" = "00" ]; then
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - CRITICAL: $CNAME is unresponsive (HTTP $HTTP_CODE). Restarting..."
        docker restart "$CID" 2>/dev/null
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Container $CNAME restarted"
        continue
    fi
    
    if [ "$HTTP_CODE" != "200" ]; then
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - WARN: $CNAME returned HTTP $HTTP_CODE"
    fi
    
    # Advanced health check: can it actually process a request?
    # Send a tiny request and measure response time
    START_TIME=$(date +%s%N)
    TEST_RESP=$(curl -s --max-time 15 "http://localhost:${PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>&1)
    END_TIME=$(date +%s%N)
    
    TEST_TIME=$(( (END_TIME - START_TIME) / 1000000 ))  # milliseconds
    TEST_CODE=$(echo "$TEST_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error',{}).get('type','ok'))" 2>/dev/null)
    
    if [ "$TEST_CODE" != "ok" ]; then
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - CRITICAL: $CNAME is hanging (request took ${TEST_TIME}ms, error: $TEST_CODE). Restarting..."
        docker restart "$CID" 2>/dev/null
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Container $CNAME restarted"
    else
        echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - $CNAME healthy (${TEST_TIME}ms response)"
    fi
done

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - Watchdog check complete"
