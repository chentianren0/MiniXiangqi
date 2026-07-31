// The pre-start controls' values, and the vocabulary they speak.
//
// docs/interaction-design.md, "Starting and configuring a game": the pre-start
// controls "are initialized afresh from the persistent Settings defaults
// whenever the page is entered", and "their values exist only as an in-memory
// draft. They are not autosaved, do not change the Settings defaults, and are
// discarded as soon as the user leaves the page."
//
// The three names below are one vocabulary in four places — the Settings
// default, this draft, the frozen configuration the core stores, and the
// archive — so they are spelled once, here, in docs/game-data.md's serialized
// form. A frontend that invented a fourth spelling would be a frontend whose
// preferences the other one could not read.

using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

/// <summary>The two accepted ways to play.</summary>
public enum PlayMode
{
    HumanVersusAi,
    FreePlay,
}

/// <summary>**我先手**, **AI 先手**, **随机**.</summary>
public enum FirstMoverChoice
{
    HumanFirst,
    AiFirst,
    Random,
}

/// <summary>**快速**, **标准**, **深思** — the three accepted thinking times.</summary>
public enum AiLevel
{
    Fast,
    Standard,
    Deep,
}

/// <summary>
/// The translation between this frontend's words and the core's constants.
/// One direction each, in one place, so that a level and its <c>movetime</c>
/// cannot drift apart — the search request cross-checks them and a disagreement
/// would be a move thought for a time the archive does not record.
/// </summary>
public static class PlayVocabulary
{
    public static int Code(this PlayMode mode) => mode == PlayMode.FreePlay
        ? Mxq.MXQ_PLAY_MODE_FREE_PLAY
        : Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI;

    public static PlayMode Mode(int code) => code == Mxq.MXQ_PLAY_MODE_FREE_PLAY
        ? PlayMode.FreePlay
        : PlayMode.HumanVersusAi;

    public static int Code(this FirstMoverChoice choice) => choice switch
    {
        FirstMoverChoice.AiFirst => Mxq.MXQ_FIRST_MOVER_AI_FIRST,
        FirstMoverChoice.Random => Mxq.MXQ_FIRST_MOVER_RANDOM,
        _ => Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
    };

    public static int Code(this AiLevel level) => level switch
    {
        AiLevel.Fast => Mxq.MXQ_AI_LEVEL_FAST,
        AiLevel.Deep => Mxq.MXQ_AI_LEVEL_DEEP,
        _ => Mxq.MXQ_AI_LEVEL_STANDARD,
    };

    /// <summary>
    /// The exact <c>go movetime</c> the level identifies, from the core's own
    /// constants rather than from a number written here: 快速 1000 ms, 标准
    /// 3000 ms, 深思 5000 ms.
    /// </summary>
    public static uint MovetimeMs(this AiLevel level) => level switch
    {
        AiLevel.Fast => Mxq.MXQ_MOVETIME_FAST_MS,
        AiLevel.Deep => Mxq.MXQ_MOVETIME_DEEP_MS,
        _ => Mxq.MXQ_MOVETIME_STANDARD_MS,
    };

    /// <summary>The serialized name, which is what a preference stores.</summary>
    public static string Name(this FirstMoverChoice choice) => choice switch
    {
        FirstMoverChoice.AiFirst => "ai-first",
        FirstMoverChoice.Random => "random",
        _ => "human-first",
    };

    public static string Name(this AiLevel level) => level switch
    {
        AiLevel.Fast => "fast",
        AiLevel.Deep => "deep",
        _ => "standard",
    };

    /// <summary>A stored name, or null where it names nothing this build knows.</summary>
    public static FirstMoverChoice? FirstMover(string? name) => name switch
    {
        "human-first" => FirstMoverChoice.HumanFirst,
        "ai-first" => FirstMoverChoice.AiFirst,
        "random" => FirstMoverChoice.Random,
        _ => null,
    };

    public static AiLevel? Level(string? name) => name switch
    {
        "fast" => AiLevel.Fast,
        "standard" => AiLevel.Standard,
        "deep" => AiLevel.Deep,
        _ => null,
    };
}

/// <summary>
/// The pre-start controls' draft. Not autosaved, never written back to the
/// Settings defaults, and gone as soon as the player leaves the page.
/// </summary>
public readonly record struct SetupDraft(FirstMoverChoice FirstMover, AiLevel Level)
{
    /// <summary>
    /// Afresh from the persistent defaults, which is what every entry to the
    /// pre-start page gets.
    /// </summary>
    public static SetupDraft FromDefaults(IPreferenceStore store) => new(
        Preferences.DefaultFirstMover(store),
        Preferences.DefaultAiLevel(store));

    /// <summary>
    /// The human's side, once a **随机** choice is drawn. Called only inside a
    /// creation attempt that has already prepared successfully, and committed
    /// only by a successful create — so a retry draws again.
    /// </summary>
    public Side ResolveHumanSide() => FirstMover switch
    {
        FirstMoverChoice.HumanFirst => Side.Red,
        FirstMoverChoice.AiFirst => Side.Black,
        _ => System.Random.Shared.Next(2) == 0 ? Side.Red : Side.Black,
    };

    /// <summary>
    /// What the pre-start board previews. **随机** remains unresolved and
    /// previews Red at the bottom; only a successful creation can flip the
    /// board.
    /// </summary>
    public bool PreviewsHumanAsBlack => FirstMover == FirstMoverChoice.AiFirst;
}
