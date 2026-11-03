/* The core instance behind MxqCore. One per process, because the engines'
 * state is process-global. */

#ifndef MXQ_CORE_STATE_HPP
#define MXQ_CORE_STATE_HPP

#include "mxq.h"

#include <string>

struct MxqCore {
    std::string asset_directory;
    bool        shutting_down = false;
};

namespace mxq {

/* Refuse a handle that is not the live instance, and every call from inside a
 * search callback. */
MxqStatus require_core(const MxqCore *core, MxqError *err);

} /* namespace mxq */

#endif /* MXQ_CORE_STATE_HPP */
