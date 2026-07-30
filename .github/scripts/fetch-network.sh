#!/usr/bin/env bash
#
# Fetch the pinned NNUE network for a CI run, if this repository has been told
# where to find it.
#
# The network is never in version control, in any form
# (docs/engine-integration.md, "Accepted NNUE handling policy"), and this
# repository is public, so it is not attached to a release here either — that
# document makes establishing the network's origin and redistribution licence a
# mandatory gate for any distribution beyond internal testing, and that gate has
# not been passed. The MXQ_NNUE_URL repository secret is therefore the seam: it
# names a location, never the bytes and never a hash.
#
# Nothing here verifies the download, deliberately. core/CMakeLists.txt already
# checks the byte length and the SHA-256 against pinned-inputs.json and stages
# nothing that fails, which is the same check every developer build performs; a
# second copy of it here would be a second place for the manifest's values to be
# restated, which docs/architecture.md's input rule exists to prevent.
#
# Outputs, on $GITHUB_OUTPUT:
#   path     the downloaded network, or empty
#   exclude  a ctest --exclude-regex for the suite that cannot run, or empty

set -euo pipefail

# RUNNER_TEMP is a native Windows path on the Windows runner, and a backslash is
# an escape almost everywhere it would then travel. Forward slashes are accepted
# by bash, by cmake.exe and by ctest.exe alike, so the path is normalised once
# here and stays normalised. On macOS the substitution matches nothing.
temporary_directory="${RUNNER_TEMP//\\//}"

if [ -z "${MXQ_NNUE_URL:-}" ]; then
	printf 'path=\n' >>"${GITHUB_OUTPUT}"
	printf 'exclude=^engine_search$\n' >>"${GITHUB_OUTPUT}"
	{
		printf '### The engine_search suite did not run on %s\n\n' "${RUNNER_OS}"
		printf 'No `MXQ_NNUE_URL` repository secret is set, so no NNUE network\n'
		printf 'reached this runner and the search facade has nothing to load.\n'
		printf 'Every other suite ran: the engine was compiled and linked, and\n'
		printf 'the rules facade answered every fixture.\n'
	} >>"${GITHUB_STEP_SUMMARY}"
	echo "no MXQ_NNUE_URL secret: the engine_search suite will be excluded"
	exit 0
fi

destination="${temporary_directory}/nnue/network.nnue"
mkdir -p "${temporary_directory}/nnue"
curl --fail --silent --show-error --location \
	--output "${destination}" "${MXQ_NNUE_URL}"

printf 'path=%s\n' "${destination}" >>"${GITHUB_OUTPUT}"
printf 'exclude=\n' >>"${GITHUB_OUTPUT}"
echo "fetched $(wc -c <"${destination}") bytes; the build verifies them against pinned-inputs.json"
