/* The core instance behind MxqCore.
 *
 * MxqCore is singleton-enforced because the embedded engine's state is
 * process-global (core-interface.md). The handle exists so teardown stays
 * explicit and the signatures stay stable if that constraint ever lifts, so
 * this holds what a second instance would need rather than assuming there can
 * only ever be one. */

#ifndef MXQ_CORE_STATE_HPP
#define MXQ_CORE_STATE_HPP

#include "mxq.h"

#include "mxq_identity.hpp"
#include "mxq_store.hpp"

#include <memory>
#include <string>

struct MxqCore {
    std::string store_directory;
    std::string asset_directory;
    uint32_t    flags = 0;
    bool        shutting_down = false;

    /* The library store, opened by mxq_core_init and closed at shutdown. Never
     * null on a live core: a store that cannot open fails initialisation. */
    std::unique_ptr<mxq::store::Store> store;

    /* The core's one clock and identity provider, configured from
     * MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY at initialisation. */
    mxq::identity::Provider identity;
};

namespace mxq {

/* The live instance, or nullptr. Used to reject a second init and to reject a
 * handle that is not the one this core issued — a stale handle from before a
 * shutdown is a programming error, not a runtime one. */
MxqCore *live_core();
MxqStatus require_core(const MxqCore *core, MxqError *err);

} /* namespace mxq */

#endif /* MXQ_CORE_STATE_HPP */
