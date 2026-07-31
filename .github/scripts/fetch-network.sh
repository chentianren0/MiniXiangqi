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
# not been passed. The bytes therefore reach a runner from somewhere this
# repository names but does not contain. Two secrets are the seam, and neither
# of them is the bytes and neither of them is a hash:
#
#   MXQ_NNUE_DEPLOY_KEY  The private half of a read-only deploy key for
#                        github.com/ppppvz/minixiangqi-assets, a private
#                        repository holding exactly one network file at the root
#                        of its main branch. This is how the network actually
#                        reaches CI. The *key* is the secret; the repository's
#                        address is not, and it is written here rather than
#                        passed in, because docs/architecture.md forbids CI
#                        taking undocumented inputs.
#   MXQ_NNUE_URL         A location to download from, for bytes kept somewhere
#                        that is not that repository. The generic alternative,
#                        and unset today.
#
# If both are set the URL wins. A deploy key is the standing arrangement,
# configured once and left alone; a URL set alongside it is somebody pointing
# this run at something else on purpose, and the deliberate act should be the
# one that takes effect.
#
# Nothing here verifies what it fetched, deliberately. core/CMakeLists.txt
# already checks the byte length and the SHA-256 against pinned-inputs.json and
# stages nothing that fails, which is the same check every developer build
# performs; a second copy of it here would be a second place for the manifest's
# values to be restated, which docs/architecture.md's input rule exists to
# prevent.
#
# The key does not reach the log. Nothing echoes it, no shell tracing is turned
# on anywhere in this script, the file it is written to is created private
# rather than made private afterwards, and it is removed on every exit path
# including a failed clone.
#
# Both runners execute this under bash — git-bash on Windows — so everything
# here is POSIX-shell portable and every path is written with forward slashes.
#
# Outputs, on $GITHUB_OUTPUT:
#   path     the fetched network, or empty
#   exclude  a ctest --exclude-regex for the suite that cannot run, or empty

set -euo pipefail

# RUNNER_TEMP is a native Windows path on the Windows runner, and a backslash is
# an escape almost everywhere it would then travel. Forward slashes are accepted
# by bash, by git, by ssh, by cmake.exe and by ctest.exe alike, so the path is
# normalised once here and stays normalised. On macOS the substitution matches
# nothing.
temporary_directory="${RUNNER_TEMP//\\//}"

if [ -z "${MXQ_NNUE_URL:-}" ] && [ -z "${MXQ_NNUE_DEPLOY_KEY:-}" ]; then
	printf 'path=\n' >>"${GITHUB_OUTPUT}"
	printf 'exclude=^engine_search$\n' >>"${GITHUB_OUTPUT}"
	{
		printf '### The engine_search suite did not run on %s\n\n' "${RUNNER_OS}"
		printf 'Neither the `MXQ_NNUE_DEPLOY_KEY` nor the `MXQ_NNUE_URL`\n'
		printf 'repository secret is set, so no NNUE network reached this\n'
		printf 'runner and the search facade has nothing to load. Every other\n'
		printf 'suite ran: the engine was compiled and linked, and the rules\n'
		printf 'facade answered every fixture.\n'
	} >>"${GITHUB_STEP_SUMMARY}"
	echo "no network secret is set: the engine_search suite will be excluded"
	exit 0
fi

if [ -n "${MXQ_NNUE_URL:-}" ]; then
	network="${temporary_directory}/nnue/network.nnue"
	mkdir -p "${temporary_directory}/nnue"
	curl --fail --silent --show-error --location \
		--output "${network}" "${MXQ_NNUE_URL}"
else
	# ssh reads an identity from a file and from nowhere else, so the key
	# becomes a file. The subshell's umask makes it private at creation —
	# not private a moment later, which is a moment during which it is
	# readable — and the trap is armed before the key is written, so no
	# path out of here leaves it behind.
	key_file="${temporary_directory}/nnue-deploy-key"
	clone_directory="${temporary_directory}/nnue-assets"
	trap 'rm -f "${key_file}"' EXIT
	(umask 077 && printf '%s\n' "${MXQ_NNUE_DEPLOY_KEY}" >"${key_file}")
	rm -rf "${clone_directory}"

	# IdentitiesOnly stops ssh offering any other identity the runner
	# happens to carry, accept-new takes github.com's host key on first
	# sight without the prompt an unattended job cannot answer, and
	# BatchMode turns every remaining prompt into a failure rather than a
	# job that hangs until the six-hour timeout.
	GIT_SSH_COMMAND="ssh -i '${key_file}' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
		git clone --depth 1 --branch main \
		git@github.com:ppppvz/minixiangqi-assets.git "${clone_directory}"
	rm -f "${key_file}"

	# The assets repository holds one network and a README. Which network is
	# its business and not this script's — the name is not pinned here, the
	# bytes are pinned in pinned-inputs.json and checked by the build — but
	# "exactly one" is, because picking one of several silently is how the
	# wrong bytes would get as far as a hash mismatch nobody expected.
	networks=("${clone_directory}"/*.nnue)
	if [ "${#networks[@]}" -ne 1 ] || [ ! -f "${networks[0]}" ]; then
		echo "expected exactly one *.nnue at the root of ppppvz/minixiangqi-assets" >&2
		exit 1
	fi
	network="${networks[0]}"
fi

printf 'path=%s\n' "${network}" >>"${GITHUB_OUTPUT}"
printf 'exclude=\n' >>"${GITHUB_OUTPUT}"
echo "fetched $(wc -c <"${network}") bytes; the build verifies them against pinned-inputs.json"
