using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace BarIceCreamShop.Api.Services;

/// Envía bytes ESC/POS tal cual (RAW) a una impresora instalada en Windows, por su nombre.
/// Equivale a "lp -o raw" en CUPS: así imprime el agente del local con impresoras USB.
[SupportedOSPlatform("windows")]
internal static class WindowsRawPrinter
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private sealed class DocInfo
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string DocName = "Foco";
        [MarshalAs(UnmanagedType.LPWStr)] public string? OutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string DataType = "RAW";
    }

    [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool OpenPrinter(string printerName, out IntPtr handle, IntPtr defaults);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr handle);
    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int StartDocPrinter(IntPtr handle, int level, [In] DocInfo docInfo);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr handle);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr handle);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr handle);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr handle, byte[] bytes, int count, out int written);

    public static void Send(string printerName, byte[] content)
    {
        if (!OpenPrinter(printerName, out var handle, IntPtr.Zero))
            throw new InvalidOperationException($"No se encontró la impresora de Windows '{printerName}'.", new Win32Exception());
        try
        {
            if (StartDocPrinter(handle, 1, new DocInfo()) == 0) throw new Win32Exception();
            try
            {
                if (!StartPagePrinter(handle)) throw new Win32Exception();
                if (!WritePrinter(handle, content, content.Length, out var written) || written != content.Length)
                    throw new InvalidOperationException($"Windows no aceptó el trabajo para '{printerName}'.", new Win32Exception());
                EndPagePrinter(handle);
            }
            finally { EndDocPrinter(handle); }
        }
        finally { ClosePrinter(handle); }
    }
}
