# AXF, custom variants, Mini Xiangqi, and NNUE

## Source snapshot and short conclusion

This report is based on clean local checkouts at:

- `/Users/tianren/coding/minixiangqi/Fairy-Stockfish` — commit `c19b5f6c66894fdb0e88d0dd100e3885f744760a`
- `/Users/tianren/coding/minixiangqi/pychess-variants` — commit `961fd6dd60ce76d3baced1a77df49ca58edcb315`

**Conclusion:** in Fairy-Stockfish, `axf` is not a custom-variant format. It is the one selectable Xiangqi **chasing adjudication** mode. A standalone custom variant can inherit built-in `minixiangqi` and set `chasingRule = axf` without changing Fairy-Stockfish. That does not, however, reproduce the locally documented Mini Xiangqi chase rules exactly: the engine's AXF code treats river-crossed (“promoted”) soldiers as chaseable, while Mini Xiangqi makes every soldier sideways-capable from the start and the pychess rules exclude soldiers from chase targets. The pychess user-variant path also rejects `chasingRule` outright. Reusing a Mini Xiangqi NNUE is structurally plausible when AXF adjudication is the only rule change, but a distinct custom variant name creates a filename/alias barrier; an external copy can in principle be renamed, whereas transparent reuse of an embedded canonical net needs an engine change or a change to the built-in variant.

## What AXF means

**Proven source facts**

- Fairy-Stockfish defines only `NO_CHASING` and `AXF_CHASING`; the parser maps the INI string `axf` to `AXF_CHASING` and accepts only `axf` or `none`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/types.h:309-311`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/parser.cpp:99-103`.
- The tracked configuration reference calls this option “xiangqi chasing rules”: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variants.ini:120-133`, with the actual property documented at `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variants.ini:250-260`.
- Fairy-Stockfish's source does not expand the acronym. The other tracked checkout expands AXF as **Asian Xiangqi Federation**: `/Users/tianren/coding/minixiangqi/pychess-variants/static/docs/xiangqi.md:22-24`.

**Inference**

`AXF_CHASING` therefore means the engine's implementation of Asian Xiangqi Federation-style long-check/long-chase adjudication. It is a named hard-coded ruleset, not a general mechanism for declaring arbitrary chase rules.

## How custom variants are declared and loaded

**Proven source facts**

An INI block has a new variant name and optional parent:

```ini
[miniaxf:minixiangqi]
chasingRule = axf
```

The syntax and inheritance contract are documented at `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variants.ini:17-41`. The parser reads `[child:parent]`, gathers `key = value` attributes, copies the parent, applies the attributes, rejects an existing child name or a missing parent, and then registers the result: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.cpp:2147-2198`. Consequently, a config cannot replace the built-in `minixiangqi` key.

Loading routes are:

- CLI `load <path>` or `check <path>`; `load <<MARKER` also accepts a here-document: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/uci.cpp:245-285`.
- UCI `VariantPath`, including path lists; setting it parses the files and refreshes `UCI_Variant`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/ucioption.cpp:70-78`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/ucioption.cpp:203-210`.
- `FAIRY_STOCKFISH_VARIANT_PATH` at startup: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/uci.cpp:313-324`.
- In-memory strings through pyffish and the JS/WASM API: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/pyffish.cpp:99-107`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/ffishjs.cpp:478-484`.

Pychess loads its server-side root `variants.ini` through `VariantPath`: `/Users/tianren/coding/minixiangqi/pychess-variants/server/fairy/fairy_board.py:19-23`. Its browser client concatenates the site INI with currently catalogued INIs and passes the resulting string to ffish: `/Users/tianren/coding/minixiangqi/pychess-variants/client/variants.ts:2064-2070`, `/Users/tianren/coding/minixiangqi/pychess-variants/client/main.ts:247-265`.

## Configurable rule dimensions

The authoritative list is the parser, not prose. It supports these broad dimensions:

- board dimensions, initial FEN, piece identities, up to the available custom-piece slots, Betza movement, per-piece mobility regions, and middle/endgame piece values: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/parser.cpp:248-325`. The supported Betza subset is bounded (atoms and directions, selected riders, hoppers, and lame leapers), not arbitrary code: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variants.ini:87-107`.
- promotion/demotion, capture-triggered effects, pawn double/triple steps, en passant, and detailed castling geometry/types: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/parser.cpp:365-453`.
- checking, mandatory capture/drop, pockets and drop restrictions, gating, walling, passing, regional movement hooks, flying generals, and the soldier's sideways-move threshold: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/parser.cpp:454-495`.
- n-move and n-fold rules, perpetual check, repeated-move and AXF chase adjudication, stalemate/checkmate results, Shogi/Shatar/Janggi special endings, extinction, flag goals, check counting, connection goals, material/counting rules, and castling-as-victory: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/parser.cpp:496-550`.

**Inference**

The format is wide but not open-ended. A rule is configuration-only when it is one of these properties or can be encoded in the supported movement notation. New history semantics, new chase classifications, or a new value alongside `axf`/`none` require C++ work.

## The built-in `minixiangqi`

**Proven source facts**

The engine registers `minixiangqi` as a built-in at `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.cpp:1931-1937`. Its definition:

- starts from the chess/fairy base, advertises the Xiangqi GUI template, and sets a 7×7 board;
- removes all pieces, then adds only chariot/rook, blocked horse, king, cannon, and soldier;
- uses `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`;
- confines each king to a 3×3 palace, makes the king move as a wazir (one orthogonal step), disables pawn double-step and castling, makes stalemate a loss, prohibits perpetual check, and enables the flying-general rule.

All of that is in `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.cpp:1222-1246`. The predefined piece movements are cannon `mRcpR`, soldier `fsW`, blocked horse `nN`, and wazir `W`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/piece.cpp:217-224`. The default `soldierPromotionRank = 1` means all Mini Xiangqi soldiers get their sideways movement immediately: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.h:118-130`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.h:891-894`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.h:1305-1316`.

These mechanics agree with the tracked pychess guide's 7×7 board, no river/advisors/elephants, immediate sideways soldiers, stalemate loss, palace, flying generals, blocked horses, chariots, and cannons: `/Users/tianren/coding/minixiangqi/pychess-variants/static/docs/minixiangqi.md:6-18`, `/Users/tianren/coding/minixiangqi/pychess-variants/static/docs/minixiangqi.md:32-70`.

The important omission is that built-in `minixiangqi` does **not** set `chasingRule`; the inherited default is `NO_CHASING`. It does set `perpetualCheckIllegal = true`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.cpp:1242-1245`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.h:123-131`. By contrast, built-in full-size `xiangqi` explicitly sets `AXF_CHASING`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.cpp:1728-1751`.

## Mini Xiangqi rules that do not map cleanly

### 1. Soldier chase exclusion is a likely semantic mismatch

**Proven source facts**

The local Mini Xiangqi guide says a perpetual chase excludes generals and soldiers: `/Users/tianren/coding/minixiangqi/pychess-variants/static/docs/minixiangqi.md:20-26`. Fairy-Stockfish's AXF classifier excludes kings and **unpromoted** soldiers but deliberately leaves promoted/crossed-river soldiers eligible as chase targets: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.cpp:2985-3018`. Mini Xiangqi's rank-1 threshold marks every soldier promoted/sideways-capable from the start.

**Inference**

Simply adding `chasingRule = axf` therefore likely makes Mini Xiangqi soldiers chaseable, contrary to the local rules text. The INI schema has no independent “chase-exempt piece types” property. Raising `soldierPromotionRank` would exclude soldiers from chase, but would also remove their required sideways movement. Exact behavior needs an engine patch separating movement state from chase classification (or adding configurable chase target/attacker sets).

### 2. AXF is hard-coded and heuristic, not declarative

**Proven source facts**

The classifier has explicit value/order cases for horse, cannon, elephant, advisor/fers, and rook, filters symmetric attacks and defenders, and separately handles direct, discovered, pinned, and discovered-check cases: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.cpp:2971-3089`. No INI fields tune those cases. Chased-target bitboards are intersected across repeated positions; unilateral perpetual check or chase scores as a mate/loss, mutual same-class violations draw, and check takes precedence over chase: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.cpp:2648-2718`.

The local Git commit that introduced this code, `9022a70549bf741db2fe4b57af42739b1cb91a2d`, describes it as “basic support” and says some complex cases were not handled. This remains current upstream evidence, not merely historical context: as checked on 2026-07-26, [issue #468, “Refinement of chasing rules,” remains open](https://github.com/fairy-stockfish/Fairy-Stockfish/issues/468), and on 2025-11-23 maintainer `ianfab` closed a newer report as its duplicate while stating that [the chasing-rule implementation “currently is incomplete”](https://github.com/fairy-stockfish/Fairy-Stockfish/issues/938#issuecomment-3568312624).

**Inference**

The broad pychess bullets—one or several checking/chasing pieces, same repeatedly chased unprotected target, check outranking chase, and mutual violations drawing—fit this implementation. Any Mini Xiangqi interpretation with different protected-piece exceptions, soldier handling, piece-value hierarchy, or non-repeating long-chase cycles cannot be expressed in AXF configuration and must be tested against concrete positions before being called exact.

### 3. Enabling AXF changes adjudication/search, not ordinary movement legality

**Proven source facts**

Chase state is computed only when `chasingRule` is enabled: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.cpp:576-599`. Results are produced in the optional-game-end/repetition path rather than in move generation: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.cpp:2618-2718`. Search treats those history-derived results as terminal values at non-root nodes and in quiescence: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/search.cpp:700-719`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/search.cpp:1544-1555`.

Built-in Mini Xiangqi also inherits `nMoveRule = 50`, `nFoldRule = 3`, and an ordinary repetition draw: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.h:122-131`. With AXF enabled, the n-move threshold is adjusted based on recent checks and, for UCCI/UCI-Cyclone, by an additional protocol-specific offset: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/position.cpp:2623-2645`.

**Inference**

An AXF child should explicitly decide whether it wants the inherited 50-move rule; `nMoveRule = 0` is available if not. Engine strength and principal variations can change materially because repeated lines become mate-valued losses rather than draws, even though the board movement rules are unchanged.

**Runtime corroboration**

A local pyffish 0.0.89 smoke test loaded `[minixiangqiaxf:minixiangqi]` with `chasingRule = axf`. For a direct 7×7 rook-chases-unprotected-cannon repetition loop, `is_optional_game_end` returned `(True, 0)` for built-in `minixiangqi` and `(True, -32000)` for the AXF child. This confirms the expected draw-versus-loss consequence for that simple case; it does not validate the full AXF rulebook.

### 4. Current pychess user variants cannot enable AXF

**Proven source facts**

Pychess labels `chasingRule` unsupported because it needs history-aware regional-rule tests, and its validation rejects any non-neutral value before asking Fairy-Stockfish to load it: `/Users/tianren/coding/minixiangqi/pychess-variants/server/catalogued_variants.py:80-90`, `/Users/tianren/coding/minixiangqi/pychess-variants/server/catalogued_variants.py:1530-1557`. A test specifically requires rejection of `chasingRule = axf`: `/Users/tianren/coding/minixiangqi/pychess-variants/tests/test_catalogued_variant_rule_safety.py:68-78`.

This is a pychess product/runtime gate, not an inability of the Fairy-Stockfish INI parser. Enabling a user-catalogued AXF variant therefore needs a pychess change and history/adjudication tests even if Fairy-Stockfish itself is left unchanged.

## Can it reuse the Mini Xiangqi NNUE?

**Structurally, yes in principle, if AXF is the only variant change.**

Fairy-Stockfish derives NNUE input dimensions and index maps from board dimensions, piece types, king mobility, drops/pockets, and initial piece count: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.cpp:2006-2083`. `chasingRule` is absent from that calculation. The feature set is king-square plus piece-square/hand features, not repetition/chase history: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/nnue/features/half_ka_v2_variants.h:37-62`. Parameter loading consumes the current variant's derived dimension and requires the stream to end exactly: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/nnue/nnue_feature_transformer.h:184-204`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/nnue/evaluate_nnue.cpp:117-126`.

**Inference:** a child that changes only `chasingRule` has the same feature layout and piece-count buckets as built-in `minixiangqi`, so its network bytes are compatible. Search supplies the new terminal adjudication. A network trained without AXF may still be suboptimal around repetition/chase choices, but that is a strength/calibration concern rather than a tensor-layout incompatibility.

**The practical obstacle is naming/embedding.**

- NNUE initialization accepts a file only when its basename starts with the selected `UCI_Variant` name or the variant's C++ `nnueAlias`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/evaluate.cpp:83-103`.
- Copying/inheriting a variant calls `init()`, which clears `nnueAlias`; `nnueAlias` is not among the parser's complete official option list: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/variant.h:221-225`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/parser.cpp:365-550`.
- Pychess's browser picker independently requires the uploaded filename to start with the current variant name plus `-`: `/Users/tianren/coding/minixiangqi/pychess-variants/client/view.ts:211-230`.

Thus an external `minixiangqi-….nnue` can in principle be copied/renamed to `miniaxf-….nnue`; the engine does not bind the network header to the variant name. A bundled/embedded canonical net is less flexible: internal loading occurs only for the compiled `EvalFileDefaultName`: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/evaluate.cpp:105-135`. Transparent reuse under a distinct custom name therefore needs an alias/name-gate patch, extraction to an external renamed file, or changing the built-in `minixiangqi` rules so its canonical name remains unchanged.

This compatibility path was also confirmed in the local pyffish smoke test: the existing Mini Xiangqi net loaded and searched after its external copy was renamed to begin with the custom variant identifier, with no Fairy-Stockfish source patch.

Finally, this particular Fairy-Stockfish checkout does **not** contain a bundled Mini Xiangqi net: its compiled default name is the generic chess `nn-3475407dc199.nnue`, and the README points regional built-in nets to separate dedicated releases: `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/src/evaluate.h:41-44`, `/Users/tianren/coding/minixiangqi/Fairy-Stockfish/README.md:20-21`. “Bundled Mini Xiangqi NNUE” is therefore a condition of a downstream/dedicated build, not of this source snapshot.

## Patch/fork boundary

No Fairy-Stockfish patch is needed for a standalone experimental child that accepts the engine's existing AXF semantics:

```ini
[miniaxf:minixiangqi]
chasingRule = axf
# Consider nMoveRule = 0 if the inherited 50-move rule is unwanted.
```

A Fairy-Stockfish patch/fork is required when any of the following is required:

1. exact Mini Xiangqi chase semantics in which sideways-capable soldiers remain chase-exempt;
2. AXF exceptions, attacker/target classes, protection/value rules, or history patterns different from the hard-coded `Position::chased()` logic;
3. changing canonical built-in `minixiangqi` in place (custom blocks cannot replace registered names);
4. transparent access by a distinct custom name to a canonical embedded Mini Xiangqi network, unless the net can be externalized and renamed; or
5. NNUE reuse after changing board geometry, piece set, king mobility, pocket model, or initial maximum piece count—those changes alter the derived input map/bucketing and generally require a matching retrained network.

Separately, publishing the variant through this checkout's user-catalogued pychess flow requires a **pychess** patch to relax the `chasingRule` gate and add full-history adjudication tests. Built-in-name collision rules also prevent a user upload from taking the name `minixiangqi`: `/Users/tianren/coding/minixiangqi/pychess-variants/server/catalogued_variants.py:2586-2601`.
