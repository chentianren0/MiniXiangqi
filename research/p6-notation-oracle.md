# Part 6 · p6-notation — Traditional notation's unhandled cases, and the notation test oracle

> **Workspace-only research.** This file is evidence and a proposal. It is not contract text and
> authorises nothing. The accepted contracts are `MiniXiangqi/docs/*.md`; the main thread authors
> any change to them. Written 2026-07-28.

## 0. What this settles, and what it found that nobody asked for

**Asked.** `interaction-design.md:519` — "Define how traditional notation renders the cases this
contract leaves open, including three or more same-type pieces sharing a file". And the oracle half
of `interaction-design.md:520`, whose required coverage `testing.md:189` already states.

**Delivered.** A resolved rule set (§5) and a **110-row oracle over 24 positions** (§7). Every
position was checked legal and every move checked legal with the engine; every expected string was
hand-written first and then confirmed against an independent renderer, so the table is a
cross-check rather than a transcript of one program's output.

**Found, and not listed as open anywhere.** The contract's unhandled range is not "three, four and
five on one file". It is that range **plus a case the contract does not name**: *two different files
each carrying two or more soldiers*. The accepted rule at `interaction-design.md:166` — 前 or 后
before the piece name, "and omits the file entirely" — becomes **ambiguous** the moment two files
are doubled, because 前兵 then names two different soldiers. Random-play measurement (§4.4) puts
that case at **528 occurrences in 43,690 side-scans**, against **186** for three-on-a-file: the case
the contract does not mention is roughly **three times more frequent** than the one it does.
Four- and five-on-a-file did not occur once in the same sample.

## 1. Method

Three kinds of claim are kept apart throughout.

- **Executed** — run in this workspace, with the exact command or result reported.
- **Cited** — quoted verbatim from a named source with its retrieval details.
- **Reasoned** — my inference, labelled as such.

**Engine.** The prebuilt module at
`/Users/tianren/coding/minixiangqi/discussion-drafts/w-base/pyffish.cpython-314-darwin.so`
(SHA-256 `5636508cae4d02c5a3ee946b32c3e755605d95fd5dbd7a717bc4384e46997c79`, built 2026-07-27 17:30
by the recipe in the `engine-build-and-test` memory), reporting `pyffish.info()` =
`Fairy-Stockfish 270726 LB by Fabian Fichter`, `pyffish.version()` = `(0, 0, 89)`. Variant
`minixiangqi`, `pyffish.start_fen('minixiangqi')` = `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`,
byte-identical to the FEN frozen at `xiangqi-rules.md:33`. Nothing under `MiniXiangqi/` or any
worktree was modified; the harness ran from `/tmp`.

**Position-legality predicate** (executed for all 24 oracle positions). A position counts as legal
only if all four hold: `pyffish.validate_fen` returns `FEN_OK`; both generals are inside their own
palaces; the two generals do not face each other down an otherwise empty file; and the side *not*
to move is not in check — tested by asking the engine for the mover's legal moves and requiring
that none of them lands on the opposing general's square. The fourth test has teeth: Fairy-Stockfish
does generate a general-capturing move from an illegal position (verified: from
`3k3/3R3/7/7/7/7/4K2 w - - 0 1` it offers `d6d7`), so the check is not vacuous. The third test is
mine rather than the engine's, because the engine tolerates a facing-generals FEN as input while
correctly refusing to *create* one (verified: from `3k3/7/7/7/7/7/2K4 w - - 0 1` the only legal
general move is `c1c2`; `c1d1` is withheld).

## 2. What the accepted contract already fixes

From `interaction-design.md:159-168` (all accepted, all normative):

- files numbered **from each player's own right**, so the two sides number oppositely;
- **Red writes Chinese numerals, Black Arabic**, and this applies "to every number in a move, not
  only to the file";
- a move names **piece, file, direction, value**; directions are 进 forward, 退 back, 平 across;
- chariot, cannon, soldier and general: 进/退 carry a **rank count**, 平 carries a **destination
  file**;
- the horse: the value after 进/退 is the **destination file**;
- two same-type pieces on one file: **前/后 before the piece name, file omitted** — 前炮退二, not
  炮前退二; 后 is the one nearer its own side.

Piece characters, `interaction-design.md:61-68`: Red 帅 俥 傌 炮 兵, Black 将 车 马 砲 卒. Coordinates,
`xiangqi-rules.md:34,36`: files `a`–`g` from Red's left, ranks `1`–`7` from Red's back rank; the
canonical move is origin-then-destination and never changes.

**Reasoned, and used throughout.** Red numbers files from its own right, so `g`=一, `f`=二, `e`=三,
`d`=四, `c`=五, `b`=六, `a`=七; Black numbers from its own right, so `a`=1 … `g`=7. Both generals
therefore start on their own file 4/四 — the centre file of seven — which is the consistency check
that the two mappings are oriented correctly.

## 3. What established practice says

### 3.1 The governing rulebook stops at three, and covers every piece type

**Cited.** 《象棋竞赛规则（2020版）》, retrieved 2026-07-28 from `http://www.gdchess.com/xqdata/xq2020/`.

第1条 1.1:

> 九道直线，红棋方面从右到左用中文数字一至九来标识，黑棋方面从右到左用阿拉伯数字1至9来标识。

第7条 7.5, the whole of what the rulebook says about same-file disambiguation:

> 如果一方相同兵种的子在同一道直线上，在走动其一时，记录应用"前""中""后"来表明，如：前马退四（前马4）、后车平六（后车6）等。

Three things follow. First, 1.1 is direct authority for the accepted file-numbering and numeral
rules — they are not an app invention. Second, 7.5 extends 前/中/后 to **any** same-type pieces, not
only soldiers, and its examples (前马退四, 后车平六) **omit the origin file**, which is direct
authority for `interaction-design.md:166`. Third, and decisively for this brief: **the governing
rulebook publishes no rule for four or five on a file, and none for two doubled files.** The open
item is genuinely open at the level of the sport's own rulebook, not merely in our contract.

### 3.2 The computer standard resolves four, five, and the two-file case

**Cited.** 《中国象棋电脑应用规范（二）：着法表示》, 象棋百科全书网, 2004年11月初稿, 2006年2月修订,
retrieved 2026-07-28 from `https://www.xqbase.com/protocol/cchess_move.htm` (GB-encoded; decoded
with `iconv -f GB18030`). Section 四、中文纵线格式:

> 一、仕(士)和相(象)如果在同一纵线上，不用“前”和“后”区别，因为能退的一定在前，能进的一定在后。

> 二、兵要按情况讨论：(1) 三个兵在一条纵线上：用“前”、“中”和“后”来区别；(2) 三个以上兵在一条纵线上：最前面的兵用“一”代替“前”，以后依次是“二”、“三”、“四”和“五”；(3) 在有两条纵线，每条纵线上都有一个以上的兵：按照“先从右到左，再从前到后”(即先看最左边一列，从前到后依次标记为“一”和“二”，可能还有“三”，再看右边一列)的顺序，把这些兵的位置标依次标记为“一”、“二”、“三”、“四”和“五”，不在这两条纵线上的兵不参与标记。

and, on numerals:

> 但是代表同一纵线上不同兵的“一二三四五”(它们类似于“前中后”的作用)例外 …… 那么某步着法就应该写成“一卒平５”。

The document's stated motive for the pure-number scheme is engineering, not readability: the
traditional form needs five characters (前兵四平五) and four 16-bit characters fit one 64-bit word.

**Two defects in this source, reported rather than smoothed over.**

1. Clauses (1) and (2) **contradict each other for exactly three**: 三个以上 ordinarily includes
   three, yet (1) assigns three to 前/中/后. The phrase 最前面的兵用“一”代替“前” only makes sense as
   an *extension* of a scheme whose front member was 前, so the intended reading — and the one every
   other source supports — is (1) three → 前/中/后, (2) **more than** three → 一/二/三/四/五.
2. Clause (3)'s parenthetical gloss (即先看最左边一列) **contradicts its own normative sentence**
   (先从右到左). The worked example decides it. The source's table gives, for four pawns on Red's
   files 四 and 六:

   | 中文纵线格式 | 坐标格式 |
   |---|---|
   | 一兵平五 | F8-E8 |
   | 二兵平五 | F6-E6 |
   | 三兵平五 | D8-E8 |
   | 四兵平五 | D6-E6 |

   **Reasoned.** In that document's coordinate figure, files run `a`–`i` left to right from Red, so
   Red's file 四 is `f` and file 六 is `d`. Labels 一 and 二 go to the `f` pawns and 三 and 四 to the
   `d` pawns — that is, **ascending own-file number first** (四 before 六, i.e. right to left from
   Red), **then front to back**. The normative sentence is right and the gloss is wrong.

### 3.3 The traditional variant, which keeps 前 and keeps the file

**Cited.** 中文维基百科, 象棋 § 中式记谱法, retrieved 2026-07-28:

> 当兵卒在同一纵线达到3个，用前、中、后来区分，达到4个，用前、二、三、四（或后）区分，达到5个，用前、二、三、四、五（或后）区分。

> 当兵卒在两个纵线都达到两个以上时，按照旧的记谱方式举例：前兵九平八，此时可省略兵（卒），记做前九平八，以达到都用4个汉字记谱的要求……

So the traditional line differs from the computer standard on both open points: it keeps **前** as
the front member of the four/five series (with 后 tolerated for the rear), and it handles two
doubled files by **restoring the file** — 前兵九平八, five characters, optionally abbreviated to
前九平八 by dropping the piece name instead.

### 3.4 The WXF-hosted English document names the trigger, and records its own uncertainty

**Cited.** *Chinese Chess File Format*, drafted by Huayong Yang, hosted by the World Xiangqi
Federation at `https://www.wxf-xiangqi.org/images/computer-xiangqi/chinese-chess-file-format.pdf`,
retrieved 2026-07-28 (text extracted from the PDF content streams; the extractor leaves line-wrap
artefacts inside a few words, which are repaired below and changed nothing else). Appendix A, XiangQi Review / AXF
notation:

> "If there are 2 sets of 2 pawns on the same file, these pawns are labeled with the letters A, B,
> C, D. They are labeled from RED's point of reference from the RIGHT, from North to South."

> "If you have 4 or 5 pawns on one file, they are labeled the same, from red's viewpoint, A-D.
> However, once the pawns move and there is only 3 pawns left on a file, then you revert to the
> regular (+ - =) when one of them moves. You only use the letters when you have more than 3 pawns
> on a file, or 2 sets of 2 pawns on 2 files."

> "[HY: according to Stephen Leary, the 3-2 situation is definitely '2 sets of stacked pawns', so
> one would have to assign letters to all 5. However, he said he was not 100% sure.]"

This is the most useful of the four sources for our purpose, for three reasons. It states the
**trigger condition** exactly as the arithmetic requires — *more than three on a file, or two
doubled files* — and nothing else triggers it. It confirms that **three reverts to 前/中/后**
(+ - =). And it is the only source honest enough to record that the **3-2 split is unresolved even
among its own authors** — which is precisely the case our five soldiers make reachable.

Its labelling order is Red-absolute ("from RED's point of reference"), where the Chinese computer
standard's is mover-relative. For Red they agree; for Black they do not. That conflict is one more
reason not to adopt a scheme that numbers across two files at all (§5).

### 3.5 What the project's own engine emits (executed)

Fairy-Stockfish implements a WXF renderer, reachable as
`pyffish.get_san(variant, fen, move, False, pyffish.NOTATION_XIANGQI_WXF)`. Measured on the oracle
positions:

| position | move | FS WXF | reading |
|---|---|---|---|
| two chariots on a file | `a5b5` / `a2b2` | `R+=6` / `R-=6` | front/rear marks, **no file** |
| two soldiers on a file | `d5d6` / `d3d4` | `P++1` / `P-+1` | front/rear marks, **no file** |
| three soldiers on a file | `d4d5` / `d3e3` / `d2c2` | `14+1` / `24=3` / `34=5` | index **from the front**, **with file** |
| five soldiers on file `c` | `c6c7` … `c2d2` | `15+1` … `55=4` | index 1–5 from the front, with file |
| two doubled files (`b`,`e`) | `b5b6` / `b3b4` / `e4e5` / `e2e3` | `16+1` / `26+1` / `13+1` / `23+1` | index **restarts per file**, with file |
| lone soldier | `g2f2` | `P1=2` | plain form |

**Reasoned, and worth stating because it contradicts a widely repeated claim.** Fairy-Stockfish
numbers **from the front** (index 1 is the most advanced pawn) and **keeps the file**, and its index
**restarts on each file** rather than running globally across two. That directly contradicts the
"1 is the pawn closest to you" reading found in several secondary write-ups, and it agrees with the
Chinese sources on direction. It also means the engine's own trigger for the indexed form is
*(three or more on the file) or (more than one doubled file)* — the same trigger the WXF-hosted
document states, and the same one adopted in §5.

### 3.6 Where the four sources agree and disagree

| case | 2020 rulebook | xqbase computer standard | Chinese traditional (Wikipedia) | WXF-hosted AXF | Fairy-Stockfish |
|---|---|---|---|---|---|
| 2 on a file | 前/后, no file | 前/后, no file | 前/后, no file | `+`/`-`, no file | `+`/`-`, no file |
| 3 on a file | **前/中/后, no file** | 前/中/后 | 前/中/后 | reverts to `+ = -` | index **+ file** |
| 4–5 on a file | *silent* | 一/二/三/四/五 from the front, no file | **前**/二/三/四(/五) (或后) | letters A–E from Red's right | index + file |
| two doubled files | *silent* | one 一–五 series **across both**, no file | **前/中/后 + file** (前兵九平八), or drop the piece name | letters across both, Red-absolute order | index + file, **per file** |
| 3-2 split | *silent* | numbered across both | (implied: per file, with file) | **explicitly uncertain** | per file, with file |
| Black's ordinal numerals | n/a | **Chinese even for Black** (一卒平５) | n/a | n/a | digits (Latin format) |

Unanimous: two → 前/后 without a file; three → 前/中/后. Contested: everything else.

## 4. What the frozen board and piece set actually make reachable

### 4.1 The piece census bounds the problem

From the frozen starting FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR`, each side has 2 chariots,
2 horses, 2 cannons, 1 general and 5 soldiers, on 7 files and 7 ranks.

**Reasoned.** Only soldiers can put three or more of one type on a file, and only soldiers can
double two files at once, because every other type has at most two members. Both open cases are
therefore soldier-only, exactly as the sources assume — this is not an accident of Mini Xiangqi, it
is the same reason full Xiangqi's rules talk about 兵/卒.

### 4.2 An arithmetic fact that removes the worst interaction

**Reasoned, and load-bearing.** With five soldiers, four-or-five on one file leaves at most one
soldier over, so **it is impossible to have four on a file and a second doubled file**; and if two
files are doubled, the largest stack is three (a 3-2 split). The two hard cases are therefore
**mutually exclusive on this board**. Whatever symbols the four/five case uses, a reader can never
meet them in a position where a second file is also doubled. Capturing soldiers only strengthens
this.

That fact is what makes the scheme in §5 safe: 一/二/三/四/五 is used for one purpose and one
purpose only, and never has to be told apart from a file number in the same string.

### 4.3 Both hard configurations are reachable by legal play (executed)

Bare positions being legal is a weak claim. Both were reached from the frozen starting position by
legal alternating play, verified move by move against `pyffish.legal_moves`, with Black replying
legally at every turn, no captures by Black, no checks, and no position repeated.

**Five Red soldiers on one file** — 44 plies (22 Red moves). Red funnels `c2,a2,d2,e2,g2` onto file
`b`. Final position, Red to move:

```
2c3n/1P1pk2/rP1npcr/pP1p3/1P3p1/1P5/RCNKNCR w - - 44 23
```

Red soldiers on `b2 b3 b4 b5 b6`. Maximum repetition of any position over the whole game: 1.
Rendered soldier moves in that reached position include 一兵进一 (`b6b7`), 二兵平七 (`b5a5`),
五兵平五 (`b2c2`).

**Two doubled files** — 10 plies (5 Red moves: `c2b2 b2b3 a2b2 e2e3 d2e2`). Final position, Red to
move:

```
1cnkn1r/r1pp2p/4pc1/p6/1P2P2/1P2P1P/RCNKNCR w - - 10 6
```

Red soldiers on `b2 b3` (file 六), `e2 e3` (file 三) and `g2` (file 一) — two doubled files plus one
spare, on move 6, with every other piece still on the board. This is not a contrived endgame; it is
five ordinary soldier moves from the start.

### 4.4 How often the cases arise (executed)

300 random legal games of up to 80 plies, 21,888 positions, each position scanned once per side
(43,690 side-scans):

| soldier configuration | side-scans | share |
|---|---|---|
| no file doubled | 31,413 | 71.9% |
| one file with 2 | 11,563 | 26.5% |
| **two files each with 2 or more** | **528** | **1.21%** |
| **three on one file** | **186** | **0.43%** |
| four or five on one file | 0 | 0% |

**Reasoned.** Random play wanders more than real play, so these are upper bounds on frequency, not
predictions. But the *ordering* is the finding: the case the contract does not name is about three
times as common as the case it does. A move list that renders 前兵进一 for two different soldiers is
not a curiosity the app will never hit.

## 5. The resolved rules

Proposed contract text, written to slot into `interaction-design.md` § *User-visible notation*.
Rules R1–R3 restate what is already accepted or already mandated by the 2020 rulebook; R4 and R5
are the new material.

Let *T* be the moving piece's type, *S* its side, *n* the number of *S*'s pieces of type *T* standing
on the moving piece's own file, and *D* the number of *S*'s files carrying two or more pieces of
type *T*.

- **R1 — plain form (n = 1).** Piece name, then the origin file in the mover's own numbering.
  *Accepted.*
- **R2 — a pair (n = 2).** 前 or 后 before the piece name; the file is omitted. 前 is the piece nearer
  the opponent, 后 the piece nearer its own side. *Accepted; also 第7条 7.5.*
- **R3 — three (n = 3).** 前, 中 or 后 before the piece name, front to back; the file is omitted.
  *Mandated by 第7条 7.5, which reads on any 相同兵种; unanimous across all four sources.*
- **R4 — four or five (n ≥ 4).** 一, 二, 三, 四, 五 before the piece name, **counted from the front**;
  the file is omitted. **The ordinal is written in Chinese numerals for both sides**, because it
  stands in for 前/中/后 rather than counting anything. Reachable only for soldiers, and only when no
  second file is doubled (§4.2).
- **R5 — more than one doubled file (D ≥ 2).** The origin file, in the mover's own numerals, is
  **restored after the piece name**, and the leading word is R2's or R3's as usual: 前兵六进一,
  后卒3进1, 中兵五平四. Pieces of type *T* that are alone on their file are unaffected and keep R1.
  Reachable only for soldiers, and only in a 2-2 or 3-2 shape (§4.2).

Everything else is unchanged: 进/退 carry a rank count for chariot, cannon, soldier and general and a
destination file for the horse; 平 carries a destination file; captures are not marked; the string
never depends on which way the board is facing.

### 5.1 Why R4 counts from the front and uses pure numbers

The three sources that address four and five all count **from the front** (xqbase 最前面的兵用“一”;
AXF "from North to South" for Red; Fairy-Stockfish's index 1 = most advanced, measured in §3.5).
There is no live dispute about direction, only about the *symbol* for the front member: 一 (xqbase,
Fairy-Stockfish) or 前 (Wikipedia's traditional line).

**Reasoned, choosing 一.** Wikipedia's own statement of the traditional form is internally unstable —
it offers 前、二、三、四（或后）, leaving the rear member as either 四 or 后, which is exactly the kind
of "either is fine" that a test oracle cannot encode. A pure 一–五 series has one member per
position, is what the sport's computer standard specifies, and is what this project's own engine
emits. The cost is real and should be stated: a reader who meets 二兵平三 in the app and has only ever
seen 前/中/后 in a book has to learn one more convention — but that reader is meeting a position that
did not occur once in 21,888 random positions, and the alternative is a rule with two legal answers.

### 5.2 Why R5 restores the file instead of numbering across both

The alternative is xqbase clause (3): number all the involved soldiers 一–五 across both files and
keep omitting the file. Three arguments against it, in decreasing order of weight.

1. **It is the one rule the sources cannot agree on.** xqbase orders the labels mover-relatively
   (先从右到左), the WXF-hosted document orders them from **Red's** viewpoint regardless of side, and
   the WXF-hosted document's own editor records that the 3-2 case was not settled among its authors.
   Adopting a scheme whose sources disagree, for a case that occurs in 1.2% of positions, buys
   nothing.
2. **It makes one symbol mean two things.** Under R4 a reader who sees 三兵 counts down one file.
   Under xqbase (3) the same 三兵 requires scanning two files in a prescribed order. §4.2 shows the
   two cases can never co-occur, so nothing forces the collision — but only if we decline it.
3. **The file is the disambiguator the app already teaches.** Every plain move carries its file, the
   numeral strips beside the board carry the files, and `interaction-design.md:167` makes the strip
   follow the board's orientation for exactly this reason. Restoring the file reuses a thing the
   reader already reads; a global ordinal introduces a new one.

R5 is also the attested traditional form (前兵九平八, §3.3) and matches Fairy-Stockfish's per-file
indexing (§3.5). Its cost is that the string becomes **five characters** in a list whose every other
entry is four, so the move-list layout must tolerate a five-character cell. That is a constraint on
the layout work, not a reason to prefer a worse rule; the 64-bit-word argument that motivated the
four-character form at xqbase has no application here.

The abbreviated traditional variant — drop the piece name instead, 前六进一 — was rejected: it
survives only because soldiers are the only type it can happen to, and a learner's move list that
sometimes stops naming the piece is worse than one that is sometimes five characters long.

### 5.3 The one place this contradicts accepted text, and why

`interaction-design.md:163` says Red's Chinese and Black's Arabic numerals apply "to **every** number
in a move". R4's ordinal is written in Chinese for Black too — 一卒进1, not 1卒进1 — following
xqbase's explicit exception (§3.2). **Reasoned:** the ordinal is not a number in the move; it is the
positional word 前/中/后 continued past three, and writing it as an Arabic digit next to Black's
Arabic file and rank numbers would make 1卒进1 read as though the first and last digits were the same
kind of thing. This is the one point in §5 that amends accepted text rather than extending it, and it
is listed for the owner in §10.

## 6. What must change in the accepted contracts

1. `interaction-design.md:166` — "omits the file entirely" is true only while at most one file is
   doubled. It needs R5's qualification, or it is ambiguous in 1.2% of positions.
2. `interaction-design.md:163` — "every number in a move" needs R4's ordinal exception, or R4 cannot
   be written for Black (§5.3).
3. `interaction-design.md:166` — "When two pieces of the same type stand on one file" becomes "two or
   more", with R3 and R4 following.
4. `interaction-design.md:519` — delete; superseded by R3–R5.
5. `interaction-design.md:520` — the oracle clause is answered by §7; the icon-symbol clause is not,
   and stays open (§10).
6. `testing.md:189` — the coverage list stops at "when two same-type pieces share a file". It must
   gain: three on a file; four and five on a file; more than one doubled file; the Chinese ordinal
   for Black; and the invariant that a capture renders exactly as a quiet move.
7. **Record R3–R5 as an interpretation of convention**, the way the 一将一捉 reading is recorded in
   `xiangqi-rules.md`. The sport's own rulebook is silent on four, five and the two-file case
   (§3.1), so this is our reading of practice, not a transcription of a normative source, and the
   contract should say so rather than implying an authority that does not exist.

## 7. The oracle

**How to read it.** Each block gives one position as a 6-field FEN in the frozen coordinate system,
then the moves exercised in it. `move` is canonical origin-then-destination notation exactly as
`xiangqi-rules.md:36` defines it and as fixtures and archives store it. `traditional string` is what
the move list and board must render.

**What was verified for every row (executed).** The position passes the four-part legality predicate
of §1. The move is in `pyffish.legal_moves` for that position. The expected string was written by
hand from the rules in §5 before any code produced it, and an independent renderer reproduces it
character for character. Every CJK character in every expected string was audited against the exact
codepoints taken from `interaction-design.md`'s own piece table, so a visually identical wrong
character cannot hide in the table. Result: **110 rows, 24 positions, 0 failures.**

**Invariants the table also pins, which no single row states.**

- A capture renders exactly as a quiet move; there is no capture mark (row 110, and rows 23 and 27).
- The string never depends on board orientation: it is computed from the mover's own numbering, so
  Flip Board changes nothing in the move list. Rows 45-53 and the Red/Black mirror pairs make this
  checkable by inspection.
- 前 always means "nearer the opponent". Rows 45-49 (Red, so higher rank) and rows 50-53 (Black, so
  lower rank) are the same geometry with opposite answers.

## 8. Cross-checks

### 8.1 The property that actually makes a notation correct (executed)

A notation is only usable if, in any position, no two legal moves render the same string. Tested by
playing **300 random legal games of up to 80 plies**, rendering **every legal move** in each of the
**21,888** positions reached, and requiring the strings within a position to be pairwise distinct.

**Result: 0 collisions.** No position produced two legal moves with the same traditional string
under R1–R5.

**Reasoned, on why this holds.** R1 carries the origin file, so two pieces of the same type on
different files can never collide. R2–R4 apply only within one file and give each piece a distinct
leading word. The only structural gap is two pieces of the same type on *different* files both
disambiguated without a file — which is exactly what R5 closes. Random play does not reach four or
five on a file (§4.4), so those two branches rest on the oracle rows and on the argument, not on
this scan.

### 8.2 Agreement and divergence with the engine's own WXF renderer (executed)

`pyffish.get_san(..., NOTATION_XIANGQI_WXF)` was captured for all 110 oracle rows. It agrees with
R1–R5 on every structural decision that matters — direction of counting, which piece is "front",
per-file rather than global indexing, and the trigger for the indexed form — and diverges on exactly
two presentational points:

- for **three** on a file it uses the numeric index (`14+1`) where R3 uses 前/中/后, per the 2020
  rulebook;
- it keeps the file in **every** indexed form, where R4 omits it (the file is not needed when only
  one file is doubled).

**Reasoned.** This makes the engine a usable *partial* oracle for an implementation: a renderer can
be differentially tested against `get_san` for the R1/R2 cases and for the *structure* of the rest,
with the two divergences whitelisted. It is not a substitute for the table, because the divergences
are precisely the open cases.

### 8.3 Homoglyph audit (executed)

Every CJK character in every expected string was checked against a fixed codepoint alphabet built
from `interaction-design.md`'s own piece table — 帅 U+5E05, 将 U+5C06, 俥 U+4FE5, 车 U+8F66,
傌 U+508C, 马 U+9A6C, 炮 U+70AE, 砲 U+7832, 兵 U+5175, 卒 U+5352 — plus 进 U+8FDB, 退 U+9000,
平 U+5E73, 前 U+524D, 中 U+4E2D, 后 U+540E and 一二三四五六七. This check earned its place: an earlier
draft of the harness carried 俲 U+4FF2 for 俥 U+4FE5, which is indistinguishable at reading size and
would have shipped a wrong character into an approved oracle.

## 9. Two Apple-platform traps that this rule set walks into

**Apple publishes nothing on Xiangqi notation, on rendering game move lists, or on non-Latin
notation systems.** Searched the Apple developer documentation; there is no such page, and I am not
going to manufacture one. The recommendations below are mine. Two documented platform behaviours do
bear on §5, and both would corrupt the notation silently.

**Locale digit substitution.** Black's numbers are Arabic digits by accepted rule
(`interaction-design.md:163`). Apple's *Preparing dates, currencies, and numbers for translation*
(Xcode documentation) instructs developers to render numbers through `formatted()` / format styles
so they localise; and Foundation's *Language-Dependent Information Constants* documents
`NSDecimalDigits` as "Strings that identify the decimal digits in addition to or instead of the
ASCII digits." **Recommendation:** the numbers in a move string must never pass through a
locale-aware formatter. They are game content in exactly the sense
`interaction-design.md:71` already fixes for the piece characters — "identical in every supported
language and … never translated" — and must be emitted as literal characters. Otherwise a device in
a locale with its own digit set can turn 卒4进1 into a string no Xiangqi book contains.

**Speech language.** A move list is Chinese text that may sit inside an English interface. UIKit's
*Speech attributes for attributed strings* documents `UIAccessibilitySpeechAttributeLanguage` as
"A key that indicates the language to use when speaking a string", and `accessibilityLanguage` is
listed under *Defining accessibility text and language*. **Recommendation:** move-list strings and
any spoken move announcement carry an explicit Simplified-Chinese speech language, so VoiceOver in
an English locale does not read 兵四进一 with an English voice. This belongs to part 8's
announcement design (`interaction-design.md:532`) rather than to this item; it is flagged here so it
is not lost between the two.

## 10. Open for the owner

Four decisions below are genuinely the product owner's. Everything else in this report is a design
or domain call and has been made, with its reasoning exposed so it can be disagreed with exactly.

### 10.1 Whether to accept the one amendment to accepted copy rules

R4 writes Black's ordinal in Chinese — 一卒进1 — against `interaction-design.md:163`'s "every number
in a move". Two options.

- **Accept the exception** (recommended, §5.3). Matches the one source that specifies this case at
  all. Cost: an accepted normative sentence gains a carve-out, and a reader of the contract must
  hold two rules where there was one.
- **Keep the accepted rule absolutely** — write 1卒进1. Cost: no source writes it that way; the
  leading 1 and the trailing 1 are different kinds of thing rendered identically, which is the exact
  confusion 一 was chosen to avoid; and the app would be the only place this form exists.

The decision is the owner's because it changes accepted contract text rather than filling a gap in
it. It affects at most the four/five-on-a-file case, which did not occur in 21,888 random positions.

### 10.2 What a user reading icon symbols gets from a character-based move list

`interaction-design.md:520` first clause, premised on the accepted `:168` — an icon user "still
reads a character-based move list". Only what is *additionally* offered is open. Five options, in
increasing cost.

- **Nothing further.** Cost: the user who chose icons because they cannot read 兵 and 俥 gets help on
  the board and none in the list — the feature stops at the board edge. Zero build cost.
- **A legend in Help**, five icons against five characters. Cost: one Help section inside an already
  bounded eight-topic scope; does not help in the moment of reading a move.
- **A move-list footer or header legend**, always visible. Cost: permanent vertical space in the
  layout that is tightest exactly when accessibility text sizes are in use.
- **Icons inline in the move list**, replacing the piece character. Cost: highest — the string stops
  being traditional notation and cannot be carried into a book, which is the stated reason
  (`:161`) traditional notation was chosen; it contradicts accepted `:168`; and it needs an icon
  legible at text size plus its own accessibility label.
- **Accessibility-layer only** — the move's spoken label names the piece in the interface language.
  Cost: nothing visual, but sighted icon users get nothing.

This is the owner's because it is a scope question about who the icon feature is for, not a question
with a right answer.

### 10.3 Whether Help teaches R3–R5

Help's scope is a hard accepted boundary of eight topics, read-only, no analysis or drills
(`interaction-design.md:527` and the accepted text above it), and one notation-adjacent content item
is already mandated — that there is no river and Help calls it out (`:123`).

- **Teach only the base notation.** Cost: a user who meets 中兵平三 or 前兵六进一 has nowhere in the
  app to find out what it means. Frequency: 0.43% and 1.21% of positions respectively (§4.4).
- **Teach the base plus 前/后 and 中.** Cost: one short subsection; covers everything measured to
  occur in random play.
- **Teach all of R1–R5.** Cost: the four/five case takes as much text as the rest combined and
  describes something a player will almost certainly never see.

### 10.4 Where the oracle lives

`testing.md:189` already requires the table to be "approved alongside the notation itself". It does
not say where it lives, and the three homes have different consequences.

- **In `interaction-design.md`**, beside the rules. Cost: 110 rows in an already 73 KB document; a
  reviewer reads it, but nothing executes it.
- **In `testing.md`**. Cost: `testing.md` is still a draft contract whose acceptance is blocked on
  execution (part 8, item 8.3); putting the oracle there risks it staying non-binding along with
  everything else, which is the risk issue #2 flags.
- **As a fixture file under `fixtures/`**, next to the accepted rules fixtures, with the prose
  contract citing it. Cost: a new fixture category and its schema; benefit: the oracle becomes
  executable rather than readable, which is what makes a notation testable at all — and the fixtures
  directory is already the accepted home for "the identifiers that connect prose to executable
  conformance fixtures" (`xiangqi-rules.md:3`).

Recommended: the fixture file, with the rules and a handful of illustrative rows in
`interaction-design.md`. But the cost of a new fixture category is a delivery decision, not a design
one.

---

## Appendix A — The oracle table

110 rows over 24 positions. FENs are 6-field records in the frozen coordinate system; moves are
canonical origin-then-destination. Every position legal, every move legal, every string verified
(§7).

**`3k3/7/7/R6/7/7/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 1 | `a4a1` | 俥七退三 | R1 chariot 退 rank-count, Red numerals, file a = 七 |
| 2 | `a4a7` | 俥七进三 | R1 chariot 进 rank-count |
| 3 | `a4g4` | 俥七平一 | R1 chariot 平 destination file |

**`3k3/7/7/r6/7/7/4K2 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 4 | `a4a7` | 车1退3 | R1 Black chariot 退, Arabic, file a = 1 |
| 5 | `a4a1` | 车1进3 | R1 Black chariot 进 |
| 6 | `a4g4` | 车1平7 | R1 Black chariot 平, dest g = 7 |

**`3k3/7/7/3N3/7/7/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 7 | `d4c6` | 傌四进五 | horse value = destination file |
| 8 | `d4e6` | 傌四进三 | horse |
| 9 | `d4b5` | 傌四进六 | horse |
| 10 | `d4f5` | 傌四进二 | horse |
| 11 | `d4b3` | 傌四退六 | horse 退 |
| 12 | `d4f3` | 傌四退二 | horse 退 |
| 13 | `d4c2` | 傌四退五 | horse 退 |
| 14 | `d4e2` | 傌四退三 | horse 退 |

**`3k3/7/7/3n3/7/7/4K2 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 15 | `d4c2` | 马4进3 | Black horse 进, Arabic dest file |
| 16 | `d4e2` | 马4进5 | Black horse |
| 17 | `d4b3` | 马4进2 | Black horse |
| 18 | `d4f3` | 马4进6 | Black horse |
| 19 | `d4c6` | 马4退3 | Black horse 退 |
| 20 | `d4e6` | 马4退5 | Black horse 退 |
| 21 | `d4b5` | 马4退2 | Black horse 退 |
| 22 | `d4f5` | 马4退6 | Black horse 退 |

**`3k3/2r4/7/2p4/7/2C4/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 23 | `c2c6` | 炮五进四 | cannon capture over one screen; capture is not marked |
| 24 | `c2c3` | 炮五进一 | cannon quiet 进 |
| 25 | `c2d2` | 炮五平四 | cannon 平 |
| 26 | `c2c1` | 炮五退一 | cannon 退 |

**`4k2/2c4/7/2P4/7/2R4/3K3 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 27 | `c6c2` | 砲3进4 | Black cannon capture; Black cannon is 砲 |
| 28 | `c6c5` | 砲3进1 | Black cannon 进 |
| 29 | `c6d6` | 砲3平4 | Black cannon 平 |
| 30 | `c6c7` | 砲3退1 | Black cannon 退 |

**`3k3/7/7/3P3/7/7/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 31 | `d4d5` | 兵四进一 | soldier 进 always 一 |
| 32 | `d4e4` | 兵四平三 | soldier sideways, dest file |
| 33 | `d4c4` | 兵四平五 | soldier sideways, dest file |

**`4k2/7/7/3p3/7/7/3K3 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 34 | `d4d3` | 卒4进1 | Black soldier 进 |
| 35 | `d4e4` | 卒4平5 | Black soldier sideways |
| 36 | `d4c4` | 卒4平3 | Black soldier sideways |

**`3k3/7/3p3/7/7/3K3/7 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 37 | `d2d1` | 帅四退一 | general 退 |
| 38 | `d2d3` | 帅四进一 | general 进 |
| 39 | `d2c2` | 帅四平五 | general 平 |
| 40 | `d2e2` | 帅四平三 | general 平 |

**`7/3k3/7/7/3P3/7/3K3 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 41 | `d6d7` | 将4退1 | Black general 退 |
| 42 | `d6d5` | 将4进1 | Black general 进 |
| 43 | `d6c6` | 将4平3 | Black general 平 |
| 44 | `d6e6` | 将4平5 | Black general 平 |

**`3k3/7/R6/7/7/R6/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 45 | `a5b5` | 前俥平六 | two chariots on a file: 前, file omitted |
| 46 | `a2b2` | 后俥平六 | two chariots on a file: 后 |
| 47 | `a5a6` | 前俥进一 | 前 with 进 |
| 48 | `a2a3` | 后俥进一 | 后 with 进 |
| 49 | `a5a3` | 前俥退二 | 前 with 退, multi-rank |

**`3k3/6c/7/7/6c/7/4K2 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 50 | `g3f3` | 前砲平6 | Black pair: 前 is the one nearer Red, i.e. lower rank |
| 51 | `g6f6` | 后砲平6 | Black pair: 后 is nearer Black |
| 52 | `g3g2` | 前砲进1 | Black pair 进 |
| 53 | `g6g7` | 后砲退1 | Black pair 退 |

**`3k3/7/1N5/7/7/1N5/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 54 | `b5a7` | 前傌进七 | 前/后 combined with horse destination-file value |
| 55 | `b5c7` | 前傌进五 | horse pair |
| 56 | `b5d6` | 前傌进四 | horse pair |
| 57 | `b5d4` | 前傌退四 | horse pair 退 |
| 58 | `b2a4` | 后傌进七 | horse pair |
| 59 | `b2c4` | 后傌进五 | horse pair |
| 60 | `b2d3` | 后傌进四 | horse pair |
| 61 | `b2d1` | 后傌退四 | horse pair 退 |

**`3k3/7/3P3/7/3P3/7/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 62 | `d5d6` | 前兵进一 | two soldiers on a file |
| 63 | `d3d4` | 后兵进一 | two soldiers on a file |
| 64 | `d5e5` | 前兵平三 | two soldiers, sideways |
| 65 | `d3c3` | 后兵平五 | two soldiers, sideways |

**`3k3/7/7/3P3/3P3/3P3/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 66 | `d4d5` | 前兵进一 | THREE soldiers on a file: 前 |
| 67 | `d3e3` | 中兵平三 | THREE: 中 |
| 68 | `d2c2` | 后兵平五 | THREE: 后 |

**`4k2/7/4p2/4p2/4p2/7/3K3 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 69 | `e3e2` | 前卒进1 | THREE Black soldiers: 前 |
| 70 | `e4d4` | 中卒平4 | THREE Black: 中 |
| 71 | `e5f5` | 后卒平6 | THREE Black: 后 |

**`3k3/7/3P3/3P3/3P3/3P3/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 72 | `d5d6` | 一兵进一 | FOUR on a file: ordinal 一 replaces 前 |
| 73 | `d4e4` | 二兵平三 | FOUR: 二 |
| 74 | `d3c3` | 三兵平五 | FOUR: 三 |
| 75 | `d2c2` | 四兵平五 | FOUR: 四 replaces 后 |

**`3k3/2P4/2P4/2P4/2P4/2P4/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 76 | `c6c7` | 一兵进一 | FIVE on a file: 一 |
| 77 | `c6b6` | 一兵平六 | FIVE: 一 |
| 78 | `c5b5` | 二兵平六 | FIVE: 二 |
| 79 | `c4d4` | 三兵平四 | FIVE: 三 |
| 80 | `c3b3` | 四兵平六 | FIVE: 四 |
| 81 | `c2d2` | 五兵平四 | FIVE: 五 |

**`3k3/4p2/4p2/4p2/4p2/7/2K4 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 82 | `e3e2` | 一卒进1 | FOUR Black: ordinal stays Chinese, rank count Arabic |
| 83 | `e4d4` | 二卒平4 | FOUR Black |
| 84 | `e5f5` | 三卒平6 | FOUR Black |
| 85 | `e6d6` | 四卒平4 | FOUR Black |

**`3k3/4p2/4p2/4p2/4p2/4p2/2K4 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 86 | `e2e1` | 一卒进1 | FIVE Black |
| 87 | `e3d3` | 二卒平4 | FIVE Black |
| 88 | `e4f4` | 三卒平6 | FIVE Black |
| 89 | `e5d5` | 四卒平4 | FIVE Black |
| 90 | `e6f6` | 五卒平6 | FIVE Black |

**`3k3/7/1P5/4P2/1P5/4P1P/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 91 | `b5b6` | 前兵六进一 | TWO doubled files: file restored after the piece name |
| 92 | `b3b4` | 后兵六进一 | TWO doubled files |
| 93 | `e4e5` | 前兵三进一 | TWO doubled files, second file |
| 94 | `e2e3` | 后兵三进一 | TWO doubled files, second file |
| 95 | `g2f2` | 兵一平二 | undoubled soldier keeps the plain form |
| 96 | `b5a5` | 前兵六平七 | TWO doubled files, 平 |
| 97 | `b5c5` | 前兵六平五 | TWO doubled files, 平 |

**`3k3/7/p1p2p1/7/2p2p1/7/4K2 b - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 98 | `c3c2` | 前卒3进1 | Black, two doubled files |
| 99 | `c5c4` | 后卒3进1 | Black, two doubled files |
| 100 | `f3f2` | 前卒6进1 | Black, second doubled file |
| 101 | `f5f4` | 后卒6进1 | Black, second doubled file |
| 102 | `a5a4` | 卒1进1 | Black undoubled soldier |
| 103 | `f3g3` | 前卒6平7 | Black, 平 |
| 104 | `c5b5` | 后卒3平2 | Black, 平 |

**`3k3/7/7/2P4/2P2P1/2P2P1/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 105 | `c4c5` | 前兵五进一 | 3+2 split: 前/中/后 with the file restored |
| 106 | `c3d3` | 中兵五平四 | 3+2 split |
| 107 | `c2b2` | 后兵五平六 | 3+2 split |
| 108 | `f3f4` | 前兵二进一 | 3+2 split, the doubled file |
| 109 | `f2g2` | 后兵二平一 | 3+2 split, the doubled file |

**`3k3/7/7/R2p3/7/7/4K2 w - - 0 1`**

| # | move | traditional string | covers |
|---|---|---|---|
| 110 | `a4d4` | 俥七平四 | capture by a chariot renders exactly as a quiet move |

<!-- rows: 110, positions: 24 -->

---

# Independent review

> **Adversarial verification, 2026-07-28.** Written by a second agent with no part in the report above.
> Everything below was re-executed or re-retrieved from the primary sources; nothing is taken on the
> report's word. This section is workspace-only research and authorises nothing. Nothing under
> `MiniXiangqi/` or any worktree was touched; the harness ran from `/tmp`; no git or GitHub writes.

## R0 · What survived verification

Stated first so the defects below are read at the right weight.

- **The oracle is sound.** I wrote a renderer from R1–R5 and from `interaction-design.md:163-167`
  alone, without reading the report's harness, and re-parsed all 110 rows out of Appendix A.
  **Result: 110/110 strings reproduced character for character, 24/24 positions pass the four-part
  legality predicate, 110/110 moves present in `pyffish.legal_moves`, 0 characters outside the
  expected codepoint set.** I also re-derived every row by hand from the contract's file numbering
  and found no error. The table is correct as published.
- **Injectivity holds.** 300 random legal games at a different seed, 21,829 positions, every legal
  move rendered: **0 collisions.**
- **All four primary sources check out verbatim.** I re-retrieved each one raw (`action=raw` for
  Wikipedia; `iconv -f GB18030` for xqbase; `pdftotext -layout` for the WXF-hosted PDF; the 2020
  rulebook page from `gdchess.com`) and diffed the quotations. §3.1, §3.2 and §3.3 are exact,
  including the easily-mistyped 「（或后）区分」 without 来. §3.1's third claim is confirmed by
  counting: the rulebook contains 同一道直线 once and 前兵 / 一兵 / 两条 zero times.
- **The engine measurements reproduce exactly.** Every cell of §3.5's WXF table
  (`R+=6`, `P++1`, `14+1`, `15+1`…`55=4`, `16+1`/`26+1`/`13+1`/`23+1`, `P1=2`) came back identical.
  So did both §1 probes: `d6d7` is offered from `3k3/3R3/7/7/7/7/4K2 w - - 0 1`, and from
  `3k3/7/7/7/7/7/2K4 w - - 0 1` the only legal move is `c1c2`. The module SHA-256 matches.
- **§4.3's 10-ply position is reproducible.** Replaying `c2b2 a6a5 b2b3 a5a4 a2b2 e6e5 e2e3 f7f5
  d2e2 a7a6` from the frozen start yields `1cnkn1r/r1pp2p/4pc1/p6/1P2P2/1P2P1P/RCNKNCR w - - 10 6`,
  byte-identical to the FEN printed. The 44-ply FEN validates, its three quoted moves are legal, and
  22 Red moves is exactly the minimum (12 sideways + 10 forward), so the ply count is not padded.
- **Every Apple citation is real and says what is claimed.** Details in R11.

The defects are in the arguments and in the contract read-across, not in the table.

---

## R1 — §4.2's load-bearing claim is refuted by the report's own strings — **HIGH**

> §4.2: "That fact is what makes the scheme in §5 safe: 一/二/三/四/五 is used for one purpose and one
> purpose only, and **never has to be told apart from a file number in the same string**."

**What is wrong.** False, and falsified by Appendix A. R4 puts the ordinal at the head and a
destination file after 平, both in the same string and — for Red — both in the same numeral system:

| row | string | 一–五 as ordinal | 一–五 as file |
|---|---|---|---|
| 75 | 四兵平五 | 四 = 4th from the front | 五 = file `c` |
| 79 | 三兵平四 | 三 = 3rd from the front | 四 = file `d` |
| 81 | 五兵平四 | 五 = 5th from the front | 四 = file `d` |

And §4.3, two pages later, prints the worst case itself: **五兵平五** (`b2c2` in the reached 44-ply
position) — the *same character* carrying both meanings in one four-character string. I confirmed
`b2c2` is legal there and that R4/R5 render it 五兵平五.

What §4.2's arithmetic actually establishes is only that **R4's ordinal and R5's restored *origin*
file never co-occur**. That is a much weaker statement than the one drawn from it, and it is the
statement §5.2 argument 2 needs — not the one §4.2 makes.

**Why it matters.** This is the sentence that licenses R4 over 前/二/三/四. It is also the sentence
that, if believed, makes 五兵平五 look impossible. Any owner reading §4.2 and then meeting 五兵平五
will not trust the rest.

**Correction.** Replace the last paragraph of §4.2 with the claim the arithmetic supports: *"The two
hard cases are mutually exclusive, so R4's ordinal and R5's restored origin file never appear in one
string. The ordinal can still stand beside a **destination** file — 三兵平四, and in the limit
五兵平五 — so R4's cost is not zero; it is that a reader must take the leading numeral as positional
and the numeral after 平 as a file. That is the same positional convention 前/中/后 already relies on,
but it is a convention, not an absence of collision."* Then add 五兵平五 to Appendix A as an explicit
row, so the hardest string the rules can produce is in the approved table rather than in prose.

---

## R2 — R5 amends accepted contract text, and by the report's own test is an owner decision — **HIGH**

> `interaction-design.md:166` (accepted): "When two pieces of the same type stand on one file, the
> move opens with 前 or 后 **before** the piece name **and omits the file entirely** — 前炮退二, not
> 炮前退二."

> §5.3 heading: "**The one place this contradicts accepted text**, and why" — referring only to R4's
> Chinese ordinal.

> §10.1: "The decision is the owner's **because it changes accepted contract text rather than filling
> a gap in it**."

**What is wrong.** R5 renders 前兵六进一. Two pieces of the same type stand on one file, and the move
does **not** omit the file. That is a direct contradiction of an accepted, unconditional normative
sentence — not an extension of it. §6 item 1 concedes exactly this (":166 … needs R5's
qualification"), so the report contradicts itself: §5.3 says R4's ordinal is *the one* place, §6 says
there are two. Applying §10.1's own escalation criterion, **R5 is as much the owner's decision as
R4's ordinal is** — and R5 bites at a measured 1.2–1.7% of side-scans, roughly a hundred times more
often than R4.

Relatedly, §0 says :166 "becomes **ambiguous**". It does not. :166 is perfectly determinate as a
*rendering* rule (omit the file, always); what it fails to be is *injective* when two files are
doubled. Calling it ambiguous makes R5 sound like clarification when it is override.

**Correction.** (a) Retitle §5.3 "The two places this contradicts accepted text". (b) Add R5's
override of :166 to §10 as a fifth owner decision, with the same two-option framing R4's ordinal
gets, and with its real frequency attached. (c) In §0 and §6 item 1, say "under-determined as a
disambiguator" rather than "ambiguous", and say plainly that R5 overrides the sentence.

---

## R3 — §5.3's reason for the Chinese ordinal is refuted by the report's Red rows — **HIGH**

> §5.3: "**Reasoned:** … writing it as an Arabic digit next to Black's Arabic file and rank numbers
> would make 1卒进1 read as though the first and last digits were the same kind of thing."

**What is wrong.** Appendix A row 75 is **四兵平五** and row 81 is **五兵平四**. For Red, the leading
ordinal and the trailing file are *already* rendered in one numeral system and are *already*
"different kinds of thing rendered identically" — and the report accepts that without a word. The
argument therefore proves too much: if the collision is tolerable for Red (where it is unavoidable),
the report owes a reason why the identical collision is intolerable for Black (where it is
avoidable). It gives none. Whatever positional cue lets a reader parse 四兵平五 (leading numeral =
position, numeral after 平 = file) parses 1卒进1 the same way (leading = position, trailing = rank
count).

**Why it matters.** §10.1 offers the owner a choice and marks one option "recommended, §5.3". The
recommendation rests on this argument. Strip it and the case for the exception reduces to a single
line of support — xqbase's 一卒平５ — which is real but is *one* source, and which R6 below shows is
attached to a position R5 declines to label at all.

**Correction.** Rewrite §5.3's justification as source-based, not reasoning-based: *"xqbase writes
the ordinal in Chinese for Black and is the only source that addresses the case; no argument from
legibility distinguishes 1卒进1 from Red's own 四兵平五, which the same rules already produce."* Then
§10.1's framing becomes honest: the owner is choosing between one source and one accepted sentence,
not between a good argument and a bad one.

---

## R4 — §4.4's two headline numbers cannot both be right — **MEDIUM**

> §4.4: "300 random legal games of up to 80 plies, **21,888 positions**, each position scanned once
> per side (**43,690 side-scans**)".

**What is wrong.** 2 × 21,888 = **43,776**, not 43,690. Eighty-six side-scans are unaccounted for.
The bucket counts do sum to 43,690 (31,413 + 11,563 + 528 + 186 + 0) and the percentages are computed
against 43,690, so the *table* is self-consistent — which means the position count, or the scan
protocol, is misstated. I ran the same protocol twice at different seeds; both times side-scans came
out at *exactly* twice the position count (21,829 → 43,658; 21,412 → 42,824). `interaction-design.md`
and `testing.md` will quote these frequencies; they need to be reproducible.

**Correction.** Re-run and republish both numbers from one run, or state which side-scans were
excluded and why.

---

## R5 — "did not occur once" is a fact about one sample, used as a fact about the game — **MEDIUM**

> §4.4 table: "four or five on one file — **0** — 0%". §8.1: "**Random play does not reach four or
> five on a file** (§4.4)." §10.1: "it bites only in a case that **did not occur in 21,888 random
> positions**." §10.3: "describes something a player will **almost certainly never see**."

**What is wrong.** I ran the same experiment — 300 random legal games, ≤80 plies, seed 20260728 —
and got **10 side-scans with four or five soldiers on one file** in 43,658 (0.02%). A second seed
gave 0. So the case is seed-dependent and rare, not absent, and §8.1's general claim ("random play
does not reach") is false as stated. The report's own §4.3 shows five-on-a-file reachable in 44 plies
of *legal* play, which already sits awkwardly beside "0".

**Why it matters.** The 0 is load-bearing in two owner decisions (§10.1, §10.3). A rare-but-nonzero
number supports a different conclusion from an observed-zero one, particularly for §10.3, where
"never see" is the whole argument for leaving R4 out of Help.

**Correction.** Report it as "0 in this sample; 10 in 43,658 side-scans at another seed — order
10⁻⁴ under random play, and reachable in 44 plies of legal play (§4.3)". Drop §8.1's general claim
and keep only the sample statement.

---

## R6 — the xqbase table is reproduced with a row silently removed, and the ellipsis hides the example's shape — **MEDIUM**

> §3.2: "The source's table gives, for four pawns on Red's files 四 and 六: [four rows]"

**What is wrong.** The source table has **five** rows. Between 二兵平五 and 三兵平五 sits:

| 中文纵线格式 | 数字纵线格式 | 坐标格式 |
|---|---|---|
| 兵五进一 | P5+1 | E7-E8 |

That row is dropped without an ellipsis or a note. It is not decorative: it is the source's own
attestation that a soldier *not* on either doubled file keeps the plain form — precisely the clause
R5 states ("Pieces of type *T* that are alone on their file … keep R1") and that Appendix A rows 95
and 102 test. The report presents that clause as its own reading when the cited table demonstrates it
directly. The dropped row also means the figure holds five pawns, not four, which matters for
"不在这两条纵线上的兵不参与标记".

Second, §3.2's numerals quote elides with 「……」 the clause **例如例局面红黑互换**. Restored, the
source reads: *"…例外，**例如例局面红黑互换**，那么某步着法就应该写成「一卒平５」。"* So xqbase's only
worked instance of the Chinese-ordinal-for-Black exception is the **mirrored two-doubled-files**
position — the configuration R5 declines to label 一–五 at all. Under this report's own rules the app
would **never** produce the string 一卒平５. The normative clause is scoped 同一纵线 and so does still
reach R4, but §10.1's "matches the one source that specifies this case at all" is stronger than the
evidence, and the reader cannot see that from behind the ellipsis.

Third, the source writes Black's digits as **全角** (「在计算机中显示全角的数字」, and 一卒平**５**
U+FF15). See R8.

**Correction.** Reproduce all five rows, or mark the omission. Restore 例如例局面红黑互换 and add one
sentence noting that the source's instance is a case R5 renders differently.

---

## R7 — §5.1's engine evidence is overstated, and the engine conforms to no published standard here — **MEDIUM**

> §5.1: "A pure 一–五 series … is what the sport's computer standard specifies, and **is what this
> project's own engine emits**."

**What is wrong.** Fairy-Stockfish emits `14+1` — an **Arabic** index **plus the file**, applied at
n ≥ 3 and at D ≥ 2. It does not emit a 一–五 series, it does not omit the file, and it does not
restrict the indexed form to n ≥ 4. §8.2 says as much; §5.1 does not, and §5.1 is where the choice is
justified. All the engine actually supports is **direction of counting** (index 1 = most advanced),
which I re-measured and confirm — and which was never in dispute (§5.1's own first paragraph says
"There is no live dispute about direction").

Worse for the appeal to authority: xqbase §五 states the WXF numeric convention as
「代替『前中后』的『一二三四五』分别用『abcde』表示」 — letters, no file. The engine's `NOTATION_XIANGQI_WXF`
uses digits and keeps the file, so it matches neither the WXF numeric format nor the 中文纵线格式.
Citing it as corroboration for a *symbol* choice is citing a third, undocumented convention.

**Correction.** In §5.1 keep the engine only as evidence for counting direction, and say explicitly
that it emits an Arabic index with the file retained, conforming to no published WXF form. Move the
symbol argument onto xqbase alone, which is where it actually rests.

---

## R8 — the oracle silently fixes a codepoint decision it never states — **MEDIUM**

> §7: "The expected string was written by hand … and an independent renderer reproduces it
> **character for character**." §8.3 audits 帅将俥车傌马炮砲兵卒 进退平前中后 一二三四五六七.

**What is wrong.** Every Black numeral in Appendix A is **ASCII** (U+0031–U+0037) — I verified this
by codepoint over all 110 rows. That is a decision, and it is nowhere stated. §8.3's alphabet lists
only CJK characters, so the audit that is presented as making the table safe against look-alikes does
not constrain the digits at all — and full-width ４ (U+FF14) against ASCII 4 is exactly the kind of
substitution the audit exists to catch. The report's own primary source specifies the opposite
(「在计算机中显示全角的数字」, 一卒平５), and `interaction-design.md:163` says only "Arabic numerals".

The accepted contract does bear on it, in the report's favour: `interaction-design.md:155` sets the
board's Chinese numerals **semibold** and its digits **bold** precisely because "the Chinese numerals
carry about a quarter more ink than the digits, because their advances are full-width" — i.e. the
accepted numeral strips use half-width digits beside full-width CJK. That is a good reason to choose
ASCII, and it is not given.

**Why it matters.** An oracle is matched character for character; a half-width/full-width mismatch
would fail every Black row while looking identical in review. And full-width digits would change the
move-list cell metrics that §5.2 argues about.

**Correction.** State the decision — "Black's numerals are ASCII U+0030–U+0039, not their full-width
forms, consistent with `interaction-design.md:155`" — and add the digit codepoints to §8.3's audited
alphabet.

---

## R9 — Help's accepted boundary is misattributed, and none of §10.3's options is inside it — **MEDIUM**

> §10.3: "Help's scope is a hard accepted boundary of eight topics, read-only, no analysis or drills
> (`interaction-design.md:527` and the accepted text above it)".

**What is wrong.** Two errors.

1. **`:527` is not a boundary; it is an open question.** It sits under `:511` — "The items below are
   **questions**, not requirements or implementation authorization" — and reads "Define help entry
   points, content organization, and illustrations within the accepted read-only rules-reference
   scope." The accepted scope is `:395` and `:397`, ~130 lines earlier, not "above it".
2. **Notation is not one of the eight topics.** `:395` lists: the board; the pieces and their
   movement; check and checkmate; stalemate; repetition and the claimable draw; perpetual check;
   perpetual chase; plus a short explanation of the app's own controls. The count of eight is right;
   the content is not what the report assumes. §10.3's *baseline* option — "Teach only the base
   notation" — already adds a ninth topic, so the option set as framed offers the owner no
   inside-the-contract choice, and the stated cost of the baseline ("a user … has nowhere in the app
   to find out what 中兵平三 means") is true today of **all** notation, R1 included.

**Correction.** Cite `:395`/`:397` for the scope and `:527` only as the open question it is. Reframe
§10.3 as *whether Help gains a notation topic at all* — a scope change either way — with the three
depths as sub-options.

---

## R10 — §5.2's third argument fails exactly where R5 costs most — **MEDIUM**

> §5.2 argument 3: "**The file is the disambiguator the app already teaches.** Every plain move
> carries its file, **the numeral strips beside the board carry the files**, and
> `interaction-design.md:167` makes the strip follow the board's orientation for exactly this reason."

**What is wrong.** `interaction-design.md:157` is accepted and says: "**The strips are hidden at
accessibility text sizes.** … without the strips a reader cannot relate a move in the list to a file
on the board without counting, which is a loss for the same user the larger type was for."

So at accessibility text sizes the reader has no file strip — and that is the same condition under
which R5's five-character cell is hardest to fit, as the report itself notes ("permanent vertical
space in the layout that is tightest exactly when accessibility text sizes are in use", §10.2). The
argument and its cost peak together, and the report presents only the peak that favours R5. Argument
3 is the weakest of the three and is presented as of equal weight.

I do not think this overturns R5 — arguments 1 and 2 survive, and the alternative loses the file
*permanently*, not just at large type. But the asymmetry has to be on the page.

**Correction.** Add: "This argument weakens at accessibility text sizes, where `:157` hides the
numeral strips; there the restored file is still the mover's own numbering the plain form uses, but
it can no longer be read off the board."

---

## R11 — Apple citations: all four verify; one material fact is omitted — **LOW**

Verified against Apple developer documentation on the pinned toolchain.

| report's claim | verdict |
|---|---|
| Foundation *Language-Dependent Information Constants* documents `NSDecimalDigits` as "Strings that identify the decimal digits in addition to or instead of the ASCII digits." | **VERIFIED**, verbatim, at `/documentation/Foundation/language-dependent-information-constants#Numeric-Information`. |
| Xcode *Preparing dates, currencies, and numbers for translation* "instructs developers to render numbers through `formatted()` / format styles so they localise" | **VERIFIED**. § *Format percents and scientific numbers*: "call `formatted()` or `formatted(_:)` on the number instance, along with the format style to display." |
| UIKit *Speech attributes for attributed strings* documents `UIAccessibilitySpeechAttributeLanguage` as "A key that indicates the language to use when speaking a string" | **VERIFIED**, verbatim. |
| `accessibilityLanguage` "is listed under *Defining accessibility text and language*" | **VERIFIED**, at `/documentation/UIKit/uiaccessibility-protocol#Defining-accessibility-text-and-language`. |
| "Apple publishes nothing on Xiangqi notation, on rendering game move lists, or on non-Latin notation systems." | **VERIFIED** as far as search reaches — a Xiangqi/move-list query returns only GameplayKit strategist pages and a Swift tutorial. Correctly owned as the author's own recommendation. |

**Omission.** The *Language-Dependent Information Constants* page opens: "**These constants are
deprecated and shouldn't be used.**" §9 cites `NSDecimalDigits` as evidence of a live platform risk
without saying so. The risk itself is real and the *other* citation (`formatted()`) carries it
properly; the deprecated constant is the weaker leg and is presented as the stronger.

**Correction.** Lead §9's locale trap with the `formatted()` citation and keep `NSDecimalDigits` only
as illustration, noting its deprecation.

---

## R12 — smaller defects, with corrections — **LOW**

1. **§8.2 "diverges on exactly two presentational points" — there is a third.** Measured: with two
   doubled files of two, the engine emits `16+1`/`26+1` — the numeric index — where R5 emits
   前兵六进一/后兵六进一. So the engine uses the index whenever *(n ≥ 3 or D ≥ 2)*, which includes an
   n = 2 case R5 renders with 前/后. Say "three points", or restate the divergence as "the engine
   indexes wherever R2/R3 use 前/中/后".
2. **§3.6 silently corrects a source defect while §3.2 flags two others.** The WXF-hosted document
   says letters "**A-D**" for four *or five* pawns on one file — an obvious error, since five need
   five letters. §3.4 quotes "A, B, C, D"; §3.6's comparison row writes "letters **A–E**". Either
   flag it as a third source defect or keep the source's own letters. The report's stated method is
   to report defects "rather than smooth over" them.
3. **§3.4's first quotation is verbatim but internally incoherent, and the report calls the document
   "exact".** The source really does say "If there are 2 sets of 2 pawns on the **same file**", which
   cannot be, and resolves itself only in the sentences the report omits ("So if black has 2 pawns on
   his 3rd file and 2 pawns on his 5th file…"). Those omitted sentences are also the strongest
   evidence for the Red-absolute ordering §3.4 asserts ("C would be northmost pawn on 3rd file
   (which is red's 7th file)"). Quote them, and note the "same file" slip.
4. **§3.4's second quotation is not verbatim.** The PDF reads "then you revert to the regular (+),
   (-), or (=) **notation** when one of them moves"; the report gives "the regular (+ - =) when one
   of them moves". That is more than the "line-wrap artefacts … repaired" the retrieval note admits.
5. **§5.2 argument 1 rests partly on an inference presented as a source reading.** "xqbase orders the
   labels **mover-relatively** (先从右到左)" — the source says only 先从右到左, with a Red-only worked
   example, and never states whose right. If xqbase were in fact Red-absolute it would *agree* with
   the WXF-hosted document and one third of argument 1 would vanish. The 3-2 uncertainty leg is
   independent and survives. Mark the mover-relative reading as an inference.
6. **§0's "not listed as open anywhere" overstates.** `:519` reads "the cases this contract leaves
   open, **including** three or more same-type pieces sharing a file" — non-exhaustive, so the
   two-doubled-file case is inside that open item, just unnamed. Also, the two buckets being compared
   overlap in kind: I measured that ~2.7% of D ≥ 2 side-scans (19/714) are 3-2 splits, which *do*
   have three pieces sharing a file and so are named by `:519`. The finding is still a real one —
   say "a case the contract's open item does not name" rather than "not listed as open anywhere".
7. **`testing.md` is treated as normative and is not.** Its status line reads "**Status: Draft
   validation proposal.** Nothing in this document is normative until its status or an individual
   section is explicitly marked accepted", and `### UI, accessibility, sound, and haptics` (which
   contains `:189`) carries no acceptance mark. "the oracle … `testing.md:189` **require**" (summary)
   and "`testing.md:189` **already requires**" (§10.4) should read "the draft coverage list at
   `testing.md:189` states". §10.4's own second bullet already knows this and contradicts the other
   two.
8. **§10.4 misreads `xiangqi-rules.md:3`.** The sentence is "**It** owns the adopted interpretation
   of Mini Xiangqi rules **and the identifiers that connect prose to executable conformance
   fixtures**" — the subject is the *document*, which owns the identifiers. The report writes "the
   fixtures directory is already the accepted home for 'the identifiers that connect prose to
   executable conformance fixtures'", which inverts it. The accepted precedent the recommendation
   actually wants is the accepted fixture set in `fixtures/rules/` (`xiangqi-rules.md:5`). Also worth
   surfacing: `testing.md:189`'s stated reason for wanting a separate approved table is "**since the
   fixtures record only canonical coordinates**" — the recommendation to make the oracle a fixture is
   fine, but it should say it is changing that premise, not resting on it.
9. **Oracle coverage gaps, both small.** The 3+2 split is exercised for **Red only** (rows 105-109) —
   yet the 3-2 case is the one the WXF-hosted document explicitly records as unsettled, and Black is
   where the sources' frames of reference diverge. And the capture invariant is pinned only in the
   **R1** form (rows 23, 27, 110); no row shows a capture rendered under R2–R5. Two Black 3+2 rows
   and one 前兵六平七-style capture would close both. (Not a correctness defect: I verified R1–R5
   render captures identically to quiet moves in all cases I generated.)

---

## R13 — one thing the report gets right that is worth protecting

§4.2's *arithmetic* — four-or-five on a file and a second doubled file cannot co-occur with five
soldiers — is correct and I confirm it holds for every piece type (no other type has more than two
members). It is the reason R4 and R5 can be written as separate rules with no precedence clause. R1
above attacks the *conclusion drawn from* that arithmetic, not the arithmetic. If §4.2 is rewritten,
keep the mutual-exclusion result and keep it labelled load-bearing; R5's rule text depends on it.

## Verdict

**NEEDS WORK — the deliverable is sound, three arguments are not.** The 110-row oracle, the rule set
as a mechanism, the source quotations and every engine measurement survived independent
re-execution. What does not survive is (R1) the sentence that justifies R4, (R2) the accounting of
which accepted text is being amended and therefore which decisions are the owner's, and (R3) the
reasoning offered for the one exception the report asks the owner to accept. R4-R10 are corrections
that change numbers, citations and framing rather than conclusions. None of the findings requires the
table to be rebuilt; R1's correction adds one row to it and R12.9 adds three more.
