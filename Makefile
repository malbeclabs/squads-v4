IMAGE_ANCHOR := squads-dz/anchor:0.32.1
PROGRAM_ID   := DZSQabvc4J8VTvjphhadVr9PDsBEqLyxQKYhbFiYfVoS
RPC          ?= https://doublezero-mainnet-beta.rpcpool.com/db336024-e7a8-46b1-80e5-352dd77060ab

# The keypair that signs the IDL account write and pays its rent. It must be the
# program's upgrade authority. Override for a keypair kept anywhere else:
#   make idl-init WALLET=/path/to/authority.json
WALLET ?= $(HOME)/.config/solana/id.json

# A leading ~ never reaches the shell unquoted, and docker needs an absolute host path
# for a bind mount, so normalize both here rather than at each use.
override WALLET := $(abspath $(patsubst ~/%,$(HOME)/%,$(WALLET)))

ANCHOR_RUN = docker run --rm -v "$$PWD":/work -w /work $(IMAGE_ANCHOR)

# Mounts the keypair itself rather than a directory, so WALLET can point anywhere on
# the host. Read-only, since anchor only reads it.
ANCHOR_RUN_SIGNED = docker run --rm -v "$$PWD":/work -w /work \
	-v "$(WALLET)":/wallet.json:ro \
	$(IMAGE_ANCHOR)

# Docker silently creates a directory for a bind mount whose source is missing, which
# would surface as a confusing anchor error rather than a missing keypair.
require-wallet:
	@test -f "$(WALLET)" || { echo "No keypair at $(WALLET). Pass WALLET=<path>." >&2; exit 1; }

.PHONY: build build-testing test idl anchor-image require-wallet idl-init idl-upgrade clean clean-docker

# The program builds inside Docker so no Solana or Anchor toolchain is needed on the
# host. --output writes the .so as the invoking user, so nothing in target/ ends up
# root-owned. The container's target/ is a BuildKit cache mount, which also keeps it
# from sharing a fingerprint directory with any host cargo build.
build:
	DOCKER_BUILDKIT=1 docker build --platform linux/amd64 \
		-f Dockerfile.build --target artifacts \
		--output type=local,dest=target/deploy .

# The suite needs the program built with --features testing, which selects a separate
# program ID, so it goes to its own output directory and does not clobber the
# deployable artifact in target/deploy.
build-testing:
	DOCKER_BUILDKIT=1 docker build --platform linux/amd64 \
		--build-arg FEATURES=testing \
		-f Dockerfile.build --target artifacts \
		--output type=local,dest=target/deploy-testing .

# Runs the TypeScript suite against a containerized validator. No Anchor CLI, no avm,
# and no Solana toolchain on the host.
test: build-testing
	yarn turbo run build
	./scripts/run-tests.sh

anchor-image:
	docker build -f Dockerfile.anchor -t $(IMAGE_ANCHOR) .

# Converts the checked-in 0.29-spec IDL, which solita works from, into the 0.30 spec
# the on-chain IDL account needs. Derived like the .so, so it lands in target/ rather
# than being committed. The address comes from the source IDL's metadata.address, so
# this needs no program ID of its own.
IDL_0_30 := target/squads_multisig_program.0.30.json

idl: anchor-image
	mkdir -p target
	$(ANCHOR_RUN) anchor idl convert sdk/multisig/idl/squads_multisig_program.json -o $(IDL_0_30)

# Writes the IDL account on chain. Requires the program to be deployed already and the
# upgrade authority to be the wallet in ~/.config/solana.
idl-init: require-wallet idl
	$(ANCHOR_RUN_SIGNED) anchor idl init $(PROGRAM_ID) \
		--filepath $(IDL_0_30) \
		--provider.cluster $(RPC) \
		--provider.wallet /wallet.json

# Replaces the contents of an existing IDL account, after a redeploy.
idl-upgrade: require-wallet idl
	$(ANCHOR_RUN_SIGNED) anchor idl upgrade $(PROGRAM_ID) \
		--filepath $(IDL_0_30) \
		--provider.cluster $(RPC) \
		--provider.wallet /wallet.json

# Removes what the builds export. The BuildKit cache mounts are what make a rebuild
# fast, so they are left alone here and cleared separately by clean-docker.
clean:
	rm -rf target/deploy target/deploy-testing

# BuildKit has no project-level filter for cache mounts, so this scopes to ours by
# matching the program name that appears in the RUN command each mount is recorded
# against. A different Dockerfile whose build command also contains that text would
# match too, but that is the narrowest filter BuildKit's cache mount type supports.
clean-docker:
	docker builder prune -f --filter type=exec.cachemount --filter 'description~=squads_multisig'
