/* The archive codec boundary. Only mxq_archive_supported_versions is
 * implemented at this stage: it is a pure report of compiled-in values and is
 * callable before mxq_core_init. */

#include "mxq_internal.hpp"

#include <cassert>

extern "C" {

MxqStatus MXQ_CALL mxq_archive_supported_versions(uint32_t *out_min_readable,
                                                  uint32_t *out_current,
                                                  MxqError *err) {
    if (out_min_readable == nullptr && out_current == nullptr) {
        assert(false && "both out parameters were null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL,
                        "both out parameters were null");
        return MXQ_ERR_ARG_NULL;
    }
    if (out_min_readable != nullptr) {
        *out_min_readable = MXQ_ARCHIVE_VERSION_MIN_READABLE;
    }
    if (out_current != nullptr) {
        *out_current = MXQ_ARCHIVE_VERSION_CURRENT;
    }
    return MXQ_OK;
}

} /* extern "C" */
