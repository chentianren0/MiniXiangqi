// The persistent Settings preferences: the keys, what an absent one means, and
// the file they live in.
//
// The Settings screen now writes them — it is `Settings/SettingsScreen.cs`, and
// it writes through the same store every consumer reads through, so that the
// keys have exactly one definition on this platform.
//
// The keys and their vocabularies are the interface between the screen that
// writes a preference and the surface that reads one, exactly as
// apple/MiniXiangqi/Settings/Preferences.swift says in as many words. This file
// carries the rows of that table this frontend has a surface for:
//
// | Key | Type | Absent means |
// |---|---|---|
// | `defaults.firstMover` | `human-first` \| `ai-first` \| `random` | `human-first` |
// | `defaults.aiLevel` | `fast` \| `standard` \| `deep` | `standard` |
// | `sound.enabled` | Bool | on |
// | `deleteConfirmation.enabled` | Bool | on |
//
// **The three rows that are not here are recorded scope rather than omissions**,
// per issue #80's owner-decided Windows trim. `notation.style` has no surface
// because the Windows MVP's move record is the core's own canonical coordinate
// text in both languages, so there is nothing for the preference to choose
// between; `pieces.symbols` has none because only the 汉字 set is drawn, and a
// preference with one option is not a preference — which is the rule
// docs/product.md § Product navigation already applies to the piece style;
// `haptics.enabled` has none because the platform offers no hardware to drive,
// and docs/interaction-design.md § Sound and haptics removes that row rather
// than greying it out. None of the three keys is written here, and none is read:
// a Windows launch leaves whatever an Apple launch stored under them exactly as
// it found it, which is what sharing a key vocabulary across frontends is worth.
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
// works.** A JSON object beside the store, read at the moment of use and never
// cached. The Apple frontend has `UserDefaults`; an unpackaged Win32 app has no
// equivalent it can reach without deciding the packaging question this
// repository has parked, so this reads a file and says so. The Settings pull
// request kept it rather than replacing it: it is the reader three surfaces
// already run against and the harness already proves, and a packaging build
// changing where preferences live is a change to one class rather than to a
// contract. What has *not* changed is the key or the vocabulary, because those
// are what the two frontends share.
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
/// A store the Settings screen can write to.
///
/// It is a second interface rather than two more members on
/// <see cref="IPreferenceStore"/> because writing is one screen's capability and
/// reading is every surface's: the pre-start page, the History destination and
/// the sound gate all take a reader and none of them has any business holding
/// something that can write. <see cref="NoPreferences"/> is the clearest case —
/// a store that holds nothing has no honest answer to <c>Write</c>, and it does
/// not have to invent one.
///
/// **A write can fail, and this interface does not report it.** Disk, quota and
/// permissions are all real, and the answer to a refused write is neither an
/// exception through a switch's event handler nor an alert with no accepted copy
/// behind it: it is that the screen goes on showing what is *stored*, which it
/// re-reads after every write. So a preference that could not be written is a
/// control that visibly did not move, which is the truth and needs no words.
/// </summary>
public interface IWritablePreferences : IPreferenceStore
{
    /// <summary>Stores one of a preference's accepted names.</summary>
    void Write(string key, string value);

    /// <summary>Stores a flag, as a flag — a JSON <c>true</c> or <c>false</c>.</summary>
    void Write(string key, bool value);
}

/// <summary>
/// The preferences file: <c>%LOCALAPPDATA%\MiniXiangqi\preferences.json</c>, a
/// flat object. Absent, unreadable, or malformed all read as "nothing is
/// stored" — a preference file can be edited by hand and is read by more than
/// one frontend, and the page still has to open.
/// </summary>
public sealed class FilePreferenceStore : IPreferenceStore, IWritablePreferences
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

    /// <inheritdoc />
    public void Write(string key, string value) => Store(key, writer => writer.WriteString(key, value));

    /// <inheritdoc />
    public void Write(string key, bool value) => Store(key, writer => writer.WriteBoolean(key, value));

    /// <summary>
    /// One preference stored, and everything else in the file left exactly as it
    /// was.
    ///
    /// **It is a read-modify-write rather than an overwrite**, because this file
    /// is not this screen's private state. It already holds keys no surface here
    /// reads — the notation, the piece symbols and the haptics switch belong to
    /// the Apple frontend, and a Windows machine sharing a roamed profile or an
    /// exported file would have them — and a screen that rewrote the object from
    /// the four rows it draws would silently delete a preference somebody set on
    /// another machine. A key the reader could not parse is the one thing not
    /// carried across: an unreadable file is replaced by a well-formed one
    /// holding what was just chosen, which is strictly better than a screen whose
    /// switches do nothing until somebody deletes a file by hand.
    ///
    /// **It lands atomically.** The new object is written to a sibling temporary
    /// file and moved over the old one, so a process that dies mid-write leaves
    /// the previous preferences rather than a truncated object every later read
    /// would answer "nothing is stored" to. <c>File.Move</c> with
    /// <c>overwrite</c> is <c>MoveFileEx</c> with <c>MOVEFILE_REPLACE_EXISTING</c>
    /// on this platform, which is the replacement the file system performs
    /// itself.
    ///
    /// **A failure is swallowed**, for the reason <see cref="IWritablePreferences"/>
    /// gives: the screen re-reads what is stored, so a write that did not happen
    /// is a control that visibly did not move.
    /// </summary>
    private void Store(string key, Action<Utf8JsonWriter> put)
    {
        string temporary = _path + ".new";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path) ?? ".");

            byte[] existing = Read();
            using (FileStream file = File.Create(temporary))
            using (Utf8JsonWriter writer = new(file, new JsonWriterOptions { Indented = true }))
            {
                writer.WriteStartObject();
                put(writer);
                if (existing.Length > 0)
                {
                    using JsonDocument document = JsonDocument.Parse(existing);
                    if (document.RootElement.ValueKind == JsonValueKind.Object)
                    {
                        foreach (JsonProperty property in document.RootElement.EnumerateObject())
                        {
                            if (!string.Equals(property.Name, key, StringComparison.Ordinal))
                            {
                                property.WriteTo(writer);
                            }
                        }
                    }
                }

                writer.WriteEndObject();
            }

            File.Move(temporary, _path, overwrite: true);
        }
        catch (Exception failure) when (
            failure is IOException or UnauthorizedAccessException or JsonException
                or NotSupportedException or ArgumentException)
        {
            try
            {
                File.Delete(temporary);
            }
            catch (Exception cleanup) when (
                cleanup is IOException or UnauthorizedAccessException)
            {
                // A scratch file beside a preferences file. Failing to remove it
                // changes nothing about what is stored, and there is nobody to
                // tell about a preference that did not take that the screen will
                // not say by re-reading.
            }
        }
    }

    /// <summary>
    /// The file's current bytes, or nothing at all where there is no readable
    /// file. Read whole rather than streamed because the same handle cannot be
    /// held open across the move that replaces it.
    /// </summary>
    private byte[] Read()
    {
        try
        {
            return File.ReadAllBytes(_path);
        }
        catch (Exception failure) when (
            failure is IOException or UnauthorizedAccessException)
        {
            return [];
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

    /// <summary>Whether the board is heard.</summary>
    public const string SoundKey = "sound.enabled";

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
    /// 声音, the gate in front of the board's four voices. On by default and on
    /// again wherever the stored value cannot be read as a flag, which is the
    /// same direction 删除前确认 takes and for a milder version of the same
    /// reason: sound is never the only channel for anything, so neither answer is
    /// dangerous, and the accepted default is what an unreadable preference
    /// means everywhere else in this table.
    ///
    /// Read at the moment the sound would fire and never cached, so the switch
    /// takes effect on the next landing rather than on the next run.
    /// </summary>
    public static bool Sound(IPreferenceStore store) => store.ReadFlag(SoundKey) ?? true;

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
