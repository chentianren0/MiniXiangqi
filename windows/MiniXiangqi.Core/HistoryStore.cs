// The library store's History surface: the list, the record actions, and the two
// interchange calls.
//
// docs/core-interface.md, "Library store": the reads are `mxq_store_history_count`
// and `mxq_store_history_page`, the record actions are `_get`, `_open`,
// `_set_pinned` and `_delete`, and interchange is `mxq_store_export` and
// `mxq_store_import`. Nothing here decides anything: the order is the core's, the
// classification is the core's, and duplicate and conflict detection is the
// core's. What this file owns is the shape of the call — the buffer protocol, the
// blob's lifetime, and the struct_size rules, each of which the interface spells
// differently here than in the calls the play screen makes.
//
// Three of those differences are worth stating, because each is a way to get this
// wrong that compiles:
//
//   * **The page's buffer rule is not the legal-move set's.** There an undersized
//     buffer is a routine way to ask for the count; here the caller named the page
//     size itself, so a `cap` below `limit` is a caller bug —
//     MXQ_ERR_ARG_BUFFER_TOO_SMALL with `required_size` set to `limit`, and
//     nothing written. The two numbers are the same by construction below.
//   * **A page element's `struct_size` is stamped by the core, not read.** So the
//     buffer is handed over zeroed. The single out-summary of
//     `mxq_store_history_get` and `mxq_store_import` is the opposite: it is a
//     caller-declared struct and carries the caller's size.
//   * **`mxq_blob_bytes` is the one pointer into core memory the interface hands
//     out**, valid until `mxq_blob_release`. The bytes are copied before it goes.

using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Core;

public sealed unsafe partial class MiniXiangqiCore
{
    /// <summary>
    /// How many records one page asks for.
    ///
    /// The same 200 the Apple frontend uses, and for the same reason: the
    /// interface deliberately has no page-size constant — "a constant here would
    /// be a second authority over a number the interface already makes the caller
    /// name" — so each frontend names one, and a library larger than one page is
    /// read by paging rather than by growing the number.
    /// </summary>
    public const int HistoryPageSize = 200;

    /// <summary>
    /// How many History records there are, and the library revision that count
    /// was true at.
    ///
    /// The revision is the staleness check the MVP has instead of a notification
    /// mechanism: a caller that holds a list re-reads this and compares.
    /// </summary>
    public (uint Records, ulong Revision) HistoryCount()
    {
        uint count;
        ulong revision;
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_history_count(Live, &count, &revision, &err),
            in err,
            nameof(Mxq.mxq_store_history_count));
        return (count, revision);
    }

    /// <summary>
    /// One page of History, in the accepted order — pinned first, newest within
    /// each group, <c>record_id</c> descending as the tie-break. **That order is
    /// the core's and is never re-sorted here**; the two sections the destination
    /// draws are the pinned prefix of what this returned and the rest of it.
    /// </summary>
    public HistoryPage HistoryPageAt(uint offset, uint limit)
    {
        if (limit == 0)
        {
            return new HistoryPage([], HistoryCount().Revision);
        }

        // Sized exactly to the limit. The caller chose the page size, so a buffer
        // smaller than it is this code's bug rather than a way to ask for a
        // count, and the core says so with MXQ_ERR_ARG_BUFFER_TOO_SMALL.
        MxqRecordSummary[] page = new MxqRecordSummary[limit];
        nuint written;
        ulong revision;
        fixed (MxqRecordSummary* buffer = page)
        {
            MxqError err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_store_history_page(Live, offset, limit, buffer, limit, &written, &revision, &err),
                in err,
                nameof(Mxq.mxq_store_history_page));
        }

        RecordSummary[] records = new RecordSummary[(int)written];
        for (int index = 0; index < records.Length; index++)
        {
            records[index] = Describe(page[index]);
        }

        return new HistoryPage(records, revision);
    }

    /// <summary>
    /// The whole of History, paged until a page comes back short, or **null**
    /// where the library would not hold still long enough to be read.
    ///
    /// The calls that make up a read of it — the count and each page — are
    /// separate transactions, so the revision each answered at is compared: a
    /// library that changed underneath is read again rather than presented as a
    /// list half of which is stale.
    ///
    /// **The race is real, and a first version of this comment said it was not.**
    /// It claimed nothing but the calling thread commits to the store, which is
    /// false of this very frontend: import, export and
    /// <c>mxq_store_archive_and_clear</c> are outside the main-thread exception
    /// by contract and run on pool threads, and any of them can commit between
    /// two of the reads below. The retry is bounded all the same, because a read
    /// that keeps losing is not a read that will win by being repeated — but
    /// exhausting the bound is a **failure to read the library**, not a shorter
    /// library. Returning the accumulated records there would publish a list that
    /// is missing whatever moved, possibly all of it, as though it were what the
    /// store holds; a caller that gets null says the library could not be read,
    /// which is exactly what happened.
    /// </summary>
    public HistoryPage? AllHistory()
    {
        for (int attempt = 0; attempt < ReadAttempts; attempt++)
        {
            ulong opening = HistoryCount().Revision;
            List<RecordSummary> records = [];
            bool stale = false;

            for (uint offset = 0; ; offset += HistoryPageSize)
            {
                HistoryPage page = HistoryPageAt(offset, HistoryPageSize);
                if (page.Revision != opening)
                {
                    stale = true;
                    break;
                }

                records.AddRange(page.Records);
                if (page.Records.Count < HistoryPageSize)
                {
                    break;
                }
            }

            if (!stale)
            {
                return new HistoryPage(records, opening);
            }
        }

        return null;
    }

    /// <summary>
    /// How many times a read of the whole library will start over before it
    /// reports that it could not be made. Three, because the writers it is
    /// racing are this process's own and are user-initiated: one import or export
    /// can land inside a read, three in a row cannot.
    /// </summary>
    private const int ReadAttempts = 3;

    /// <summary>
    /// Open a History record for replay: a **detached read-only session** whose
    /// queries all answer and whose derived affordances all read 0.
    ///
    /// docs/core-interface.md names this as the one History call whose cost is
    /// not bounded by the per-move commit's argument — it decodes an archive and
    /// replays every ply, so it rises with the game's own length.
    /// </summary>
    public GameSession OpenHistoryRecord(ulong recordId)
    {
        MxqGame* replay;
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_history_open(Live, recordId, &replay, &err),
            in err,
            nameof(Mxq.mxq_store_history_open));
        return new GameSession(replay);
    }

    /// <summary>
    /// Pin or unpin. Local library organization only: it changes no game content,
    /// and it is not in the archive.
    /// </summary>
    public void SetHistoryPinned(ulong recordId, bool pinned)
    {
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_history_set_pinned(Live, recordId, pinned ? (byte)1 : (byte)0, &err),
            in err,
            nameof(Mxq.mxq_store_history_set_pinned));
    }

    /// <summary>
    /// Delete a History record, permanently. There is no soft delete, no
    /// Recently Deleted and no Undo; a failed deletion leaves the record intact.
    /// </summary>
    public void DeleteHistoryRecord(ulong recordId)
    {
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_history_delete(Live, recordId, &err),
            in err,
            nameof(Mxq.mxq_store_history_delete));
    }

    /// <summary>
    /// One record's archive bytes: the canonical document the store holds, with a
    /// fresh export event stamped into its <c>origin</c>.
    ///
    /// The blob is the one pointer into core memory this interface hands out, and
    /// it is valid until the release below — so the bytes are copied before it
    /// goes.
    /// </summary>
    public byte[] ExportRecord(ulong recordId)
    {
        MxqBlob* blob = null;
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_store_export(Live, recordId, &blob, &err),
            in err,
            nameof(Mxq.mxq_store_export));

        try
        {
            if (blob is null)
            {
                throw new MxqException(
                    nameof(Mxq.mxq_store_export),
                    Mxq.MXQ_ERR_INTERNAL_INVARIANT,
                    MxqCall.StatusName(Mxq.MXQ_ERR_INTERNAL_INVARIANT),
                    Mxq.MXQ_DOMAIN_INTERNAL,
                    "mxq_store_export reported success without a blob");
            }

            return new ReadOnlySpan<byte>(Mxq.mxq_blob_bytes(blob), (int)Mxq.mxq_blob_len(blob)).ToArray();
        }
        finally
        {
            Mxq.mxq_blob_release(blob);
        }
    }

    /// <summary>
    /// Import one game file. Never partially commits: validation runs in order
    /// and nothing touches the database until the final stage.
    ///
    /// A duplicate is <c>MXQ_IMPORT_EXISTING</c> with the existing record — a
    /// **success**, not an error — and every rejection class the pipeline defines
    /// arrives as its own typed status through <see cref="MxqException"/>.
    /// </summary>
    public ImportResult ImportGame(ReadOnlySpan<byte> file)
    {
        int outcome = Mxq.MXQ_IMPORT_CREATED;
        ulong recordId = 0;
        MxqRecordSummary summary = default;
        summary.struct_size = (uint)sizeof(MxqRecordSummary);
        MxqError err = MxqCall.Error();

        // An empty span has no base address, and a null pointer is
        // MXQ_ERR_ARG_NULL rather than the empty file's own refusal. A spare byte
        // lends an address while the length stays 0, so the core answers about
        // the file rather than about the caller.
        byte spare = 0;
        fixed (byte* bytes = file)
        {
            MxqCall.Check(
                Mxq.mxq_store_import(
                    Live,
                    bytes is null ? &spare : bytes,
                    (nuint)file.Length,
                    &outcome,
                    &recordId,
                    &summary,
                    &err),
                in err,
                nameof(Mxq.mxq_store_import));
        }

        return new ImportResult(outcome, recordId, Describe(summary));
    }

    private static RecordSummary Describe(MxqRecordSummary summary) => new(
        summary.record_id,
        GameVocabulary.Kind(summary.game),
        summary.mode,
        summary.human_side,
        summary.ai_level,
        summary.outcome,
        summary.end_reason,
        summary.provenance,
        summary.pinned != 0,
        summary.move_count,
        summary.started_at_ms,
        summary.ended_at_ms,
        summary.added_at_ms,
        Utf8.Read(summary.game_id));
}
