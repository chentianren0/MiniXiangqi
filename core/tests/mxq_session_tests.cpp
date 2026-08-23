/*
 * The session runner: store-attached sessions and their round trip through the
 * store, plus the core's own SHA-256.
 *
 * Two kinds of case, deliberately:
 *
 *   - the scenarios in fixtures/store/, which are data — a configuration, a
 *     move line, and what must be true of the game they make — so a new
 *     scenario is a new file and never a new function here;
 *   - named cases for what is a property of the interface rather than of a
 *     game: a second active game, a failed commit, a concurrent call, a
 *     tombstoned handle.
 *
 * Most of it runs through the public C surface only. Three things are reached
 * through the core's internal headers on purpose, and nothing else is:
 *
 *   - the clock and identity provider, to advance the deterministic identity
 *     sequence to the identifier a golden was minted with. The sequence
 *     restarts at every mxq_core_init, and the archive corpus gives each file
 *     its own identity, so without this a golden could only ever be reproduced
 *     if it happened to be the first game of its run;
 *   - the session's single-owner guard, so that "another thread is inside this
 *     session" can be arranged exactly rather than raced for. Holding the
 *     guard *is* being inside the session, so the concurrency case needs no
 *     test-only seam in the core and has no sleep in it;
 *   - a second SQLite connection, to take the database's write lock so that a
 *     commit fails for the reason a real one would.
 *
 * Without MXQ_ENABLE_RULES_FACADE the mxq_game_ functions are not in the
 * library at all — a session answers its queries by replaying — so every
 * session expectation reports NOT IMPLEMENTED, which is never counted as a
 * pass, and the SHA-256 vectors still run.
 */

#include "mxq.h"

#include "mxq_json.hpp"

#if MXQ_TEST_RULES_FACADE
#include "mxq_core_state.hpp" /* internal, deliberately: see above */
#include "mxq_session.hpp"    /* internal, deliberately: the owner guard */
#include "sqlite3.h"
#endif

#include "mxq_notation.hpp"
#include "mxq_deal.hpp"
#include "mxq_sha256.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;

#ifndef MXQ_TEST_RULES_FACADE
#define MXQ_TEST_RULES_FACADE 0
#endif

namespace {

int g_passed = 0;
int g_failed = 0;
int g_skipped = 0;
int g_checks = 0;

/* The one skip the closing banner speaks for, matched by value. Two things skip
 * here and they are two different absences: this one, and a scenario of a game
 * only a build with the second engine carries. A banner that fired on the total
 * announced that the session surface was missing from a build that had it,
 * which is a report about the build that is not true of it. */
const char *const kNoFacade = "the mxq_game_ functions need the rules facade";
int g_skipped_no_facade = 0;

/* ---------------------------------------------------------------------- */
/* One case's verdict                                                      */
/* ---------------------------------------------------------------------- */

struct Case {
    std::string              name;
    std::vector<std::string> messages;
    std::string              skip_reason;

    explicit Case(std::string n) : name(std::move(n)) {}

    void skip(const std::string &why) { skip_reason = why; }

    void check(bool ok, const std::string &what) {
        ++g_checks;
        if (!ok) {
            messages.push_back(what);
        }
    }

    void check_eq(const std::string &got, const std::string &want,
                  const std::string &what) {
        check(got == want,
              what + ": expected \"" + want + "\", got \"" + got + "\"");
    }

    void check_eq(int64_t got, int64_t want, const std::string &what) {
        check(got == want, what + ": expected " + std::to_string(want) +
                               ", got " + std::to_string(got));
    }

    void report() {
        if (!messages.empty()) {
            ++g_failed;
            std::cout << "  FAIL      " << name << "\n";
            for (const std::string &m : messages) {
                std::cout << "            " << m << "\n";
            }
            return;
        }
        if (!skip_reason.empty()) {
            ++g_skipped;
            if (skip_reason == kNoFacade) {
                ++g_skipped_no_facade;
            }
            std::cout << "  SKIP      " << name << "  (" << skip_reason << ")\n";
            return;
        }
        ++g_passed;
        std::cout << "  PASS      " << name << "\n";
    }
};

/* ---------------------------------------------------------------------- */
/* SHA-256, which needs no engine                                          */
/* ---------------------------------------------------------------------- */

/*
 * The published NIST vectors, plus the one-million-'a' vector that exercises
 * the block loop rather than the padding. The core carries its own SHA-256
 * because a content hash compared across platforms cannot come from two
 * libraries; these are what says it is the same function everyone else's is.
 */
void case_sha256_vectors() {
    Case c("sha-256 against the published vectors");

    struct Vector {
        std::string input;
        std::string digest;
    };
    const std::vector<Vector> vectors = {
        {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
        {"abc",
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        {"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"},
        {"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn"
         "hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"},
        /* 56 bytes: the padding boundary where the length no longer fits in
         * the block the message ends in. */
        {std::string(56, 'a'),
         "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"},
        {std::string(1000000, 'a'),
         "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"},
    };

    for (const Vector &v : vectors) {
        const std::string label = v.input.size() > 16
                                      ? std::to_string(v.input.size()) +
                                            " bytes"
                                      : "\"" + v.input + "\"";
        c.check_eq(mxq::sha256_hex(v.input), v.digest, label);
    }
    c.report();
}

/* ---------------------------------------------------------------------- */
/* The deal derivation, which needs no engine either                       */
/* ---------------------------------------------------------------------- */

/*
 * The cross-implementation anchor for docs/boardgame-protocol-v2.md's
 * derivation.
 *
 * Two devices playing one dealt game never send the deal: each derives it from
 * the seed and the nonce, and if they derive different deals they are playing
 * different games under one identifier. So this case is not a test of the C++
 * below it — it is the vector a second implementation is checked against, and
 * the Swift side that plays a nearby dealt game must reproduce every value
 * stated here byte for byte.
 *
 * Both vectors take the same seed, thirty-two zero bytes, because a vector
 * anyone can transcribe into any language is worth more here than a
 * plausible-looking one; nothing about the derivation is weaker for it, and a
 * seed is not a secret once the record is finished anyway.
 *
 * The first vector is the plain path, hand-executed:
 *
 *   seed   = 00 x32,  nonce = ff x32
 *   key    = SHA-256(seed ‖ nonce)
 *          = bba91ca85dc914b2ec3efb9e16e7267bf9193b14350d20fba8a8b406730ae30a
 *   block0 = SHA-256(key ‖ 0000000000000000)
 *          = 5d463d7be9f352db48287f649f880e85be31ccab6d461bc82de2539fe9da558d
 *   block1 = SHA-256(key ‖ 0000000000000001)
 *          = 9c84f01455bd9136c7224a5347a6fd9c8a888cbe9768b996aa357e4de2367c4b
 *
 * Red's permutation reads the stream from the front, four bytes a draw, for i
 * from 14 down to 1 with a value below i + 1 each time: 0x5d463d7b mod 15 = 2,
 * 0xe9f352db mod 14 = 13, 0x48287f64 mod 13 = 5, and so on through
 * 0x9768b996 mod 2 = 0, which is the fourteenth draw and the last. Black's
 * follows immediately, from the same stream and never rewound, so its first
 * draw is 0xaa357e4d mod 15 = 6 — the twenty-second four-byte group, which lies
 * inside block1. The two permutations that come out are
 *
 *   red   = [10, 8, 11, 4, 9, 14, 0, 12, 3, 6, 7, 1, 5, 13, 2]
 *   black = [11, 14, 1, 2, 8, 13, 12, 7, 0, 3, 10, 5, 4, 9, 6]
 *
 * and the pieces those item numbers name, laid onto each side's fifteen squares
 * in the protocol's order, are what the expectations below spell.
 *
 * The second vector exists for one branch the first cannot reach: rejection
 * sampling. With nonce a1444100…, the key is
 * 8bcc8f8794ce803a4c4193be621e2066a54e04460a59f914a9f3263dab2c0821 and Red's
 * seventh draw — a value below nine — takes 0xfffffffd, which is at or above
 * the largest multiple of nine that is at most 2^32 (4294967292) and must be
 * discarded. The next four bytes, 0x95ad55d8, give 8. An implementation that
 * took v mod n and skipped the discard derives a different deal from this pair
 * and fails here; the odds of a random pair reaching that branch are about two
 * in a hundred million, which is why the vector was searched for rather than
 * stumbled on.
 */
void case_deal_derivation() {
    Case c("the deal derivation, against its cross-implementation vectors");

    const std::string seed(64, '0');

    /* The commitment is SHA-256 of the seed's own bytes, which for this seed is
     * a value published in more than one place. */
    std::string commit;
    c.check(mxq::deal::commitment_of(seed, commit),
            "the commitment of thirty-two zero bytes");
    c.check_eq(commit,
               "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925",
               "commit = SHA-256(seed)");

    struct Vector {
        std::string nonce;
        std::string red;
        std::string black;
        std::string digest;
        std::string what;
    };
    const std::vector<Vector> vectors = {
        {std::string(64, 'f'), "PCPBCPRPNAARBPN", "pprncpparnpbbca",
         "ed1c9fb490c3d2f0e011e283c229b1408174109b7e632f8a0c01ac4541acb766",
         "the plain path"},
        {"a144410000000000000000000000000000000000000000000000000000000000",
         "CAPNAPRNPBPPCBR", "cpppaparrcbpnnb",
         "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea001baa",
         "a rejected draw"},
    };

    for (const Vector &v : vectors) {
        mxq::deal::Deal deal;
        std::string why;
        const bool derived = mxq::deal::derive(seed, v.nonce, deal, why);
        c.check(derived,
                v.what + ": the derivation refused its input: " + why);
        if (!derived) {
            continue;
        }
        std::string red(deal.red, deal.red + mxq::deal::kDealtPieces);
        std::string black(deal.black, deal.black + mxq::deal::kDealtPieces);
        c.check_eq(red, v.red, v.what + ": Red's fifteen, square by square");
        c.check_eq(black, v.black, v.what + ": Black's fifteen");
        c.check_eq(deal.digest, v.digest, v.what + ": the deal digest");
    }

    /* The squares those fifteen are laid onto, at both ends of both lists: the
     * order is the protocol's and a deal laid out in another one is another
     * game. */
    c.check_eq(std::string(mxq::deal::square_of(MXQ_COLOR_RED, 0)), "a1",
               "Red's first dealt square");
    c.check_eq(std::string(mxq::deal::square_of(MXQ_COLOR_RED, 14)), "i4",
               "Red's last dealt square");
    c.check_eq(std::string(mxq::deal::square_of(MXQ_COLOR_BLACK, 0)), "a7",
               "Black's first dealt square");
    c.check_eq(std::string(mxq::deal::square_of(MXQ_COLOR_BLACK, 14)), "i10",
               "Black's last dealt square");

    /* And the one spelling all four handshake values have. */
    c.check(mxq::deal::is_hex32(seed), "sixty-four lowercase hexadecimal");
    c.check(!mxq::deal::is_hex32(std::string(63, '0')), "sixty-three is not");
    c.check(!mxq::deal::is_hex32(std::string(64, 'F')), "uppercase is not");
    c.report();
}

#if MXQ_TEST_RULES_FACADE

/* ---------------------------------------------------------------------- */
/* Core and store scaffolding                                              */
/* ---------------------------------------------------------------------- */

std::string assets_dir() {
    if (const char *env = std::getenv("MXQ_ASSETS_DIR")) {
        return env;
    }
#if defined(MXQ_ASSETS_DIR_DEFAULT)
    return MXQ_ASSETS_DIR_DEFAULT;
#else
    return std::string();
#endif
}

MxqError make_error() {
    MxqError err;
    std::memset(&err, 0, sizeof(err));
    err.struct_size = static_cast<uint32_t>(sizeof(err));
    return err;
}

bool read_file(const fs::path &path, std::string &out) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    out.assign(std::istreambuf_iterator<char>(in),
               std::istreambuf_iterator<char>());
    return true;
}


fs::path scratch_root() {
    static const fs::path root = [] {
        std::random_device rd;
        char token[17];
        std::snprintf(token, sizeof(token), "%08x%08x", rd(), rd());
        return fs::temp_directory_path() /
               ("minixiangqi-session-tests-" + std::string(token));
    }();
    return root;
}

fs::path scratch_dir(const std::string &name) {
    const fs::path dir = scratch_root() / name;
    std::error_code ec;
    fs::remove_all(dir, ec);
    fs::create_directories(dir, ec);
    return dir;
}

MxqStatus init_core(const fs::path &store_dir, uint32_t flags, MxqCore **out,
                    MxqError *err) {
    const std::string assets = assets_dir();
    const std::string store = store_dir.string();
    MxqCoreConfig config;
    std::memset(&config, 0, sizeof(config));
    config.struct_size = static_cast<uint32_t>(sizeof(config));
    config.api_major = MXQ_API_VERSION_MAJOR;
    config.api_minor = MXQ_API_VERSION_MINOR;
    config.api_patch = MXQ_API_VERSION_PATCH;
    config.flags = flags;
    config.store_directory = store.c_str();
    config.asset_directory = assets.c_str();
    return mxq_core_init(&config, out, err);
}

MxqPosition make_position() {
    MxqPosition p;
    std::memset(&p, 0, sizeof(p));
    p.struct_size = static_cast<uint32_t>(sizeof(p));
    return p;
}

MxqGameStatus make_status() {
    MxqGameStatus s;
    std::memset(&s, 0, sizeof(s));
    s.struct_size = static_cast<uint32_t>(sizeof(s));
    return s;
}

MxqGameConfig make_config() {
    MxqGameConfig c;
    std::memset(&c, 0, sizeof(c));
    c.struct_size = static_cast<uint32_t>(sizeof(c));
    c.mode = MXQ_PLAY_MODE_FREE_PLAY;
    c.human_side = MXQ_COLOR_NONE;
    c.ai_level = MXQ_AI_LEVEL_NONE;
    c.first_mover_choice = MXQ_FIRST_MOVER_NONE;
    c.ai_movetime_ms = 0;
    c.local_side = MXQ_COLOR_NONE;
    return c;
}

/* ---------------------------------------------------------------------- */
/* Reading a scenario                                                      */
/* ---------------------------------------------------------------------- */

struct Scenario {
    std::string              title;
    MxqGameConfig            config = make_config();
    std::vector<std::string> moves;
    std::string              archive; /* a golden in fixtures/archive/valid */
    /* The wire session's deal, where the scenario's game has one. It is the
     * first member of this schema that belongs to a game rather than to a mode:
     * only the dealt game has a deal, and a scenario of it is created through
     * mxq_game_create_nearby, which is the entry the four values arrive in.
     * Empty means the scenario creates its game the ordinary way. */
    std::string              deal_commit;
    std::string              deal_nonce;
    std::string              deal_seed;
    std::string              deal_digest;
    /* Whether the scenario's game is one only a build with the second engine
     * carries. Which games a build carries is the build's, per mxq.h, so a
     * scenario of a game this one has not got is reported as not evaluated
     * rather than failed — the same posture the whole runner takes without the
     * first engine. */
    bool                     needs_gomoku = false;
    /* The status block, in the serialised vocabulary. */
    std::string              state;
    std::string              reason;
    int64_t                  at_occurrence = 0;
    bool                     claim_available = false;
    bool                     undo_available = false;
    int64_t                  undo_plies = 0;
    bool                     resign_available = false;
    bool                     search_expected = false;
    std::vector<int64_t>     undo;
};

std::string state_text(MxqGameState state) {
    switch (state) {
    case MXQ_GAME_ONGOING: return "ongoing";
    case MXQ_GAME_CLAIMABLE_DRAW: return "claimable-draw";
    case MXQ_GAME_RED_WINS: return "red-wins";
    case MXQ_GAME_BLACK_WINS: return "black-wins";
    case MXQ_GAME_DRAW: return "draw";
    default: break;
    }
    return "unknown(" + std::to_string(state) + ")";
}

std::string reason_text(MxqEndReason reason) {
    switch (reason) {
    case MXQ_END_REASON_NONE: return "null";
    case MXQ_END_REASON_CHECKMATE: return "checkmate";
    case MXQ_END_REASON_STALEMATE: return "stalemate";
    case MXQ_END_REASON_THREEFOLD_REPETITION: return "threefold-repetition";
    case MXQ_END_REASON_PERPETUAL_CHECK: return "perpetual-check";
    case MXQ_END_REASON_PERPETUAL_CHASE: return "perpetual-chase";
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK: return "mutual-perpetual-check";
    case MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE: return "mutual-perpetual-chase";
    case MXQ_END_REASON_RESIGNATION: return "resignation";
    case MXQ_END_REASON_ENDED_EARLY: return "ended-early";
    default: break;
    }
    return "unknown(" + std::to_string(reason) + ")";
}

bool read_scenario(const fs::path &path, Scenario &out, std::string &error) {
    std::string text;
    if (!read_file(path, text)) {
        error = "cannot read " + path.string();
        return false;
    }
    mxqtest::JsonValue root;
    if (!mxqtest::json_parse(text, root, error)) {
        return false;
    }
    if (!root.is_object()) {
        error = "the scenario is not a JSON object";
        return false;
    }

    const mxqtest::JsonValue *title = root.member("title");
    out.title = title != nullptr && title->is_string() ? title->string()
                                                       : path.stem().string();

    const mxqtest::JsonValue *config = root.member("config");
    if (config == nullptr || !config->is_object()) {
        error = "the scenario has no \"config\" object";
        return false;
    }
    const mxqtest::JsonValue *mode = config->member("mode");
    if (mode == nullptr || !mode->is_string()) {
        error = "\"config.mode\" is missing";
        return false;
    }
    if (mode->string() == "human-vs-ai") {
        out.config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
        const mxqtest::JsonValue *side = config->member("human_side");
        const mxqtest::JsonValue *level = config->member("ai_level");
        const mxqtest::JsonValue *movetime = config->member("ai_movetime_ms");
        const mxqtest::JsonValue *first = config->member("first_mover_choice");
        if (side == nullptr || level == nullptr || movetime == nullptr ||
            first == nullptr) {
            error = "a human-versus-AI scenario states human_side, ai_level, "
                    "ai_movetime_ms and first_mover_choice";
            return false;
        }
        out.config.human_side =
            side->string() == "red" ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
        out.config.ai_level = level->string() == "fast" ? MXQ_AI_LEVEL_FAST
                              : level->string() == "standard"
                                  ? MXQ_AI_LEVEL_STANDARD
                                  : MXQ_AI_LEVEL_DEEP;
        out.config.ai_movetime_ms =
            static_cast<uint32_t>(movetime->number());
        out.config.first_mover_choice =
            first->string() == "human-first"  ? MXQ_FIRST_MOVER_HUMAN_FIRST
            : first->string() == "ai-first"   ? MXQ_FIRST_MOVER_AI_FIRST
                                              : MXQ_FIRST_MOVER_RANDOM;
    } else if (mode->string() == "nearby" || mode->string() == "online") {
        out.config.mode = mode->string() == "nearby" ? MXQ_PLAY_MODE_NEARBY
                                                     : MXQ_PLAY_MODE_ONLINE;
        /* Local perspective is store metadata rather than archive content, and
         * a networked game is played from one of the two sides of this device,
         * so a networked scenario states which. */
        const mxqtest::JsonValue *local = config->member("local_side");
        if (local == nullptr || !local->is_string() ||
            (local->string() != "red" && local->string() != "black")) {
            error = "a networked scenario states \"config.local_side\"";
            return false;
        }
        out.config.local_side =
            local->string() == "red" ? MXQ_COLOR_RED : MXQ_COLOR_BLACK;
    } else if (mode->string() != "free-play") {
        error = "\"config.mode\" is not one of the accepted modes";
        return false;
    }

    /* The position the game begins from, where the scenario composes one.
     * Absent is the game's frozen start, exactly as the empty member is on the
     * other side of the interface — a scenario says where it begins only when
     * that is something to say. */
    if (const mxqtest::JsonValue *start = config->member("start_fen")) {
        if (!start->is_string()) {
            error = "\"config.start_fen\" is not a string";
            return false;
        }
        if (start->string().size() >= sizeof(out.config.start_fen)) {
            error = "\"config.start_fen\" is longer than the interface carries";
            return false;
        }
        std::memcpy(out.config.start_fen, start->string().c_str(),
                    start->string().size() + 1);
    }

    /* The game the scenario is of. Required rather than defaulted: a scenario
     * that did not say would be replayed under whichever game the runner
     * happened to pick, which is the one thing a many-game corpus must not
     * do. */
    {
        const mxqtest::JsonValue *game = config->member("game");
        if (game == nullptr || !game->is_string()) {
            error = "\"config.game\" is missing";
            return false;
        }
        if (game->string() == "minixiangqi") {
            out.config.game = MXQ_GAME_KIND_MINI_XIANGQI;
        } else if (game->string() == "xiangqi") {
            out.config.game = MXQ_GAME_KIND_XIANGQI;
        } else if (game->string() == "gomoku-15") {
            out.config.game = MXQ_GAME_KIND_GOMOKU_15;
            out.needs_gomoku = true;
        } else if (game->string() == "renju") {
            out.config.game = MXQ_GAME_KIND_RENJU;
            out.needs_gomoku = true;
        } else if (game->string() == "jieqi") {
            out.config.game = MXQ_GAME_KIND_JIEQI;
        } else {
            error = "\"config.game\" is not one of the accepted games";
            return false;
        }
    }

    /* The deal the scenario's game was dealt, where it has one: the four
     * values the protocol's handshake left behind, each sixty-four lowercase
     * hexadecimal digits. A scenario that states them is created over a wire
     * session carrying them, which is the only way a dealt game reaches the
     * store with the evidence its record must hold. */
    if (const mxqtest::JsonValue *deal = root.member("deal")) {
        const auto value = [&](const char *name) {
            const mxqtest::JsonValue *v = deal->member(name);
            return v != nullptr && v->is_string() ? v->string() : std::string();
        };
        out.deal_commit = value("commit");
        out.deal_nonce = value("nonce");
        out.deal_seed = value("seed");
        out.deal_digest = value("digest");
        if (out.deal_commit.size() != 64 || out.deal_nonce.size() != 64 ||
            out.deal_seed.size() != 64 || out.deal_digest.size() != 64) {
            error = "a scenario's \"deal\" states four 64-digit values";
            return false;
        }
    }

    if (const mxqtest::JsonValue *moves = root.member("moves")) {
        for (const mxqtest::JsonValue &move : moves->array()) {
            out.moves.push_back(move.string());
        }
    }
    if (const mxqtest::JsonValue *archive = root.member("archive")) {
        out.archive = archive->string();
    }

    const mxqtest::JsonValue *status = root.member("status");
    if (status == nullptr || !status->is_object()) {
        error = "the scenario has no \"status\" object";
        return false;
    }
    const auto text_member = [&](const char *name) {
        const mxqtest::JsonValue *v = status->member(name);
        if (v == nullptr || v->is_null()) {
            return std::string("null");
        }
        return v->string();
    };
    const auto bool_member = [&](const char *name) {
        const mxqtest::JsonValue *v = status->member(name);
        return v != nullptr && v->is_bool() && v->boolean();
    };
    const auto number_member = [&](const char *name) {
        const mxqtest::JsonValue *v = status->member(name);
        return v != nullptr && v->is_number()
                   ? static_cast<int64_t>(v->number())
                   : 0;
    };
    out.state = text_member("state");
    out.reason = text_member("reason");
    out.at_occurrence = number_member("at_occurrence");
    out.claim_available = bool_member("claim_available");
    out.undo_available = bool_member("undo_available");
    out.undo_plies = number_member("undo_plies");
    out.resign_available = bool_member("resign_available");
    out.search_expected = bool_member("search_expected");

    if (const mxqtest::JsonValue *undo = root.member("undo")) {
        for (const mxqtest::JsonValue &plies : undo->array()) {
            out.undo.push_back(static_cast<int64_t>(plies.number()));
        }
    }
    return true;
}

/* ---------------------------------------------------------------------- */
/* Small readers over a live session                                       */
/* ---------------------------------------------------------------------- */

std::vector<std::string> history_of(const MxqGame *game, Case &c,
                                    const std::string &where) {
    size_t count = 0;
    MxqError err = make_error();
    MxqStatus rc = mxq_game_move_history(game, nullptr, 0, &count, &err);
    if (count == 0) {
        c.check(rc == MXQ_OK, where + ": an empty history is MXQ_OK, got " +
                                  mxq_status_name(rc));
        return {};
    }
    c.check(rc == MXQ_ERR_ARG_BUFFER_TOO_SMALL,
            where + ": asking for the count alone is buffer-too-small, got " +
                std::string(mxq_status_name(rc)));
    c.check_eq(static_cast<int64_t>(err.required_size),
               static_cast<int64_t>(count),
               where + ": required_size names the count");

    std::vector<MxqMove> moves(count);
    for (MxqMove &move : moves) {
        std::memset(&move, 0, sizeof(move));
        move.struct_size = static_cast<uint32_t>(sizeof(move));
    }
    err = make_error();
    rc = mxq_game_move_history(game, moves.data(), moves.size(), &count, &err);
    c.check(rc == MXQ_OK, where + ": mxq_game_move_history failed: " +
                              std::string(mxq_status_name(rc)));
    std::vector<std::string> out;
    out.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        out.push_back(moves[i].text);
    }
    return out;
}

std::string game_id_of(const MxqGame *game, Case &c, const std::string &where) {
    char buffer[MXQ_GAME_ID_CAP];
    size_t len = 0;
    MxqError err = make_error();
    const MxqStatus rc =
        mxq_game_id(game, buffer, sizeof(buffer), &len, &err);
    c.check(rc == MXQ_OK,
            where + ": mxq_game_id failed: " + std::string(mxq_status_name(rc)));
    if (rc != MXQ_OK) {
        return std::string();
    }
    c.check_eq(static_cast<int64_t>(len), 36, where + ": the identity's length");
    return std::string(buffer);
}

std::string encode_of(MxqCore *core, const MxqGame *game, Case &c,
                      const std::string &where) {
    MxqBlob *blob = nullptr;
    MxqError err = make_error();
    const MxqStatus rc = mxq_archive_encode(core, game, &blob, &err);
    c.check(rc == MXQ_OK, where + ": mxq_archive_encode failed: " +
                              std::string(mxq_status_name(rc)) + ": " +
                              err.detail);
    if (rc != MXQ_OK) {
        return std::string();
    }
    const std::string bytes(
        reinterpret_cast<const char *>(mxq_blob_bytes(blob)),
        mxq_blob_len(blob));
    mxq_blob_release(blob);
    return bytes;
}

/* The whole status block, as the scenario spells it, so a mismatch names the
 * field rather than the struct. */
void check_status(Case &c, const MxqGame *game, const Scenario &scenario,
                  const std::string &where) {
    MxqGameStatus status = make_status();
    MxqError err = make_error();
    const MxqStatus rc = mxq_game_status(game, &status, &err);
    c.check(rc == MXQ_OK, where + ": mxq_game_status failed: " +
                              std::string(mxq_status_name(rc)));
    if (rc != MXQ_OK) {
        return;
    }
    c.check_eq(state_text(status.state), scenario.state, where + ": state");
    c.check_eq(reason_text(status.reason), scenario.reason, where + ": reason");
    c.check_eq(status.at_occurrence, scenario.at_occurrence,
               where + ": at_occurrence");
    c.check_eq(status.claim_available, scenario.claim_available ? 1 : 0,
               where + ": claim_available");
    c.check_eq(status.undo_available, scenario.undo_available ? 1 : 0,
               where + ": undo_available");
    c.check_eq(status.undo_plies, scenario.undo_plies, where + ": undo_plies");
    c.check_eq(status.resign_available, scenario.resign_available ? 1 : 0,
               where + ": resign_available");
    c.check_eq(status.search_expected, scenario.search_expected ? 1 : 0,
               where + ": search_expected");

    /* Whose turn it is, against the position's own answer rather than against a
     * transcription here. The scenario states no side to move for the same
     * reason it states no FEN: the position is already compared with the
     * session-free facade, so the assertion worth making is that the two
     * reports of one fact agree — and one of them is what the Play home reads
     * from mxq_store_active_summary, where no position is returned at all. */
    MxqPosition position = make_position();
    err = make_error();
    if (mxq_game_position(game, &position, &err) == MXQ_OK) {
        c.check_eq(status.side_to_move, position.side_to_move,
                   where + ": the status and the position name one side to "
                           "move");
    }
}

void check_config(Case &c, const MxqGame *game, const Scenario &scenario,
                  const std::string &where) {
    MxqGameConfig config = make_config();
    MxqError err = make_error();
    const MxqStatus rc = mxq_game_config(game, &config, &err);
    c.check(rc == MXQ_OK, where + ": mxq_game_config failed: " +
                              std::string(mxq_status_name(rc)));
    if (rc != MXQ_OK) {
        return;
    }
    c.check_eq(config.game, scenario.config.game, where + ": game");
    c.check_eq(config.mode, scenario.config.mode, where + ": mode");
    c.check_eq(config.human_side, scenario.config.human_side,
               where + ": human_side");
    c.check_eq(config.ai_level, scenario.config.ai_level, where + ": ai_level");
    c.check_eq(config.first_mover_choice, scenario.config.first_mover_choice,
               where + ": first_mover_choice");
    c.check_eq(config.ai_movetime_ms, scenario.config.ai_movetime_ms,
               where + ": ai_movetime_ms");
    /* The one configuration member the archive does not carry. Comparing it
     * after the resume is the assertion that matters: local perspective
     * survives a close and a reopen through the store's own column, and the
     * blob it is not in cannot be what carried it. */
    c.check_eq(config.local_side, scenario.config.local_side,
               where + ": local_side");
    /* Where the game began. Reading it back after the resume is the assertion
     * that matters: a composed start survives a close and a reopen through the
     * document alone, and a build that substituted the frozen array on the way
     * back would answer here with a position the scenario never named. */
    c.check_eq(std::string(config.start_fen),
               std::string(scenario.config.start_fen), where + ": start_fen");
}

/*
 * The position, and every prefix of it, against the session-free facade.
 *
 * mxq_rules_evaluate over the same (start_fen, moves) prefix is the surface
 * fixtures/rules already gates, so comparing against it is comparing against
 * the conformance corpus rather than against a FEN transcribed into a second
 * file here.
 */
void check_positions(Case &c, MxqCore *core, const MxqGameConfig &config,
                     const MxqGame *game,
                     const std::vector<std::string> &moves,
                     const std::string &where) {
    const MxqGameKind kind = config.game;
    char start_fen[MXQ_FEN_CAP];
    start_fen[0] = '\0';
    size_t fen_len = 0;
    /* The scenario's own start where it has one, and the game's frozen start
     * where it has none. The empty member means the frozen start, so this is
     * the same convention the core applies and not a second reading of it —
     * and the two are asked in this order rather than the other way round
     * because a game with no frozen start is a programming error to ask: it
     * answers MXQ_ERR_ARG_RANGE, and where NDEBUG is undefined it asserts. A
     * dealt game is that game, and its configuration always names its start. */
    if (config.start_fen[0] != '\0') {
        std::memcpy(start_fen, config.start_fen,
                    std::strlen(config.start_fen) + 1);
    } else {
        mxq_rules_start_fen(kind, start_fen, sizeof(start_fen), &fen_len,
                            nullptr);
    }

    for (size_t ply = 0; ply <= moves.size(); ++ply) {
        std::vector<const char *> texts;
        texts.reserve(ply);
        for (size_t i = 0; i < ply; ++i) {
            texts.push_back(moves[i].c_str());
        }

        MxqPosition expected = make_position();
        MxqGameStatus expected_status = make_status();
        MxqError err = make_error();
        MxqStatus rc = mxq_rules_evaluate(core, kind, start_fen,
                                          texts.empty() ? nullptr : texts.data(),
                                          texts.size(), &expected,
                                          &expected_status, nullptr, &err);
        c.check(rc == MXQ_OK, where + ": the facade could not evaluate the "
                                      "prefix of length " +
                                  std::to_string(ply));
        if (rc != MXQ_OK) {
            return;
        }

        MxqPosition got = make_position();
        err = make_error();
        rc = mxq_game_position_at(game, static_cast<uint32_t>(ply), &got, &err);
        c.check(rc == MXQ_OK, where + ": mxq_game_position_at(" +
                                  std::to_string(ply) + ") failed: " +
                                  std::string(mxq_status_name(rc)));
        if (rc != MXQ_OK) {
            continue;
        }
        c.check_eq(std::string(got.fen), std::string(expected.fen),
                   where + ": the FEN at ply " + std::to_string(ply));
        c.check_eq(got.ply_count, static_cast<int64_t>(ply),
                   where + ": ply_count at ply " + std::to_string(ply));
        c.check_eq(got.side_to_move, expected.side_to_move,
                   where + ": side to move at ply " + std::to_string(ply));
        /* The facade's two output shapes report one side to move. Asked here
         * rather than in a case of its own because a scenario beginning from a
         * composed position runs every ply of it with Black to move at the
         * even ones, and a member nothing writes reads Red. */
        c.check_eq(expected_status.side_to_move, expected.side_to_move,
                   where + ": the facade's status and position name one side "
                           "to move at ply " +
                       std::to_string(ply));
        c.check_eq(got.in_check, expected.in_check,
                   where + ": in_check at ply " + std::to_string(ply));

        if (ply == moves.size()) {
            MxqPosition current = make_position();
            err = make_error();
            rc = mxq_game_position(game, &current, &err);
            c.check(rc == MXQ_OK, where + ": mxq_game_position failed");
            if (rc == MXQ_OK) {
                c.check_eq(std::string(current.fen), std::string(expected.fen),
                           where + ": the current FEN");
                c.check_eq(current.ply_count, static_cast<int64_t>(ply),
                           where + ": the current ply count");
            }
        }
    }

    /* One past the end is out of range, which a scrubber may legitimately
     * ask. */
    MxqPosition beyond = make_position();
    MxqError err = make_error();
    const MxqStatus rc = mxq_game_position_at(
        game, static_cast<uint32_t>(moves.size() + 1), &beyond, &err);
    c.check(rc == MXQ_ERR_ARG_RANGE,
            where + ": a ply beyond the retained line is MXQ_ERR_ARG_RANGE, "
                    "got " +
                std::string(mxq_status_name(rc)));
}

/* The legal-move set, against the same facade, plus the from-square filter. */
void check_legal_moves(Case &c, MxqCore *core, const MxqGameConfig &config,
                       const MxqGame *game,
                       const std::vector<std::string> &moves,
                       const std::string &where) {
    const MxqGameKind kind = config.game;
    char start_fen[MXQ_FEN_CAP];
    start_fen[0] = '\0';
    size_t fen_len = 0;
    /* The scenario's start before the frozen one, for the reason check_positions
     * states: asking a game with no frozen start asserts where NDEBUG is
     * undefined. */
    if (config.start_fen[0] != '\0') {
        std::memcpy(start_fen, config.start_fen,
                    std::strlen(config.start_fen) + 1);
    } else {
        mxq_rules_start_fen(kind, start_fen, sizeof(start_fen), &fen_len,
                            nullptr);
    }

    std::vector<const char *> texts;
    texts.reserve(moves.size());
    for (const std::string &move : moves) {
        texts.push_back(move.c_str());
    }

    size_t expected_count = 0;
    MxqError err = make_error();
    mxq_rules_legal_moves(core, kind, start_fen,
                          texts.empty() ? nullptr : texts.data(), texts.size(),
                          nullptr, 0, &expected_count, &err);
    std::vector<MxqMove> expected(expected_count);
    for (MxqMove &move : expected) {
        std::memset(&move, 0, sizeof(move));
        move.struct_size = static_cast<uint32_t>(sizeof(move));
    }
    err = make_error();
    MxqStatus rc = mxq_rules_legal_moves(
        core, kind, start_fen,
        texts.empty() ? nullptr : texts.data(), texts.size(),
        expected.data(), expected.size(), &expected_count, &err);
    c.check(rc == MXQ_OK, where + ": the facade could not list legal moves");

    size_t count = 0;
    err = make_error();
    rc = mxq_game_legal_moves(game, nullptr, 0, &count, &err);
    c.check(rc == MXQ_ERR_ARG_BUFFER_TOO_SMALL,
            where + ": asking for the count alone is buffer-too-small");
    c.check_eq(static_cast<int64_t>(count),
               static_cast<int64_t>(expected_count),
               where + ": the number of legal moves");

    std::vector<MxqMove> got(count);
    for (MxqMove &move : got) {
        std::memset(&move, 0, sizeof(move));
        move.struct_size = static_cast<uint32_t>(sizeof(move));
    }
    err = make_error();
    rc = mxq_game_legal_moves(game, got.data(), got.size(), &count, &err);
    c.check(rc == MXQ_OK, where + ": mxq_game_legal_moves failed");

    std::vector<std::string> from_facade;
    for (const MxqMove &move : expected) {
        from_facade.push_back(move.text);
    }
    std::vector<std::string> from_session;
    for (size_t i = 0; i < count; ++i) {
        from_session.push_back(got[i].text);
    }
    std::sort(from_facade.begin(), from_facade.end());
    std::sort(from_session.begin(), from_session.end());
    c.check(from_facade == from_session,
            where + ": the session's legal-move set is the facade's");

    /* The from-square filter is exactly the subset with that origin, and a
     * square with nothing on it is a count of zero rather than an error.
     *
     * Which prefix of a move is its origin is the game's own answer, asked of
     * the notation rather than taken as two characters: "a1" is a prefix of
     * "a10" as text and not a square of it, so a fixed-width comparison counts
     * a tenth or a fifteenth rank's moves as another square's. */
    if (!from_facade.empty()) {
        const std::string &first = from_facade.front();
        const size_t width = mxq::notation::square_length(
            kind, first.data(), first.size());
        const std::string square = first.substr(0, width);
        size_t expected_here = 0;
        for (const std::string &move : from_facade) {
            if (mxq::notation::move_begins_at(kind, move,
                                              square.c_str())) {
                ++expected_here;
            }
        }
        std::vector<MxqMove> here(expected_here);
        for (MxqMove &move : here) {
            std::memset(&move, 0, sizeof(move));
            move.struct_size = static_cast<uint32_t>(sizeof(move));
        }
        size_t here_count = 0;
        err = make_error();
        rc = mxq_game_legal_moves_from(game, square.c_str(), here.data(),
                                       here.size(), &here_count, &err);
        c.check(rc == MXQ_OK, where + ": mxq_game_legal_moves_from failed");
        c.check_eq(static_cast<int64_t>(here_count),
                   static_cast<int64_t>(expected_here),
                   where + ": the moves from " + square);
    }
}

/* The wire session a dealt scenario is created over: a session at its birth,
 * carrying the deal the scenario states and nothing else that matters. */
MxqNearbySession nearby_session_of(const Scenario &scenario,
                                   const char *session_id,
                                   const char *peer_id) {
    MxqNearbySession wire;
    std::memset(&wire, 0, sizeof(wire));
    wire.struct_size = static_cast<uint32_t>(sizeof(wire));
    wire.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
    wire.sent_end = MXQ_NEARBY_TERMINAL_NONE;
    std::memcpy(wire.session_id, session_id, std::strlen(session_id) + 1);
    std::memcpy(wire.peer_id, peer_id, std::strlen(peer_id) + 1);
    std::memcpy(wire.deal_commit, scenario.deal_commit.c_str(), 65);
    std::memcpy(wire.deal_nonce, scenario.deal_nonce.c_str(), 65);
    std::memcpy(wire.deal_seed, scenario.deal_seed.c_str(), 65);
    std::memcpy(wire.deal_digest, scenario.deal_digest.c_str(), 65);
    return wire;
}

/* The deal a session reports, compared against the one the scenario dealt it.
 * Asked after the resume above all: the four values are the store's own row and
 * not the document's, and a resumed session re-verifies its deal against all of
 * them before it exists at all. */
void check_deal(Case &c, const MxqGame *game, const Scenario &scenario,
                const std::string &where) {
    MxqNearbySession wire;
    std::memset(&wire, 0, sizeof(wire));
    wire.struct_size = static_cast<uint32_t>(sizeof(wire));
    uint8_t exists = 0;
    MxqError err = make_error();
    const MxqStatus rc = mxq_game_nearby_session(game, &wire, &exists, &err);
    c.check(rc == MXQ_OK, where + ": mxq_game_nearby_session failed: " +
                              std::string(mxq_status_name(rc)));
    c.check(exists == 1, where + ": the dealt game carries its wire session");
    if (rc != MXQ_OK || exists == 0) {
        return;
    }
    c.check_eq(std::string(wire.deal_commit), scenario.deal_commit,
               where + ": deal_commit");
    c.check_eq(std::string(wire.deal_nonce), scenario.deal_nonce,
               where + ": deal_nonce");
    c.check_eq(std::string(wire.deal_seed), scenario.deal_seed,
               where + ": deal_seed");
    c.check_eq(std::string(wire.deal_digest), scenario.deal_digest,
               where + ": deal_digest");
}

/* ---------------------------------------------------------------------- */
/* The deterministic identity sequence                                     */
/* ---------------------------------------------------------------------- */

/*
 * The index a deterministic identifier carries: the counter is spelled in the
 * final 62 bits, so the last group of the UUID is it. Advancing the provider
 * to that index is how a golden minted as the corpus's third game can be
 * reproduced by a run that would otherwise mint its first.
 */
bool advance_identity_to(MxqCore *core, const std::string &game_id,
                         std::string &error) {
    const size_t dash = game_id.rfind('-');
    if (dash == std::string::npos) {
        error = "the golden's game_id is not a UUID";
        return false;
    }
    const unsigned long long index =
        std::strtoull(game_id.substr(dash + 1).c_str(), nullptr, 16);
    if (index > 1024) {
        error = "the golden's identity index is implausibly far along";
        return false;
    }
    for (unsigned long long i = 0; i < index; ++i) {
        core->identity.next_game_id();
    }
    return true;
}

/* ---------------------------------------------------------------------- */
/* The scenario round trip                                                 */
/* ---------------------------------------------------------------------- */

void run_scenario(const fs::path &path, const fs::path &archives) {
    Scenario scenario;
    std::string error;
    Case c(path.stem().string());
    if (!read_scenario(path, scenario, error)) {
        c.check(false, "cannot read the scenario: " + error);
        c.report();
        return;
    }
    c.name = path.stem().string() + " — " + scenario.title;

#if !MXQ_TEST_GOMOKU_FACADE
    if (scenario.needs_gomoku) {
        c.skip("the placement games need the second engine");
        c.report();
        return;
    }
#endif

    std::string golden;
    if (!scenario.archive.empty() &&
        !read_file(archives / "valid" / scenario.archive, golden)) {
        c.check(false, "cannot read the golden " + scenario.archive);
        c.report();
        return;
    }

    const fs::path store = scratch_dir(path.stem().string());

    /* ---- the first lifetime: create, play, encode ---- */
    MxqCore *core = nullptr;
    MxqError err = make_error();
    MxqStatus rc = init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core,
                             &err);
    c.check(rc == MXQ_OK, std::string("mxq_core_init failed: ") + err.detail);
    if (rc != MXQ_OK) {
        c.report();
        return;
    }

    if (!golden.empty()) {
        const size_t at = golden.find("\"game_id\":\"");
        if (at == std::string::npos ||
            !advance_identity_to(core, golden.substr(at + 11, 36), error)) {
            c.check(false, "cannot align the identity sequence: " + error);
            mxq_core_shutdown(core, nullptr);
            c.report();
            return;
        }
    }

    MxqGame *game = nullptr;
    err = make_error();
    if (scenario.deal_commit.empty()) {
        rc = mxq_game_create(core, &scenario.config, &game, &err);
        c.check(rc == MXQ_OK, std::string("mxq_game_create failed: ") +
                                  mxq_status_name(rc) + ": " + err.detail);
    } else {
        /* A dealt game is created over the wire session its deal arrived in:
         * three of those four values are its record's own evidence, and this
         * entry is where they reach the document. The two identifiers are the
         * runner's, because nothing about them is compared — they are device
         * bookkeeping the archive deliberately never carries. */
        const MxqNearbySession wire =
            nearby_session_of(scenario, "session-of-the-dealt-scenario",
                              "peer-of-the-dealt-scenario");
        rc = mxq_game_create_nearby(core, &scenario.config, &wire, &game, &err);
        c.check(rc == MXQ_OK, std::string("mxq_game_create_nearby failed: ") +
                                  mxq_status_name(rc) + ": " + err.detail);
    }
    if (rc != MXQ_OK) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }

    MxqPosition created = make_position();
    mxq_game_position(game, &created, nullptr);
    c.check_eq(created.ply_count, 0, "a created game has no moves");
    c.check_eq(static_cast<int64_t>(created.position_revision), 0,
               "a created game is at revision 0");

    for (size_t i = 0; i < scenario.moves.size(); ++i) {
        MxqPosition after = make_position();
        MxqGameStatus status = make_status();
        err = make_error();
        rc = mxq_game_apply_move(game, scenario.moves[i].c_str(), &after,
                                 &status, &err);
        c.check(rc == MXQ_OK, "move " + std::to_string(i) + " (" +
                                  scenario.moves[i] + ") was refused: " +
                                  std::string(mxq_status_name(rc)) + ": " +
                                  err.detail);
        if (rc != MXQ_OK) {
            break;
        }
        c.check_eq(after.ply_count, static_cast<int64_t>(i + 1),
                   "the ply count after move " + std::to_string(i));
        c.check_eq(static_cast<int64_t>(after.position_revision),
                   static_cast<int64_t>(i + 1),
                   "the revision after move " + std::to_string(i));
    }

    const std::string id_before = game_id_of(game, c, "before the close");
    check_config(c, game, scenario, "before the close");
    if (!scenario.deal_commit.empty()) {
        check_deal(c, game, scenario, "before the close");
    }
    check_status(c, game, scenario, "before the close");
    check_positions(c, core, scenario.config, game, scenario.moves, "before the close");
    check_legal_moves(c, core, scenario.config, game, scenario.moves, "before the close");
    const std::vector<std::string> history_before =
        history_of(game, c, "before the close");
    c.check(history_before == scenario.moves,
            "the retained line before the close is the scenario's");

    const std::string encoded = encode_of(core, game, c, "before the close");
    c.check(encode_of(core, game, c, "re-encoded") == encoded,
            "encoding the same committed state twice produces the same bytes");
    if (!golden.empty()) {
        c.check_eq(encoded, golden,
                   "the encoded session is the golden " + scenario.archive);
    }

    /* What was encoded must be readable by both entry points, because the
     * writer and the reader are one contract. */
    MxqArchiveInfo info;
    std::memset(&info, 0, sizeof(info));
    info.struct_size = static_cast<uint32_t>(sizeof(info));
    err = make_error();
    rc = mxq_archive_probe(core,
                           reinterpret_cast<const uint8_t *>(encoded.data()),
                           encoded.size(), &info, &err);
    c.check(rc == MXQ_OK, std::string("the encoded session does not probe: ") +
                              mxq_status_name(rc) + ": " + err.detail);
    c.check_eq(static_cast<int64_t>(info.move_count),
               static_cast<int64_t>(scenario.moves.size()),
               "the probed move count");
    c.check_eq(std::string(info.game_id), id_before, "the probed identity");
    c.check_eq(info.end_reason, MXQ_END_REASON_NONE,
               "an active game's archive records no end");

    std::memset(&info, 0, sizeof(info));
    info.struct_size = static_cast<uint32_t>(sizeof(info));
    err = make_error();
    rc = mxq_archive_validate(core,
                              reinterpret_cast<const uint8_t *>(encoded.data()),
                              encoded.size(), &info, &err);
    c.check(rc == MXQ_OK,
            std::string("the encoded session does not validate: ") +
                mxq_status_name(rc) + ": " + err.detail);

    mxq_game_release(game);
    game = nullptr;
    mxq_core_shutdown(core, nullptr);
    core = nullptr;

    /* ---- the second lifetime: resume and compare ---- */
    err = make_error();
    rc = init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err);
    c.check(rc == MXQ_OK, std::string("reopening the store failed: ") +
                              err.detail);
    if (rc != MXQ_OK) {
        c.report();
        return;
    }

    uint8_t exists = 0;
    err = make_error();
    rc = mxq_game_resume_active(core, &game, &exists, &err);
    c.check(rc == MXQ_OK, std::string("mxq_game_resume_active failed: ") +
                              mxq_status_name(rc) + ": " + err.detail);
    c.check(exists == 1, "the active game is there after the reopen");
    if (rc != MXQ_OK || exists == 0) {
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }

    c.check_eq(game_id_of(game, c, "after the resume"), id_before,
               "the identity survives the round trip");
    check_config(c, game, scenario, "after the resume");
    if (!scenario.deal_commit.empty()) {
        check_deal(c, game, scenario, "after the resume");
    }
    check_status(c, game, scenario, "after the resume");
    check_positions(c, core, scenario.config, game, scenario.moves, "after the resume");
    const std::vector<std::string> history_after =
        history_of(game, c, "after the resume");
    c.check(history_after == history_before,
            "the retained line survives the round trip");
    c.check_eq(encode_of(core, game, c, "after the resume"), encoded,
               "the resumed session encodes to the same bytes");

    /* ---- undo, to the start and past it ---- */
    size_t remaining = scenario.moves.size();
    for (size_t i = 0; i < scenario.undo.size(); ++i) {
        uint32_t removed = 0;
        err = make_error();
        rc = mxq_game_undo(game, &removed, &err);
        c.check(rc == MXQ_OK, "undo " + std::to_string(i) + " failed: " +
                                  std::string(mxq_status_name(rc)) + ": " +
                                  err.detail);
        if (rc != MXQ_OK) {
            break;
        }
        c.check_eq(removed, scenario.undo[i],
                   "undo " + std::to_string(i) + " removed the stated plies");
        remaining -= removed;
        const std::vector<std::string> line =
            history_of(game, c, "after undo " + std::to_string(i));
        c.check_eq(static_cast<int64_t>(line.size()),
                   static_cast<int64_t>(remaining),
                   "the line's length after undo " + std::to_string(i));
    }

    uint32_t removed = 0;
    err = make_error();
    rc = mxq_game_undo(game, &removed, &err);
    c.check(rc == MXQ_ERR_STATE_UNDO_UNAVAILABLE,
            std::string("undo past the last decision is "
                        "MXQ_ERR_STATE_UNDO_UNAVAILABLE, got ") +
                mxq_status_name(rc));
    c.check_eq(removed, 0, "a refused undo removes nothing");
    const std::vector<std::string> line_at_end =
        history_of(game, c, "at the end");
    c.check_eq(static_cast<int64_t>(line_at_end.size()),
               static_cast<int64_t>(remaining),
               "a refused undo leaves the line as it was");

    /* The undone game is committed too: it survives one more round trip. */
    mxq_game_release(game);
    game = nullptr;
    mxq_core_shutdown(core, nullptr);
    core = nullptr;

    err = make_error();
    rc = init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err);
    c.check(rc == MXQ_OK, "reopening after the undos failed");
    if (rc == MXQ_OK) {
        exists = 0;
        err = make_error();
        rc = mxq_game_resume_active(core, &game, &exists, &err);
        c.check(rc == MXQ_OK && exists == 1,
                "the undone game resumes as the active game");
        if (rc == MXQ_OK && exists == 1) {
            const std::vector<std::string> resumed =
                history_of(game, c, "after the undos");
            c.check(resumed == line_at_end,
                    "the undone line is what was committed");
            mxq_game_release(game);
        }
        mxq_core_shutdown(core, nullptr);
    }

    c.report();
}

/* ---------------------------------------------------------------------- */
/* Cases that are properties of the interface                              */
/* ---------------------------------------------------------------------- */

/*
 * The square-and-move grammar directly, because the two public gates over it
 * refuse with statuses that assert — those expectations are only observable in
 * a release build, and this one is worth having in both.
 *
 * These are the inputs a length-only or an unbounded-accumulator reading gets
 * wrong. They need no core: the grammar is a constant of each ruleset.
 */
void case_notation_grammar() {
    Case c("the square-and-move grammar accepts exactly the squares each "
           "board has");

    const auto square = [](MxqGameKind game, const char *text) {
        return mxq::notation::well_formed_square(game, text);
    };
    const auto move = [](MxqGameKind game, const char *text) {
        return mxq::notation::well_formed_move(game, text);
    };

    /* The empty string consumes as many characters as it has, which is what a
     * length comparison alone reads as agreement. */
    c.check(!square(MXQ_GAME_KIND_MINI_XIANGQI, ""),
            "the empty string is not a square");
    c.check(!square(MXQ_GAME_KIND_XIANGQI, ""),
            "on either board");
    c.check(!move(MXQ_GAME_KIND_MINI_XIANGQI, ""),
            "and it is not a move");

    /* A digit run long enough to overflow the rank accumulator. Under wrapping
     * these come back into range and become squares this notation says do not
     * exist. */
    c.check(!square(MXQ_GAME_KIND_XIANGQI, "a4294967297"),
            "a rank of more digits than an int32_t holds is not a square");
    c.check(!square(MXQ_GAME_KIND_MINI_XIANGQI, "a4294967297"),
            "on either board");
    c.check(!move(MXQ_GAME_KIND_XIANGQI, "a4294967297b1"),
            "and no move begins with one");
    c.check(!square(MXQ_GAME_KIND_XIANGQI, "a99999999999999999999"),
            "nor does a run longer than any integer this core carries");

    /* The squares each board does have, and the ones it does not. */
    c.check(square(MXQ_GAME_KIND_MINI_XIANGQI, "g7"), "g7 is a Mini square");
    c.check(!square(MXQ_GAME_KIND_MINI_XIANGQI, "h1"), "h1 is not");
    c.check(!square(MXQ_GAME_KIND_MINI_XIANGQI, "a8"), "nor is a8");
    c.check(square(MXQ_GAME_KIND_XIANGQI, "i10"), "i10 is a Xiangqi square");
    c.check(!square(MXQ_GAME_KIND_XIANGQI, "a11"), "a11 is not");
    c.check(!square(MXQ_GAME_KIND_XIANGQI, "a01"),
            "and a leading zero is a second spelling this notation refuses");

    /* The split rule, which is the whole reason the grammar is one module. */
    c.check(move(MXQ_GAME_KIND_XIANGQI, "a1a10"),
            "a1a10 reads as a1 then a10");
    c.check(move(MXQ_GAME_KIND_XIANGQI, "a9a10"),
            "and a9a10 is the longest move either board spells");
    c.check(!move(MXQ_GAME_KIND_MINI_XIANGQI, "a1a10"),
            "the same text is no move at all on the smaller board");

    c.report();
}

void case_second_active_game() {
    Case c("a second active game is refused");
    const fs::path store = scratch_dir("second-active");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGameConfig config = make_config();
    MxqGame *first = nullptr;
    err = make_error();
    c.check(mxq_game_create(core, &config, &first, &err) == MXQ_OK,
            "the first creation succeeds");

    MxqGame *second = reinterpret_cast<MxqGame *>(0x1);
    err = make_error();
    const MxqStatus rc = mxq_game_create(core, &config, &second, &err);
    c.check(rc == MXQ_ERR_STATE_ACTIVE_GAME_EXISTS,
            std::string("a second creation is MXQ_ERR_STATE_ACTIVE_GAME_EXISTS,"
                        " got ") +
                mxq_status_name(rc));
    c.check(second == nullptr, "no second session was produced");

    /* And the first game is untouched by the refusal. */
    MxqPosition position = make_position();
    c.check(mxq_game_position(first, &position, nullptr) == MXQ_OK,
            "the first game still answers");
    c.check_eq(position.ply_count, 0, "the first game is unchanged");

    mxq_game_release(first);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * The three questions creation asks of a composed start, and the two entries
 * that never take one.
 *
 * One case rather than five, because it is one ladder: what it pins is that
 * each rung answers in its own code and that the earlier rung wins, which a
 * build that collapsed two of them into one status would fail here and nowhere
 * else. The frozen start reaching the same ladder is the fourth check — a game
 * created the way every game before this one was must still be created.
 */
void case_start_position_ladder() {
    Case c("the questions a composed start is asked, in order");
    const fs::path store = scratch_dir("start-ladder");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const auto with_start = [](const char *fen) {
        MxqGameConfig config = make_config();
        config.game = MXQ_GAME_KIND_XIANGQI;
        std::memcpy(config.start_fen, fen, std::strlen(fen) + 1);
        return config;
    };
    const auto refused = [&](const MxqGameConfig &config, MxqStatus want,
                             const std::string &what) {
        MxqGame *game = reinterpret_cast<MxqGame *>(0x1);
        MxqError e = make_error();
        const MxqStatus rc = mxq_game_create(core, &config, &game, &e);
        c.check(rc == want, what + ": expected " +
                                std::string(mxq_status_name(want)) + ", got " +
                                std::string(mxq_status_name(rc)) + " (" +
                                e.detail + ")");
        c.check(game == nullptr, what + ": no session was produced");
    };

    /* Rung one, twice: a position of the other game's board, and a position of
     * this one carrying the counters a game with plies behind it would. Both
     * are how a start is spelled, so both are the same code. */
    refused(with_start("rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"),
            MXQ_ERR_RULES_INVALID_FEN, "a position of the other game's board");
    refused(with_start("4k4/9/7c1/1r7/9/3pP4/6R2/9/9/4K4 b - - 3 7"),
            MXQ_ERR_RULES_INVALID_FEN, "counters no start carries");

    /* Rung two: a position of this board that the predicate refuses — Red is
     * not to move and stands in check. */
    refused(with_start("4k4/9/9/9/9/9/4r4/9/9/4K4 b - - 0 1"),
            MXQ_ERR_RULES_ILLEGAL_POSITION, "an illegal setup");

    /* Rung three: a legal setup that is already decided. Black is to move and
     * has no legal move, which is a loss for the side that cannot move and
     * therefore no game to begin. */
    refused(with_start("3k5/9/9/9/9/9/9/4R4/3R5/4K4 b - - 0 1"),
            MXQ_ERR_STATE_GAME_OVER, "a position with a result of its own");

    /* Nearby play takes no composed start at all: the wire protocol carries
     * none, so a game begun from one is not a game two devices could both be
     * in. */
#if defined(NDEBUG)
    {
        MxqGameConfig config =
            with_start("4k4/9/7c1/1r7/9/3pP4/6R2/9/9/4K4 b - - 0 1");
        config.mode = MXQ_PLAY_MODE_NEARBY;
        config.local_side = MXQ_COLOR_RED;
        MxqNearbySession session;
        std::memset(&session, 0, sizeof(session));
        session.struct_size = static_cast<uint32_t>(sizeof(session));
        session.proposer = MXQ_NEARBY_PROPOSER_LOCAL;
        session.sent_end = MXQ_NEARBY_TERMINAL_NONE;
        std::memcpy(session.session_id, "019b76da-a800-7000-8000-000000000000",
                    37);
        std::memcpy(session.peer_id, "peer", 5);
        MxqGame *game = nullptr;
        err = make_error();
        const MxqStatus rc =
            mxq_game_create_nearby(core, &config, &session, &game, &err);
        c.check(rc == MXQ_ERR_ARG_RANGE,
                std::string("a nearby game refuses a composed start, got ") +
                    mxq_status_name(rc));
        c.check(game == nullptr, "and creates nothing");
    }
#endif

    /* Human-versus-AI takes none either, and for its own reason:
     * first_mover_choice is archive content that cannot be reconstructed, and
     * it says nothing about a game whose start names its own side to move. */
#if defined(NDEBUG)
    {
        MxqGameConfig config =
            with_start("4k4/9/7c1/1r7/9/3pP4/6R2/9/9/4K4 b - - 0 1");
        config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
        config.human_side = MXQ_COLOR_RED;
        config.ai_level = MXQ_AI_LEVEL_FAST;
        config.first_mover_choice = MXQ_FIRST_MOVER_HUMAN_FIRST;
        config.ai_movetime_ms = 1000;
        refused(config, MXQ_ERR_ARG_RANGE,
                "a composed start in human-versus-AI play");
    }
#endif

    /* The frozen start spelled out is the game's own start, everywhere the
     * empty member is: it is created, and it reads back empty, so one committed
     * game answers one way about where it began. */
    {
        MxqGameConfig explicit_frozen = make_config();
        explicit_frozen.game = MXQ_GAME_KIND_XIANGQI;
        char frozen[MXQ_FEN_CAP];
        size_t frozen_len = 0;
        mxq_rules_start_fen(MXQ_GAME_KIND_XIANGQI, frozen, sizeof(frozen),
                            &frozen_len, nullptr);
        std::memcpy(explicit_frozen.start_fen, frozen, frozen_len + 1);

        MxqGame *plain = nullptr;
        err = make_error();
        c.check(mxq_game_create(core, &explicit_frozen, &plain, &err) == MXQ_OK,
                std::string("the frozen start spelled out is created: ") +
                    err.detail);
        if (plain != nullptr) {
            MxqGameConfig read_back = make_config();
            c.check(mxq_game_config(plain, &read_back, nullptr) == MXQ_OK,
                    "the frozen-start game answers");
            c.check_eq(std::string(read_back.start_fen), std::string(),
                       "a start that is the frozen one reads back empty");
            /* Filed rather than released: the library holds one active game,
             * and the scene below is the next one. */
            c.check(mxq_store_archive_and_clear(core, plain, nullptr, nullptr) ==
                        MXQ_OK,
                    "and is filed, leaving the library free");
            mxq_game_release(plain);
        }
    }

    /* And the position the whole ladder exists for is created, from the start
     * the configuration named and with Black making ply 0. */
    MxqGameConfig scene =
        with_start("4k4/9/7c1/1r7/9/3pP4/6R2/9/9/4K4 b - - 0 1");
    MxqGame *game = nullptr;
    err = make_error();
    c.check(mxq_game_create(core, &scene, &game, &err) == MXQ_OK,
            std::string("the scene is created: ") + err.detail);
    if (game != nullptr) {
        MxqPosition position = make_position();
        c.check(mxq_game_position(game, &position, nullptr) == MXQ_OK,
                "the scene answers");
        c.check_eq(std::string(position.fen), std::string(scene.start_fen),
                   "the session begins from the composed position");
        c.check_eq(position.side_to_move, MXQ_COLOR_BLACK,
                   "the composed position's own side moves first");
        MxqGameStatus status = make_status();
        c.check(mxq_game_status(game, &status, nullptr) == MXQ_OK,
                "the scene has a status");
        c.check_eq(status.side_to_move, MXQ_COLOR_BLACK,
                   "the status names the side to move");
        c.check_eq(status.state, MXQ_GAME_ONGOING, "the scene is a game");
        mxq_game_release(game);
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * The same ladder asked of the one game that has no frozen start.
 *
 * Its configuration always names a start, so the three questions are asked of
 * every session it has rather than only of a composed one — and the second of
 * them is the dealt-start question, which is the whole of what this game's rules
 * say about a position it may be set up in. The third never refuses one: a dealt
 * start is a full board with a move for the side to move, so there is nothing
 * for a startability case to catch and none is written.
 *
 * Two refusals here are not rungs at all but configuration shapes, and both
 * assert, so both are stated where the assertions are compiled out: an empty
 * start for a game that has no start to mean, and the mode this game does not
 * play. The third of that kind is the nearby door — a dealt game played over the
 * wire records the deal its handshake produced, so it is created through the
 * entry that carries one.
 */
void case_dealt_start_ladder() {
    Case c("the questions a dealt start is asked, and the shapes it refuses");
    const fs::path store = scratch_dir("dealt-ladder");

    /* One deal, the corpus's own: the vector fixtures/archive/valid's jieqi
     * golden is built on, so the position here and the position there are one
     * position rather than two transcriptions. */
    const char *const kDealt =
        "r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/"
        "P~1P~1C~1B~1R~/1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 0 1";

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const auto with_start = [](const char *fen) {
        MxqGameConfig config = make_config();
        config.game = MXQ_GAME_KIND_JIEQI;
        std::memcpy(config.start_fen, fen, std::strlen(fen) + 1);
        return config;
    };
    const auto refused = [&](const MxqGameConfig &config, MxqStatus want,
                             const std::string &what) {
        MxqGame *game = reinterpret_cast<MxqGame *>(0x1);
        MxqError e = make_error();
        const MxqStatus rc = mxq_game_create(core, &config, &game, &e);
        c.check(rc == want, what + ": expected " +
                                std::string(mxq_status_name(want)) + ", got " +
                                std::string(mxq_status_name(rc)) + " (" +
                                e.detail + ")");
        c.check(game == nullptr, what + ": no session was produced");
    };

    /* Rung one: how the position is spelled. A face-down piece stands on its own
     * start square and nowhere else — it flips the moment it moves — so a record
     * standing one elsewhere spells a position the game cannot reach; and the
     * counters a start carries are halfmove 0 and fullmove 1 whatever the
     * position. */
    refused(with_start("4k4/9/9/9/9/9/9/9/R~8/4K4 w - - 0 1"),
            MXQ_ERR_RULES_INVALID_FEN, "a face-down piece off its own square");
    refused(with_start("r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/"
                       "P~1P~1C~1B~1R~/1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 3 7"),
            MXQ_ERR_RULES_INVALID_FEN, "counters no start carries");

    /* Rung two: the membership question, which for this game is the dealt start
     * and nothing else. The standard array face up is a position of this board
     * and of this game, and it is not a deal. */
    refused(with_start("rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/"
                       "RNBAKABNR w - - 0 1"),
            MXQ_ERR_RULES_ILLEGAL_POSITION, "a position that is not a deal");

    /* And the same question asked of the predicate directly, which is where the
     * rule the refusal carries is readable: the answer names neither a side nor
     * a point, because a deal is dealt whole. */
    {
        MxqSetupViolation violation;
        std::memset(&violation, 0, sizeof(violation));
        violation.struct_size = static_cast<uint32_t>(sizeof(violation));
        err = make_error();
        const MxqStatus rc = mxq_rules_validate_setup(
            core, MXQ_GAME_KIND_JIEQI,
            "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1",
            &violation, &err);
        c.check(rc == MXQ_ERR_RULES_ILLEGAL_POSITION,
                std::string("the predicate refuses a position that is not a "
                            "deal, got ") +
                    mxq_status_name(rc));
        c.check_eq(violation.rule, MXQ_SETUP_RULE_NOT_DEALT_START,
                   "the rule the refusal carries");
        c.check_eq(violation.side, MXQ_COLOR_NONE, "and names no side");
        c.check_eq(std::string(violation.square), std::string(),
                   "and no square");
    }

#if defined(NDEBUG)
    /* A configuration of a shape this game does not have: there is no one
     * position for an empty member to mean, so the member is not optional
     * here. */
    {
        MxqGameConfig config = make_config();
        config.game = MXQ_GAME_KIND_JIEQI;
        refused(config, MXQ_ERR_ARG_RANGE, "an empty start for a dealt game");
    }

    /* And the mode it does not play: no search, no network, nothing to
     * prepare. */
    {
        MxqGameConfig config = with_start(kDealt);
        config.mode = MXQ_PLAY_MODE_HUMAN_VS_AI;
        config.human_side = MXQ_COLOR_RED;
        config.ai_level = MXQ_AI_LEVEL_FAST;
        config.first_mover_choice = MXQ_FIRST_MOVER_HUMAN_FIRST;
        config.ai_movetime_ms = 1000;
        refused(config, MXQ_ERR_ARG_RANGE, "a dealt game against an AI");
    }

    /* And the door: a nearby game of it carries the evidence its deal was dealt,
     * and this entry takes no wire session to carry it. */
    {
        MxqGameConfig config = with_start(kDealt);
        config.mode = MXQ_PLAY_MODE_NEARBY;
        config.local_side = MXQ_COLOR_RED;
        refused(config, MXQ_ERR_ARG_RANGE,
                "a nearby dealt game without its wire session");
    }
#endif

    /* And the deal itself is a game to begin: Free Play deals its own, so it
     * carries no handshake evidence, its start reads back spelled out — there
     * being no frozen start for the member to fold into — and Red moves first,
     * as every deal is dealt. */
    MxqGameConfig dealt = with_start(kDealt);
    MxqGame *game = nullptr;
    err = make_error();
    c.check(mxq_game_create(core, &dealt, &game, &err) == MXQ_OK,
            std::string("the dealt start is created: ") + err.detail);
    if (game != nullptr) {
        MxqGameConfig read_back = make_config();
        c.check(mxq_game_config(game, &read_back, nullptr) == MXQ_OK,
                "the dealt game answers");
        c.check_eq(std::string(read_back.start_fen), std::string(kDealt),
                   "a dealt start always reads back spelled out");
        MxqPosition position = make_position();
        c.check(mxq_game_position(game, &position, nullptr) == MXQ_OK,
                "the dealt game has a position");
        c.check_eq(std::string(position.fen), std::string(kDealt),
                   "the session begins from the deal it was created with");
        c.check_eq(position.side_to_move, MXQ_COLOR_RED,
                   "a deal is dealt with Red to move");
        MxqGameStatus status = make_status();
        c.check(mxq_game_status(game, &status, nullptr) == MXQ_OK,
                "the dealt game has a status");
        c.check_eq(status.state, MXQ_GAME_ONGOING,
                   "and a dealt start never has a result of its own");
        c.check_eq(status.search_expected, 0,
                   "nothing searches this game, at any ply");
        mxq_game_release(game);
    }

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * The deal entry, asked for the same two deals the derivation is anchored on.
 *
 * case_deal_derivation states those vectors against the derivation itself; this
 * states them against the public C surface, which is what a second
 * implementation of docs/boardgame-protocol-v2.md's derivation is compared with
 * and what every caller above this interface derives through. Two readings of
 * one anchor: the fifteen letters a side and the digest there, the position
 * record those letters spell and the same digest here, from the same seed and
 * nonce.
 *
 * The start FENs below are not a third statement of the deal. Each is those
 * same fifteen letters laid onto the fifteen squares the protocol fixes, in the
 * order it fixes them, with the two generals face up between them — and the
 * second vector's is the corpus's own dealt start, the one case_dealt_start_ladder
 * creates a game from and the jieqi archive golden is built on. That the entry
 * derives that exact record from that seed and nonce is what binds this surface
 * to the corpus as well as to the anchor.
 */
void case_deal_entry() {
    Case c("the deal entry, against the cross-implementation anchors");
    const fs::path store = scratch_dir("deal-entry");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    const auto make_deal = [] {
        MxqDeal deal;
        std::memset(&deal, 0, sizeof(deal));
        deal.struct_size = static_cast<uint32_t>(sizeof(deal));
        return deal;
    };

    const std::string seed(64, '0');
    /* Both vectors are dealt from that seed, so both bind one commitment: the
     * SHA-256 of thirty-two zero bytes. */
    const std::string commit =
        "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925";

    struct Vector {
        std::string nonce;
        std::string start_fen;
        std::string digest;
        std::string what;
    };
    const std::vector<Vector> vectors = {
        {std::string(64, 'f'),
         "a~r~n~p~kb~b~c~a~/9/1p~5p~1/p~1p~1r~1n~1c~/9/9/A~1R~1B~1P~1N~/"
         "1N~5A~1/9/P~C~P~B~KC~P~R~P~ w - - 0 1",
         "ed1c9fb490c3d2f0e011e283c229b1408174109b7e632f8a0c01ac4541acb766",
         "the plain path"},
        {"a144410000000000000000000000000000000000000000000000000000000000",
         "r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/P~1P~1C~1B~1R~/"
         "1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 0 1",
         "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea001baa",
         "a rejected draw"},
    };

    for (const Vector &v : vectors) {
        MxqDeal deal = make_deal();
        err = make_error();
        const MxqStatus rc = mxq_rules_deal(core, MXQ_GAME_KIND_JIEQI,
                                            seed.c_str(), v.nonce.c_str(),
                                            &deal, &err);
        c.check(rc == MXQ_OK, v.what + ": the entry refused its input: " +
                                  mxq_status_name(rc) + " (" + err.detail + ")");
        if (rc != MXQ_OK) {
            continue;
        }
        c.check_eq(std::string(deal.start_fen), v.start_fen,
                   v.what + ": the dealt start");
        c.check_eq(std::string(deal.commit), commit,
                   v.what + ": the commitment the seed binds");
        c.check_eq(std::string(deal.digest), v.digest,
                   v.what + ": the deal digest");
    }

    /* A newer caller's struct: everything this build knows is written, and
     * struct_size reads back the size this build could interpret rather than
     * the size the caller declared. */
    {
        MxqDeal deal = make_deal();
        deal.struct_size = static_cast<uint32_t>(sizeof(deal)) + 16u;
        err = make_error();
        const MxqStatus rc =
            mxq_rules_deal(core, MXQ_GAME_KIND_JIEQI, seed.c_str(),
                           vectors[0].nonce.c_str(), &deal, &err);
        c.check(rc == MXQ_OK, std::string("a larger struct_size is a newer "
                                          "caller, not a refusal: ") +
                                  mxq_status_name(rc));
        c.check_eq(static_cast<int64_t>(deal.struct_size),
                   static_cast<int64_t>(sizeof(MxqDeal)),
                   "struct_size reads back the size this build interprets");
        c.check_eq(std::string(deal.start_fen), vectors[0].start_fen,
                   "and the deal is the same deal");
    }

#if defined(NDEBUG)
    /*
     * The refusals, all four of them programming errors: they assert where
     * NDEBUG is undefined and return their code where it is defined, so only a
     * release build observes the codes.
     */
    const auto refused = [&](MxqGameKind game, const char *seed_text,
                             const char *nonce_text, MxqStatus want,
                             const std::string &what) {
        MxqDeal deal = make_deal();
        MxqError e = make_error();
        const MxqStatus rc =
            mxq_rules_deal(core, game, seed_text, nonce_text, &deal, &e);
        c.check(rc == want, what + ": expected " +
                                std::string(mxq_status_name(want)) + ", got " +
                                std::string(mxq_status_name(rc)) + " (" +
                                e.detail + ")");
    };
    const std::string nonce = vectors[0].nonce;

    /* One game is dealt, and the game whose board it shares is not it. */
    refused(MXQ_GAME_KIND_XIANGQI, seed.c_str(), nonce.c_str(),
            MXQ_ERR_ARG_RANGE, "a game with no deal");

    /* The one spelling all four handshake values have, asked of both of the
     * two this entry takes. */
    refused(MXQ_GAME_KIND_JIEQI, std::string(63, '0').c_str(), nonce.c_str(),
            MXQ_ERR_ARG_RANGE, "a seed of sixty-three digits");
    refused(MXQ_GAME_KIND_JIEQI, std::string(64, 'F').c_str(), nonce.c_str(),
            MXQ_ERR_ARG_RANGE, "a seed in uppercase");
    refused(MXQ_GAME_KIND_JIEQI, seed.c_str(), std::string(64, 'z').c_str(),
            MXQ_ERR_ARG_RANGE, "a nonce that is not hexadecimal");

    /* The two required strings. */
    refused(MXQ_GAME_KIND_JIEQI, nullptr, nonce.c_str(), MXQ_ERR_ARG_NULL,
            "a null seed");
    refused(MXQ_GAME_KIND_JIEQI, seed.c_str(), nullptr, MXQ_ERR_ARG_NULL,
            "a null nonce");

    /* And the out struct: absent, and declared at a size this build cannot
     * interpret — which is any size short of the whole struct while this
     * interface version is the only one there has been. */
    {
        MxqError e = make_error();
        const MxqStatus rc = mxq_rules_deal(core, MXQ_GAME_KIND_JIEQI,
                                            seed.c_str(), nonce.c_str(),
                                            nullptr, &e);
        c.check(rc == MXQ_ERR_ARG_NULL,
                std::string("a null out: expected MXQ_ERR_ARG_NULL, got ") +
                    mxq_status_name(rc));
    }
    {
        MxqDeal deal = make_deal();
        deal.struct_size = 4u;
        MxqError e = make_error();
        const MxqStatus rc = mxq_rules_deal(core, MXQ_GAME_KIND_JIEQI,
                                            seed.c_str(), nonce.c_str(), &deal,
                                            &e);
        c.check(rc == MXQ_ERR_ARG_STRUCT_SIZE,
                std::string("a short struct_size: expected "
                            "MXQ_ERR_ARG_STRUCT_SIZE, got ") +
                    mxq_status_name(rc));
    }
#endif

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_resume_without_a_game() {
    Case c("resuming when there is nothing to resume");
    const fs::path store = scratch_dir("resume-nothing");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    MxqGame *game = reinterpret_cast<MxqGame *>(0x1);
    uint8_t exists = 1;
    err = make_error();
    const MxqStatus rc = mxq_game_resume_active(core, &game, &exists, &err);
    c.check(rc == MXQ_OK, std::string("absence is success, got ") +
                              mxq_status_name(rc));
    c.check(exists == 0, "*out_exists is 0");
    c.check(game == nullptr, "*out_game is NULL");

    mxq_core_shutdown(core, nullptr);
    c.report();
}

void case_refused_moves_change_nothing() {
    Case c("a refused move changes nothing");
    const fs::path store = scratch_dir("refused-moves");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    mxq_game_create(core, &config, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);

    const std::string before = encode_of(core, game, c, "before the refusals");

    /* Malformed and illegal are always distinguished. */
    err = make_error();
    MxqStatus rc = mxq_game_apply_move(game, "zz99", nullptr, nullptr, &err);
    c.check(rc == MXQ_ERR_RULES_MALFORMED_MOVE,
            std::string("a malformed move is MXQ_ERR_RULES_MALFORMED_MOVE, "
                        "got ") +
                mxq_status_name(rc));
    err = make_error();
    rc = mxq_game_apply_move(game, "a1a1", nullptr, nullptr, &err);
    c.check(rc == MXQ_ERR_RULES_ILLEGAL_MOVE,
            std::string("an illegal move is MXQ_ERR_RULES_ILLEGAL_MOVE, got ") +
                mxq_status_name(rc));
    err = make_error();
    rc = mxq_game_apply_move(game, "b1b3", nullptr, nullptr, &err);
    c.check(rc == MXQ_ERR_RULES_ILLEGAL_MOVE,
            "a move that is legal notation but not legal here is refused too");

    /*
     * A rank whose digits run past what an int32_t holds. The move text comes
     * from a caller here and from an archive elsewhere, and the notation's own
     * grammar says a square has exactly one spelling — so a rank that wrapped
     * back into range would both be undefined behaviour and invent a second
     * spelling of a1. The answer must be the malformed one: reaching the
     * illegal-move rung at all would mean the wrap happened and something
     * tokenised this as two squares.
     */
    err = make_error();
    rc = mxq_game_apply_move(game, "a4294967297b1", nullptr, nullptr, &err);
    c.check(rc == MXQ_ERR_RULES_MALFORMED_MOVE,
            std::string("a rank of more digits than an int32_t holds is "
                        "malformed, got ") +
                mxq_status_name(rc));

    c.check_eq(encode_of(core, game, c, "after the refusals"), before,
               "the committed state is untouched by every refusal");

    MxqPosition position = make_position();
    mxq_game_position(game, &position, nullptr);
    c.check_eq(static_cast<int64_t>(position.position_revision), 1,
               "a refused move does not advance the revision");

    /*
     * The from-square gate, which is a different rule from the move grammar:
     * mxq.h promises MXQ_ERR_ARG_RANGE for a string that is not a square of
     * this board, and the empty string is not one. It is worth its own
     * expectation because it is the one input a length-only check accepts —
     * "consumed as many characters as it has" is true of nothing at all.
     *
     * These assert in a debug build, as every closed-vocabulary range does, so
     * the expectations are stated where the assertion is compiled out.
     */
#if defined(NDEBUG)
    {
        size_t count = 7;
        err = make_error();
        rc = mxq_game_legal_moves_from(game, "", nullptr, 0, &count, &err);
        c.check(rc == MXQ_ERR_ARG_RANGE,
                std::string("the empty string is not a square of this board, "
                            "got ") +
                    mxq_status_name(rc));
        c.check_eq(static_cast<int64_t>(count), 0,
                   "and the refusal writes no count");

        count = 7;
        err = make_error();
        rc = mxq_game_legal_moves_from(game, "a4294967297", nullptr, 0, &count,
                                       &err);
        c.check(rc == MXQ_ERR_ARG_RANGE,
                std::string("neither is a rank of more digits than an int32_t "
                            "holds, got ") +
                    mxq_status_name(rc));
    }
#endif

    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * A failed commit, driven through the store's own path: a second connection
 * takes the write lock, so BEGIN IMMEDIATE inside the mutation is refused as
 * SQLITE_BUSY exactly as a real contended write would be. No seam in the core
 * arranges this, and nothing sleeps.
 */
void case_failed_commit_leaves_the_game_unchanged() {
    Case c("a failed commit means the mutation did not happen");
    const fs::path store = scratch_dir("failed-commit");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    mxq_game_create(core, &config, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);
    const std::string before = encode_of(core, game, c, "before the lock");

    sqlite3 *blocker = nullptr;
    const std::string path = (store / "library.sqlite3").string();
    if (sqlite3_open_v2(path.c_str(), &blocker, SQLITE_OPEN_READWRITE,
                        nullptr) != SQLITE_OK) {
        c.check(false, "cannot open the second connection");
        sqlite3_close(blocker);
        mxq_game_release(game);
        mxq_core_shutdown(core, nullptr);
        c.report();
        return;
    }
    c.check(sqlite3_exec(blocker, "BEGIN EXCLUSIVE;", nullptr, nullptr,
                         nullptr) == SQLITE_OK,
            "the second connection takes the write lock");

    err = make_error();
    MxqStatus rc = mxq_game_apply_move(game, "b7b5", nullptr, nullptr, &err);
    c.check(mxq_status_domain(rc) == MXQ_DOMAIN_STORE,
            std::string("a move that cannot commit fails in the store domain, "
                        "got ") +
                mxq_status_name(rc));
    c.check_eq(encode_of(core, game, c, "after the failed move"), before,
               "the game is exactly at its pre-mutation committed state");

    MxqPosition position = make_position();
    mxq_game_position(game, &position, nullptr);
    c.check_eq(position.ply_count, 1, "the move did not happen");
    c.check_eq(static_cast<int64_t>(position.position_revision), 1,
               "a failed commit does not advance the revision");

    uint32_t removed = 0;
    err = make_error();
    rc = mxq_game_undo(game, &removed, &err);
    c.check(mxq_status_domain(rc) == MXQ_DOMAIN_STORE,
            std::string("an undo that cannot commit fails in the store domain, "
                        "got ") +
                mxq_status_name(rc));
    c.check_eq(removed, 0, "a failed undo removes nothing");
    c.check_eq(encode_of(core, game, c, "after the failed undo"), before,
               "the game is still exactly where it was");

    sqlite3_exec(blocker, "ROLLBACK;", nullptr, nullptr, nullptr);
    sqlite3_close(blocker);

    /* The same call succeeds once the lock is gone, so what failed was the
     * commit and not the move. */
    err = make_error();
    rc = mxq_game_apply_move(game, "b7b5", nullptr, nullptr, &err);
    c.check(rc == MXQ_OK, std::string("the same move commits once the store is "
                                      "free, got ") +
                              mxq_status_name(rc) + ": " + err.detail);

    /* And what is in the store is what the session says. */
    const std::string after = encode_of(core, game, c, "after the retry");
    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);

    err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) ==
        MXQ_OK) {
        uint8_t exists = 0;
        MxqGame *resumed = nullptr;
        mxq_game_resume_active(core, &resumed, &exists, &err);
        c.check(exists == 1, "the game is still the active one");
        if (exists == 1) {
            c.check_eq(encode_of(core, resumed, c, "resumed"), after,
                       "the committed row is the session's own bytes");
            mxq_game_release(resumed);
        }
        mxq_core_shutdown(core, nullptr);
    }
    c.report();
}

/*
 * Two threads inside one session. The first "thread" is this one, holding the
 * session's own owner guard — which is what being inside a session is — so the
 * second thread's call meets a claimed session deterministically, with no
 * sleep and no test-only hook in the core.
 */
void case_concurrent_use_is_refused() {
    Case c("a second thread inside one session is refused");
    const fs::path store = scratch_dir("concurrent");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    mxq_game_create(core, &config, &game, &err);

    std::vector<MxqStatus> refusals;
    {
        mxq::session::Owner inside(game);
        c.check(inside.held(), "this thread is inside the session");

        std::thread other([&] {
            MxqPosition position = make_position();
            MxqGameStatus status = make_status();
            uint32_t removed = 0;
            size_t count = 0;
            char id[MXQ_GAME_ID_CAP];
            size_t len = 0;
            refusals.push_back(mxq_game_position(game, &position, nullptr));
            refusals.push_back(mxq_game_status(game, &status, nullptr));
            refusals.push_back(mxq_game_move_history(game, nullptr, 0, &count,
                                                    nullptr));
            refusals.push_back(
                mxq_game_id(game, id, sizeof(id), &len, nullptr));
            refusals.push_back(
                mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr));
            refusals.push_back(mxq_game_undo(game, &removed, nullptr));
            MxqBlob *blob = nullptr;
            refusals.push_back(mxq_archive_encode(core, game, &blob, nullptr));
            mxq_blob_release(blob);
        });
        other.join();
    }

    for (const MxqStatus rc : refusals) {
        c.check(rc == MXQ_ERR_ARG_CONCURRENT_USE,
                std::string("a call from another thread is "
                            "MXQ_ERR_ARG_CONCURRENT_USE, got ") +
                    mxq_status_name(rc));
    }

    /* The session is usable again once no one is inside it, and the refused
     * move never happened. */
    MxqPosition position = make_position();
    c.check(mxq_game_position(game, &position, nullptr) == MXQ_OK,
            "the session answers again afterwards");
    c.check_eq(position.ply_count, 0, "the refused move did not happen");

    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * Shutdown with an outstanding handle. The contract promises that every
 * function on it answers MXQ_ERR_ARG_INVALID_HANDLE rather than touching freed
 * memory, and that the caller still releases it.
 */
void case_tombstoned_handle() {
    Case c("a handle outstanding at shutdown is a tombstone, not a dangler");
    const fs::path store = scratch_dir("tombstone");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    mxq_game_create(core, &config, &game, &err);
    mxq_game_apply_move(game, "b1b3", nullptr, nullptr, nullptr);

    c.check(mxq_core_shutdown(core, nullptr) == MXQ_OK, "shutdown succeeds");

    MxqPosition position = make_position();
    MxqGameStatus status = make_status();
    MxqGameConfig read_config = make_config();
    size_t count = 0;
    uint32_t removed = 0;
    char id[MXQ_GAME_ID_CAP];
    size_t len = 0;
    uint64_t record_id = 0;

    const std::vector<std::pair<const char *, MxqStatus>> answers = {
        {"mxq_game_position", mxq_game_position(game, &position, nullptr)},
        {"mxq_game_status", mxq_game_status(game, &status, nullptr)},
        {"mxq_game_config", mxq_game_config(game, &read_config, nullptr)},
        {"mxq_game_id", mxq_game_id(game, id, sizeof(id), &len, nullptr)},
        {"mxq_game_legal_moves",
         mxq_game_legal_moves(game, nullptr, 0, &count, nullptr)},
        {"mxq_game_legal_moves_from",
         mxq_game_legal_moves_from(game, "b1", nullptr, 0, &count, nullptr)},
        {"mxq_game_move_history",
         mxq_game_move_history(game, nullptr, 0, &count, nullptr)},
        {"mxq_game_position_at",
         mxq_game_position_at(game, 0, &position, nullptr)},
        {"mxq_game_apply_move",
         mxq_game_apply_move(game, "b7b5", nullptr, nullptr, nullptr)},
        {"mxq_game_undo", mxq_game_undo(game, &removed, nullptr)},
        {"mxq_game_claim_draw",
         mxq_game_claim_draw(game, &record_id, nullptr)},
        {"mxq_game_resign", mxq_game_resign(game, &record_id, nullptr)},
        {"mxq_game_confirm_result",
         mxq_game_confirm_result(game, &record_id, nullptr)},
    };
    for (const auto &answer : answers) {
        c.check(answer.second == MXQ_ERR_ARG_INVALID_HANDLE,
                std::string(answer.first) +
                    " on a tombstone is MXQ_ERR_ARG_INVALID_HANDLE, got " +
                    mxq_status_name(answer.second));
    }
    /* mxq_archive_encode is deliberately not in that list: it takes the core
     * as well as the session, and this core has been shut down, so the call
     * would be a use of a freed handle rather than a test of a tombstoned one.
     * The concurrency case covers encode's own handle checks. */

    /* Release is still the caller's to make, and is still safe. */
    mxq_game_release(game);
    c.report();
}

/*
 * The measured worst case behind the legal-move capacity in
 * docs/core-interface.md, pinned so it cannot move quietly.
 *
 * The contract sizes every game's fixed array at one shared figure, 512, and
 * derives a per-game bound beside it that sizes nothing: Mini Xiangqi's is 83,
 * over a measured maximum of 77 found by hill-climbing over positions the core
 * accepts. What those derivations are for is the margin — a game whose bound
 * crept toward the shared figure would be a game something had been mis-modeled
 * about — and this is the one of them with a measurement under it. That
 * measurement is the kind that rots: a rules change — a mobility region, a
 * chase exclusion, a piece's move set — can swell legal-move counts toward the
 * ceiling without failing anything else, and the fixtures would not notice,
 * since the busiest position any of them reaches has 32 legal moves. This
 * position is the evidence, so it is asserted: the count is exact, and the
 * bound it sits under is checked with it.
 */
void case_legal_move_capacity() {
    Case c("the measured legal-move worst case, pinned");
    const fs::path store = scratch_dir("capacity");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, 0, &core, &err) != MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }

    /* Red's full starting complement against a bare general. */
    const char *kBusiest = "4C2/2kP1P1/2P4/3N1P1/2N4/1C1K1P1/R5R w - - 0 1";
    const size_t kBusiestCount = 77;
    const size_t kDerivedBound = 83;

    size_t count = 0;
    err = make_error();
    c.check(mxq_rules_legal_moves(core, MXQ_GAME_KIND_MINI_XIANGQI, kBusiest, nullptr, 0, nullptr, 0,
                                  &count, &err) ==
                MXQ_ERR_ARG_BUFFER_TOO_SMALL,
            "asking for the count alone is the routine buffer refusal");
    c.check_eq(static_cast<int64_t>(count),
               static_cast<int64_t>(kBusiestCount),
               "the measured busiest position's legal-move count");
    c.check_eq(static_cast<int64_t>(err.required_size),
               static_cast<int64_t>(kBusiestCount),
               "and required_size says how much room it needs");

    /* The contract's claim, made twice over: the count fits the capacity it
     * says is sufficient, and stays under the bound it derived. */
    std::vector<MxqMove> out(128);
    for (MxqMove &m : out) {
        std::memset(&m, 0, sizeof(m));
        m.struct_size = static_cast<uint32_t>(sizeof(MxqMove));
    }
    size_t written = 0;
    err = make_error();
    const MxqStatus held = mxq_rules_legal_moves(
        core, MXQ_GAME_KIND_MINI_XIANGQI, kBusiest, nullptr, 0, out.data(),
        out.size(), &written, &err);
    c.check(held == MXQ_OK,
            std::string("a 128-element buffer holds it, got ") +
                mxq_status_name(held));
    c.check_eq(static_cast<int64_t>(written),
               static_cast<int64_t>(kBusiestCount), "and it wrote them all");
    c.check(count <= kDerivedBound,
            "the measured maximum stays under the derived bound of " +
                std::to_string(kDerivedBound));

    mxq_core_shutdown(core, nullptr);
    c.report();
}

/*
 * How long one committed move takes, measured rather than asserted.
 *
 * #50 leaves open whether the one-row active-game commit may run on the main
 * actor. That is an app-side decision and this is the number it needs: the
 * cost of apply_move including its synchronous_FULL commit, on this machine.
 */
void case_commit_latency() {
    Case c("commit latency, measured");
    const fs::path store = scratch_dir("latency");

    MxqCore *core = nullptr;
    MxqError err = make_error();
    if (init_core(store, MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY, &core, &err) !=
        MXQ_OK) {
        c.check(false, "mxq_core_init failed");
        c.report();
        return;
    }
    MxqGameConfig config = make_config();
    MxqGame *game = nullptr;
    mxq_game_create(core, &config, &game, &err);

    /* A repeating cycle, so the measurement is of the commit and not of an
     * ever-longer replay. */
    const char *const cycle[] = {"b1b3", "b7b5", "b3b1", "b5b7"};
    std::vector<double> samples;
    for (int i = 0; i < 40; ++i) {
        const auto start = std::chrono::steady_clock::now();
        const MxqStatus rc = mxq_game_apply_move(game, cycle[i % 4], nullptr,
                                                 nullptr, &err);
        const auto end = std::chrono::steady_clock::now();
        if (rc != MXQ_OK) {
            /* The cycle reaches a claimable repetition, which is not an error;
             * undo back one and keep going. */
            uint32_t removed = 0;
            mxq_game_undo(game, &removed, nullptr);
            continue;
        }
        samples.push_back(
            std::chrono::duration<double, std::milli>(end - start).count());
    }
    std::sort(samples.begin(), samples.end());
    if (!samples.empty()) {
        std::cout << "            apply_move over " << samples.size()
                  << " commits: median "
                  << samples[samples.size() / 2] << " ms, worst "
                  << samples.back() << " ms\n";
    }
    c.check(!samples.empty(), "at least one commit was measured");

    mxq_game_release(game);
    mxq_core_shutdown(core, nullptr);
    c.report();
}

#endif /* MXQ_TEST_RULES_FACADE */

} /* namespace */

int main(int argc, char **argv) {
    fs::path fixtures;
    fs::path archives;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--fixtures" && i + 1 < argc) {
            fixtures = argv[++i];
        } else if (arg == "--archives" && i + 1 < argc) {
            archives = argv[++i];
        } else {
            std::cerr << "usage: mxq_session_tests [--fixtures <dir>] "
                         "[--archives <dir>]\n";
            return 2;
        }
    }
    if (fixtures.empty()) {
        if (const char *env = std::getenv("MXQ_STORE_FIXTURES_DIR")) {
            fixtures = env;
        } else {
            fixtures = MXQ_STORE_FIXTURES_DIR_DEFAULT;
        }
    }
    if (archives.empty()) {
        if (const char *env = std::getenv("MXQ_ARCHIVE_FIXTURES_DIR")) {
            archives = env;
        } else {
            archives = MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT;
        }
    }

    std::cout << "Mini Xiangqi session and store round-trip tests\n"
              << "  fixtures        " << fixtures.string() << "\n"
              << "  archives        " << archives.string() << "\n"
              << "  rules facade    "
              << (MXQ_TEST_RULES_FACADE
                      ? "available; the mxq_game_ functions are in this build"
                      : "ABSENT; the mxq_game_ functions are not in this build")
              << "\n\n";

    case_sha256_vectors();
    case_deal_derivation();

#if MXQ_TEST_RULES_FACADE
    std::vector<fs::path> scenarios;
    std::error_code ec;
    for (const fs::directory_entry &entry :
         fs::directory_iterator(fixtures, ec)) {
        if (entry.path().extension() == ".json") {
            scenarios.push_back(entry.path());
        }
    }
    if (ec || scenarios.empty()) {
        std::cerr << "mxq_session_tests: no scenarios in " << fixtures.string()
                  << "\n";
        return 2;
    }
    std::sort(scenarios.begin(), scenarios.end());
    for (const fs::path &scenario : scenarios) {
        run_scenario(scenario, archives);
    }

    case_notation_grammar();
    case_second_active_game();
    case_start_position_ladder();
    case_dealt_start_ladder();
    case_deal_entry();
    case_resume_without_a_game();
    case_refused_moves_change_nothing();
    case_failed_commit_leaves_the_game_unchanged();
    case_concurrent_use_is_refused();
    case_tombstoned_handle();
    case_legal_move_capacity();
    case_commit_latency();

    std::error_code cleanup;
    fs::remove_all(scratch_root(), cleanup);
#else
    Case skipped("the session round trip");
    skipped.skip(kNoFacade);
    skipped.report();
#endif

    const int total = g_passed + g_failed + g_skipped;
    std::cout << "\n"
              << total << " cases: " << g_passed << " passed, " << g_failed
              << " failed, " << g_skipped << " skipped\n"
              << g_checks << " expectations evaluated\n";
    if (g_skipped_no_facade > 0) {
        std::cout << "\nNOT IMPLEMENTED: the session surface is not in this "
                     "build. Build with -DMXQ_ENABLE_RULES_FACADE=ON to "
                     "evaluate it.\n";
    }
    return g_failed > 0 ? 1 : 0;
}
