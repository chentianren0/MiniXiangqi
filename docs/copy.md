# Copy

This document is for UI engineers, designers, testers, and anyone who reviews or changes what the application says. It owns every user-facing string pair — the normative Simplified Chinese and its approved English — the symbolic key each pair is stored under, the vocabulary that is never translated, and the localization process. It does not own where a string appears, when it appears, or the behavior it describes; each of those belongs to the contract named beside the row.

> **Status: Accepted bilingual copy contract**
>
> The Simplified Chinese here is normative and exact. The English counterparts are approved. Strings also appear inline in other contracts where behavior is described, and that is deliberate — a contract has to be readable on its own — but **this table is the string of record for the pair and for the key**, and a difference between a row here and a quotation elsewhere is resolved in favour of the row. A row marked *(proposed)* is not accepted and is listed again under **Need to discuss**, which is explicitly non-normative.

## How to read the table

- **Key** is the symbolic key the string is stored under in the String Catalog. Keys are hierarchical and stable: a key survives a wording change in either language, and it is the join between this contract and the build artefact. A key is never the source string.
- **中文** is normative. It is what a reviewer approves and what a translator translates from.
- **English** is approved, and is a translation of the Chinese rather than a second source.
- **Surface** is what the string is presented as, because the same words are written differently on a button, in an alert title, and in an accessibility label.
- **Source** names the contract section that owns the behavior, and, where the string is already live, the file it is live in. Every Chinese string below exists in a contract or in `apple/MiniXiangqi/` today, except where the Source column says otherwise.

Contract sections are cited by document and section name rather than by line number, so that the citation survives an edit above it.

## The string table

### Navigation and modes

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `nav.play` | 对局 | Play | navigation destination; screen title; the Play back control's accessibility label | [product.md](product.md) § Product navigation; [interaction-design.md](interaction-design.md) § Navigation — English only there; `Play/PlayDestination.swift` — a back control names the page it returns to, which here is always the Play home |
| `nav.history` | 历史 | History | navigation destination | same; 历史 is attested inside 保存到历史 and 已记录到历史 |
| `nav.settings` | 设置 | Settings | navigation destination; screen title | same; 设置 is attested inside 本局设置 and 人机对弈默认设置; `ContentView.swift`, `Settings/SettingsScreen.swift` |
| `nav.resumeGame` | 回到对局 | Resume Game | button | [interaction-design.md](interaction-design.md) § The Play home, § Saving the active game before choosing a new mode — English only there; `Play/PlayHome.swift` |
| `nav.moveList` | 棋谱 | Moves | toolbar item; sheet title | [interaction-design.md](interaction-design.md) § The move list during play — the stacked layout reaches the list on demand, and this names both the item that reaches it and the sheet it opens; `Play/PlayScreen.swift`. 谱 is attested inside 记谱法 |
| `mode.humanVersusAI` | 人机对弈 | Human versus AI | mode entry; metadata token | [interaction-design.md](interaction-design.md) § The Play home, § Saving the active game before choosing a new mode; [product.md](product.md) § Target-MVP play modes; `Play/PlayHome.swift`, `Play/ActiveGameMetadata.swift` |
| `mode.freePlay` | 自由对弈 | Free Play | mode entry; metadata token | same |

### Controls

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `control.undo` | 悔棋 | Undo | button | [interaction-design.md](interaction-design.md) § Play controls; `Play/PlayScreen.swift` — the play-control cluster's, and only there |
| `control.claimDraw` | 判和 | Claim Draw | button | [interaction-design.md](interaction-design.md) § Play controls; `Play/PlayScreen.swift` |
| `control.flipBoard` | 翻转棋盘 | Flip Board | button; accessibility label | [interaction-design.md](interaction-design.md) § Play controls, § Board orientation; `Play/PlayScreen.swift` |
| `control.resign` | 认输 | Resign | button; alert button | [interaction-design.md](interaction-design.md) § Play controls; `Play/PlayScreen.swift` — the cluster's, and the confirmation's destructive action |
| `control.startGame` | 开始对局 | Start Game | button | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |
| `control.newGame` | 开始新对局 | New Game | button | `Play/PlayScreen.swift` — the play-control cluster's concluding action |
| `control.save` | 保存 | Save | button | [interaction-design.md](interaction-design.md) § Natural result presentation; `Play/ResultNotice.swift` — the notice's default action |
| `control.saveAndNewGame` | 保存并开始新对局 | Save and New Game | button | same — the notice's second action, which files and resets in one press |
| `control.endGame` | 结束对局 | End Game | button | [interaction-design.md](interaction-design.md) § Natural result presentation — retired as the notice's label, where `control.save` now names the same act; no surface reads it |
| `control.done` | 完成 | Done | button | [interaction-design.md](interaction-design.md) § Natural result presentation, § The move list during play — the same word closes the recorded notice and the stacked layout's move-list sheet; `Play/ResultNotice.swift`, `Play/PlayScreen.swift` |
| `control.replay` | 回放 | Replay | button | [interaction-design.md](interaction-design.md) § Natural result presentation; `Play/ResultNotice.swift` |
| `control.cancel` | 取消 | Cancel | alert button | [interaction-design.md](interaction-design.md) § Play controls and every alert below |
| `control.tryAgain` | 重试 | Try Again | alert button; inline button | [interaction-design.md](interaction-design.md) § Insufficient memory for AI play, § Saving the active game before choosing a new mode, § Turn status — the stalled AI activity slot's retry is the same word and the same key |
| `control.later` | 稍后 | Later | alert button | [interaction-design.md](interaction-design.md) § Insufficient memory for AI play — the mid-game re-preparation failure's cancel action. Not 取消: nothing is being cancelled, the game is saved, and it goes on |
| `control.saveAndContinue` | 保存并继续 | Save and Continue | alert button | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; [product.md](product.md) § Games and history; `Play/PlayHome.swift` |
| `control.keepPlaying` | 继续对局 | Keep Playing | alert button | [interaction-design.md](interaction-design.md) § Claimable threefold repetition; `Play/PlayScreen.swift` |
| `control.endAsDraw` | 以和棋结束 | End as a Draw | alert button | same |
| `control.share` | 共享 | Share | swipe action; context menu; screen-reader action | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |
| `control.delete` | 删除 | Delete | swipe action; alert button | [interaction-design.md](interaction-design.md) § History library |
| `control.pin` | 置顶 | Pin | swipe action; context menu | [interaction-design.md](interaction-design.md) § History library |
| `control.unpin` | 取消置顶 | Unpin | swipe action; context menu | [interaction-design.md](interaction-design.md) § History library |
| `control.import` | 导入… | Import… | toolbar item | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |
| `control.view` | 查看 | View | alert button | same — the duplicate answer's way to the record it found |
| `control.ok` | 好 | OK | alert button | same — the acknowledgement of an alert that is informational plus at most one navigation |

### Turn status

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `status.redToMove` | 轮到红方 | Red to Move | status line; metadata token | [interaction-design.md](interaction-design.md) § Turn status, § Saving the active game before choosing a new mode; `Play/TurnStatus.swift`, `Play/ActiveGameMetadata.swift` |
| `status.blackToMove` | 轮到黑方 | Black to Move | status line; metadata token | same |
| `status.check` | 将军 | Check | status token | [interaction-design.md](interaction-design.md) § Turn status, § Game-state markers; `Play/TurnStatus.swift` |
| `status.sideToMove.checked` | `%1$@　%2$@` | `%1$@ %2$@` | status-line format | `Play/TurnStatus.swift` — the separator is an ideographic space in Chinese and an ordinary space in English |
| `status.drawAvailable` | 可判和 | Draw Available | status line; metadata token | [interaction-design.md](interaction-design.md) § Turn status, § Claimable threefold repetition; `Play/TurnStatus.swift`, `Play/ActiveGameMetadata.swift` |
| `status.controller.you` | 你 | You | secondary label | [interaction-design.md](interaction-design.md) § Turn status; `Play/TurnStatus.swift` |
| `status.controller.ai` | AI | AI | secondary label | same — identical in both languages |
| `status.aiThinking` | AI 正在思考 | AI is thinking | accessibility label | [interaction-design.md](interaction-design.md) § Turn status; `Play/TurnStatus.swift` — the activity indicator's label, never drawn on screen |
| `status.aiUnavailable` | AI 暂时无法启动 | The AI can't start right now | status line | same — the AI activity slot's stalled state, after the mid-game notice was answered with 稍后 |
| `status.redWins` | 红方胜 | Red Wins | status line | `Play/TurnStatus.swift` |
| `status.blackWins` | 黑方胜 | Black Wins | status line | same |
| `status.draw` | 和局 | Draw | status line | same |
| `status.saveFailed` | 无法保存这一步，请重试。 | Couldn't save that move. Please try again. | transient capsule at the turn status | [interaction-design.md](interaction-design.md) § Game-state markers, § Move input |

### Result notice

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `result.redWins` | 红方获胜 | Red Wins | notice title; metadata token | [interaction-design.md](interaction-design.md) § Natural result presentation, § Saving the active game before choosing a new mode; `Play/ResultNotice.swift`, `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `result.blackWins` | 黑方获胜 | Black Wins | notice title; metadata token | same |
| `result.draw` | 和棋 | Draw | notice title; metadata token | same |
| `result.recorded` | 已记录到历史 | Saved to History | notice title once the game is filed | [interaction-design.md](interaction-design.md) § Natural result presentation; `Play/ResultNotice.swift` |
| `result.announcement` | `%1$@，%2$@` | `%1$@, %2$@` | VoiceOver announcement format | `Play/ResultNotice.swift` — the separator is an ideographic comma in Chinese and a comma-space in English |

### Result reasons

One vocabulary, used by the result notice's second line, the turn status, the History row, and the save-and-continue metadata. Each row corresponds to an `end_reason` value frozen in [game-data.md](game-data.md).

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `reason.checkmate` | 将死 | Checkmate | reason line; metadata token | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; `Play/TurnStatus.swift` |
| `reason.stalemate` | 困毙 | Stalemate | reason line; metadata token | `Play/TurnStatus.swift` |
| `reason.threefoldRepetition` | 三次重复 | Threefold Repetition | reason line; metadata token | same |
| `reason.perpetualCheck` | 长将 | Perpetual Check | reason line; metadata token | same |
| `reason.perpetualChase` | 长捉 | Perpetual Chase | reason line; metadata token | same |
| `reason.mutualPerpetualCheck` | 双方长将 | Mutual Perpetual Check | reason line; metadata token | same |
| `reason.mutualPerpetualChase` | 双方长捉 | Mutual Perpetual Chase | reason line; metadata token | same |
| `reason.resignation` | 认输 | Resignation | reason line; metadata token | same |
| `reason.endedEarly` | 提前结束 | Ended Early | reason line; metadata token; the History row's **result** slot | same; [interaction-design.md](interaction-design.md) § History library — `outcome = none` holds exactly when the reason is ended-early, so the row states the one fact once rather than adding a word for the absence of a winner |

**Stalemate is kept deliberately.** It is the standard English Xiangqi term, the notice title has already named the winner, and the Help stage owes the statement that having no legal move loses in Xiangqi. The English word's chess sense is corrected by the surface it appears on rather than by renaming the reason.

### Alerts

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `alert.resign.title` | 认输？ | Resign? | alert title | [interaction-design.md](interaction-design.md) § Play controls; `Play/PlayScreen.swift` |
| `alert.resign.message` | 认输后本局将记为你落败。 | Resigning records this game as your loss. | alert message | same |
| `alert.claimDraw.title` | 局面已三次重复 | This position has occurred three times. | alert title | [interaction-design.md](interaction-design.md) § Claimable threefold repetition; `Play/PlayScreen.swift` |
| `alert.claimDraw.message` | 可以和棋结束。 | You can end the game as a draw. | alert message | same |
| `alert.newGame.title` | 开始新对局？ | Start a new game? | alert title | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; `Play/PlayHome.swift` |
| `alert.newGame.metadataHeader` | 当前对局 | Current Game | metadata header; section header on the Play home | same, and § The Play home; `Play/PlayHome.swift` — one string over one line, wherever that line is shown |
| `alert.newGame.message` | 这盘对局将按当前状态保存到历史。 | This game will be saved to History as it is now. | alert message | same; `Play/PlayHome.swift` |
| `alert.saveFailed.title` | 无法保存对局 | Couldn't Save the Game | alert title | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode, § Move input; `Play/PlayScreen.swift`, `Play/PlayHome.swift` |
| `alert.saveFailed.message` | 当前对局仍然保留。请重试。 | The current game is unchanged. Please try again. | alert message | same |
| `alert.aiUnavailable.title` | 无法启动 AI 对手 | Couldn't Start the AI Opponent | alert title | [interaction-design.md](interaction-design.md) § Insufficient memory for AI play; [engine-integration.md](engine-integration.md) |
| `alert.aiUnavailable.message` | 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 | There is not enough memory available. Please close some other apps, then try again. | alert message | same — the pre-start form; `Play/SetupScreen.swift` |
| `alert.aiUnavailable.resumeMessage` | 当前可用内存不足。对局已保存，可以稍后继续。请尝试关闭一些其他 App，然后重试。 | There is not enough memory available. The game is saved and you can continue later. Please close some other apps, then try again. | alert message | same — the mid-game form, under the same title; `Play/PlayScreen.swift` |
| `alert.gameNotStarted.title` | 无法开始对局 | Couldn't Start the Game | alert title | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |
| `alert.gameNotStarted.message` | 保存这盘新对局时出错。请重试。 | Saving the new game failed. Please try again. | alert message | same |
| `alert.deleteGame.title` | 删除这盘棋？ | Delete this game? | alert title | [interaction-design.md](interaction-design.md) § History library |
| `alert.deleteGame.message` | 删除后无法恢复。 | This game can't be recovered. | alert message | same |
| `alert.deleteFailed.title` *(proposed)* | 无法删除这盘棋 | Couldn't Delete This Game | alert title | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |
| `alert.deleteFailed.message` *(proposed)* | 这盘棋仍然保留在历史里。请重试。 | This game is still in History. Please try again. | alert message | same |
| `alert.importDuplicate.title` | 这盘棋已经在历史里 | This Game Is Already in History | alert title | [interaction-design.md](interaction-design.md) § History library; [game-data.md](game-data.md) § Accepted MVP record behavior; `History/HistoryScreen.swift` |
| `alert.importDuplicate.message` | 文件里的对局和历史中的一盘完全相同，所以没有重复添加。 | The game in this file is identical to one already in History, so it wasn't added again. | alert message | same |
| `alert.importConflict.title` | 这个文件和历史中的一盘棋冲突 | This File Conflicts with a Game in History | alert title | same |
| `alert.importConflict.message` | 它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。 | It is the same game as one in History, but its contents differ. History is unchanged. To use this file, delete that game from History first. | alert message | same |
| `alert.importNewerVersion.title` | 这个文件由更新版本的 Mini Xiangqi 创建 | This File Was Created by a Newer Version of Mini Xiangqi | alert title | [game-data.md](game-data.md) § Migration — the one message the compatibility promise requires to be distinct |
| `alert.importNewerVersion.message` | 当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。 | This version can't read it. Update Mini Xiangqi and try again. History is unchanged. | alert message | same |
| `alert.importUnreadable.title` | 无法读取这个对局文件 | Can't Read This Game File | alert title | [interaction-design.md](interaction-design.md) § History library |
| `alert.importUnreadable.message` | 文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。 | The file's contents are invalid or too large to import. History is unchanged. Check that the file is complete, or ask for a new copy. | alert message | same |
| `alert.importSaveFailed.title` | 无法保存导入的对局 | Couldn't Save the Imported Game | alert title | same |
| `alert.importSaveFailed.message` | 对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。 | The game file is fine, but saving it to History failed. History is unchanged. Please try again. | alert message | same |
| `alert.importDamagedRecord.title` | 历史中有一盘损坏的棋 | A Game in History Is Damaged | alert title | same — the one import answer about the library rather than the file, and the only one that may say 损坏 |
| `alert.importDamagedRecord.message` | 这个文件对应的历史记录已损坏，无法比较或导入。如果要用这个文件，请先删除历史中的那一盘。 | The record in History matching this file is damaged, so it can't be compared or imported. To use this file, delete that game from History first. | alert message | same |

`alert.claimDraw.title` and `alert.claimDraw.message` together preserve the accepted sentence 局面已三次重复，可以和棋结束。 The split into title and message is the accepted presentation; neither half is a new decision, and the pair must not be recombined into a single title.

`alert.deleteGame.message` says *recovered* rather than *undone* on purpose: the application has a visible Undo control that means something else, and the target MVP has no deletion Undo.

`alert.aiUnavailable.title` carries **two** messages, because the situation is one situation and the guarantee is not. Memory is not available right now, whether the game has started or not, so a second title would name a distinction the reader cannot act on. What the mid-game form adds is the one thing the pre-start case has no need of — the game is saved — and its actions are 稍后 and 重试 rather than 取消 and 重试, because there is nothing to cancel.

`alert.gameNotStarted.*` is the creation failure that is **not** about memory: the game could not be persisted. It cannot borrow `alert.saveFailed.*`, whose message promises that 当前对局仍然保留 — there is no current game to keep, and a message that says there is would be worse than no message.

`alert.newGame.metadataHeader`, the active game's metadata line, and `alert.newGame.message` are composed into that alert's one message with line breaks between them, because an alert on Apple platforms is a title, a message and its actions and has no third slot for a header. **The break is not copy and carries no key**: it holds no punctuation and is the same in both languages, so no format string stands between them — unlike `metadata.join`, whose middot is a piece of writing. The same header names the current-game section on the Play home, over the same line; it is one string for one thing, not two keys for two surfaces.

### Failure screens

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `failure.coreDidNotStart` | 核心未能启动 | The core did not start | unavailable-content title | `ContentView.swift` — English shipped; the Chinese source is supplied here |
| `failure.gameDidNotStart` | 对局未能开始 | The game did not start | unavailable-content title | `Play/PlayScreen.swift` — same |
| `failure.historyDidNotLoad` *(proposed)* | 历史未能载入 | History did not load | unavailable-content title | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |

Both screens carry a technical description beneath the title. That description is diagnostic text from the core, not copy, and is not localized.

### Pre-start setup

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `setup.thisGame` | 本局设置 | This Game | control-group header | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |
| `setup.firstMover` | 先后手 | First Mover | accessibility label | same — the segmented control's own name. 本局设置 names the group and the three options name themselves, so it is not drawn; a screen reader still has to be able to call the control something, and 默认先后手 is the Settings default's name rather than this game's |
| `setup.iMoveFirst` | 我先手 | I Move First | option | same; [product.md](product.md) § Target-MVP play modes |
| `setup.aiMovesFirst` | AI 先手 | AI Moves First | option | same |
| `setup.random` | 随机 | Random | option | same |
| `setup.aiLevel` | AI 等级 | AI Level | row label | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |
| `setup.level.fast` | 快速 | Fast | option | same; [product.md](product.md) § Target-MVP play modes; [engine-integration.md](engine-integration.md) |
| `setup.level.standard` | 标准 | Standard | option | same |
| `setup.level.deep` | 深思 | Deep | option | same |
| `setup.freePlayExplanation` | 你将控制红黑双方，红方先行。 | You control both Red and Black. Red moves first. | explanatory line | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |

### Settings

The Settings destination as it stands: four groups, and every string on it below.

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `settings.section.board` | 棋盘 | Board | group header | [issue #64](https://github.com/ppppvz/MiniXiangqi/issues/64) § The Settings screen; `Settings/SettingsScreen.swift` — one of the two groups with a header |
| `settings.symbols.label` | 棋子符号 | Piece Symbols | row label | same; the choice itself is fixed in [interaction-design.md](interaction-design.md) § Piece symbols |
| `settings.symbols.hanzi` | 汉字 | Chinese Characters | option | same — the accepted default |
| `settings.symbols.icons` | 图标 | Icons | option | same |
| `settings.notation.label` | 记谱法 | Notation | row label | same; the choice itself is fixed in [interaction-design.md](interaction-design.md) § User-visible notation |
| `settings.notation.traditional` | 中文 | Chinese | option | same — the accepted default |
| `settings.notation.wxf` | WXF | WXF | option | same — identical in both languages |
| `settings.sound.label` | 声音 | Sound | toggle label | same; [interaction-design.md](interaction-design.md) § Sound and haptics |
| `settings.haptics.label` | 触感 | Haptics | toggle label | same |
| `settings.confirmDelete.label` | 删除前确认 | Confirm Before Deleting | toggle label | same; [interaction-design.md](interaction-design.md) § History library; [product.md](product.md) § Product navigation |
| `settings.confirmDelete.footer` | 关闭后，删除立即执行。删除无法撤销。 | When off, deletion happens immediately. A deletion cannot be undone. | group footer | same |
| `settings.defaults.group` | 人机对弈默认设置 | Human versus AI Defaults | group header | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Settings/SettingsScreen.swift` |
| `settings.defaults.firstMover` | 默认先后手 | Default First Mover | row label | same |
| `settings.defaults.aiLevel` | 默认 AI 等级 | Default AI Level | row label | same |
| `settings.defaults.footer` | 这些设置用于开始新的人机对弈，不会改变进行中的对局。 | These settings apply when you start a new Human versus AI game. They don't change a game in progress. | group footer | same — the accepted footer, which says what the two values do and what they deliberately do not |

And the rows for surfaces no longer built at all:

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `settings.confirmBeforeDeleting` | 删除前确认 | Confirm Before Deleting | toggle label | retired in favour of `settings.confirmDelete.label`, which names the same switch beside its footer; no surface reads it |
| `settings.pieces.group` | 棋子 | Pieces | group label | retired: the group became 棋盘 (`settings.section.board`), which is what the two choices in it are about |
| `settings.pieces.style` | 样式 | Style | row label | retired with the piece-style control, deferred in [product.md](product.md) § Product navigation |
| `settings.pieces.symbols` | 符号 | Symbols | row label | retired in favour of `settings.symbols.label`: with the style row gone, 符号 alone no longer says what it is the symbol of |
| `settings.pieces.footer` | 棋子样式同时决定棋盘的配色。 | The piece style also sets the board colors. | group footer | retired with the piece-style row it explained |
| `settings.pieces.style.traditional` | 传统 | Traditional | option | retired with the piece-style control; the style itself is still the accepted default in [interaction-design.md](interaction-design.md) § Piece styles |
| `settings.pieces.style.modern` | 现代 | Modern | option | same |
| `settings.pieces.style.highContrast` | 高对比度 | High Contrast | option | same |
| `settings.pieces.symbols.characters` | 汉字 | Chinese Characters | option | retired in favour of `settings.symbols.hanzi`; the word is unchanged |
| `settings.pieces.symbols.icons` | 图标 | Icons | option | retired in favour of `settings.symbols.icons`; the word is unchanged |

**中文** names the notation by the language it is written in, not by 传统, which names a piece style: a screen that offered 传统 in two groups for two unrelated things would teach the wrong word. **WXF** is a name and is never translated, like **AI** in `status.controller.ai`; it carries a key all the same, because it is a control label and both languages have to answer for it.

There are two footers on the screen, and only two. `settings.confirmDelete.footer` says what turning the switch off costs and that the cost is permanent — the permanence is [product.md](product.md)'s own rule, not a warning invented here. `settings.defaults.footer` says what the two values above it are *for*, which is the one thing a reader cannot work out from the labels: they initialize the next game's setup and never reach the game already on the board. Every other group goes without, because a footer under every group is a screen nobody reads.

Nothing here offers an interface language, and no key exists for one: the operating system owns the language, per the Settings scope in [product.md](product.md).

### Game metadata

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `metadata.youRed` | 你执红 | You: Red | metadata token | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `metadata.youBlack` | 你执黑 | You: Black | metadata token | this contract — the mirror of 你执红, which is the form the contracts happen to show; `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `metadata.inProgress` | 进行中 | In Progress | metadata token | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; `Play/ActiveGameMetadata.swift` — the live game's own state, where a filed record has a committed result instead |
| `metadata.moveCount` | `%lld 步` | `%lld moves` | metadata token | same; `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `metadata.imported` | 导入 | Imported | row prefix on an imported record | [interaction-design.md](interaction-design.md) § History library; `History/RecordMetadata.swift` |
| `metadata.join` | `%1$@ · %2$@` | `%1$@ · %2$@` | metadata-line format | same; `Play/TurnStatus.swift` |

`metadata.moveCount` is a plural pattern in English and a literal in Chinese: 步 is invariant, *move* is not, and a one-ply game is reachable in Free Play. English *move* counts one player's move, mirroring the number the Chinese shows; Help defines the term, and that definition is owed by the Help stage.

`metadata.join` composes the accepted metadata lines — 人机对弈 · 你执红, 进行中 · 轮到黑方 · 42 步, 红方获胜 · 将死 · 42 步, 进行中 · 可判和 · 42 步 — and is applied repeatedly rather than once per line length. The middot and its surrounding spaces are the same in both languages.

### History and replay

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `history.section.pinned` *(proposed)* | 已置顶 | Pinned | list section header | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |
| `history.section.others` *(proposed)* | 其他对局 | Other Games | list section header | same |
| `history.empty.title` *(proposed)* | 还没有历史对局 | No Games Yet | unavailable-content title | same |
| `history.empty.description` *(proposed)* | 对局结束后会保存到这里。 | Games you finish are saved here. | unavailable-content description | same |
| `replay.progress` *(proposed)* | `%1$lld / %2$lld` | `%1$lld / %2$lld` | replay progress | [interaction-design.md](interaction-design.md) § History replay; `History/ReplayScreen.swift` — plies shown of plies recorded; numerals and a separator, and no word is translated |
| `replay.first` *(proposed)* | 回到开始 | Go to Start | accessibility label | same; `History/ReplayTransport.swift` |
| `replay.previous` *(proposed)* | 上一步 | Previous Move | accessibility label | same |
| `replay.next` *(proposed)* | 下一步 | Next Move | accessibility label | same |
| `replay.last` *(proposed)* | 跳到最后 | Go to End | accessibility label | same |
| `replay.autoplay` *(proposed)* | 自动播放 | Autoplay | accessibility label | same |
| `replay.pause` *(proposed)* | 暂停 | Pause | accessibility label | same |

The five transport controls are icon-only, so every one of these is what a screen reader reads and what a pointer's help tag shows; none of them is drawn on screen. **Autoplay** rather than *Play* in English because 对局 is already *Play*: the navigation destination and the playback control would otherwise be the same English word, and the Chinese never had that collision.

`history.empty.description` is one sentence rather than the two the Part 7 draft proposed. The second named importing a game file, and import does not exist yet; a line that offers an action the app cannot take is worse than a short line.

### Board accessibility

The point description is composed from the square name, then the vocabulary below in the order the board contract gives.

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `board.a11y.red` | 红 | Red | accessibility label | `Board/BoardView.swift` |
| `board.a11y.black` | 黑 | Black | accessibility label | same |
| `board.a11y.empty` | 空 | Empty | accessibility label | same |
| `board.a11y.selected` | 已选择 | Selected | accessibility label | same |
| `board.a11y.legalMove` | 可走 | Legal Move | accessibility label | same |
| `board.a11y.capture` | 可吃 | Capture | accessibility label | same |
| `board.a11y.inCheck` | 被将军 | In Check | accessibility label | same |

### Piece names

English piece names are accepted in [interaction-design.md](interaction-design.md) § Piece representation. They are recorded here because they are the English half of a pair: where an accessibility label or a line of Help names a piece, Chinese names it by the character the piece carries and English names it by its name. They are never board labels in either language.

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `piece.general` | 帅 (red) / 将 (black) | General | help text; accessibility label | [interaction-design.md](interaction-design.md) § Piece representation; `Board/Board.swift` |
| `piece.chariot` | 俥 / 车 | Chariot | help text; accessibility label | same |
| `piece.horse` | 傌 / 马 | Horse | help text; accessibility label | same |
| `piece.cannon` | 炮 / 砲 | Cannon | help text; accessibility label | same |
| `piece.soldier` | 兵 / 卒 | Soldier | help text; accessibility label | same |

### Move list and application

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `moveList.rowNumber` | `%lld.` | `%lld.` | move-list row number | `Play/MoveList.swift` — numerals and a full stop; no word is translated |
| `app.displayName` | Mini Xiangqi | Mini Xiangqi | application name | [product.md](product.md) § Product identity and distribution; `apple/MiniXiangqi.xcodeproj` — one name in both languages for now, and open below |

## Where the two languages deliberately do not match one to one

These are decisions, not oversights, and a mechanical one-to-one check will flag them.

- **Two Chinese result forms share one English form.** The notice titles 红方获胜 / 黑方获胜 / 和棋 and the shorter status-line forms 红方胜 / 黑方胜 / 和局 are two registers in Chinese — a sentence about the game and a line about the turn — and both take Red Wins / Black Wins / Draw in English. English has no equivalent register difference short enough for the status line, and inventing one would make the two surfaces disagree about the same result.
- **One Chinese string takes two English words.** 认输 is the control (`control.resign`, **Resign**) and the recorded reason (`reason.resignation`, **Resignation**). The Chinese is the same word acting as verb and as noun; English is not.
- **The claim's action and its state stay apart in both languages.** 判和 is the control (**Claim Draw**); 可判和 is the state (**Draw Available**). Chinese already distinguishes them and English follows.
- **The accessibility representation switches with the language.** Chinese names a piece by the character on it — 帅, 炮 — because that is what the board shows and what the reader is learning. English names it by its piece name, never by the character, per the accepted piece-representation rule. So `b1 红 炮 已选择` is `b1 Red Cannon Selected` and not `b1 Red 炮 Selected`.
- **请 is mirrored, not dropped.** Where the Chinese says 请, the English says *Please* — in `status.saveFailed`, `alert.saveFailed.message`, and `alert.aiUnavailable.message`. The English is a translation of the Chinese and says neither more nor less than it does.

## Never translated

Game content is identical in every supported language. It is not copy, it carries no key, and it never enters the String Catalog.

- **The ten piece characters** — 帅 将 俥 车 傌 马 炮 砲 兵 卒. Fixed in [interaction-design.md](interaction-design.md) § Piece representation: the pieces are Chinese characters, this is a teaching application, and the board presents the real characters rather than a translated substitute.
- **The notation direction and position tokens** — 进, 退, 平, and the leading 前, 中, 后 — and the numbered forms that replace them when four or more pieces of a type share a file: 一兵, 二兵, and so on. Fixed in [interaction-design.md](interaction-design.md) § User-visible notation, which also fixes that a piece is named in a move by its own side's character form.
- **The Chinese numerals in notation and in the file-numeral strip** — 一 二 三 四 五 六 七. Red writes every number in a move in Chinese numerals and Black in Arabic ones, and the numeral strips show each player their own. Fixed in [interaction-design.md](interaction-design.md) § User-visible notation.
- **Pictorial piece icons**, when that symbol set is selected. They are game presentation and do not change with the interface language, per [interaction-design.md](interaction-design.md) § Piece symbols.

A reader using icon symbols still reads a character-based move list, because traditional notation names pieces by their characters. What else that reader is offered remains open in [interaction-design.md](interaction-design.md) § Need to discuss.

## The localization process

1. **Both languages are complete before a string ships.** A String Catalog carries a `zh-Hans` and an `en` entry for every key in the table above. A key with one language filled in is an incomplete string, not a partially localized one.
2. **Keys are symbolic, never the source string.** Xcode's default is source-string-as-key; it is wrong here, because the source language is Chinese, a Chinese key is unreadable to an English reviewer, and a wording change in the normative Chinese would silently orphan its translation. The key is the join between this contract and the catalog, and it is what makes a copy change reviewable as a copy change.
3. **`developmentRegion` stays `en`.** Chinese normativity is a property of this contract, not of an Xcode setting: the build's development region governs how Xcode and the platform treat the project, and changing it would buy nothing that this document does not already state. (Owner decision, 2026-07-28.)
4. **Every copy change is a contract change.** A new string, a reworded string, or a retired key is a pull request against this file, reviewed as a contract is reviewed. The catalog follows the contract; the contract never follows the catalog.
5. **Nothing machine-translated ships as accepted.** A translation carrying Xcode's Machine Translated state — XLIFF `state-qualifier` `leveraged-mt` — is a draft. Acceptance happens in this table.
6. **Per internal build, two mechanical runs and one human pass.** Run the application under the Double-Length and Bounded String pseudolanguages and confirm nothing truncates and nothing intersects the board block; then run the accepted smoke flows in both Simplified Chinese and English, switching with the system's per-app language setting.
7. **Native-speaker review is TestFlight internal testing.** Apple's own recommendation for reviewing localized copy is to put the build in front of native speakers, and internal distribution already does exactly that. There is no separate reviewer role and no XLIFF round trip: with one reviewer per language, a hand-off buys ceremony rather than scrutiny.
8. **A mechanical agreement check joins CI when CI exists.** One check that this table and the String Catalog agree in both languages — the same key set, the same values, and no user-facing key in the catalog that is absent here. It needs no second human, and it is the evidence [testing.md](testing.md) asks for.

## Implementation notes

These are the consequences for the code that the localization pull request inherited rather than rediscovered. **All seven were discharged by that PR**; they stand as the record of what it owed, and the code they describe is the code as it stood before it.

- **The accessibility representation switch needs a mapping the code does not have.** `Board/BoardView.swift` builds a point's label from the piece's *character*, which is correct in Chinese and wrong in English. The English label uses the piece name, so the code needs a piece-kind-to-localized-name mapping beside the existing kind-to-character one. `b1 红 炮 已选择` becomes `b1 Red Cannon Selected`.
- **Every composed string becomes a localized format string.** Three exist today and each is currently built by concatenation: the result announcement's ideographic comma in `Play/ResultNotice.swift`, the ideographic space before 将军 in `Play/TurnStatus.swift`, and the ` · ` metadata join in the same file. Their separators differ between the languages and cannot be hard-coded around a translated fragment.
- **The claim alert splits into a title and a message.** Today the whole sentence is the alert title in `Play/PlayScreen.swift`. `alert.claimDraw.title` and `alert.claimDraw.message` are separate keys and separate alert roles.
- **The three cluster buttons need accessibility identifiers.** `PlayScreenUITests` finds 悔棋, 判和, and 翻转棋盘 by their labels. A label is copy and will change with the language; an identifier will not. The identifiers go in before localization, not after it breaks the suite.
- **The two failure screens gain Chinese sources.** `ContentView.swift` and `Play/PlayScreen.swift` carry English literals with no Chinese behind them. `failure.coreDidNotStart` and `failure.gameDidNotStart` supply it.
- **`metadata.moveCount` is a plural pattern**, authored with the String Catalog's plural variants rather than as a literal with a number interpolated into it.
- **One code comment still carries the pre-rename style name.** `Board/BoardStyle.swift` says 高对比 where the contract now says 高对比度; the rename rides along with the next change to that file.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Decide whether the application's display name stays **Mini Xiangqi** in Simplified Chinese. One name in both languages is what ships today and is recorded above as accepted for now; a Chinese name is a product-identity decision rather than a translation.
- Approve the rows marked *(proposed)* above: the two History section headers, the empty state's two lines, the History-read failure title, the deletion-failure pair, and the replay transport's seven. They are what the History destination and its replay say, and they ship in the String Catalog behind this proposal.
- Supply copy for the surfaces that still have no accepted string in either language: the Help entry point and its contents, and autoplay speeds if they are ever offered. The sound and haptics toggles are no longer among them — 声音 and 触感 are accepted above, with the rest of the Settings destination, in [issue #64](https://github.com/ppppvz/MiniXiangqi/issues/64)'s Stage 5 design. Import and export, and the import, duplicate, conflict and error messages, are proposed above rather than still open. The History row's date and move-count formatting needed no copy in the end — the date is the system's own words and the count reuses `metadata.moveCount`.
- Decide what the metadata line does in English where it is aligned to the board. The middot composition is accepted, and the English forms of the longest lines are materially wider than their Chinese sources; whether they wrap, restyle, or recompose is a layout question that belongs with the stacked-layout item in [interaction-design.md](interaction-design.md) § Need to discuss, not a copy question.
