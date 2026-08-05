# Copy

This document owns every user-facing string pair — the normative Simplified Chinese and its approved English — the symbolic key each pair is stored under, the vocabulary that is never translated, and the localization process. It does not own where a string appears, when it appears, or the behavior it describes; each of those belongs to the contract named beside the row.

> **Status: binding.** The Simplified Chinese is normative and exact; the English counterparts are approved. Strings also appear inline in other contracts where behavior is described, and that is deliberate — a contract has to be readable on its own — but **this table is the string of record for the pair and for the key**, and a difference between a row here and a quotation elsewhere is resolved in favour of the row. A row marked *(proposed)* is not accepted.

## How to read the table

- **Key** is the symbolic key the string is stored under in the String Catalog. Keys are hierarchical and stable: a key survives a wording change in either language, and it is the join between this contract and the build artefact. A key is never the source string.
- **中文** is normative. It is what a reviewer approves and what a translator translates from.
- **English** is approved, and is a translation of the Chinese rather than a second source.
- **Surface** is what the string is presented as, because the same words are written differently on a button, in an alert title, and in an accessibility label.
- **Source** names the contract section that owns the behavior, and, where the string is live, the file it is live in.

Contract sections are cited by document and section name rather than by line number, so that the citation survives an edit above it. The table's five-column shape is machine-read: the Windows smoke harness parses this file and checks its own string table against these rows.

## The string table

### Navigation and modes

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `nav.play` | 对局 | Play | navigation destination; screen title; the Play back control's accessibility label | [product.md](product.md) § Product navigation; [interaction-design.md](interaction-design.md) § Navigation — English only there; `Play/PlayDestination.swift` — a back control names the page it returns to, which here is always the Play home |
| `nav.history` | 历史 | History | navigation destination | same; 历史 is attested inside 保存到历史 and 已记录到历史 |
| `nav.settings` | 设置 | Settings | navigation destination; screen title | same; 设置 is attested inside 本局设置 and 人机对弈默认设置; `ContentView.swift`, `Settings/SettingsScreen.swift` |
| `nav.resumeGame` | 回到对局 | Resume Game | button | [interaction-design.md](interaction-design.md) § The Play home, § Saving the active game before choosing a new mode — English only there; `Play/PlayHome.swift` |
| `nav.moveList` | 棋谱 | Moves | toolbar item; sheet title | [interaction-design.md](interaction-design.md) § The move list during play — the stacked layout reaches the list on demand, and this names both the item that reaches it and the sheet it opens; `Play/PlayScreen.swift`. 谱 is attested inside 记谱法 |
| `game.xiangqi` | 象棋 | Xiangqi | Play-home section header; pre-start game name; metadata token | [interaction-design.md](interaction-design.md) § The Play home, § Starting and configuring a game, § Saving the active game before choosing a new mode; `Play/PlayHome.swift`, `Play/SetupScreen.swift`, `Play/ActiveGameMetadata.swift` |
| `game.miniXiangqi` | 迷你象棋 | Mini Xiangqi | Play-home section header; pre-start game name; metadata token | same — this is the game name inside the application, while `app.displayName` remains the product name |
| `mode.humanVersusAI` | 人机对弈 | Human versus AI | mode entry; metadata token | [interaction-design.md](interaction-design.md) § The Play home, § Saving the active game before choosing a new mode; [product.md](product.md) § Play modes; `Play/PlayHome.swift`, `Play/ActiveGameMetadata.swift` |
| `mode.freePlay` | 自由对弈 | Free Play | mode entry; metadata token | same |
| `mode.nearby` | 附近对弈 | Nearby Play | mode entry | [interaction-design.md](interaction-design.md) § Nearby play — the third row inside each game's section, absent where the hardware has no radio; `Play/PlayHome.swift` |

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
| `control.endGame` | 结束对局 | End Game | button | [interaction-design.md](interaction-design.md) § Natural result presentation — no surface reads it; `control.save` names that act |
| `control.done` | 完成 | Done | button | [interaction-design.md](interaction-design.md) § Natural result presentation, § The move list during play — the same word closes the recorded notice and the stacked layout's move-list sheet; `Play/ResultNotice.swift`, `Play/PlayScreen.swift` |
| `control.replay` | 回放 | Replay | button | [interaction-design.md](interaction-design.md) § Natural result presentation; `Play/ResultNotice.swift` |
| `control.close` | 关闭 | Close | accessibility label | [interaction-design.md](interaction-design.md) § Natural result presentation — the result notice's own close control. On Apple platforms the platform names it and no key is read; on Windows the control is the app's own glyph button and has to be named. `windows/MiniXiangqi.App/MainWindow.xaml.cs` |
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
| `control.accept` | 接受 | Accept | alert button | [interaction-design.md](interaction-design.md) § Nearby play — the consent prompt's answer that starts the game; `Nearby/NearbyProposeSheet.swift` |
| `control.decline` | 拒绝 | Decline | alert button | same — its other answer. 拒绝 rather than 取消: an invitation is refused, not cancelled |

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
| `status.controller.peer` | 对方 | Them | secondary label | [interaction-design.md](interaction-design.md) § Turn status, § Nearby play — the other player at the other device; `Play/TurnStatus.swift` |
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
| `reason.fiftyMoveRule` | 五十回合规则 | Fifty-Move Rule | reason line; metadata token | [xiangqi-rules.md](xiangqi-rules.md) § End conditions; `Play/TurnStatus.swift` |
| `reason.resignation` | 认输 | Resignation | reason line; metadata token | same |
| `reason.endedEarly` | 提前结束 | Ended Early | reason line; metadata token; the History row's **result** slot | same; [interaction-design.md](interaction-design.md) § History library — `outcome = none` holds exactly when the reason is ended-early, so the row states the one fact once rather than adding a word for the absence of a winner |

**Stalemate is kept deliberately.** It is the standard English Xiangqi term, the notice title has already named the winner, and Help owes the statement that having no legal move loses in Xiangqi. The English word's chess sense is corrected by the surface it appears on rather than by renaming the reason.

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
| `alert.nearbyInvite.title` | 对方邀请你对弈 | Someone Wants to Play | alert title | [interaction-design.md](interaction-design.md) § Nearby play; `Nearby/NearbyProposeSheet.swift` |
| `alert.nearbyInvite.message` | 接受后立即开始对局。 | The game starts as soon as you accept. | alert message | same — the sentence under the invitation's own metadata line |
| `alert.nearbyDeclined.title` | 对局没有开始 | The Game Didn't Start | alert title | same — the title over every refusal in the § Nearby play table below |
| `alert.deleteGame.title` | 删除这盘棋？ | Delete this game? | alert title | [interaction-design.md](interaction-design.md) § History library |
| `alert.deleteGame.message` | 删除后无法恢复。 | This game can't be recovered. | alert message | same |
| `alert.deleteFailed.title` | 无法删除这盘棋 | Couldn't Delete This Game | alert title | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |
| `alert.deleteFailed.message` | 这盘棋仍然保留在历史里。请重试。 | This game is still in History. Please try again. | alert message | same |
| `alert.importDuplicate.title` | 这盘棋已经在历史里 | This Game Is Already in History | alert title | [interaction-design.md](interaction-design.md) § History library; [game-data.md](game-data.md) § Import and export; `History/HistoryScreen.swift` |
| `alert.importDuplicate.message` | 文件里的对局和历史中的一盘完全相同，所以没有重复添加。 | The game in this file is identical to one already in History, so it wasn't added again. | alert message | same |
| `alert.importConflict.title` | 这个文件和历史中的一盘棋冲突 | This File Conflicts with a Game in History | alert title | same |
| `alert.importConflict.message` | 它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。 | It is the same game as one in History, but its contents differ. History is unchanged. To use this file, delete that game from History first. | alert message | same |
| `alert.importNewerVersion.title` | 这个文件由更新版本的 Mini Xiangqi 创建 | This File Was Created by a Newer Version of Mini Xiangqi | alert title | [game-data.md](game-data.md) § Versions — the distinct answer for an archive whose version is newer than this build |
| `alert.importNewerVersion.message` | 当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。 | This version can't read it. Update Mini Xiangqi and try again. History is unchanged. | alert message | same |
| `alert.importUnreadable.title` | 无法读取这个对局文件 | Can't Read This Game File | alert title | [interaction-design.md](interaction-design.md) § History library |
| `alert.importUnreadable.message` | 文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。 | The file's contents are invalid or too large to import. History is unchanged. Check that the file is complete, or ask for a new copy. | alert message | same |
| `alert.importSaveFailed.title` | 无法保存导入的对局 | Couldn't Save the Imported Game | alert title | same |
| `alert.importSaveFailed.message` | 对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。 | The game file is fine, but saving it to History failed. History is unchanged. Please try again. | alert message | same |
| `alert.importDamagedRecord.title` | 历史中有一盘损坏的棋 | A Game in History Is Damaged | alert title | same — the one import answer about the library rather than the file, and the only one that may say 损坏 |
| `alert.importDamagedRecord.message` | 这个文件对应的历史记录已损坏，无法比较或导入。如果要用这个文件，请先删除历史中的那一盘。 | The record in History matching this file is damaged, so it can't be compared or imported. To use this file, delete that game from History first. | alert message | same |

`alert.claimDraw.title` and `alert.claimDraw.message` together preserve the accepted sentence 局面已三次重复，可以和棋结束。 The split into title and message is the accepted presentation, and the pair must not be recombined into a single title.

`alert.deleteGame.message` says *recovered* rather than *undone* on purpose: the application has a visible Undo control that means something else, and there is no deletion Undo.

`alert.aiUnavailable.title` carries **two** messages, because the situation is one situation and the guarantee is not. Memory is not available right now, whether the game has started or not, so a second title would name a distinction the reader cannot act on. What the mid-game form adds is the one thing the pre-start case has no need of — the game is saved — and its actions are 稍后 and 重试 rather than 取消 and 重试, because there is nothing to cancel.

`alert.gameNotStarted.*` is the creation failure that is **not** about memory: the game could not be persisted. It cannot borrow `alert.saveFailed.*`, whose message promises that 当前对局仍然保留 — there is no current game to keep, and a message that says there is would be worse than no message.

`alert.newGame.metadataHeader`, the active game's metadata line, and `alert.newGame.message` are composed into that alert's one message with line breaks between them, because an alert on Apple platforms is a title, a message and its actions and has no third slot for a header. **The break is not copy and carries no key**: it holds no punctuation and is the same in both languages, so no format string stands between them — unlike `metadata.join`, whose middot is a piece of writing. The same header names the current-game section on the Play home, over the same line; it is one string for one thing, not two keys for two surfaces.

### Failure screens

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `failure.coreDidNotStart` | 核心未能启动 | The core did not start | unavailable-content title | `ContentView.swift` |
| `failure.gameDidNotStart` | 对局未能开始 | The game did not start | unavailable-content title | `Play/PlayScreen.swift` |
| `failure.historyDidNotLoad` | 历史未能载入 | History did not load | unavailable-content title | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |

Each screen carries a technical description beneath the title. That description is diagnostic text from the core, not copy, and is not localized.

### Pre-start setup

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `setup.thisGame` | 本局设置 | This Game | control-group header | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |
| `setup.firstMover` | 先后手 | First Mover | accessibility label | same — the segmented control's own name. 本局设置 names the group and the three options name themselves, so it is not drawn; a screen reader still has to be able to call the control something, and 默认先后手 is the Settings default's name rather than this game's |
| `setup.iMoveFirst` | 我先手 | I Move First | option | same; [product.md](product.md) § Play modes |
| `setup.aiMovesFirst` | AI 先手 | AI Moves First | option | same |
| `setup.random` | 随机 | Random | option | same |
| `setup.aiLevel` | AI 等级 | AI Level | row label | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |
| `setup.level.fast` | 快速 | Fast | option | same; [product.md](product.md) § Play modes; [engine-integration.md](engine-integration.md) |
| `setup.level.standard` | 标准 | Standard | option | same |
| `setup.level.deep` | 深思 | Deep | option | same |
| `setup.freePlayExplanation` | 你将控制红黑双方，红方先行。 | You control both Red and Black. Red moves first. | explanatory line | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Play/SetupScreen.swift` |

### Settings

The Settings destination is four preference groups and the About row under them, and every string on it and on the About page it reaches is below.

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `settings.section.board` | 棋盘 | Board | group header | [product.md](product.md) § Product navigation; `Settings/SettingsScreen.swift` — one of the two groups with a header |
| `settings.symbols.label` | 棋子符号 | Piece Symbols | row label | same; the choice itself is fixed in [interaction-design.md](interaction-design.md) § Piece symbols |
| `settings.symbols.hanzi` | 汉字 | Chinese Characters | option | same — the accepted default |
| `settings.symbols.icons` | 图标 | Icons | option | same |
| `settings.notation.label` | 记谱法 | Notation | row label | same; the choice itself is fixed in [interaction-design.md](interaction-design.md) § User-visible notation |
| `settings.notation.traditional` | 中文 | Chinese | option | same — the default under the Chinese interface, where the default follows the interface language |
| `settings.notation.wxf` | WXF | WXF | option | same — identical in both languages, and the default under the English interface |
| `settings.sound.label` | 声音 | Sound | toggle label | same; [interaction-design.md](interaction-design.md) § Sound and haptics |
| `settings.haptics.label` | 触感 | Haptics | toggle label | same; the row is absent where the device has no haptic hardware, per the same section |
| `settings.confirmDelete.label` | 删除前确认 | Confirm Before Deleting | toggle label | same; [interaction-design.md](interaction-design.md) § History library; [product.md](product.md) § Product navigation |
| `settings.confirmDelete.footer` | 关闭后，删除立即执行。删除无法撤销。 | When off, deletion happens immediately. A deletion cannot be undone. | group footer | same |
| `settings.defaults.group` | 人机对弈默认设置 | Human versus AI Defaults | group header | [interaction-design.md](interaction-design.md) § Starting and configuring a game; `Settings/SettingsScreen.swift` |
| `settings.defaults.firstMover` | 默认先后手 | Default First Mover | row label | same |
| `settings.defaults.aiLevel` | 默认 AI 等级 | Default AI Level | row label | same |
| `settings.defaults.footer` | 这些设置用于开始新的人机对弈，不会改变进行中的对局。 | These settings apply when you start a new Human versus AI game. They don't change a game in progress. | group footer | same — the accepted footer, which says what the two values do and what they deliberately do not |
| `about.title` | 关于 | About | Settings row label; page title | [interaction-design.md](interaction-design.md) § Navigation; `Settings/SettingsScreen.swift`, `Settings/AboutScreen.swift` — one word for the row and the page it opens |
| `about.name` | 名称 | Name | row label | same — the value beside it is the bundle's display name, which is `app.displayName` |
| `about.version` | 版本 | Version | row label | same — the value beside it is the bundle's marketing version, a number rather than copy |
| `about.build` | 构建版本 | Build | row label | same — the bundle's build, likewise |
| `about.license` | 许可证 | License | row label; page title | [product.md](product.md) § Product identity and distribution; `Settings/AboutScreen.swift` — the licence text the page shows is the GPL's own document, not copy, and is not localized |
| `about.license.statement` | Mini Xiangqi 是自由软件，依据 GNU General Public License v3 发布。 | Mini Xiangqi is free software, released under the GNU General Public License v3. | group footer | same — the licence is named by its own name in both languages, like WXF |
| `about.source` | 源代码 | Source Code | row label | same — the row links the repository the App Store listing links |

And the keys no surface reads. They are kept so that none is reused for something else:

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `settings.confirmBeforeDeleting` | 删除前确认 | Confirm Before Deleting | toggle label | superseded by `settings.confirmDelete.label`, which names the same switch beside its footer |
| `settings.pieces.group` | 棋子 | Pieces | group label | superseded by `settings.section.board`, which is what the two choices in that group are about |
| `settings.pieces.style` | 样式 | Style | row label | the piece-style control is not offered, per [product.md](product.md) § Product navigation |
| `settings.pieces.symbols` | 符号 | Symbols | row label | superseded by `settings.symbols.label`: without the style row, 符号 alone no longer says what it is the symbol of |
| `settings.pieces.footer` | 棋子样式同时决定棋盘的配色。 | The piece style also sets the board colors. | group footer | belongs to the piece-style row it explained |
| `settings.pieces.style.traditional` | 传统 | Traditional | option | the style itself is still the accepted default in [interaction-design.md](interaction-design.md) § Piece styles |
| `settings.pieces.style.modern` | 现代 | Modern | option | same |
| `settings.pieces.style.highContrast` | 高对比度 | High Contrast | option | same |
| `settings.pieces.symbols.characters` | 汉字 | Chinese Characters | option | superseded by `settings.symbols.hanzi`; the word is unchanged |
| `settings.pieces.symbols.icons` | 图标 | Icons | option | superseded by `settings.symbols.icons`; the word is unchanged |

**中文** names the notation by the language it is written in, not by 传统, which names a piece style: a screen that offered 传统 in two groups for two unrelated things would teach the wrong word. **WXF** is a name and is never translated, like **AI** in `status.controller.ai`; it carries a key all the same, because it is a control label and both languages have to answer for it.

There are two footers on the Settings screen, and only two. `settings.confirmDelete.footer` says what turning the switch off costs and that the cost is permanent — the permanence is [product.md](product.md)'s own rule, not a warning invented here. `settings.defaults.footer` says what the two values above it are *for*, which is the one thing a reader cannot work out from the labels: they initialize the next game's setup and never reach the game already on the board. Every other group goes without, because a footer under every group is a screen nobody reads.

**The Windows frontend draws three of the four preference groups**, per the Settings scope in [product.md](product.md), so eight of the keys above carry no Windows string: `settings.section.board`, `settings.symbols.*`, `settings.notation.*` and `settings.haptics.label` — one group header, two rows of a label and two options each, and one switch — and no `about.*` key does either, that page being an Apple surface. Nothing about the *rows* changes — they are one contract for both frontends and the Apple app draws every one of them — and no key is retired, because each is a preference the Windows frontend has no surface for rather than one it disagrees with. **Both footers survive the trim**, which is why the paragraph above still reads the same on that platform: the two groups they belong to are among the three that ship, and an absent row explains itself by not being there rather than by needing a third footer to say so. The six option words the two default rows offer are `setup.iMoveFirst`, `setup.aiMovesFirst`, `setup.random` and the three `setup.level.*`, keyed once under **Pre-start setup** and read by both screens; `windows/MiniXiangqi.Play/Text/Strings.cs` is where the Windows half lives.

Nothing here offers an interface language, and no key exists for one: the operating system owns the language, per the Settings scope in [product.md](product.md).

### Nearby play

The propose sheet, the one line the board ever says about the connection, and the sentence under **对局没有开始**. The game names, the sides, the results and the reasons are the same rows the rest of this table already carries: a nearby game is a game.

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `nearby.theyMoveFirst` | 对方先手 | They Move First | option | [interaction-design.md](interaction-design.md) § Nearby play; `Nearby/NearbyProposeSheet.swift` — the other half of the side choice, beside `setup.iMoveFirst`. It names the other player because which colour they take belongs to the game |
| `nearby.devices` | 附近的设备 | Nearby Devices | group header | same |
| `nearby.searching` | 正在查找附近的设备… | Looking for nearby devices… | row | same — what the group says with nobody in it yet |
| `nearby.invite` | 发出邀请 | Send Invitation | button | same — the sheet's one tinted action |
| `nearby.waitingForAnswer` | 正在等待对方回应… | Waiting for a reply… | row | same — an invitation that has gone out and not been answered |
| `nearby.pairing` | 配对 | Pairing | group header | same |
| `nearby.pairing.footer` | 两台设备只需配对一次。 | Two devices only need to be paired once. | group footer | same |
| `nearby.discoverable` | 让这台设备可被发现 | Make This Device Discoverable | button | same — the system's own pairing view, named by what it does |
| `nearby.findDevice` | 查找设备 | Find a Device | button | same — the system's own device picker |
| `nearby.pairing.unavailable` | 这台设备无法配对 | This device can't pair | row | same — what stands where the system's pairing views cannot be offered |
| `nearby.connecting` | 正在连接对方… | Connecting to the other device… | status line at the turn status | [interaction-design.md](interaction-design.md) § Nearby play; `Nearby/NearbyBoardScreen.swift` — the one line the board ever says about the link, and only where the link is costing the player something |
| `nearby.refusal.declined` | 对方拒绝了这局对弈。 | They declined the game. | alert message | same — the protocol's `declined` |
| `nearby.refusal.busy` | 对方正在进行另一局对弈。 | They're already playing another game. | alert message | same — its `busy` |
| `nearby.refusal.unknownGame` | 对方的 App 不下这个游戏。 | Their app doesn't play this game. | alert message | same — its `unknown_game` |
| `nearby.refusal.rulesMismatch` | 两台设备对规则的解读不同。请都更新到最新版本后再试。 | The two devices read the rules differently. Update both to the latest version and try again. | alert message | same — its `rules_mismatch` |
| `nearby.refusal.unknownSession` | 对方设备上已经没有这局对弈了。 | The other device no longer has this game. | alert message | same — its `unknown_session` |
| `nearby.refusal.alreadyPlaying` | 你和对方已经有一局对弈了。 | You already have a game with this device. | alert message | same — one game at a time per pair of devices, which this device's own engine is what says |
| `nearby.refusal.settling` | 上一局还没有结束。请稍后再试。 | The last game hasn't finished yet. Please try again in a moment. | alert message | same — the pair's previous game is not settled between the two devices yet |
| `nearby.refusal.notNow` | 现在无法开始对局。请重试。 | The game can't start right now. Please try again. | alert message | same — every other refusal, which is a connection that went away between the press and the send |

The five refusal reasons above the last three are the protocol's own closed vocabulary, and each has a sentence rather than a shared one: they are things a person can act on — wait, update, or ask the other device — and a reader cannot act on a code. The last three are this device's engine refusing to send at all, in the three situations that differ for the reader.

### Game metadata

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `metadata.youRed` | 你执红 | You: Red | metadata token | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `metadata.youBlack` | 你执黑 | You: Black | metadata token | this contract — the mirror of 你执红, which is the form the contracts show; `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `metadata.inProgress` | 进行中 | In Progress | metadata token | [interaction-design.md](interaction-design.md) § Saving the active game before choosing a new mode; `Play/ActiveGameMetadata.swift` — the live game's own state, where a filed record has a committed result instead |
| `metadata.moveCount` | `%lld 步` | `%lld moves` | metadata token | same; `History/RecordMetadata.swift`, `Play/ActiveGameMetadata.swift` |
| `metadata.moveCount.one` | `%lld 步` | `%lld move` | metadata token | same — the plural pattern's **one** variant, spelled as a key of its own for a frontend with no String Catalog; `windows/MiniXiangqi.Play/Play/PlayText.cs` |
| `metadata.imported` | 导入 | Imported | row prefix on an imported record | [interaction-design.md](interaction-design.md) § History library; `History/RecordMetadata.swift` |
| `metadata.join` | `%1$@ · %2$@` | `%1$@ · %2$@` | metadata-line format | same; `Play/TurnStatus.swift` |

`metadata.moveCount` is a plural pattern in English and a literal in Chinese: 步 is invariant, *move* is not, and a one-ply game is reachable in Free Play. It is authored with the String Catalog's plural variants rather than as a literal with a number interpolated into it. English *move* counts one player's move, mirroring the number the Chinese shows; Help defines the term.

**`metadata.moveCount.one` is that pattern's other half, for a platform that has no pattern.** A String Catalog holds one key with plural variants and the platform selects between them, which is what the Apple frontend reads; the Windows frontend's string table is a table of pairs and has no such mechanism, so the **one** variant is a key and the frontend selects. It is one row rather than a full CLDR set because English has exactly two forms here and Chinese has one — a `zero`, `two`, `few` or `many` row would be a variant no supported language distinguishes. Both rows carry the same Chinese, deliberately: 步 does not change, and a row that pretended otherwise would be a translation nobody asked for. The key is only read where there is no catalog; nothing on Apple platforms looks it up.

`metadata.join` composes the accepted metadata lines, beginning with the game and mode — 象棋 · 人机对弈 · 你执红 · 进行中 · 轮到黑方 · 42 步, or 迷你象棋 · 自由对弈 · 红方获胜 · 将死 · 42 步 — and is applied repeatedly rather than once per line length. The middot and its surrounding spaces are the same in both languages.

### History and replay

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `history.section.pinned` | 已置顶 | Pinned | list section header | [interaction-design.md](interaction-design.md) § History library; `History/HistoryScreen.swift` |
| `history.section.others` | 其他对局 | Other Games | list section header | same |
| `history.empty.title` | 还没有历史对局 | No Games Yet | unavailable-content title | same |
| `history.empty.description` | 对局结束后会保存到这里。 | Games you finish are saved here. | unavailable-content description | same — one sentence, because the empty state says what it says and offers nothing else to do; the 导入… toolbar item is above it either way |
| `replay.progress` | `%1$lld / %2$lld` | `%1$lld / %2$lld` | replay progress | [interaction-design.md](interaction-design.md) § History replay; `History/ReplayScreen.swift` — plies shown of plies recorded; numerals and a separator, and no word is translated |
| `replay.first` | 回到开始 | Go to Start | accessibility label | same; `History/ReplayTransport.swift` |
| `replay.previous` | 上一步 | Previous Move | accessibility label | same |
| `replay.next` | 下一步 | Next Move | accessibility label | same |
| `replay.last` | 跳到最后 | Go to End | accessibility label | same |
| `replay.autoplay` *(proposed)* | 自动播放 | Autoplay | accessibility label | same |
| `replay.pause` *(proposed)* | 暂停 | Pause | accessibility label | same |

The five transport controls are icon-only, so every one of these is what a screen reader reads and what a pointer's help tag shows; none of them is drawn on screen. **Autoplay** rather than *Play* in English because 对局 is already *Play*: the navigation destination and the playback control would otherwise be the same English word, and the Chinese never had that collision.

**The Windows frontend ships every row above except `replay.autoplay` and `replay.pause`**, whose control does not exist there: Windows replay is a step-through viewer with four transport controls, so a fifth string would be one nothing reads. The two rows are not retired — the Apple frontend has the control — and they reach Windows with the autoplay control. The remaining rows are live in `windows/MiniXiangqi.Play/Text/Strings.cs` as well as in the String Catalog, and the mechanical agreement check runs over both.

### When there is no room for the board

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `board.tooSmall` | 窗口太小，放不下棋盘。请把窗口调大一些。 | The window is too small to fit the board. Please make it larger. | line in the board's place | [interaction-design.md](interaction-design.md) § Layout shapes — the Mini Xiangqi 44-point and Xiangqi 34-point floors, and the refusal that keeps either board from being drawn below its own; `windows/MiniXiangqi.Play/Board/BoardSpace.cs` |

**It is not a failure screen and does not join that family.** Nothing went wrong, nothing was lost, and the reader can put it right with one drag of a window edge — so it takes no 无法 title, carries no diagnostic beneath it, and is one line where a failure screen is a title and a description. It says the fact and then the remedy, in that order, and stops.

**It is read on Windows**, where a window is resized against a navigation container whose own width changes with it: the accepted floor is derived so that the board survives every arrangement the platform chooses, and this line is the honest floor under the residue — an unusual display scale, a window frame wider than the app's arithmetic allowed for, a platform default that moves. iOS and iPadOS have no resize to reach it with, and whether the Mac's own window can is the Apple frontend's question; the row is here for it if the answer is yes.

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
| `piece.advisor` | 仕 / 士 | Advisor | accessibility label | same |
| `piece.elephant` | 相 / 象 | Elephant | accessibility label | same |
| `piece.chariot` | 俥 / 车 | Chariot | help text; accessibility label | same |
| `piece.horse` | 傌 / 马 | Horse | help text; accessibility label | same |
| `piece.cannon` | 炮 / 砲 | Cannon | help text; accessibility label | same |
| `piece.soldier` | 兵 / 卒 | Soldier | help text; accessibility label | same |

The Chinese cell of a piece row is a description of the two characters rather than a value: the characters are game content and never enter a string table. Its English half is a value like any other.

### Move list and application

| Key | 中文 | English | Surface | Source |
|---|---|---|---|---|
| `moveList.rowNumber` | `%lld.` | `%lld.` | move-list row number | `Play/MoveList.swift` — numerals and a full stop; no word is translated |
| `app.displayName` | Mini Xiangqi | Mini Xiangqi | application name | [product.md](product.md) § Product identity and distribution; `apple/MiniXiangqi.xcodeproj` — one name in both languages |

## Where the two languages deliberately do not match one to one

These are decisions, not oversights, and a mechanical one-to-one check will flag them.

- **Two Chinese result forms share one English form.** The notice titles 红方获胜 / 黑方获胜 / 和棋 and the shorter status-line forms 红方胜 / 黑方胜 / 和局 are two registers in Chinese — a sentence about the game and a line about the turn — and both take Red Wins / Black Wins / Draw in English. English has no equivalent register difference short enough for the status line, and inventing one would make the two surfaces disagree about the same result.
- **One Chinese string takes two English words.** 认输 is the control (`control.resign`, **Resign**) and the recorded reason (`reason.resignation`, **Resignation**). The Chinese is the same word acting as verb and as noun; English is not.
- **The claim's action and its state stay apart in both languages.** 判和 is the control (**Claim Draw**); 可判和 is the state (**Draw Available**). Chinese already distinguishes them and English follows.
- **The accessibility representation switches with the language.** Chinese names a piece by the character on it — 帅, 炮 — because that is what the board shows and what the reader is learning. English names it by its piece name, never by the character, per the accepted piece-representation rule. So `b1 红 炮 已选择` is `b1 Red Cannon Selected` and not `b1 Red 炮 Selected`.
- **请 is mirrored, not dropped.** Where the Chinese says 请, the English says *Please* — in `status.saveFailed`, `alert.saveFailed.message`, and `alert.aiUnavailable.message`. The English is a translation of the Chinese and says neither more nor less than it does.

## Never translated

Game content is identical in every supported language. It is not copy, it carries no key, and it never enters the String Catalog.

- **The fourteen piece characters** — 帅 将 仕 士 相 象 俥 车 傌 马 炮 砲 兵 卒. Fixed in [interaction-design.md](interaction-design.md) § Piece representation: the pieces are Chinese characters, this is a teaching application, and the board presents the real characters rather than a translated substitute.
- **The notation direction and position tokens** — 进, 退, 平, and the leading 前, 中, 后 — and the numbered forms that replace them when four or more pieces of a type share a file: 一兵, 二兵, and so on. Fixed in [interaction-design.md](interaction-design.md) § User-visible notation, which also fixes that a piece is named in a move by its own side's character form.
- **The Chinese numerals in notation and in the file-numeral strip** — 一 二 三 四 五 六 七 八 九. Red writes every number in a move in Chinese numerals and Black in Arabic ones, and each game's numeral strips show the files it has. Fixed in [interaction-design.md](interaction-design.md) § User-visible notation.
- **Pictorial piece icons**, when that symbol set is selected. They are game presentation and do not change with the interface language, per [interaction-design.md](interaction-design.md) § Piece symbols.

A reader using icon symbols still reads a character-based move list, because traditional notation names pieces by their characters.

## The localization process

1. **Both languages are complete before a string ships.** A String Catalog carries a `zh-Hans` and an `en` entry for every key in the table above. A key with one language filled in is an incomplete string, not a partially localized one.
2. **Keys are symbolic, never the source string.** Xcode's default is source-string-as-key; it is wrong here, because the source language is Chinese, a Chinese key is unreadable to an English reviewer, and a wording change in the normative Chinese would silently orphan its translation. The key is the join between this contract and the catalog, and it is what makes a copy change reviewable as a copy change.
3. **`developmentRegion` stays `en`.** Chinese normativity is a property of this contract, not of an Xcode setting.
4. **Every copy change is a contract change.** A new string, a reworded string, or a retired key is a pull request against this file, reviewed as a contract is reviewed. The catalog follows the contract; the contract never follows the catalog.
5. **Nothing machine-translated ships as accepted.** A translation carrying Xcode's Machine Translated state — XLIFF `state-qualifier` `leveraged-mt` — is a draft. Acceptance happens in this table.
6. **A composed string is a localized format string.** Separators differ between the languages — an ideographic space, an ideographic comma, the middot — and must never be hard-coded around a translated fragment.
7. **A test finds a control by identifier, never by label.** A label is copy and changes with the language; an identifier does not.
8. **Per internal build, two mechanical runs and one human pass.** Run the application under the Double-Length and Bounded String pseudolanguages and confirm nothing truncates and nothing intersects the board block; then run the accepted smoke flows in both Simplified Chinese and English, switching with the system's per-app language setting.
9. **Native-speaker review is TestFlight internal testing.** Apple's own recommendation for reviewing localized copy is to put the build in front of native speakers, and internal distribution already does exactly that. There is no separate reviewer role and no XLIFF round trip: with one reviewer per language, a hand-off buys ceremony rather than scrutiny.
10. **A mechanical agreement check runs in CI**: one check that this table and the String Catalog agree in both languages — the same key set, the same values, and no user-facing key in the catalog that is absent here. It needs no second human, and it is the evidence [testing.md](testing.md) asks for.
