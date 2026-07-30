#include "mxq_internal.hpp"

#include <cassert>
#include <cstring>

namespace mxq {

namespace {

/* The version-1 prefix every value struct must at least carry. */
constexpr uint32_t kStructSizeField = static_cast<uint32_t>(sizeof(uint32_t));

} /* namespace */

namespace {

/* required, index and subsystem go to their own fields; a caller that wants
 * none passes zero for each, which is what an unset field reads as. */
void fill(MxqError *err, MxqStatus status, const char *detail,
          uint64_t required, uint64_t index, int32_t subsystem);

} /* namespace */

void fill_error(MxqError *err, MxqStatus status, const char *detail) {
    fill(err, status, detail, 0, 0, 0);
}

void fill_error_required(MxqError *err, MxqStatus status, const char *detail,
                         uint64_t required) {
    fill(err, status, detail, required, 0, 0);
}

void fill_error_index(MxqError *err, MxqStatus status, const char *detail,
                      uint64_t index) {
    fill(err, status, detail, 0, index, 0);
}

void fill_error_subsystem(MxqError *err, MxqStatus status, const char *detail,
                          int32_t subsystem_code) {
    fill(err, status, detail, 0, 0, subsystem_code);
}

namespace {

void fill(MxqError *err, MxqStatus status, const char *detail,
          uint64_t required, uint64_t index, int32_t subsystem) {
    if (err == nullptr) {
        return;
    }
    const uint32_t declared = err->struct_size;
    if (declared < kStructSizeField) {
        /* The caller did not set struct_size. There is nothing safe to write
         * beyond leaving it alone; the returned status is the contract. */
        return;
    }
    const uint32_t known = static_cast<uint32_t>(sizeof(MxqError));
    const uint32_t writable = declared < known ? declared : known;
    std::memset(err, 0, writable);
    err->struct_size = writable;

    /* Every field below is written only when the caller's declared size covers
     * it, so an older frontend's smaller struct is never overrun. */
    if (writable >= offsetof(MxqError, status) + sizeof(err->status)) {
        err->status = status;
    }
    if (writable >= offsetof(MxqError, subsystem_code) + sizeof(err->subsystem_code)) {
        err->subsystem_code = subsystem;
    }
    if (writable >= offsetof(MxqError, required_size) + sizeof(err->required_size)) {
        err->required_size = required;
    }
    if (writable >= offsetof(MxqError, detail_index) + sizeof(err->detail_index)) {
        err->detail_index = index;
    }
    if (detail != nullptr &&
        writable >= offsetof(MxqError, detail) + 1u) {
        const size_t cap = writable - offsetof(MxqError, detail);
        const size_t n = std::strlen(detail);
        const size_t copied = n < cap - 1 ? n : cap - 1;
        std::memcpy(err->detail, detail, copied);
        err->detail[copied] = '\0';
    }
}

} /* namespace */

MxqStatus begin_out(void *out, uint32_t declared, uint32_t known,
                    uint32_t min_known, MxqError *err) {
    if (out == nullptr) {
        assert(false && "required out pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (declared < min_known) {
        assert(false && "struct_size is smaller than this interface version");
        fill_error(err, MXQ_ERR_ARG_STRUCT_SIZE,
                   "struct_size is smaller than this interface version");
        return MXQ_ERR_ARG_STRUCT_SIZE;
    }
    const uint32_t writable = declared < known ? declared : known;
    std::memset(out, 0, writable);
    *static_cast<uint32_t *>(out) = writable;
    return MXQ_OK;
}

MxqStatus check_in(const void *in, uint32_t declared, uint32_t known,
                   uint32_t min_known, MxqError *err) {
    (void)known;
    if (in == nullptr) {
        assert(false && "required in pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "required in pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    if (declared < min_known) {
        assert(false && "struct_size is smaller than this interface version");
        fill_error(err, MXQ_ERR_ARG_STRUCT_SIZE,
                   "struct_size is smaller than this interface version");
        return MXQ_ERR_ARG_STRUCT_SIZE;
    }
    return MXQ_OK;
}

void copy_bounded(char *dst, size_t cap, const char *src) {
    assert(dst != nullptr && cap > 0);
    if (src == nullptr) {
        dst[0] = '\0';
        return;
    }
    const size_t n = std::strlen(src);
    assert(n < cap && "core value does not fit its fixed-capacity field");
    const size_t copied = n < cap - 1 ? n : cap - 1;
    std::memcpy(dst, src, copied);
    dst[copied] = '\0';
}

MxqStatus write_string(const char *value, char *out, size_t cap,
                       size_t *out_len, MxqError *err) {
    assert(value != nullptr);
    const size_t n = std::strlen(value);
    if (out_len != nullptr) {
        *out_len = n;
    }
    if (out == nullptr || cap < n + 1) {
        fill_error_required(err, MXQ_ERR_ARG_BUFFER_TOO_SMALL,
                            "output buffer is smaller than the value",
                            static_cast<uint64_t>(n) + 1u);
        return MXQ_ERR_ARG_BUFFER_TOO_SMALL;
    }
    std::memcpy(out, value, n + 1);
    return MXQ_OK;
}

uint64_t percent(uint64_t value, uint32_t p) {
    assert(p <= 100);
    const uint64_t pp = static_cast<uint64_t>(p);
    return (value / 100u) * pp + ((value % 100u) * pp) / 100u;
}

namespace {

/* Thread-local, because only the engine thread is ever inside a callback and
 * every other thread must keep answering normally while one runs. */
thread_local bool tls_in_search_callback = false;

} /* namespace */

bool in_search_callback() {
    return tls_in_search_callback;
}

MxqStatus refuse_reentrant(MxqError *err) {
    fill_error(err, MXQ_ERR_ARG_REENTRANT,
               "called from inside a search callback, where only the status "
               "and blob helpers and the four pure queries are legal");
    return MXQ_ERR_ARG_REENTRANT;
}

CallbackScope::CallbackScope() {
    tls_in_search_callback = true;
}

CallbackScope::~CallbackScope() {
    tls_in_search_callback = false;
}

} /* namespace mxq */
