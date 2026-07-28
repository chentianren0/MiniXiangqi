/* Engine preparation.
 *
 * Only mxq_engine_plan is implemented at this stage. The contract makes it a
 * pure function of the frontend-supplied probe values precisely so that every
 * budget boundary in docs/testing.md is testable without an engine, so it needs
 * nothing that is not yet vendored. */

#include "mxq_internal.hpp"

namespace {

constexpr uint64_t kBytesPerMiB = 1024ull * 1024ull;

} /* namespace */

extern "C" {

MxqStatus MXQ_CALL mxq_engine_plan(const MxqEngineBudget *budget,
                                   MxqEnginePlan *out, MxqError *err) {
    MxqStatus rc = mxq::check_in(
        budget, budget != nullptr ? budget->struct_size : 0u,
        static_cast<uint32_t>(sizeof(MxqEngineBudget)),
        static_cast<uint32_t>(sizeof(MxqEngineBudget)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqEnginePlan)),
                        static_cast<uint32_t>(sizeof(MxqEnginePlan)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    /* Reserve the greater of MXQ_ENGINE_RESERVE_PERCENT of the fresh probe
     * value or MXQ_ENGINE_MIN_RESERVE_BYTES. */
    uint64_t reserve = mxq::percent(budget->available_bytes,
                                    MXQ_ENGINE_RESERVE_PERCENT);
    if (reserve < MXQ_ENGINE_MIN_RESERVE_BYTES) {
        reserve = MXQ_ENGINE_MIN_RESERVE_BYTES;
    }

    /* Usable available memory. */
    const uint64_t usable =
        budget->available_bytes > reserve ? budget->available_bytes - reserve : 0;

    /* The byte budget: the minimum of the cap, half the device's physical
     * memory, and the usable amount. */
    uint64_t bytes = static_cast<uint64_t>(MXQ_ENGINE_MAX_HASH_MIB) * kBytesPerMiB;
    const uint64_t half_physical =
        mxq::percent(budget->physical_bytes, MXQ_ENGINE_PHYSICAL_PERCENT);
    if (half_physical < bytes) {
        bytes = half_physical;
    }
    if (usable < bytes) {
        bytes = usable;
    }

    /* UCI Hash is an integer count of MiB; round down to the accepted
     * granularity rather than to whole GiB, which would discard too much
     * usable capacity. */
    const uint64_t mib =
        (bytes / kBytesPerMiB) / MXQ_ENGINE_HASH_GRANULARITY_MIB *
        MXQ_ENGINE_HASH_GRANULARITY_MIB;

    out->threads = budget->active_processor_count > 0
                       ? budget->active_processor_count
                       : 1u;
    out->hash_mib = static_cast<uint32_t>(mib);
    out->sufficient = mib >= MXQ_ENGINE_MIN_HASH_MIB ? 1u : 0u;
    out->reserve_bytes = reserve;
    out->usable_bytes = usable;
    out->budget_bytes = bytes;

    /* Below the minimum the plan reports insufficiency; refusing is
     * mxq_engine_prepare's job, and this function initialises nothing. */
    return MXQ_OK;
}

} /* extern "C" */
