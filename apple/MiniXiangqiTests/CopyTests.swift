// What the String Catalog answers, in each language it answers in.
//
// docs/copy.md is the register: normative Simplified Chinese with an approved
// English beside it, the pair stored under one symbolic key. Most of what it
// holds is a plain string, and the running screen is what proves those arrived
// — PlayScreenUITests photographs both languages. What a screenshot cannot
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

@Suite("The copy register, as the catalog answers it")
@MainActor
struct CopyTests {

    @Test("Both languages are complete for every key the application reads")
    func everyKeyAnswersInBothLanguages() throws {
        // Not the whole register: it holds the surfaces still to be built too,
        // and a key with no screen behind it is not this suite's business.
        // These are the ones the application asks for today.
        let keys = [
            "alert.claimDraw.title", "alert.claimDraw.message",
            "alert.saveFailed.title", "alert.saveFailed.message",
            "alert.aiUnavailable.title", "alert.aiUnavailable.message",
            "alert.aiUnavailable.resumeMessage",
            "alert.gameNotStarted.title", "alert.gameNotStarted.message",
            "alert.newGame.title", "alert.newGame.metadataHeader",
            "alert.newGame.message",
            "alert.resign.title", "alert.resign.message",
            "alert.deleteGame.title", "alert.deleteGame.message",
            "alert.deleteFailed.title", "alert.deleteFailed.message",
            "alert.importDuplicate.title", "alert.importDuplicate.message",
            "alert.importConflict.title", "alert.importConflict.message",
            "alert.importNewerVersion.title", "alert.importNewerVersion.message",
            "alert.importUnreadable.title", "alert.importUnreadable.message",
            "alert.importSaveFailed.title", "alert.importSaveFailed.message",
            "alert.importDamagedRecord.title", "alert.importDamagedRecord.message",
            "board.a11y.red", "board.a11y.black", "board.a11y.empty",
            "board.a11y.selected", "board.a11y.legalMove", "board.a11y.capture",
            "board.a11y.inCheck",
            "control.undo", "control.claimDraw", "control.flipBoard",
            "control.newGame", "control.save", "control.saveAndNewGame",
            "control.keepPlaying", "control.endAsDraw",
            "control.cancel", "control.tryAgain", "control.later",
            "control.saveAndContinue",
            "control.ok", "control.view", "control.resign", "control.startGame",
            "control.delete", "control.pin", "control.unpin",
            "control.share", "control.import", "control.replay", "control.done",
            "failure.coreDidNotStart", "failure.gameDidNotStart",
            "failure.historyDidNotLoad",
            "history.section.pinned", "history.section.others",
            "history.empty.title", "history.empty.description",
            "metadata.join", "metadata.moveCount", "moveList.rowNumber",
            "metadata.youRed", "metadata.youBlack", "metadata.imported",
            "metadata.inProgress",
            "mode.humanVersusAI", "mode.freePlay",
            "nav.play", "nav.history", "nav.settings", "nav.resumeGame",
            "settings.section.board",
            "settings.symbols.label", "settings.symbols.hanzi", "settings.symbols.icons",
            "settings.notation.label", "settings.notation.traditional",
            "settings.notation.wxf",
            "settings.sound.label", "settings.haptics.label",
            "settings.confirmDelete.label", "settings.confirmDelete.footer",
            "settings.defaults.group", "settings.defaults.firstMover",
            "settings.defaults.aiLevel", "settings.defaults.footer",
            "setup.thisGame", "setup.firstMover", "setup.iMoveFirst",
            "setup.aiMovesFirst", "setup.random", "setup.aiLevel",
            "setup.level.fast", "setup.level.standard", "setup.level.deep",
            "setup.freePlayExplanation",
            "replay.progress", "replay.first", "replay.previous",
            "replay.next", "replay.last", "replay.autoplay", "replay.pause",
            "piece.general", "piece.chariot", "piece.horse", "piece.cannon", "piece.soldier",
            "reason.checkmate", "reason.stalemate", "reason.threefoldRepetition",
            "reason.perpetualCheck", "reason.perpetualChase",
            "reason.mutualPerpetualCheck", "reason.mutualPerpetualChase",
            "reason.resignation", "reason.endedEarly",
            "result.redWins", "result.blackWins", "result.draw", "result.announcement",
            "result.recorded",
            "status.redToMove", "status.blackToMove", "status.check",
            "status.sideToMove.checked", "status.drawAvailable",
            "status.redWins", "status.blackWins", "status.draw",
            "status.saveFailed",
            "status.controller.you", "status.controller.ai",
            "status.aiThinking", "status.aiUnavailable",
        ]
        for language in ["en", "zh-Hans"] {
            for key in keys {
                // A key with no entry answers with itself, which is the one
                // thing a value here can never legitimately be: every key in
                // the register is symbolic, and no accepted string is one.
                let answer = try value(key, in: language)
                #expect(answer != key, "\(key) has no \(language) value")
            }
        }
    }

    @Test("A piece is named by its character in Chinese and by its name in English")
    func pieceNamesSwitchWithTheLanguage() throws {
        // The pairs the register accepts. The Chinese half is the character
        // the disc carries, which never enters the catalog: it reaches the
        // label as the format's argument, which the English name ignores.
        let expected: [(PieceKind, Side, String, String)] = [
            (.general, .red, "帅", "General"),
            (.general, .black, "将", "General"),
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
        // save-and-continue metadata is still to be built; docs/copy.md asks
        // that this be authored as plural variants rather than as a literal
        // with a number pushed into it, and that has to be true before the
        // screen arrives rather than after. A plural pattern resolves against
        // a locale, so the locale is named rather than inherited.
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
    }
}
