/*
 * The archive codec boundary — the read side.
 *
 * mxq_archive_supported_versions is a pure report of compiled-in values and is
 * callable before mxq_core_init. mxq_archive_probe decodes and structurally
 * validates an archive; mxq_archive_validate does everything probe does and
 * then replays the move line through the rules tier. mxq_archive_encode, the
 * write side, is not here yet: it is the only function that produces canonical
 * bytes, and it lands with sessions.
 *
 * The ladder below is docs/game-data.md's accepted validation order, in that
 * order and no other, because the order is itself the contract: a file that
 * fails two ways must be reported by the earlier one. Nothing here touches the
 * store — validation is complete before persistence is even consulted, which is
 * what "nothing touches the database until the final stage" means at this
 * level.
 *
 *   1. transport and size
 *   2. strict UTF-8 and JSON syntax under the structural limits, with
 *      duplicate member names, null, and non-integer numbers rejected
 *   3. the envelope, then explicit version dispatch — and only inside a known
 *      version, unknown members
 *   4. field validity: the closed vocabularies, then the cross-field rules
 *   5. the rules tier: the frozen initial position, every move legal in
 *      sequence, and the recorded terminal pair agreeing with the replayed
 *      adjudication                                    (validate only)
 *
 * Stages 1 to 4 are mxq_archive_probe. Stage 5 needs the rules facade, so
 * mxq_archive_validate is compiled only when MXQ_ENABLE_RULES_FACADE is ON —
 * absent from the library rather than stubbed, exactly as the session-free
 * rules facade is, because the error taxonomy has no not-implemented code and
 * inventing one would be inventing contract vocabulary.
 */

#include "mxq_internal.hpp"

#include "mxq_archive_json.hpp"
#include "mxq_core_state.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_engine_bridge.hpp"
#endif

#include <cassert>
#include <cstring>
#include <string>
#include <vector>

namespace mxq {
namespace archive {
namespace {

/* ---------------------------------------------------------------------- */
/* The accepted import limits, from docs/game-data.md                      */
/* ---------------------------------------------------------------------- */

constexpr size_t kMaxArchiveBytes = 1024u * 1024u; /* 1 MiB per file */
constexpr size_t kMaxPlies        = 10000u;
constexpr size_t kMaxDepth        = 4u;
constexpr size_t kMaxMembers      = 32u;
constexpr size_t kMaxStringBytes  = 256u;

json::Limits limits() {
    json::Limits l{};
    l.max_depth = kMaxDepth;
    l.max_members = kMaxMembers;
    l.max_string_bytes = kMaxStringBytes;
    /* The ply limit is an array-element limit: `moves` is the only array the
     * format has, so enforcing it during parsing enforces it before any
     * schema question is asked, which is where the accepted order puts it. */
    l.max_array_elements = kMaxPlies;
    return l;
}

/* The in-band type check. The extension and the UTI are hints; this is not. */
constexpr const char *kArchiveFormat = "minixiangqi-game";

/* The ruleset identity of docs/xiangqi-rules.md, not an engine variant. */
constexpr const char *kRulesId = "minixiangqi";

/* ---------------------------------------------------------------------- */
/* The decoded document                                                    */
/* ---------------------------------------------------------------------- */

struct Decoded {
    uint32_t            archive_version = 0;
    std::string         game_id;
    std::string         rules_id;
    int64_t             rules_version = 0;
    std::string         start_fen;
    std::vector<std::string> moves;
    MxqPlayMode         mode = MXQ_PLAY_MODE_FREE_PLAY;
    MxqColor            human_side = MXQ_COLOR_NONE;
    MxqAiLevel          ai_level = MXQ_AI_LEVEL_NONE;
    uint32_t            ai_movetime_ms = 0;
    MxqFirstMoverChoice first_mover_choice = MXQ_FIRST_MOVER_NONE;
    int64_t             started_at_ms = 0;
    /* The terminal triple is present exactly when the game is completed; an
     * active game's stored content omits all three. */
    bool                completed = false;
    MxqOutcome          outcome = MXQ_OUTCOME_NONE;
    MxqEndReason        end_reason = MXQ_END_REASON_NONE;
    int64_t             ended_at_ms = 0;
};

/* A rejection: the contract status plus the diagnostic that names the field. */
struct Reject {
    MxqStatus   status;
    std::string detail;
    uint64_t    index = 0; /* MxqError.detail_index, where the status uses it */
};

bool reject(Reject &out, MxqStatus status, std::string detail) {
    out.status = status;
    out.detail = std::move(detail);
    out.index = 0;
    return false;
}

/* ---------------------------------------------------------------------- */
/* Small field readers                                                     */
/* ---------------------------------------------------------------------- */

/* A member that must exist and be of one type. Absence and the wrong type are
 * different sentences because they are different mistakes. */
const json::Value *typed_member(const json::Value &object, const char *name,
                                json::Value::Type type, const char *where,
                                Reject &err) {
    const json::Value *value = object.member(name);
    if (value == nullptr) {
        reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
               std::string(where) + " has no \"" + name + "\" member");
        return nullptr;
    }
    if (value->type() != type) {
        reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
               std::string("\"") + name + "\" must be " +
                   json::Value::type_name(type) + ", not " +
                   json::Value::type_name(value->type()));
        return nullptr;
    }
    return value;
}

/* Every member of object must be one of the known names. Called only after
 * version dispatch: an unknown member is a rejection *within a known version*,
 * and a document from a later version must be reported as that instead. */
bool only_known_members(const json::Value &object, const char *const *known,
                        size_t known_count, const char *where, Reject &err) {
    for (size_t i = 0; i < object.member_count(); ++i) {
        const std::string &name = object.member_name(i);
        bool found = false;
        for (size_t k = 0; k < known_count; ++k) {
            if (name == known[k]) {
                found = true;
                break;
            }
        }
        if (!found) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          std::string(where) + " has an unknown member \"" +
                              name + "\" in archive version 1");
        }
    }
    return true;
}

bool is_lower_hex(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
}

/* game_id is a version 7 UUID in canonical lowercase text, frozen at creation
 * and never derived from content. Its shape is checkable here and is worth
 * checking: identity is what duplicate and conflict handling compare. */
bool valid_game_id(const std::string &id) {
    if (id.size() != 36) {
        return false;
    }
    for (size_t i = 0; i < id.size(); ++i) {
        const char c = id[i];
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (c != '-') {
                return false;
            }
        } else if (!is_lower_hex(c)) {
            return false;
        }
    }
    /* The version nibble and the RFC 9562 variant bits. */
    return id[14] == '7' &&
           (id[19] == '8' || id[19] == '9' || id[19] == 'a' || id[19] == 'b');
}

/* The frozen canonical move notation of docs/xiangqi-rules.md: <from><to> over
 * the 7 by 7 board, with no suffix. */
bool valid_move_text(const std::string &move) {
    if (move.size() != 4) {
        return false;
    }
    for (size_t i = 0; i < 4; i += 2) {
        if (move[i] < 'a' || move[i] > 'g') {
            return false;
        }
        if (move[i + 1] < '1' || move[i + 1] > '7') {
            return false;
        }
    }
    return true;
}

/* Days from 1970-01-01 to y-m-d, proleptic Gregorian. Howard Hinnant's
 * civil-from-days inverse, which is exact for every year this format can
 * spell and needs no time-zone database — the archive's instants are UTC by
 * construction. */
int64_t days_from_civil(int64_t y, unsigned m, unsigned d) {
    y -= m <= 2 ? 1 : 0;
    const int64_t era = (y >= 0 ? y : y - 399) / 400;
    const int64_t yoe = y - era * 400;
    const int64_t doy =
        (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + static_cast<int64_t>(d) - 1;
    const int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

unsigned days_in_month(int64_t year, unsigned month) {
    static const unsigned kDays[12] = {31, 28, 31, 30, 31, 30,
                                       31, 31, 30, 31, 30, 31};
    if (month == 2) {
        const bool leap =
            (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
        return leap ? 29u : 28u;
    }
    return kDays[month - 1];
}

bool digits(const std::string &s, size_t at, size_t count, int64_t &out) {
    out = 0;
    for (size_t i = 0; i < count; ++i) {
        const char c = s[at + i];
        if (c < '0' || c > '9') {
            return false;
        }
        out = out * 10 + (c - '0');
    }
    return true;
}

/*
 * The exact fixed-width RFC 3339 UTC form game-data.md fixes:
 * YYYY-MM-DDTHH:MM:SS.sssZ, 24 characters, nothing else accepted — no offset
 * spelling, no lowercase t or z, no variable fractional digits. One spelling is
 * what makes two exports of the same game compare byte for byte.
 */
bool parse_timestamp(const std::string &text, int64_t &out_ms) {
    if (text.size() != 24) {
        return false;
    }
    if (text[4] != '-' || text[7] != '-' || text[10] != 'T' ||
        text[13] != ':' || text[16] != ':' || text[19] != '.' ||
        text[23] != 'Z') {
        return false;
    }
    int64_t year = 0;
    int64_t month = 0;
    int64_t day = 0;
    int64_t hour = 0;
    int64_t minute = 0;
    int64_t second = 0;
    int64_t millis = 0;
    if (!digits(text, 0, 4, year) || !digits(text, 5, 2, month) ||
        !digits(text, 8, 2, day) || !digits(text, 11, 2, hour) ||
        !digits(text, 14, 2, minute) || !digits(text, 17, 2, second) ||
        !digits(text, 20, 3, millis)) {
        return false;
    }
    if (month < 1 || month > 12) {
        return false;
    }
    if (day < 1 ||
        day > static_cast<int64_t>(
                  days_in_month(year, static_cast<unsigned>(month)))) {
        return false;
    }
    /* No leap second: the format has one spelling of every instant, and 60 is
     * a second this core would have to invent a meaning for. */
    if (hour > 23 || minute > 59 || second > 59) {
        return false;
    }
    const int64_t days =
        days_from_civil(year, static_cast<unsigned>(month),
                        static_cast<unsigned>(day));
    out_ms = ((days * 24 + hour) * 60 + minute) * 60000 + second * 1000 + millis;
    return true;
}

/* The closed serialised vocabularies of docs/game-data.md. Unknown values are
 * rejected rather than mapped to a default: a value this build does not know is
 * a value it cannot honour. */
bool read_mode(const std::string &text, MxqPlayMode &out) {
    if (text == "human-vs-ai") {
        out = MXQ_PLAY_MODE_HUMAN_VS_AI;
        return true;
    }
    if (text == "free-play") {
        out = MXQ_PLAY_MODE_FREE_PLAY;
        return true;
    }
    return false;
}

bool read_color(const std::string &text, MxqColor &out) {
    if (text == "red") {
        out = MXQ_COLOR_RED;
        return true;
    }
    if (text == "black") {
        out = MXQ_COLOR_BLACK;
        return true;
    }
    return false;
}

bool read_ai_level(const std::string &text, MxqAiLevel &out) {
    if (text == "fast") {
        out = MXQ_AI_LEVEL_FAST;
        return true;
    }
    if (text == "standard") {
        out = MXQ_AI_LEVEL_STANDARD;
        return true;
    }
    if (text == "deep") {
        out = MXQ_AI_LEVEL_DEEP;
        return true;
    }
    return false;
}

bool read_first_mover(const std::string &text, MxqFirstMoverChoice &out) {
    if (text == "human-first") {
        out = MXQ_FIRST_MOVER_HUMAN_FIRST;
        return true;
    }
    if (text == "ai-first") {
        out = MXQ_FIRST_MOVER_AI_FIRST;
        return true;
    }
    if (text == "random") {
        out = MXQ_FIRST_MOVER_RANDOM;
        return true;
    }
    return false;
}

bool read_outcome(const std::string &text, MxqOutcome &out) {
    if (text == "red-wins") {
        out = MXQ_OUTCOME_RED_WINS;
        return true;
    }
    if (text == "black-wins") {
        out = MXQ_OUTCOME_BLACK_WINS;
        return true;
    }
    if (text == "draw") {
        out = MXQ_OUTCOME_DRAW;
        return true;
    }
    if (text == "none") {
        out = MXQ_OUTCOME_NONE;
        return true;
    }
    return false;
}

bool read_end_reason(const std::string &text, MxqEndReason &out) {
    if (text == "checkmate") {
        out = MXQ_END_REASON_CHECKMATE;
        return true;
    }
    if (text == "stalemate") {
        out = MXQ_END_REASON_STALEMATE;
        return true;
    }
    if (text == "threefold-repetition") {
        out = MXQ_END_REASON_THREEFOLD_REPETITION;
        return true;
    }
    if (text == "perpetual-check") {
        out = MXQ_END_REASON_PERPETUAL_CHECK;
        return true;
    }
    if (text == "perpetual-chase") {
        out = MXQ_END_REASON_PERPETUAL_CHASE;
        return true;
    }
    if (text == "mutual-perpetual-check") {
        out = MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK;
        return true;
    }
    if (text == "mutual-perpetual-chase") {
        out = MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE;
        return true;
    }
    if (text == "resignation") {
        out = MXQ_END_REASON_RESIGNATION;
        return true;
    }
    if (text == "ended-early") {
        out = MXQ_END_REASON_ENDED_EARLY;
        return true;
    }
    return false;
}

bool is_draw_reason(MxqEndReason reason) {
    return reason == MXQ_END_REASON_THREEFOLD_REPETITION ||
           reason == MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK ||
           reason == MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE;
}

/* ---------------------------------------------------------------------- */
/* Stage 3: the envelope and version dispatch                              */
/* ---------------------------------------------------------------------- */

bool read_origin(const json::Value &origin, Reject &err) {
    /* origin describes the export event and is never hashed, never compared,
     * and never trusted — but it is still part of the version-1 document, so a
     * malformed one is a malformed file. Nothing read here reaches the
     * decoded summary. */
    static const char *const kKnown[] = {"app_version", "exported_at"};
    if (!only_known_members(origin, kKnown, 2, "\"origin\"", err)) {
        return false;
    }
    if (typed_member(origin, "app_version", json::Value::Type::String,
                     "\"origin\"", err) == nullptr) {
        return false;
    }
    const json::Value *exported_at = typed_member(
        origin, "exported_at", json::Value::Type::String, "\"origin\"", err);
    if (exported_at == nullptr) {
        return false;
    }
    int64_t ignored = 0;
    if (!parse_timestamp(exported_at->string(), ignored)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"origin.exported_at\" is not an RFC 3339 UTC instant "
                      "in the form YYYY-MM-DDTHH:MM:SS.sssZ");
    }
    return true;
}

bool read_envelope(const json::Value &document, const json::Value *&out_content,
                   Decoded &out, Reject &err) {
    if (!document.is_object()) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "the archive is not a JSON object");
    }

    /* The in-band type check comes first: a file that is not one of ours must
     * not be reported as a version problem or as corruption of ours. */
    const json::Value *format =
        typed_member(document, "archive_format", json::Value::Type::String,
                     "the archive", err);
    if (format == nullptr) {
        return false;
    }
    if (format->string() != kArchiveFormat) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"archive_format\" is not \"" +
                          std::string(kArchiveFormat) + "\"");
    }

    const json::Value *version =
        typed_member(document, "archive_version", json::Value::Type::Integer,
                     "the archive", err);
    if (version == nullptr) {
        return false;
    }
    if (version->integer() < 1) {
        /* Not a version at all: archive versions are a single monotonically
         * increasing integer starting at 1, so this is a corrupt field rather
         * than a file from another release. */
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"archive_version\" is not a positive integer");
    }
    if (version->integer() > MXQ_ARCHIVE_VERSION_CURRENT) {
        Reject r;
        reject(r, MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION,
               "this file was created by a newer version of Mini Xiangqi "
               "(archive version " +
                   std::to_string(version->integer()) + ")");
        err = r;
        return false;
    }
    if (version->integer() < MXQ_ARCHIVE_VERSION_MIN_READABLE) {
        return reject(err, MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION,
                      "archive version " + std::to_string(version->integer()) +
                          " is older than this build reads");
    }
    out.archive_version = static_cast<uint32_t>(version->integer());

    /* Only now, inside a known version, is an unknown member a rejection. */
    static const char *const kKnown[] = {"archive_format", "archive_version",
                                         "content", "game_id", "origin"};
    if (!only_known_members(document, kKnown, 5, "the archive", err)) {
        return false;
    }

    const json::Value *game_id = typed_member(
        document, "game_id", json::Value::Type::String, "the archive", err);
    if (game_id == nullptr) {
        return false;
    }
    if (!valid_game_id(game_id->string())) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"game_id\" is not a version 7 UUID in canonical "
                      "lowercase text");
    }
    out.game_id = game_id->string();

    const json::Value *origin = typed_member(
        document, "origin", json::Value::Type::Object, "the archive", err);
    if (origin == nullptr) {
        return false;
    }
    if (!read_origin(*origin, err)) {
        return false;
    }

    out_content = typed_member(document, "content", json::Value::Type::Object,
                               "the archive", err);
    return out_content != nullptr;
}

/* ---------------------------------------------------------------------- */
/* Stage 4: field validity and the cross-field rules                       */
/* ---------------------------------------------------------------------- */

bool read_content(const json::Value &content, Decoded &out, Reject &err) {
    static const char *const kKnown[] = {
        "ai_level",   "ai_movetime_ms", "end_reason", "ended_at",
        "first_mover_choice", "human_side", "mode", "moves",
        "outcome",    "rules_id",       "rules_version", "start_fen",
        "started_at"};
    if (!only_known_members(content, kKnown, 13, "\"content\"", err)) {
        return false;
    }

    const json::Value *rules_id = typed_member(
        content, "rules_id", json::Value::Type::String, "\"content\"", err);
    if (rules_id == nullptr) {
        return false;
    }
    if (rules_id->string() != kRulesId) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"rules_id\" is not \"" + std::string(kRulesId) + "\"");
    }
    out.rules_id = rules_id->string();

    const json::Value *rules_version =
        typed_member(content, "rules_version", json::Value::Type::Integer,
                     "\"content\"", err);
    if (rules_version == nullptr) {
        return false;
    }
    if (rules_version->integer() < 1) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"rules_version\" is not a positive integer");
    }
    out.rules_version = rules_version->integer();

    const json::Value *start_fen = typed_member(
        content, "start_fen", json::Value::Type::String, "\"content\"", err);
    if (start_fen == nullptr) {
        return false;
    }
    if (start_fen->string().empty() ||
        start_fen->string().size() >= MXQ_FEN_CAP) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"start_fen\" is not a FEN this build can carry");
    }
    out.start_fen = start_fen->string();

    const json::Value *moves = typed_member(
        content, "moves", json::Value::Type::Array, "\"content\"", err);
    if (moves == nullptr) {
        return false;
    }
    out.moves.reserve(moves->elements().size());
    for (size_t i = 0; i < moves->elements().size(); ++i) {
        const json::Value &move = moves->elements()[i];
        if (!move.is_string() || !valid_move_text(move.string())) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "\"moves\"[" + std::to_string(i) +
                              "] is not a move in canonical notation");
        }
        out.moves.push_back(move.string());
    }

    const json::Value *mode = typed_member(content, "mode",
                                           json::Value::Type::String,
                                           "\"content\"", err);
    if (mode == nullptr) {
        return false;
    }
    if (!read_mode(mode->string(), out.mode)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"mode\" is not one of \"human-vs-ai\", \"free-play\"");
    }

    /*
     * The mode-to-configuration relationship, which is also the mapping the C
     * interface's NONE constants stand for: the four configuration members
     * exist exactly for human-versus-AI games, and Free Play omits them rather
     * than writing a null or an empty value. A Free Play document carrying one
     * of them is as malformed as a human-versus-AI document missing one.
     */
    static const char *const kConfig[] = {"ai_level", "ai_movetime_ms",
                                          "first_mover_choice", "human_side"};
    const bool human_vs_ai = out.mode == MXQ_PLAY_MODE_HUMAN_VS_AI;
    for (const char *name : kConfig) {
        const bool present = content.has_member(name);
        if (present != human_vs_ai) {
            return reject(
                err, MXQ_ERR_ARCHIVE_MALFORMED,
                present ? std::string("\"") + name +
                              "\" is present in a Free Play game, which omits it"
                        : std::string("\"content\" has no \"") + name +
                              "\" member in a human-versus-AI game");
        }
    }

    if (human_vs_ai) {
        const json::Value *human_side =
            typed_member(content, "human_side", json::Value::Type::String,
                         "\"content\"", err);
        if (human_side == nullptr) {
            return false;
        }
        if (!read_color(human_side->string(), out.human_side)) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "\"human_side\" is not one of \"red\", \"black\"");
        }

        const json::Value *ai_level =
            typed_member(content, "ai_level", json::Value::Type::String,
                         "\"content\"", err);
        if (ai_level == nullptr) {
            return false;
        }
        if (!read_ai_level(ai_level->string(), out.ai_level)) {
            return reject(
                err, MXQ_ERR_ARCHIVE_MALFORMED,
                "\"ai_level\" is not one of \"fast\", \"standard\", \"deep\"");
        }

        /*
         * ai_movetime_ms is checked for presence and range, never against the
         * current level-to-time pairing: game-data.md stores it beside the
         * level exactly so that a later retuning of a level's time does not
         * reinterpret existing archives. The range is the one the contract
         * already fixes elsewhere — positive, and representable in the uint32
         * the interface carries it in.
         */
        const json::Value *movetime =
            typed_member(content, "ai_movetime_ms", json::Value::Type::Integer,
                         "\"content\"", err);
        if (movetime == nullptr) {
            return false;
        }
        if (movetime->integer() <= 0 ||
            movetime->integer() > static_cast<int64_t>(UINT32_MAX)) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "\"ai_movetime_ms\" is not a positive thinking time");
        }
        out.ai_movetime_ms = static_cast<uint32_t>(movetime->integer());

        const json::Value *first_mover =
            typed_member(content, "first_mover_choice",
                         json::Value::Type::String, "\"content\"", err);
        if (first_mover == nullptr) {
            return false;
        }
        if (!read_first_mover(first_mover->string(), out.first_mover_choice)) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "\"first_mover_choice\" is not one of "
                          "\"human-first\", \"ai-first\", \"random\"");
        }
    }

    const json::Value *started_at = typed_member(
        content, "started_at", json::Value::Type::String, "\"content\"", err);
    if (started_at == nullptr) {
        return false;
    }
    if (!parse_timestamp(started_at->string(), out.started_at_ms)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"started_at\" is not an RFC 3339 UTC instant in the "
                      "form YYYY-MM-DDTHH:MM:SS.sssZ");
    }
    if (out.started_at_ms < 0) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"started_at\" is before the epoch");
    }

    /*
     * The terminal triple: present exactly when the game is completed, which
     * every exported file is, and absent in an active game's stored content.
     * Two of the three is neither shape.
     */
    const bool has_outcome = content.has_member("outcome");
    const bool has_reason = content.has_member("end_reason");
    const bool has_ended_at = content.has_member("ended_at");
    if (has_outcome != has_reason || has_outcome != has_ended_at) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"outcome\", \"end_reason\" and \"ended_at\" are "
                      "present together or not at all");
    }
    out.completed = has_outcome;
    if (!out.completed) {
        return true;
    }

    const json::Value *outcome = typed_member(
        content, "outcome", json::Value::Type::String, "\"content\"", err);
    if (outcome == nullptr) {
        return false;
    }
    if (!read_outcome(outcome->string(), out.outcome)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"outcome\" is not one of \"red-wins\", \"black-wins\", "
                      "\"draw\", \"none\"");
    }

    const json::Value *end_reason = typed_member(
        content, "end_reason", json::Value::Type::String, "\"content\"", err);
    if (end_reason == nullptr) {
        return false;
    }
    if (!read_end_reason(end_reason->string(), out.end_reason)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"end_reason\" is not one of the accepted end reasons");
    }

    const json::Value *ended_at = typed_member(
        content, "ended_at", json::Value::Type::String, "\"content\"", err);
    if (ended_at == nullptr) {
        return false;
    }
    if (!parse_timestamp(ended_at->string(), out.ended_at_ms)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"ended_at\" is not an RFC 3339 UTC instant in the form "
                      "YYYY-MM-DDTHH:MM:SS.sssZ");
    }

    /* The accepted cross-field rules, enforced here and as store constraints:
     * one place decides them, and both places agree. */
    if ((out.outcome == MXQ_OUTCOME_NONE) !=
        (out.end_reason == MXQ_END_REASON_ENDED_EARLY)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"outcome\" is \"none\" exactly when \"end_reason\" is "
                      "\"ended-early\"");
    }
    if ((out.outcome == MXQ_OUTCOME_DRAW) != is_draw_reason(out.end_reason)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"outcome\" is \"draw\" exactly when \"end_reason\" is "
                      "one of the three draw reasons");
    }
    if (out.end_reason == MXQ_END_REASON_RESIGNATION) {
        if (out.mode != MXQ_PLAY_MODE_HUMAN_VS_AI) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "\"resignation\" is a human-versus-AI end reason");
        }
        const MxqOutcome win_for_the_other_side =
            out.human_side == MXQ_COLOR_RED ? MXQ_OUTCOME_BLACK_WINS
                                            : MXQ_OUTCOME_RED_WINS;
        if (out.outcome != win_for_the_other_side) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "a resignation's outcome is the win for the side "
                          "opposite \"human_side\"");
        }
    }
    if (out.ended_at_ms < out.started_at_ms) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"ended_at\" is before \"started_at\"");
    }
    return true;
}

/* ---------------------------------------------------------------------- */
/* Stages 1 to 4 together                                                  */
/* ---------------------------------------------------------------------- */

bool decode(const uint8_t *bytes, size_t len, Decoded &out, Reject &err) {
    /* Stage 1: transport and size. */
    if (len == 0) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED, "the archive is empty");
    }
    if (len > kMaxArchiveBytes) {
        return reject(err, MXQ_ERR_ARCHIVE_TOO_LARGE,
                      "the archive is larger than the 1 MiB import limit");
    }

    /* Stage 2: strict UTF-8 and JSON syntax under the structural limits. */
    json::Value document;
    json::Error json_error{};
    if (!json::parse(bytes, len, limits(), document, json_error)) {
        return reject(err, json_error.status, json_error.detail);
    }

    /* Stage 3: the envelope, then version dispatch, then unknown members. */
    const json::Value *content = nullptr;
    if (!read_envelope(document, content, out, err)) {
        return false;
    }

    /* Stage 4: field validity and the cross-field rules. */
    return read_content(*content, out, err);
}

void fill_info(const Decoded &decoded, MxqArchiveInfo *out) {
    out->archive_version = decoded.archive_version;
    out->move_count = static_cast<uint32_t>(decoded.moves.size());
    out->mode = decoded.mode;
    out->human_side = decoded.human_side;
    /* An archive with no committed end reads MXQ_OUTCOME_NONE and
     * MXQ_END_REASON_NONE, and ended_at_ms 0. MxqOutcome has no absent
     * constant, so end_reason is what separates an ended-early record from a
     * game that has not ended: see MxqArchiveInfo in mxq.h. */
    out->outcome = decoded.completed ? decoded.outcome : MXQ_OUTCOME_NONE;
    out->end_reason = decoded.completed ? decoded.end_reason
                                        : MXQ_END_REASON_NONE;
    out->started_at_ms = decoded.started_at_ms;
    out->ended_at_ms = decoded.completed ? decoded.ended_at_ms : 0;
    copy_bounded(out->game_id, sizeof(out->game_id), decoded.game_id.c_str());
}

#if defined(MXQ_ENABLE_RULES_FACADE)

const char *state_text(MxqGameState state) {
    switch (state) {
    case MXQ_GAME_ONGOING: return "ongoing";
    case MXQ_GAME_CLAIMABLE_DRAW: return "a claimable draw";
    case MXQ_GAME_RED_WINS: return "a red win";
    case MXQ_GAME_BLACK_WINS: return "a black win";
    case MXQ_GAME_DRAW: return "a draw";
    }
    return "an unrecognised state";
}

bool terminal(MxqGameState state) {
    return state == MXQ_GAME_RED_WINS || state == MXQ_GAME_BLACK_WINS ||
           state == MXQ_GAME_DRAW;
}

/*
 * The recorded terminal pair against the replayed adjudication, exactly as
 * game-data.md's validation order states it:
 *
 *   - threefold-repetition requires the facade to report claim eligibility,
 *     not a terminal state — in this ruleset the neutral repetition is always a
 *     user claim, so a file recording it must be one the claim was available
 *     in;
 *   - resignation and ended-early require a non-terminal final position,
 *     because an unconfirmed natural result is always recorded as its actual
 *     result: a checkmate saved as "ended early" would be a lost result, and
 *     the archive must refuse it rather than accept the loss;
 *   - every other reason is an automatic rule outcome, so the replay must
 *     report that same outcome, with the recorded outcome naming the same
 *     winner.
 *
 * The resignation winner rule is a cross-field one and is enforced before the
 * replay ever runs.
 */
MxqStatus check_terminal_pair(const Decoded &decoded,
                              const engine::Adjudication &adj, MxqError *err) {
    const std::string replayed = state_text(adj.state);

    if (decoded.end_reason == MXQ_END_REASON_RESIGNATION ||
        decoded.end_reason == MXQ_END_REASON_ENDED_EARLY) {
        if (terminal(adj.state)) {
            fill_error(err, MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH,
                       ("the final position is " + replayed +
                        ", which a game ended by the user cannot record: an "
                        "unconfirmed natural result is recorded as its actual "
                        "result")
                           .c_str());
            return MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH;
        }
        return MXQ_OK;
    }

    if (decoded.end_reason == MXQ_END_REASON_THREEFOLD_REPETITION) {
        if (adj.state != MXQ_GAME_CLAIMABLE_DRAW) {
            fill_error(err, MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH,
                       ("the final position is " + replayed +
                        ", but a threefold-repetition draw requires the "
                        "position the claim was available in")
                           .c_str());
            return MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH;
        }
        return MXQ_OK;
    }

    if (!terminal(adj.state) || adj.reason != decoded.end_reason) {
        fill_error(err, MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH,
                   ("the replayed adjudication is " + replayed +
                    ", which does not agree with the recorded end reason")
                       .c_str());
        return MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH;
    }

    const MxqOutcome replayed_outcome = adj.state == MXQ_GAME_RED_WINS
                                            ? MXQ_OUTCOME_RED_WINS
                                            : (adj.state == MXQ_GAME_BLACK_WINS
                                                   ? MXQ_OUTCOME_BLACK_WINS
                                                   : MXQ_OUTCOME_DRAW);
    if (decoded.outcome != replayed_outcome) {
        fill_error(err, MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH,
                   ("the replayed adjudication is " + replayed +
                    ", which does not agree with the recorded outcome")
                       .c_str());
        return MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH;
    }
    return MXQ_OK;
}

#endif /* MXQ_ENABLE_RULES_FACADE */

MxqStatus begin(MxqCore *core, const uint8_t *bytes, MxqArchiveInfo *out,
                MxqError *err) {
    const MxqStatus rc = require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (bytes == nullptr) {
        assert(false && "required bytes pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "bytes was null");
        return MXQ_ERR_ARG_NULL;
    }
    return begin_out(out, out != nullptr ? out->struct_size : 0u,
                     static_cast<uint32_t>(sizeof(MxqArchiveInfo)),
                     static_cast<uint32_t>(sizeof(MxqArchiveInfo)), err);
}

} /* namespace */
} /* namespace archive */
} /* namespace mxq */

extern "C" {

MxqStatus MXQ_CALL mxq_archive_supported_versions(uint32_t *out_min_readable,
                                                  uint32_t *out_current,
                                                  MxqError *err) {
    if (out_min_readable == nullptr && out_current == nullptr) {
        assert(false && "both out parameters were null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL,
                        "both out parameters were null");
        return MXQ_ERR_ARG_NULL;
    }
    if (out_min_readable != nullptr) {
        *out_min_readable = MXQ_ARCHIVE_VERSION_MIN_READABLE;
    }
    if (out_current != nullptr) {
        *out_current = MXQ_ARCHIVE_VERSION_CURRENT;
    }
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_archive_probe(MxqCore *core, const uint8_t *bytes,
                                     size_t len, MxqArchiveInfo *out,
                                     MxqError *err) {
    const MxqStatus rc = mxq::archive::begin(core, bytes, out, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::archive::Decoded decoded;
    mxq::archive::Reject rejected{};
    if (!mxq::archive::decode(bytes, len, decoded, rejected)) {
        mxq::fill_error(err, rejected.status, rejected.detail.c_str());
        return rejected.status;
    }
    mxq::archive::fill_info(decoded, out);
    return MXQ_OK;
}

#if defined(MXQ_ENABLE_RULES_FACADE)

MxqStatus MXQ_CALL mxq_archive_validate(MxqCore *core, const uint8_t *bytes,
                                        size_t len, MxqArchiveInfo *out,
                                        MxqError *err) {
    const MxqStatus rc = mxq::archive::begin(core, bytes, out, err);
    if (rc != MXQ_OK) {
        return rc;
    }

    mxq::archive::Decoded decoded;
    mxq::archive::Reject rejected{};
    if (!mxq::archive::decode(bytes, len, decoded, rejected)) {
        mxq::fill_error(err, rejected.status, rejected.detail.c_str());
        return rejected.status;
    }

    /*
     * Stage 5, the rules tier. The initial position must be exactly the frozen
     * starting FEN — version 1 defines no other, and the setup-legality
     * predicate a later version would need does not exist — then every move
     * must be legal in sequence, then the recorded terminal pair must agree
     * with the replayed adjudication.
     */
    if (decoded.start_fen != MXQ_START_FEN) {
        mxq::fill_error(err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY,
                        "\"start_fen\" is not the frozen starting position, "
                        "which is the only initial position archive version 1 "
                        "defines");
        return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
    }

    std::vector<const char *> moves;
    moves.reserve(decoded.moves.size());
    for (const std::string &move : decoded.moves) {
        moves.push_back(move.c_str());
    }

    std::string fen;
    std::string detail;
    bool in_check = false;
    uint32_t ply = 0;
    mxq::engine::Adjudication adj{};
    size_t first_illegal = 0;

    switch (mxq::engine::replay(decoded.start_fen.c_str(),
                                moves.empty() ? nullptr : moves.data(),
                                moves.size(), fen, in_check, ply, adj, nullptr,
                                first_illegal, detail)) {
    case mxq::engine::ReplayError::None:
        break;
    case mxq::engine::ReplayError::IllegalMove:
        mxq::fill_error_index(
            err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY,
            ("the move line is not legal: " + detail).c_str(), first_illegal);
        return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
    case mxq::engine::ReplayError::StartFenInvalid:
    case mxq::engine::ReplayError::NotInitialised:
        mxq::fill_error(err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY,
                        detail.c_str());
        return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
    }

    if (decoded.completed) {
        const MxqStatus terminal =
            mxq::archive::check_terminal_pair(decoded, adj, err);
        if (terminal != MXQ_OK) {
            return terminal;
        }
    }
    /* An active game's stored content records no end, and there is nothing for
     * the adjudication to agree with: an unconfirmed natural terminal state
     * remains the active game, so a terminal final position is as valid there
     * as an ongoing one. */

    mxq::archive::fill_info(decoded, out);
    return MXQ_OK;
}

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* extern "C" */
