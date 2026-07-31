// The persistent Settings defaults, read where the pre-start page needs them.
//
// **This pull request reads them and writes none of them.** The Settings screen
// is the next rung of the ladder and it owns writing; what is here is the two
// values docs/interaction-design.md § Starting and configuring a game says the
// pre-start controls are "initialized afresh from the persistent Settings
// defaults whenever the page is entered", read from the keys the Apple frontend
// already stores them under, with the accepted fallbacks for absence.
//
// The keys and their vocabularies are the interface between the screen that
// writes a preference and the surface that reads one, exactly as
// apple/MiniXiangqi/Settings/Preferences.swift says in as many words. This file
// carries the same two rows of that table:
//
// | Key | Type | Absent means |
// |---|---|---|
// | `defaults.firstMover` | `human-first` \| `ai-first` \| `random` | `human-first` |
// | `defaults.aiLevel` | `fast` \| `standard` \| `deep` | `standard` |
// | `deleteConfirmation.enabled` | Bool | on |
//
// The two choice names are docs/game-data.md's serialized vocabulary, so the
// preference, the frozen configuration and the archive all say the same words —
// and so that a preference written by one frontend reads correctly in the other,
// which is the whole reason the key rather than the storage is the contract.
//
// **删除前确认 joined them with the History destination**, which is the surface
// that reads it: it gates a permanent deletion, and docs/game-data.md's Settings
// placement is explicit that the core never reads a preference and that this one
// in particular "gates a permanent deletion but does not perform it". Its absent
// value is on, and a value this reader cannot make sense of reads as on too —
// **false is the dangerous answer here**, because on this key it deletes a game
// without asking, so anything short of an unambiguous no is treated as a yes.
//
// **Where they are kept on Windows is deliberately the smallest answer that
// works.** A JSON file of string values beside the store, read at the moment of
// use and never cached. The Apple frontend has `UserDefaults`; an unpackaged
// Win32 app has no equivalent it can reach without deciding the packaging
// question this repository has parked, so this reads a file and says so. The
// Settings pull request may keep it or replace it; what it may not do is change
// the key or the vocabulary, because those are what the two frontends share.
//
// Every value is read at the moment of use rather than cached at launch, which
// is the rule the Apple side states and the reason a switch takes effect at the
// next event rather than at the next run.

using System.Text.Json;

namespace MiniXiangqi.Play;

/// <summary>Where a stored preference is read from.</summary>
public interface IPreferenceStore
{
    /// <summary>
    /// The value stored under <paramref name="key"/>, or null where nothing is
    /// stored — which is the state of every first launch, and which every
    /// caller answers with the accepted default rather than with a failure.
    /// </summary>
    string? Read(string key);

    /// <summary>
    /// The flag stored under <paramref name="key"/>, or null where nothing
    /// recognisable is stored.
    ///
    /// A flag is a second read rather than a spelling of the first because a
    /// preferences file can be written by a Settings screen and edited by hand,
    /// and a JSON <c>true</c> and the string <c>"true"</c> are both honest ways
    /// to have written one. What is not a flag at all — a number, an object, a
    /// word neither language of this table knows — reads as absent, and the
    /// caller supplies the accepted default.
    /// </summary>
    bool? ReadFlag(string key) => Preferences.Flag(Read(key));
}

/// <summary>
/// The preferences file: <c>%LOCALAPPDATA%\MiniXiangqi\preferences.json</c>, a
/// flat object of string values. Absent, unreadable, or malformed all read as
/// "nothing is stored" — a preference file can be edited by hand and is read by
/// more than one frontend, and the page still has to open.
/// </summary>
public sealed class FilePreferenceStore : IPreferenceStore
{
    private readonly string _path;

    public FilePreferenceStore()
        : this(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MiniXiangqi",
            "preferences.json"))
    {
    }

    public FilePreferenceStore(string path)
    {
        _path = path;
    }

    public string? Read(string key) => Value(key) is { ValueKind: JsonValueKind.String } value
        ? value.GetString()
        : null;

    /// <summary>
    /// A JSON <c>true</c> or <c>false</c> first, and the string spellings of one
    /// after that — which is what the interface's own default does with whatever
    /// <see cref="Read"/> returned.
    /// </summary>
    public bool? ReadFlag(string key) => Value(key) switch
    {
        { ValueKind: JsonValueKind.True } => true,
        { ValueKind: JsonValueKind.False } => false,
        { ValueKind: JsonValueKind.String } text => Preferences.Flag(text.GetString()),
        _ => null,
    };

    private JsonElement? Value(string key)
    {
        try
        {
            using FileStream file = File.OpenRead(_path);
            using JsonDocument document = JsonDocument.Parse(file);
            return document.RootElement.ValueKind == JsonValueKind.Object
                && document.RootElement.TryGetProperty(key, out JsonElement value)
                ? value.Clone()
                : null;
        }
        catch (Exception failure) when (
            failure is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }
}

/// <summary>A store that holds nothing: every key is absent.</summary>
public sealed class NoPreferences : IPreferenceStore
{
    public static readonly NoPreferences Instance = new();

    public string? Read(string key) => null;
}

public static class Preferences
{
    /// <summary>Which side a new human-versus-AI game opens on.</summary>
    public const string DefaultFirstMoverKey = "defaults.firstMover";

    /// <summary>How long a new human-versus-AI game's opponent thinks.</summary>
    public const string DefaultAiLevelKey = "defaults.aiLevel";

    /// <summary>Whether deleting a History record asks first.</summary>
    public const string DeleteConfirmationKey = "deleteConfirmation.enabled";

    /// <summary>
    /// The string spellings of a flag a hand-edited or foreign-written
    /// preferences file may hold. Anything else is not a flag, and the caller's
    /// accepted default answers instead.
    /// </summary>
    public static bool? Flag(string? text) => text?.ToLowerInvariant() switch
    {
        "1" or "yes" or "true" or "on" => true,
        "0" or "no" or "false" or "off" => false,
        _ => null,
    };

    /// <summary>
    /// 删除前确认, which is enabled by default and enabled again wherever the
    /// stored value cannot be read as a flag. Read at the moment of use, like
    /// every other preference here, so a switch takes effect at the next
    /// deletion rather than at the next run.
    /// </summary>
    public static bool ConfirmsDeletion(IPreferenceStore store) =>
        store.ReadFlag(DeleteConfirmationKey) ?? true;

    /// <summary>
    /// 我先手 on a new installation. A stored name nothing recognises reads as
    /// the accepted default too, for the reason the file store gives.
    /// </summary>
    public static FirstMoverChoice DefaultFirstMover(IPreferenceStore store) =>
        PlayVocabulary.FirstMover(store.Read(DefaultFirstMoverKey)) ?? FirstMoverChoice.HumanFirst;

    /// <summary>标准 on a new installation, per the accepted profiles.</summary>
    public static AiLevel DefaultAiLevel(IPreferenceStore store) =>
        PlayVocabulary.Level(store.Read(DefaultAiLevelKey)) ?? AiLevel.Standard;
}
