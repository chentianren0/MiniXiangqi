#!/usr/bin/env bash
#
# Configure, build and run the core suites, in whichever configurations the
# generator this platform uses needs a pass for.
#
#   $1  single-config | multi-config
#   $2  the build directory, relative to $RUNNER_TEMP
#
# The macOS runner takes the first: its default generator is single-config, so
# each configuration is its own build tree and its own configure. The Windows
# runner takes the second: CMake's default there is the newest installed Visual
# Studio, which is multi-config, so one configure serves both and the network is
# staged once. Naming no generator is deliberate — CMake locates the toolset
# itself, nothing hardcodes an edition path or an environment script, and no
# third-party action sets one up.
#
# MXQ_NNUE_SOURCE and MXQ_CTEST_EXCLUDE come from the fetch-network step, and
# are both empty when no network reached the runner.

set -euo pipefail

generator_kind="$1"
build_directory="${RUNNER_TEMP//\\//}/$2"

configure_options=(-DMXQ_ENABLE_RULES_FACADE=ON)
if [ -n "${MXQ_NNUE_SOURCE:-}" ]; then
	configure_options+=("-DMXQ_NNUE_SOURCE=${MXQ_NNUE_SOURCE}")
fi

test_options=(--output-on-failure)
if [ -n "${MXQ_CTEST_EXCLUDE:-}" ]; then
	test_options+=(--exclude-regex "${MXQ_CTEST_EXCLUDE}")
fi

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
	cmake -S core -B "${build_directory}" -A x64 "${configure_options[@]}"
	grep -E '^CMAKE_(CXX_COMPILER|GENERATOR):' \
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
