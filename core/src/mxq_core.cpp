/* Core lifecycle. */

#include "mxq_build_config.h"
#include "mxq_core_state.hpp"
#include "mxq_internal.hpp"
#include "mxq_notation.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_engine_bridge.hpp"
#include "mxq_search.hpp"
#include "mxq_session.hpp"
#endif

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
#include "mxq_rapfi_bridge.hpp"
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
    /* Before anything else: inside a search callback the only legal calls
     * are the status and blob helpers and the four pure queries that take no
     * core instance, so everything passing this gate refuses there — before
     * it could block the engine thread it is running on. */
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

MxqStatus MXQ_CALL mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core,
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
#endif

    /* The store opens with the core and a store that cannot open or create
     * fails initialisation whole: a core without persistence would break every
     * promise the session surface makes, so there is no degraded mode. */
    const MxqStatus store_rc =
        mxq::store::open(core->store_directory, core->store, err);
    if (store_rc != MXQ_OK) {
        return store_rc;
    }

#if defined(MXQ_ENABLE_RULES_FACADE)
    /* The engine thread, last: everything above can fail, and a failed
     * initialisation must not leak a thread. */
    mxq::search::startup();
#endif

    mxq::g_core = std::move(core);
    *out_core = mxq::g_core.get();
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_core_shutdown(MxqCore *core, MxqError *err) {
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
#if defined(MXQ_ENABLE_RULES_FACADE)
    /* The contract's order: cancel all work, join the engine thread, then the
     * store. Outstanding searches deliver their callbacks with the cancelled
     * outcome before the join; the retained result does not survive. */
    mxq::search::shutdown();
    /* Invalidate outstanding handles before the store they are attached to
     * goes away — and after the engine thread joined, because delivery reads
     * the registry. They are tombstoned rather than freed: their owners still
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

MxqStatus MXQ_CALL mxq_core_cancel_all(MxqCore *core, MxqError *err) {
    const MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
#if defined(MXQ_ENABLE_RULES_FACADE)
    /* The backgrounding and memory-pressure path: cancel cooperatively and
     * block until the engine quiesces. Callbacks still fire, with the
     * cancelled outcome, before this returns. The committed game is never
     * affected — search output never commits. */
    return mxq::search::cancel_all_and_quiesce(err);
#else
    /* Without the engine no search can be outstanding, so the state this call
     * asks for already holds. */
    return MXQ_OK;
#endif
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

    /* The build revisions. These are load-bearing rather than diagnostics: a
     * test report or a saved diagnostic must be able to name the build that
     * produced it. They come from the repository's pinned-input manifest, which
     * the build reads — never from a value written twice. What a game binds is
     * mxq_core_game_profile's, because there are two of those and one of
     * these. */
    mxq::copy_bounded(out->core_revision, sizeof(out->core_revision),
                      MXQ_BUILD_CORE_REVISION);
    mxq::copy_bounded(out->fork_revision, sizeof(out->fork_revision),
                      MXQ_BUILD_FORK_REVISION);

    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_core_game_profile(MxqGameKind game, MxqGameProfile *out,
                                         MxqError *err) {
    MxqStatus rc = mxq::require_game(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    /* What this reports is what one game binds for a search: a pinned variant
     * and that variant's network. A game bound to no searched variant has
     * neither, so there is nothing for the struct to carry and the entry
     * answers for it exactly as preparation does. */
    if (!mxq::notation::searched(game)) {
        assert(false && "no engine searches this game");
        mxq::fill_error(err, MXQ_ERR_ARG_RANGE,
                        "no engine searches this game, so it binds no variant "
                        "and no network");
        return MXQ_ERR_ARG_RANGE;
    }
    rc = mxq::begin_out(out, out != nullptr ? out->struct_size : 0u,
                        static_cast<uint32_t>(sizeof(MxqGameProfile)),
                        static_cast<uint32_t>(sizeof(MxqGameProfile)), err);
    if (rc != MXQ_OK) {
        return rc;
    }

    out->game = game;

#if defined(MXQ_ENABLE_GOMOKU_FACADE)
    /* The placement games' pins live in the second bridge, and they are asked of
     * it for the reason the first bridge is asked below: the bridge is what
     * pairs a game with the weights it verifies, and a report assembled beside
     * it could name a pairing the bridge would refuse. Renju pins a network per
     * side and this field carries one, so it carries the pair's — see
     * MxqGameProfile. */
    if (mxq::notation::move_class_of(game) ==
        mxq::notation::MoveClass::Placement) {
        const mxq::rapfi::Rules rules = mxq::rapfi::rules_of(game);
        mxq::copy_bounded(out->variant_id, sizeof(out->variant_id),
                          mxq::rapfi::rules_variant_id(rules));
        mxq::copy_bounded(out->nnue_sha256, sizeof(out->nnue_sha256),
                          mxq::rapfi::rules_nnue_sha256(rules));
        return MXQ_OK;
    }
#endif

#if defined(MXQ_ENABLE_RULES_FACADE)
    /* Read from the bridge's own pinned rows rather than from the build
     * configuration a second time: the bridge is what pairs a variant with the
     * network it verifies, and a report assembled beside it could name a
     * pairing the bridge would refuse. */
    const mxq::engine::Variant variant = mxq::engine::variant_of(game);
    mxq::copy_bounded(out->variant_id, sizeof(out->variant_id),
                      mxq::engine::variant_id(variant));
    mxq::copy_bounded(out->nnue_sha256, sizeof(out->nnue_sha256),
                      mxq::engine::variant_nnue_sha256(variant));
#else
    /* Without the engine there is no bridge to ask, and the pins are still
     * build facts this report owes: the manifest reaches them through the same
     * generated configuration the bridge reads. */
    mxq::copy_bounded(out->variant_id, sizeof(out->variant_id),
                      game == MXQ_GAME_KIND_XIANGQI
                          ? MXQ_BUILD_XIANGQI_VARIANT_ID
                          : MXQ_BUILD_VARIANT_ID);
    mxq::copy_bounded(out->nnue_sha256, sizeof(out->nnue_sha256),
                      game == MXQ_GAME_KIND_XIANGQI
                          ? MXQ_BUILD_XIANGQI_NNUE_SHA256
                          : MXQ_BUILD_NNUE_SHA256);
#endif
    return MXQ_OK;
}

} /* extern "C" */
