#!/usr/bin/env bash

CHAINID="test"

rm -rf /root/.celestia-app

# Build genesis file incl account for passed address
coins="1000000000000000utia"
celestia-appd init $CHAINID --chain-id $CHAINID
celestia-appd keys add validator --keyring-backend="test"
# this won't work because some proto types are declared twice and the logs output to stdout (dependency hell involving iavl)
celestia-appd add-genesis-account $(celestia-appd keys show validator -a --keyring-backend="test") $coins
celestia-appd gentx validator 5000000000utia \
  --keyring-backend="test" \
  --chain-id $CHAINID \
  --evm-address 0x966e6f22781EF6a6A82BBB4DB3df8E225DfD9488 # private key: da6ed55cb2894ac2c9c10209c09de8e8b9d109b910338d5bf3d747a7e1fc9eb9

celestia-appd collect-gentxs

# Set proper defaults and change ports
# If you encounter: `sed: -I or -i may not be used with stdin` on MacOS you can mitigate by installing gnu-sed
# https://gist.github.com/andre3k1/e3a1a7133fded5de5a9ee99c87c6fa0d?permalink_comment_id=3082272#gistcomment-3082272
sed -i'.bak' 's#"tcp://127.0.0.1:26657"#"tcp://0.0.0.0:26657"#g' ~/.celestia-app/config/config.toml
sed -i'.bak' 's/timeout_commit = "25s"/timeout_commit = "1s"/g' ~/.celestia-app/config/config.toml
sed -i'.bak' 's/timeout_propose = "3s"/timeout_propose = "1s"/g' ~/.celestia-app/config/config.toml
sed -i'.bak' 's/index_all_keys = false/index_all_keys = true/g' ~/.celestia-app/config/config.toml
sed -i'.bak' 's/mode = "full"/mode = "validator"/g' ~/.celestia-app/config/config.toml

mkdir -p /bridge/keys/
cp -r ~/.celestia-app/keyring-test/ /bridge/keys/keyring-test/

# Start the celestia-app
celestia-appd start &

# Try to get the genesis hash. Usually first request returns an empty string (port is not open, curl fails), later attempts
# returns "null" if block was not yet produced.
GENESIS=
CNT=0
MAX=30
while [ "${#GENESIS}" -le 4 -a $CNT -ne $MAX ]; do
	GENESIS=$(curl -s http://127.0.0.1:26657/block?height=1 | jq '.result.block_id.hash' | tr -d '"')
	((CNT++))
	sleep 1
done

export CELESTIA_CUSTOM=test:$GENESIS
echo $CELESTIA_CUSTOM

celestia bridge init --node.store /bridge
export CELESTIA_NODE_AUTH_TOKEN=$(celestia bridge auth admin --node.store /bridge)
echo "WARNING: Keep this auth token secret **DO NOT** log this auth token outside of development. CELESTIA_NODE_AUTH_TOKEN=$CELESTIA_NODE_AUTH_TOKEN"
celestia bridge start \
  --node.store /bridge --gateway \
  --core.ip 127.0.0.1 \
  --keyring.accname validator \
  --gateway.deprecated-endpoints
