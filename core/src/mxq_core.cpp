/* Core lifecycle. */

#include "mxq_build_config.h"
#include "mxq_core_state.hpp"
#include "mxq_internal.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_engine_bridge.hpp"
#include "mxq_session.hpp"
#endif

#include <cassert>
#include <memory>
#include <mutex>

namespace mxq {
namespace {
std::mutex g_lifecycle_mutex;
std::unique_ptr<MxqCore> g_core;
} /* namespace */

MxqCore *live_core() {
    return g_core.get();
}

MxqStatus require_core(const MxqCore *core, MxqError *err) {
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

MxqStatus MXQ_CALL mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core,
                                 MxqError *err) {
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

    /* Only the major version gates: within one major there are no removals or
     * signature changes, so an older or newer minor is compatible by contract. */
    if (config->api_major != MXQ_API_VERSION_MAJOR) {
        assert(false && "caller's API major version does not match");
        mxq::fill_error(err, MXQ_ERR_ARG_API_VERSION,
                        "the caller's MXQ_API_VERSION major does not match this core");
        return MXQ_ERR_ARG_API_VERSION;
    }

    std::lock_guard<std::mutex> lock(mxq::g_lifecycle_mutex);
    if (mxq::g_core) {
        assert(false && "a second mxq_core_init before shutdown");
        mxq::fill_error(err, MXQ_ERR_STATE_ALREADY_INITIALIZED,
                        "the core is already initialised");
        return MXQ_ERR_STATE_ALREADY_INITIALIZED;
    }

    auto core = std::make_unique<MxqCore>();
    core->store_directory = config->store_directory ? config->store_directory : "";
    core->asset_directory = config->asset_directory ? config->asset_directory : "";
    core->flags = config->flags;
    core->identity.reset((core->flags & MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY) != 0);

#if defined(MXQ_ENABLE_RULES_FACADE)
    /* The engine is prepared here rather than lazily, so that a packaging
     * failure — a missing or malformed variant configuration — surfaces at
     * initialisation instead of at the first rules query, where the caller has
     * no sensible recovery. */
    std::string detail;
    if (!mxq::engine::ensure_initialised(core->asset_directory.c_str(), detail)) {
        mxq::fill_error(err, MXQ_ERR_ENGINE_ASSET_MISSING, detail.c_str());
        return MXQ_ERR_ENGINE_ASSET_MISSING;
    }
#endif

    /* The store opens with the core and a store that cannot open or create
     * fails initialisation whole: a core without persistence would break every
     * promise the session surface makes, so there is no degraded mode. */
    const MxqStatus store_rc =
        mxq::store::open(core->store_directory, core->store, err);
    if (store_rc != MXQ_OK) {
        return store_rc;
    }

    mxq::g_core = std::move(core);
    *out_core = mxq::g_core.get();
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_core_shutdown(MxqCore *core, MxqError *err) {
    std::lock_guard<std::mutex> lock(mxq::g_lifecycle_mutex);
    if (core == nullptr || core != mxq::g_core.get()) {
        assert(false && "shutdown of a handle that is not the live instance");
        mxq::fill_error(err, MXQ_ERR_STATE_NOT_INITIALIZED,
                        "the core handle is not the live instance");
        return MXQ_ERR_STATE_NOT_INITIALIZED;
    }
    core->shutting_down = true;
#if defined(MXQ_ENABLE_RULES_FACADE)
    /* Invalidate outstanding handles before the store they are attached to
     * goes away. They are tombstoned rather than freed: their owners still
     * hold them and still release them, and until they do, every function on
     * one answers MXQ_ERR_ARG_INVALID_HANDLE instead of touching freed
     * memory. */
    mxq::session::invalidate_all(core);
#endif
    /* Close the store before the instance goes away, explicitly rather than
     * by member destruction order, because "shutdown closes the store" is a
     * contract clause and not an implementation accident. */
    core->store.reset();
    mxq::g_core.reset();
    return MXQ_OK;
}

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
