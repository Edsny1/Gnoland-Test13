# Gnoland test13 Validator Node Setup

Full guide to run a validator node on **gno.land test13** testnet.

> **Quick start:** Use the automated setup script — `bash scripts/setup.sh`

---

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 200 GB SSD | 500 GB NVMe |
| Go | 1.22+ | latest |

---


## Auto Install

```bash
# Download and run setup script
wget -O setup.sh https://raw.githubusercontent.com/Edsny1/Gnoland-Test13/Edsny/scripts/setup.sh
chmod +x setup.sh
bash setup.sh
```

Or with curl:

```bash
curl -o setup.sh https://raw.githubusercontent.com/Edsny1/Gnoland-Test13/Edsny/scripts/setup.sh
chmod +x setup.sh
bash setup.sh
```



## Manual Setup

### 1. Install dependencies

```bash
sudo apt update && sudo apt install -y git make wget curl zstd pv
```

Install Go (skip if already installed):

```bash
GO_VERSION="1.22.4"
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm "go${GO_VERSION}.linux-amd64.tar.gz"

echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
```


### 2. Build binaries

```bash
git clone https://github.com/gnolang/gno.git
cd gno && git checkout chain/test13
make -C gno.land install.gnoland install.gnokey
```

Verify:

```bash
gnoland version
gnokey --help
```

---

### 3. Download and verify genesis

```bash
cd ~/gno

wget -O genesis.json \
  https://github.com/gnolang/gno/releases/download/chain/test13/genesis.json

# Verify SHA256 — must match exactly
shasum -a 256 genesis.json
# expected: 56f56e135174feff9f93283d5ec7e4ec955cd5155108aff5009d4fd51c5adaf2
```

---

### 4. Initialize config and keys

```bash
cd ~/gno
gnoland config init
gnoland secrets init
```

---

### 5. Configure node

Apply required chain-wide settings:

```bash
# Persistent peers (required)
gnoland config set p2p.persistent_peers \
  "g142k7zc2qym3c0u6jmkf6rv26llgr2f4nakmlmt@sentry-1.test13.testnets.gno.land:26656,g1lxkf9gn7kddrr26c640ww5wg3ezsm22we8cjpc@sentry-2.test13.testnets.gno.land:26656"

# Chain-wide consensus settings (must match exactly)
gnoland config set application.prune_strategy syncable
gnoland config set consensus.timeout_commit 3s
gnoland config set consensus.peer_gossip_sleep_duration 10ms
gnoland config set p2p.flush_throttle_timeout 10ms

# Performance
gnoland config set mempool.size 10000
gnoland config set p2p.max_num_outbound_peers 40
```

Set your node-specific values:

```bash
gnoland config set moniker "YOUR-NODE-NAME"
gnoland config set p2p.external_address "YOUR-SERVER-IP:26656"
gnoland config set p2p.pex true
```

#### Using custom ports (17xxx)

If port 26xxx is already in use on your server:

```bash
gnoland config set p2p.laddr "tcp://0.0.0.0:17656"
gnoland config set rpc.laddr "tcp://127.0.0.1:17657"
gnoland config set telemetry.prometheus_listen_addr ":17660"
```

> Update `p2p.external_address` to match your P2P port.

---

### 6. Load snapshot (fast sync)

Skip hours of syncing by using a community snapshot:

```bash
# Stop node if running
sudo systemctl stop gnoland 2>/dev/null || pkill -f "gnoland start" 2>/dev/null || true

# Clear old data (keys and config are NOT touched)
rm -rf ~/gno/gnoland-data/db ~/gno/gnoland-data/wal

# Download and extract snapshot
curl -L https://snapshots.luckystar.asia/gnolandtest/gnoland_data.tar.zst \
  | zstd -d \
  | tar -xf - -C ~/gno/gnoland-data
```

---

### 7. Create systemd service

```bash
sudo tee /etc/systemd/system/gnoland.service > /dev/null <<EOF
[Unit]
Description=Gnoland test-13 Node
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/gno
Environment=GNOROOT=$HOME/gno
Environment=HOME=$HOME
ExecStart=$(which gnoland) start \
  --chainid test-13 \
  --genesis $HOME/gno/genesis.json \
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
sudo systemctl start gnoland
```

Check logs:

```bash
sudo journalctl -u gnoland -f
```

---

### 8. Check sync status

```bash
# Replace 17657 with 26657 if you're using default ports
curl -s http://127.0.0.1:17657/status | python3 -c "
import sys, json
d = json.load(sys.stdin)
info = d['result']['sync_info']
print('Latest block :', info['latest_block_height'])
print('Catching up  :', info['catching_up'])
"
```

Wait until `catching_up: False` before proceeding.

---

### 9. Add operator wallet

Create a new wallet:

```bash
gnokey add YOUR-KEY-NAME
```

Or recover from existing mnemonic:

```bash
gnokey add YOUR-KEY-NAME --recover
```

Get your operator address:

```bash
gnokey list
```

---

### 10. Get testnet GNOT

Visit the faucet and request tokens for your `g1...` operator address:

**https://test13.testnets.gno.land/faucet**

Verify balance:

```bash
gnokey query \
  -remote "https://rpc.test13.testnets.gno.land" \
  auth/accounts/YOUR-G1-ADDRESS
```

---

### 11. Register as validator candidate

Get your consensus public key:

```bash
gnoland secrets get validator_key
# Note the gpub1... value
```

Register on the valoper realm:

```bash
gnokey maketx call \
  --pkgpath gno.land/r/gnops/valopers \
  --func Register \
  --args "YOUR-MONIKER" \
  --args "YOUR-DESCRIPTION" \
  --args "data-center" \
  --args "YOUR-G1-OPERATOR-ADDRESS" \
  --args "YOUR-GPUB1-CONSENSUS-PUBKEY" \
  --gas-fee 1000000ugnot \
  --gas-wanted 50000000 \
  --chainid test-13 \
  --remote https://rpc.test13.testnets.gno.land \
  --broadcast \
  YOUR-KEY-NAME
```

> **Note:** Registration only makes you a **candidate**. A GovDAO member must create and pass a proposal to add you to the active validator set.

---

### 12. Update description (optional)

Description limit is **2048 characters**. To update after registration:

```bash
gnokey maketx call \
  --pkgpath "gno.land/r/gnops/valopers" \
  --func "UpdateDescription" \
  --args "YOUR-G1-OPERATOR-ADDRESS" \
  --args "YOUR-NEW-DESCRIPTION" \
  --gas-fee 1000000ugnot \
  --gas-wanted 50000000 \
  --chainid test-13 \
  --remote https://rpc.test13.testnets.gno.land \
  --broadcast \
  YOUR-KEY-NAME
```

---

## Useful commands

```bash
# Service management
sudo systemctl start gnoland
sudo systemctl stop gnoland
sudo systemctl restart gnoland
sudo systemctl status gnoland

# Logs
sudo journalctl -u gnoland -f
sudo journalctl -u gnoland --since "1 hour ago"

# Sync status
curl -s http://127.0.0.1:17657/status | python3 -c \
  "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print('Height:', d['latest_block_height'], '| Catching up:', d['catching_up'])"

# Validator key info
gnoland secrets get validator_key

# Wallet list
gnokey list
```

---

## Explorer & resources

| Resource | URL |
|----------|-----|
| Explorer | https://test13.testnets.gno.land |
| Faucet | https://test13.testnets.gno.land/faucet |
| Valopers | https://test13.testnets.gno.land/r/gnops/valopers |
| Active validators | https://test13.testnets.gno.land/r/sys/validators/v3 |
| RPC | https://rpc.test13.testnets.gno.land |
| Snapshot | https://snapshots.luckystar.asia/gnolandtest/ |

---

## Firewall

```bash
# P2P — must be open to public
sudo ufw allow 17656/tcp comment "gnoland P2P"

# RPC — open if you serve public endpoints
sudo ufw allow 17657/tcp comment "gnoland RPC"

# Prometheus — restrict to monitoring server only
sudo ufw allow from YOUR-MONITORING-IP to any port 17660
```
# Gnoland-Test13
