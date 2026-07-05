#!/bin/bash
# ============================================================
# Script Name: System Scanner + Performance Monitor
# Description: System scanning, update checking, performance monitoring
# Supports: Linux (Ubuntu/Debian/RHEL/CentOS/Fedora/Arch/Parrot)
# Outputs: TXT + JSON reports only
# ============================================================

# ------------------- SETTINGS -------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_FILE="${SCRIPT_DIR}/system_report_${TIMESTAMP}.txt"
JSON_FILE="${SCRIPT_DIR}/system_report_${TIMESTAMP}.json"

# Colors for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Check Bash version
if (( BASH_VERSINFO[0] < 4 )); then
    echo -e "${RED}Error: This script requires Bash 4.0 or higher${NC}"
    echo "Current version: $BASH_VERSION"
    exit 1
fi

# ------------------- SYSTEM DETECTION FUNCTIONS -------------------
detect_os() {
    echo -e "${BLUE}[1/5] Detecting operating system...${NC}"
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        OS_ID="$ID"
        OS_PRETTY="$PRETTY_NAME"
    elif [[ -f /etc/redhat-release ]]; then
        OS_NAME="Red Hat"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
        OS_ID="rhel"
        OS_PRETTY=$(cat /etc/redhat-release)
    elif [[ -f /etc/arch-release ]]; then
        OS_NAME="Arch Linux"
        OS_VERSION="Rolling Release"
        OS_ID="arch"
        OS_PRETTY="Arch Linux"
    else
        OS_NAME="Unknown"
        OS_VERSION="Unknown"
        OS_ID="unknown"
        OS_PRETTY="Unknown OS"
    fi
    
    KERNEL=$(uname -r)
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    UPTIME=$(uptime -p | sed 's/up //')
    
    echo -e "${GREEN}✓ OS: $OS_PRETTY${NC}"
    echo -e "${GREEN}✓ Kernel: $KERNEL${NC}"
    echo -e "${GREEN}✓ Architecture: $ARCH${NC}"
    echo -e "${GREEN}✓ Uptime: $UPTIME${NC}"
}

# ------------------- UPDATE CHECK FUNCTIONS -------------------
check_updates_debian() {
    echo -e "${BLUE}[2/5] Updating package list (APT)...${NC}"
    if ! sudo apt update -qq 2>/dev/null; then
        echo -e "${RED}✗ Failed to update package list (needs sudo)${NC}"
        return 1
    fi
    
    echo -e "${BLUE}[3/5] Checking for available updates...${NC}"
    
    UPDATES_COUNT=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    UPDATES_LIST=$(apt list --upgradable 2>/dev/null | grep "upgradable" | \
                   awk -F'/' '{print $1}' | head -20)
    SECURITY_COUNT=$(apt list --upgradable 2>/dev/null | grep -i "security" | wc -l)
    
    # Fixed old packages detection
    OLD_PACKAGES=$(dpkg-query -W -f='${Package} ${Version} ${Install-Time}\n' 2>/dev/null | \
                   awk '{
                     if($3 ~ /^[0-9]+$/ && $3 > 0) {
                       current=systime();
                       if((current-$3)>15552000) print $1" "$2" (6+ months old)"
                     }
                   }' | head -10)
    
    echo -e "${GREEN}✓ Available updates: $UPDATES_COUNT${NC}"
    echo -e "${YELLOW}✓ Security updates: $SECURITY_COUNT${NC}"
}

check_updates_redhat() {
    echo -e "${BLUE}[2/5] Checking for updates (YUM/DNF)...${NC}"
    
    if command -v dnf &> /dev/null; then
        PKG_MGR="dnf"
        UPDATES_COUNT=$(sudo dnf check-update -q 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
        UPDATES_LIST=$(sudo dnf check-update -q 2>/dev/null | grep "^[a-zA-Z]" | awk '{print $1}' | head -20)
        SECURITY_COUNT=$(sudo dnf check-update -q --security 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
    else
        PKG_MGR="yum"
        UPDATES_COUNT=$(sudo yum check-update -q 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
        UPDATES_LIST=$(sudo yum check-update -q 2>/dev/null | grep "^[a-zA-Z]" | awk '{print $1}' | head -20)
        SECURITY_COUNT=$(sudo yum check-update -q --security 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
    fi
    
    echo -e "${GREEN}✓ Available updates: $UPDATES_COUNT${NC}"
    echo -e "${YELLOW}✓ Security updates: $SECURITY_COUNT${NC}"
}

check_updates_arch() {
    echo -e "${BLUE}[2/5] Updating package list (Pacman)...${NC}"
    if ! sudo pacman -Sy --noconfirm 2>/dev/null; then
        echo -e "${RED}✗ Failed to update package list${NC}"
        return 1
    fi
    
    echo -e "${BLUE}[3/5] Checking for available updates...${NC}"
    
    UPDATES_COUNT=$(sudo pacman -Qu 2>/dev/null | wc -l)
    UPDATES_LIST=$(sudo pacman -Qu 2>/dev/null | awk '{print $1}' | head -20)
    SECURITY_COUNT=0
    
    echo -e "${GREEN}✓ Available updates: $UPDATES_COUNT${NC}"
}

# ------------------- PERFORMANCE MONITORING FUNCTIONS -------------------
monitor_performance() {
    echo -e "${MAGENTA}[4/5] Monitoring system performance (CPU, RAM, Disk, Network)...${NC}"
    
    # CPU
    CPU_CORES=$(nproc 2>/dev/null || echo "1")
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | awk -F':' '{print $2}' | xargs || echo "Unknown")
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr ',' '.' || echo "0")
    CPU_IDLE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1 | tr ',' '.' || echo "0")
    CPU_USER=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr ',' '.' || echo "0")
    CPU_SYSTEM=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $4}' | cut -d'%' -f1 | tr ',' '.' || echo "0")
    
    TOP_CPU_PROCESSES=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{printf "  • %-20s CPU: %5s%% MEM: %5s%%\n", $11, $3, $4}')
    
    # RAM
    MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "N/A")
    MEM_USED=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "N/A")
    MEM_AVAILABLE=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}' || echo "N/A")
    MEM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.1f", ($3/$2)*100}' || echo "0")
    
    SWAP_TOTAL=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "N/A")
    SWAP_USED=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3}' || echo "N/A")
    SWAP_FREE=$(free -h 2>/dev/null | awk '/^Swap:/ {print $4}' || echo "N/A")
    SWAP_PERCENT=$(free 2>/dev/null | awk '/^Swap:/ {if($2>0) printf "%.1f", ($3/$2)*100; else print "0"}')
    
    TOP_MEM_PROCESSES=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{printf "  • %-20s MEM: %5s%% CPU: %5s%%\n", $11, $4, $3}')
    
    # Disk
    DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "N/A")
    DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}' || echo "N/A")
    DISK_AVAIL=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    DISK_PERCENT=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    
    DISK_PARTITIONS=$(df -h 2>/dev/null | grep -v "tmpfs" | grep -v "udev" | grep -v "loop" | tail -n +2 | \
                      awk '{printf "  • %-15s %-8s %-8s %-8s %s\n", $6, $2, $3, $4, $5}')
    
    if command -v iostat &> /dev/null; then
        DISK_READ=$(iostat -d -k 1 2 2>/dev/null | grep -E "^sd|^vd|^nvme" | tail -1 | awk '{print $3}' || echo "0")
        DISK_WRITE=$(iostat -d -k 1 2 2>/dev/null | grep -E "^sd|^vd|^nvme" | tail -1 | awk '{print $4}' || echo "0")
    else
        DISK_READ="N/A (install sysstat)"
        DISK_WRITE="N/A (install sysstat)"
    fi
    
    # Network
    NET_INTERFACES=$(ip -br link 2>/dev/null | grep -v "lo" | grep "UP" | awk '{print $1}' | xargs || echo "None")
    
    MAIN_IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
    if [[ -n "$MAIN_IFACE" ]] && [[ -d "/sys/class/net/$MAIN_IFACE" ]]; then
        RX_BYTES=$(cat /sys/class/net/$MAIN_IFACE/statistics/rx_bytes 2>/dev/null || echo "0")
        TX_BYTES=$(cat /sys/class/net/$MAIN_IFACE/statistics/tx_bytes 2>/dev/null || echo "0")
        RX_MB=$(echo "scale=2; $RX_BYTES/1024/1024" | bc 2>/dev/null || echo "0")
        TX_MB=$(echo "scale=2; $TX_BYTES/1024/1024" | bc 2>/dev/null || echo "0")
        NET_SPEED=$(ethtool $MAIN_IFACE 2>/dev/null | grep "Speed" | awk '{print $2}' || echo "Unknown")
    else
        RX_MB="0"
        TX_MB="0"
        NET_SPEED="Unknown"
    fi
    
    TCP_CONNECTIONS=$(ss -tun 2>/dev/null | grep -c "ESTAB" || echo "0")
    TCP_TOTAL=$(ss -tun 2>/dev/null | grep -c "^tcp" || echo "0")
    UDP_TOTAL=$(ss -tun 2>/dev/null | grep -c "^udp" || echo "0")
    LISTENING_PORTS=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1" | grep LISTEN | awk '{print $4}' | awk -F':' '{print $NF}' | sort -n | uniq | head -10 | xargs || echo "None")
    
    # Evaluations
    if (( $(echo "$CPU_USAGE > 80" | bc -l 2>/dev/null || echo "0") )); then
        CPU_STATUS="Very High"
        CPU_RECOMMEND="Reduce processes or upgrade CPU"
    elif (( $(echo "$CPU_USAGE > 60" | bc -l 2>/dev/null || echo "0") )); then
        CPU_STATUS="High"
        CPU_RECOMMEND="Check running processes"
    else
        CPU_STATUS="Good"
        CPU_RECOMMEND="No recommendations"
    fi
    
    if (( $(echo "$MEM_PERCENT > 80" | bc -l 2>/dev/null || echo "0") )); then
        MEM_STATUS="Very High"
        MEM_RECOMMEND="Add more RAM or reduce services"
    elif (( $(echo "$MEM_PERCENT > 60" | bc -l 2>/dev/null || echo "0") )); then
        MEM_STATUS="High"
        MEM_RECOMMEND="Review memory usage"
    else
        MEM_STATUS="Good"
        MEM_RECOMMEND="No recommendations"
    fi
    
    if (( DISK_PERCENT > 80 )); then
        DISK_STATUS="Very High"
        DISK_RECOMMEND="Delete unnecessary files or expand partition"
    elif (( DISK_PERCENT > 60 )); then
        DISK_STATUS="High"
        DISK_RECOMMEND="Clean temporary files"
    else
        DISK_STATUS="Good"
        DISK_RECOMMEND="No recommendations"
    fi
    
    echo -e "${GREEN}✓ Performance monitoring completed${NC}"
}

# ------------------- OLD SERVICES CHECK FUNCTIONS -------------------
check_old_services() {
    echo -e "${BLUE}[5/5] Checking for outdated/dangerous services...${NC}"
    
    declare -A OLD_SERVICES=(
        ["telnet"]="Telnet - Unencrypted, use SSH instead"
        ["ftp"]="FTP - Unencrypted, use SFTP/FTPS"
        ["rsh"]="RSH - Very dangerous, insecure"
        ["rlogin"]="Rlogin - Insecure"
        ["rexec"]="Rexec - Insecure"
        ["httpd"]="Apache - Ensure it's updated"
        ["nginx"]="Nginx - Ensure it's updated"
        ["mysql"]="MySQL - Ensure updated to version 8.0+"
        ["postgresql"]="PostgreSQL - Ensure updated to version 15+"
        ["redis"]="Redis - Ensure password is set"
        ["mongodb"]="MongoDB - Ensure authentication is enabled"
        ["vsftpd"]="vsftpd - Ensure updated to version 3.0.5+"
        ["openssh"]="OpenSSH - Ensure updated to version 9.0+"
    )
    
    FOUND_OLD=()
    
    if command -v systemctl &> /dev/null; then
        for service in "${!OLD_SERVICES[@]}"; do
            if systemctl list-units --type=service --all 2>/dev/null | grep -q "$service"; then
                VERSION=""
                if command -v "$service" &> /dev/null; then
                    VERSION=$("$service" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
                fi
                FOUND_OLD+=("$service (Version: ${VERSION:-Unknown}) - ${OLD_SERVICES[$service]}")
            fi
        done
    else
        for service in "${!OLD_SERVICES[@]}"; do
            if ps aux 2>/dev/null | grep -v grep | grep -q "$service"; then
                VERSION=""
                if command -v "$service" &> /dev/null; then
                    VERSION=$("$service" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
                fi
                FOUND_OLD+=("$service (Version: ${VERSION:-Unknown}) - ${OLD_SERVICES[$service]}")
            fi
        done
    fi
    
    if [[ ${#FOUND_OLD[@]} -gt 0 ]]; then
        echo -e "${RED}✗ Found outdated/dangerous services:${NC}"
        for item in "${FOUND_OLD[@]}"; do
            echo -e "  ${RED}• $item${NC}"
        done
    else
        echo -e "${GREEN}✓ No dangerous services found${NC}"
    fi
}

# ------------------- REPORT GENERATION FUNCTIONS -------------------
generate_reports() {
    echo -e "${BLUE}Generating reports...${NC}"
    
    # ----- TEXT REPORT -----
    {
        echo "=========================================="
        echo "       System Scanner Report"
        echo "=========================================="
        echo "Scan Date: $(date)"
        echo "Path: $SCRIPT_DIR"
        echo "Host: $HOSTNAME"
        echo "------------------------------------------"
        echo ""
        echo "🔹 System Information:"
        echo "   Operating System: $OS_PRETTY"
        echo "   Version: $OS_VERSION"
        echo "   Kernel: $KERNEL"
        echo "   Architecture: $ARCH"
        echo "   Uptime: $UPTIME"
        echo ""
        echo "🔹 Available Updates:"
        echo "   Total Updates: $UPDATES_COUNT"
        echo "   Security Updates: ${SECURITY_COUNT:-0}"
        echo ""
        echo "🔹 Update List (First 20):"
        if [[ -n "$UPDATES_LIST" ]]; then
            echo "$UPDATES_LIST" | sed 's/^/   • /'
        else
            echo "   ✗ No updates available"
        fi
        echo ""
        echo "🔹 Old Packages (6+ months):"
        if [[ -n "$OLD_PACKAGES" ]]; then
            echo "$OLD_PACKAGES" | sed 's/^/   • /'
        else
            echo "   ✓ No old packages found"
        fi
        echo ""
        echo "=========================================="
        echo "           Performance Monitoring"
        echo "=========================================="
        echo ""
        echo "🔹 CPU:"
        echo "   Model: $CPU_MODEL"
        echo "   Cores: $CPU_CORES"
        echo "   Usage: $CPU_USAGE%"
        echo "   User: $CPU_USER% | System: $CPU_SYSTEM% | Idle: $CPU_IDLE%"
        echo "   Load Average: $LOAD_AVG"
        echo "   Status: $CPU_STATUS"
        echo "   Recommendation: $CPU_RECOMMEND"
        echo "   Top Processes:"
        echo "$TOP_CPU_PROCESSES"
        echo ""
        echo "🔹 RAM:"
        echo "   Total: $MEM_TOTAL"
        echo "   Used: $MEM_USED ($MEM_PERCENT%)"
        echo "   Available: $MEM_AVAILABLE"
        echo "   Status: $MEM_STATUS"
        echo "   Recommendation: $MEM_RECOMMEND"
        echo "   Top Processes:"
        echo "$TOP_MEM_PROCESSES"
        echo ""
        echo "🔹 Swap:"
        echo "   Total: $SWAP_TOTAL"
        echo "   Used: $SWAP_USED (${SWAP_PERCENT}%)"
        echo "   Free: $SWAP_FREE"
        echo ""
        echo "🔹 Disk:"
        echo "   Total: $DISK_TOTAL"
        echo "   Used: $DISK_USED ($DISK_PERCENT%)"
        echo "   Available: $DISK_AVAIL"
        echo "   Status: $DISK_STATUS"
        echo "   Recommendation: $DISK_RECOMMEND"
        echo "   Partitions:"
        echo "$DISK_PARTITIONS"
        echo "   I/O Read: ${DISK_READ:-N/A} KB/s"
        echo "   I/O Write: ${DISK_WRITE:-N/A} KB/s"
        echo ""
        echo "🔹 Network:"
        echo "   Interfaces: $NET_INTERFACES"
        echo "   Main Interface: $MAIN_IFACE"
        echo "   Speed: ${NET_SPEED:-Unknown}"
        echo "   Received: $RX_MB MB"
        echo "   Transmitted: $TX_MB MB"
        echo "   TCP Connections: $TCP_CONNECTIONS"
        echo "   Listening Ports: ${LISTENING_PORTS:-None}"
        echo ""
        echo "🔹 Dangerous Services:"
        if [[ ${#FOUND_OLD[@]} -gt 0 ]]; then
            for item in "${FOUND_OLD[@]}"; do
                echo "   • $item"
            done
        else
            echo "   ✓ No dangerous services found"
        fi
        echo ""
        echo "=========================================="
        echo "           Recommendations"
        echo "=========================================="
        if [[ $UPDATES_COUNT -gt 0 ]]; then
            echo "   ⚠️  $UPDATES_COUNT updates available"
            if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]] || [[ "$OS_ID" == "parrot" ]]; then
                echo "      sudo apt upgrade -y"
            elif [[ "$OS_ID" == "rhel" ]] || [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "fedora" ]]; then
                echo "      sudo $PKG_MGR upgrade -y"
            elif [[ "$OS_ID" == "arch" ]]; then
                echo "      sudo pacman -Syu"
            fi
        else
            echo "   ✅ System is fully updated"
        fi
        
        if [[ ${#FOUND_OLD[@]} -gt 0 ]]; then
            echo "   ⚠️  Stop/Update old services:"
            for item in "${FOUND_OLD[@]}"; do
                echo "      - $item"
            done
        fi
        
        if (( $(echo "$CPU_USAGE > 70" | bc -l 2>/dev/null || echo "0") )); then
            echo "   ⚠️  High CPU: $CPU_USAGE%"
        fi
        if (( $(echo "$MEM_PERCENT > 70" | bc -l 2>/dev/null || echo "0") )); then
            echo "   ⚠️  High RAM: $MEM_PERCENT%"
        fi
        if (( DISK_PERCENT > 75 )); then
            echo "   ⚠️  Low disk space: $DISK_PERCENT%"
        fi
        
        echo ""
        echo "=========================================="
        echo "Report saved to: $REPORT_FILE"
        echo "=========================================="
    } | tee "$REPORT_FILE"
    
    # ----- JSON REPORT -----
    {
        echo "{"
        echo "  \"scan_time\": \"$(date -Iseconds 2>/dev/null || date +'%Y-%m-%dT%H:%M:%S%z')\","
        echo "  \"hostname\": \"$HOSTNAME\","
        echo "  \"system\": {"
        echo "    \"name\": \"$OS_PRETTY\","
        echo "    \"version\": \"$OS_VERSION\","
        echo "    \"kernel\": \"$KERNEL\","
        echo "    \"architecture\": \"$ARCH\","
        echo "    \"uptime\": \"$UPTIME\""
        echo "  },"
        echo "  \"updates\": {"
        echo "    \"total\": $UPDATES_COUNT,"
        echo "    \"security\": ${SECURITY_COUNT:-0},"
        echo "    \"list\": ["
        first=1
        if [[ -n "$UPDATES_LIST" ]]; then
            while IFS= read -r pkg; do
                if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
                echo "      \"$pkg\""
            done <<< "$UPDATES_LIST"
        fi
        echo "    ]"
        echo "  },"
        echo "  \"old_packages\": ["
        first=1
        if [[ -n "$OLD_PACKAGES" ]]; then
            while IFS= read -r pkg; do
                if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
                echo "      \"$pkg\""
            done <<< "$OLD_PACKAGES"
        fi
        echo "  ],"
        echo "  \"performance\": {"
        echo "    \"cpu\": {"
        echo "      \"model\": \"$CPU_MODEL\","
        echo "      \"cores\": $CPU_CORES,"
        echo "      \"usage\": $CPU_USAGE,"
        echo "      \"user\": $CPU_USER,"
        echo "      \"system\": $CPU_SYSTEM,"
        echo "      \"idle\": $CPU_IDLE,"
        echo "      \"load_avg\": \"$LOAD_AVG\","
        echo "      \"status\": \"$CPU_STATUS\","
        echo "      \"recommendation\": \"$CPU_RECOMMEND\","
        echo "      \"top_processes\": ["
        first=1
        if [[ -n "$TOP_CPU_PROCESSES" ]]; then
            while IFS= read -r proc; do
                if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
                echo "        \"$proc\""
            done <<< "$TOP_CPU_PROCESSES"
        fi
        echo "      ]"
        echo "    },"
        echo "    \"memory\": {"
        echo "      \"total\": \"$MEM_TOTAL\","
        echo "      \"used\": \"$MEM_USED\","
        echo "      \"available\": \"$MEM_AVAILABLE\","
        echo "      \"percent\": $MEM_PERCENT,"
        echo "      \"status\": \"$MEM_STATUS\","
        echo "      \"recommendation\": \"$MEM_RECOMMEND\","
        echo "      \"top_processes\": ["
        first=1
        if [[ -n "$TOP_MEM_PROCESSES" ]]; then
            while IFS= read -r proc; do
                if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
                echo "        \"$proc\""
            done <<< "$TOP_MEM_PROCESSES"
        fi
        echo "      ]"
        echo "    },"
        echo "    \"swap\": {"
        echo "      \"total\": \"$SWAP_TOTAL\","
        echo "      \"used\": \"$SWAP_USED\","
        echo "      \"free\": \"$SWAP_FREE\","
        echo "      \"percent\": $SWAP_PERCENT"
        echo "    },"
        echo "    \"disk\": {"
        echo "      \"total\": \"$DISK_TOTAL\","
        echo "      \"used\": \"$DISK_USED\","
        echo "      \"available\": \"$DISK_AVAIL\","
        echo "      \"percent\": $DISK_PERCENT,"
        echo "      \"status\": \"$DISK_STATUS\","
        echo "      \"recommendation\": \"$DISK_RECOMMEND\","
        echo "      \"partitions\": ["
        first=1
        if [[ -n "$DISK_PARTITIONS" ]]; then
            while IFS= read -r part; do
                if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
                echo "        \"$part\""
            done <<< "$DISK_PARTITIONS"
        fi
        echo "      ],"
        echo "      \"io_read\": \"${DISK_READ:-N/A}\","
        echo "      \"io_write\": \"${DISK_WRITE:-N/A}\""
        echo "    },"
        echo "    \"network\": {"
        echo "      \"interfaces\": \"$NET_INTERFACES\","
        echo "      \"main_interface\": \"$MAIN_IFACE\","
        echo "      \"speed\": \"${NET_SPEED:-unknown}\","
        echo "      \"rx_mb\": $RX_MB,"
        echo "      \"tx_mb\": $TX_MB,"
        echo "      \"tcp_connections\": $TCP_CONNECTIONS,"
        echo "      \"listening_ports\": \"$LISTENING_PORTS\""
        echo "    }"
        echo "  },"
        echo "  \"dangerous_services\": ["
        first=1
        for item in "${FOUND_OLD[@]}"; do
            if [[ $first -eq 1 ]]; then first=0; else echo ","; fi
            echo "    \"$item\""
        done
        echo "  ],"
        echo "  \"recommendations\": {"
        echo "    \"updates\": \"$([[ $UPDATES_COUNT -gt 0 ]] && echo 'Updates available' || echo 'System up to date')\","
        echo "    \"dangerous_services\": \"${#FOUND_OLD[@]} found\","
        echo "    \"cpu_usage\": \"$CPU_USAGE%\","
        echo "    \"memory_usage\": \"$MEM_PERCENT%\","
        echo "    \"disk_usage\": \"$DISK_PERCENT%\""
        echo "  }"
        echo "}"
    } > "$JSON_FILE"
    
    echo -e "${GREEN}✓ Reports generated:${NC}"
    echo "  📄 TXT: $REPORT_FILE"
    echo "  📊 JSON: $JSON_FILE"
}

# ------------------- MAIN FUNCTION -------------------
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   System Scanner + Performance Monitor${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    detect_os
    echo ""
    
    case "$OS_ID" in
        ubuntu|debian|linuxmint|parrot)
            check_updates_debian
            ;;
        rhel|centos|fedora|rocky|almalinux)
            check_updates_redhat
            ;;
        arch|manjaro)
            check_updates_arch
            ;;
        *)
            echo -e "${RED}⚠️  Unsupported OS: $OS_NAME${NC}"
            echo "Only checking services and performance"
            UPDATES_COUNT=0
            UPDATES_LIST=""
            SECURITY_COUNT=0
            ;;
    esac
    
    echo ""
    monitor_performance
    echo ""
    check_old_services
    echo ""
    generate_reports
    
    echo ""
    echo -e "${GREEN}✅ Scan completed!${NC}"
    echo -e "📂 Reports saved in: $SCRIPT_DIR"
}

# ------------------- EXECUTE SCRIPT -------------------
main
