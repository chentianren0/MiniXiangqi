// The Settings destination: the preferences the app keeps, and nothing else.
//
// docs/product.md, "Product navigation": Settings is the third primary
// destination, it holds the persistent preferences, it stores no game data, and
// changing one never alters an active game. It holds no interface-language
// control either — the operating system owns the language, and on Windows that
// is the system's language preference list, which .NET already resolves
// `CurrentUICulture` from.
//
// **Three groups here where the Mac has four**, and every difference is issue
// #80's owner-decided Windows trim rather than a design change:
//
//   * 棋盘 is absent entirely. Its two rows are 棋子符号 and 记谱法. The move
//     record on this platform is the core's own canonical coordinate text in
//     both languages — the 记谱法 preference and the two proper renderings
//     arrive together post-MVP — so there is nothing for the notation row to
//     choose between; and only the 汉字 symbol set is drawn, so the symbols row
//     is a preference with one option, which docs/product.md § Product
//     navigation has already ruled is not a preference. A group whose every row
//     went is a group that goes.
//   * 触感 is absent from the feedback group, **not for the MVP** rather than
//     for want of an API — Windows' own touchpad haptics exist and
//     `Motion/Feedback.cs` names them, and they are experimental, 24H2-gated and
//     rarely carried, so a switch over them now would do nothing on nearly every
//     machine. That is the contract's "unavailable rather than silently
//     ineffective" all the same, so the row is **removed rather than greyed
//     out**, which is iOS's own answer. The group survives losing it exactly as
//     the contract says it does — it has no header to strand, and the two
//     switches were never conditioned on each other, so 声音 standing alone
//     means what it meant standing above 触感.
//   * The two remaining groups are unchanged: 人机对弈默认设置, headed and
//     footed, and 删除前确认, footed.
//
// **The two-footer rule survives intact, and that is not a coincidence.** "There
// are two footers on the screen, and only two" — `settings.defaults.footer` and
// `settings.confirmDelete.footer` — and both of the groups they belong to are
// among the three that ship. Nothing here needed a third footer to explain an
// absence, because an absent row explains itself by not being there.
//
// **This screen is silent.** Sound is an event of the board, per
// docs/interaction-design.md § Sound and haptics, and a screen that clicked back
// at every switch would be the app talking about itself. There is no `Feedback`
// on this type at all, which is how that is enforced rather than remembered.
//
// **Every value is read from the store, every time it is asked for.** Nothing
// below caches: the properties are the stored preferences, so a control shows
// what *is* stored rather than what was last asked for. Two things fall out of
// that and both are wanted. A write the file system refused leaves the control
// where it was, which is the truth and needs no alert; and a preference changed
// underneath the screen — by hand, or by an Apple frontend over a shared profile
// — is picked up on the next refresh without a relaunch, which is the same
// "read at the moment of use" rule the sound gate and the deletion gate run
// under.
//
// **This is a deliberate divergence from the Mac**, which mirrors each value
// into `@State` and therefore shows what was *asked for*. That difference is
// confined to a failure mode the two platforms do not share equally: a
// `UserDefaults` write barely has one, while a file write has disk, quota and
// permissions behind it. `Changed` is raised whether or not the write landed,
// and that unconditional raise is the whole of the snap-back — it is what
// redraws the control to the stored value. Announcing only on success would
// leave a switch showing something nobody stored, silently, which is why the
// harness drives a refused write rather than describing one.

namespace MiniXiangqi.Play;

/// <summary>
/// The Settings destination, minus the window. The window turns this into XAML
/// and turns XAML's events back into calls on it, and holds nothing else — the
/// same split the Play and History destinations have, for the same reason: a
/// WinUI 3 process cannot be launched over SSH, so a screen that lived in the
/// window could be exercised on no machine this project owns.
/// </summary>
public sealed class SettingsScreen
{
    private readonly IWritablePreferences _preferences;

    public SettingsScreen(IWritablePreferences preferences) => _preferences = preferences;

    /// <summary>Raised whenever a preference was written.</summary>
    public event Action? Changed;

    /// <summary>
    /// **默认先后手** — which side a new human-versus-AI game opens on. It
    /// initializes the next pre-start page's draft and reaches no game that
    /// exists, which is what the group's footer says out loud.
    /// </summary>
    public FirstMoverChoice DefaultFirstMover => Preferences.DefaultFirstMover(_preferences);

    /// <summary>**默认 AI 等级** — how long that game's opponent thinks.</summary>
    public AiLevel DefaultAiLevel => Preferences.DefaultAiLevel(_preferences);

    /// <summary>**声音** — whether the board is heard.</summary>
    public bool Sound => Preferences.Sound(_preferences);

    /// <summary>**删除前确认** — whether deleting a History record asks first.</summary>
    public bool ConfirmsDeletion => Preferences.ConfirmsDeletion(_preferences);

    public void ChooseDefaultFirstMover(FirstMoverChoice choice)
    {
        if (choice != DefaultFirstMover)
        {
            Write(Preferences.DefaultFirstMoverKey, choice.Name());
        }
    }

    public void ChooseDefaultAiLevel(AiLevel level)
    {
        if (level != DefaultAiLevel)
        {
            Write(Preferences.DefaultAiLevelKey, level.Name());
        }
    }

    public void SetSound(bool on)
    {
        if (on != Sound)
        {
            Write(Preferences.SoundKey, on);
        }
    }

    public void SetDeleteConfirmation(bool on)
    {
        if (on != ConfirmsDeletion)
        {
            Write(Preferences.DeleteConfirmationKey, on);
        }
    }

    /// <summary>
    /// The written form is the *name*, never an index: an index is a position in
    /// a list a later design may reorder and a name is not, and these three names
    /// are docs/game-data.md's serialized vocabulary — the preference, the frozen
    /// configuration and the archive all say the same word.
    ///
    /// A preference already holding the chosen value is not written again, above.
    /// That is not an optimisation over a cheap write: a control that reports the
    /// value it was just *given* is what a XAML selector does when a refresh sets
    /// it, and a screen that wrote on every such report would rewrite the file
    /// every time it drew.
    ///
    /// **`Changed` is raised whether or not the write landed, and that is
    /// load-bearing rather than lax.** A refused write is answered by the control
    /// snapping back to the stored value, and this raise is the only thing that
    /// redraws it — the store swallowed the failure and has nothing to report.
    /// Announcing only on success would leave a switch showing a value nobody
    /// stored, and nothing else in the app would notice.
    /// </summary>
    private void Write(string key, string value)
    {
        _preferences.Write(key, value);
        Changed?.Invoke();
    }

    private void Write(string key, bool value)
    {
        _preferences.Write(key, value);
        Changed?.Invoke();
    }
}
