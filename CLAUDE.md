# Star River

Native SwiftUI board-game app (Xiangqi, Mini Xiangqi, Jieqi, Gomoku, Renju) for iPhone, iPad and Mac over a C++ core in `core/`. GPLv3.

Before you start, say in a line what you are about to do; brief updates while you work help the owner follow along. Close with a short recap that stands on its own. When the owner wants to discuss a problem, deliver the assessment and the decisions that are theirs to make.

## Simplicity

- Apple-native and simple: use what the platform provides, and add nothing the app does not need.
- Fix a wrong basis rather than patch around it. Breaking changes and big diffs are fine.
- Tooling, CI and process are added when the owner asks for them.
- A test earns its place by the regression it would catch; a red-tape test is deleted rather than fixed.
- Comments say what the code cannot.

## Docs

Docs hold what the code, the project file and Apple cannot say: product decisions, game rules, file formats. The code and the project file are the source for everything else. The repository stays free of the owner's name and of paths from their machine.

## Sessions

- Work that is a task of its own goes to a session started with `start_session`: one task, a complete brief, Opus, effort high by default, xhigh for intricate work, medium for mechanical work. Subagents are for quick reads the current turn needs.
- One or two work sessions at a time, three at most; reviewers are extra. Each works in its own worktree and is archived, worktree included, when its work is done.
- Work is tracked as GitHub issues, created before it starts.

## Pull requests

- The author session opens the PR and may carry one PR or several. Everything lands through a PR.
- One review round: one to three fresh Opus reviewer sessions post their findings on the PR, ranked by severity with evidence. The author judges each finding, fixes what matters and says on the PR what it left alone and why. Work that seems to need a second review is split into more PRs instead.
- Merge or squash, delete the branch, tell the owner. Commit, push and merge without asking. Facts the owner should know later go on GitHub.
