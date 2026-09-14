#!/usr/bin/env bash
#
# Configure, build and run the core suites, in both configurations.
#
#   $1  the build directory, relative to $RUNNER_TEMP
#
# The runner's default generator is single-config, so each configuration is
# its own build tree and its own configure. Naming no generator is deliberate —
# CMake locates the toolset itself, nothing hardcodes a path or an environment
# script, and no third-party action sets one up.
#
# Nothing is passed for the network. It is in the checkout, at the path
# pinned-inputs.json records, and core/CMakeLists.txt defaults to it — so every
# suite runs, including engine_search, and a run that excluded one is not a
# shape this file can produce.

set -euo pipefail

build_directory="${RUNNER_TEMP}/$1"

for configuration in RelWithDebInfo Debug; do
	cmake -S core -B "${build_directory}-${configuration}" \
		-DCMAKE_BUILD_TYPE="${configuration}" \
		-DMXQ_ENABLE_RULES_FACADE=ON
	cmake --build "${build_directory}-${configuration}" --parallel
	ctest --test-dir "${build_directory}-${configuration}" --output-on-failure
done
