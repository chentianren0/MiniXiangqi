/*
 * Internal helpers shared by the core's translation units.
 *
 * Nothing here is visible through mxq.h. The public boundary is C; the
 * implementation behind it is C++, per docs/architecture.md.
 */

#ifndef MXQ_INTERNAL_HPP
#define MXQ_INTERNAL_HPP

#include "mxq.h"

#include <cstddef>
#include <cstdint>

/* The versions this build implements, on the axes MxqVersion reports. They are
 * deliberately not public macros: the contract exposes them through
 * mxq_core_version and mxq_archive_supported_versions so that a caller reads
 * the running core's values rather than the ones it compiled against. */
#define MXQ_ARCHIVE_VERSION_CURRENT      1u
#define MXQ_ARCHIVE_VERSION_MIN_READABLE 1u
#define MXQ_STORE_SCHEMA_VERSION         1u

/* The frozen starting position, per docs/xiangqi-rules.md. */
#define MXQ_START_FEN "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

/*
 * An immutable byte buffer owned by the core. Only the codec and the store
 * produce these; the accessors below are the whole public surface.
 */
struct MxqBlob {
    uint8_t *data;
    size_t   len;
};

namespace mxq {

/* Fill an optional MxqError, honouring the capacity the caller compiled
 * against. Safe with err == nullptr. */
void fill_error(MxqError *err, MxqStatus status, const char *detail);

/* As fill_error, additionally setting required_size. */
void fill_error_required(MxqError *err, MxqStatus status, const char *detail,
                         uint64_t required);

/* As fill_error, additionally setting detail_index — which is the field
 * MXQ_ERR_RULES_INVALID_HISTORY documents as carrying the first illegal move's
 * index. required_size means the size a call needs and is a different field. */
void fill_error_index(MxqError *err, MxqStatus status, const char *detail,
                      uint64_t index);

/* As fill_error, additionally setting subsystem_code — the raw subsystem
 * result (a SQLite result code, for the store) that MxqError carries for
 * diagnostics only and that is never branched on. */
void fill_error_subsystem(MxqError *err, MxqStatus status, const char *detail,
                          int32_t subsystem_code);

/*
 * Prepare a caller-supplied out struct: reject NULL, reject a struct_size this
 * build cannot interpret, and zero the part this build knows about so that
 * every field the caller can read is written exactly once.
 *
 * known is sizeof the struct as this build declares it; the caller's declared
 * size may be smaller (an older frontend) or larger (a newer one), and either
 * is accepted as long as it covers the version-1 prefix.
 */
MxqStatus begin_out(void *out, uint32_t declared, uint32_t known,
                    uint32_t min_known, MxqError *err);

/* Validate a caller-supplied in struct the same way, without zeroing. */
MxqStatus check_in(const void *in, uint32_t declared, uint32_t known,
                   uint32_t min_known, MxqError *err);

/* Copy a NUL-terminated string into a fixed-capacity field, truncating never:
 * a source that does not fit is a core bug and trips an assertion in debug
 * builds. */
void copy_bounded(char *dst, size_t cap, const char *src);

/* Write a NUL-terminated string to a caller buffer under the routine
 * buffer-too-small rule: *out_len is always the length excluding the NUL, and a
 * cap below length + 1 returns MXQ_ERR_ARG_BUFFER_TOO_SMALL with required_size
 * set to length + 1. */
MxqStatus write_string(const char *value, char *out, size_t cap,
                       size_t *out_len, MxqError *err);

/* percent(x, p) == x * p / 100, computed exactly and without overflow for any
 * uint64_t x and any p in 0..100. */
uint64_t percent(uint64_t value, uint32_t p);

} /* namespace mxq */

#endif /* MXQ_INTERNAL_HPP */
