/*
 * The facts about this build that the core reports: the engine revisions under
 * engines/, the variants it searches and the networks it loads for them. An
 * engine update changes its revision here and in its README.
 */

#ifndef MXQ_BUILD_CONFIG_H
#define MXQ_BUILD_CONFIG_H

/* The repository revision. The package build has no step that could read it. */
#define MXQ_BUILD_CORE_REVISION "unknown"

/* The Fairy-Stockfish fork revision. */
#define MXQ_BUILD_FORK_REVISION "791e25f5902ee0c8a9624886a768432a0badafc5"

/* The Rapfi fork revision. */
#define MXQ_BUILD_GOMOKU_FORK_REVISION "265b7d66c7b57bbd8689c8dfd1efb4133e02b5ed"

/* The variant the app plays, defined by assets/minixiangqi-variants.ini, and
 * the engine's own name for built-in xiangqi. */
#define MXQ_BUILD_VARIANT_ID "minixiangqiaxf"
#define MXQ_BUILD_XIANGQI_VARIANT_ID "xiangqi"

/* Each network is named by the first twelve hexadecimal digits of its SHA-256,
 * which is also how a profile identifier names it. Fairy-Stockfish loads a
 * network only when its basename begins with the variant's identifier, so the
 * first two names are not decoration. */
#define MXQ_BUILD_NNUE_ID "ad52b8658c9e"
#define MXQ_BUILD_NNUE_FILENAME MXQ_BUILD_VARIANT_ID "-" MXQ_BUILD_NNUE_ID ".nnue"

#define MXQ_BUILD_XIANGQI_NNUE_ID "c07e94a5c7cb"
#define MXQ_BUILD_XIANGQI_NNUE_FILENAME \
    MXQ_BUILD_XIANGQI_VARIANT_ID "-" MXQ_BUILD_XIANGQI_NNUE_ID ".nnue"

/* Rapfi's weights: one file serves both sides of freestyle, and Renju has one
 * per side. */
#define MXQ_BUILD_GOMOKU_NNUE_ID "6bc0d1b0ff8e"
#define MXQ_BUILD_GOMOKU_NNUE_FILENAME \
    "mix9svqfreestyle_bsmix-" MXQ_BUILD_GOMOKU_NNUE_ID ".bin.lz4"

#define MXQ_BUILD_RENJU_BLACK_NNUE_ID "7ab8c974c30d"
#define MXQ_BUILD_RENJU_BLACK_NNUE_FILENAME \
    "mix9svqrenju_bs15_black-" MXQ_BUILD_RENJU_BLACK_NNUE_ID ".bin.lz4"

#define MXQ_BUILD_RENJU_WHITE_NNUE_FILENAME \
    "mix9svqrenju_bs15_white-a31f318518d3.bin.lz4"

#endif /* MXQ_BUILD_CONFIG_H */
