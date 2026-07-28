#include "mxq_json.hpp"

#include <cmath>
#include <cstdlib>
#include <utility>

namespace mxqtest {

const JsonValue *JsonValue::member(std::string_view name) const {
    if (type_ != Type::Object) {
        return nullptr;
    }
    const auto it = object_.find(std::string(name));
    return it == object_.end() ? nullptr : &it->second;
}

JsonValue JsonValue::make_null() { return JsonValue(); }

JsonValue JsonValue::make_bool(bool v) {
    JsonValue j;
    j.type_ = Type::Bool;
    j.boolean_ = v;
    return j;
}

JsonValue JsonValue::make_number(double v) {
    JsonValue j;
    j.type_ = Type::Number;
    j.number_ = v;
    return j;
}

JsonValue JsonValue::make_string(std::string v) {
    JsonValue j;
    j.type_ = Type::String;
    j.string_ = std::move(v);
    return j;
}

JsonValue JsonValue::make_array(JsonArray v) {
    JsonValue j;
    j.type_ = Type::Array;
    j.array_ = std::move(v);
    return j;
}

JsonValue JsonValue::make_object(JsonObject v) {
    JsonValue j;
    j.type_ = Type::Object;
    j.object_ = std::move(v);
    return j;
}

const char *JsonValue::type_name(Type t) {
    switch (t) {
    case Type::Null: return "null";
    case Type::Bool: return "boolean";
    case Type::Number: return "number";
    case Type::String: return "string";
    case Type::Array: return "array";
    case Type::Object: return "object";
    }
    return "unknown";
}

namespace {

class Parser {
public:
    Parser(std::string_view text) : text_(text) {}

    bool parse(JsonValue &out, std::string &error) {
        skip_ws();
        if (!parse_value(out, 0)) {
            error = error_;
            return false;
        }
        skip_ws();
        if (pos_ != text_.size()) {
            error = at("trailing content after the document");
            return false;
        }
        return true;
    }

private:
    static constexpr int kMaxDepth = 64;

    std::string_view text_;
    size_t pos_ = 0;
    std::string error_;

    std::string at(const std::string &what) const {
        return "byte " + std::to_string(pos_) + ": " + what;
    }

    bool fail(const std::string &what) {
        if (error_.empty()) {
            error_ = at(what);
        }
        return false;
    }

    void skip_ws() {
        while (pos_ < text_.size()) {
            const char c = text_[pos_];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                ++pos_;
            } else {
                break;
            }
        }
    }

    bool literal(std::string_view word) {
        if (text_.substr(pos_, word.size()) != word) {
            return false;
        }
        pos_ += word.size();
        return true;
    }

    bool parse_value(JsonValue &out, int depth) {
        if (depth > kMaxDepth) {
            return fail("nesting is deeper than the reader allows");
        }
        if (pos_ >= text_.size()) {
            return fail("unexpected end of document");
        }
        switch (text_[pos_]) {
        case '{': return parse_object(out, depth);
        case '[': return parse_array(out, depth);
        case '"': {
            std::string s;
            if (!parse_string(s)) {
                return false;
            }
            out = JsonValue::make_string(std::move(s));
            return true;
        }
        case 't':
            if (!literal("true")) {
                return fail("expected true");
            }
            out = JsonValue::make_bool(true);
            return true;
        case 'f':
            if (!literal("false")) {
                return fail("expected false");
            }
            out = JsonValue::make_bool(false);
            return true;
        case 'n':
            if (!literal("null")) {
                return fail("expected null");
            }
            out = JsonValue::make_null();
            return true;
        default: return parse_number(out);
        }
    }

    bool parse_object(JsonValue &out, int depth) {
        ++pos_; /* '{' */
        JsonObject members;
        skip_ws();
        if (pos_ < text_.size() && text_[pos_] == '}') {
            ++pos_;
            out = JsonValue::make_object(std::move(members));
            return true;
        }
        for (;;) {
            skip_ws();
            if (pos_ >= text_.size() || text_[pos_] != '"') {
                return fail("expected a member name");
            }
            std::string key;
            if (!parse_string(key)) {
                return false;
            }
            skip_ws();
            if (pos_ >= text_.size() || text_[pos_] != ':') {
                return fail("expected ':' after a member name");
            }
            ++pos_;
            skip_ws();
            JsonValue value;
            if (!parse_value(value, depth + 1)) {
                return false;
            }
            if (!members.emplace(key, std::move(value)).second) {
                return fail("duplicate member name \"" + key + "\"");
            }
            skip_ws();
            if (pos_ < text_.size() && text_[pos_] == ',') {
                ++pos_;
                continue;
            }
            if (pos_ < text_.size() && text_[pos_] == '}') {
                ++pos_;
                out = JsonValue::make_object(std::move(members));
                return true;
            }
            return fail("expected ',' or '}'");
        }
    }

    bool parse_array(JsonValue &out, int depth) {
        ++pos_; /* '[' */
        JsonArray items;
        skip_ws();
        if (pos_ < text_.size() && text_[pos_] == ']') {
            ++pos_;
            out = JsonValue::make_array(std::move(items));
            return true;
        }
        for (;;) {
            skip_ws();
            JsonValue value;
            if (!parse_value(value, depth + 1)) {
                return false;
            }
            items.push_back(std::move(value));
            skip_ws();
            if (pos_ < text_.size() && text_[pos_] == ',') {
                ++pos_;
                continue;
            }
            if (pos_ < text_.size() && text_[pos_] == ']') {
                ++pos_;
                out = JsonValue::make_array(std::move(items));
                return true;
            }
            return fail("expected ',' or ']'");
        }
    }

    static void append_utf8(std::string &s, uint32_t cp) {
        if (cp < 0x80u) {
            s.push_back(static_cast<char>(cp));
        } else if (cp < 0x800u) {
            s.push_back(static_cast<char>(0xC0u | (cp >> 6)));
            s.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
        } else if (cp < 0x10000u) {
            s.push_back(static_cast<char>(0xE0u | (cp >> 12)));
            s.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
            s.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
        } else {
            s.push_back(static_cast<char>(0xF0u | (cp >> 18)));
            s.push_back(static_cast<char>(0x80u | ((cp >> 12) & 0x3Fu)));
            s.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
            s.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
        }
    }

    bool parse_hex4(uint32_t &out) {
        if (pos_ + 4 > text_.size()) {
            return fail("truncated \\u escape");
        }
        uint32_t v = 0;
        for (int i = 0; i < 4; ++i) {
            const char c = text_[pos_ + static_cast<size_t>(i)];
            v <<= 4;
            if (c >= '0' && c <= '9') {
                v |= static_cast<uint32_t>(c - '0');
            } else if (c >= 'a' && c <= 'f') {
                v |= static_cast<uint32_t>(c - 'a' + 10);
            } else if (c >= 'A' && c <= 'F') {
                v |= static_cast<uint32_t>(c - 'A' + 10);
            } else {
                return fail("invalid hexadecimal in a \\u escape");
            }
        }
        pos_ += 4;
        out = v;
        return true;
    }

    bool parse_string(std::string &out) {
        ++pos_; /* opening quote */
        out.clear();
        for (;;) {
            if (pos_ >= text_.size()) {
                return fail("unterminated string");
            }
            const unsigned char c = static_cast<unsigned char>(text_[pos_]);
            if (c == '"') {
                ++pos_;
                return true;
            }
            if (c < 0x20u) {
                return fail("unescaped control character in a string");
            }
            if (c != '\\') {
                out.push_back(static_cast<char>(c));
                ++pos_;
                continue;
            }
            ++pos_;
            if (pos_ >= text_.size()) {
                return fail("unterminated escape");
            }
            const char e = text_[pos_++];
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
                    if (pos_ + 1 < text_.size() && text_[pos_] == '\\' &&
                        text_[pos_ + 1] == 'u') {
                        pos_ += 2;
                        uint32_t low = 0;
                        if (!parse_hex4(low)) {
                            return false;
                        }
                        if (low < 0xDC00u || low > 0xDFFFu) {
                            return fail("invalid low surrogate");
                        }
                        cp = 0x10000u + ((cp - 0xD800u) << 10) + (low - 0xDC00u);
                    } else {
                        return fail("unpaired high surrogate");
                    }
                } else if (cp >= 0xDC00u && cp <= 0xDFFFu) {
                    return fail("unpaired low surrogate");
                }
                append_utf8(out, cp);
                break;
            }
            default: return fail("unknown escape");
            }
        }
    }

    bool parse_number(JsonValue &out) {
        const size_t start = pos_;
        if (pos_ < text_.size() && text_[pos_] == '-') {
            ++pos_;
        }
        if (pos_ >= text_.size() ||
            !(text_[pos_] >= '0' && text_[pos_] <= '9')) {
            return fail("expected a value");
        }
        while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') {
            ++pos_;
        }
        if (pos_ < text_.size() && text_[pos_] == '.') {
            ++pos_;
            if (pos_ >= text_.size() ||
                !(text_[pos_] >= '0' && text_[pos_] <= '9')) {
                return fail("expected a digit after '.'");
            }
            while (pos_ < text_.size() && text_[pos_] >= '0' &&
                   text_[pos_] <= '9') {
                ++pos_;
            }
        }
        if (pos_ < text_.size() && (text_[pos_] == 'e' || text_[pos_] == 'E')) {
            ++pos_;
            if (pos_ < text_.size() && (text_[pos_] == '+' || text_[pos_] == '-')) {
                ++pos_;
            }
            if (pos_ >= text_.size() ||
                !(text_[pos_] >= '0' && text_[pos_] <= '9')) {
                return fail("expected a digit in the exponent");
            }
            while (pos_ < text_.size() && text_[pos_] >= '0' &&
                   text_[pos_] <= '9') {
                ++pos_;
            }
        }
        const std::string literal_text(text_.substr(start, pos_ - start));
        out = JsonValue::make_number(std::strtod(literal_text.c_str(), nullptr));
        return true;
    }
};

} /* namespace */

bool json_parse(std::string_view text, JsonValue &out, std::string &error) {
    /* Tolerate a UTF-8 byte order mark, which some editors add. */
    if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
        static_cast<unsigned char>(text[1]) == 0xBB &&
        static_cast<unsigned char>(text[2]) == 0xBF) {
        text.remove_prefix(3);
    }
    Parser parser(text);
    return parser.parse(out, error);
}

} /* namespace mxqtest */
