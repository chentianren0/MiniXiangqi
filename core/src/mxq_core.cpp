/* Core lifecycle. */

#include "mxq_core_state.hpp"
#include "mxq_internal.hpp"

#include "mxq_engine_bridge.hpp"
#include "mxq_search.hpp"


#include <cassert>
#include <memory>
#include <mutex>

namespace mxq {
namespace {
std::mutex g_lifecycle_mutex;
std::unique_ptr<MxqCore> g_core;
} /* namespace */

MxqStatus require_core(const MxqCore *core, MxqError *err) {
    /* Before anything else, so a callback never blocks the engine thread it
     * is running on. */
    if (in_search_callback()) {
        return refuse_reentrant(err);
    }
    if (core == nullptr) {
        assert(false && "required core handle was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "required core handle was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (core != g_core.get()) {
        assert(false && "core handle is not the live instance");
        fill_error(err, MXQ_ERR_STATE_NOT_INITIALIZED,
                   "the core handle is not the live instance");
        return MXQ_ERR_STATE_NOT_INITIALIZED;
    }
    if (core->shutting_down) {
        fill_error(err, MXQ_ERR_STATE_SHUTTING_DOWN, "the core is shutting down");
        return MXQ_ERR_STATE_SHUTTING_DOWN;
    }
    return MXQ_OK;
}

} /* namespace mxq */

extern "C" {

MxqStatus mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core,
                                 MxqError *err) {
    if (mxq::in_search_callback()) {
        return mxq::refuse_reentrant(err);
    }
    const MxqStatus rc = mxq::check_in(
        config, config != nullptr ? config->struct_size : 0u,
        static_cast<uint32_t>(sizeof(MxqCoreConfig)),
        static_cast<uint32_t>(sizeof(MxqCoreConfig)), err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (out_core == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    *out_core = nullptr;

    std::lock_guard<std::mutex> lock(mxq::g_lifecycle_mutex);
    if (mxq::g_core) {
        assert(false && "a second mxq_core_init before shutdown");
        mxq::fill_error(err, MXQ_ERR_STATE_ALREADY_INITIALIZED,
                        "the core is already initialised");
        return MXQ_ERR_STATE_ALREADY_INITIALIZED;
    }

    auto core = std::make_unique<MxqCore>();
    core->asset_directory = config->asset_directory ? config->asset_directory : "";

    /* The engine is prepared here rather than lazily, so that a packaging
     * failure — a missing or malformed variant configuration — surfaces at
     * initialisation instead of at the first rules query, where the caller has
     * no sensible recovery. A configuration that is not there and one that is
     * there but does not yield the pinned variant are different packaging
     * failures and carry their own codes. */
    std::string detail;
    switch (mxq::engine::ensure_initialised(core->asset_directory.c_str(),
                                            detail)) {
    case mxq::engine::InitError::None:
        break;
    case mxq::engine::InitError::AssetMissing:
        mxq::fill_error(err, MXQ_ERR_ENGINE_ASSET_MISSING, detail.c_str());
        return MXQ_ERR_ENGINE_ASSET_MISSING;
    case mxq::engine::InitError::VariantLoadFailed:
        mxq::fill_error(err, MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED,
                        detail.c_str());
        return MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED;
    }

    /* The engine thread, last: everything above can fail, and a failed
     * initialisation must not leak a thread. */
    mxq::search::startup();

    mxq::g_core = std::move(core);
    *out_core = mxq::g_core.get();
    return MXQ_OK;
}

MxqStatus mxq_core_shutdown(MxqCore *core, MxqError *err) {
    if (mxq::in_search_callback()) {
        return mxq::refuse_reentrant(err);
    }
    std::lock_guard<std::mutex> lock(mxq::g_lifecycle_mutex);
    if (core == nullptr || core != mxq::g_core.get()) {
        assert(false && "shutdown of a handle that is not the live instance");
        mxq::fill_error(err, MXQ_ERR_STATE_NOT_INITIALIZED,
                        "the core handle is not the live instance");
        return MXQ_ERR_STATE_NOT_INITIALIZED;
    }
    core->shutting_down = true;
    /* Outstanding searches deliver their callbacks, cancelled, before the
     * engine thread joins. */
    mxq::search::shutdown();
    mxq::g_core.reset();
    return MXQ_OK;
}

MxqStatus mxq_core_cancel_all(MxqCore *core, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    return mxq::search::cancel_all_and_quiesce(err);
}

} /* extern "C" */
