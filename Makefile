# CI passes the GitHub Actions cache backend through this. Empty locally, where the
# daemon's own cache already persists between builds.
DOCKER_BUILD_FLAGS ?=

.PHONY: build clean-docker

# The program builds inside Docker so no Solana or Anchor toolchain is needed on the
# host. --output writes the .so as the invoking user, so nothing in target/ ends up
# root-owned. The container's target/ is a BuildKit cache mount, which also keeps it
# from sharing a fingerprint directory with any host cargo build.
build:
	DOCKER_BUILDKIT=1 docker build --platform linux/amd64 $(DOCKER_BUILD_FLAGS) \
		-f Dockerfile.build --target artifacts \
		--output type=local,dest=target/deploy .

# BuildKit has no project-level filter for cache mounts, so this scopes to ours by
# matching the program name that appears in the RUN command each mount is recorded
# against. A different Dockerfile whose build command also contains that text would
# match too, but that is the narrowest filter BuildKit's cache mount type supports.
clean-docker:
	docker builder prune -f --filter type=exec.cachemount --filter 'description~=squads_multisig'
