#!/usr/bin/env bash
# =============================================================================
# Gnoland test13 — Validator Setup Script
# =============================================================================
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
CHAIN_ID="test-13"
GENESIS_URL="https://github.com/gnolang/gno/releases/download/chain/test13/genesis.json"
GENESIS_SHA256="56f56e135174feff9f93283d5ec7e4ec955cd5155108aff5009d4fd51c5adaf2"
SNAPSHOT_URL="https://snapshots.luckystar.asia/gnolandtest/gnoland_data.tar.zst"
RPC_REMOTE="https://rpc.test13.testnets.gno.land"
PERSISTENT_PEERS="g142k7zc2qym3c0u6jmkf6rv26llgr2f4nakmlmt@sentry-1.test13.testnets.gno.land:26656,g1lxkf9gn7kddrr26c640ww5wg3ezsm22we8cjpc@sentry-2.test13.testnets.gno.land:26656"
DESCRIPTION_MAX=2048

GNO_DIR="$HOME/gno"
DATA_DIR="$GNO_DIR/gnoland-data"
SERVICE_FILE="/etc/systemd/system/gnoland.service"

# Default ports (changeable)
P2P_PORT=17656
RPC_PORT=17657
PROM_PORT=17660

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }
die()     { error "$*"; exit 1; }

press_enter() {
    echo ""
    read -rp "  Press Enter to continue..."
}

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' not found. Run option 1 (Install Node) first."
}

gnoland_bin() {
    command -v gnoland 2>/dev/null || echo "$HOME/go/bin/gnoland"
}

rpc_port_flag() {
    echo "http://127.0.0.1:${RPC_PORT}/status"
}

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║         Gnoland test13 — Validator Setup          ║"
    echo "  ║              Chain ID: test-13                     ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        banner
        echo -e "  ${BOLD}Main Menu${NC}\n"
        echo "  [1] Install node"
        echo "  [2] Check sync status"
        echo "  [3] Add wallet / Recover wallet"
        echo "  [4] Load snapshot"
        echo "  [5] Add / Update description"
        echo "  [6] Register validator"
        echo "  [7] Service management"
        echo "  [0] Exit"
        echo ""
        read -rp "  Choose an option: " choice

        case "$choice" in
            1) install_node ;;
            2) check_sync ;;
            3) wallet_menu ;;
            4) load_snapshot ;;
            5) update_description ;;
            6) register_validator ;;
            7) service_menu ;;
            0) echo ""; exit 0 ;;
            *) warn "Invalid option, try again."; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. INSTALL NODE
# ══════════════════════════════════════════════════════════════════════════════
install_node() {
    banner
    echo -e "  ${BOLD}[1] Install Node${NC}\n"

    # ── Dependencies ──────────────────────────────────────────────────────────
    info "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y git make wget curl zstd pv python3 build-essential 2>&1 \
        | grep -E "^(Get|Setting|Preparing|Unpacking|Processing)" || true
    success "Dependencies installed."

    # ── Go ────────────────────────────────────────────────────────────────────
    if command -v go &>/dev/null; then
        GO_VER=$(go version | awk '{print $3}')
        info "Go already installed: $GO_VER"
    else
        info "Installing Go..."
        GO_VERSION="1.22.4"
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz

        # Add to PATH if not already there
        if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
            echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
        fi
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
        success "Go $(go version | awk '{print $3}') installed."
    fi

    # ── Clone & build ─────────────────────────────────────────────────────────
    if [[ -d "$GNO_DIR/.git" ]]; then
        info "Repo already exists at $GNO_DIR, pulling latest..."
        cd "$GNO_DIR"
        git fetch origin chain/test13
        git checkout chain/test13
        git pull origin chain/test13
    else
        info "Cloning gno repository (branch: chain/test13)..."
        git clone --branch chain/test13 --depth 1 \
            https://github.com/gnolang/gno.git "$GNO_DIR"
    fi

    info "Building gnoland and gnokey (this may take a few minutes)..."
    cd "$GNO_DIR"
    make -C gno.land install.gnoland install.gnokey
    success "Binaries built: $(which gnoland)"

    # ── Genesis ───────────────────────────────────────────────────────────────
    if [[ -f "$GNO_DIR/genesis.json" ]]; then
        info "genesis.json already exists, verifying checksum..."
    else
        info "Downloading genesis.json..."
        wget -q -O "$GNO_DIR/genesis.json" "$GENESIS_URL"
    fi

    ACTUAL_SHA=$(shasum -a 256 "$GNO_DIR/genesis.json" | awk '{print $1}')
    if [[ "$ACTUAL_SHA" == "$GENESIS_SHA256" ]]; then
        success "Genesis checksum verified."
    else
        die "Genesis checksum mismatch!\n  Expected: $GENESIS_SHA256\n  Got:      $ACTUAL_SHA"
    fi

    # ── Init config & secrets ─────────────────────────────────────────────────
    cd "$GNO_DIR"
    if [[ ! -f "$GNO_DIR/gnoland-data/config/config.toml" ]]; then
        info "Initializing config and secrets..."
        GNOROOT="$GNO_DIR" gnoland config init
        GNOROOT="$GNO_DIR" gnoland secrets init
        success "Config and secrets initialized."
    else
        info "Config already exists, skipping init."
    fi

    # ── Node-specific config ───────────────────────────────────────────────────
    echo ""
    read -rp "  Enter your node moniker (name): " MONIKER
    read -rp "  Enter your public server IP (for p2p.external_address): " SERVER_IP
    echo ""
    echo "  Port configuration:"
    echo "  Default ports are 17656/17657/17660."
    read -rp "  Use default ports? [Y/n]: " USE_DEFAULT_PORTS
    USE_DEFAULT_PORTS=${USE_DEFAULT_PORTS:-Y}

    if [[ ! "$USE_DEFAULT_PORTS" =~ ^[Yy]$ ]]; then
        read -rp "  P2P port  [default: 17656]: " P2P_PORT_IN
        read -rp "  RPC port  [default: 17657]: " RPC_PORT_IN
        read -rp "  Prom port [default: 17660]: " PROM_PORT_IN
        P2P_PORT=${P2P_PORT_IN:-17656}
        RPC_PORT=${RPC_PORT_IN:-17657}
        PROM_PORT=${PROM_PORT_IN:-17660}
    fi

    info "Applying config settings..."
    cd "$GNO_DIR"
    GNOROOT="$GNO_DIR" gnoland config set moniker "$MONIKER"
    GNOROOT="$GNO_DIR" gnoland config set p2p.persistent_peers "$PERSISTENT_PEERS"
    GNOROOT="$GNO_DIR" gnoland config set p2p.external_address "${SERVER_IP}:${P2P_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set p2p.laddr "tcp://0.0.0.0:${P2P_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set rpc.laddr "tcp://127.0.0.1:${RPC_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set telemetry.prometheus_listen_addr ":${PROM_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set application.prune_strategy syncable
    GNOROOT="$GNO_DIR" gnoland config set consensus.timeout_commit 3s
    GNOROOT="$GNO_DIR" gnoland config set consensus.peer_gossip_sleep_duration 10ms
    GNOROOT="$GNO_DIR" gnoland config set p2p.flush_throttle_timeout 10ms
    GNOROOT="$GNO_DIR" gnoland config set mempool.size 10000
    GNOROOT="$GNO_DIR" gnoland config set p2p.max_num_outbound_peers 40
    GNOROOT="$GNO_DIR" gnoland config set p2p.pex true
    success "Config applied."

    # ── Systemd service ───────────────────────────────────────────────────────
    info "Creating systemd service..."
    GNOLAND_BIN=$(gnoland_bin)
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Gnoland test-13 Node
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$GNO_DIR
Environment=GNOROOT=$GNO_DIR
Environment=HOME=$HOME
ExecStart=$GNOLAND_BIN start \\
  --chainid $CHAIN_ID \\
  --genesis $GNO_DIR/genesis.json \\
  --skip-genesis-sig-verification
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gnoland

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable gnoland
    success "Systemd service created and enabled."

    echo ""
    echo -e "  ${BOLD}Installation complete!${NC}"
    echo ""
    echo "  Next steps:"
    echo "  → Option [4] Load snapshot   (recommended — much faster sync)"
    echo "  → Option [7] Service management → Start node"
    echo "  → Option [2] Check sync status"
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. CHECK SYNC STATUS
# ══════════════════════════════════════════════════════════════════════════════
check_sync() {
    banner
    echo -e "  ${BOLD}[2] Sync Status${NC}\n"

    STATUS=$(curl -s "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null || true)

    if [[ -z "$STATUS" ]]; then
        warn "Cannot reach node at port $RPC_PORT."
        echo "  → Is the node running? Check: sudo systemctl status gnoland"
    else
        CATCHING_UP=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print(d['catching_up'])" 2>/dev/null || echo "unknown")
        HEIGHT=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print(d['latest_block_height'])" 2>/dev/null || echo "unknown")
        TIME=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print(d['latest_block_time'][:19])" 2>/dev/null || echo "unknown")

        echo "  Latest block height : $HEIGHT"
        echo "  Latest block time   : $TIME"

        if [[ "$CATCHING_UP" == "False" ]]; then
            echo -e "  Catching up         : ${GREEN}No — fully synced ✓${NC}"
        else
            echo -e "  Catching up         : ${YELLOW}Yes — still syncing...${NC}"
        fi
    fi

    echo ""
    echo "  Validator key info:"
    cd "$GNO_DIR" 2>/dev/null && GNOROOT="$GNO_DIR" gnoland secrets get validator_key 2>/dev/null || \
        warn "Could not read validator key. Is node initialized?"

    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. WALLET MENU
# ══════════════════════════════════════════════════════════════════════════════
wallet_menu() {
    while true; do
        banner
        echo -e "  ${BOLD}[3] Wallet${NC}\n"
        echo "  [1] Create new wallet"
        echo "  [2] Recover wallet from mnemonic"
        echo "  [3] List wallets"
        echo "  [0] Back"
        echo ""
        read -rp "  Choose: " choice

        case "$choice" in
            1) wallet_create ;;
            2) wallet_recover ;;
            3) wallet_list ;;
            0) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

wallet_create() {
    banner
    echo -e "  ${BOLD}Create New Wallet${NC}\n"
    require_cmd gnokey

    read -rp "  Enter key name: " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    echo ""
    warn "You will be shown a 24-word mnemonic. Write it down and store it safely."
    warn "It CANNOT be recovered if lost."
    press_enter

    gnokey add "$KEY_NAME"

    echo ""
    success "Wallet '$KEY_NAME' created."
    press_enter
}

wallet_recover() {
    banner
    echo -e "  ${BOLD}Recover Wallet from Mnemonic${NC}\n"
    require_cmd gnokey

    read -rp "  Enter key name: " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    echo ""
    info "You will be prompted for your mnemonic phrase."
    gnokey add "$KEY_NAME" --recover

    echo ""
    success "Wallet '$KEY_NAME' recovered."
    press_enter
}

wallet_list() {
    banner
    echo -e "  ${BOLD}Wallets${NC}\n"
    require_cmd gnokey
    gnokey list
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. LOAD SNAPSHOT
# ══════════════════════════════════════════════════════════════════════════════
load_snapshot() {
    banner
    echo -e "  ${BOLD}[4] Load Snapshot${NC}\n"

    echo "  Snapshot source: $SNAPSHOT_URL"
    echo ""
    warn "This will DELETE existing chain data (db and wal)."
    warn "Your keys, config, and secrets will NOT be touched."
    echo ""
    read -rp "  Continue? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    # Stop node
    info "Stopping gnoland service..."
    sudo systemctl stop gnoland 2>/dev/null || pkill -f "gnoland start" 2>/dev/null || true
    sleep 2

    # Clear old data
    info "Clearing old chain data..."
    rm -rf "$DATA_DIR/db" "$DATA_DIR/wal"
    mkdir -p "$DATA_DIR"
    success "Old data cleared."

    # Download and extract
    info "Downloading and extracting snapshot (this may take a few minutes)..."
    echo ""

    if command -v pv &>/dev/null; then
        curl -L "$SNAPSHOT_URL" | pv | zstd -d | tar -xf - -C "$DATA_DIR"
    else
        curl -L --progress-bar "$SNAPSHOT_URL" | zstd -d | tar -xf - -C "$DATA_DIR"
    fi

    echo ""
    success "Snapshot loaded."
    echo ""
    echo "  Data directory contents:"
    ls -lh "$DATA_DIR/" 2>/dev/null || true

    echo ""
    echo "  Start the node via option [7] Service management → Start."
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. ADD / UPDATE DESCRIPTION
# ══════════════════════════════════════════════════════════════════════════════
update_description() {
    banner
    echo -e "  ${BOLD}[5] Add / Update Description${NC}\n"
    require_cmd gnokey

    # Get operator address
    echo "  Available wallets:"
    gnokey list
    echo ""
    read -rp "  Enter key name: " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    OPERATOR_ADDR=$(gnokey list 2>/dev/null | grep "^[0-9]" | grep "$KEY_NAME" | \
        grep -oP 'addr: \K[^ ]+' || true)

    if [[ -z "$OPERATOR_ADDR" ]]; then
        read -rp "  Enter your g1... operator address manually: " OPERATOR_ADDR
    fi

    echo ""
    echo "  Enter your description."
    echo "  Limit: $DESCRIPTION_MAX characters. Markdown is supported."
    echo "  Type your description below, then press Ctrl+D when done:"
    echo "  ─────────────────────────────────────────────────────────"
    DESCRIPTION=$(cat)

    DESC_LEN=${#DESCRIPTION}
    echo ""
    info "Description length: $DESC_LEN / $DESCRIPTION_MAX characters"

    if [[ $DESC_LEN -gt $DESCRIPTION_MAX ]]; then
        error "Description exceeds $DESCRIPTION_MAX character limit ($DESC_LEN chars)."
        error "Please shorten your description and try again."
        press_enter
        return
    fi

    if [[ $DESC_LEN -eq 0 ]]; then
        warn "Description is empty. Aborting."
        press_enter
        return
    fi

    echo ""
    echo "  Preview (first 200 chars):"
    echo "  ${DESCRIPTION:0:200}..."
    echo ""
    read -rp "  Submit this description? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    gnokey maketx call \
        --pkgpath "gno.land/r/gnops/valopers" \
        --func "UpdateDescription" \
        --args "$OPERATOR_ADDR" \
        --args "$DESCRIPTION" \
        --gas-fee 1000000ugnot \
        --gas-wanted 50000000 \
        --chainid "$CHAIN_ID" \
        --remote "$RPC_REMOTE" \
        --broadcast \
        "$KEY_NAME"

    echo ""
    success "Description updated."
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. REGISTER VALIDATOR
# ══════════════════════════════════════════════════════════════════════════════
register_validator() {
    banner
    echo -e "  ${BOLD}[6] Register Validator${NC}\n"
    require_cmd gnokey

    # Check sync first
    CATCHING_UP=$(curl -s "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['result']['sync_info']['catching_up'])" 2>/dev/null || echo "unknown")

    if [[ "$CATCHING_UP" == "True" ]]; then
        warn "Node is still syncing. It is strongly recommended to wait until fully synced."
        read -rp "  Continue anyway? [y/N]: " CONT
        [[ "$CONT" =~ ^[Yy]$ ]] || { press_enter; return; }
    fi

    # Get consensus pubkey
    info "Reading consensus public key..."
    cd "$GNO_DIR"
    VALIDATOR_INFO=$(GNOROOT="$GNO_DIR" gnoland secrets get validator_key 2>/dev/null || true)
    CONSENSUS_PUBKEY=$(echo "$VALIDATOR_INFO" | python3 -c \
        "import sys,json; print(json.load(sys.stdin)['pub_key'])" 2>/dev/null || true)

    if [[ -z "$CONSENSUS_PUBKEY" ]]; then
        warn "Could not auto-detect consensus pubkey."
        read -rp "  Enter your gpub1... consensus pubkey manually: " CONSENSUS_PUBKEY
    else
        info "Consensus pubkey: $CONSENSUS_PUBKEY"
    fi

    echo ""
    echo "  Available wallets:"
    gnokey list
    echo ""
    read -rp "  Enter key name (operator wallet): " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    OPERATOR_ADDR=$(gnokey list 2>/dev/null | grep "^[0-9]" | grep "$KEY_NAME" | \
        grep -oP 'addr: \K[^ ]+' || true)

    if [[ -z "$OPERATOR_ADDR" ]]; then
        read -rp "  Enter your g1... operator address manually: " OPERATOR_ADDR
    fi
    info "Operator address: $OPERATOR_ADDR"

    # Check balance
    echo ""
    info "Checking balance..."
    BALANCE=$(gnokey query -remote "$RPC_REMOTE" "auth/accounts/$OPERATOR_ADDR" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BaseAccount',{}).get('coins','0ugnot'))" 2>/dev/null || echo "unknown")
    info "Balance: $BALANCE"

    if [[ "$BALANCE" == "0ugnot" || "$BALANCE" == "" ]]; then
        warn "Balance is 0. Get testnet GNOT from: https://test13.testnets.gno.land/faucet"
        warn "Then run this option again."
        press_enter
        return
    fi

    # Gather registration info
    echo ""
    read -rp "  Moniker (node display name): " MONIKER
    echo ""
    echo "  Server type options: cloud | on-prem | data-center"
    read -rp "  Server type: " SERVER_TYPE
    echo ""
    echo "  Enter a short description (press Ctrl+D when done):"
    echo "  Note: Full description can be set/updated via option [5]."
    echo "  ─────────────────────────────────────────────────────────"
    DESCRIPTION=$(cat)

    DESC_LEN=${#DESCRIPTION}
    if [[ $DESC_LEN -gt $DESCRIPTION_MAX ]]; then
        error "Description exceeds $DESCRIPTION_MAX characters ($DESC_LEN). Shorten and retry."
        press_enter
        return
    fi

    # Summary
    echo ""
    echo "  ─── Registration summary ────────────────────────────────"
    echo "  Moniker         : $MONIKER"
    echo "  Operator address: $OPERATOR_ADDR"
    echo "  Consensus pubkey: $CONSENSUS_PUBKEY"
    echo "  Server type     : $SERVER_TYPE"
    echo "  Description     : ${DESCRIPTION:0:80}..."
    echo "  ─────────────────────────────────────────────────────────"
    echo ""
    read -rp "  Submit registration? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    gnokey maketx call \
        --pkgpath gno.land/r/gnops/valopers \
        --func Register \
        --args "$MONIKER" \
        --args "$DESCRIPTION" \
        --args "$SERVER_TYPE" \
        --args "$OPERATOR_ADDR" \
        --args "$CONSENSUS_PUBKEY" \
        --gas-fee 1000000ugnot \
        --gas-wanted 50000000 \
        --chainid "$CHAIN_ID" \
        --remote "$RPC_REMOTE" \
        --broadcast \
        "$KEY_NAME"

    echo ""
    success "Registration submitted!"
    echo ""
    echo "  You are now a validator CANDIDATE."
    echo "  A GovDAO member must create and pass a proposal to add you to"
    echo "  the active validator set."
    echo ""
    echo "  Check your profile:"
    echo "  https://test13.testnets.gno.land/r/gnops/valopers:$OPERATOR_ADDR"
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 7. SERVICE MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════
service_menu() {
    while true; do
        banner
        echo -e "  ${BOLD}[7] Service Management${NC}\n"

        # Show current status
        if systemctl is-active --quiet gnoland 2>/dev/null; then
            echo -e "  Status: ${GREEN}● running${NC}"
        else
            echo -e "  Status: ${RED}● stopped${NC}"
        fi
        echo ""
        echo "  [1] Start"
        echo "  [2] Stop"
        echo "  [3] Restart"
        echo "  [4] View live logs (Ctrl+C to exit)"
        echo "  [5] View last 50 log lines"
        echo "  [0] Back"
        echo ""
        read -rp "  Choose: " choice

        case "$choice" in
            1)
                sudo systemctl start gnoland
                success "Node started."
                sleep 1
                ;;
            2)
                sudo systemctl stop gnoland
                success "Node stopped."
                sleep 1
                ;;
            3)
                sudo systemctl restart gnoland
                success "Node restarted."
                sleep 1
                ;;
            4)
                echo ""
                info "Press Ctrl+C to return to menu."
                sleep 1
                sudo journalctl -u gnoland -f || true
                ;;
            5)
                echo ""
                sudo journalctl -u gnoland -n 50 --no-pager || true
                press_enter
                ;;
            0) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════
main_menu
