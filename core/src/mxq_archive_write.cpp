/* The canonical writer. See mxq_archive_write.hpp for what it owes. */

#include "mxq_archive_write.hpp"

#include "mxq_build_config.h"
#include "mxq_internal.hpp"
#include "mxq_notation.hpp"

#include <algorithm>
#include <cassert>
#include <utility>

namespace mxq {
namespace archive {
namespace {

/* The in-band type check, spelled here exactly as the reader in
 * mxq_archive.cpp requires it. It names the file format rather than either
 * game: one format carries both, and the game is content.rules_id. */
constexpr const char *kArchiveFormat = "minixiangqi-game";

/*
 * origin.app_version. The core is the only writer of an archive, so the
 * version that describes the document is the product version this core was
 * built as, taken from the one place the build states it. The frontend does
 * not supply it: origin is never hashed, never compared and never trusted, so
 * a value the frontend could vary would buy nothing and cost byte-stability.
 */
constexpr const char *kAppVersion = MXQ_BUILD_APP_VERSION;

/* ---------------------------------------------------------------------- */
/* JSON, in the canonical spelling only                                    */
/* ---------------------------------------------------------------------- */

/*
 * Minimal escaping: the two characters JSON requires escaped, the five control
 * characters with a two-character form, and \u00xx for the remaining controls.
 * Nothing else is escaped — not the solidus, and no non-ASCII byte, which is
 * emitted as the UTF-8 it already is.
 *
 * No value this format carries contains a control character today; the general
 * rule is written anyway, because a writer that is correct only for its
 * current inputs is a writer that breaks silently on the first new one.
 */
void write_json_string(std::string &out, const std::string &value) {
    static const char kHex[] = "0123456789abcdef";
    out.push_back('"');
    for (const char raw : value) {
        const unsigned char c = static_cast<unsigned char>(raw);
        switch (c) {
        case '"':  out += "\\\""; continue;
        case '\\': out += "\\\\"; continue;
        case '\b': out += "\\b";  continue;
        case '\f': out += "\\f";  continue;
        case '\n': out += "\\n";  continue;
        case '\r': out += "\\r";  continue;
        case '\t': out += "\\t";  continue;
        default: break;
        }
        if (c < 0x20u) {
            out += "\\u00";
            out.push_back(kHex[(c >> 4) & 0xfu]);
            out.push_back(kHex[c & 0xfu]);
            continue;
        }
        out.push_back(raw);
    }
    out.push_back('"');
}

std::string json_string(const std::string &value) {
    std::string out;
    write_json_string(out, value);
    return out;
}

/* The vocabulary helpers answer a null pointer for the values the archive
 * omits, and this writer only asks them for members it is about to write. The
 * overload exists so that a caller which got that wrong writes an empty string
 * — a document the reader refuses — rather than constructing a std::string
 * from a null pointer. */
std::string json_string(const char *value) {
    assert(value != nullptr && "the writer asked for a member the archive omits");
    return json_string(value != nullptr ? std::string(value) : std::string());
}

/*
 * One object, its members written in codepoint order.
 *
 * The order is produced by sorting rather than by writing the members in a
 * hand-kept sequence: the clause is "members in codepoint order", and a
 * hand-kept sequence is a clause that drifts the first time a member is added.
 * Comparing std::string compares bytes as unsigned, which for UTF-8 is
 * codepoint order.
 */
std::string json_object(std::vector<std::pair<const char *, std::string>> members) {
    std::sort(members.begin(), members.end(),
              [](const std::pair<const char *, std::string> &a,
                 const std::pair<const char *, std::string> &b) {
                  return std::string(a.first) < std::string(b.first);
              });
    std::string out;
    out.push_back('{');
    for (size_t i = 0; i < members.size(); ++i) {
        if (i > 0) {
            out.push_back(',');
        }
        write_json_string(out, members[i].first);
        out.push_back(':');
        out += members[i].second;
    }
    out.push_back('}');
    return out;
}

std::string json_moves(const std::vector<std::string> &moves) {
    std::string out;
    out.push_back('[');
    for (size_t i = 0; i < moves.size(); ++i) {
        if (i > 0) {
            out.push_back(',');
        }
        write_json_string(out, moves[i]);
    }
    out.push_back(']');
    return out;
}

/* ---------------------------------------------------------------------- */
/* Time                                                                    */
/* ---------------------------------------------------------------------- */

/* Howard Hinnant's civil_from_days, the inverse of the days_from_civil the
 * reader parses timestamps with. Exact for every year this fixed-width form
 * can spell, and needs no time-zone database: the archive's instants are UTC
 * by construction. */
void civil_from_days(int64_t days, int64_t &year, unsigned &month,
                     unsigned &day) {
    days += 719468;
    const int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    const int64_t doe = days - era * 146097;
    const int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const int64_t y = yoe + era * 400;
    const int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const int64_t mp = (5 * doy + 2) / 153;
    day = static_cast<unsigned>(doy - (153 * mp + 2) / 5 + 1);
    month = static_cast<unsigned>(mp + (mp < 10 ? 3 : -9));
    year = y + (month <= 2 ? 1 : 0);
}

void write_padded(std::string &out, int64_t value, int width) {
    char buffer[8];
    for (int i = width - 1; i >= 0; --i) {
        buffer[i] = static_cast<char>('0' + value % 10);
        value /= 10;
    }
    out.append(buffer, static_cast<size_t>(width));
}

} /* namespace */

std::string timestamp_text(int64_t epoch_ms) {
    /* Every instant this core writes comes from its own clock and is at or
     * after the epoch; a negative one would have no spelling in a form whose
     * year field is four digits. */
    assert(epoch_ms >= 0 && "an archive instant is at or after the epoch");
    if (epoch_ms < 0) {
        epoch_ms = 0;
    }
    const int64_t ms_per_day = 86400000;
    const int64_t days = epoch_ms / ms_per_day;
    int64_t rest = epoch_ms % ms_per_day;

    int64_t year = 0;
    unsigned month = 0;
    unsigned day = 0;
    civil_from_days(days, year, month, day);

    const int64_t millis = rest % 1000;
    rest /= 1000;
    const int64_t second = rest % 60;
    rest /= 60;
    const int64_t minute = rest % 60;
    const int64_t hour = rest / 60;

    std::string out;
    out.reserve(24);
    write_padded(out, year, 4);
    out.push_back('-');
    write_padded(out, month, 2);
    out.push_back('-');
    write_padded(out, day, 2);
    out.push_back('T');
    write_padded(out, hour, 2);
    out.push_back(':');
    write_padded(out, minute, 2);
    out.push_back(':');
    write_padded(out, second, 2);
    out.push_back('.');
    write_padded(out, millis, 3);
    out.push_back('Z');
    return out;
}

/* ---------------------------------------------------------------------- */
/* The closed vocabularies                                                 */
/* ---------------------------------------------------------------------- */

const char *rules_id_text(MxqGameKind game) {
    switch (game) {
    case MXQ_GAME_KIND_MINI_XIANGQI: return "minixiangqi";
    case MXQ_GAME_KIND_XIANGQI:      return "xiangqi";
    default: break;
    }
    assert(false && "a game outside the closed vocabulary reached the writer");
    return nullptr;
}

const char *mode_text(MxqPlayMode mode) {
    switch (mode) {
    case MXQ_PLAY_MODE_HUMAN_VS_AI: return "human-vs-ai";
    case MXQ_PLAY_MODE_FREE_PLAY:   return "free-play";
    default: break;
    }
    assert(false && "a mode outside the closed vocabulary reached the writer");
    return nullptr;
}

const char *color_text(MxqColor color) {
    switch (color) {
    case MXQ_COLOR_RED:   return "red";
    case MXQ_COLOR_BLACK: return "black";
    default: break;
    }
    return nullptr; /* MXQ_COLOR_NONE: the archive omits the member */
}

const char *ai_level_text(MxqAiLevel level) {
    switch (level) {
    case MXQ_AI_LEVEL_FAST:     return "fast";
    case MXQ_AI_LEVEL_STANDARD: return "standard";
    case MXQ_AI_LEVEL_DEEP:     return "deep";
    default: break;
    }
    return nullptr;
}

const char *first_mover_text(MxqFirstMoverChoice choice) {
    switch (choice) {
    case MXQ_FIRST_MOVER_HUMAN_FIRST: return "human-first";
    case MXQ_FIRST_MOVER_AI_FIRST:    return "ai-first";
    case MXQ_FIRST_MOVER_RANDOM:      return "random";
    default: break;
    }
    return nullptr;
}

const char *outcome_text(MxqOutcome outcome) {
    switch (outcome) {
    case MXQ_OUTCOME_NONE:       return "none";
    case MXQ_OUTCOME_RED_WINS:   return "red-wins";
    case MXQ_OUTCOME_BLACK_WINS: return "black-wins";
    case MXQ_OUTCOME_DRAW:       return "draw";
    default: break;
    }
    assert(false && "an outcome outside the closed vocabulary reached the writer");
    return nullptr;
}

const char *end_reason_text(MxqEndReason reason) {
    switch (reason) {
    case MXQ_END_REASON_CHECKMATE:              return "checkmate";
    case MXQ_END_REASON_STALEMATE:              return "stalemate";
    case MXQ_END_REASON_THREEFOLD_REPETITION:   return "threefold-repetition";
    case MXQ_END_REASON_PERPETUAL_CHECK:        return "perpetual-check";
    case MXQ_END_REASON_PERPETUAL_CHASE:        return "perpetual-chase";
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK: return "mutual-perpetual-check";
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE: return "mutual-perpetual-chase";
    case MXQ_END_REASON_RESIGNATION:            return "resignation";
    case MXQ_END_REASON_ENDED_EARLY:            return "ended-early";
    case MXQ_END_REASON_FIFTY_MOVE_RULE:        return "fifty-move-rule";
    default: break;
    }
    return nullptr; /* MXQ_END_REASON_NONE: no end is recorded */
}

/* ---------------------------------------------------------------------- */
/* The document                                                            */
/* ---------------------------------------------------------------------- */

std::string content_bytes(const Record &record) {
    std::vector<std::pair<const char *, std::string>> members;
    members.reserve(13);

    members.emplace_back("rules_id", json_string(rules_id_text(record.config.game)));
    members.emplace_back("rules_version", std::to_string(MXQ_RULES_VERSION));
    /* Version 2 defines exactly one initial position per game, so the writer
     * states that game's frozen one rather than carrying a start position it
     * would have to validate. Both members read the same field, which is what
     * makes a document naming one game and opening from the other's board
     * unwritable rather than merely refused. */
    members.emplace_back("start_fen",
                         json_string(notation::start_fen(record.config.game)));
    members.emplace_back("moves", json_moves(record.moves));
    members.emplace_back("mode", json_string(mode_text(record.config.mode)));

    /* The four configuration members exist exactly for human-versus-AI games;
     * Free Play omits them rather than writing a null or an empty value, which
     * is what MXQ_COLOR_NONE, MXQ_AI_LEVEL_NONE and MXQ_FIRST_MOVER_NONE stand
     * for on the other side of the C interface. */
    if (record.config.mode == MXQ_PLAY_MODE_HUMAN_VS_AI) {
        members.emplace_back("human_side",
                             json_string(color_text(record.config.human_side)));
        members.emplace_back("ai_level",
                             json_string(ai_level_text(record.config.ai_level)));
        members.emplace_back("ai_movetime_ms",
                             std::to_string(record.config.ai_movetime_ms));
        members.emplace_back(
            "first_mover_choice",
            json_string(first_mover_text(record.config.first_mover_choice)));
    }

    members.emplace_back("started_at",
                         json_string(timestamp_text(record.started_at_ms)));

    if (record.completed) {
        members.emplace_back("outcome", json_string(outcome_text(record.outcome)));
        members.emplace_back("end_reason",
                             json_string(end_reason_text(record.end_reason)));
        members.emplace_back("ended_at",
                             json_string(timestamp_text(record.ended_at_ms)));
    }

    return json_object(std::move(members));
}

std::string document_bytes(const Record &record, const std::string &content) {
    std::vector<std::pair<const char *, std::string>> origin;
    origin.reserve(2);
    origin.emplace_back("app_version", json_string(kAppVersion));
    origin.emplace_back("exported_at",
                        json_string(timestamp_text(record.written_at_ms)));

    std::vector<std::pair<const char *, std::string>> document;
    document.reserve(5);
    document.emplace_back("archive_format", json_string(kArchiveFormat));
    document.emplace_back("archive_version",
                          std::to_string(MXQ_ARCHIVE_VERSION_CURRENT));
    document.emplace_back("content", content);
    document.emplace_back("game_id", json_string(record.game_id));
    document.emplace_back("origin", json_object(std::move(origin)));

    return json_object(std::move(document));
}

} /* namespace archive */
} /* namespace mxq */
