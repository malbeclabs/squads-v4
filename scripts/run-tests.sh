#!/usr/bin/env bash
# Runs the TypeScript test suite against a solana-test-validator in a container.
#
# Anchor is not involved. It only ever orchestrated this: start a validator, build,
# deploy, run mocha. --bpf-program and --account cover the first three, and the tests
# talk to 127.0.0.1:8899 directly through @solana/web3.js rather than an anchor
# provider, so nothing in the suite needs it.
set -euo pipefail

IMAGE="${IMAGE:-solanafoundation/solana-verifiable-build:2.3.13}"
CONTAINER="${CONTAINER:-squads-test-validator}"
# The program builds with --features testing for the suite, which selects this ID.
TEST_PROGRAM_ID="${TEST_PROGRAM_ID:-GyhGAqjokLwF9UXdQ2dR5Zwiup242j4mX4J1tSMKyAmD}"
FIXTURE_ADDRESS="${FIXTURE_ADDRESS:-D3oQ6QxSYk6aKUsmBTa9BghFQvbRi7kxP6h95NSdjjXz}"
FIXTURE_FILE="tests/fixtures/pre-rent-collector/multisig-account.json"
SO="target/deploy-testing/squads_multisig_program.so"
# 16 ticks at the validator's 160 ticks per second is a 100ms slot, against a 400ms
# default. The suite spends most of its time waiting for confirmations, so this is
# most of the difference between a two minute run and a fifteen minute one. It is not
# set lower because vault_transaction_create_from_buffer confirms a transaction it
# expects to fail, and at 50ms that confirmation rejects before the test can read the
# logs it asserts on.
TICKS_PER_SLOT="${TICKS_PER_SLOT:-16}"

test -f "$SO" || { echo "Missing $SO. Run 'make build-testing' first." >&2; exit 1; }

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

# 8899 is RPC and 8900 is the PubSub websocket. web3.js confirms transactions over the
# websocket, so omitting 8900 fails every confirmation with ECONNREFUSED.
docker run -d --rm --name "$CONTAINER" --platform linux/amd64 \
	-p 8899:8899 -p 8900:8900 \
	-v "$PWD":/work -w /tmp \
	"$IMAGE" \
	solana-test-validator --reset --bind-address 0.0.0.0 \
		--ticks-per-slot "$TICKS_PER_SLOT" \
		--bpf-program "$TEST_PROGRAM_ID" "/work/$SO" \
		--account "$FIXTURE_ADDRESS" "/work/$FIXTURE_FILE" >/dev/null

for _ in $(seq 1 60); do
	if curl -sf -X POST -H 'Content-Type: application/json' \
		-d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' \
		http://127.0.0.1:8899 2>/dev/null | grep -q '"result":"ok"'; then
		break
	fi
	sleep 1
done

curl -sf -X POST -H 'Content-Type: application/json' \
	-d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' \
	http://127.0.0.1:8899 | grep -q '"result":"ok"' \
	|| { echo "Validator did not become healthy." >&2; docker logs --tail 40 "$CONTAINER" >&2; exit 1; }

# tests/utils.ts reads the program keypair from this path.
mkdir -p target/deploy
cp test-program-keypair.json target/deploy/squads_multisig_program-keypair.json

npx mocha --node-option require=ts-node/register --extension ts -t 1000000 tests/index.ts
