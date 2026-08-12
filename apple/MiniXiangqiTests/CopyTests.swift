// What the String Catalog answers, in each language it answers in.
//
// The catalog is the string of record: normative Simplified Chinese with an
// approved English beside it, the pair stored under one symbolic key. Most of
// what it holds is a plain string, and the running screen is what proves those
// arrived — PlayScreenUITests photographs both languages. What a screenshot cannot
// judge is a pattern: a format whose argument is a piece character in one
// language and nothing at all in the other, and a count whose noun inflects in
// one language and does not in the other. Those are checked here, against the
// catalog the application itself carries.

import Foundation
import Testing
@testable import MiniXiangqi

/// The bundle one language's strings compiled into. The unit suite is hosted
/// by the application, so the application's own resources are what is read.
private func bundle(_ language: String) throws -> Bundle {
    let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"),
                            "the application should carry \(language) strings")
    return try #require(Bundle(path: path))
}

/// A key's value, exactly as the catalog compiled it — which for a plural is
/// the pattern rather than a finished sentence.
private func value(_ key: String, in language: String) throws -> String {
    try bundle(language).localizedString(forKey: key, value: nil, table: nil)
}

@Suite("The copy the catalog carries, in each language it answers in")
@MainActor
struct CopyTests {

    @Test("Both languages are complete for every key the application reads")
    func everyKeyAnswersInBothLanguages() throws {
        // Not the whole catalog: it holds the surfaces still to be built
        // too, and a key with no screen behind it is not this suite's business.
        // These are the ones the application asks for today.
        let keys = [
            "about.title", "about.name", "about.version", "about.build",
            "about.license", "about.license.statement", "about.source",
            "alert.claimDraw.title", "alert.claimDraw.message",
            "alert.saveFailed.title", "alert.saveFailed.message",
            "alert.aiUnavailable.title", "alert.aiUnavailable.message",
            "alert.aiUnavailable.resumeMessage",
            "alert.gameNotStarted.title", "alert.gameNotStarted.message",
            "alert.hintUnavailable.title", "alert.hintUnavailable.message",
            "alert.newGame.title", "alert.newGame.metadataHeader",
            "alert.newGame.message",
            "alert.nearbyInvite.title", "alert.nearbyInvite.message",
            "alert.nearbyDeclined.title",
            "alert.resign.title", "alert.resign.message",
            "alert.deleteGame.title", "alert.deleteGame.message",
            "alert.deleteFailed.title", "alert.deleteFailed.message",
            "alert.importDuplicate.title", "alert.importDuplicate.message",
            "alert.importConflict.title", "alert.importConflict.message",
            "alert.importNewerVersion.title", "alert.importNewerVersion.message",
            "alert.importUnreadable.title", "alert.importUnreadable.message",
            "alert.importSaveFailed.title", "alert.importSaveFailed.message",
            "alert.importDamagedRecord.title", "alert.importDamagedRecord.message",
            "board.a11y.red", "board.a11y.black", "board.a11y.white",
            "board.a11y.empty",
            "board.a11y.selected", "board.a11y.legalMove", "board.a11y.capture",
            "board.a11y.inCheck", "board.a11y.suggested",
            "board.a11y.pending", "board.a11y.forbidden",
            "board.a11y.hint.announcement", "board.a11y.hint.point",
            "control.undo", "control.claimDraw", "control.offerDraw",
            "control.flipBoard", "control.hint",
            "control.newGame", "control.save", "control.saveAndNewGame",
            "control.keepPlaying", "control.endAsDraw",
            "control.cancel", "control.tryAgain", "control.later",
            "control.saveAndContinue",
            "control.ok", "control.view", "control.resign", "control.startGame",
            "control.accept", "control.decline",
            "control.delete", "control.pin", "control.unpin",
            "control.share", "control.import", "control.replay", "control.done",
            "failure.coreDidNotStart", "failure.gameDidNotStart",
            "failure.historyDidNotLoad",
            "history.section.pinned", "history.section.others",
            "history.empty.title", "history.empty.description",
            "metadata.join", "metadata.moveCount", "moveList.rowNumber",
            "metadata.youRed", "metadata.youBlack", "metadata.youWhite",
            "metadata.imported",
            "metadata.inProgress",
            "game.miniXiangqi", "game.xiangqi", "game.gomoku", "game.renju",
            "mode.humanVersusAI", "mode.freePlay", "mode.nearby",
            "nav.play", "nav.history", "nav.settings", "nav.resumeGame",
            "nearby.theyMoveFirst", "nearby.devices", "nearby.searching",
            "nearby.unnamedDevice",
            "nearby.invite", "nearby.waitingForAnswer",
            "nearby.pairing", "nearby.pairing.footer", "nearby.pairing.unavailable",
            "nearby.discoverable", "nearby.findDevice", "nearby.connecting",
            "nearby.refusal.declined", "nearby.refusal.busy",
            "nearby.refusal.unknownGame", "nearby.refusal.rulesMismatch",
            "nearby.refusal.unknownSession", "nearby.refusal.alreadyPlaying",
            "nearby.refusal.settling", "nearby.refusal.notNow",
            "nearby.theyOfferDraw", "nearby.theyAskUndo",
            "nearby.ended.title", "nearby.ended.disagreement", "nearby.ended.newGame",
            "settings.section.board",
            "settings.symbols.label", "settings.symbols.hanzi", "settings.symbols.icons",
            "settings.notation.label", "settings.notation.traditional",
            "settings.notation.wxf",
            "settings.sound.label", "settings.haptics.label",
            "settings.confirmDelete.label", "settings.confirmDelete.footer",
            "settings.confirmPlacement.label", "settings.confirmPlacement.footer",
            "settings.defaults.group", "settings.defaults.firstMover",
            "settings.defaults.aiLevel", "settings.defaults.footer",
            "setup.thisGame", "setup.firstMover", "setup.iMoveFirst",
            "setup.aiMovesFirst", "setup.random", "setup.aiLevel",
            "setup.level.fast", "setup.level.standard", "setup.level.deep",
            "setup.freePlayExplanation", "setup.freePlayExplanation.placement",
            "replay.progress", "replay.first", "replay.previous",
            "replay.next", "replay.last", "replay.autoplay", "replay.pause",
            "piece.general", "piece.advisor", "piece.elephant", "piece.chariot",
            "piece.horse", "piece.cannon", "piece.soldier",
            "reason.checkmate", "reason.stalemate", "reason.threefoldRepetition",
            "reason.perpetualCheck", "reason.perpetualChase",
            "reason.mutualPerpetualCheck", "reason.mutualPerpetualChase",
            "reason.fiftyMoveRule",
            "reason.resignation", "reason.endedEarly",
            "reason.agreedDraw", "reason.mutualResignation",
            "reason.fiveInARow", "reason.boardFull",
            "result.redWins", "result.blackWins", "result.whiteWins",
            "result.draw", "result.announcement",
            "result.recorded",
            "status.redToMove", "status.blackToMove", "status.whiteToMove",
            "status.check",
            "status.sideToMove.checked", "status.drawAvailable",
            "status.redWins", "status.blackWins", "status.whiteWins",
            "status.draw",
            "status.saveFailed",
            "status.controller.you", "status.controller.ai", "status.controller.peer",
            "status.aiThinking", "status.aiUnavailable", "status.hintThinking",
        ]
        for language in ["en", "zh-Hans"] {
            for key in keys {
                // A key with no entry answers with itself, which is the one
                // thing a value here can never legitimately be: every key in
                // the catalog is symbolic, and no accepted string is one.
                let answer = try value(key, in: language)
                #expect(answer != key, "\(key) has no \(language) value")
            }
        }
    }

    @Test("The local-network sentence is the catalog's, in both languages")
    func theBundleStringIsThere() throws {
        // The one accepted string that is not a String Catalog row: the system
        // reads it out of the bundle to explain its own permission alert with,
        // so it is localized in `InfoPlist.xcstrings` and compiled into each
        // language's `InfoPlist.strings` rather than into `Localizable`. A
        // catalog that failed to compile would leave the alert speaking the
        // development language to every reader, which nothing else here would
        // notice.
        let table = "InfoPlist"
        let key = "NSLocalNetworkUsageDescription"

        #expect(try bundle("zh-Hans").localizedString(forKey: key, value: nil, table: table)
                == "用于查找并连接附近对弈的对方设备。")
        #expect(try bundle("en").localizedString(forKey: key, value: nil, table: table)
                == "Used to find and connect to the other player's device for Nearby Play.")
    }

    @Test("The four game names are complete and distinct in both languages")
    func gameNamesAreAcceptedCopy() throws {
        #expect(try value("game.xiangqi", in: "zh-Hans") == "象棋")
        #expect(try value("game.xiangqi", in: "en") == "Xiangqi")
        #expect(try value("game.miniXiangqi", in: "zh-Hans") == "迷你象棋")
        #expect(try value("game.miniXiangqi", in: "en") == "Mini Xiangqi")
        #expect(try value("game.gomoku", in: "zh-Hans") == "五子棋")
        #expect(try value("game.gomoku", in: "en") == "Gomoku")
        #expect(try value("game.renju", in: "zh-Hans") == "连珠")
        #expect(try value("game.renju", in: "en") == "Renju")
        // Four names, four distinct words in each language: a section heading
        // that repeated another game's name would send a player to the wrong
        // board.
        let names = GameKind.allCases.map(\.localizedName)
        #expect(Set(names).count == GameKind.allCases.count)
    }

    /// What the placement games call their sides, in both languages.
    ///
    /// The mapping is the load-bearing part and the one a reader cannot check
    /// from the catalog alone: `Side.red` is the core's first mover, and on
    /// these boards the first mover is the *black* stone. A future change that
    /// carried the xiangqi words onto a gomoku board would leave a Go player
    /// reading 红方 about a black stone, which is what this pins.
    @Test("A placement game names its sides Black and White, first mover Black")
    func placementSideNamesFollowTheStones() throws {
        #expect(GameKind.gomoku15.sideToMoveText(.red) == String(localized: "status.blackToMove"))
        #expect(GameKind.gomoku15.sideToMoveText(.black) == String(localized: "status.whiteToMove"))
        #expect(GameKind.renju.sideName(.red) == String(localized: "board.a11y.black"))
        #expect(GameKind.renju.sideName(.black) == String(localized: "board.a11y.white"))
        #expect(GameKind.renju.youAreText(.red) == String(localized: "metadata.youBlack"))
        #expect(GameKind.renju.youAreText(.black) == String(localized: "metadata.youWhite"))
        #expect(GameKind.gomoku15.winsText(.red) == String(localized: "status.blackWins"))
        #expect(GameKind.gomoku15.resultText(.black) == String(localized: "result.whiteWins"))
        // And the xiangqi games are untouched by any of it.
        #expect(GameKind.xiangqi.sideToMoveText(.red) == String(localized: "status.redToMove"))
        #expect(try value("status.whiteToMove", in: "zh-Hans") == "轮到白方")
        #expect(try value("status.whiteToMove", in: "en") == "White to Move")
        #expect(try value("board.a11y.white", in: "zh-Hans") == "白")
    }

    @Test("A piece is named by its character in Chinese and by its name in English")
    func pieceNamesSwitchWithTheLanguage() throws {
        // The pairs the catalog carries. The Chinese half is the character
        // the disc carries, which never enters the catalog: it reaches the
        // label as the format's argument, which the English name ignores.
        let expected: [(PieceKind, Side, String, String)] = [
            (.general, .red, "帅", "General"),
            (.general, .black, "将", "General"),
            (.advisor, .red, "仕", "Advisor"),
            (.advisor, .black, "士", "Advisor"),
            (.elephant, .red, "相", "Elephant"),
            (.elephant, .black, "象", "Elephant"),
            (.chariot, .red, "俥", "Chariot"),
            (.chariot, .black, "车", "Chariot"),
            (.horse, .red, "傌", "Horse"),
            (.horse, .black, "马", "Horse"),
            (.cannon, .red, "炮", "Cannon"),
            (.cannon, .black, "砲", "Cannon"),
            (.soldier, .red, "兵", "Soldier"),
            (.soldier, .black, "卒", "Soldier"),
        ]
        for (kind, side, chinese, english) in expected {
            let key = "piece.\(String(describing: kind))"
            let character = kind.character(for: side)
            let inChinese = try value(key, in: "zh-Hans")
            let inEnglish = try value(key, in: "en")
            #expect(String(format: inChinese, character) == chinese)
            #expect(String(format: inEnglish, character) == english)
            // The character on the disc is the same either way. What the whole
            // label comes to in each language is asserted where the language
            // can be chosen, which is the UI suite.
            #expect(character == chinese)
        }
    }

    @Test("A move count inflects in English and does not in Chinese")
    func theMoveCountIsAPluralPattern() throws {
        // The one key installed ahead of the screen that will read it. The
        // save-and-continue metadata is still to be built; the accepted form
        // is plural variants rather than a literal with a number pushed into
        // it, and that has to be true before the screen arrives rather than
        // after. A plural pattern resolves against a locale, so the locale is
        // named rather than inherited.
        let english = try value("metadata.moveCount", in: "en")
        #expect(String(format: english, locale: Locale(identifier: "en"), 1) == "1 move")
        #expect(String(format: english, locale: Locale(identifier: "en"), 2) == "2 moves")
        #expect(String(format: english, locale: Locale(identifier: "en"), 42) == "42 moves")

        // The Chinese measure word is invariant, so one form does for all.
        let chinese = try value("metadata.moveCount", in: "zh-Hans")
        #expect(String(format: chinese, locale: Locale(identifier: "zh-Hans"), 1) == "1 步")
        #expect(String(format: chinese, locale: Locale(identifier: "zh-Hans"), 42) == "42 步")
    }

    @Test("The composed strings carry each language's own separator")
    func composedStringsAreFormatsRatherThanConcatenations() throws {
        // The three that exist today. Each was built by concatenation before,
        // and each has a separator that belongs to the language rather than to
        // the code around it.
        let checkedInChinese = try value("status.sideToMove.checked", in: "zh-Hans")
        let checkedInEnglish = try value("status.sideToMove.checked", in: "en")
        #expect(String(format: checkedInChinese, "轮到黑方", "将军") == "轮到黑方　将军")
        #expect(String(format: checkedInEnglish, "Black to Move", "Check") == "Black to Move Check")

        let announcementInChinese = try value("result.announcement", in: "zh-Hans")
        let announcementInEnglish = try value("result.announcement", in: "en")
        #expect(String(format: announcementInChinese, "红方获胜", "将死") == "红方获胜，将死")
        #expect(String(format: announcementInEnglish, "Red Wins", "Checkmate") == "Red Wins, Checkmate")

        // The metadata join's middot is the same in both, and it is a format
        // string all the same: what a language puts around a separator is that
        // language's to say, and this is the key that would carry it.
        for language in ["en", "zh-Hans"] {
            let join = try value("metadata.join", in: language)
            #expect(String(format: join, "a", "b") == "a · b")
        }

        // The hint's announcement, composed from the point vocabulary: the
        // side, the piece, and the two point names. Four arguments rather than
        // a joined string, because every separator in it belongs to a language
        // — English puts a colon and spaces between them, Chinese an
        // ideographic colon and no space at all between the side and the piece.
        let hintInChinese = try value("board.a11y.hint.announcement", in: "zh-Hans")
        let hintInEnglish = try value("board.a11y.hint.announcement", in: "en")
        #expect(String(format: hintInChinese, "红", "炮", "b1", "b5") == "提示：红炮 b1 到 b5")
        #expect(String(format: hintInEnglish, "Red", "Cannon", "b1", "b5")
                == "Suggestion: Red Cannon b1 to b5")
    }
}
