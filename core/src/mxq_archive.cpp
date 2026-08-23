/*
 * The archive codec boundary.
 *
 * mxq_archive_supported_versions is a pure report of compiled-in values and is
 * callable before mxq_core_init. mxq_archive_probe decodes and structurally
 * validates an archive; mxq_archive_validate does everything probe does and
 * then replays the move line through the rules tier. mxq_archive_encode is the
 * write side: it takes a session, so it is gated on the rules facade like the
 * sessions themselves, and every question about the canonical spelling belongs
 * to mxq_archive_write.cpp rather than here.
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
#include "mxq_archive_read.hpp"
#include "mxq_archive_write.hpp"
#include "mxq_core_state.hpp"
#include "mxq_deal.hpp"
#include "mxq_notation.hpp"

#if defined(MXQ_ENABLE_RULES_FACADE)
#include "mxq_engine_bridge.hpp"
#include "mxq_rules.hpp"
#include "mxq_session.hpp"
#include "mxq_setup.hpp"
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

/*
 * The string bound is the format's own number, decided rather than inherited.
 *
 * 256 bytes is what every string this format carries fits inside with room to
 * spare: the widest is start_fen, and its domain is no longer the four frozen
 * starts — a xiangqi document may carry any position that game's setup-legality
 * predicate accepts, which no arrangement of pieces spells in more than 109,
 * and a jieqi document carries a dealt start, which every deal spells in
 * exactly 99. The timestamps are 24, game_id is 36, the three deal members are
 * 64 apiece, a ply is at most 6, and the serialised
 * identifiers are shorter than any of them. The number is chosen against the
 * widest position any game this specification carries can reach — a full 15x15
 * placement board is 251 characters — rather than against the widest one a
 * document may open from, so it already admits every start of every game.
 *
 * It is one bound for every string, start_fen included, and the parser applies
 * it at stage 2 rather than any field re-stating it at stage 4: the accepted
 * validation order requires a file that fails two ways to be reported by the
 * earlier one, and a second copy of a number is a second authority for it.
 *
 * start_fen is the one member with a further constraint — a value this reader
 * accepts must be one MxqPosition.fen can carry — and that is a relationship
 * between a format bound and an ABI capacity, so it is asserted at compile time
 * rather than branched on per file. It used to be a second runtime bound at
 * stage 4, comparing against MXQ_FEN_CAP itself, and two authorities for one
 * number is what makes a number move without anyone deciding it: while the cap
 * was 96 that branch was the tighter of the two and decided the member's bound;
 * when the cap became 512 for the placement games it fell behind the general
 * limit and stopped deciding anything, so start_fen widened from 96 to 256 by
 * arithmetic rather than by choice, and the branch that used to state it became
 * unreachable. Removing it leaves one authority, and a capacity that ever
 * shrinks below it fails the build instead of a file.
 */
constexpr size_t kMaxStringBytes = 256u;

static_assert(kMaxStringBytes < MXQ_FEN_CAP,
              "a start_fen this reader accepts must fit MxqPosition.fen");

/*
 * These bound the import surface and nothing else. Live local play is not
 * length-limited, and a locally produced game that exceeds them stays fully
 * playable and replayable — only re-importing its export is refused. Both
 * public entry points here are import-facing and apply them; the store's own
 * path back into a game it wrote does not, or a long local game could be
 * exported and never resumed. read_stored below is that path.
 */

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

/*
 * The same reader with the two *size* bounds lifted — plies here, the file
 * size at the transport stage — and the three that describe the format's own
 * shape kept. Depth, members per object and string length are properties of a
 * version 6 document rather than of how long a game ran, no document this core
 * writes approaches them, and keeping them means a corrupted row cannot steer
 * the reader into unbounded work.
 */
json::Limits stored_limits() {
    json::Limits l = limits();
    l.max_array_elements = SIZE_MAX;
    return l;
}

/* The in-band type check. The extension and the UTI are hints; this is not.
 * It names the file format, which every game shares; which game a file records
 * is content.rules_id. */
constexpr const char *kArchiveFormat = "minixiangqi-game";

/* ---------------------------------------------------------------------- */
/* The decoded document                                                    */
/* ---------------------------------------------------------------------- */

struct Decoded {
    uint32_t            archive_version = 0;
    std::string         game_id;
    /* The ruleset identity, decoded: which game this document records, and
     * therefore which board its moves are read against, which starting position
     * it must open from, and which rule reasons it may end with. Not an engine
     * variant. */
    MxqGameKind         game = MXQ_GAME_KIND_MINI_XIANGQI;
    int64_t             rules_version = 0;
    std::string         start_fen;
    std::vector<std::string> moves;
    /* The deal's provenance, present exactly for a jieqi document whose mode is
     * nearby. Empty is absent, and the presence rule is enforced at stage 4
     * with the rest of the cross-field rules; what the values mean is checked
     * at the rules tier, where the deal they derive is compared with the start
     * they stand beside. */
    std::string         deal_commit;
    std::string         deal_nonce;
    std::string         deal_seed;
    MxqPlayMode         mode = MXQ_PLAY_MODE_FREE_PLAY;
    MxqColor            human_side = MXQ_COLOR_NONE;
    MxqAiLevel          ai_level = MXQ_AI_LEVEL_NONE;
    uint32_t            ai_movetime_ms = 0;
    MxqFirstMoverChoice first_mover_choice = MXQ_FIRST_MOVER_NONE;
    int64_t             started_at_ms = 0;
    /* origin.exported_at. Nothing in the decoded summary carries it — origin
     * is never hashed, compared or trusted — but the store's own path back
     * into a game keeps it, so that resuming and re-encoding a session
     * reproduces the bytes the row holds rather than restamping them. */
    int64_t             origin_written_at_ms = 0;
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
                              name + "\" in archive version " +
                              std::to_string(MXQ_ARCHIVE_VERSION_CURRENT));
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

/*
 * The closed serialised vocabularies of docs/game-data.md. Unknown values are
 * rejected rather than mapped to a default: a value this build does not know is
 * a value it cannot honour.
 *
 * rules_id spells the games this format version carries, of which a build
 * accepts the ones it also plays. Which games a build carries is the build's,
 * per mxq.h: a core compiled without the engine a game is played on does not
 * carry that game, and here that is not a preference but a necessity — the
 * board, the move grammar and the frozen start of a game this build does not
 * carry are not in it, so there is nothing to read the rest of the document
 * against. A game the format version does not spell would be the same refusal
 * from the other side, arriving as a null from rules_id_text; version 6 spells
 * every game this core plays, so that arm answers for nothing today and is kept
 * because the two sides of the pairing are one rule.
 */
bool read_rules_id(const std::string &text, MxqGameKind &out) {
    for (const MxqGameKind game : {MXQ_GAME_KIND_MINI_XIANGQI,
                                   MXQ_GAME_KIND_XIANGQI,
                                   MXQ_GAME_KIND_GOMOKU_15,
                                   MXQ_GAME_KIND_RENJU,
                                   MXQ_GAME_KIND_JIEQI}) {
        const char *spelling = rules_id_text(game);
        if (notation::known_game(game) && spelling != nullptr &&
            text == spelling) {
            out = game;
            return true;
        }
    }
    return false;
}

bool read_mode(const std::string &text, MxqPlayMode &out) {
    if (text == "human-vs-ai") {
        out = MXQ_PLAY_MODE_HUMAN_VS_AI;
        return true;
    }
    if (text == "free-play") {
        out = MXQ_PLAY_MODE_FREE_PLAY;
        return true;
    }
    if (text == "nearby") {
        out = MXQ_PLAY_MODE_NEARBY;
        return true;
    }
    if (text == "online") {
        out = MXQ_PLAY_MODE_ONLINE;
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
    if (text == "fifty-move-rule") {
        out = MXQ_END_REASON_FIFTY_MOVE_RULE;
        return true;
    }
    if (text == "forty-move-rule") {
        out = MXQ_END_REASON_FORTY_MOVE_RULE;
        return true;
    }
    if (text == "agreed-draw") {
        out = MXQ_END_REASON_AGREED_DRAW;
        return true;
    }
    if (text == "mutual-resignation") {
        out = MXQ_END_REASON_MUTUAL_RESIGNATION;
        return true;
    }
    if (text == "five-in-a-row") {
        out = MXQ_END_REASON_FIVE_IN_A_ROW;
        return true;
    }
    if (text == "board-full") {
        out = MXQ_END_REASON_BOARD_FULL;
        return true;
    }
    return false;
}

bool is_draw_reason(MxqEndReason reason) {
    return reason == MXQ_END_REASON_THREEFOLD_REPETITION ||
           reason == MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK ||
           reason == MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE ||
           reason == MXQ_END_REASON_FIFTY_MOVE_RULE ||
           reason == MXQ_END_REASON_FORTY_MOVE_RULE ||
           reason == MXQ_END_REASON_AGREED_DRAW ||
           reason == MXQ_END_REASON_MUTUAL_RESIGNATION ||
           reason == MXQ_END_REASON_BOARD_FULL;
}

/*
 * Which reasons the rules of a game can produce, as against the ones a player
 * or a pair of players declare.
 *
 * The rule reasons partition by what kind of game reaches them, and the
 * partition is total: nine belong to the movement games — a placement game has
 * no king to mate, no side to leave without a move, and no position that occurs
 * twice, since every ply adds a stone and none is ever removed — and two belong
 * to the placement games, which are the only ones with a line of five to make
 * or a board to fill. The four declared ends — resignation, ended-early,
 * agreed-draw, mutual-resignation — belong to every game and are governed by
 * mode instead, above.
 *
 * Both halves are stated because a partition checked on one side only refuses
 * half of what it knows: a xiangqi document recording "board-full" and a gomoku
 * document recording "checkmate" are the same mistake.
 */
bool is_movement_rule_reason(MxqEndReason reason) {
    return reason == MXQ_END_REASON_CHECKMATE ||
           reason == MXQ_END_REASON_STALEMATE ||
           reason == MXQ_END_REASON_THREEFOLD_REPETITION ||
           reason == MXQ_END_REASON_PERPETUAL_CHECK ||
           reason == MXQ_END_REASON_PERPETUAL_CHASE ||
           reason == MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK ||
           reason == MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE ||
           reason == MXQ_END_REASON_FIFTY_MOVE_RULE ||
           reason == MXQ_END_REASON_FORTY_MOVE_RULE;
}

bool is_placement_rule_reason(MxqEndReason reason) {
    return reason == MXQ_END_REASON_FIVE_IN_A_ROW ||
           reason == MXQ_END_REASON_BOARD_FULL;
}

/* The two ends only two players can reach, and therefore only a nearby record
 * can carry. A resignation is not among them: one player alone reaches that,
 * and both local modes and nearby play have their own way to. */
bool is_agreed_reason(MxqEndReason reason) {
    return reason == MXQ_END_REASON_AGREED_DRAW ||
           reason == MXQ_END_REASON_MUTUAL_RESIGNATION;
}

/* ---------------------------------------------------------------------- */
/* Stage 3: the envelope and version dispatch                              */
/* ---------------------------------------------------------------------- */

bool read_origin(const json::Value &origin, Decoded &out, Reject &err) {
    /* origin describes the export event and is never hashed, never compared,
     * and never trusted — but it is still part of the document, so a malformed
     * one is a malformed file. Nothing read here reaches the decoded
     * summary. */
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
    if (!parse_timestamp(exported_at->string(), out.origin_written_at_ms)) {
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
        /* The one message the contract requires to be distinct, and never to
         * be presented as corruption. */
        return reject(err, MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION,
                      "this file was created by a newer version of Mini "
                      "Xiangqi (archive version " +
                          std::to_string(version->integer()) + ")");
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
    if (!read_origin(*origin, out, err)) {
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
        "ai_level",   "ai_movetime_ms", "deal_commit", "deal_nonce",
        "deal_seed",  "end_reason",     "ended_at",
        "first_mover_choice", "human_side", "mode", "moves",
        "outcome",    "rules_id",       "rules_version", "start_fen",
        "started_at"};
    if (!only_known_members(content, kKnown, 16, "\"content\"", err)) {
        return false;
    }

    const json::Value *rules_id = typed_member(
        content, "rules_id", json::Value::Type::String, "\"content\"", err);
    if (rules_id == nullptr) {
        return false;
    }
    if (!read_rules_id(rules_id->string(), out.game)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"rules_id\" is not a game this build carries");
    }

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
    /*
     * A rules interpretation this build does not implement is refused the same
     * way an archive version it cannot read is, because it is the same fact: a
     * game's meaning derives from rules_id plus rules_version, that version
     * increments only when an accepted change alters a legal move or a
     * user-visible result, and so a file recorded under another one cannot be
     * reproduced here. Replaying it under this interpretation would either
     * fail as an illegal move or — worse — succeed and disagree about the
     * result, which would be presented as corruption of the file. The
     * unsupported-version answer says the true thing instead.
     */
    if (rules_version->integer() != MXQ_RULES_VERSION) {
        return reject(err, MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION,
                      "recorded under rules version " +
                          std::to_string(rules_version->integer()) +
                          "; this build implements " +
                          std::to_string(MXQ_RULES_VERSION));
    }
    out.rules_version = rules_version->integer();

    const json::Value *start_fen = typed_member(
        content, "start_fen", json::Value::Type::String, "\"content\"", err);
    if (start_fen == nullptr) {
        return false;
    }
    /*
     * How long a start_fen may be is the format's one string bound, applied by
     * the parser at stage 2 — where a file that fails two ways must be reported,
     * and where every other string of the document is bounded too. What is left
     * for stage 4 is the one structural thing that bound cannot say: a FEN is
     * not nothing. A shorter FEN that is merely wrong is carried on and resolved
     * at the rules tier, where being "not the frozen starting position" is a
     * replay answer rather than a structural one, so probe accepts every
     * wrong-but-carryable FEN — which is exactly what probe promises.
     */
    if (start_fen->string().empty()) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"start_fen\" is empty");
    }
    out.start_fen = start_fen->string();

    const json::Value *moves = typed_member(
        content, "moves", json::Value::Type::Array, "\"content\"", err);
    if (moves == nullptr) {
        return false;
    }
    /* Judged against the board of the game rules_id named, which is why that
     * member is read first: "a9a10" is a move in one game and nonsense in the
     * other, and a reader with one grammar would accept or refuse both. */
    out.moves.reserve(moves->elements().size());
    for (size_t i = 0; i < moves->elements().size(); ++i) {
        const json::Value &move = moves->elements()[i];
        if (!move.is_string() ||
            !notation::well_formed_move(out.game, move.string())) {
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
                      "\"mode\" is not one of \"human-vs-ai\", \"free-play\", "
                      "\"nearby\", \"online\"");
    }

    /*
     * The mode-to-configuration relationship, which is also the mapping the C
     * interface's NONE constants stand for: the four configuration members
     * exist exactly for human-versus-AI games, and every other mode omits them
     * rather than writing a null or an empty value. A Free Play or networked
     * document carrying one of them is as malformed as a human-versus-AI
     * document missing one.
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
                              "\" is present in a game that is not "
                              "human-versus-AI, which omits it"
                        : std::string("\"content\" has no \"") + name +
                              "\" member in a human-versus-AI game");
        }
    }

    /* And the one game that plays no mode at all: jieqi has no AI, so a
     * document recording a game of it against a machine records a game this app
     * cannot have played. The four configuration members are refused with the
     * mode rather than one at a time, because it is the mode they belong to. */
    if (human_vs_ai && out.game == MXQ_GAME_KIND_JIEQI) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"jieqi\" has no AI, so no document of it records a game "
                      "played against one");
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

    /*
     * The deal's provenance: present exactly when the game is jieqi and the
     * mode is a networked one, and absent otherwise, because a locally dealt
     * game has no handshake behind it to record and no other game has a deal at
     * all. Both halves are checked, and on both axes: a free-play jieqi document
     * carrying them and a networked minixiangqi document carrying them are two
     * different mistakes, each refused in its own words, and a rule checked on
     * one side only refuses half of what it knows.
     *
     * The shape is the format's — thirty-two bytes as sixty-four lowercase
     * hexadecimal digits, which is how all four handshake values are written
     * everywhere — and it is field validity rather than a rules question, so it
     * is answered here. Whether the values are the deal's is the rules tier's,
     * where the deal they derive is compared with the start they stand beside.
     */
    {
        static const char *const kDealMembers[] = {"deal_commit", "deal_nonce",
                                                   "deal_seed"};
        const bool dealt = out.game == MXQ_GAME_KIND_JIEQI &&
                           mxq::networked_mode(out.mode);
        for (const char *name : kDealMembers) {
            const bool present = content.has_member(name);
            if (present == dealt) {
                continue;
            }
            if (!present) {
                return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                              std::string("\"content\" has no \"") + name +
                                  "\" member in a networked jieqi game");
            }
            /* The two axes refuse a present member for two different reasons,
             * and each says its own: a game that is dealt no start has no deal
             * for a member to be evidence of, while the dealt game played
             * locally has a deal and no handshake behind it. One sentence for
             * both would leave whoever reads the detail unable to tell which
             * mistake the file made. */
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          out.game != MXQ_GAME_KIND_JIEQI
                              ? std::string("\"") + name +
                                    "\" is present in a game that is dealt no "
                                    "start and so has no deal at all"
                              : std::string("\"") + name +
                                    "\" is present in a game whose deal came "
                                    "from no handshake, which omits it");
        }
        if (dealt) {
            std::string *const fields[] = {&out.deal_commit, &out.deal_nonce,
                                           &out.deal_seed};
            for (size_t i = 0; i < 3; ++i) {
                const json::Value *value =
                    typed_member(content, kDealMembers[i],
                                 json::Value::Type::String, "\"content\"", err);
                if (value == nullptr) {
                    return false;
                }
                if (!deal::is_hex32(value->string())) {
                    return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                                  std::string("\"") + kDealMembers[i] +
                                      "\" is not thirty-two bytes in lowercase "
                                      "hexadecimal");
                }
                *fields[i] = value->string();
            }
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
                      "one of the six draw reasons");
    }
    /*
     * A resignation is a side losing, and the outcome names the winner, so the
     * side that resigned is its opposite and no member has to say it. Free Play
     * has nobody to resign to; the modes with an opponent each add their own
     * rule — human-versus-AI's loser is the human, and a networked game's is
     * whichever side the sender was, which the outcome already carries.
     */
    if (out.end_reason == MXQ_END_REASON_RESIGNATION) {
        if (out.mode != MXQ_PLAY_MODE_HUMAN_VS_AI &&
            !mxq::networked_mode(out.mode)) {
            return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                          "\"resignation\" needs an opponent to resign to");
        }
        if (out.mode == MXQ_PLAY_MODE_HUMAN_VS_AI) {
            const MxqOutcome win_for_the_other_side =
                out.human_side == MXQ_COLOR_RED ? MXQ_OUTCOME_BLACK_WINS
                                                : MXQ_OUTCOME_RED_WINS;
            if (out.outcome != win_for_the_other_side) {
                return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                              "a resignation's outcome is the win for the side "
                              "opposite \"human_side\"");
            }
        }
    }
    /* The two ends two players declare to each other belong to the modes that
     * have two players. */
    if (is_agreed_reason(out.end_reason) && !mxq::networked_mode(out.mode)) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"agreed-draw\" and \"mutual-resignation\" are networked "
                      "end reasons");
    }
    /* A rule reason belongs to the kind of game whose rules produce it, both
     * ways round; see is_movement_rule_reason. The move class is the game's own
     * and is asked of the game rules_id named, which is why that member is read
     * before this one runs. */
    const bool placement =
        notation::move_class_of(out.game) == notation::MoveClass::Placement;
    if (is_placement_rule_reason(out.end_reason) && !placement) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"five-in-a-row\" and \"board-full\" are the placement "
                      "games' end reasons");
    }
    if (is_movement_rule_reason(out.end_reason) && placement) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "that end reason is one only a movement game's rules "
                      "reach");
    }
    /* Narrower than the partition above: two of the three movement games count
     * captureless play, and they count it to different numbers. Mini Xiangqi
     * counts nothing at all, so both refusals name the one game that reaches
     * their reason. */
    if (out.end_reason == MXQ_END_REASON_FIFTY_MOVE_RULE &&
        out.game != MXQ_GAME_KIND_XIANGQI) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"fifty-move-rule\" is Xiangqi's end reason");
    }
    if (out.end_reason == MXQ_END_REASON_FORTY_MOVE_RULE &&
        out.game != MXQ_GAME_KIND_JIEQI) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED,
                      "\"forty-move-rule\" is Jieqi's end reason");
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

/* import_bounds selects between the two callers this decoder has: an
 * import-facing entry point, which applies the accepted file-size and ply
 * bounds, and the store's own path back into a game it wrote, which must
 * not. Everything else about the ladder is identical, because a stored
 * document is a version 6 document like any other. */
bool decode(const uint8_t *bytes, size_t len, bool import_bounds, Decoded &out,
            Reject &err) {
    /* Stage 1: transport and size. */
    if (len == 0) {
        return reject(err, MXQ_ERR_ARCHIVE_MALFORMED, "the archive is empty");
    }
    if (import_bounds && len > kMaxArchiveBytes) {
        return reject(err, MXQ_ERR_ARCHIVE_TOO_LARGE,
                      "the archive is larger than the 1 MiB import limit");
    }

    /* Stage 2: strict UTF-8 and JSON syntax under the structural limits. */
    json::Value document;
    json::Error json_error{};
    if (!json::parse(bytes, len, import_bounds ? limits() : stored_limits(),
                     document, json_error)) {
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
    out->game = decoded.game;
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

void fill_stored(const Decoded &decoded, Stored &out) {
    out.archive_version = decoded.archive_version;
    out.game_id = decoded.game_id;
    out.config.struct_size = static_cast<uint32_t>(sizeof(MxqGameConfig));
    out.config.game = decoded.game;
    out.config.mode = decoded.mode;
    out.config.human_side = decoded.human_side;
    out.config.ai_level = decoded.ai_level;
    out.config.first_mover_choice = decoded.first_mover_choice;
    out.config.ai_movetime_ms = decoded.ai_movetime_ms;
    /* The archive carries no local side and never will, so decoding one always
     * answers absence. A caller that has a local perspective — resume, which
     * reads the store column beside the blob — sets it afterwards; a caller
     * that has none, such as an import preview, is right to leave it. */
    out.config.local_side = MXQ_COLOR_NONE;
    /* The document spells every start out; the configuration keeps the frozen
     * one as the empty string, which is the convention MxqGameConfig.start_fen
     * states. Normalising here is what makes a stored game's configuration read
     * the same before and after a resume — and re-encoding writes the start
     * back in full either way, so the bytes are unchanged by it. */
    if (!notation::has_frozen_start(decoded.game) ||
        decoded.start_fen != notation::start_fen(decoded.game)) {
        copy_bounded(out.config.start_fen, sizeof(out.config.start_fen),
                     decoded.start_fen.c_str());
    }
    out.moves = decoded.moves;
    out.deal_commit = decoded.deal_commit;
    out.deal_nonce = decoded.deal_nonce;
    out.deal_seed = decoded.deal_seed;
    out.started_at_ms = decoded.started_at_ms;
    out.written_at_ms = decoded.origin_written_at_ms;
    out.completed = decoded.completed;
    out.outcome = decoded.completed ? decoded.outcome : MXQ_OUTCOME_NONE;
    out.end_reason = decoded.completed ? decoded.end_reason
                                       : MXQ_END_REASON_NONE;
    out.ended_at_ms = decoded.completed ? decoded.ended_at_ms : 0;
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
 *   - the four declared reasons — resignation, ended-early, agreed-draw and
 *     mutual-resignation — require a non-terminal final position, because an
 *     unconfirmed natural result is always recorded as its actual result and an
 *     end the rules decided outranks one a player or a pair of players
 *     declared: a checkmate saved as "ended early" or agreed away as a draw
 *     would be a lost result, and the archive must refuse it rather than accept
 *     the loss;
 *   - every other reason is an automatic rule outcome, so the replay must
 *     report that same outcome, with the recorded outcome naming the same
 *     winner.
 *
 * The resignation winner rule is a cross-field one and is enforced before the
 * replay ever runs.
 */
MxqStatus check_terminal_pair(const Decoded &decoded,
                              const rules::Adjudication &adj, MxqError *err) {
    const std::string replayed = state_text(adj.state);

    if (decoded.end_reason == MXQ_END_REASON_RESIGNATION ||
        decoded.end_reason == MXQ_END_REASON_ENDED_EARLY ||
        is_agreed_reason(decoded.end_reason)) {
        if (terminal(adj.state)) {
            /* MxqError.detail is short by contract, so it says which rule was
             * broken rather than why the rule exists; the why is above. */
            fill_error(err, MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH,
                       ("the final position is " + replayed +
                        ", which a game the players ended cannot record")
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

/*
 * Stage 5, the rules tier, in one place because two entry points run it.
 *
 * The initial position must be one the game rules_id names begins from — the
 * per-game start policy, which is the setup-legality predicate asked through
 * mxq::setup::judge_start and is total over the five games: a xiangqi document
 * may carry any position that predicate accepts, a jieqi document carries a
 * dealt start, and every other game's carries exactly its frozen start, because
 * a game whose rules define neither a predicate nor a deal has no other
 * position to begin from. Then, where the document carries the evidence of a
 * deal, that evidence must be this game's; then every move must be legal in
 * sequence, then the recorded terminal pair must agree with the replayed
 * adjudication.
 *
 * The start is judged before anything is replayed, and that order is
 * load-bearing rather than tidy: an illegal setup can be a position offering
 * the capture of a general, and the engine asserts that no capture is one, so a
 * file reaching the replay first could take a build down instead of being
 * refused.
 *
 * Two rungs, two domains. A start that is not a position of this game's board
 * at all, or that carries counters a start cannot, is the file disagreeing with
 * itself — MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY, this stage's own voice. A start
 * that is a position of the board but not one the game may be set up in is the
 * setup question's answer wherever it is asked, so it carries that question's
 * own MXQ_ERR_RULES_ILLEGAL_POSITION.
 *
 * An archive that records no end has no terminal pair to agree with: an
 * unconfirmed natural terminal position remains the active game, so it is as
 * valid there as an ongoing one. mxq_archive_validate accepts that shape;
 * read_imported refuses it one stage earlier, for a reason that is about what
 * an import creates rather than about what the rules say.
 */
MxqStatus validate_rules_tier(const Decoded &decoded, MxqError *err) {
    {
        setup::Violation violation;
        std::string why;
        switch (setup::judge_start(decoded.game, decoded.start_fen.c_str(),
                                   violation, why)) {
        case setup::StartError::None:
            break;
        case setup::StartError::Structural:
        case setup::StartError::NotInitialised:
            fill_error(err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY,
                       ("\"start_fen\" is not a position this game begins "
                        "from: " +
                        why)
                           .c_str());
            return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
        case setup::StartError::Illegal:
            fill_error(err, MXQ_ERR_RULES_ILLEGAL_POSITION,
                       ("\"start_fen\" is not a position this game may be set "
                        "up in: " +
                        why)
                           .c_str());
            return MXQ_ERR_RULES_ILLEGAL_POSITION;
        }
    }

    /*
     * Then the deal, where the document carries the evidence of one: the seed
     * must hash to the commitment and the deal the seed and the nonce derive
     * must be the one start_fen spells. A file whose own evidence contradicts
     * its start is no record of the game it claims, which is the file
     * disagreeing with itself rather than the setup question being answered —
     * so it lands on this stage's own voice and not on the predicate's.
     *
     * It is asked after the start has been judged, because the comparison reads
     * the identities a dealt start spells and a position that is not a dealt
     * start has none to read.
     */
    if (!decoded.deal_commit.empty()) {
        std::string why;
        if (!deal::verify(decoded.deal_commit, decoded.deal_nonce,
                          decoded.deal_seed, decoded.start_fen.c_str(),
                          /*expected_digest=*/nullptr, why)) {
            fill_error(err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY,
                       ("the recorded deal is not this game's: " + why).c_str());
            return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
        }
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
    rules::Adjudication adj{};
    size_t first_illegal = 0;

    switch (rules::replay(decoded.game, decoded.start_fen.c_str(),
                          moves.empty() ? nullptr : moves.data(), moves.size(),
                          fen, in_check, ply, adj, nullptr, first_illegal,
                          detail)) {
    case rules::ReplayError::None:
        break;
    case rules::ReplayError::IllegalMove:
        fill_error_index(err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY,
                         ("the move line is not legal: " + detail).c_str(),
                         first_illegal);
        return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
    case rules::ReplayError::StartFenInvalid:
    case rules::ReplayError::NotInitialised:
        fill_error(err, MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY, detail.c_str());
        return MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY;
    case rules::ReplayError::Faulted:
        fill_error(err, MXQ_ERR_RESOURCE_ALLOCATION_FAILED, detail.c_str());
        return MXQ_ERR_RESOURCE_ALLOCATION_FAILED;
    }

    if (!decoded.completed) {
        return MXQ_OK;
    }
    return check_terminal_pair(decoded, adj, err);
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

/* The store's own path back in. Same ladder, same diagnostics, the two import
 * size bounds lifted; see mxq_archive_read.hpp for why they must be. */
MxqStatus read_stored(const uint8_t *bytes, size_t len, Stored &out,
                      MxqError *err) {
    out = Stored{};
    if (bytes == nullptr) {
        assert(false && "required bytes pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "bytes was null");
        return MXQ_ERR_ARG_NULL;
    }
    Decoded decoded;
    Reject rejected{};
    if (!decode(bytes, len, /*import_bounds=*/false, decoded, rejected)) {
        fill_error(err, rejected.status, rejected.detail.c_str());
        return rejected.status;
    }
    fill_stored(decoded, out);
    return MXQ_OK;
}

#if defined(MXQ_ENABLE_RULES_FACADE)

/* The importer's path in. Same ladder, every bound applied, the rules tier
 * run, and the one refusal that belongs to import rather than to the format;
 * see mxq_archive_read.hpp. */
MxqStatus read_imported(const uint8_t *bytes, size_t len, Stored &out,
                        MxqError *err) {
    out = Stored{};
    if (bytes == nullptr) {
        assert(false && "required bytes pointer was null");
        fill_error(err, MXQ_ERR_ARG_NULL, "bytes was null");
        return MXQ_ERR_ARG_NULL;
    }

    Decoded decoded;
    Reject rejected{};
    if (!decode(bytes, len, /*import_bounds=*/true, decoded, rejected)) {
        fill_error(err, rejected.status, rejected.detail.c_str());
        return rejected.status;
    }

    const MxqStatus rules = validate_rules_tier(decoded, err);
    if (rules != MXQ_OK) {
        return rules;
    }

    /*
     * And then the one refusal that is import's rather than the format's: an
     * exported file contains one immutable History game, and a document with no
     * terminal trio is the shape a stored *active* game has. Refusing it here
     * keeps the store's own "a record can only enter this library as imported
     * once it is complete" from being the thing that says so, which would be a
     * database error for a file problem.
     *
     * It comes last, after the accepted validation order has run entire, and
     * not among its stages. It is not one of them: those five decide whether
     * the bytes are a version 6 archive, and this decides whether that archive
     * is a game an import may file. Asking it earlier would mask a rejection
     * class the corpus names — an incomplete document with an illegal move
     * would be reported for the shape rather than for the move — and the answer
     * a file gets must not depend on which entry point asked.
     */
    if (!decoded.completed) {
        fill_error(err, MXQ_ERR_ARCHIVE_MALFORMED,
                   "the file records no end, and an imported game is always a "
                   "completed one");
        return MXQ_ERR_ARCHIVE_MALFORMED;
    }

    fill_stored(decoded, out);
    return MXQ_OK;
}

#endif /* MXQ_ENABLE_RULES_FACADE */

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
    if (!mxq::archive::decode(bytes, len, true, decoded, rejected)) {
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
    if (!mxq::archive::decode(bytes, len, true, decoded, rejected)) {
        mxq::fill_error(err, rejected.status, rejected.detail.c_str());
        return rejected.status;
    }

    /* Stage 5, the rules tier — the same one mxq_store_import runs, so a file
     * this call accepts is a file that import's validation accepts. */
    const MxqStatus rules = mxq::archive::validate_rules_tier(decoded, err);
    if (rules != MXQ_OK) {
        return rules;
    }

    mxq::archive::fill_info(decoded, out);
    return MXQ_OK;
}

MxqStatus MXQ_CALL mxq_archive_encode(MxqCore *core, const MxqGame *game,
                                      MxqBlob **out_blob, MxqError *err) {
    if (out_blob == nullptr) {
        assert(false && "required out pointer was null");
        mxq::fill_error(err, MXQ_ERR_ARG_NULL, "required out pointer was null");
        return MXQ_ERR_ARG_NULL;
    }
    /* Written before anything can fail, so that a caller reading *out_blob
     * after a rejection reads NULL rather than whatever it held. */
    *out_blob = nullptr;

    MxqStatus rc = mxq::require_core(core, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    rc = mxq::session::require(game, err);
    if (rc != MXQ_OK) {
        return rc;
    }
    if (game->core != core) {
        assert(false && "the session belongs to another core");
        mxq::fill_error(err, MXQ_ERR_ARG_INVALID_HANDLE,
                        "the session was not issued by this core");
        return MXQ_ERR_ARG_INVALID_HANDLE;
    }
    mxq::session::Owner owner(const_cast<MxqGame *>(game));
    if (!owner.held()) {
        return mxq::session::concurrent_use(err);
    }

    /* The classification derives from the committed game state and never from
     * the caller; for an active game there is none to derive, and the document
     * omits the terminal trio. */
    const mxq::archive::Record record = mxq::session::record_of(*game);
    const std::string content = mxq::archive::content_bytes(record);
    const std::string document = mxq::archive::document_bytes(record, content);

    auto *blob = new MxqBlob();
    blob->data = new uint8_t[document.size()];
    blob->len = document.size();
    std::memcpy(blob->data, document.data(), document.size());
    *out_blob = blob;
    return MXQ_OK;
}

#endif /* MXQ_ENABLE_RULES_FACADE */

} /* extern "C" */
