/* Core lifecycle. Only mxq_core_version is implemented at this stage: it is a
 * pure report of compiled-in values and is callable before mxq_core_init. */

#include "mxq_build_config.h"
#include "mxq_internal.hpp"

extern "C" {

MxqStatus MXQ_CALL mxq_core_version(MxqVersion *out, MxqError *err) {
    const MxqStatus rc = mxq::begin_out(
        out, out != nullptr ? out->struct_size : 0u,
        static_cast<uint32_t>(sizeof(MxqVersion)),
        static_cast<uint32_t>(sizeof(MxqVersion)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    out->api_major = MXQ_API_VERSION_MAJOR;
    out->api_minor = MXQ_API_VERSION_MINOR;
    out->api_patch = MXQ_API_VERSION_PATCH;

    out->archive_version_current = MXQ_ARCHIVE_VERSION_CURRENT;
    out->archive_version_min_readable = MXQ_ARCHIVE_VERSION_MIN_READABLE;
    out->store_schema_version = MXQ_STORE_SCHEMA_VERSION;

    /* The engine profile. These are load-bearing rather than diagnostics: a
     * test report or a saved diagnostic must be able to name the build that
     * produced it. They come from the repository's pinned-input manifest, which
     * the build reads — never from a value written twice. */
    mxq::copy_bounded(out->core_revision, sizeof(out->core_revision),
                      MXQ_BUILD_CORE_REVISION);
    mxq::copy_bounded(out->fork_revision, sizeof(out->fork_revision),
                      MXQ_BUILD_FORK_REVISION);
    mxq::copy_bounded(out->variant_id, sizeof(out->variant_id),
                      MXQ_BUILD_VARIANT_ID);
    mxq::copy_bounded(out->nnue_sha256, sizeof(out->nnue_sha256),
                      MXQ_BUILD_NNUE_SHA256);

    return MXQ_OK;
}

} /* extern "C" */
