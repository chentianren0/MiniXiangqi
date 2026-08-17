# Jieqi Engine Integration

This document defines how the shared core vendors, calls, constrains, and validates the embedded Pikafish rules authority — the engine Jieqi's legality and adjudication are answered by — and what that engine constrains on the core's side of the bridge. It does not define Pikafish internals, fork maintenance, source-level patch design, or upstream synchronization; those belong in the Pikafish fork repository. It states no rule of the game: Jieqi's rules are [jieqi-rules.md](jieqi-rules.md)'s. Mini Xiangqi's and Xiangqi's engine is [engine-integration.md](engine-integration.md)'s subject and the placement games' is [placement-engine-integration.md](placement-engine-integration.md)'s, and this engine shares less with those two than they share with each other, because it does not search.

> **Status: binding.** The C surface every question below is asked through is [core-interface.md](core-interface.md)'s, which is one surface over every embedded engine and shows none of them.

## Scope and ownership

- The shared core owns the vendored rules slice, the bridge that speaks to it, every validation, and the translation between this contract's canonical record and the engine's own dialect, as placed by [architecture.md](architecture.md). Frontends own the user-facing failure presentation.
- The `chentianren0/Pikafish` fork owns any Pikafish source change, fork-specific tests, build implementation, and upstream maintenance.
- The `official-pikafish/Pikafish` repository is reference-only unless the user separately authorizes a contribution.
- Engine source revision, patches, build inputs, and hashes must be pinned reproducibly.
- **This engine plays no moves and evaluates nothing.** It is a rules authority and nothing else: it answers what is legal and what has ended, and it is asked for neither a move nor a score anywhere in this core.
- **This project owns Jieqi's rules, and the engine is held to them.** That is the opposite of the placement games, whose rules authority *is* their pinned engine and which therefore carry no conformance corpus of ours. Here the contract is [jieqi-rules.md](jieqi-rules.md) and the executable authority is that document's `jq-` fixtures: the engine must satisfy them, an approved fixture exposing a mismatch is answered by a focused change in the fork, and engine observations never alter the fixtures' authority. What `rules_version` means for Jieqi is that document's question and never this one's.

## What the engine answers

- **Legality**: the legal moves of a position, and the check state.
- **The endings that read history**: repetition, perpetual check, perpetual chase, and the forty-move rule — which of them fired, and the side the result names.

Two things it is deliberately not asked. **Mate and stalemate are the caller's questions**, from an empty legal-move list and the check state, exactly as they are on the engine Mini Xiangqi and Xiangqi are played on; the engine's own adjudication reports neither. And **disclosure is no engine's business at all**: who may know a hidden identity is [jieqi-rules.md](jieqi-rules.md)'s, decided above this bridge and never asked of anything below it.

## The pin and the fork line

The rules authority is `chentianren0/Pikafish`, branch **`jieqi-mxq`**, commit **`0401526394857ec9b31a878dbae8de81861db330`**, whose base is the upstream `jieqi` branch at commit `9b963f727983a1d9308e0dca48b39c802b8e75a2`.

**The fork's `jieqi` branch is a clean mirror of upstream and carries none of our work; the patch series rides beside it on `jieqi-mxq`.** That is this fork's analogue of the Fairy-Stockfish fork's patched master, and it is what keeps two questions separate: what upstream says, and what this core compiles. Moving to a newer upstream is then a visible operation on a named branch rather than an archaeology of one history.

## The fork change set

The pinned branch carries two focused changes, recorded in the manifest:

- **`Position::rule_judge` reports which rule produced its value.** It gains an optional out-parameter naming one of repetition, perpetual check, perpetual chase, and the forty-move rule. The violating side is not repeated there — it is read from the value the function already returns, and one fact lives in one place. The parameter shadows that value exactly, including the two-fold-repetition bound the engine's own search reads when the function returns false, so a caller may name that result too. And the chase detector reports the one fact only it holds, whether a chase occurred, which is what separates a plain repetition draw from a mutual perpetual chase. Existing callers compile unchanged.
- **`MAX_MOVES` is raised from 128 to 256**, which is one line of `src/types.h`. 128 stands above Xiangqi's derived maximum of 119 and below Jieqi's of 175, and the gap is not a margin but a defect: `MoveList` holds `ExtMove[MAX_MOVES]`, so a position offering more legal moves than that writes past its own storage. Ordinary play reaches such positions — a face-down piece moves as the piece whose square it stands on while the identity it was dealt may stand revealed and moving elsewhere, so one deal puts a chariot's moves and a chariot on the board at once — and the write is inside a frame this core creates, on a call this interface invites, from a record its own structural reading accepts. The raised bound is above the derived maximum with room, and the core pins a position past the old one through its public surface so that the bound cannot quietly fall back.

Both changes are required rather than convenient. The first: the end-reason vocabularies in [core-interface.md](core-interface.md) and [game-data.md](game-data.md) name the rule that ended a game, and the unpatched function reports only that an ending fired and what it is worth — one draw value stands for a threefold repetition, a mutual perpetual check, a repetition that is no chase, and the forty-move rule alike. The second: no validation on this side can prevent the overrun, because the position that causes it is a legal one that the game reaches by playing, and a core that refused it would be refusing the game. The Fairy-Stockfish fork carries a change of the first's purpose for the other two xiangqi games, and the parallel is that purpose alone — the two touch different things and neither is a model for the other. Nothing else is asked of this fork.

## The rules slice

- **Three translation units compile: `position.cpp`, `movegen.cpp`, `bitboard.cpp`.** Their include closure is much wider than they are — some forty-three files, carrying header declarations from the engine's search, UCI and network layers — and **not one of those layers is compiled**: the core builds three objects, and a declaration nothing calls costs nothing. One network header contributes a constant table the position code reads, and no evaluation, search, thread or option code enters the core beside it.
- **Three symbols the closure leaves undefined are supplied as one-line stubs by a link closure of the slice's own**, a file beside the vendored sources rather than part of the bridge: a prefetch hint, the transposition table's first-entry accessor, and the square-name formatter. None of the three has anything to do — the prefetch is advisory, the table accessor is unreachable because the bridge hands the position no table, and the formatter serves only a stream operator nothing calls — and each is declared in the engine's own namespace, which the rename below reaches. Three inert stubs and a wide closure are together the price of leaving the vendored sources exactly as the fork wrote them, and that is lower than the price of a source change to be carried, rebased and re-reviewed at every pin.
- **Bootstrap is `Bitboards::init()` and `Position::init()`, once.** Neither depends on the other, and both must have run before the first position is set or the first move generated, because setting a position already reads the magic tables and the Zobrist keys. There is nothing else: no configuration, no assets, no allocation to plan, and nothing to release.
- **What those two fill is written once and read forever after**, so distinct positions are independent of each other once the bootstrap has run. One position is not: adjudication is a non-const call on it, the move machinery maintains a repetition filter inside it, and the caller owns the state chain a line is played through and must outlive it. So one line is one owner's, which is what a session already is. **Adjudication also stands a second position on the stack.** It copies the object up to but not including the repetition filter, so what it stands there carries sixteen kibibytes of uninitialized filter beside the part it copied. That is a stack-sizing constraint rather than memory anybody manages: a thread that adjudicates needs the room for it, and the bridge decides where positions live rather than leaving it incidental.

## The namespace is renamed wholesale

**The engine's namespace is renamed at compile time**, by a definition on this engine's build target substituting our own name for `Stockfish`, applied to every translation unit of the slice, **to the link closure's stub definitions**, which are declared in that namespace too, and to the bridge, which speaks the renamed types and to nothing else. It reaches that far and no further: a translation unit of the core that speaks to the other engine must never be compiled under it, which is why the bridge is a build target of its own.

The reason is not tidiness. Both embedded Stockfish-family engines define strong symbols in `namespace Stockfish` that collide exactly — thirteen of them, `Position::set` not among them, the two engines' signatures differing there — and two static archives carrying one symbol link with no diagnostic at all, the archive order deciding which body every call reaches. The failure that produces is a **silent wrong-engine binding**: one game answered by another game's rules, with no link error, no runtime error, and nothing in a build log to notice. The rename is what makes the two engines co-linkable, not a convention applied to them afterwards.

## The bridge owns every validation

**The engine validates nothing, and that is stated as its posture rather than as a hazard we rate.** Setting a position has no error path: a malformed record is accepted and silently mangled — a missing pool field zeroes the pool, a wrong field count shifts the counters into one another, unreadable counters become zero — and none of it is reported. There is no validate-position entry to call, and the engine's own assertions are compiled out of the build the app ships.

Reveal letters are unchecked in the same way. A letter naming a piece of the wrong colour is accepted and plants an enemy piece on the board; a letter naming an identity the pool has exhausted is accepted and drives that count below zero, after which the position can no longer be written; and a face-down piece moved without its letter stays face down on a square that is not its own, which is a position this dialect cannot spell and the engine cannot read back.

So the rules below are the bridge's, and each of them is load-bearing:

- **Every position record and every reveal letter reaching the engine is composed or checked by the core first**, against the structural reading and the dealt-start question [core-interface.md](core-interface.md) states.
- **Reveal letters are always the core's own.** The core holds the whole deal, so what a move revealed is derived from the deal and the move — never taken from a file, a user, or another device. The wire names no identity at any point of a session, per [boardgame-protocol-v2.md](boardgame-protocol-v2.md), so nothing remote reaches this engine as a letter.
- **Each move is checked against the engine's own legal list before it is applied**, and a move that is not there stops the replay rather than being skipped. A silently shortened line answers about a position several plies from the one asked about, and looks exactly like an answer.
- **Pool counts are single digits in this dialect**, and the largest count a Jieqi deal reaches is five, so every count the game can produce is spellable. A count outside `0`–`9` is a defect on our side rather than a case to encode around.

## Adjudication replays from the game's start, always

**A position reached by playing a line and the same position set from its own record do not carry the same key.** The engine's flip bookkeeping is why: revealing a mover maintains the position's hash, while the pool decrement for a *captured* face-down piece goes through an accessor that maintains nothing, and setting a position from a record folds the whole remaining pool into the key. Setting a position also leaves its repetition filter empty, where a played position's has been accumulating.

One rule follows: **every adjudication runs over a whole line replayed from the game's own start position, and no adjudication resumes from a mid-game record.** It costs nothing, because it is the shape the core already has — every rules query in [core-interface.md](core-interface.md) is defined over an initial position plus a complete move history, for reasons of its own — and it is what the core's other bridges do.

Within one such replay the divergence cannot mislead, and the argument is exact. The engine decides repetition by comparing hash keys, and it compares them only inside a scan window its own capture reset keeps from reaching across a capture. Every key inside one window was therefore computed over the same remaining pool, so the term the capture bookkeeping failed to fold in is one constant additive offset carried identically by both keys of any comparison, and it cancels under equality. A reveal is not a hazard beside it: the key is maintained directly across one.

## The engine's dialect

Defined here and nowhere else. It is the bridge's private vocabulary: no archive, no fixture, no wire message, and no entry of the C interface spells a position or a move this way, and a reader who meets this dialect above the bridge has found a defect.

**A position is five fields**: the placement, with a face-down piece written `X` for Red and `x` for Black; the side to move; the remaining pool, as twelve letter-and-count pairs in a fixed order with the zero counts written out; the halfmove counter; and the fullmove number.

**A face-down piece's identity is not in that record.** The engine reads it from the square — a face-down piece is whatever starts on the square it stands on, which is Jieqi's own rule about how such a piece moves — and the pool field, not the placement, is what says which identities are still concealed. Two things follow. The dialect cannot spell a face-down piece anywhere but its own start square, and what happens if one tries is not a mangled position but an **out-of-bounds write**: the engine indexes its pool by the piece the square starts with, and a square that starts with nothing indexes outside it. The game never puts a face-down piece anywhere else and the core's structural reading refuses such a record before the bridge is reached, so that rule is a memory guarantee rather than a tidiness one. And the bridge derives the pool from the identities the contract's own record still holds face down, which is where the deal enters the engine at all.

**A move is four characters** — the origin square and the destination — and carries a trailing identity letter exactly where the move changed what is known: five characters when the mover flips up; five when a face-up piece captured a face-down one, the letter being the captured piece's identity; and six when a face-down piece captured a face-down one, the mover's identity first and the captured piece's second. Case names the colour, so the two letters of a six-character token always differ in case.

**Nothing in the slice consumes a move token.** The engine's own move parser and the entry that plays a line through a position are both in sources the core does not compile, so a token is a form the bridge writes and reads rather than a string it hands over. Applying a ply is the bridge's own work, in two parts: the move through the engine's move application, and the reveal through its flip entry, `do_flip`. The pool bookkeeping is the bridge's in the same way, the move application never touching it — and it is the other half of the validation rules above, because what the pool holds is what the next position record spells.

**The engine numbers ranks from zero**, its squares running `a0` to `i9` where this contract's run `a1` to `i10`. A square therefore translates by arithmetic in both directions and never by copying, in a position record as much as in a move token, and a rank that looks right is the failure this sentence exists to prevent.

**The bridge translates in both directions and holds the whole dialect.** From the contract's canonical record — the position record [jieqi-rules.md](jieqi-rules.md) freezes, the coordinate moves, and the deal — it composes this dialect's position and its move tokens; what comes back is legal moves, a check state, and an adjudication. What comes back carries no identity letter either: the engine prints the two squares alone, and which reveal a move made is the deal's answer rather than the engine's, in that direction as in the other.

## Vendoring and build

- The pinned revision reaches the core as a **copied source snapshot**, compiled by a core-owned build description, and never as an artifact the fork built.
- **Nothing in the snapshot is edited here.** Every engine source change belongs to the fork and arrives as a new snapshot at a new pin, which is what keeps the manifest's ordered change list a description of the bytes the core compiles.
- The snapshot carries the three sources and their whole include closure, some forty-three files, because that is what the unedited sources ask for. Only the three compile; the rest arrive as declarations, one of them a network header contributing the constant table the position code reads, and nothing in the snapshot loads a network.
- **The slice compiles wherever the core compiles**, on every development platform rather than only on the platforms the application offers this game on: one conformance harness must produce identical results everywhere, and this game carries a corpus. Where the game is *offered* is the application's question, and [product.md](product.md) answers it.
- **The build is netless, and no network exists to make it otherwise.** This engine's feature set is not the one published Pikafish networks are trained for, and the engine rejects such a file by its own hash check. Nothing is shipped, staged or verified: this engine has no asset of any kind, and the weight preflight the other two engines run has no counterpart here.
- **Search is impossible at this pin, which is a fact rather than a policy.** The whole engine verifies its network before any search and **exits the process** when that fails, so it cannot be made to search at all. The slice carries neither the search nor that verification, so the engine's own way of ending a process is not among the code the core compiles.
- Third-party notices and corresponding-source availability for the GPLv3 engine must be prepared before any build containing it is distributed.

## Failure containment

[architecture.md](architecture.md) forbids an exception or a process exit crossing the core's boundary, so the bridge's entry points contain failure and return a typed failure like every other. Two properties of the slice are what make that reachable rather than hopeful. The engine's own process exit lives in the network verification, which the slice does not carry, and a fork revision that put such a path inside the slice would be a change this contract refuses. And the slice allocates nothing of its own: the position and the state chain a line is played through are the bridge's objects, and the tables behind them are written once at bootstrap and never again. What it does not do is check the bounds of what it is handed, so the bridge's validation rules above are part of this guarantee rather than a courtesy standing beside it.

## What this engine takes no part in

Named because a reader of the other two engine contracts will look for them:

- **No search facade entry answers for this game.** Preparation, the profile identifier, the hint and the search all refuse it, per [core-interface.md](core-interface.md), and the refusals are permanent rather than a state some preparation would clear.
- **No memory policy applies.** This engine allocates no transposition table and asks for no threads, so the adaptive Hash budget, the 4 GiB cap, the 256 MiB minimum and the insufficient-memory presentation reach it nowhere. Preparing or releasing either searching engine neither disturbs it nor is disturbed by it.
- **No level, no thinking time, no diagnostics, no readiness identifier.** Nothing here produces a move, so nothing attributes one. What identifies the build a rules answer came from is the pin recorded in the manifest and the conformance run over the `jq-` fixtures.
- **No lifecycle.** Backgrounding and teardown cancel searches and release what searches hold; there is nothing here to cancel and nothing held.

## The pinned-input manifest

`pinned-inputs.json` is the single source of truth for this engine's inputs as it is for the other two, and records them separately from both:

- the fork's repository, the branch the patch series rides on, the pinned revision, the upstream base it derives from, and the ordered list of focused changes applied at that revision;
- the vendored snapshot's method, its paths, its exclusions, and its per-file hashes;
- no network entry of any kind. The absence is the recorded fact, not an omission in the record.

The build verifies every hash before packaging and fails on a mismatch rather than compiling unverified bytes.
