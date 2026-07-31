using System.ComponentModel;
using System.Runtime.InteropServices;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Core;

/// <summary>
/// The Windows memory probe the engine budget is computed from.
///
/// docs/engine-integration.md fixes it: <c>GlobalMemoryStatusEx</c>, taking
/// <c>ullAvailPhys</c> as available memory and <c>ullTotalPhys</c> as physical
/// memory. A frontend service rather than core logic — the core never derives a
/// platform value — and the caller takes a fresh probe at each calculation
/// rather than caching one.
/// </summary>
public static unsafe partial class WindowsMemoryProbe
{
    /// <summary>Probe now, and return the budget struct the core reads.</summary>
    public static MxqEngineBudget Current()
    {
        MEMORYSTATUSEX status = default;
        status.dwLength = (uint)sizeof(MEMORYSTATUSEX);
        if (GlobalMemoryStatusEx(ref status) == 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "GlobalMemoryStatusEx failed.");
        }

        return new MxqEngineBudget
        {
            struct_size = (uint)sizeof(MxqEngineBudget),
            active_processor_count = (uint)Environment.ProcessorCount,
            available_bytes = status.ullAvailPhys,
            physical_bytes = status.ullTotalPhys,
        };
    }

    // Hand-written, so [LibraryImport] rather than [DllImport]: the generated
    // core bindings are ClangSharp's output and take the shape ClangSharp
    // emits, but nothing constrains the platform calls the frontend writes
    // itself. It also matters here, where the generated bindings do not care:
    // this assembly carries [assembly: DisableRuntimeMarshalling], under which
    // DllImport cannot honour SetLastError while LibraryImport's generated stub
    // reads the error explicitly. See windows/README.md.
    [LibraryImport("kernel32", SetLastError = true)]
    private static partial int GlobalMemoryStatusEx(ref MEMORYSTATUSEX buffer);

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }
}
