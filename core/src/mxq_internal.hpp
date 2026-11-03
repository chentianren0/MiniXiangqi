/*
 * Internal helpers shared by the core's translation units. Nothing here is
 * visible through mxq.h.
 */

#ifndef MXQ_INTERNAL_HPP
#define MXQ_INTERNAL_HPP

#include "mxq.h"

#include <cstddef>
#include <cstdint>

namespace mxq {

/* Fill an optional MxqError, honouring the size the caller compiled against.
 * Safe with err == nullptr. */
void fill_error(MxqError *err, MxqStatus status, const char *detail);

/* As fill_error, additionally setting required_size. */
void fill_error_required(MxqError *err, MxqStatus status, const char *detail,
                         uint64_t required);

/* As fill_error, additionally setting detail_index. */
void fill_error_index(MxqError *err, MxqStatus status, const char *detail,
                      uint64_t index);

/* Prepare a caller-supplied out struct: reject NULL and a struct_size this
 * build cannot interpret, and zero what this build knows about. */
MxqStatus begin_out(void *out, uint32_t declared, uint32_t known,
                    uint32_t min_known, MxqError *err);

/* Validate a caller-supplied in struct the same way, without zeroing. */
MxqStatus check_in(const void *in, uint32_t declared, uint32_t known,
                   uint32_t min_known, MxqError *err);

/* A game outside the vocabulary is a caller error: it asserts in a debug build
 * and is MXQ_ERR_ARG_RANGE in a release one. */
MxqStatus require_game(MxqGameKind game, MxqError *err);

/* Copy a NUL-terminated string into a fixed-capacity field. A source that does
 * not fit is a core bug and asserts in a debug build. */
void copy_bounded(char *dst, size_t cap, const char *src);

/* Write a NUL-terminated string to a caller buffer: *out_len is always the
 * length without the NUL, and a cap below length + 1 is
 * MXQ_ERR_ARG_BUFFER_TOO_SMALL with required_size set. */
MxqStatus write_string(const char *value, char *out, size_t cap,
                       size_t *out_len, MxqError *err);

/* percent(x, p) == x * p / 100, exact and without overflow for p in 0..100. */
uint64_t percent(uint64_t value, uint32_t p);

/* The Hash plan mxq.h describes, for the probe in budget. */
MxqStatus engine_plan(const MxqEngineBudget *budget, MxqEnginePlan *out,
                      MxqError *err);

/*
 * The search-callback reentrancy guard: a callback that calls back in is
 * refused before it can deadlock the engine thread it runs on.
 */
bool in_search_callback();

/* Fill err and return MXQ_ERR_ARG_REENTRANT. */
MxqStatus refuse_reentrant(MxqError *err);

/* Marks this thread as inside a search callback for its own lifetime. */
class CallbackScope {
public:
    CallbackScope();
    ~CallbackScope();
    CallbackScope(const CallbackScope &) = delete;
    CallbackScope &operator=(const CallbackScope &) = delete;
};

} /* namespace mxq */

#endif /* MXQ_INTERNAL_HPP */
