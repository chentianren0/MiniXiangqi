/*
 * Layout assertions for the public boundary.
 *
 * The contract requires every struct crossing mxq.h to be blittable by
 * construction, because the Windows frontend marshals them through
 * ClangSharp-generated P/Invoke declarations and the Apple frontend imports
 * them through a module map. This translation unit emits no code; it exists so
 * that a layout change is a compile error on whichever platform introduces it,
 * rather than a silent marshalling bug on the other one.
 *
 * The offsets below are exhaustive and were chosen so that no struct contains
 * implicit padding: every field is asserted to begin exactly where the previous
 * one ends, and every struct's size is asserted exactly. Any ABI that agrees on
 * the sizes and alignments of the fixed-width integer types therefore agrees on
 * these layouts.
 */

#include "mxq_internal.hpp"

#include <cstddef>
#include <type_traits>

namespace {

#define MXQ_ASSERT_BLITTABLE(T)                                              \
    static_assert(std::is_standard_layout<T>::value,                         \
                  #T " must be standard layout");                            \
    static_assert(std::is_trivially_copyable<T>::value,                      \
                  #T " must be trivially copyable");                         \
    static_assert(offsetof(T, struct_size) == 0,                             \
                  #T " must begin with struct_size")

#define MXQ_ASSERT_AT(T, field, at)                                          \
    static_assert(offsetof(T, field) == (at),                                \
                  #T "." #field " moved; the bindings would mis-marshal")

#define MXQ_ASSERT_SIZE(T, bytes)                                            \
    static_assert(sizeof(T) == (bytes), #T " changed size")

/* Every enumerated vocabulary is exactly 32 bits wide and signed. */
static_assert(sizeof(MxqStatus) == 4, "MxqStatus must be 32 bits");
static_assert(sizeof(MxqColor) == 4, "MxqColor must be 32 bits");
static_assert(sizeof(MxqPlayMode) == 4, "MxqPlayMode must be 32 bits");
static_assert(sizeof(MxqGameKind) == 4, "MxqGameKind must be 32 bits");
static_assert(sizeof(MxqAiLevel) == 4, "MxqAiLevel must be 32 bits");
static_assert(sizeof(MxqFirstMoverChoice) == 4,
              "MxqFirstMoverChoice must be 32 bits");
static_assert(sizeof(MxqGameState) == 4, "MxqGameState must be 32 bits");
static_assert(sizeof(MxqOutcome) == 4, "MxqOutcome must be 32 bits");
static_assert(sizeof(MxqEndReason) == 4, "MxqEndReason must be 32 bits");
static_assert(sizeof(MxqSetupRule) == 4, "MxqSetupRule must be 32 bits");
static_assert(sizeof(MxqProvenance) == 4, "MxqProvenance must be 32 bits");
static_assert(sizeof(MxqImportOutcome) == 4, "MxqImportOutcome must be 32 bits");
static_assert(sizeof(MxqEngineState) == 4, "MxqEngineState must be 32 bits");
static_assert(sizeof(MxqSearchOutcome) == 4, "MxqSearchOutcome must be 32 bits");
static_assert(std::is_signed<MxqStatus>::value, "MxqStatus must be signed");

MXQ_ASSERT_BLITTABLE(MxqError);
MXQ_ASSERT_AT(MxqError, status, 4);
MXQ_ASSERT_AT(MxqError, subsystem_code, 8);
MXQ_ASSERT_AT(MxqError, reserved0, 12);
MXQ_ASSERT_AT(MxqError, required_size, 16);
MXQ_ASSERT_AT(MxqError, detail_index, 24);
MXQ_ASSERT_AT(MxqError, detail, 32);
MXQ_ASSERT_SIZE(MxqError, 32 + MXQ_DETAIL_CAP);

MXQ_ASSERT_BLITTABLE(MxqVersion);
MXQ_ASSERT_AT(MxqVersion, api_major, 4);
MXQ_ASSERT_AT(MxqVersion, api_minor, 8);
MXQ_ASSERT_AT(MxqVersion, api_patch, 12);
MXQ_ASSERT_AT(MxqVersion, archive_version_current, 16);
MXQ_ASSERT_AT(MxqVersion, archive_version_min_readable, 20);
MXQ_ASSERT_AT(MxqVersion, store_schema_version, 24);
MXQ_ASSERT_AT(MxqVersion, reserved0, 28);
MXQ_ASSERT_AT(MxqVersion, core_revision, 32);
MXQ_ASSERT_AT(MxqVersion, fork_revision, 32 + MXQ_REVISION_CAP);
MXQ_ASSERT_SIZE(MxqVersion, 32 + 2 * MXQ_REVISION_CAP);

MXQ_ASSERT_BLITTABLE(MxqGameProfile);
MXQ_ASSERT_AT(MxqGameProfile, game, 4);
MXQ_ASSERT_AT(MxqGameProfile, variant_id, 8);
MXQ_ASSERT_AT(MxqGameProfile, nnue_sha256, 8 + MXQ_VARIANT_ID_CAP);
MXQ_ASSERT_SIZE(MxqGameProfile,
                8 + MXQ_VARIANT_ID_CAP + MXQ_SHA256_HEX_CAP);

MXQ_ASSERT_BLITTABLE(MxqCoreConfig);
MXQ_ASSERT_AT(MxqCoreConfig, api_major, 4);
MXQ_ASSERT_AT(MxqCoreConfig, api_minor, 8);
MXQ_ASSERT_AT(MxqCoreConfig, api_patch, 12);
MXQ_ASSERT_AT(MxqCoreConfig, flags, 16);
MXQ_ASSERT_AT(MxqCoreConfig, reserved0, 20);
MXQ_ASSERT_AT(MxqCoreConfig, store_directory, 24);
MXQ_ASSERT_AT(MxqCoreConfig, asset_directory, 32);
MXQ_ASSERT_SIZE(MxqCoreConfig, 40);

MXQ_ASSERT_BLITTABLE(MxqMove);
MXQ_ASSERT_AT(MxqMove, text, 4);
MXQ_ASSERT_SIZE(MxqMove, 4 + MXQ_MOVE_TEXT_CAP);

MXQ_ASSERT_BLITTABLE(MxqPosition);
MXQ_ASSERT_AT(MxqPosition, ply_count, 4);
MXQ_ASSERT_AT(MxqPosition, position_revision, 8);
MXQ_ASSERT_AT(MxqPosition, side_to_move, 16);
MXQ_ASSERT_AT(MxqPosition, in_check, 20);
MXQ_ASSERT_AT(MxqPosition, reserved0, 21);
MXQ_ASSERT_AT(MxqPosition, fen, 24);
MXQ_ASSERT_SIZE(MxqPosition, 24 + MXQ_FEN_CAP);

MXQ_ASSERT_BLITTABLE(MxqGameStatus);
MXQ_ASSERT_AT(MxqGameStatus, state, 4);
MXQ_ASSERT_AT(MxqGameStatus, reason, 8);
MXQ_ASSERT_AT(MxqGameStatus, at_occurrence, 12);
MXQ_ASSERT_AT(MxqGameStatus, undo_plies, 16);
MXQ_ASSERT_AT(MxqGameStatus, claim_available, 20);
MXQ_ASSERT_AT(MxqGameStatus, undo_available, 21);
MXQ_ASSERT_AT(MxqGameStatus, resign_available, 22);
MXQ_ASSERT_AT(MxqGameStatus, search_expected, 23);
MXQ_ASSERT_SIZE(MxqGameStatus, 24);

MXQ_ASSERT_BLITTABLE(MxqSetupViolation);
MXQ_ASSERT_AT(MxqSetupViolation, rule, 4);
MXQ_ASSERT_AT(MxqSetupViolation, side, 8);
MXQ_ASSERT_AT(MxqSetupViolation, square, 12);
MXQ_ASSERT_SIZE(MxqSetupViolation, 12 + MXQ_SQUARE_TEXT_CAP);

MXQ_ASSERT_BLITTABLE(MxqGameConfig);
MXQ_ASSERT_AT(MxqGameConfig, mode, 4);
MXQ_ASSERT_AT(MxqGameConfig, human_side, 8);
MXQ_ASSERT_AT(MxqGameConfig, ai_level, 12);
MXQ_ASSERT_AT(MxqGameConfig, first_mover_choice, 16);
MXQ_ASSERT_AT(MxqGameConfig, ai_movetime_ms, 20);
MXQ_ASSERT_AT(MxqGameConfig, game, 24);
MXQ_ASSERT_AT(MxqGameConfig, local_side, 28);
MXQ_ASSERT_SIZE(MxqGameConfig, 32);

MXQ_ASSERT_BLITTABLE(MxqRecordSummary);
MXQ_ASSERT_AT(MxqRecordSummary, move_count, 4);
MXQ_ASSERT_AT(MxqRecordSummary, record_id, 8);
MXQ_ASSERT_AT(MxqRecordSummary, started_at_ms, 16);
MXQ_ASSERT_AT(MxqRecordSummary, ended_at_ms, 24);
MXQ_ASSERT_AT(MxqRecordSummary, added_at_ms, 32);
MXQ_ASSERT_AT(MxqRecordSummary, mode, 40);
MXQ_ASSERT_AT(MxqRecordSummary, human_side, 44);
MXQ_ASSERT_AT(MxqRecordSummary, ai_level, 48);
MXQ_ASSERT_AT(MxqRecordSummary, ai_movetime_ms, 52);
MXQ_ASSERT_AT(MxqRecordSummary, outcome, 56);
MXQ_ASSERT_AT(MxqRecordSummary, end_reason, 60);
MXQ_ASSERT_AT(MxqRecordSummary, provenance, 64);
MXQ_ASSERT_AT(MxqRecordSummary, pinned, 68);
MXQ_ASSERT_AT(MxqRecordSummary, is_active, 69);
MXQ_ASSERT_AT(MxqRecordSummary, reserved0, 70);
MXQ_ASSERT_AT(MxqRecordSummary, game_id, 72);
MXQ_ASSERT_AT(MxqRecordSummary, game, 72 + MXQ_GAME_ID_CAP);
MXQ_ASSERT_AT(MxqRecordSummary, local_side, 76 + MXQ_GAME_ID_CAP);
MXQ_ASSERT_SIZE(MxqRecordSummary, 80 + MXQ_GAME_ID_CAP);

MXQ_ASSERT_BLITTABLE(MxqArchiveInfo);
MXQ_ASSERT_AT(MxqArchiveInfo, archive_version, 4);
MXQ_ASSERT_AT(MxqArchiveInfo, move_count, 8);
MXQ_ASSERT_AT(MxqArchiveInfo, mode, 12);
MXQ_ASSERT_AT(MxqArchiveInfo, human_side, 16);
MXQ_ASSERT_AT(MxqArchiveInfo, outcome, 20);
MXQ_ASSERT_AT(MxqArchiveInfo, end_reason, 24);
MXQ_ASSERT_AT(MxqArchiveInfo, game, 28);
MXQ_ASSERT_AT(MxqArchiveInfo, started_at_ms, 32);
MXQ_ASSERT_AT(MxqArchiveInfo, ended_at_ms, 40);
MXQ_ASSERT_AT(MxqArchiveInfo, game_id, 48);
MXQ_ASSERT_SIZE(MxqArchiveInfo, 48 + MXQ_GAME_ID_CAP);

MXQ_ASSERT_BLITTABLE(MxqEngineBudget);
MXQ_ASSERT_AT(MxqEngineBudget, active_processor_count, 4);
MXQ_ASSERT_AT(MxqEngineBudget, available_bytes, 8);
MXQ_ASSERT_AT(MxqEngineBudget, physical_bytes, 16);
MXQ_ASSERT_SIZE(MxqEngineBudget, 24);

MXQ_ASSERT_BLITTABLE(MxqEnginePlan);
MXQ_ASSERT_AT(MxqEnginePlan, threads, 4);
MXQ_ASSERT_AT(MxqEnginePlan, hash_mib, 8);
MXQ_ASSERT_AT(MxqEnginePlan, sufficient, 12);
MXQ_ASSERT_AT(MxqEnginePlan, reserved0, 13);
MXQ_ASSERT_AT(MxqEnginePlan, reserve_bytes, 16);
MXQ_ASSERT_AT(MxqEnginePlan, usable_bytes, 24);
MXQ_ASSERT_AT(MxqEnginePlan, budget_bytes, 32);
MXQ_ASSERT_SIZE(MxqEnginePlan, 40);

MXQ_ASSERT_BLITTABLE(MxqSearchRequest);
MXQ_ASSERT_AT(MxqSearchRequest, movetime_ms, 4);
MXQ_ASSERT_SIZE(MxqSearchRequest, 8);

MXQ_ASSERT_BLITTABLE(MxqSearchResult);
MXQ_ASSERT_AT(MxqSearchResult, outcome, 4);
MXQ_ASSERT_AT(MxqSearchResult, ticket, 8);
MXQ_ASSERT_AT(MxqSearchResult, position_revision, 16);
MXQ_ASSERT_AT(MxqSearchResult, nodes, 24);
MXQ_ASSERT_AT(MxqSearchResult, score_cp, 32);
MXQ_ASSERT_AT(MxqSearchResult, depth, 36);
MXQ_ASSERT_AT(MxqSearchResult, elapsed_ms, 40);
MXQ_ASSERT_AT(MxqSearchResult, status, 44);
MXQ_ASSERT_AT(MxqSearchResult, move, 48);
MXQ_ASSERT_AT(MxqSearchResult, game_id, 60);
MXQ_ASSERT_AT(MxqSearchResult, profile_id, 60 + MXQ_GAME_ID_CAP);
MXQ_ASSERT_AT(MxqSearchResult, reserved0,
              60 + MXQ_GAME_ID_CAP + MXQ_PROFILE_ID_CAP);
MXQ_ASSERT_SIZE(MxqSearchResult,
                64 + MXQ_GAME_ID_CAP + MXQ_PROFILE_ID_CAP);

/* The 1000-block domains must stay one per block and in ascending order. */
static_assert(MXQ_DOMAIN_ARGUMENT == 1000 && MXQ_DOMAIN_STATE == 2000 &&
                  MXQ_DOMAIN_RULES == 3000 && MXQ_DOMAIN_STORE == 4000 &&
                  MXQ_DOMAIN_ARCHIVE == 5000 && MXQ_DOMAIN_ENGINE == 6000 &&
                  MXQ_DOMAIN_RESOURCE == 7000 && MXQ_DOMAIN_INTERNAL == 9000,
              "the error taxonomy's 1000-blocks are part of the contract");

#undef MXQ_ASSERT_BLITTABLE
#undef MXQ_ASSERT_AT
#undef MXQ_ASSERT_SIZE

} /* namespace */
