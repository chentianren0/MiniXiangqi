namespace MiniXiangqi.Core.Interop;

/// <summary>
/// The one place a status becomes an exception, and the one place an
/// <c>MxqError</c> is prepared.
/// </summary>
public static unsafe class MxqCall
{
    /// <summary>
    /// A zeroed error with <c>struct_size</c> set to what this build compiled
    /// against. Every value struct begins with that field, and the core reads
    /// it to know which fields the caller can interpret.
    /// </summary>
    public static MxqError Error()
    {
        return new MxqError { struct_size = (uint)sizeof(MxqError) };
    }

    /// <summary>Throw unless <paramref name="status"/> is <c>MXQ_OK</c>.</summary>
    public static void Check(int status, in MxqError err, string operation)
    {
        if (status == Mxq.MXQ_OK)
        {
            return;
        }

        throw Failure(status, in err, operation);
    }

    /// <summary>
    /// Throw unless <paramref name="status"/> is the answer a count probe
    /// gives.
    ///
    /// The first half of the core's two-call buffer protocol — a NULL buffer
    /// with cap 0 — asks for a count, and the count is all it asks for, so the
    /// call reports that the buffer could not hold the answer: it returns
    /// <c>MXQ_ERR_ARG_BUFFER_TOO_SMALL</c> with the count written and
    /// <c>required_size</c> set. That status is routine rather than a
    /// programming error, and it is the ordinary answer here; only an empty
    /// list returns <c>MXQ_OK</c>, because then cap 0 really was enough. A
    /// binding that treated every non-OK status as a failure would fail on the
    /// most common call in the interface.
    /// </summary>
    public static void CheckCountProbe(int status, in MxqError err, string operation)
    {
        if (status is Mxq.MXQ_OK or Mxq.MXQ_ERR_ARG_BUFFER_TOO_SMALL)
        {
            return;
        }

        throw Failure(status, in err, operation);
    }

    /// <summary>Build the exception for a status without throwing it.</summary>
    public static MxqException Failure(int status, in MxqError err, string operation)
    {
        string detail = string.Empty;

        // The core writes detail only into the part of MxqError the caller
        // declared, and only when it has one to write. A status that arrived
        // with no error struct filled reads as an empty diagnostic rather than
        // as whatever the field happened to hold.
        if (err.status == status)
        {
            MxqError copy = err;
            detail = Utf8.Read(copy.detail);
        }

        return new MxqException(operation, status, StatusName(status), Mxq.mxq_status_domain(status), detail);
    }

    /// <summary>The stable ASCII name of a status, for logs and diagnostics.</summary>
    public static string StatusName(int status)
    {
        return Utf8.Read(Mxq.mxq_status_name(status));
    }
}
