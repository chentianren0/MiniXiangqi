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

#include <string>

struct MxqCore {
    std::string store_directory;
    std::string asset_directory;
    uint32_t    flags = 0;
    bool        shutting_down = false;
};

namespace mxq {

/* The live instance, or nullptr. Used to reject a second init and to reject a
 * handle that is not the one this core issued — a stale handle from before a
 * shutdown is a programming error, not a runtime one. */
MxqCore *live_core();
MxqStatus require_core(const MxqCore *core, MxqError *err);

} /* namespace mxq */

#endif /* MXQ_CORE_STATE_HPP */
