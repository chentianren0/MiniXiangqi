using System.Runtime.InteropServices;
using System.Text;

namespace MiniXiangqi.Core.Interop;

/// <summary>
/// The two string shapes mxq.h uses, and nothing else.
///
/// Bounded strings are carried by value in fixed-capacity NUL-terminated
/// arrays, which ClangSharp gives us as C# inline arrays of <c>sbyte</c>;
/// unbounded ones (paths, moves, squares) cross as borrowed
/// <c>const char *</c>. Both are UTF-8.
/// </summary>
public static unsafe class Utf8
{
    /// <summary>
    /// Read a fixed-capacity NUL-terminated field. A field that fills its
    /// capacity without a NUL is not something the core produces; it is read as
    /// the whole capacity rather than run off the end.
    /// </summary>
    public static string Read(ReadOnlySpan<sbyte> field)
    {
        ReadOnlySpan<byte> bytes = MemoryMarshal.AsBytes(field);
        int nul = bytes.IndexOf((byte)0);
        if (nul >= 0)
        {
            bytes = bytes[..nul];
        }

        return Encoding.UTF8.GetString(bytes);
    }

    /// <summary>
    /// Read a NUL-terminated string the core owns, such as
    /// <c>mxq_status_name</c>'s immortal literal. Never freed here; the core
    /// hands out no memory the caller frees.
    /// </summary>
    public static string Read(sbyte* value)
    {
        return value is null ? string.Empty : Encoding.UTF8.GetString(MemoryMarshal.CreateReadOnlySpanFromNullTerminated((byte*)value));
    }

    /// <summary>
    /// Encode a string as the NUL-terminated UTF-8 bytes a <c>const char *</c>
    /// parameter borrows for the duration of a call. The caller pins it.
    /// </summary>
    public static byte[] Encode(string value)
    {
        ArgumentNullException.ThrowIfNull(value);

        byte[] bytes = new byte[Encoding.UTF8.GetByteCount(value) + 1];
        Encoding.UTF8.GetBytes(value, bytes);
        return bytes;
    }
}
