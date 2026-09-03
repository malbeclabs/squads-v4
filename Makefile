.PHONY: build build-testing test clean clean-docker

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
