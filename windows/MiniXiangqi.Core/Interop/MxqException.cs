namespace MiniXiangqi.Core.Interop;

/// <summary>
/// A typed core failure, carrying everything the C boundary reported.
///
/// docs/core-interface.md requires a frontend to select its presentation family
/// by <see cref="Domain"/> and its copy by exact <see cref="Status"/>, and to
/// tolerate an unknown status inside a known domain. Nothing here interprets
/// either: this type carries them, and the presentation layer decides. The
/// detail string is a short English diagnostic for logs, never user-facing
/// copy.
/// </summary>
public sealed class MxqException : Exception
{
    internal MxqException(string operation, int status, string statusName, int domain, string detail)
        : base(Describe(operation, status, statusName, detail))
    {
        Operation = operation;
        Status = status;
        StatusName = statusName;
        Domain = domain;
        Detail = detail;
    }

    /// <summary>The <c>mxq_</c> function that reported the failure.</summary>
    public string Operation { get; }

    /// <summary>The <c>MxqStatus</c> value.</summary>
    public int Status { get; }

    /// <summary>Its stable ASCII name, from <c>mxq_status_name</c>.</summary>
    public string StatusName { get; }

    /// <summary>Its 1000-block domain, from <c>mxq_status_domain</c>.</summary>
    public int Domain { get; }

    /// <summary><c>MxqError.detail</c>, or empty when the core supplied none.</summary>
    public string Detail { get; }

    private static string Describe(string operation, int status, string statusName, string detail)
    {
        return detail.Length == 0
            ? $"{operation} failed: {statusName} ({status})"
            : $"{operation} failed: {statusName} ({status}) — {detail}";
    }
}
