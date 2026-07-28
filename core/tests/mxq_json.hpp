/*
 * A minimal, dependency-free JSON reader for the fixture runner.
 *
 * The runner must build on every development platform with nothing fetched, so
 * it carries its own reader rather than a third-party one. This is a reader
 * only: it is not the archive codec, which is core code with its own canonical
 * form and its own limits, and it must never be mistaken for it.
 */

#ifndef MXQ_TESTS_JSON_HPP
#define MXQ_TESTS_JSON_HPP

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace mxqtest {

class JsonValue;

using JsonArray = std::vector<JsonValue>;
using JsonObject = std::map<std::string, JsonValue>;

class JsonValue {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    JsonValue() = default;

    Type type() const { return type_; }

    bool is_null() const { return type_ == Type::Null; }
    bool is_bool() const { return type_ == Type::Bool; }
    bool is_number() const { return type_ == Type::Number; }
    bool is_string() const { return type_ == Type::String; }
    bool is_array() const { return type_ == Type::Array; }
    bool is_object() const { return type_ == Type::Object; }

    bool boolean() const { return boolean_; }
    double number() const { return number_; }
    const std::string &string() const { return string_; }
    const JsonArray &array() const { return array_; }
    const JsonObject &object() const { return object_; }

    /* Returns nullptr when this is not an object or the member is absent. */
    const JsonValue *member(std::string_view name) const;

    static JsonValue make_null();
    static JsonValue make_bool(bool v);
    static JsonValue make_number(double v);
    static JsonValue make_string(std::string v);
    static JsonValue make_array(JsonArray v);
    static JsonValue make_object(JsonObject v);

    static const char *type_name(Type t);

private:
    Type type_ = Type::Null;
    bool boolean_ = false;
    double number_ = 0.0;
    std::string string_;
    JsonArray array_;
    JsonObject object_;
};

/*
 * Parse a complete JSON document. On failure returns false and sets `error` to
 * a message naming the byte offset. Duplicate member names are rejected, which
 * a fixture must never contain.
 */
bool json_parse(std::string_view text, JsonValue &out, std::string &error);

} /* namespace mxqtest */

#endif /* MXQ_TESTS_JSON_HPP */
