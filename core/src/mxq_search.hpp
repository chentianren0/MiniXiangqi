/*
 * The search facade behind mxq_engine_prepare/teardown/query and the
 * mxq_search_ group: the core's one engine thread, its task queue, the ticket
 * and result store, and the delivery ladder. See mxq_search.cpp for the
 * design; this header is only what mxq_core.cpp's lifecycle needs to call.
 *
 * The facade's state is process-global, exactly as the engine bridge's is and
 * for the same reason: the embedded engine's process-global state admits one
 * instance, which is why MxqCore is singleton-enforced (core-interface.md).
 *
 * Compiled only when MXQ_ENABLE_RULES_FACADE is ON, like the bridge and the
 * sessions: a search facade without an engine cannot exist, so without one
 * the mxq_engine_ and mxq_search_ functions are absent from the library
 * rather than stubbed.
 */

#ifndef MXQ_SEARCH_HPP
#define MXQ_SEARCH_HPP

#include "mxq.h"

struct MxqCore;

namespace mxq {
namespace search {

/* Spawn the engine thread and reset the facade — tickets, retained result,
 * engine state — for a fresh core. Called by mxq_core_init after everything
 * that can fail has succeeded, so a failed initialisation never leaks a
 * thread. */
void startup();

/* The engine-thread half of mxq_core_shutdown, in the contract's order:
 * cancel all work, drain it — cancelled callbacks still fire — join the
 * engine thread, release the engine to the deconfigured posture, and drop the
 * retained result. The caller then invalidates sessions and closes the
 * store. */
void shutdown();

/* The body of mxq_core_cancel_all: cancel every outstanding search
 * cooperatively and block until the engine quiesces. Callbacks still fire,
 * with MXQ_SEARCH_CANCELLED. */
MxqStatus cancel_all_and_quiesce(MxqError *err);

} /* namespace search */
} /* namespace mxq */

#endif /* MXQ_SEARCH_HPP */
