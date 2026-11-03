/*
 * The search facade's lifecycle, as mxq_core.cpp calls it. The facade's state
 * is process-global, like the engines it fronts.
 */

#ifndef MXQ_SEARCH_HPP
#define MXQ_SEARCH_HPP

#include "mxq.h"

struct MxqCore;

namespace mxq {
namespace search {

/* Spawn the engine thread and reset the facade for a fresh core. Called last
 * in mxq_core_init, so a failed initialisation never leaks a thread. */
void startup();

/* Cancel all work, drain it (cancelled callbacks still fire), join the engine
 * thread and release the engines. */
void shutdown();

/* Cancel every outstanding search and block until the engine thread is idle.
 * Callbacks still fire, cancelled. */
MxqStatus cancel_all_and_quiesce(MxqError *err);

} /* namespace search */
} /* namespace mxq */

#endif /* MXQ_SEARCH_HPP */
