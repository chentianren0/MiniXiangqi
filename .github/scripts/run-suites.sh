#!/usr/bin/env bash
#
# Configure, build and run the core suites, in whichever configurations the
# generator this platform uses needs a pass for.
#
#   $1  single-config | multi-config
#   $2  the build directory, relative to $RUNNER_TEMP
#   $3  multi-config only: the generator platform for -A. x64 by default.
#
# The macOS runner takes the first: its default generator is single-config, so
# each configuration is its own build tree and its own configure. The Windows
# runners take the second: CMake's default there is the newest installed Visual
# Studio, which is multi-config, so one configure serves both and the network is
# staged once. Naming no generator is deliberate — CMake locates the toolset
# itself, nothing hardcodes an edition path or an environment script, and no
# third-party action sets one up.
#
# The generator platform is a parameter rather than a constant because there are
# now two Windows runners, x64 and ARM64, and the Visual Studio generator does
# not follow the host: without -A it targets whatever the generator's own
# default is, which is not the same question as "what machine is this". Naming
# it makes each job's target architecture readable in the job rather than
# inferred from the runner label.
#
# Nothing is passed for the network. It is in the checkout, at the path
# pinned-inputs.json records, and core/CMakeLists.txt defaults to it — so every
# suite runs on every runner, including engine_search, and a run that excluded
# one is not a shape this file can produce any more.

set -euo pipefail

generator_kind="$1"
build_directory="${RUNNER_TEMP//\\//}/$2"
generator_platform="${3:-x64}"

configure_options=(-DMXQ_ENABLE_RULES_FACADE=ON)
test_options=(--output-on-failure)

case "${generator_kind}" in
single-config)
	for configuration in RelWithDebInfo Debug; do
		cmake -S core -B "${build_directory}-${configuration}" \
			-DCMAKE_BUILD_TYPE="${configuration}" \
			"${configure_options[@]}"
		cmake --build "${build_directory}-${configuration}" --parallel
		ctest --test-dir "${build_directory}-${configuration}" \
			"${test_options[@]}"
	done
	;;
multi-config)
	cmake -S core -B "${build_directory}" -A "${generator_platform}" \
		"${configure_options[@]}"
	grep -E '^CMAKE_(CXX_COMPILER|GENERATOR|GENERATOR_PLATFORM|SYSTEM_PROCESSOR):' \
		"${build_directory}/CMakeCache.txt"
	for configuration in RelWithDebInfo Debug; do
		cmake --build "${build_directory}" --config "${configuration}"
		ctest --test-dir "${build_directory}" -C "${configuration}" \
			"${test_options[@]}"
	done
	;;
*)
	echo "unknown generator kind: ${generator_kind}" >&2
	exit 2
	;;
esac
