/* The Hash plan, a pure function of the probe: mxq_engine_prepare applies
 * it. */

#include "mxq_internal.hpp"

namespace {

constexpr uint64_t kBytesPerMiB = 1024ull * 1024ull;

} /* namespace */

namespace mxq {

MxqStatus engine_plan(const MxqEngineBudget *budget, MxqEnginePlan *out,
                      MxqError *err) {
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

    uint64_t reserve = mxq::percent(budget->available_bytes,
                                    MXQ_ENGINE_RESERVE_PERCENT);
    if (reserve < MXQ_ENGINE_MIN_RESERVE_BYTES) {
        reserve = MXQ_ENGINE_MIN_RESERVE_BYTES;
    }

    const uint64_t usable =
        budget->available_bytes > reserve ? budget->available_bytes - reserve : 0;

    uint64_t bytes = static_cast<uint64_t>(MXQ_ENGINE_MAX_HASH_MIB) * kBytesPerMiB;
    const uint64_t half_physical =
        mxq::percent(budget->physical_bytes, MXQ_ENGINE_PHYSICAL_PERCENT);
    if (half_physical < bytes) {
        bytes = half_physical;
    }
    if (usable < bytes) {
        bytes = usable;
    }

    /* UCI Hash is a whole count of MiB; rounding to whole GiB would discard
     * too much usable capacity. */
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

    /* Refusing an insufficient plan is mxq_engine_prepare's job. */
    return MXQ_OK;
}

} /* namespace mxq */
