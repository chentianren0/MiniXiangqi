/*
 * The core's own JSON reader, sized to the game archive.
 *
 * The archive is one canonical-JSON document (docs/game-data.md), so the codec
 * needs a reader; it must be the core's own, because the core depends on no
 * third party for a correctness-critical path and cannot depend on the test
 * runner's reader either — core/tests/mxq_json.* is fixture-side code, and a
 * core validated by fixtures its own parser had read would be validating
 * itself.
 *
 * It is deliberately not a general JSON library. It reads exactly what an
 * archive may contain, under exactly the import limits game-data.md fixes, and
 * it enforces on the read path exactly what that document's rejection taxonomy
 * places there:
 *
 *   - strict UTF-8, checked over the whole input before anything is parsed;
 *   - JSON syntax per RFC 8259, with no extensions — no comments, no trailing
 *     commas, no unquoted names, no NaN or Infinity;
 *   - `null` rejected wherever it appears: the archive has no absent-value
 *     encoding, it omits the member instead;
 *   - numbers must be integers — a fraction or an exponent is a rejection, not
 *     a rounding — and must fit int64_t;
 *   - duplicate member names rejected;
 *   - the structural limits: nesting depth, members per object, string bytes,
 *     and array elements.
 *
 * What it deliberately does NOT enforce is the rest of the canonical form —
 * members in codepoint order, one line, no insignificant whitespace. Those
 * describe what the core writes and what content hashing consumes, and the
 * accepted validation order re-establishes them by canonicalising after
 * validation and before hashing. Rejecting an incoming file over the spelling
 * of a document it agrees with byte-for-byte once canonicalised is not
 * something any clause asks for.
 *
 * Every rejection carries the archive-domain status the taxonomy gives it, so
 * the codec above never translates a parser's private error code into contract
 * vocabulary.
 */

#ifndef MXQ_ARCHIVE_JSON_HPP
#define MXQ_ARCHIVE_JSON_HPP

#include "mxq.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mxq {
namespace json {

/* The accepted import limits of docs/game-data.md, as the reader applies them.
 * They are parameters rather than constants so that each limit is stated once,
 * at the codec, and the reader holds no opinion of its own about the archive. */
struct Limits {
    size_t max_depth;           /* container nesting; the document object is 1 */
    size_t max_members;         /* members in one object */
    size_t max_string_bytes;    /* decoded bytes of one string, names included */
    size_t max_array_elements;  /* elements in one array */
};

/* Why a document was rejected: the contract status, and a short diagnostic
 * naming the offending byte offset. */
struct Error {
    MxqStatus   status;
    std::string detail;
};

/*
 * One parsed value. There is no Null: a document containing `null` anywhere is
 * rejected before a value could be built for it.
 *
 * Object members are held in two parallel vectors in document order, because
 * the codec reports them in that order — an unknown-member rejection names the
 * first offending member, and naming it as the file spells it makes the
 * diagnostic reproducible. An object holds at most max_members entries, so
 * lookup is a linear scan and no index is worth its complexity.
 */
class Value {
public:
    enum class Type { Bool, Integer, String, Array, Object };

    Type type() const { return type_; }
    bool is_bool() const { return type_ == Type::Bool; }
    bool is_integer() const { return type_ == Type::Integer; }
    bool is_string() const { return type_ == Type::String; }
    bool is_array() const { return type_ == Type::Array; }
    bool is_object() const { return type_ == Type::Object; }

    bool boolean() const { return boolean_; }
    int64_t integer() const { return integer_; }
    const std::string &string() const { return string_; }

    const std::vector<Value> &elements() const { return elements_; }

    size_t member_count() const { return member_names_.size(); }
    const std::string &member_name(size_t i) const { return member_names_[i]; }
    const Value &member_value(size_t i) const { return member_values_[i]; }

    /* The member with this name, or nullptr when absent or when this is not an
     * object. */
    const Value *member(const char *name) const;
    bool has_member(const char *name) const { return member(name) != nullptr; }

    static const char *type_name(Type t);

private:
    friend class Parser;

    Type                     type_ = Type::Object;
    bool                     boolean_ = false;
    int64_t                  integer_ = 0;
    std::string              string_;
    std::vector<Value>       elements_;    /* Type::Array */
    std::vector<std::string> member_names_;/* Type::Object, document order */
    std::vector<Value>       member_values_;
};

/*
 * Parse one complete JSON document. Returns false with err filled on every
 * rejection; err.status is always an archive-domain status.
 */
bool parse(const uint8_t *bytes, size_t len, const Limits &limits, Value &out,
           Error &err);

} /* namespace json */
} /* namespace mxq */

#endif /* MXQ_ARCHIVE_JSON_HPP */
