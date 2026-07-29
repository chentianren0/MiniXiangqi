/* The core's own JSON reader. See mxq_archive_json.hpp for what it does and
 * does not enforce, and why. */

#include "mxq_archive_json.hpp"

#include <cstdio>
#include <string>

namespace mxq {
namespace json {

const Value *Value::member(const char *name) const {
    if (type_ != Type::Object || name == nullptr) {
        return nullptr;
    }
    for (size_t i = 0; i < member_names_.size(); ++i) {
        if (member_names_[i] == name) {
            return &member_values_[i];
        }
    }
    return nullptr;
}

const char *Value::type_name(Type t) {
    switch (t) {
    case Type::Bool: return "a boolean";
    case Type::Integer: return "an integer";
    case Type::String: return "a string";
    case Type::Array: return "an array";
    case Type::Object: return "an object";
    }
    return "a value";
}

namespace {

std::string at(size_t offset) {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), " at byte %llu",
                  static_cast<unsigned long long>(offset));
    return std::string(buffer);
}

/*
 * Strict UTF-8 validation over the whole input, before a byte is parsed.
 *
 * Strict means the definition that leaves no second spelling of a character:
 * shortest form only, no surrogate code points, nothing above U+10FFFF, and no
 * truncated sequence at the end. An overlong encoding is the classic way a
 * validator and a consumer disagree about the same bytes, and this is untrusted
 * input.
 */
bool valid_utf8(const uint8_t *bytes, size_t len, size_t &bad_offset) {
    size_t i = 0;
    while (i < len) {
        const uint8_t b = bytes[i];
        size_t extra = 0;
        uint32_t cp = 0;
        if (b < 0x80u) {
            i += 1;
            continue;
        } else if ((b & 0xE0u) == 0xC0u) {
            extra = 1;
            cp = b & 0x1Fu;
        } else if ((b & 0xF0u) == 0xE0u) {
            extra = 2;
            cp = b & 0x0Fu;
        } else if ((b & 0xF8u) == 0xF0u) {
            extra = 3;
            cp = b & 0x07u;
        } else {
            bad_offset = i;
            return false;
        }
        if (i + extra >= len) {
            /* A sequence the input ends in the middle of. */
            bad_offset = i;
            return false;
        }
        for (size_t k = 1; k <= extra; ++k) {
            const uint8_t c = bytes[i + k];
            if ((c & 0xC0u) != 0x80u) {
                bad_offset = i + k;
                return false;
            }
            cp = (cp << 6) | (c & 0x3Fu);
        }
        const bool overlong = (extra == 1 && cp < 0x80u) ||
                              (extra == 2 && cp < 0x800u) ||
                              (extra == 3 && cp < 0x10000u);
        const bool surrogate = cp >= 0xD800u && cp <= 0xDFFFu;
        if (overlong || surrogate || cp > 0x10FFFFu) {
            bad_offset = i;
            return false;
        }
        i += extra + 1;
    }
    return true;
}

void append_utf8(std::string &out, uint32_t cp) {
    if (cp < 0x80u) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800u) {
        out.push_back(static_cast<char>(0xC0u | (cp >> 6)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    } else if (cp < 0x10000u) {
        out.push_back(static_cast<char>(0xE0u | (cp >> 12)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    } else {
        out.push_back(static_cast<char>(0xF0u | (cp >> 18)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 12) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    }
}

} /* namespace */

/*
 * Recursive descent. The recursion is bounded by Limits::max_depth, which is
 * checked before descending, so the stack cost of a hostile file is bounded by
 * the contract rather than by the file.
 */
class Parser {
public:
    Parser(const uint8_t *bytes, size_t len, const Limits &limits, Error &err)
        : bytes_(bytes), len_(len), limits_(limits), err_(err) {}

    bool run(Value &out) {
        skip_whitespace();
        if (!parse_value(out, 1)) {
            return false;
        }
        skip_whitespace();
        if (pos_ != len_) {
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "trailing content after the JSON document" + at(pos_));
        }
        return true;
    }

private:
    bool fail(MxqStatus status, const std::string &detail) {
        err_.status = status;
        err_.detail = detail;
        return false;
    }

    bool at_end() const { return pos_ >= len_; }
    uint8_t peek() const { return bytes_[pos_]; }

    void skip_whitespace() {
        while (pos_ < len_) {
            const uint8_t c = bytes_[pos_];
            if (c == 0x20u || c == 0x09u || c == 0x0Au || c == 0x0Du) {
                ++pos_;
            } else {
                break;
            }
        }
    }

    bool literal(const char *text) {
        const size_t n = std::string(text).size();
        if (pos_ + n > len_) {
            return false;
        }
        for (size_t i = 0; i < n; ++i) {
            if (bytes_[pos_ + i] != static_cast<uint8_t>(text[i])) {
                return false;
            }
        }
        pos_ += n;
        return true;
    }

    bool parse_value(Value &out, size_t depth) {
        if (at_end()) {
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "a value was expected but the document ended");
        }
        const uint8_t c = peek();
        switch (c) {
        case '{':
            return parse_object(out, depth);
        case '[':
            return parse_array(out, depth);
        case '"': {
            std::string s;
            if (!parse_string(s)) {
                return false;
            }
            out.type_ = Value::Type::String;
            out.string_ = std::move(s);
            return true;
        }
        case 't':
            if (literal("true")) {
                out.type_ = Value::Type::Bool;
                out.boolean_ = true;
                return true;
            }
            break;
        case 'f':
            if (literal("false")) {
                out.type_ = Value::Type::Bool;
                out.boolean_ = false;
                return true;
            }
            break;
        case 'n': {
            const size_t start = pos_;
            if (literal("null")) {
                /* Its own rejection class: the archive never writes null, it
                 * omits the member, so a null is a document this core must not
                 * guess the meaning of. */
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "null is forbidden in an archive" + at(start));
            }
            break;
        }
        default:
            break;
        }
        if (c == '-' || (c >= '0' && c <= '9')) {
            return parse_number(out);
        }
        return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                    "not a JSON value" + at(pos_));
    }

    bool parse_object(Value &out, size_t depth) {
        if (depth > limits_.max_depth) {
            return fail(MXQ_ERR_ARCHIVE_TOO_LARGE,
                        "JSON nesting is deeper than the import limit" +
                            at(pos_));
        }
        out.type_ = Value::Type::Object;
        ++pos_; /* '{' */
        skip_whitespace();
        if (!at_end() && peek() == '}') {
            ++pos_;
            return true;
        }
        for (;;) {
            skip_whitespace();
            if (at_end() || peek() != '"') {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "a member name was expected" + at(pos_));
            }
            const size_t name_at = pos_;
            std::string name;
            if (!parse_string(name)) {
                return false;
            }
            for (const std::string &existing : out.member_names_) {
                if (existing == name) {
                    return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                                "duplicate member \"" + name + "\"" +
                                    at(name_at));
                }
            }
            if (out.member_names_.size() + 1 > limits_.max_members) {
                return fail(MXQ_ERR_ARCHIVE_TOO_LARGE,
                            "an object has more members than the import limit" +
                                at(name_at));
            }
            skip_whitespace();
            if (at_end() || peek() != ':') {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "\":\" was expected after a member name" + at(pos_));
            }
            ++pos_;
            skip_whitespace();
            Value value;
            if (!parse_value(value, depth + 1)) {
                return false;
            }
            out.member_names_.push_back(std::move(name));
            out.member_values_.push_back(std::move(value));

            skip_whitespace();
            if (at_end()) {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "the document ended inside an object");
            }
            if (peek() == ',') {
                ++pos_;
                continue;
            }
            if (peek() == '}') {
                ++pos_;
                return true;
            }
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "\",\" or \"}\" was expected" + at(pos_));
        }
    }

    bool parse_array(Value &out, size_t depth) {
        if (depth > limits_.max_depth) {
            return fail(MXQ_ERR_ARCHIVE_TOO_LARGE,
                        "JSON nesting is deeper than the import limit" +
                            at(pos_));
        }
        out.type_ = Value::Type::Array;
        ++pos_; /* '[' */
        skip_whitespace();
        if (!at_end() && peek() == ']') {
            ++pos_;
            return true;
        }
        for (;;) {
            skip_whitespace();
            if (out.elements_.size() + 1 > limits_.max_array_elements) {
                return fail(MXQ_ERR_ARCHIVE_TOO_LARGE,
                            "an array has more elements than the import limit" +
                                at(pos_));
            }
            Value element;
            if (!parse_value(element, depth + 1)) {
                return false;
            }
            out.elements_.push_back(std::move(element));

            skip_whitespace();
            if (at_end()) {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "the document ended inside an array");
            }
            if (peek() == ',') {
                ++pos_;
                continue;
            }
            if (peek() == ']') {
                ++pos_;
                return true;
            }
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "\",\" or \"]\" was expected" + at(pos_));
        }
    }

    bool parse_string(std::string &out) {
        const size_t start = pos_;
        ++pos_; /* the opening quote */
        out.clear();
        for (;;) {
            if (at_end()) {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "the document ended inside a string" + at(start));
            }
            const uint8_t c = bytes_[pos_];
            if (c == '"') {
                ++pos_;
                break;
            }
            if (c < 0x20u) {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "an unescaped control character in a string" +
                                at(pos_));
            }
            if (c != '\\') {
                out.push_back(static_cast<char>(c));
                ++pos_;
            } else {
                ++pos_;
                if (at_end()) {
                    return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                                "the document ended inside an escape" +
                                    at(start));
                }
                const uint8_t e = bytes_[pos_++];
                switch (e) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    uint32_t cp = 0;
                    if (!parse_hex4(cp)) {
                        return false;
                    }
                    if (cp >= 0xD800u && cp <= 0xDBFFu) {
                        /* A high surrogate must be followed by its low half;
                         * a lone half has no character to stand for. */
                        if (pos_ + 1 >= len_ || bytes_[pos_] != '\\' ||
                            bytes_[pos_ + 1] != 'u') {
                            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                                        "an unpaired surrogate escape" +
                                            at(pos_));
                        }
                        pos_ += 2;
                        uint32_t low = 0;
                        if (!parse_hex4(low)) {
                            return false;
                        }
                        if (low < 0xDC00u || low > 0xDFFFu) {
                            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                                        "an unpaired surrogate escape" +
                                            at(pos_));
                        }
                        cp = 0x10000u + ((cp - 0xD800u) << 10) + (low - 0xDC00u);
                    } else if (cp >= 0xDC00u && cp <= 0xDFFFu) {
                        return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                                    "an unpaired surrogate escape" + at(pos_));
                    }
                    append_utf8(out, cp);
                    break;
                }
                default:
                    return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                                "an unrecognised string escape" + at(pos_ - 1));
                }
            }
            if (out.size() > limits_.max_string_bytes) {
                return fail(MXQ_ERR_ARCHIVE_TOO_LARGE,
                            "a string is longer than the import limit" +
                                at(start));
            }
        }
        if (out.size() > limits_.max_string_bytes) {
            return fail(MXQ_ERR_ARCHIVE_TOO_LARGE,
                        "a string is longer than the import limit" + at(start));
        }
        return true;
    }

    bool parse_hex4(uint32_t &out) {
        if (pos_ + 4 > len_) {
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "a truncated \\u escape" + at(pos_));
        }
        out = 0;
        for (int i = 0; i < 4; ++i) {
            const uint8_t c = bytes_[pos_++];
            uint32_t digit = 0;
            if (c >= '0' && c <= '9') {
                digit = static_cast<uint32_t>(c - '0');
            } else if (c >= 'a' && c <= 'f') {
                digit = static_cast<uint32_t>(c - 'a') + 10u;
            } else if (c >= 'A' && c <= 'F') {
                digit = static_cast<uint32_t>(c - 'A') + 10u;
            } else {
                return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                            "a malformed \\u escape" + at(pos_ - 1));
            }
            out = (out << 4) | digit;
        }
        return true;
    }

    bool parse_number(Value &out) {
        const size_t start = pos_;
        bool negative = false;
        if (peek() == '-') {
            negative = true;
            ++pos_;
        }
        if (at_end() || peek() < '0' || peek() > '9') {
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "a malformed number" + at(start));
        }
        /* RFC 8259 forbids a leading zero, and so does the canonical form: an
         * integer has exactly one spelling. */
        if (peek() == '0' && pos_ + 1 < len_ && bytes_[pos_ + 1] >= '0' &&
            bytes_[pos_ + 1] <= '9') {
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "a number with a leading zero" + at(start));
        }

        uint64_t magnitude = 0;
        bool overflow = false;
        while (!at_end() && peek() >= '0' && peek() <= '9') {
            const uint64_t digit = static_cast<uint64_t>(peek() - '0');
            if (magnitude > (UINT64_C(0x7FFFFFFFFFFFFFFF) - digit) / 10u) {
                overflow = true;
            } else {
                magnitude = magnitude * 10u + digit;
            }
            ++pos_;
        }
        if (!at_end() && (peek() == '.' || peek() == 'e' || peek() == 'E')) {
            /* Its own rejection class. The archive serialises integers only, so
             * a fractional or exponential number is a document written against
             * a different contract, never a value to round. */
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "a number that is not an integer" + at(start));
        }
        if (overflow) {
            return fail(MXQ_ERR_ARCHIVE_MALFORMED,
                        "an integer outside the representable range" +
                            at(start));
        }
        out.type_ = Value::Type::Integer;
        out.integer_ = negative ? -static_cast<int64_t>(magnitude)
                                : static_cast<int64_t>(magnitude);
        return true;
    }

    const uint8_t *bytes_;
    size_t         len_;
    size_t         pos_ = 0;
    const Limits  &limits_;
    Error         &err_;
};

bool parse(const uint8_t *bytes, size_t len, const Limits &limits, Value &out,
           Error &err) {
    err.status = MXQ_ERR_ARCHIVE_MALFORMED;
    err.detail.clear();

    if (bytes == nullptr || len == 0) {
        err.detail = "the archive is empty";
        return false;
    }
    size_t bad = 0;
    if (!valid_utf8(bytes, len, bad)) {
        err.detail = "not valid UTF-8" + at(bad);
        return false;
    }
    Parser parser(bytes, len, limits, err);
    return parser.run(out);
}

} /* namespace json */
} /* namespace mxq */
