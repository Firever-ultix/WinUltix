# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# CORE_HELPERS.PS1 - UNIFIED CORE ENGINE
# Core_Helpers: Unified C# P/Invoke runtime (DWM, DPI, Shell, Token Privileges, COM AppActivator, CPU Topology, NtDll Timer/DPC, CfgMgr32 PnpTree), async Runspace engine ($UltixSync), 4-color UI factories, and JSON profile snapshotter.
# ==========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------
# 1. UNIFIED WIN32 / NTDLL / KERNEL32 / CFGMGR32 P/INVOKE RUNTIME
# ------------------------------------------

if (-not ([System.Management.Automation.PSTypeName]'WinUltix.NativeMethods').Type) {
    Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing") -TypeDefinition @"
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Globalization;
    using System.Runtime.CompilerServices;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Windows.Forms;

    namespace WinUltix {
        // DWM Dark Title Bar, High-DPI GDI Scaling, Icon Extractor & Fast Kernel32 Queries
        public static class NativeMethods {
            private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
            private struct MEMORYSTATUSEX {
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

            [DllImport("dwmapi.dll", PreserveSig = true)]
            private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

            [DllImport("shell32.dll", SetLastError = true)]
            private static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

            [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
            private static extern uint PrivateExtractIconsW(
                string szFileName, int nIconIndex, int cxIcon, int cyIcon,
                IntPtr[] phicon, uint[] piconid, uint nIcons, uint flags);

            [DllImport("user32.dll", SetLastError = true)]
            public static extern bool DestroyIcon(IntPtr hIcon);

            [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool QueryFullProcessImageNameW(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool CloseHandle(IntPtr hObject);

            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            private static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

            private const uint SPI_SETMOUSE = 0x0004;
            private const uint SPIF_UPDATEINIFILE = 0x01;
            private const uint SPIF_SENDCHANGE = 0x02;

            public static bool ApplyLiveMouseParams(int threshold1, int threshold2, int speed) {
                int[] mouseParams = new int[3] { threshold1, threshold2, speed };
                return SystemParametersInfoW(SPI_SETMOUSE, 0, mouseParams, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
            }

            public static void EnableDarkTitleBar(IntPtr handle) {
                if (handle == IntPtr.Zero) return;
                int useDark = 1;
                if (DwmSetWindowAttribute(handle, 20, ref useDark, sizeof(int)) != 0) {
                    DwmSetWindowAttribute(handle, 19, ref useDark, sizeof(int));
                }
            }

            public static void EnableGdiDpiScaling() {
                try { SetCurrentProcessExplicitAppUserModelID("Firever.WinUltix"); } catch { }
                try { SetProcessDpiAwarenessContext(new IntPtr(-5)); } catch { }
            }

            public static Bitmap ExtractHighResExeIcon(string exePath, int size) {
                IntPtr[] hIcons = new IntPtr[1];
                uint[] ids = new uint[1];
                uint count = PrivateExtractIconsW(exePath, 0, size, size, hIcons, ids, 1, 0);
                if (count > 0 && hIcons[0] != IntPtr.Zero) {
                    try {
                        using (Icon ico = Icon.FromHandle(hIcons[0])) {
                            return ico.ToBitmap();
                        }
                    } catch {
                        try { return Bitmap.FromHicon(hIcons[0]); } catch { }
                    } finally {
                        DestroyIcon(hIcons[0]);
                    }
                }
                return null;
            }

            public static int GetTotalPhysicalMemoryKB() {
                MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
                mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
                if (GlobalMemoryStatusEx(ref mem) && mem.ullTotalPhys > 0) {
                    ulong kb = mem.ullTotalPhys / 1024UL;
                    return (kb > (ulong)int.MaxValue) ? int.MaxValue : (int)kb;
                }
                return 16777216;
            }

            public static string GetProcessExecutablePath(int pid) {
                if (pid <= 4) return "";
                IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
                if (hProc == IntPtr.Zero) return "";
                try {
                    uint capacity = 1024;
                    StringBuilder sb = new StringBuilder((int)capacity);
                    if (QueryFullProcessImageNameW(hProc, 0, sb, ref capacity)) {
                        return sb.ToString();
                    }
                } finally {
                    CloseHandle(hProc);
                }
                return "";
            }

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern IntPtr CreateFileW(
                string lpFileName, uint dwDesiredAccess, uint dwShareMode,
                IntPtr lpSecurityAttributes, uint dwCreationDisposition,
                uint dwFlagsAndAttributes, IntPtr hTemplateFile);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool DeviceIoControl(
                IntPtr hDevice, uint dwIoControlCode,
                IntPtr lpInBuffer, uint nInBufferSize,
                out uint lpOutBuffer, uint nOutBufferSize,
                out uint lpBytesReturned, IntPtr lpOverlapped);

            private const uint FSCTL_IS_VOLUME_DIRTY = 0x00090078;

            public static int IsVolumeDirty(string driveName) {
                if (string.IsNullOrWhiteSpace(driveName)) return -1;
                string cleanDrive = driveName.Trim().TrimEnd('\\');
                if (!cleanDrive.EndsWith(":", StringComparison.Ordinal)) cleanDrive += ":";
                IntPtr hVol = CreateFileW(@"\\.\" + cleanDrive, 0x80000000U, 3U, IntPtr.Zero, 3U, 0U, IntPtr.Zero);
                if (hVol == IntPtr.Zero || hVol == new IntPtr(-1)) return -1;
                try {
                    uint flags = 0, ret = 0;
                    if (DeviceIoControl(hVol, FSCTL_IS_VOLUME_DIRTY, IntPtr.Zero, 0U, out flags, 4U, out ret, IntPtr.Zero)) {
                        return ((flags & 1U) != 0U) ? 1 : 0;
                    }
                } finally {
                    CloseHandle(hVol);
                }
                return -1;
            }
        }

        // Non-Invasive Shell & Taskbar Broadcast Interop
        public static class ShellInterop {
            private static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
            private const uint WM_SETTINGCHANGE = 0x001A;
            private const uint SMTO_ABORTIFHUNG = 0x0002;
            private const int SHCNE_ASSOCCHANGED = 0x08000000;
            private const uint SHCNF_IDLIST = 0x0000;
            private const uint SHCNF_FLUSHNOWAIT = 0x2000;

            [DllImport("shell32.dll")]
            public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern IntPtr SendMessageTimeout(
                IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
                uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

            public static void BroadcastShellRefresh() {
                IntPtr result;
                SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST | SHCNF_FLUSHNOWAIT, IntPtr.Zero, IntPtr.Zero);
                SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, "TraySettings", SMTO_ABORTIFHUNG, 100, out result);
                SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, "ShellState", SMTO_ABORTIFHUNG, 100, out result);
                SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, "Policy", SMTO_ABORTIFHUNG, 100, out result);
                SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, "Environment", SMTO_ABORTIFHUNG, 100, out result);
            }
        }

        // Token Privilege Escalation & Live SCM Service Configurator
        public static class PrivilegeEnabler {
            private const uint SC_MANAGER_CONNECT = 0x0001;
            private const uint SERVICE_CHANGE_CONFIG = 0x0002;
            private const uint SERVICE_START = 0x0010;
            private const uint SERVICE_STOP = 0x0020;
            private const uint SERVICE_CONTROL_STOP = 0x00000001;
            private const uint SERVICE_NO_CHANGE = 0xFFFFFFFF;

            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            private static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            private static extern bool OpenProcessToken(IntPtr h, uint acc, ref IntPtr phtok);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern IntPtr OpenSCManagerW(string machineName, string databaseName, uint dwAccess);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern IntPtr OpenServiceW(IntPtr hSCManager, string lpServiceName, uint dwDesiredAccess);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool ChangeServiceConfigW(
                IntPtr hService, uint dwServiceType, uint dwStartType, uint dwErrorControl,
                string lpBinaryPathName, string lpLoadOrderGroup, IntPtr lpdwTagId,
                string lpDependencies, string lpServiceStartName, string lpPassword, string lpDisplayName);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool StartServiceW(IntPtr hService, uint dwNumServiceArgs, IntPtr lpServiceArgVectors);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool ControlService(IntPtr hService, uint dwControl, out SERVICE_STATUS lpServiceStatus);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool QueryServiceObjectSecurity(
                IntPtr hService, uint dwSecurityInformation, byte[] lpSecurityDescriptor,
                uint cbBufSize, out uint pcbBytesNeeded);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool SetServiceObjectSecurity(
                IntPtr hService, uint dwSecurityInformation, byte[] lpSecurityDescriptor);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool CloseServiceHandle(IntPtr hSCObject);

            [DllImport("kernel32.dll", ExactSpelling = true)]
            private static extern IntPtr GetCurrentProcess();

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool CloseHandle(IntPtr hObject);

            private const uint READ_CONTROL = 0x00020000;
            private const uint WRITE_DAC = 0x00040000;
            private const uint WRITE_OWNER = 0x00080000;
            private const int SERVICE_ALL_ACCESS = 0x000F01FF;
            private const uint OWNER_SECURITY_INFORMATION = 0x00000001;
            private const uint DACL_SECURITY_INFORMATION = 0x00000004;

            [StructLayout(LayoutKind.Sequential, Pack = 1)]
            private struct TokPriv1Luid {
                public int Count;
                public long Luid;
                public int Attr;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct SERVICE_STATUS {
                public uint dwServiceType;
                public uint dwCurrentState;
                public uint dwControlsAccepted;
                public uint dwWin32ExitCode;
                public uint dwServiceSpecificExitCode;
                public uint dwCheckPoint;
                public uint dwWaitHint;
            }

            public static void EnablePrivilege(string privilege) {
                IntPtr htok = IntPtr.Zero;
                if (!OpenProcessToken(GetCurrentProcess(), 0x00000028U, ref htok)) return;
                try {
                    TokPriv1Luid tp = new TokPriv1Luid { Count = 1, Luid = 0, Attr = 0x00000002 };
                    if (LookupPrivilegeValue(null, privilege, ref tp.Luid)) {
                        AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                    }
                } finally {
                    if (htok != IntPtr.Zero) CloseHandle(htok);
                }
            }

            private static bool GrantAdminServiceAccess(IntPtr hScm, string serviceName) {
                var adminSid = new System.Security.Principal.SecurityIdentifier(
                    System.Security.Principal.WellKnownSidType.BuiltinAdministratorsSid, null);

                IntPtr hSvcDac = OpenServiceW(hScm, serviceName, READ_CONTROL | WRITE_DAC);
                if (hSvcDac == IntPtr.Zero) {
                    EnablePrivilege("SeTakeOwnershipPrivilege");
                    IntPtr hSvcOwn = OpenServiceW(hScm, serviceName, WRITE_OWNER);
                    if (hSvcOwn != IntPtr.Zero) {
                        try {
                            var ownerSd = new System.Security.AccessControl.RawSecurityDescriptor(
                                System.Security.AccessControl.ControlFlags.None, adminSid, null, null, null);
                            byte[] ownerBytes = new byte[ownerSd.BinaryLength];
                            ownerSd.GetBinaryForm(ownerBytes, 0);
                            SetServiceObjectSecurity(hSvcOwn, OWNER_SECURITY_INFORMATION, ownerBytes);
                        } finally {
                            CloseServiceHandle(hSvcOwn);
                        }
                        hSvcDac = OpenServiceW(hScm, serviceName, READ_CONTROL | WRITE_DAC);
                    }
                }

                if (hSvcDac == IntPtr.Zero) return false;
                try {
                    uint needed = 0;
                    QueryServiceObjectSecurity(hSvcDac, DACL_SECURITY_INFORMATION, null, 0, out needed);
                    if (needed == 0) return false;

                    byte[] sdBuf = new byte[needed];
                    if (!QueryServiceObjectSecurity(hSvcDac, DACL_SECURITY_INFORMATION, sdBuf, needed, out needed)) {
                        return false;
                    }

                    var rsd = new System.Security.AccessControl.RawSecurityDescriptor(sdBuf, 0);
                    if (rsd.DiscretionaryAcl == null) {
                        rsd.DiscretionaryAcl = new System.Security.AccessControl.RawAcl(2, 1);
                    }
                    rsd.DiscretionaryAcl.InsertAce(0, new System.Security.AccessControl.CommonAce(
                        System.Security.AccessControl.AceFlags.None,
                        System.Security.AccessControl.AceQualifier.AccessAllowed,
                        SERVICE_ALL_ACCESS,
                        adminSid,
                        false,
                        null));

                    byte[] newSd = new byte[rsd.BinaryLength];
                    rsd.GetBinaryForm(newSd, 0);
                    return SetServiceObjectSecurity(hSvcDac, DACL_SECURITY_INFORMATION, newSd);
                } catch {
                    return false;
                } finally {
                    CloseServiceHandle(hSvcDac);
                }
            }

            public static bool SetServiceConfigLive(string serviceName, int startType, bool startNow) {
                if (string.IsNullOrWhiteSpace(serviceName)) return false;
                bool changeConfig = (startType >= 0 && startType <= 4);
                uint access = (changeConfig ? SERVICE_CHANGE_CONFIG : 0U) | (startNow ? SERVICE_START : 0U);
                if (access == 0U) return false;

                IntPtr hScm = IntPtr.Zero;
                IntPtr hSvc = IntPtr.Zero;

                try {
                    hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
                    if (hScm == IntPtr.Zero) return false;
                    hSvc = OpenServiceW(hScm, serviceName, access);
                    if (hSvc == IntPtr.Zero && GrantAdminServiceAccess(hScm, serviceName)) {
                        hSvc = OpenServiceW(hScm, serviceName, access);
                    }
                    if (hSvc == IntPtr.Zero) return false;

                    bool ok = true;
                    if (changeConfig) {
                        ok = ChangeServiceConfigW(
                            hSvc, SERVICE_NO_CHANGE, (uint)startType, SERVICE_NO_CHANGE,
                            null, null, IntPtr.Zero, null, null, null, null);
                    }

                    if (startNow && startType != 4) {
                        StartServiceW(hSvc, 0, IntPtr.Zero);
                    }
                    return ok;
                } finally {
                    if (hSvc != IntPtr.Zero) CloseServiceHandle(hSvc);
                    if (hScm != IntPtr.Zero) CloseServiceHandle(hScm);
                }
            }

            public static bool StopServiceLive(string serviceName) {
                if (string.IsNullOrWhiteSpace(serviceName)) return false;
                IntPtr hScm = IntPtr.Zero;
                IntPtr hSvc = IntPtr.Zero;

                try {
                    hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
                    if (hScm == IntPtr.Zero) return false;
                    hSvc = OpenServiceW(hScm, serviceName, SERVICE_STOP);
                    if (hSvc == IntPtr.Zero && GrantAdminServiceAccess(hScm, serviceName)) {
                        hSvc = OpenServiceW(hScm, serviceName, SERVICE_STOP);
                    }
                    if (hSvc == IntPtr.Zero) return false;

                    SERVICE_STATUS status;
                    return ControlService(hSvc, SERVICE_CONTROL_STOP, out status);
                } finally {
                    if (hSvc != IntPtr.Zero) CloseServiceHandle(hSvc);
                    if (hScm != IntPtr.Zero) CloseServiceHandle(hScm);
                }
            }
        }

        // COM IApplicationActivationManager for Native Start Menu Compilation
        [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        public interface IApplicationActivationManager {
            IntPtr ActivateApplication([In] String appUserModelId, [In] String arguments, [In] UInt32 options, [Out] out UInt32 processId);
        }

        [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
        public class AppActivator : IApplicationActivationManager {
            [MethodImpl(MethodImplOptions.InternalCall, MethodCodeType = MethodCodeType.Runtime)]
            public extern IntPtr ActivateApplication([In] String appUserModelId, [In] String arguments, [In] UInt32 options, [Out] out UInt32 processId);
        }

        // Fast Numeric-Aware, Tie-Safe & Multi-Mode Column Sorter for WinForms ListViews
        public class ListViewColumnSorter : IComparer {
            public int ColumnToSort = 0;
            public SortOrder OrderOfSort = SortOrder.None;
            private CaseInsensitiveComparer ObjectCompare = new CaseInsensitiveComparer();

            private static bool TryParseSortableNumber(string s, out double val) {
                val = 0;
                if (string.IsNullOrWhiteSpace(s)) return false;
                string clean = s.Trim();

                // Natural numeric sort for DriverStore oemXX.inf packages
                if (clean.Length > 7 && clean.StartsWith("oem", StringComparison.OrdinalIgnoreCase) && clean.EndsWith(".inf", StringComparison.OrdinalIgnoreCase)) {
                    string numPart = clean.Substring(3, clean.Length - 7);
                    if (double.TryParse(numPart, NumberStyles.Integer, CultureInfo.InvariantCulture, out val)) return true;
                }

                // Strip leading "Max: " prefix if sorting by Peak column
                if (clean.StartsWith("Max:", StringComparison.OrdinalIgnoreCase)) {
                    clean = clean.Substring(4).Trim();
                }

                // Strip live driver overhead suffix: "142.5 µs/s", "85.0 µs (1s: ...)" -> leading float
                int usIdx = clean.IndexOf(" \u00B5s", StringComparison.OrdinalIgnoreCase);
                if (usIdx < 0) usIdx = clean.IndexOf(" us", StringComparison.OrdinalIgnoreCase);
                if (usIdx > 0) {
                    clean = clean.Substring(0, usIdx).Trim();
                }

                // Strip trailing unit or core annotation: " MB", " KB", " GB", "%", or " (Core X)"
                int parenIdx = clean.IndexOf(" (Core ", StringComparison.OrdinalIgnoreCase);
                if (parenIdx > 0) {
                    clean = clean.Substring(0, parenIdx).Trim();
                } else if (clean.EndsWith(" MB", StringComparison.OrdinalIgnoreCase) ||
                           clean.EndsWith(" KB", StringComparison.OrdinalIgnoreCase) ||
                           clean.EndsWith(" GB", StringComparison.OrdinalIgnoreCase)) {
                    clean = clean.Substring(0, clean.Length - 3).Trim();
                } else if (clean.EndsWith("%", StringComparison.Ordinal)) {
                    clean = clean.Substring(0, clean.Length - 1).Trim();
                }

                clean = clean.Replace("\u00A0", "").Replace(" ", "").Replace(',', '.');
                return double.TryParse(clean, NumberStyles.Float, CultureInfo.InvariantCulture, out val);
            }

            public int Compare(object x, object y) {
                if (OrderOfSort == SortOrder.None) return 0;
                ListViewItem listviewX = (ListViewItem)x;
                ListViewItem listviewY = (ListViewItem)y;

                // ColumnToSort == -1: Special sort by SubItems[4] 1s instantaneous load "(1s: XX.X)"
                string textX, textY;
                if (ColumnToSort == -1) {
                    textX = (listviewX.SubItems.Count > 4) ? listviewX.SubItems[4].Text : "";
                    textY = (listviewY.SubItems.Count > 4) ? listviewY.SubItems[4].Text : "";
                    int idxX = textX.IndexOf("1s:", StringComparison.OrdinalIgnoreCase);
                    int idxY = textY.IndexOf("1s:", StringComparison.OrdinalIgnoreCase);
                    if (idxX >= 0) textX = textX.Substring(idxX + 3).TrimEnd(')', ' ');
                    if (idxY >= 0) textY = textY.Substring(idxY + 3).TrimEnd(')', ' ');
                } else {
                    textX = (ColumnToSort >= 0 && ColumnToSort < listviewX.SubItems.Count) ? listviewX.SubItems[ColumnToSort].Text : "";
                    textY = (ColumnToSort >= 0 && ColumnToSort < listviewY.SubItems.Count) ? listviewY.SubItems[ColumnToSort].Text : "";
                }

                int compareResult;
                double numX, numY;
                if (TryParseSortableNumber(textX, out numX) && TryParseSortableNumber(textY, out numY)) {
                    compareResult = numX.CompareTo(numY);
                } else {
                    compareResult = ObjectCompare.Compare(textX, textY);
                }

                if (OrderOfSort == SortOrder.Descending) compareResult = -compareResult;

                // Deterministic tie-breaker by SubItem[1] (Device Name) to prevent unstable QuickSort row jitter on 0.0 ties
                if (compareResult == 0 && listviewX.SubItems.Count > 1 && listviewY.SubItems.Count > 1) {
                    compareResult = ObjectCompare.Compare(listviewX.SubItems[1].Text, listviewY.SubItems[1].Text);
                }
                return compareResult;
            }
        }

        // Native CPU Core & L3 Cache Topology Inspector (3D V-Cache & Hybrid P/E Detection)
        public class CoreRecord {
            public byte Flags;
            public byte EfficiencyClass;
            public long Mask;
        }

        public class L3CacheRecord {
            public uint SizeBytes;
            public long Mask;
        }

        // Native Zero-WMI SMBIOS Type 17 (Memory Device) Parser via kernel32!GetSystemFirmwareTable (<0.1ms)
        public static class SmbiosRamInfo {
            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern uint GetSystemFirmwareTable(uint FirmwareTableProviderSignature, uint FirmwareTableID, IntPtr pFirmwareTableBuffer, uint BufferSize);

            private const uint RSMB = 0x52534D42; // 'RSMB' in ASCII

            private static string GetSmbiosString(byte[] data, int structEnd, int strEnd, byte index) {
                if (index == 0) return "";
                int curIdx = 1;
                int pos = structEnd;
                while (pos < strEnd && data[pos] != 0) {
                    int start = pos;
                    while (pos < strEnd && data[pos] != 0) pos++;
                    if (curIdx == index) {
                        return Encoding.ASCII.GetString(data, start, pos - start).Trim();
                    }
                    curIdx++;
                    pos++;
                }
                return "";
            }

            public static string GetRamSummary(ulong fallbackTotalKB) {
                double fallbackGB = Math.Round(fallbackTotalKB / 1048576.0, 1);
                uint size = GetSystemFirmwareTable(RSMB, 0, IntPtr.Zero, 0);
                if (size <= 8 || size > 65536) return string.Format(CultureInfo.InvariantCulture, "{0} GB", fallbackGB);

                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try {
                    if (GetSystemFirmwareTable(RSMB, 0, buf, size) != size) {
                        return string.Format(CultureInfo.InvariantCulture, "{0} GB", fallbackGB);
                    }
                    byte[] raw = new byte[size];
                    Marshal.Copy(buf, raw, 0, (int)size);

                    int totalSlots = 0;
                    int usedSlots  = 0;
                    ulong totalMB  = 0;
                    var stickSizesMB = new List<ulong>();
                    uint bestSpeed = 0;
                    byte memType   = 0;
                    string partNum = "";
                    string vendor  = "";

                    int pos = 8; // Skip 8-byte RawSMBIOSData header
                    while (pos + 4 <= raw.Length) {
                        byte type = raw[pos];
                        byte len  = raw[pos + 1];
                        if (len < 4 || pos + len > raw.Length) break;

                        int strEnd = pos + len;
                        while (strEnd + 1 < raw.Length && !(raw[strEnd] == 0 && raw[strEnd + 1] == 0)) {
                            strEnd++;
                        }
                        int nextPos = Math.Min(raw.Length, strEnd + 2);

                        // SMBIOS Type 17: Memory Device
                        if (type == 17 && len >= 0x15) {
                            ushort rawSize = BitConverter.ToUInt16(raw, pos + 0x0C);
                            if (rawSize != 0xFFFF) {
                                totalSlots++;
                                ulong moduleMB = 0;
                                if (rawSize == 0x7FFF && len >= 0x20) {
                                    uint extSize = BitConverter.ToUInt32(raw, pos + 0x1C);
                                    moduleMB = (ulong)(extSize & 0x7FFFFFFFU);
                                } else if (rawSize > 0) {
                                    moduleMB = ((rawSize & 0x8000) != 0) ? ((ulong)(rawSize & 0x7FFF) / 1024UL) : (ulong)rawSize;
                                }

                                if (moduleMB > 0) {
                                    usedSlots++;
                                    totalMB += moduleMB;
                                    stickSizesMB.Add(moduleMB);

                                    if (len > 0x12 && raw[pos + 0x12] > 0 && memType == 0) {
                                        memType = raw[pos + 0x12];
                                    }

                                    uint spd = BitConverter.ToUInt16(raw, pos + 0x15);
                                    if (len >= 0x22) {
                                        ushort cfgSpd = BitConverter.ToUInt16(raw, pos + 0x20);
                                        if (cfgSpd > 0 && cfgSpd != 0xFFFF) spd = cfgSpd;
                                        else if (cfgSpd == 0xFFFF && len >= 0x60) {
                                            uint extSpd = BitConverter.ToUInt32(raw, pos + 0x5C);
                                            if (extSpd > 0) spd = extSpd;
                                        }
                                    }
                                    if (spd > bestSpeed && spd <= 16000) bestSpeed = spd;

                                    if (string.IsNullOrEmpty(vendor) && len > 0x17) {
                                        string v = GetSmbiosString(raw, pos + len, strEnd, raw[pos + 0x17]);
                                        if (!string.IsNullOrWhiteSpace(v) && !v.StartsWith("Unknown", StringComparison.OrdinalIgnoreCase) && !v.StartsWith("0000", StringComparison.Ordinal)) {
                                            vendor = v;
                                        }
                                    }
                                    if (string.IsNullOrEmpty(partNum) && len > 0x1A) {
                                        string p = GetSmbiosString(raw, pos + len, strEnd, raw[pos + 0x1A]);
                                        if (!string.IsNullOrWhiteSpace(p) && !p.StartsWith("Unknown", StringComparison.OrdinalIgnoreCase) && !p.StartsWith("None", StringComparison.OrdinalIgnoreCase)) {
                                            partNum = p;
                                        }
                                    }
                                }
                            }
                        }

                        if (type == 127) break;
                        pos = nextPos;
                    }

                    if (usedSlots == 0 || totalMB == 0) {
                        return string.Format(CultureInfo.InvariantCulture, "{0} GB", fallbackGB);
                    }

                    string ddrStr = "RAM";
                    switch (memType) {
                        case 0x18: ddrStr = "DDR3"; break;
                        case 0x1A: ddrStr = "DDR4"; break;
                        case 0x1E: ddrStr = "LPDDR4"; break;
                        case 0x22: ddrStr = "DDR5"; break;
                        case 0x23: ddrStr = "LPDDR5"; break;
                    }

                    ulong totalGB = totalMB / 1024UL;
                    string speedPart = (bestSpeed > 0) ? string.Format(" @ {0} MT/s", bestSpeed) : "";

                    ulong firstStickGB = stickSizesMB[0] / 1024UL;
                    bool uniformSticks = (firstStickGB > 0);
                    for (int i = 1; i < stickSizesMB.Count; i++) {
                        if ((stickSizesMB[i] / 1024UL) != firstStickGB) { uniformSticks = false; break; }
                    }

                    string layoutPart = uniformSticks
                        ? string.Format("{0}x {1} GB", usedSlots, firstStickGB)
                        : string.Format("{0} Modules", usedSlots);

                    string slotsPart = (totalSlots >= usedSlots && totalSlots <= 16)
                        ? string.Format(" | {0}/{1} Slots", usedSlots, totalSlots)
                        : "";

                    string modelPart = "";
                    if (!string.IsNullOrEmpty(partNum)) {
                        modelPart = " | " + partNum;
                    } else if (!string.IsNullOrEmpty(vendor)) {
                        modelPart = " | " + vendor;
                    }

                    return string.Format(CultureInfo.InvariantCulture, "{0} GB {1}{2} ({3}{4}{5})",
                        totalGB, ddrStr, speedPart, layoutPart, slotsPart, modelPart);
                } catch {
                    return string.Format(CultureInfo.InvariantCulture, "{0} GB", fallbackGB);
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
            }
        }

        public static class CpuTopology {
            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool GetLogicalProcessorInformationEx(
                int RelationshipType,
                IntPtr Buffer,
                ref uint ReturnedLength);

            private const int RelationProcessorCore = 0;
            private const int RelationCache = 2;

            public static List<CoreRecord> GetProcessorCores() {
                var list = new List<CoreRecord>();
                uint len = 0;
                GetLogicalProcessorInformationEx(RelationProcessorCore, IntPtr.Zero, ref len);
                if (len == 0) return list;

                IntPtr buf = Marshal.AllocHGlobal((int)len);
                try {
                    if (GetLogicalProcessorInformationEx(RelationProcessorCore, buf, ref len)) {
                        int offset = 0;
                        while (offset < (int)len) {
                            IntPtr cur = IntPtr.Add(buf, offset);
                            int rel = Marshal.ReadInt32(cur, 0);
                            int size = Marshal.ReadInt32(cur, 4);
                            if (rel == RelationProcessorCore && size >= 40) {
                                byte flags = Marshal.ReadByte(cur, 8);
                                byte eff   = Marshal.ReadByte(cur, 9);
                                long mask  = Marshal.ReadIntPtr(cur, 32).ToInt64();
                                list.Add(new CoreRecord { Flags = flags, EfficiencyClass = eff, Mask = mask });
                            }
                            if (size <= 0) break;
                            offset += size;
                        }
                    }
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
                return list;
            }

            public static List<L3CacheRecord> GetL3Caches() {
                var list = new List<L3CacheRecord>();
                uint len = 0;
                GetLogicalProcessorInformationEx(RelationCache, IntPtr.Zero, ref len);
                if (len == 0) return list;

                IntPtr buf = Marshal.AllocHGlobal((int)len);
                try {
                    if (GetLogicalProcessorInformationEx(RelationCache, buf, ref len)) {
                        int offset = 0;
                        while (offset < (int)len) {
                            IntPtr cur = IntPtr.Add(buf, offset);
                            int rel = Marshal.ReadInt32(cur, 0);
                            int size = Marshal.ReadInt32(cur, 4);
                            if (rel == RelationCache && size >= 48) {
                                byte level = Marshal.ReadByte(cur, 8);
                                if (level == 3) {
                                    uint cacheSize = (uint)Marshal.ReadInt32(cur, 12);
                                    long mask      = Marshal.ReadIntPtr(cur, 40).ToInt64();
                                    list.Add(new L3CacheRecord { SizeBytes = cacheSize, Mask = mask });
                                }
                            }
                            if (size <= 0) break;
                            offset += size;
                        }
                    }
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
                return list;
            }

            public static long GetTailThreadsMask(long domainMask, int threadCount) {
                var bitIndices = new List<int>();
                for (int b = 0; b < 64; b++) {
                    if ((domainMask & (1L << b)) != 0) bitIndices.Add(b);
                }
                if (bitIndices.Count <= threadCount) return domainMask;
                long result = 0;
                for (int i = bitIndices.Count - threadCount; i < bitIndices.Count; i++) {
                    result |= (1L << bitIndices[i]);
                }
                return result;
            }
        }

        // Native Kernel Timer Resolution & Per-CPU Interrupt/DPC Telemetry
        public static class NtDll {
            [DllImport("ntdll.dll")]
            private static extern int NtQueryTimerResolution(out uint MaximumTime, out uint MinimumTime, out uint CurrentTime);

            [DllImport("ntdll.dll", SetLastError = true)]
            private static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);

            [DllImport("ntdll.dll")]
            private static extern int NtQuerySystemInformation(int SystemInformationClass, IntPtr SystemInformation, uint SystemInformationLength, out uint ReturnLength);

            private const int SystemInterruptInformation = 23; // 0x17 (24 bytes per logical processor)

            public static uint[] GetTimerData() {
                uint max, min, cur;
                NtQueryTimerResolution(out max, out min, out cur);
                return new uint[] { max, min, cur };
            }

            public static uint SetTimerResolution(uint desired100Ns, bool enable) {
                uint cur = 0;
                NtSetTimerResolution(desired100Ns, enable, out cur);
                return cur;
            }

            public static uint[] GetProcessorDpcCounts() {
                int lpCount = Environment.ProcessorCount;
                int structSize = 24;
                uint bufLen = (uint)(lpCount * structSize);
                IntPtr buf = Marshal.AllocHGlobal((int)bufLen);
                try {
                    uint retLen = 0;
                    int status = NtQuerySystemInformation(SystemInterruptInformation, buf, bufLen, out retLen);
                    if (status != 0) return new uint[0];

                    int validCount = Math.Min(lpCount, (int)(retLen / structSize));
                    uint[] dpcCounts = new uint[validCount];
                    for (int i = 0; i < validCount; i++) {
                        // Offset 4 inside SYSTEM_INTERRUPT_INFORMATION is DpcCount (uint)
                        dpcCounts[i] = (uint)Marshal.ReadInt32(buf, (i * structSize) + 4);
                    }
                    return dpcCounts;
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
            }
        }

        // Lock-Free Real-Time Kernel ETW ISR/DPC Per-Driver Profiler (With Session Average & Peak Tracking)
        public class DriverLoadRecord {
            public string DriverName;
            public string ServiceKey;
            public double UsPerSec;
            public double AvgUsPerSec;
            public double MaxPeakUs;
            public long CallsPerSec;
            public long TotalCalls;
            public int ElapsedSec;
        }

        public static class DpcDriverProfiler {
            [DllImport("ntdll.dll")]
            private static extern int NtQuerySystemInformation(int SystemInformationClass, IntPtr SystemInformation, uint SystemInformationLength, out uint ReturnLength);

            [DllImport("kernel32.dll")]
            private static extern bool QueryPerformanceFrequency(out long lpFrequency);

            [DllImport("kernel32.dll")]
            private static extern bool QueryPerformanceCounter(out long lpPerformanceCount);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
            private static extern uint StartTraceW(out ulong SessionHandle, string SessionName, IntPtr Properties);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
            private static extern uint ControlTraceW(ulong SessionHandle, string SessionName, IntPtr Properties, uint ControlCode);

            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern ulong OpenTraceW(IntPtr Logfile);

            [DllImport("advapi32.dll")]
            private static extern uint ProcessTrace(ulong[] HandleArray, uint HandleCount, IntPtr StartTime, IntPtr EndTime);

            [DllImport("advapi32.dll")]
            private static extern uint CloseTrace(ulong TraceHandle);

            [UnmanagedFunctionPointer(CallingConvention.StdCall)]
            private delegate void EventRecordCallback(IntPtr pEventRecord);

            private struct KernelModuleRange : IComparable<KernelModuleRange> {
                public ulong BaseAddress;
                public ulong EndAddress;
                public string DriverName;
                public string ServiceKey;

                public int CompareTo(KernelModuleRange other) {
                    return this.BaseAddress.CompareTo(other.BaseAddress);
                }
            }

            private const int SystemModuleInformation = 11;
            private const uint EVENT_TRACE_CONTROL_STOP = 1;
            private const uint EVENT_TRACE_FLAG_INTERRUPT = 0x00000040;
            private const uint EVENT_TRACE_FLAG_DPC = 0x00000020;
            private const uint EVENT_TRACE_REAL_TIME_MODE = 0x00000100;
            private const uint EVENT_TRACE_SYSTEM_LOGGER_MODE = 0x02000000;
            private const uint WNODE_FLAG_TRACED_GUID = 0x00020000;
            private const uint PROCESS_TRACE_MODE_REAL_TIME = 0x00000100;
            private const uint PROCESS_TRACE_MODE_RAW_TIMESTAMP = 0x00001000;
            private const uint PROCESS_TRACE_MODE_EVENT_RECORD = 0x10000000;
            private const int PERFINFO_GUID_DATA1 = unchecked((int)0xce1dbfb4);

            private static readonly Guid SystemTraceControlGuid = new Guid("9e814aad-3204-11d2-9a82-006008a86939");
            private static readonly EventRecordCallback _callbackDelegate = new EventRecordCallback(OnEventRecord);

            private sealed class ProfilerSessionState {
                public readonly KernelModuleRange[] Modules;
                public readonly long[] WindowTicks;
                public readonly long[] WindowCounts;
                public readonly long[] TotalTicks;
                public readonly long[] TotalCounts;
                public readonly long[] SessionPeakTicks;
                public long SessionStartQpc;

                public ProfilerSessionState(KernelModuleRange[] modules, long startQpc) {
                    Modules          = modules;
                    WindowTicks      = new long[modules.Length];
                    WindowCounts     = new long[modules.Length];
                    TotalTicks       = new long[modules.Length];
                    TotalCounts      = new long[modules.Length];
                    SessionPeakTicks = new long[modules.Length];
                    SessionStartQpc  = startQpc;
                }
            }

            private static readonly object _lifecycleLock = new object();
            private static volatile bool _running = false;
            private static string _activeSessionName = "WinUltix_DpcProfiler";
            private static ulong _sessionHandle = 0;
            private static ulong _traceHandle = 0;
            private static System.Threading.Thread _workerThread = null;
            private static ProfilerSessionState _sessionState = new ProfilerSessionState(new KernelModuleRange[0], 0);
            private static long _qpcFreq = 10000000L;
            private static long _maxSaneTicks = 5000000L;

            public static bool IsRunning { get { return _running; } }

            private static void LoadKernelModules() {
                PrivilegeEnabler.EnablePrivilege("SeSystemProfilePrivilege");

                uint retLen = 0;
                NtQuerySystemInformation(SystemModuleInformation, IntPtr.Zero, 0, out retLen);
                if (retLen == 0) retLen = 262144;
                uint bufLen = retLen + 65536;

                IntPtr buf = Marshal.AllocHGlobal((int)bufLen);
                try {
                    int status = NtQuerySystemInformation(SystemModuleInformation, buf, bufLen, out retLen);
                    if (status != 0) return;

                    int count = Marshal.ReadInt32(buf, 0);
                    int headOffset = IntPtr.Size;
                    int entrySize = (IntPtr.Size == 8) ? 296 : 284;
                    var list = new List<KernelModuleRange>(Math.Max(16, count));

                    for (int i = 0; i < count; i++) {
                        IntPtr item = IntPtr.Add(buf, headOffset + (i * entrySize));
                        ulong imgBase = unchecked((ulong)Marshal.ReadIntPtr(item, IntPtr.Size * 2).ToInt64());
                        uint imgSize  = unchecked((uint)Marshal.ReadInt32(item, IntPtr.Size * 3));
                        if (imgBase == 0 || imgSize == 0) continue;

                        ushort fnOffset = (ushort)Marshal.ReadInt16(item, (IntPtr.Size * 3) + 14);
                        if (fnOffset >= 256) fnOffset = 0;

                        IntPtr pathPtr = IntPtr.Add(item, (IntPtr.Size * 3) + 16 + fnOffset);
                        string drvFile = Marshal.PtrToStringAnsi(pathPtr);
                        if (string.IsNullOrWhiteSpace(drvFile)) drvFile = "Unknown.sys";

                        int slashIdx = drvFile.LastIndexOf('\\');
                        if (slashIdx >= 0 && slashIdx + 1 < drvFile.Length) {
                            drvFile = drvFile.Substring(slashIdx + 1);
                        }

                        string svcKey = drvFile;
                        if (svcKey.EndsWith(".sys", StringComparison.OrdinalIgnoreCase) ||
                            svcKey.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                            svcKey.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)) {
                            svcKey = svcKey.Substring(0, svcKey.Length - 4);
                        }

                        list.Add(new KernelModuleRange {
                            BaseAddress = imgBase,
                            EndAddress  = imgBase + (ulong)imgSize,
                            DriverName  = drvFile,
                            ServiceKey  = svcKey.ToLowerInvariant()
                        });
                    }

                    list.Sort();
                    long nowQpc;
                    QueryPerformanceCounter(out nowQpc);
                    System.Threading.Volatile.Write(ref _sessionState, new ProfilerSessionState(list.ToArray(), nowQpc));
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
            }

            public static void ResetStats() {
                ProfilerSessionState st = System.Threading.Volatile.Read(ref _sessionState);
                if (st == null) return;
                long now;
                QueryPerformanceCounter(out now);
                System.Threading.Interlocked.Exchange(ref st.SessionStartQpc, now);
                for (int i = 0; i < st.Modules.Length; i++) {
                    System.Threading.Interlocked.Exchange(ref st.WindowTicks[i], 0);
                    System.Threading.Interlocked.Exchange(ref st.WindowCounts[i], 0);
                    System.Threading.Interlocked.Exchange(ref st.TotalTicks[i], 0);
                    System.Threading.Interlocked.Exchange(ref st.TotalCounts[i], 0);
                    System.Threading.Interlocked.Exchange(ref st.SessionPeakTicks[i], 0);
                }
            }

            private static int FindModuleIndex(KernelModuleRange[] mods, ulong routineAddr) {
                int lo = 0;
                int hi = mods.Length - 1;
                while (lo <= hi) {
                    int mid = (lo + hi) >> 1;
                    ulong start = mods[mid].BaseAddress;
                    if (routineAddr < start) {
                        hi = mid - 1;
                    } else if (routineAddr >= mods[mid].EndAddress) {
                        lo = mid + 1;
                    } else {
                        return mid;
                    }
                }
                return -1;
            }

            private static void OnEventRecord(IntPtr pEventRecord) {
                if (!_running || pEventRecord == IntPtr.Zero) return;

                ProfilerSessionState st = System.Threading.Volatile.Read(ref _sessionState);
                if (st == null || st.Modules.Length == 0) return;

                byte opcode = Marshal.ReadByte(pEventRecord, 45);
                if (opcode != 68 && opcode != 67 && opcode != 69 && opcode != 66 && opcode != 50) return;

                if (Marshal.ReadInt32(pEventRecord, 24) != PERFINFO_GUID_DATA1) return;

                ushort userDataLen = (ushort)Marshal.ReadInt16(pEventRecord, (IntPtr.Size == 8) ? 86 : 82);
                if (userDataLen < 16) return;

                IntPtr userData = Marshal.ReadIntPtr(pEventRecord, (IntPtr.Size == 8) ? 96 : 88);
                if (userData == IntPtr.Zero) return;

                long exitTs = Marshal.ReadInt64(pEventRecord, 16);
                long initTs = Marshal.ReadInt64(userData, 0);
                ulong routine = unchecked((ulong)Marshal.ReadInt64(userData, 8));
                if (routine < 0xFFFF000000000000UL) return;

                int idx = FindModuleIndex(st.Modules, routine);
                if (idx < 0) return;

                long delta = exitTs - initTs;
                if (delta < 0 || delta > _maxSaneTicks) delta = 0;

                System.Threading.Interlocked.Add(ref st.WindowTicks[idx], delta);
                System.Threading.Interlocked.Increment(ref st.WindowCounts[idx]);
                System.Threading.Interlocked.Add(ref st.TotalTicks[idx], delta);
                System.Threading.Interlocked.Increment(ref st.TotalCounts[idx]);

                long curPeak = System.Threading.Interlocked.Read(ref st.SessionPeakTicks[idx]);
                if (delta > curPeak) {
                    System.Threading.Interlocked.Exchange(ref st.SessionPeakTicks[idx], delta);
                }
            }

            private static IntPtr AllocTraceProperties(string sessionName, Guid sessionGuid, uint logFileMode) {
                int totalSize = 120 + 512;
                IntPtr ptr = Marshal.AllocHGlobal(totalSize);
                for (int i = 0; i < totalSize; i++) Marshal.WriteByte(ptr, i, 0);

                Marshal.WriteInt32(ptr, 0, totalSize);
                byte[] guidBytes = sessionGuid.ToByteArray();
                Marshal.Copy(guidBytes, 0, IntPtr.Add(ptr, 24), 16);
                Marshal.WriteInt32(ptr, 40, 1);
                Marshal.WriteInt32(ptr, 44, unchecked((int)WNODE_FLAG_TRACED_GUID));
                Marshal.WriteInt32(ptr, 48, 64);
                Marshal.WriteInt32(ptr, 52, 4);
                Marshal.WriteInt32(ptr, 56, 16);
                Marshal.WriteInt32(ptr, 64, unchecked((int)logFileMode));
                Marshal.WriteInt32(ptr, 68, 1);
                Marshal.WriteInt32(ptr, 72, unchecked((int)(EVENT_TRACE_FLAG_DPC | EVENT_TRACE_FLAG_INTERRUPT)));
                Marshal.WriteInt32(ptr, 116, 120);

                byte[] nameBytes = Encoding.Unicode.GetBytes(sessionName + "\0");
                Marshal.Copy(nameBytes, 0, IntPtr.Add(ptr, 120), nameBytes.Length);
                return ptr;
            }

            public static bool Start() {
                lock (_lifecycleLock) {
                    if (_running) return true;
                    if (IntPtr.Size != 8) return false;

                    long freq;
                    if (QueryPerformanceFrequency(out freq) && freq > 0) {
                        _qpcFreq = freq;
                        _maxSaneTicks = freq / 2;
                    }

                    LoadKernelModules();
                    ProfilerSessionState st = System.Threading.Volatile.Read(ref _sessionState);
                    if (st == null || st.Modules.Length == 0) return false;

                    _activeSessionName = "WinUltix_DpcProfiler";
                    Guid privGuid = Guid.NewGuid();
                    uint privMode = EVENT_TRACE_REAL_TIME_MODE | EVENT_TRACE_SYSTEM_LOGGER_MODE;
                    IntPtr props = AllocTraceProperties(_activeSessionName, privGuid, privMode);
                    uint status = 0;

                    try {
                        ControlTraceW(0, _activeSessionName, props, EVENT_TRACE_CONTROL_STOP);
                        Marshal.FreeHGlobal(props);
                        props = AllocTraceProperties(_activeSessionName, privGuid, privMode);
                        status = StartTraceW(out _sessionHandle, _activeSessionName, props);

                        if (status != 0) {
                            Marshal.FreeHGlobal(props);
                            _activeSessionName = "NT Kernel Logger";
                            props = AllocTraceProperties(_activeSessionName, SystemTraceControlGuid, EVENT_TRACE_REAL_TIME_MODE);
                            ControlTraceW(0, _activeSessionName, props, EVENT_TRACE_CONTROL_STOP);
                            Marshal.FreeHGlobal(props);
                            props = AllocTraceProperties(_activeSessionName, SystemTraceControlGuid, EVENT_TRACE_REAL_TIME_MODE);
                            status = StartTraceW(out _sessionHandle, _activeSessionName, props);
                        }
                    } finally {
                        Marshal.FreeHGlobal(props);
                    }

                    if (status != 0) return false;

                    IntPtr logfile = IntPtr.Zero;
                    IntPtr loggerNamePtr = IntPtr.Zero;
                    try {
                        logfile = Marshal.AllocHGlobal(448);
                        loggerNamePtr = Marshal.StringToHGlobalUni(_activeSessionName);
                        for (int i = 0; i < 448; i++) Marshal.WriteByte(logfile, i, 0);
                        Marshal.WriteIntPtr(logfile, 8, loggerNamePtr);
                        uint traceMode = PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD | PROCESS_TRACE_MODE_RAW_TIMESTAMP;
                        Marshal.WriteInt32(logfile, 28, unchecked((int)traceMode));
                        IntPtr cbPtr = Marshal.GetFunctionPointerForDelegate(_callbackDelegate);
                        Marshal.WriteIntPtr(logfile, 424, cbPtr);

                        _traceHandle = OpenTraceW(logfile);
                    } finally {
                        if (loggerNamePtr != IntPtr.Zero) Marshal.FreeHGlobal(loggerNamePtr);
                        if (logfile != IntPtr.Zero) Marshal.FreeHGlobal(logfile);
                    }

                    if (_traceHandle == 0 || _traceHandle == unchecked((ulong)-1L)) {
                        Stop();
                        return false;
                    }

                    long nowStart;
                    QueryPerformanceCounter(out nowStart);
                    System.Threading.Interlocked.Exchange(ref st.SessionStartQpc, nowStart);

                    _running = true;
                    ulong hTraceCopy = _traceHandle;
                    _workerThread = new System.Threading.Thread(delegate() {
                        try {
                            ProcessTrace(new ulong[] { hTraceCopy }, 1, IntPtr.Zero, IntPtr.Zero);
                        } catch { }
                    });
                    _workerThread.IsBackground = true;
                    _workerThread.Name = "WinUltix_EtwDpcWorker";
                    _workerThread.Start();
                    return true;
                }
            }

            public static void Stop() {
                lock (_lifecycleLock) {
                    _running = false;
                    if (_sessionHandle != 0 || !string.IsNullOrEmpty(_activeSessionName)) {
                        IntPtr props = AllocTraceProperties(_activeSessionName, SystemTraceControlGuid, EVENT_TRACE_REAL_TIME_MODE);
                        try { ControlTraceW(_sessionHandle, _activeSessionName, props, EVENT_TRACE_CONTROL_STOP); } catch { }
                        finally { Marshal.FreeHGlobal(props); }
                        _sessionHandle = 0;
                    }
                    if (_traceHandle != 0 && _traceHandle != unchecked((ulong)-1L)) {
                        try { CloseTrace(_traceHandle); } catch { }
                        _traceHandle = 0;
                    }
                    if (_workerThread != null && _workerThread.IsAlive) {
                        try { _workerThread.Join(1500); } catch { }
                        _workerThread = null;
                    }
                }
            }

            public static List<DriverLoadRecord> SampleDriverLoads() {
                var results = new List<DriverLoadRecord>();
                ProfilerSessionState st = System.Threading.Volatile.Read(ref _sessionState);
                if (!_running || st == null || st.Modules.Length == 0) return results;

                long nowQpc;
                QueryPerformanceCounter(out nowQpc);
                long startQpc = System.Threading.Interlocked.Read(ref st.SessionStartQpc);
                double elapsedSec = Math.Max(1.0, (double)(nowQpc - startQpc) / (double)_qpcFreq);
                int elapsedInt = Math.Max(1, (int)Math.Round(elapsedSec));

                double tickToUs = 1000000.0 / (double)_qpcFreq;
                for (int i = 0; i < st.Modules.Length; i++) {
                    long winTicks  = System.Threading.Interlocked.Exchange(ref st.WindowTicks[i], 0);
                    long winCounts = System.Threading.Interlocked.Exchange(ref st.WindowCounts[i], 0);
                    long totTicks  = System.Threading.Interlocked.Read(ref st.TotalTicks[i]);
                    long totCounts = System.Threading.Interlocked.Read(ref st.TotalCounts[i]);
                    long peakTicks = System.Threading.Interlocked.Read(ref st.SessionPeakTicks[i]);

                    if (totCounts > 0 || winCounts > 0 || peakTicks > 0) {
                        results.Add(new DriverLoadRecord {
                            DriverName  = st.Modules[i].DriverName,
                            ServiceKey  = st.Modules[i].ServiceKey,
                            UsPerSec    = Math.Round(winTicks * tickToUs, 1),
                            AvgUsPerSec = Math.Round((totTicks * tickToUs) / elapsedSec, 1),
                            MaxPeakUs   = Math.Round(peakTicks * tickToUs, 1),
                            CallsPerSec = winCounts,
                            TotalCalls  = totCounts,
                            ElapsedSec  = elapsedInt
                        });
                    }
                }
                return results;
            }
        }

        // Native CfgMgr32 PnP Device Tree Walker & Node Status Inspector (<5ms)
        public static class PnpTree {
            private const uint DN_HAS_PROBLEM = 0x00000400;
            private const uint CM_PROB_DISABLED = 22;

            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            private static extern int CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);

            [DllImport("cfgmgr32.dll")]
            private static extern int CM_Get_Parent(out uint pdnDevInst, uint dnDevInst, uint ulFlags);

            [DllImport("cfgmgr32.dll")]
            private static extern int CM_Get_Child(out uint pdnDevInst, uint dnDevInst, uint ulFlags);

            [DllImport("cfgmgr32.dll")]
            private static extern int CM_Get_Sibling(out uint pdnDevInst, uint dnDevInst, uint ulFlags);

            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            private static extern int CM_Get_Device_IDW(uint dnDevInst, StringBuilder Buffer, int BufferLen, uint ulFlags);

            [DllImport("cfgmgr32.dll")]
            private static extern int CM_Get_DevNode_Status(out uint pulStatus, out uint pulProblemNumber, uint dnDevInst, uint ulFlags);

            public static string GetDeviceId(uint devInst) {
                var sb = new StringBuilder(512);
                if (CM_Get_Device_IDW(devInst, sb, sb.Capacity, 0) == 0) return sb.ToString();
                return "";
            }

            // Returns -1 if node does not exist, 0 if active/healthy, or CM_PROB_* code (e.g., 22 = Disabled)
            public static int GetDeviceConfigStatus(string instanceId) {
                if (string.IsNullOrEmpty(instanceId)) return -1;
                uint devInst;
                if (CM_Locate_DevNodeW(out devInst, instanceId, 0) != 0) return -1;
                uint status, problem;
                if (CM_Get_DevNode_Status(out status, out problem, devInst, 0) != 0) return -1;
                if ((status & DN_HAS_PROBLEM) != 0) return (int)problem;
                return 0;
            }

            public static bool IsDeviceDisabled(string instanceId) {
                return GetDeviceConfigStatus(instanceId) == (int)CM_PROB_DISABLED;
            }

            public static List<string> GetParentChain(string instanceId) {
                var chain = new List<string>();
                uint cur;
                if (CM_Locate_DevNodeW(out cur, instanceId, 0) != 0) return chain;
                uint parent;
                int guard = 0;
                while (guard++ < 32 && CM_Get_Parent(out parent, cur, 0) == 0) {
                    string pid = GetDeviceId(parent);
                    if (string.IsNullOrEmpty(pid)) break;
                    chain.Add(pid);
                    cur = parent;
                }
                return chain;
            }

            private static void CollectDescendants(uint devInst, int depth, List<string> output) {
                if (depth > 16) return;
                uint child;
                if (CM_Get_Child(out child, devInst, 0) != 0) return;

                uint cur = child;
                int guard = 0;
                while (guard++ < 256) {
                    string id = GetDeviceId(cur);
                    if (!string.IsNullOrEmpty(id)) {
                        output.Add(depth.ToString() + "|" + id);
                        CollectDescendants(cur, depth + 1, output);
                    }
                    uint sibling;
                    if (CM_Get_Sibling(out sibling, cur, 0) != 0) break;
                    cur = sibling;
                }
            }

            public static List<string> GetDescendants(string instanceId) {
                var list = new List<string>();
                uint root;
                if (CM_Locate_DevNodeW(out root, instanceId, 0) != 0) return list;
                CollectDescendants(root, 1, list);
                return list;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct DEVPROPKEY {
                public Guid fmtid;
                public uint pid;
            }

            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            private static extern int CM_Get_DevNode_PropertyW(
                uint dnDevInst,
                ref DEVPROPKEY PropertyKey,
                out uint PropertyType,
                IntPtr PropertyBuffer,
                ref uint PropertyBufferSize,
                uint ulFlags);

            private static readonly Guid GUID_PCI_DEVICE = new Guid("3ab22e31-8264-4b4e-9af5-a8d2d8e33e62");

            private static int ReadPciDevPropInt(uint devInst, uint pid) {
                DEVPROPKEY key = new DEVPROPKEY { fmtid = GUID_PCI_DEVICE, pid = pid };
                uint propType = 0;
                uint bufSize  = 8;
                IntPtr buf = Marshal.AllocHGlobal(8);
                try {
                    Marshal.WriteInt64(buf, 0, 0L);
                    if (CM_Get_DevNode_PropertyW(devInst, ref key, out propType, buf, ref bufSize, 0) == 0 && bufSize > 0) {
                        if (bufSize == 1) return Marshal.ReadByte(buf, 0);
                        if (bufSize == 2) return Marshal.ReadInt16(buf, 0);
                        return Marshal.ReadInt32(buf, 0);
                    }
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
                return 0;
            }

            public static string GetPcieLinkInfo(string instanceId) {
                if (string.IsNullOrEmpty(instanceId)) return "";
                uint devInst;
                if (CM_Locate_DevNodeW(out devInst, instanceId, 0) != 0) return "";

                // DEVPKEY_PciDevice: 9=CurrentLinkSpeed, 10=CurrentLinkWidth, 11=MaxLinkSpeed, 12=MaxLinkWidth
                int curSpeed = ReadPciDevPropInt(devInst, 9);
                int curWidth = ReadPciDevPropInt(devInst, 10);
                int maxSpeed = ReadPciDevPropInt(devInst, 11);
                int maxWidth = ReadPciDevPropInt(devInst, 12);

                int effSpeed = Math.Max(curSpeed, maxSpeed);
                int effWidth = (curWidth > 0) ? curWidth : maxWidth;
                if (effSpeed <= 0 && effWidth <= 0) return "";

                string genStr = "";
                switch (effSpeed) {
                    case 1: genStr = "1.0"; break;
                    case 2: genStr = "2.0"; break;
                    case 3: genStr = "3.0"; break;
                    case 4: genStr = "4.0"; break;
                    case 5: genStr = "5.0"; break;
                    case 6: genStr = "6.0"; break;
                }

                string prefix = string.IsNullOrEmpty(genStr) ? "PCIe" : ("PCIe " + genStr);
                if (curWidth > 0 && maxWidth > 0 && curWidth < maxWidth) {
                    return string.Format("{0} x{1} (Max: x{2})", prefix, curWidth, maxWidth);
                }
                if (effWidth > 0) {
                    return string.Format("{0} x{1}", prefix, effWidth);
                }
                return prefix;
            }
        }

        // Native USBHUB3 IOCTL & BusReportedDeviceDesc Prober
        public class HubProbeResult {
            public int TotalPorts;
            public int Usb2Ports;
            public int Usb3Ports;
            public int SsPlusPorts;
            public int ActivePorts;
            public Dictionary<int, string> PortSpeeds = new Dictionary<int, string>();
        }

        public static class UsbProberV2 {
            [StructLayout(LayoutKind.Sequential)]
            private struct DEVPROPKEY {
                public Guid fmtid;
                public uint pid;
            }

            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            private static extern int CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);

            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            private static extern int CM_Get_DevNode_PropertyW(
                uint dnDevInst,
                ref DEVPROPKEY PropertyKey,
                out uint PropertyType,
                IntPtr PropertyBuffer,
                ref uint PropertyBufferSize,
                uint ulFlags);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern IntPtr CreateFileW(
                string lpFileName, uint dwDesiredAccess, uint dwShareMode,
                IntPtr lpSecurityAttributes, uint dwCreationDisposition,
                uint dwFlagsAndAttributes, IntPtr hTemplateFile);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool DeviceIoControl(
                IntPtr hDevice, uint dwIoControlCode,
                IntPtr lpInBuffer, uint nInBufferSize,
                IntPtr lpOutBuffer, uint nOutBufferSize,
                out uint lpBytesReturned, IntPtr lpOverlapped);

            [DllImport("kernel32.dll")]
            private static extern bool CloseHandle(IntPtr hObject);

            private const uint GENERIC_WRITE = 0x40000000;
            private const uint FILE_SHARE_READ = 0x00000001;
            private const uint FILE_SHARE_WRITE = 0x00000002;
            private const uint OPEN_EXISTING = 3;

            private const uint IOCTL_USB_GET_NODE_INFORMATION = 0x00220408;
            private const uint IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX = 0x00220448;
            private const uint IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX_V2 = 0x0022045C;

            // DEVPKEY_Device_BusReportedDeviceDesc ({540b947e-8b40-45bc-a8a2-6a0b894cbda2}, 4)
            private static DEVPROPKEY KEY_BUS_REPORTED_DESC = new DEVPROPKEY {
                fmtid = new Guid("540b947e-8b40-45bc-a8a2-6a0b894cbda2"),
                pid = 4
            };

            public static string GetBusReportedDesc(string instanceId) {
                uint devInst;
                if (CM_Locate_DevNodeW(out devInst, instanceId, 0) != 0) return "";

                uint propType = 0;
                uint bufSize = 512;
                IntPtr buf = Marshal.AllocHGlobal((int)bufSize);
                try {
                    int cr = CM_Get_DevNode_PropertyW(devInst, ref KEY_BUS_REPORTED_DESC, out propType, buf, ref bufSize, 0);
                    if (cr == 0 && propType == 18 && bufSize > 2) {
                        string val = Marshal.PtrToStringUni(buf);
                        return (val != null) ? val.Trim() : "";
                    }
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
                return "";
            }

            public static HubProbeResult ProbeHub(string hubInstanceId) {
                if (string.IsNullOrEmpty(hubInstanceId)) return new HubProbeResult();
                if (PnpTree.GetDeviceConfigStatus(hubInstanceId) != 0) return new HubProbeResult();

                HubProbeResult result = new HubProbeResult();
                System.Threading.Thread worker = new System.Threading.Thread(delegate() {
                    result = ProbeHubCore(hubInstanceId);
                });
                worker.IsBackground = true;
                worker.Name = "WinUltix_UsbHubProbe";
                worker.Start();

                if (!worker.Join(350)) {
                    return new HubProbeResult();
                }
                return result;
            }

            private static HubProbeResult ProbeHubCore(string hubInstanceId) {
                var res = new HubProbeResult();
                string symPath = @"\\?\" + hubInstanceId.Replace('\\', '#') + "#{f18a0e88-c30c-11d0-8815-00a0c906bed8}";
                IntPtr hHub = CreateFileW(symPath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (hHub == IntPtr.Zero || hHub == new IntPtr(-1)) {
                    hHub = CreateFileW(symPath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                }
                if (hHub == IntPtr.Zero || hHub == new IntPtr(-1)) return res;

                IntPtr bufNode = IntPtr.Zero;
                IntPtr bufV2   = IntPtr.Zero;
                IntPtr bufEx   = IntPtr.Zero;

                try {
                    bufNode = Marshal.AllocHGlobal(128);
                    bufV2   = Marshal.AllocHGlobal(32);
                    bufEx   = Marshal.AllocHGlobal(64);

                    for (int i = 0; i < 128; i++) Marshal.WriteByte(bufNode, i, 0);
                    uint ret = 0;
                    if (!DeviceIoControl(hHub, IOCTL_USB_GET_NODE_INFORMATION, bufNode, 76, bufNode, 76, out ret, IntPtr.Zero)) {
                        return res;
                    }

                    int numPorts = Marshal.ReadByte(bufNode, 6);
                    if (numPorts <= 0 || numPorts > 127) return res;
                    res.TotalPorts = numPorts;

                    for (int p = 1; p <= numPorts; p++) {
                        for (int i = 0; i < 16; i++) Marshal.WriteByte(bufV2, i, 0);
                        Marshal.WriteInt32(bufV2, 0, p);
                        Marshal.WriteInt32(bufV2, 4, 16);
                        Marshal.WriteInt32(bufV2, 8, 7);

                        uint protocols = 0;
                        uint v2Flags   = 0;
                        if (DeviceIoControl(hHub, IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX_V2, bufV2, 16, bufV2, 16, out ret, IntPtr.Zero)) {
                            protocols = (uint)Marshal.ReadInt32(bufV2, 8);
                            v2Flags   = (uint)Marshal.ReadInt32(bufV2, 12);
                            if ((protocols & 0x04) != 0) {
                                res.Usb3Ports++;
                                if ((v2Flags & 0x08) != 0 || (v2Flags & 0x04) != 0) res.SsPlusPorts++;
                            } else if ((protocols & 0x02) != 0) {
                                res.Usb2Ports++;
                            }
                        }

                        for (int i = 0; i < 64; i++) Marshal.WriteByte(bufEx, i, 0);
                        Marshal.WriteInt32(bufEx, 0, p);
                        if (DeviceIoControl(hHub, IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX, bufEx, 35, bufEx, 35, out ret, IntPtr.Zero)) {
                            ushort bcdUsb   = (ushort)Marshal.ReadInt16(bufEx, 6);
                            byte speed      = Marshal.ReadByte(bufEx, 23);
                            uint connStatus = (uint)Marshal.ReadInt32(bufEx, 31);
                            if (connStatus == 1) {
                                res.ActivePorts++;

                                bool isDedicatedSsPort = ((protocols & 0x04) != 0 && (protocols & 0x02) == 0);
                                bool isOperatingSsPlus = ((v2Flags & 0x04) != 0) || (speed >= 4);
                                bool isOperatingSs     = ((v2Flags & 0x01) != 0) || (speed >= 3) || isDedicatedSsPort || (bcdUsb >= 0x0300);
                                bool isSsCapableDevice = ((v2Flags & 0x02) != 0) || ((v2Flags & 0x08) != 0);

                                string speedStr = "USB";
                                if (isOperatingSsPlus || (isOperatingSs && bcdUsb >= 0x0320)) {
                                    speedStr = (bcdUsb >= 0x0320) ? "20 Gbps SS+" : "10 Gbps SS+";
                                } else if (isOperatingSs && bcdUsb >= 0x0310) {
                                    speedStr = ((v2Flags & 0x08) != 0 || isDedicatedSsPort) ? "10 Gbps SS+" : "5 Gbps SS";
                                } else if (isOperatingSs) {
                                    speedStr = "5 Gbps SS";
                                } else if (speed == 2) {
                                    speedStr = isSsCapableDevice ? "480 Mbps HS [Throttled USB 3.x!]" : "480 Mbps HS";
                                } else if (speed == 1) {
                                    speedStr = "12 Mbps FS";
                                } else if (speed == 0) {
                                    speedStr = "1.5 Mbps LS";
                                }
                                res.PortSpeeds[p] = speedStr;
                            }
                        }
                    }
                } catch { } finally {
                    if (bufNode != IntPtr.Zero) Marshal.FreeHGlobal(bufNode);
                    if (bufV2 != IntPtr.Zero) Marshal.FreeHGlobal(bufV2);
                    if (bufEx != IntPtr.Zero) Marshal.FreeHGlobal(bufEx);
                    CloseHandle(hHub);
                }
                return res;
            }
        }

        // Owner-Drawn Dark TabControl (Eliminates Win32 white 3D borders & gray headers)
        public class DarkTabControl : TabControl {
            [StructLayout(LayoutKind.Sequential)]
            private struct RECT {
                public int Left, Top, Right, Bottom;
            }

            private const int TCM_ADJUSTRECT = 0x1328;
            private int _hoverIndex = -1;

            public DarkTabControl() {
                this.SetStyle(
                    ControlStyles.UserPaint |
                    ControlStyles.ResizeRedraw |
                    ControlStyles.AllPaintingInWmPaint |
                    ControlStyles.OptimizedDoubleBuffer,
                    true);
                this.DoubleBuffered = true;
                this.SizeMode = TabSizeMode.Fixed;
                this.ItemSize = new Size(57, 22);
            }

            protected override void WndProc(ref Message m) {
                if (m.Msg == TCM_ADJUSTRECT && !this.DesignMode) {
                    RECT rc = (RECT)Marshal.PtrToStructure(m.LParam, typeof(RECT));
                    rc.Left   -= 3;
                    rc.Right  += 3;
                    rc.Top    -= 1;
                    rc.Bottom += 3;
                    Marshal.StructureToPtr(rc, m.LParam, true);
                }
                base.WndProc(ref m);
            }

            protected override void OnMouseMove(MouseEventArgs e) {
                base.OnMouseMove(e);
                int newHover = -1;
                for (int i = 0; i < this.TabCount; i++) {
                    if (this.GetTabRect(i).Contains(e.Location)) {
                        newHover = i;
                        break;
                    }
                }
                if (newHover != _hoverIndex) {
                    _hoverIndex = newHover;
                    this.Invalidate();
                }
            }

            protected override void OnMouseLeave(EventArgs e) {
                base.OnMouseLeave(e);
                if (_hoverIndex != -1) {
                    _hoverIndex = -1;
                    this.Invalidate();
                }
            }

            protected override void OnPaint(PaintEventArgs e) {
                Graphics g = e.Graphics;
                g.Clear(Color.FromArgb(30, 30, 30));

                if (this.TabCount <= 0) return;

                Rectangle bodyRect   = this.DisplayRectangle;
                Rectangle borderRect = new Rectangle(bodyRect.X - 1, bodyRect.Y - 1, bodyRect.Width + 1, bodyRect.Height + 1);
                using (Pen borderPen = new Pen(Color.FromArgb(65, 65, 65), 1)) {
                    g.DrawRectangle(borderPen, borderRect);
                }

                for (int i = 0; i < this.TabCount; i++) {
                    Rectangle tabRect = this.GetTabRect(i);
                    bool isSelected = (i == this.SelectedIndex);
                    bool isHovered  = (i == _hoverIndex);

                    Color backColor = isSelected
                        ? Color.FromArgb(40, 40, 42)
                        : (isHovered ? Color.FromArgb(34, 34, 36) : Color.FromArgb(22, 22, 22));

                    using (SolidBrush bgBrush = new SolidBrush(backColor)) {
                        g.FillRectangle(bgBrush, tabRect);
                    }

                    using (Pen tabPen = new Pen(Color.FromArgb(60, 60, 60), 1)) {
                        g.DrawRectangle(tabPen, tabRect.X, tabRect.Y, tabRect.Width - 1, tabRect.Height - 1);
                    }

                    if (isSelected) {
                        using (SolidBrush accentBrush = new SolidBrush(Color.FromArgb(80, 180, 255))) {
                            g.FillRectangle(accentBrush, tabRect.X + 1, tabRect.Y + 1, tabRect.Width - 2, 3);
                        }
                    }

                    Color textColor = isSelected
                        ? Color.White
                        : (isHovered ? Color.LightSkyBlue : Color.Silver);

                    Rectangle textRect = new Rectangle(tabRect.X, tabRect.Y + 1, tabRect.Width, tabRect.Height - 1);
                    TextRenderer.DrawText(
                        g,
                        this.TabPages[i].Text,
                        this.Font,
                        textRect,
                        textColor,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
                }
            }
        }

        // Custom GDI+ Flat Dark ProgressBar with Cached Font & Centered Percentage Readout
        public class DarkProgressBar : ProgressBar {
            private static readonly Font StatusFont = new Font("Consolas", 9.0f, FontStyle.Bold);

            public DarkProgressBar() {
                this.SetStyle(
                    ControlStyles.UserPaint |
                    ControlStyles.ResizeRedraw |
                    ControlStyles.AllPaintingInWmPaint |
                    ControlStyles.OptimizedDoubleBuffer,
                    true);
                this.DoubleBuffered = true;
            }

            protected override void OnPaint(PaintEventArgs e) {
                Graphics g = e.Graphics;
                Rectangle rect = this.ClientRectangle;

                using (SolidBrush bgBrush = new SolidBrush(Color.FromArgb(20, 20, 20))) {
                    g.FillRectangle(bgBrush, rect);
                }

                double range = Math.Max(1, this.Maximum - this.Minimum);
                double pct   = Math.Max(0.0, Math.Min(1.0, (double)(this.Value - this.Minimum) / range));

                if (this.Value > 0 && rect.Width > 2 && rect.Height > 2) {
                    int fillWidth = (int)Math.Round((rect.Width - 2) * pct);
                    if (fillWidth > 0) {
                        Rectangle fillRect = new Rectangle(1, 1, fillWidth, rect.Height - 2);
                        using (SolidBrush fillBrush = new SolidBrush(Color.FromArgb(45, 105, 165))) {
                            g.FillRectangle(fillBrush, fillRect);
                        }
                        if (rect.Height > 4) {
                            using (SolidBrush topGlow = new SolidBrush(Color.FromArgb(75, 145, 210))) {
                                g.FillRectangle(topGlow, 1, 1, fillWidth, 2);
                            }
                        }
                    }
                }

                using (Pen borderPen = new Pen(Color.FromArgb(65, 65, 65), 1)) {
                    g.DrawRectangle(borderPen, 0, 0, rect.Width - 1, rect.Height - 1);
                }

                string statusText = (this.Value > 0)
                    ? string.Format("{0}%", (int)Math.Round(pct * 100.0))
                    : "READY";
                Color textColor = (this.Value > 0) ? Color.White : Color.FromArgb(115, 115, 115);

                TextRenderer.DrawText(
                    g,
                    statusText,
                    StatusFont,
                    rect,
                    textColor,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
            }
        }

        // Thread-Safe Win32 Live Expert Command & Output Console (AllocConsole + Unified Dark Theme & Geometry)
        public static class ExpertConsole {
            [StructLayout(LayoutKind.Sequential)]
            private struct COORD {
                public short X;
                public short Y;
                public COORD(short x, short y) { X = x; Y = y; }
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct SMALL_RECT {
                public short Left;
                public short Top;
                public short Right;
                public short Bottom;
                public SMALL_RECT(short l, short t, short r, short b) { Left = l; Top = t; Right = r; Bottom = b; }
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct CONSOLE_SCREEN_BUFFER_INFO_EX {
                public uint cbSize;
                public COORD dwSize;
                public COORD dwCursorPosition;
                public ushort wAttributes;
                public SMALL_RECT srWindow;
                public COORD dwMaximumWindowSize;
                public ushort wPopupAttributes;
                public bool bFullscreenSupported;
                [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
                public uint[] ColorTable;
            }

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool AllocConsole();

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern IntPtr GetConsoleWindow();

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern IntPtr GetStdHandle(int nStdHandle);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool SetConsoleTitleW(string lpConsoleTitle);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern bool WriteConsoleW(IntPtr hConsoleOutput, string lpBuffer, uint nNumberOfCharsToWrite, out uint lpNumberOfCharsWritten, IntPtr lpReserved);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool GetConsoleScreenBufferInfoEx(IntPtr hConsoleOutput, ref CONSOLE_SCREEN_BUFFER_INFO_EX lpConsoleScreenBufferInfoEx);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool SetConsoleScreenBufferInfoEx(IntPtr hConsoleOutput, ref CONSOLE_SCREEN_BUFFER_INFO_EX lpConsoleScreenBufferInfoEx);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool SetConsoleTextAttribute(IntPtr hConsoleOutput, ushort wAttributes);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool FillConsoleOutputAttribute(IntPtr hConsoleOutput, ushort wAttribute, uint nLength, COORD dwWriteCoord, out uint lpNumberOfAttrsWritten);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool SetConsoleScreenBufferSize(IntPtr hConsoleOutput, COORD dwSize);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool SetConsoleWindowInfo(IntPtr hConsoleOutput, bool bAbsolute, ref SMALL_RECT lpConsoleWindow);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern COORD GetLargestConsoleWindowSize(IntPtr hConsoleOutput);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool DeleteMenu(IntPtr hMenu, uint uPosition, uint uFlags);

            private delegate bool ConsoleCtrlDelegate(uint ctrlType);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate handler, bool add);

            private const int STD_INPUT_HANDLE = -10;
            private const int STD_OUTPUT_HANDLE = -11;
            private const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
            private const uint ENABLE_MOUSE_INPUT = 0x0010;
            private const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
            private const uint ENABLE_EXTENDED_FLAGS = 0x0080;
            private const int SW_HIDE = 0;
            private const int SW_SHOW = 5;
            private const uint SC_CLOSE = 0xF060;
            private const uint MF_BYCOMMAND = 0x00000000;

            private static volatile bool _visible = false;
            private static bool _initialized = false;
            private static readonly object _stateLock = new object();
            private static readonly object _writeLock = new object();
            private static readonly ConsoleCtrlDelegate _ctrlHandler = new ConsoleCtrlDelegate(OnConsoleCtrl);

            private static bool OnConsoleCtrl(uint ctrlType) {
                if (ctrlType == 2) {
                    SetVisible(false);
                    return true;
                }
                return false;
            }

            private static void ApplyDarkThemeAndGeometry(IntPtr hOut) {
                if (hOut == IntPtr.Zero || hOut == new IntPtr(-1)) return;

                COORD maxWin = GetLargestConsoleWindowSize(hOut);
                short cols = (maxWin.X > 20) ? (short)Math.Min(136, maxWin.X - 2) : (short)120;
                short rows = (maxWin.Y > 12) ? (short)Math.Min(34, maxWin.Y - 2) : (short)30;
                short bufRows = 3000;

                CONSOLE_SCREEN_BUFFER_INFO_EX csbi = new CONSOLE_SCREEN_BUFFER_INFO_EX();
                csbi.cbSize = (uint)Marshal.SizeOf(typeof(CONSOLE_SCREEN_BUFFER_INFO_EX));
                if (GetConsoleScreenBufferInfoEx(hOut, ref csbi)) {
                    if (csbi.ColorTable == null || csbi.ColorTable.Length < 16) {
                        csbi.ColorTable = new uint[16];
                    }
                    // COLORREF format: 0x00BBGGRR — override slots 0, 1 (Blue) & 5 (PowerShell #012456 bg)
                    csbi.ColorTable[0]  = 0x00121212; // Background: #121212
                    csbi.ColorTable[1]  = 0x00121212; // Standard Dark Blue -> #121212
                    csbi.ColorTable[5]  = 0x00121212; // PowerShell Default Bg Slot 5 -> #121212
                    csbi.ColorTable[7]  = 0x00E0E0E0; // Default Foreground: #E0E0E0
                    csbi.ColorTable[8]  = 0x00857D78; // ANSI 90 (Bright Black / Gray)
                    csbi.ColorTable[12] = 0x005555FF; // ANSI 91 (Bright Red)
                    csbi.ColorTable[14] = 0x0055E6FF; // ANSI 93 (Bright Yellow/Amber)
                    csbi.wAttributes    = 0x0007;
                    csbi.dwSize         = new COORD(cols, bufRows);
                    csbi.srWindow       = new SMALL_RECT(0, 0, cols, rows);
                    SetConsoleScreenBufferInfoEx(hOut, ref csbi);
                }

                SMALL_RECT tinyRect = new SMALL_RECT(0, 0, 1, 1);
                SMALL_RECT winRect  = new SMALL_RECT(0, 0, (short)(cols - 1), (short)(rows - 1));
                SetConsoleWindowInfo(hOut, true, ref tinyRect);
                SetConsoleScreenBufferSize(hOut, new COORD(cols, bufRows));
                SetConsoleWindowInfo(hOut, true, ref winRect);

                // Update active text attribute & VT default reset target, then repaint all existing buffer cells
                SetConsoleTextAttribute(hOut, 0x0007);
                uint written;
                FillConsoleOutputAttribute(hOut, 0x0007, (uint)(cols * bufRows), new COORD(0, 0), out written);
            }

            public static bool IsVisible {
                get { return _visible; }
            }

            public static bool Toggle() {
                SetVisible(!_visible);
                return _visible;
            }

            public static void SetVisible(bool show) {
                lock (_stateLock) {
                    IntPtr hWnd = GetConsoleWindow();
                    if (show) {
                        if (hWnd == IntPtr.Zero) {
                            AllocConsole();
                            hWnd = GetConsoleWindow();
                        }
                        if (hWnd != IntPtr.Zero && !_initialized) {
                            SetConsoleTitleW("WinUltix - Live Expert Command & Output Stream");
                            SetConsoleCtrlHandler(_ctrlHandler, true);
                            IntPtr hMenu = GetSystemMenu(hWnd, false);
                            if (hMenu != IntPtr.Zero) {
                                DeleteMenu(hMenu, SC_CLOSE, MF_BYCOMMAND);
                            }
                            IntPtr hOut = GetStdHandle(STD_OUTPUT_HANDLE);
                            uint outMode;
                            if (hOut != IntPtr.Zero && GetConsoleMode(hOut, out outMode)) {
                                SetConsoleMode(hOut, outMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
                            }
                            ApplyDarkThemeAndGeometry(hOut);

                            IntPtr hIn = GetStdHandle(STD_INPUT_HANDLE);
                            uint inMode;
                            if (hIn != IntPtr.Zero && GetConsoleMode(hIn, out inMode)) {
                                uint cleanIn = (inMode & ~(ENABLE_QUICK_EDIT_MODE | ENABLE_MOUSE_INPUT)) | ENABLE_EXTENDED_FLAGS;
                                SetConsoleMode(hIn, cleanIn);
                            }
                            _initialized = true;
                        }
                        if (hWnd != IntPtr.Zero) {
                            ShowWindow(hWnd, SW_SHOW);
                        }
                        _visible = true;
                    } else {
                        if (hWnd != IntPtr.Zero) {
                            ShowWindow(hWnd, SW_HIDE);
                        }
                        _visible = false;
                    }
                }
            }

            public static void WriteLine(string text, string ansiColor) {
                if (!_visible || string.IsNullOrEmpty(text)) return;
                lock (_writeLock) {
                    IntPtr hOut = GetStdHandle(STD_OUTPUT_HANDLE);
                    if (hOut == IntPtr.Zero || hOut == new IntPtr(-1)) return;
                    // Reset only foreground (SGR 39) so background remains locked to attribute 0 (#121212)
                    string payload = "\x1b[" + ansiColor + "m" + text + "\x1b[39m\r\n";
                    uint written;
                    WriteConsoleW(hOut, payload, (uint)payload.Length, out written, IntPtr.Zero);
                }
            }
        }
    }
"@ -ErrorAction SilentlyContinue
}

function Read-HighResBitmapFromIco {
    param([Parameter(Mandatory=$true)][string]$IcoFilePath)
    try {
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($IcoFilePath)
        if ($bytes.Length -lt 22) { return $null }

        $count = [BitConverter]::ToUInt16($bytes, 4)
        $bestOffset = 0
        $bestLength = 0
        $bestDim    = -1

        for ($i = 0; $i -lt $count; $i++) {
            $entryPos = 6 + ($i * 16)
            if (($entryPos + 16) -gt $bytes.Length) { break }
            $w = [int]$bytes[$entryPos]
            if ($w -eq 0) { $w = 256 }
            $len = [BitConverter]::ToInt32($bytes, $entryPos + 8)
            $off = [BitConverter]::ToInt32($bytes, $entryPos + 12)

            if ($w -ge $bestDim -and ($off + $len) -le $bytes.Length) {
                $bestDim    = $w
                $bestOffset = $off
                $bestLength = $len
            }
        }

        if ($bestLength -gt 8) {
            # Check for PNG signature (89 50 4E 47) inside the largest .ico frame
            if ($bytes[$bestOffset] -eq 0x89 -and $bytes[$bestOffset + 1] -eq 0x50 -and $bytes[$bestOffset + 2] -eq 0x4E -and $bytes[$bestOffset + 3] -eq 0x47) {
                $ms = New-Object System.IO.MemoryStream($bytes, $bestOffset, $bestLength)
                $img = [System.Drawing.Image]::FromStream($ms)
                $bmp = New-Object System.Drawing.Bitmap($img)
                $img.Dispose()
                $ms.Dispose()
                return $bmp
            }
        }

        $icoLarge = New-Object System.Drawing.Icon($IcoFilePath, 256, 256)
        $bmpFallback = $icoLarge.ToBitmap()
        $icoLarge.Dispose()
        return $bmpFallback
    } catch {
        return $null
    }
}

function Initialize-WinUltixIcon {
    if ($null -ne $global:UltixAppIcon) { return }
    try {
        # 1. Compiled Standalone .EXE Mode: Check WINULTIX_HOST_EXE passed by C# wrapper or own process PE header
        $hostExe = if (-not [string]::IsNullOrWhiteSpace($env:WINULTIX_HOST_EXE) -and (Test-Path -LiteralPath $env:WINULTIX_HOST_EXE)) {
            $env:WINULTIX_HOST_EXE
        } else {
            [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        }

        if ($hostExe -and $hostExe -notmatch '(?i)(powershell|pwsh|ise)\.exe$' -and (Test-Path -LiteralPath $hostExe)) {
            $global:UltixAppIcon     = [System.Drawing.Icon]::ExtractAssociatedIcon($hostExe)
            $global:UltixHighResLogo = [WinUltix.NativeMethods]::ExtractHighResExeIcon($hostExe, 256)
            if ($null -eq $global:UltixHighResLogo) {
                $global:UltixHighResLogo = [WinUltix.NativeMethods]::ExtractHighResExeIcon($hostExe, 64)
            }
            if ($null -ne $global:UltixAppIcon) { return }
        }

        # 2. Local Script Mode (src\ or build\): Resolve single root X:\assets\WinUltix.ico
        $resolvedIco = $null
        if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
            $parentDir = Split-Path -Path $ScriptDir -Parent
            foreach ($cand in @((Join-Path $ScriptDir "assets\WinUltix.ico"), (Join-Path $parentDir "assets\WinUltix.ico"))) {
                if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path -LiteralPath $cand)) {
                    if ((Get-Item -LiteralPath $cand -ErrorAction SilentlyContinue).Length -gt 1024) {
                        $resolvedIco = $cand
                        break
                    }
                }
            }
        }

        # 3. Memory-Only 'irm | iex' Mode: Validate cache & download into RAM buffer before writing to disk
        if ([string]::IsNullOrWhiteSpace($resolvedIco)) {
            $cacheDir = Join-Path $env:LOCALAPPDATA "WinUltix"
            $cacheIco = Join-Path $cacheDir "WinUltix.ico"

            # Purge poisoned 0-byte / corrupted cache file left by previous failed DownloadFile call
            if (Test-Path -LiteralPath $cacheIco) {
                if ((Get-Item -LiteralPath $cacheIco -Force -ErrorAction SilentlyContinue).Length -le 1024) {
                    Remove-Item -LiteralPath $cacheIco -Force -ErrorAction SilentlyContinue
                }
            }

            if (-not (Test-Path -LiteralPath $cacheIco)) {
                try {
                    if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null }
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                    $wc = New-Object System.Net.WebClient
                    $urls = @(
                        "https://raw.githubusercontent.com/Firever-ultix/WinUltix/main/assets/WinUltix.ico",
                        "https://raw.githubusercontent.com/Firever-ultix/WinUltix/main/assets/winultix.ico"
                    )
                    foreach ($url in $urls) {
                        try {
                            [byte[]]$icoBytes = $wc.DownloadData($url)
                            # Verify valid Win32 ICONDIR magic header (00 00 01 00) and size > 1 KB
                            if ($null -ne $icoBytes -and $icoBytes.Length -gt 1024 -and $icoBytes[0] -eq 0 -and $icoBytes[1] -eq 0 -and $icoBytes[2] -eq 1 -and $icoBytes[3] -eq 0) {
                                [System.IO.File]::WriteAllBytes($cacheIco, $icoBytes)
                                break
                            }
                        } catch { }
                    }
                    $wc.Dispose()
                } catch { }
            }

            if ((Test-Path -LiteralPath $cacheIco) -and (Get-Item -LiteralPath $cacheIco -Force -ErrorAction SilentlyContinue).Length -gt 1024) {
                $resolvedIco = $cacheIco
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($resolvedIco)) {
            $global:UltixAppIcon     = New-Object System.Drawing.Icon($resolvedIco, 32, 32)
            $global:UltixHighResLogo = Read-HighResBitmapFromIco -IcoFilePath $resolvedIco
        }
    } catch { }
}

function Enable-WinUltixDarkTitleBar {
    param([Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Form)
    try {
        [WinUltix.NativeMethods]::EnableDarkTitleBar($Form.Handle)
        Initialize-WinUltixIcon
        if ($null -ne $global:UltixAppIcon) {
            $Form.Icon = $global:UltixAppIcon
        }
    } catch { }
}

function Enable-UltixDoubleBuffer {
    param([Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Control)
    try {
        $propInfo = $Control.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
        if ($null -ne $propInfo) { $propInfo.SetValue($Control, $true, $null) }
    } catch { }
}

# ------------------------------------------
# 2. SHARED SYSTEM & WORKER UTILITIES (AUTO-INJECTED INTO RUNSPACES)
# ------------------------------------------
function Get-UltixUserProfiles {
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenSids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $profListRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    if (Test-Path -LiteralPath $profListRoot) {
        foreach ($subKey in (Get-ChildItem -LiteralPath $profListRoot -ErrorAction SilentlyContinue)) {
            $sid = $subKey.PSChildName
            if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { continue }

            $rawPath = (Get-ItemProperty -LiteralPath $subKey.PSPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
            if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }

            $localPath = [System.Environment]::ExpandEnvironmentVariables($rawPath).TrimEnd('\')
            if (-not [System.IO.Directory]::Exists($localPath)) { continue }

            $userName = [System.IO.Path]::GetFileName($localPath)
            if ($userName -match '^(?i)(Public|Default.*|All Users|systemprofile|LocalService|NetworkService)$') { continue }

            $hiveRoot = "Registry::HKEY_USERS\$sid"
            $isLoaded = (Test-Path -LiteralPath $hiveRoot)

            if ($seenSids.Add($sid)) {
                $results.Add([PSCustomObject]@{
                    SID          = $sid
                    UserName     = $userName
                    LocalPath    = $localPath
                    HiveRoot     = $hiveRoot
                    IsHiveLoaded = $isLoaded
                })
            }
        }
    }

    # Zero-WMI fallback if registry ProfileList enumeration returned zero profiles
    if ($results.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $results.Add([PSCustomObject]@{
            SID          = "CurrentUser"
            UserName     = $env:USERNAME
            LocalPath    = $env:USERPROFILE.TrimEnd('\')
            HiveRoot     = "HKCU:"
            IsHiveLoaded = (Test-Path -LiteralPath "HKCU:\Software")
        })
    }

    return @($results)
}

function Get-UltixFastSize {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$TargetPaths)
    [int64]$totalBytes = 0

    foreach ($rawPath in $TargetPaths) {
        if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }

        try {
            if ([System.IO.File]::Exists($rawPath)) {
                $totalBytes += ([System.IO.FileInfo]::new($rawPath)).Length
                continue
            }
        } catch { }

        if (-not [System.IO.Directory]::Exists($rawPath)) { continue }

        $dirStack = [System.Collections.Generic.Stack[string]]::new()
        $dirStack.Push($rawPath)

        while ($dirStack.Count -gt 0) {
            $currentDir = $dirStack.Pop()

            try {
                foreach ($filePath in [System.IO.Directory]::EnumerateFiles($currentDir)) {
                    try {
                        $totalBytes += ([System.IO.FileInfo]::new($filePath)).Length
                    } catch [System.UnauthorizedAccessException] {
                    } catch { }
                }
            } catch [System.UnauthorizedAccessException] {
            } catch { }

            try {
                foreach ($subDir in [System.IO.Directory]::EnumerateDirectories($currentDir)) {
                    try {
                        $attr = [System.IO.File]::GetAttributes($subDir)
                        if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                            $dirStack.Push($subDir)
                        }
                    } catch [System.UnauthorizedAccessException] {
                    } catch { }
                }
            } catch [System.UnauthorizedAccessException] {
            } catch { }
        }
    }
    return $totalBytes
}

function Grant-UltixRegistryKeyAccess {
    param([Parameter(Mandatory=$true)][string]$RegistryPath)
    if ([string]::IsNullOrWhiteSpace($RegistryPath)) { return }

    $baseHive   = $null
    $subKeyPath = ""
    if ($RegistryPath -match '^(?i)(HKLM:\\|Registry::HKEY_LOCAL_MACHINE\\)(.+)$') {
        $baseHive   = [Microsoft.Win32.Registry]::LocalMachine
        $subKeyPath = $matches[2]
    } elseif ($RegistryPath -match '^(?i)(HKCU:\\|Registry::HKEY_CURRENT_USER\\)(.+)$') {
        $baseHive   = [Microsoft.Win32.Registry]::CurrentUser
        $subKeyPath = $matches[2]
    } elseif ($RegistryPath -match '^(?i)(HKCR:\\|Registry::HKEY_CLASSES_ROOT\\)(.+)$') {
        $baseHive   = [Microsoft.Win32.Registry]::ClassesRoot
        $subKeyPath = $matches[2]
    } elseif ($RegistryPath -match '^(?i)(HKU:\\|Registry::HKEY_USERS\\)(.+)$') {
        $baseHive   = [Microsoft.Win32.Registry]::Users
        $subKeyPath = $matches[2]
    }
    if ($null -eq $baseHive -or [string]::IsNullOrWhiteSpace($subKeyPath)) { return }

    try {
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeTakeOwnershipPrivilege")
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeRestorePrivilege")
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

        $keyOwn = $baseHive.OpenSubKey(
            $subKeyPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::TakeOwnership
        )
        if ($null -ne $keyOwn) {
            try {
                $aclOwn = $keyOwn.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
                $aclOwn.SetOwner($adminSid)
                $keyOwn.SetAccessControl($aclOwn)
            } finally {
                $keyOwn.Dispose()
            }
        }

        $keyAcl = $baseHive.OpenSubKey(
            $subKeyPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions
        )
        if ($null -ne $keyAcl) {
            try {
                $acl = $keyAcl.GetAccessControl()
                $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $adminSid,
                    [System.Security.AccessControl.RegistryRights]::FullControl,
                    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.SetAccessRule($rule)
                $keyAcl.SetAccessControl($acl)
            } finally {
                $keyAcl.Dispose()
            }
        }
    } catch { }
}

function Set-ProtectedServiceStart {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceName,
        [Parameter(Mandatory=$true)][int]$StartValue,
        [switch]$StartService,
        [string]$Module = ""
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (-not (Test-Path -LiteralPath $regPath)) { return }

    $startFlag = if ($StartService.IsPresent) { " -StartService" } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($Module)) {
        Write-UltixExpertCommand -CommandText "Set-ProtectedServiceStart -ServiceName '$ServiceName' -StartValue $StartValue$startFlag" -Module $Module
    }

    $escalatedAcl = $false
    try {
        Set-ItemProperty -LiteralPath $regPath -Name "Start" -Value $StartValue -Type DWord -Force -ErrorAction Stop
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        $escalatedAcl = $true
        Grant-UltixRegistryKeyAccess -RegistryPath $regPath
        try {
            Set-ItemProperty -LiteralPath $regPath -Name "Start" -Value $StartValue -Type DWord -Force -ErrorAction Stop
        } catch {
            if (-not [string]::IsNullOrWhiteSpace($Module)) {
                Write-UltixExpertResult -OutputText $_.Exception.Message -ExitCode 1 -Module $Module
            }
            throw
        }
    }

    # Synchronize live in-memory SCM database (services.exe) via ChangeServiceConfigW & optionally start immediately
    $scmSynced = $false
    if ($null -ne ([WinUltix.PrivilegeEnabler].GetMethod("SetServiceConfigLive"))) {
        $scmSynced = [WinUltix.PrivilegeEnabler]::SetServiceConfigLive($ServiceName, $StartValue, $StartService.IsPresent)
    }
    if ($StartService.IsPresent -and $StartValue -ne 4) {
        Start-Service -Name $ServiceName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    }

    if (-not [string]::IsNullOrWhiteSpace($Module)) {
        $aclNote = if ($escalatedAcl) { " | ACL: TrustedInstaller Bypassed" } else { "" }
        $scmNote = if ($scmSynced) { " | Live SCM: Synced" } else { "" }
        Write-UltixExpertResult -OutputText "$ServiceName -> Start=$StartValue$scmNote$aclNote" -ExitCode 0 -Module $Module
    }
}

function Stop-UltixService {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceName,
        [switch]$IncludePerUserInstances,
        [string]$Module = ""
    )
    $targets = [System.Collections.Generic.List[System.ServiceProcess.ServiceController]]::new()
    try {
        $mainSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($null -ne $mainSvc) { $targets.Add($mainSvc) }
        if ($IncludePerUserInstances.IsPresent) {
            foreach ($subSvc in @(Get-Service -Name "${ServiceName}_*" -ErrorAction SilentlyContinue)) {
                $targets.Add($subSvc)
            }
        }
        if ($targets.Count -eq 0) { return }

        $runningTargets = @($targets | Where-Object { $_.Status -ne 'Stopped' })
        if ($runningTargets.Count -eq 0) { return }

        if (-not [string]::IsNullOrWhiteSpace($Module)) {
            Write-UltixExpertCommand -CommandText "Stop-UltixService -ServiceName '$ServiceName'" -Module $Module
        }

        $usedScmFallback = $false
        foreach ($svc in $runningTargets) {
            Stop-Service -InputObject $svc -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $svc.Refresh()
            if ($svc.Status -ne 'Stopped' -and $null -ne ([WinUltix.PrivilegeEnabler].GetMethod("StopServiceLive"))) {
                $usedScmFallback = $true
                [void][WinUltix.PrivilegeEnabler]::StopServiceLive($svc.ServiceName)
                Start-Sleep -Milliseconds 150
                $svc.Refresh()
            }
        }

        $finalStates = ($runningTargets | ForEach-Object { "$($_.ServiceName)=$($_.Status)" }) -join ", "
        $scmNote = if ($usedScmFallback) { " | Live SCM ControlService" } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($Module)) {
            Write-UltixExpertResult -OutputText "$finalStates$scmNote" -ExitCode 0 -Module $Module
        }
    } finally {
        foreach ($t in $targets) {
            if ($null -ne $t) { $t.Dispose() }
        }
    }
}

function Stop-UltixProcess {
    param(
        [Parameter(Mandatory=$true)][string[]]$Name,
        [string]$Module = ""
    )
    $procs = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return 0 }

    $killedCount = 0
    $procNames   = ($procs | Select-Object -ExpandProperty ProcessName -Unique) -join ","
    if (-not [string]::IsNullOrWhiteSpace($Module)) {
        Write-UltixExpertCommand -CommandText "Stop-Process -Name '$procNames' -Force" -Module $Module
    }

    try {
        foreach ($p in $procs) {
            try {
                if (-not $p.HasExited) {
                    $p.Kill()
                    $killedCount++
                }
            } catch {
                try {
                    Stop-Process -Id $p.Id -Force -ErrorAction Stop
                    $killedCount++
                } catch { }
            }
        }
    } finally {
        foreach ($p in $procs) {
            if ($null -ne $p) { $p.Dispose() }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Module)) {
        Write-UltixExpertResult -OutputText "Terminated $killedCount instance(s) ($procNames)" -ExitCode 0 -Module $Module
    }
    return $killedCount
}

function Unlock-UltixTrustedInstaller {
    $tiRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller"
    $tiStart   = (Get-ItemProperty -LiteralPath $tiRegPath -Name "Start" -ErrorAction SilentlyContinue).Start
    if ($tiStart -eq 4) {
        Set-ProtectedServiceStart -ServiceName "TrustedInstaller" -StartValue 3
    }
}

function Grant-UltixDirectoryAdminAccess {
    param([Parameter(Mandatory=$true)][string]$TargetPath)
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return }
    try {
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeTakeOwnershipPrivilege")
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeRestorePrivilege")
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeBackupPrivilege")
    } catch { }
    # 100% locale-independent ownership & ACL grant via well-known Administrators SID (*S-1-5-32-544)
    & icacls.exe "$TargetPath" /setowner "*S-1-5-32-544" /T /C /Q 2>$null | Out-Null
    & icacls.exe "$TargetPath" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
}

function Get-UltixPowerAcIndex {
    param(
        [Parameter(Mandatory=$true)][string]$SettingGuid,
        [string]$SubGroupGuid = "SUB_PROCESSOR",
        [switch]$IncludeHidden
    )
    $queryFlag = if ($IncludeHidden -or $SubGroupGuid -eq "SUB_PROCESSOR") { "/qh" } else { "/q" }
    $out = powercfg.exe $queryFlag SCHEME_CURRENT $SubGroupGuid $SettingGuid 2>$null
    if (-not $out) { return $null }

    # In powercfg output, the last two hex lines are always Current AC [-2] and Current DC [-1]
    $hexLines = @($out -match ':\s*(0x[0-9a-fA-F]+)\s*$')
    if ($hexLines.Count -ge 2 -and $hexLines[-2] -match '(0x[0-9a-fA-F]+)\s*$') {
        return [convert]::ToInt32($matches[1], 16)
    } elseif ($hexLines.Count -eq 1 -and $hexLines[0] -match '(0x[0-9a-fA-F]+)\s*$') {
        return [convert]::ToInt32($matches[1], 16)
    }
    return $null
}

function Update-ShellEnvironment {
    param(
        [array]$ModifiedItems = @(),
        [switch]$ForceExplorerRestart,
        [string]$Module = "CORE"
    )

    $needsExplorerRestart = $ForceExplorerRestart.IsPresent
    $needsSearchRestart   = $false

    foreach ($item in $ModifiedItems) {
        if ($null -ne $item.ActionData) {
            if ($item.ActionData.RestartShell -eq $true)  { $needsExplorerRestart = $true }
            if ($item.ActionData.RestartSearch -eq $true) { $needsSearchRestart   = $true }
        }
    }

    try {
        [WinUltix.ShellInterop]::BroadcastShellRefresh()
    } catch { }

    if ($needsSearchRestart) {
        [void](Stop-UltixProcess -Name "SearchHost" -Module $Module)
        Write-GUI " -> Refreshed Windows Search UI host (SearchHost.exe)."
    }

    if ($needsExplorerRestart) {
        Write-GUI " -> Policy change requires shell reload. Restarting explorer.exe..."
        [void](Stop-UltixProcess -Name "explorer" -Module $Module)
        Start-Sleep -Milliseconds 400
        $expProcs = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)
        if ($expProcs.Count -eq 0) {
            Start-Process "explorer.exe"
        } else {
            foreach ($ep in $expProcs) { if ($null -ne $ep) { $ep.Dispose() } }
        }
    } else {
        Write-GUI " -> Shell & Taskbar refreshed live via Win32 WM_SETTINGCHANGE / SHChangeNotify."
    }
}

function Write-UltixExpertCommand {
    param(
        [Parameter(Mandatory=$true)][string]$CommandText,
        [string]$Module = "CORE"
    )
    if (-not [WinUltix.ExpertConsole]::IsVisible) { return }
    $ts = [DateTime]::Now.ToString("HH:mm:ss")
    $modPadded = "[$Module]".PadRight(15)
    # 93 = Bright Yellow/Amber for executed commands
    [WinUltix.ExpertConsole]::WriteLine("[$ts] $modPadded > $CommandText", "93")
}

function Write-UltixExpertResult {
    param(
        [AllowEmptyString()][string]$OutputText,
        [int]$ExitCode = 0,
        [string]$Module = "CORE"
    )
    if (-not [WinUltix.ExpertConsole]::IsVisible) { return }
    $ts = [DateTime]::Now.ToString("HH:mm:ss")
    $modPad = " " * 15
    $color = if ($ExitCode -eq 0) { "90" } else { "91" }
    $cleanOut = if ([string]::IsNullOrWhiteSpace($OutputText)) { "OK (No stdout)" } else { $OutputText.Trim() }
    # Exact 29-char prefix alignment matching command column
    [WinUltix.ExpertConsole]::WriteLine("[$ts] $modPad|-> [EXIT: $ExitCode] $cleanOut", $color)
}

function Set-UltixRegValue {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [AllowEmptyString()][string]$Name = "",
        [Parameter(Mandatory=$true)]$Value,
        [string]$Type = "DWord",
        [string]$Module = "CORE"
    )
    $isDefaultVal = ($Name -eq "" -or $Name -eq "(Default)")
    $fmtVal = if ($Type -eq "Binary" -and $Value -is [byte[]]) {
        $hexPreview = ($Value | Select-Object -First 4 | ForEach-Object { "0x{0:X2}" -f $_ }) -join ","
        if ($Value.Length -gt 4) { "[byte[]]($hexPreview,..[$($Value.Length)B])" } else { "[byte[]]($hexPreview)" }
    } elseif ($Type -eq "MultiString" -and $Value -is [array]) {
        "@(" + (($Value | ForEach-Object { "'$_'" }) -join ",") + ")"
    } elseif ($Type -in @("String", "ExpandString") -or $isDefaultVal) {
        "'$(([string]$Value).Replace("'", "''"))'"
    } else {
        "$Value"
    }

    if ($isDefaultVal) {
        Write-UltixExpertCommand -CommandText "Set-Item -LiteralPath '$Path' -Value $fmtVal -Force" -Module $Module
    } else {
        Write-UltixExpertCommand -CommandText "Set-ItemProperty -LiteralPath '$Path' -Name '$Name' -Value $fmtVal -Type $Type -Force" -Module $Module
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($isDefaultVal) {
            Set-Item -LiteralPath $Path -Value ([string]$Value) -Force -ErrorAction Stop | Out-Null
            Write-UltixExpertResult -OutputText "(Default) = '$Value'" -ExitCode 0 -Module $Module
        } else {
            $writeVal = $Value
            if ($Type -eq "DWord" -and $writeVal -is [long] -and $writeVal -gt [int]::MaxValue) {
                $writeVal = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$writeVal), 0)
            }
            Set-ItemProperty -LiteralPath $Path -Name $Name -Value $writeVal -Type $Type -Force -ErrorAction Stop | Out-Null
            Write-UltixExpertResult -OutputText "$Name = $fmtVal ($Type)" -ExitCode 0 -Module $Module
        }
    } catch {
        Write-UltixExpertResult -OutputText $_.Exception.Message -ExitCode 1 -Module $Module
        throw
    }
}

function Remove-UltixRegItem {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [AllowEmptyString()][string]$Name = "",
        [switch]$IgnoreMissing,
        [string]$Module = "CORE"
    )
    $isKeyDelete = [string]::IsNullOrEmpty($Name)
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($IgnoreMissing.IsPresent) { return }
    }

    if ($isKeyDelete) {
        Write-UltixExpertCommand -CommandText "Remove-Item -LiteralPath '$Path' -Recurse -Force" -Module $Module
    } else {
        Write-UltixExpertCommand -CommandText "Remove-ItemProperty -LiteralPath '$Path' -Name '$Name' -Force" -Module $Module
    }

    try {
        if ($isKeyDelete) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop | Out-Null
            Write-UltixExpertResult -OutputText "Deleted key: $Path" -ExitCode 0 -Module $Module
        } else {
            Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop | Out-Null
            Write-UltixExpertResult -OutputText "Deleted value: $Name" -ExitCode 0 -Module $Module
        }
    } catch [System.Management.Automation.PSArgumentException], [System.Management.Automation.ItemNotFoundException] {
        if ($IgnoreMissing.IsPresent) {
            Write-UltixExpertResult -OutputText "Already absent (No-op)" -ExitCode 0 -Module $Module
            return
        }
        Write-UltixExpertResult -OutputText $_.Exception.Message -ExitCode 1 -Module $Module
        throw
    } catch {
        Write-UltixExpertResult -OutputText $_.Exception.Message -ExitCode 1 -Module $Module
        throw
    }
}

function Invoke-UltixExe {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$Module = "CORE"
    )
    $argLine = ($Arguments | ForEach-Object {
        if ($_ -eq "") {
            '""'
        } elseif ($_ -match '\s' -and $_ -notmatch '^".*"$') {
            $safeArg = $_ -replace '\\+$', '$0$0'
            "`"$safeArg`""
        } else {
            $_
        }
    }) -join " "
    Write-UltixExpertCommand -CommandText "$FilePath $argLine".Trim() -Module $Module

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $ec = $proc.ExitCode

        $rawMsg = if ($ec -ne 0 -and -not [string]::IsNullOrWhiteSpace($stderr)) {
            $stderr
        } elseif (-not [string]::IsNullOrWhiteSpace($stdout)) {
            $stdout
        } else {
            $stderr
        }

        $cleanOut = ($rawMsg -replace '\x00', '' -replace '\s+', ' ').Trim()
        if ($cleanOut.Length -gt 180) { $cleanOut = $cleanOut.Substring(0, 177) + "..." }

        Write-UltixExpertResult -OutputText $cleanOut -ExitCode $ec -Module $Module
        return $ec
    } finally {
        if ($null -ne $proc) { $proc.Dispose() }
    }
}

function Invoke-UltixStep {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [string]$SuccessOutput = "Completed",
        [string]$Module = "CORE"
    )
    Write-UltixExpertCommand -CommandText $Command -Module $Module
    try {
        $res = & $Action
        $msg = if ($res -is [string] -and -not [string]::IsNullOrWhiteSpace($res)) { $res } else { $SuccessOutput }
        Write-UltixExpertResult -OutputText $msg -ExitCode 0 -Module $Module
        return $res
    } catch {
        Write-UltixExpertResult -OutputText $_.Exception.Message -ExitCode 1 -Module $Module
        throw
    }
}

# ------------------------------------------
# 3. GLOBAL UI HELPERS & CONTROL FACTORIES
# ------------------------------------------
function Write-GUI { 
    param(
        [AllowEmptyString()][string]$Message,
        [switch]$DeferUpdate
    )
    if ($null -ne $global:infoBox -and -not $global:infoBox.IsDisposed) {
        if ($global:infoBox -is [System.Windows.Forms.RichTextBox]) {
            if ($Message -eq "") {
                $global:infoBox.AppendText("`r`n")
                if (-not $DeferUpdate) {
                    $global:infoBox.ScrollToCaret()
                    $global:infoBox.Update()
                }
                return
            }

            $msgColor = [System.Drawing.Color]::LightGray
            if ($Message -match '^\s*(===|---)') {
                $msgColor = [System.Drawing.Color]::Cyan
            } elseif ($Message -match '\[ERROR\]|\[\-\]|(?i)\bfailed\b|(?i)(?<!Windows\s|Hardware\s)\berror\b(?!\s+Reporting)') {
                $msgColor = [System.Drawing.Color]::IndianRed
            } elseif ($Message -match '\[!\]|(?i)\bWARNING\b|-> STATUS:') {
                $msgColor = [System.Drawing.Color]::Orange
            } elseif ($Message -match '\[OK\]|\[\+\]|\[ENABLED\]|(?i)\b(completed|online|restored|clean)\b') {
                $msgColor = [System.Drawing.Color]::LightGreen
            } elseif ($Message -match '\[\*\]|\[DISABLED\]|^\s*->') {
                $msgColor = [System.Drawing.Color]::LightSkyBlue
            }

            $global:infoBox.SelectionStart  = $global:infoBox.TextLength
            $global:infoBox.SelectionLength = 0
            $global:infoBox.SelectionColor  = [System.Drawing.Color]::FromArgb(255, 115, 115, 115)
            $global:infoBox.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] ")

            $global:infoBox.SelectionStart  = $global:infoBox.TextLength
            $global:infoBox.SelectionLength = 0
            $global:infoBox.SelectionColor  = $msgColor
            $global:infoBox.AppendText($Message)

            if (-not $DeferUpdate) {
                $global:infoBox.ScrollToCaret()
                $global:infoBox.Update()
            }
        } else {
            $line = if ($Message -eq "") { "`r`n" } else { "`r`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }
            $global:infoBox.AppendText($line)
            if (-not $DeferUpdate) {
                $global:infoBox.Update()
            }
        }
    } else {
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Format-UltixDeviceName {
    param([AllowEmptyString()][string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $clean = $RawName.Trim()

    # 100% locale-independent canonical normalization for standard Windows inbox .inf tokens
    if ($clean -match '^@([^,;]+),([^;]+);(.+)$') {
        $infFile  = $matches[1].Trim().ToLowerInvariant()
        $infToken = $matches[2].Trim().ToLowerInvariant()
        $restPart = $matches[3].Trim()

        switch ($infFile) {
            "usbxhci.inf" {
                if ($restPart -match ';\(([^,]+),([^,]+),([^)]+)\)\s*$') {
                    return "$($matches[1].Trim()) USB $($matches[2].Trim()) eXtensible Host Controller - $($matches[3].Trim()) (Microsoft)"
                }
            }
            "hdaudbus.inf" { return "High Definition Audio Controller" }
            "hdaudio.inf"  { return "High Definition Audio Device" }
            "stornvme.inf" { return "Standard NVM Express Controller" }
            "mshdc.inf" {
                if ($infToken -match 'storahci|ahci') { return "Standard SATA AHCI Controller" }
            }
            "usb.inf" {
                if ($infToken -match 'composite') { return "USB Composite Device" }
            }
            "input.inf" {
                if ($infToken -match 'hid\.devicedesc') { return "USB Input Device" }
            }
            "keyboard.inf" {
                if ($infToken -match 'hid\.keyboarddevice') { return "HID Keyboard Device" }
            }
            "msmouse.inf" {
                if ($infToken -match 'hid\.mousedevice') { return "HID-compliant mouse" }
            }
            "hidclass.inf" { return "HID-compliant device" }
            "hidserv.inf"  { return "HID-compliant consumer control device" }
            "usbhub3.inf" {
                if ($infToken -match 'usb30hub') { return "Generic SuperSpeed USB Hub" }
                if ($infToken -match 'usb20hub') { return "Generic USB Hub" }
            }
        }
        $clean = $restPart
    }

    # Resolve parameterized INF templates like '%1 USB %2 eXtensible Host Controller - %3 (Microsoft);(Intel(R),3.0,1.0)'
    $lastSemi = $clean.LastIndexOf(';')
    if ($lastSemi -gt 0 -and $lastSemi -lt ($clean.Length - 1)) {
        $basePart = $clean.Substring(0, $lastSemi).Trim()
        $paramRaw = $clean.Substring($lastSemi + 1).Trim()
        if ($paramRaw.StartsWith("(") -and $paramRaw.EndsWith(")") -and $paramRaw.Length -gt 2) {
            $paramRaw = $paramRaw.Substring(1, $paramRaw.Length - 2).Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($paramRaw)) {
            $paramList = @($paramRaw.Split(','))
            if ($basePart -match '%\d+') {
                for ($i = 0; $i -lt $paramList.Count; $i++) {
                    $token = "%$($i + 1)"
                    $basePart = $basePart.Replace($token, $paramList[$i].Trim())
                }
                $clean = $basePart.Trim()
            } else {
                if ($basePart -notmatch [regex]::Escape($paramRaw)) {
                    $clean = "$basePart ($paramRaw)"
                } else {
                    $clean = $basePart
                }
            }
        }
    }
    return $clean.Trim()
}

function Write-UltixSystemBanner {
    param([string]$StatusMessage = "Ready for deployment. Modular architecture loaded successfully.")

    if ($null -eq $global:infoBox -or $global:infoBox.IsDisposed) { return }

    # 1. OS Version, DisplayVersion (24H2/25H2/26H2), Build & UBR (<0.15ms)
    $ntCur = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName", "DisplayVersion", "ReleaseId", "CurrentBuild", "UBR" -ErrorAction SilentlyContinue
    $prodName = if ($null -ne $ntCur -and $ntCur.ProductName) { [string]$ntCur.ProductName } else { "Windows OS" }
    $buildNum = if ($null -ne $ntCur -and $ntCur.CurrentBuild) { [int]$ntCur.CurrentBuild } else { [Environment]::OSVersion.Version.Build }
    if ($buildNum -ge 22000 -and $prodName -match 'Windows 10') {
        $prodName = $prodName -replace 'Windows 10', 'Windows 11'
    }
    $dispVer = if ($null -ne $ntCur -and $ntCur.DisplayVersion) { [string]$ntCur.DisplayVersion } elseif ($null -ne $ntCur -and $ntCur.ReleaseId) { [string]$ntCur.ReleaseId } else { "" }
    $ubr     = if ($null -ne $ntCur -and $null -ne $ntCur.UBR) { ".$($ntCur.UBR)" } else { "" }
    $osStr   = "$prodName $(if($dispVer){"$dispVer "})(Build $buildNum$ubr)"

    # 2. Motherboard model from BIOS registry (<0.05ms)
    $biosProps = Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\Description\System\BIOS" -Name "BaseBoardProduct" -ErrorAction SilentlyContinue
    $boardStr  = if ($null -ne $biosProps -and -not [string]::IsNullOrWhiteSpace($biosProps.BaseBoardProduct)) { " | Board: $($biosProps.BaseBoardProduct.Trim())" } else { "" }

    # 3. CPU Model, Core/Thread count, Topology & L3 Cache (<0.25ms)
    $cpuName = (Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\Description\System\CentralProcessor\0" -Name "ProcessorNameString" -ErrorAction SilentlyContinue).ProcessorNameString
    if ([string]::IsNullOrWhiteSpace($cpuName)) { $cpuName = "Unknown CPU" } else { $cpuName = $cpuName.Trim() }

    $physCores = if (Get-Command Get-UltixPhysicalCoreMasks -ErrorAction SilentlyContinue) { (Get-UltixPhysicalCoreMasks).Count } else { [Environment]::ProcessorCount }
    $logCores  = [Environment]::ProcessorCount
    $topoLabel = if (Get-Command Get-CPUTopologyProfile -ErrorAction SilentlyContinue) { (Get-CPUTopologyProfile).Label } else { "Standard" }

    $l3Str  = ""
    $l3List = @([WinUltix.CpuTopology]::GetL3Caches())
    if ($l3List.Count -gt 0) {
        [uint64]$totalL3Bytes = 0
        foreach ($c in $l3List) { $totalL3Bytes += [uint64]$c.SizeBytes }
        $totalL3MB = [math]::Round($totalL3Bytes / 1MB, 0)
        if ($l3List.Count -gt 1) {
            $domParts = @($l3List | Sort-Object SizeBytes -Descending | ForEach-Object { "$([math]::Round($_.SizeBytes / 1MB, 0))" }) -join "+"
            $l3Str = " | L3: $totalL3MB MB ($domParts MB)"
        } elseif ($totalL3MB -gt 0) {
            $l3Str = " | L3: $totalL3MB MB"
        }
    }

    # 4. Physical RAM + Universal Multi-Vendor SPD PartNumber Decoder (G.Skill, Corsair, Kingston, TeamGroup, Crucial, Patriot, GoodRAM) (<0.1ms)
    $rawRamKB = [uint64][WinUltix.NativeMethods]::GetTotalPhysicalMemoryKB()
    $ramStr   = [WinUltix.SmbiosRamInfo]::GetRamSummary($rawRamKB)
    $activeMt = if ($ramStr -match '@\s*(\d+)\s*MT/s') { [int]$matches[1] } else { 0 }

    $specMt = 0
    $specCl = 0
    # Pattern A: Full 4-digit MT/s + C/J/Z/CL/L + 2-digit CAS (G.Skill F4-3600C16 / F5-6000J30, Corsair 6000C30 / 6000Z30, TeamGroup 6000HC30, GoodRAM 6000D564L30)
    if ($ramStr -match '(?i)(?:^|[^0-9])([2-9]\d00)[A-Z0-9]{0,5}?(?:CL|[CJZL])(\d{2})(?:[^0-9]|$)') {
        $specMt = [int]$matches[1]
        $specCl = [int]$matches[2]
    }
    # Pattern B: Kingston Fury / Crucial / Patriot 2- or 3-digit shorthand (KF560C30 -> 6000 CL30, KF436C16 -> 3600 CL16, BL2K16G36C16 -> 3600 CL16, PVV532G600C30 -> 6000 CL30)
    elseif ($ramStr -match '(?i)(?:KF[45]|G)(\d{2,3})C(\d{2})\b') {
        $rawSpd = [int]$matches[1]
        $specMt = if ($rawSpd -lt 100) { $rawSpd * 100 } else { $rawSpd * 10 }
        $specCl = [int]$matches[2]
    }
    # Pattern C: Standalone CLxx token in PartNumber
    elseif ($ramStr -match '(?i)\bCL(\d{2})\b') {
        $specCl = [int]$matches[1]
    }

    if ($specMt -gt 0 -and $specCl -gt 0) {
        if ($activeMt -gt 0 -and [math]::Abs($activeMt - $specMt) -le 200) {
            $ramStr = $ramStr -replace ' MT/s ', " MT/s CL$specCl "
        } elseif ($activeMt -gt 0 -and $activeMt -lt ($specMt - 200)) {
            $ramStr = $ramStr -replace ' MT/s ', " MT/s [XMP/EXPO Off - Spec: $specMt CL$specCl] "
        }
    } elseif ($specCl -gt 0) {
        $ramStr = $ramStr -replace ' MT/s ', " MT/s CL$specCl "
    }

    # 5. Active PCI GPU(s), 64-Bit VRAM, Negotiated PCIe Bus Link & Decoded Driver Version (<0.3ms)
    $gpuEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $pciRoot    = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum\PCI", $false)
    $classRoot  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Class", $false)
    if ($null -ne $pciRoot -and $null -ne $classRoot) {
        try {
            foreach ($venName in $pciRoot.GetSubKeyNames()) {
                $venKey = $pciRoot.OpenSubKey($venName, $false)
                if ($null -eq $venKey) { continue }
                try {
                    foreach ($instName in $venKey.GetSubKeyNames()) {
                        $instKey = $venKey.OpenSubKey($instName, $false)
                        if ($null -eq $instKey) { continue }
                        try {
                            $clsName = [string]$instKey.GetValue("Class", "")
                            $clsGuid = [string]$instKey.GetValue("ClassGUID", "")
                            $drvRel  = [string]$instKey.GetValue("Driver", "")
                            $svcName = [string]$instKey.GetValue("Service", "")

                            $isDisplay = (
                                $clsName -match '^(?i)Display$' -or
                                $clsGuid -match '(?i)4d36e968-e325-11ce-bfc1-08002be10318' -or
                                $drvRel  -match '(?i)4d36e968-e325-11ce-bfc1-08002be10318' -or
                                $svcName -match '^(?i)(nvlddmkm|amdkmdag|amdwddmg|igfx|igfxn)$'
                            )
                            if (-not $isDisplay) { continue }

                            $instanceId = "PCI\$venName\$instName"
                            if ([WinUltix.PnpTree]::GetDeviceConfigStatus($instanceId) -ne 0) { continue }

                            $rawGpuName = [string]$instKey.GetValue("FriendlyName", "")
                            if ([string]::IsNullOrWhiteSpace($rawGpuName)) { $rawGpuName = [string]$instKey.GetValue("DeviceDesc", "") }
                            $gpuName = Format-UltixDeviceName -RawName $rawGpuName

                            [uint64]$vramBytes = 0
                            $drvVer = ""

                            if (-not [string]::IsNullOrWhiteSpace($drvRel)) {
                                $drvKey = $classRoot.OpenSubKey($drvRel, $false)
                                if ($null -ne $drvKey) {
                                    try {
                                        $descVal = [string]$drvKey.GetValue("DriverDesc", "")
                                        if (-not [string]::IsNullOrWhiteSpace($descVal)) { $gpuName = $descVal.Trim() }
                                        $drvVer  = [string]$drvKey.GetValue("DriverVersion", "")

                                        foreach ($qwProp in @("HardwareInformation.qwMemorySize", "Settings\HardwareInformation.qwMemorySize")) {
                                            $rawQw = $drvKey.GetValue($qwProp, $null)
                                            if ($null -ne $rawQw) {
                                                if ($rawQw -is [long] -or $rawQw -is [uint64] -or $rawQw -is [int]) {
                                                    if ([int64]$rawQw -gt 0) { $vramBytes = [uint64]$rawQw; break }
                                                } elseif ($rawQw -is [byte[]] -and $rawQw.Length -ge 8) {
                                                    $vramBytes = [BitConverter]::ToUInt64($rawQw, 0)
                                                    if ($vramBytes -gt 0) { break }
                                                }
                                            }
                                        }
                                        if ($vramBytes -eq 0) {
                                            $rawMem = $drvKey.GetValue("HardwareInformation.MemorySize", $null)
                                            if ($null -ne $rawMem) {
                                                if ($rawMem -is [int] -or $rawMem -is [long]) {
                                                    $vramBytes = [uint64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$rawMem), 0)
                                                } elseif ($rawMem -is [byte[]] -and $rawMem.Length -ge 4) {
                                                    $vramBytes = [uint64][BitConverter]::ToUInt32($rawMem, 0)
                                                }
                                            }
                                        }
                                    } finally {
                                        $drvKey.Dispose()
                                    }
                                }
                            }

                            if ([string]::IsNullOrWhiteSpace($gpuName)) { $gpuName = "PCI Display Adapter" }
                            $vramStr = if ($vramBytes -ge 1073741824) {
                                "$([math]::Round($vramBytes / 1GB, 1)) GB VRAM"
                            } elseif ($vramBytes -gt 0) {
                                "$([math]::Round($vramBytes / 1MB, 0)) MB VRAM"
                            } else {
                                "Shared VRAM"
                            }

                            # Translate WDDM INF version (e.g. 32.0.15.8157 -> 581.57) for NVIDIA GPUs
                            $drvFormatted = $drvVer
                            if (($svcName -eq "nvlddmkm" -or $gpuName -match '(?i)(NVIDIA|GeForce|RTX|GTX|Quadro)') -and $drvVer -match '^\d+\.\d+\.\d*(\d)\.(\d{2})(\d{2})$') {
                                $drvFormatted = "$($matches[1])$($matches[2]).$($matches[3])"
                            }

                            $pcieLink = [WinUltix.PnpTree]::GetPcieLinkInfo($instanceId)
                            $pcieStr  = if (-not [string]::IsNullOrWhiteSpace($pcieLink))      { " | $pcieLink" } else { "" }
                            $verStr   = if (-not [string]::IsNullOrWhiteSpace($drvFormatted))  { " | Drv: $drvFormatted" } else { "" }

                            $gpuEntries.Add([PSCustomObject]@{
                                VramBytes = $vramBytes
                                Text      = "$gpuName ($vramStr$pcieStr$verStr)"
                            })
                        } finally {
                            $instKey.Dispose()
                        }
                    }
                } finally {
                    $venKey.Dispose()
                }
            }
        } finally {
            $pciRoot.Dispose()
            $classRoot.Dispose()
        }
    }
    $gpuStr = if ($gpuEntries.Count -gt 0) {
        @($gpuEntries | Sort-Object VramBytes -Descending | Select-Object -ExpandProperty Text) -join " + "
    } else {
        "Standard Display Adapter"
    }

    $global:infoBox.SelectionColor = [System.Drawing.Color]::Cyan
    $global:infoBox.AppendText("--- WINULTIX $Global:AppVersion ---`r`n")

    $global:infoBox.SelectionColor = [System.Drawing.Color]::FromArgb(255, 165, 175, 185)
    $global:infoBox.AppendText("[SYS] OS  : $osStr$boardStr`r`n")
    $global:infoBox.AppendText("[CPU] PRC : $cpuName ($($physCores)C/$($logCores)T | $topoLabel$l3Str)`r`n")
    $global:infoBox.AppendText("[RAM] MEM : $ramStr`r`n")
    $global:infoBox.AppendText("[GPU] GFX : $gpuStr`r`n`r`n")

    if (-not [string]::IsNullOrWhiteSpace($StatusMessage)) {
        $global:infoBox.SelectionColor = [System.Drawing.Color]::LightGreen
        $global:infoBox.AppendText("$StatusMessage`r`n")
    }
}

function Show-Description { 
    param([string]$Desc)
    if ($null -ne $global:descBox -and -not $global:descBox.IsDisposed) {
        $global:descBox.Text = $Desc -replace "(?<!`r)`n", "`r`n" 
    }
}

function Restore-Log { 
    if ($null -ne $global:descBox -and -not $global:descBox.IsDisposed) {
        $global:descBox.Text = "Hover over any button to see operation details." 
    }
}

function Update-Progress { 
    param([int]$Percent)
    if ($null -ne $global:progBar -and -not $global:progBar.IsDisposed) {
        $clamped = [math]::Max(0, [math]::Min(100, $Percent))
        $global:progBar.Value = $clamped
        $global:progBar.Invalidate()
        $global:progBar.Update()
    }
}

function Get-UltixActiveNetworkAdapters {
    $adapters = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }

        try {
            $ipProps = $nic.GetIPProperties()
            if ($null -eq $ipProps) { continue }
            $validGw = @($ipProps.GatewayAddresses | Where-Object { $_.Address.ToString() -notin @("0.0.0.0", "::") })
            if ($validGw.Count -eq 0) { continue }

            $v4Props = $ipProps.GetIPv4Properties()
            if ($null -eq $v4Props -or $v4Props.Index -le 0) { continue }

            $v4Addrs = [System.Collections.Generic.List[string]]::new()
            $v6Addrs = [System.Collections.Generic.List[string]]::new()
            foreach ($dnsIp in $ipProps.DnsAddresses) {
                if ($dnsIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    $v4Addrs.Add($dnsIp.ToString())
                } elseif ($dnsIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and -not $dnsIp.IsIPv6SiteLocal) {
                    $v6Addrs.Add($dnsIp.ToString())
                }
            }

            $ifGuid = [string]$nic.Id
            $v4RegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$ifGuid"
            $staticNs = [string](Get-ItemProperty -LiteralPath $v4RegKey -Name "NameServer" -ErrorAction SilentlyContinue).NameServer
            $primaryV4 = if ($v4Addrs.Count -gt 0) { $v4Addrs[0] } else { "" }

            $providerName = if ([string]::IsNullOrWhiteSpace($staticNs)) {
                "Default (DHCP)"
            } else {
                switch ($primaryV4) {
                    "9.9.9.9"        { "Quad9 (9.9.9.9)" }
                    "1.1.1.1"        { "Cloudflare (1.1.1.1)" }
                    "94.140.14.14"   { "AdGuard (94.140.14.14)" }
                    "8.8.8.8"        { "Google (8.8.8.8)" }
                    "208.67.222.222" { "OpenDNS (208.67.222.222)" }
                    default          { "Custom" }
                }
            }

            $isDohActive = $false
            if (-not [string]::IsNullOrWhiteSpace($ifGuid) -and -not [string]::IsNullOrWhiteSpace($primaryV4)) {
                $dohKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$ifGuid\DohInterfaceSettings\Doh\$primaryV4"
                $flags  = (Get-ItemProperty -LiteralPath $dohKey -Name "DohFlags" -ErrorAction SilentlyContinue).DohFlags
                if ($null -ne $flags -and ($flags -band 1) -eq 1) { $isDohActive = $true }
            }

            $adapters.Add([PSCustomObject]@{
                InterfaceIndex   = [int]$v4Props.Index
                InterfaceGuid    = $ifGuid
                InterfaceName    = [string]$nic.Description
                InterfaceAlias   = [string]$nic.Name
                DnsV4            = @($v4Addrs)
                DnsV6            = @($v6Addrs)
                PrimaryV4        = $primaryV4
                StaticNameServer = $staticNs
                ProviderName     = $providerName
                IsDohActive      = $isDohActive
            })
        } catch { }
    }
    return @($adapters)
}

function Update-DNSLabel {
    if ($null -eq $global:lblCurrentDNS -or $global:lblCurrentDNS.IsDisposed) { return }

    try {
        $activeNic = @(Get-UltixActiveNetworkAdapters) | Select-Object -First 1
        if ($null -eq $activeNic) {
            $global:lblCurrentDNS.Text = "Current DNS: No active internet route"
            $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::DarkGray
            return
        }

        if ([string]::IsNullOrWhiteSpace($activeNic.StaticNameServer)) {
            $dhcpHint = if (-not [string]::IsNullOrWhiteSpace($activeNic.PrimaryV4)) { " (DHCP - $($activeNic.PrimaryV4))" } else { " (DHCP)" }
            $global:lblCurrentDNS.Text = "Current DNS: Default provider$dhcpHint"
            $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue
            return
        }

        $shortProv  = ($activeNic.ProviderName -replace '\s*\([^)]*\)$', '')
        $stackBadge = if ($activeNic.DnsV6.Count -gt 0) { "IPv4+v6" } else { "IPv4" }
        $dohBadge   = if ($activeNic.IsDohActive) { " [DoH Encrypted]" } else { " [Plaintext]" }

        $global:lblCurrentDNS.Text = "Current DNS: $shortProv ($($activeNic.PrimaryV4) | $stackBadge)$dohBadge"
        $global:lblCurrentDNS.ForeColor = if ($activeNic.IsDohActive) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::LightSkyBlue }
    } catch {
        $global:lblCurrentDNS.Text = "Current DNS: Unknown"
    }
}

# Unified 4-Color Engineering Palette
$global:UltixColors = @{
    Standard  = @(55, 58, 64)    # Matte Slate: Standard OS tweaks, cleaners, and repairs
    Inspector = @(45, 85, 125)   # Steel Blue: Interactive grid inspectors, analyzers, and safe profiles
    Danger    = @(135, 50, 50)   # Deep Crimson: Aggressive/destructive actions and hard kernel locks
    Audit     = @(72, 76, 82)    # Neutral Gray: All [?] audit buttons
    Add       = @(45, 95, 60)    # Muted Green: [+] add target buttons
    TabBg     = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
}

# Centralized Typography & Live Font Scaling Configuration
# Change UiFamily (e.g. "Segoe UI Semibold", "Segoe UI", "Tahoma", "Verdana") or ScaleOffset (+0.5 / -0.5) in one place!
$global:UltixTypography = @{
    UiFamily        = "Segoe UI Semibold"
    TextFamily      = "Segoe UI"
    MonoFamily      = "Consolas"
    ScaleOffset     = 0.0
    TabHeaderSize   = 9.0     # Fixed for 57px tab headers so they never clip
    FooterBtnSize   = 9.25    # Optimal fit for 28px global footer buttons
    MainBtnSize     = 9.75    # Full-width tab buttons (320px / 370px)
    CompactBtnSize  = 9.25    # Half-width 2-column buttons (180px / 240px)
    ToolbarBtnSize  = 9.5     # Modal top toolbar buttons (Select All, Select Visible, Refresh)
    ModalActionSize = 9.75    # Modal bottom execution buttons (Start, Stop, Execute, Cancel)
    SectionHdrSize  = 9.5     # Section headers above button groups
    ModalDescSize   = 10.5    # Top description text in modals
    GridTextSize    = 10.25   # ListView & CheckedListBox rows
}

$global:UltixFontCache = @{}

# Load saved font scale offset from registry if present (clamped to [-1.0 .. +1.5])
try {
    $savedScale = (Get-ItemProperty -LiteralPath "HKCU:\Software\WinUltix" -Name "FontScaleOffset" -ErrorAction SilentlyContinue).FontScaleOffset
    if ($null -ne $savedScale) {
        $parsedScale = [double]::Parse([string]$savedScale, [System.Globalization.CultureInfo]::InvariantCulture)
        $global:UltixTypography.ScaleOffset = [math]::Max(-1.0, [math]::Min(1.5, [math]::Round($parsedScale * 2.0) / 2.0))
    }
} catch { }

function Get-UltixFont {
    param(
        [ValidateSet("TabHeader", "MainButton", "CompactButton", "IconButton", "FooterButton", "ToolbarButton", "ModalAction", "SectionHeader", "ModalDesc", "GridText", "GridMono")]
        [string]$Role = "MainButton",
        [double]$CustomSize = 0.0
    )
    $t = $global:UltixTypography
    $offset     = [double]$t.ScaleOffset
    $halfOffset = [math]::Round(($offset * 0.5) * 4.0) / 4.0

    $family = $t.UiFamily
    $size   = 9.5
    $style  = [System.Drawing.FontStyle]::Regular

    switch ($Role) {
        "TabHeader"     { $family = $t.UiFamily;   $size = $t.TabHeaderSize;                                     $style = [System.Drawing.FontStyle]::Regular }
        "FooterButton"  { $family = $t.UiFamily;   $size = $t.FooterBtnSize;                                     $style = [System.Drawing.FontStyle]::Regular }
        "MainButton"    { $family = $t.UiFamily;   $size = $t.MainBtnSize + $offset;                             $style = [System.Drawing.FontStyle]::Regular }
        "CompactButton" { $family = $t.UiFamily;   $size = [math]::Min(9.75, $t.CompactBtnSize + $halfOffset);   $style = [System.Drawing.FontStyle]::Regular }
        "IconButton"    { $family = $t.TextFamily; $size = 10.0 + $halfOffset;                                   $style = [System.Drawing.FontStyle]::Bold    }
        "ToolbarButton" { $family = $t.UiFamily;   $size = [math]::Min(10.0, $t.ToolbarBtnSize + $halfOffset);   $style = [System.Drawing.FontStyle]::Regular }
        "ModalAction"   { $family = $t.TextFamily; $size = [math]::Min(10.25, $t.ModalActionSize + $halfOffset); $style = [System.Drawing.FontStyle]::Bold    }
        "SectionHeader" { $family = $t.TextFamily; $size = [math]::Min(10.0, $t.SectionHdrSize + $halfOffset);   $style = [System.Drawing.FontStyle]::Bold    }
        "ModalDesc"     { $family = $t.TextFamily; $size = [math]::Min(11.0, $t.ModalDescSize + $halfOffset);    $style = [System.Drawing.FontStyle]::Regular }
        "GridText"      { $family = $t.TextFamily; $size = $t.GridTextSize + $offset;                            $style = [System.Drawing.FontStyle]::Regular }
        "GridMono"      { $family = $t.MonoFamily; $size = $t.GridTextSize + $offset;                            $style = [System.Drawing.FontStyle]::Regular }
    }

    if ($CustomSize -gt 0.0) {
        $size = [math]::Round($CustomSize * 4.0) / 4.0
    }

    $cacheKey = "$family|$([int]$style)|$size"
    if ($global:UltixFontCache.ContainsKey($cacheKey)) {
        return $global:UltixFontCache[$cacheKey]
    }

    if ($family -eq "Segoe UI Semibold" -and $style -eq [System.Drawing.FontStyle]::Regular) {
        try {
            $fontObj = New-Object System.Drawing.Font("Segoe UI Semibold", [float]$size, [System.Drawing.FontStyle]::Regular)
        } catch {
            $fontObj = New-Object System.Drawing.Font("Segoe UI", [float]$size, [System.Drawing.FontStyle]::Bold)
        }
    } else {
        $fontObj = New-Object System.Drawing.Font($family, [float]$size, $style)
    }

    $global:UltixFontCache[$cacheKey] = $fontObj
    return $fontObj
}

function Get-UltixFittedFont {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Control,
        [string]$Role = ""
    )
    if ([string]::IsNullOrWhiteSpace($Role)) {
        $Role = if (-not [string]::IsNullOrWhiteSpace($Control.AccessibleName)) { $Control.AccessibleName } else { "MainButton" }
    }

    $baseFont = Get-UltixFont -Role $Role
    if (-not ($Control -is [System.Windows.Forms.Button]) -or [string]::IsNullOrWhiteSpace($Control.Text) -or $Role -eq "IconButton" -or $Control.Width -le 45) {
        return $baseFont
    }

    # WinForms FlatButtonAdapter subtracts ~22px horizontally (border + adapter padding + GDI overhang)
    # and ~8..12px vertically before passing DT_EDITCONTROL to user32!DrawTextExW.
    $maxWidth  = [math]::Max(20, $Control.Width - 22)
    $maxHeight = [math]::Max(12, $Control.Height - 8)
    $isTallMultiLine = ($Control.Height -ge 55)

    $curSize           = [double]$baseFont.SizeInPoints
    $minSingleLineSize = 8.0
    $minFallbackSize   = 7.25

    if ($isTallMultiLine) {
        while ($curSize -ge $minFallbackSize) {
            $candFont = Get-UltixFont -Role $Role -CustomSize $curSize
            $wordsFit = $true
            foreach ($word in ($Control.Text -split '\s+')) {
                if ([string]::IsNullOrEmpty($word)) { continue }
                $wSz = [System.Windows.Forms.TextRenderer]::MeasureText($word, $candFont, [System.Drawing.Size]::new(2000, 2000), [System.Windows.Forms.TextFormatFlags]::SingleLine)
                if ($wSz.Width -gt $maxWidth) {
                    $wordsFit = $false
                    break
                }
            }
            if ($wordsFit) {
                $wrapFlags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
                $wrapSz = [System.Windows.Forms.TextRenderer]::MeasureText($Control.Text, $candFont, [System.Drawing.Size]::new($maxWidth, 2000), $wrapFlags)
                if ($wrapSz.Height -le ($Control.Height - 12)) {
                    return $candFont
                }
            }
            $curSize = [math]::Round(($curSize - 0.25) * 4.0) / 4.0
        }
        return (Get-UltixFont -Role $Role -CustomSize $minFallbackSize)
    }

    # Stage 1: Single-line fit for standard buttons (Height < 55) so WinForms never wraps
    # the trailing word onto a hidden 2nd line suppressed by DT_EDITCONTROL.
    while ($curSize -ge $minSingleLineSize) {
        $candFont = Get-UltixFont -Role $Role -CustomSize $curSize
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($Control.Text, $candFont, [System.Drawing.Size]::new(2000, 2000), [System.Windows.Forms.TextFormatFlags]::SingleLine)
        if ($sz.Width -le $maxWidth -and $sz.Height -le $maxHeight) {
            return $candFont
        }
        $curSize = [math]::Round(($curSize - 0.25) * 4.0) / 4.0
    }

    # Stage 2: Multi-line fallback if text is still wider than 1 line at 8.0pt
    while ($curSize -ge $minFallbackSize) {
        $candFont = Get-UltixFont -Role $Role -CustomSize $curSize
        $wrapFlags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
        $wrapSz = [System.Windows.Forms.TextRenderer]::MeasureText($Control.Text, $candFont, [System.Drawing.Size]::new($maxWidth, 2000), $wrapFlags)
        if ($wrapSz.Height -le ($Control.Height - 10)) {
            return $candFont
        }
        $curSize = [math]::Round(($curSize - 0.25) * 4.0) / 4.0
    }

    return (Get-UltixFont -Role $Role -CustomSize $minFallbackSize)
}

function Set-UltixFontScale {
    param([double]$Delta = 0.0)

    $cur = [double]$global:UltixTypography.ScaleOffset
    $newOffset = [math]::Max(-1.0, [math]::Min(1.5, [math]::Round(($cur + $Delta) * 2.0) / 2.0))
    $global:UltixTypography.ScaleOffset = $newOffset

    try {
        if (-not (Test-Path -LiteralPath "HKCU:\Software\WinUltix")) { New-Item -Path "HKCU:\Software\WinUltix" -Force | Out-Null }
        Set-ItemProperty -LiteralPath "HKCU:\Software\WinUltix" -Name "FontScaleOffset" -Value ($newOffset.ToString([System.Globalization.CultureInfo]::InvariantCulture)) -Type String -Force -ErrorAction SilentlyContinue
    } catch { }

    if ($null -ne $global:form -and -not $global:form.IsDisposed) {
        $global:form.SuspendLayout()
        try {
            if ($null -ne $global:tabControl -and -not $global:tabControl.IsDisposed) {
                foreach ($tab in $global:tabControl.TabPages) {
                    foreach ($c in $tab.Controls) {
                        if (-not [string]::IsNullOrWhiteSpace($c.AccessibleName)) {
                            $c.Font = Get-UltixFittedFont -Control $c -Role $c.AccessibleName
                        }
                    }
                }
            }
            if ($null -ne $global:btnFontDec -and -not $global:btnFontDec.IsDisposed) {
                $global:btnFontDec.Enabled = ($newOffset -gt -1.0)
            }
            if ($null -ne $global:btnFontInc -and -not $global:btnFontInc.IsDisposed) {
                $global:btnFontInc.Enabled = ($newOffset -lt 1.5)
            }
        } finally {
            $global:form.ResumeLayout($true)
        }
    }

    $sign = if ($newOffset -gt 0) { "+$newOffset" } else { "$newOffset" }
    Show-Description "UI Font Scale: $sign pt (Bounds: -1.0 pt Min to +1.5 pt Max | Main Buttons: $($global:UltixTypography.MainBtnSize + $newOffset) pt)."
}

function New-UltixButton {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$X,
        [Parameter(Mandatory=$true)][int]$Y,
        [int]$Width = 370,
        [int]$Height = 40,
        [int[]]$RGB = @(55, 58, 64),
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White,
        [System.Drawing.Font]$Font = $null,
        [string]$Description = "",
        [scriptblock]$OnClick = $null,
        [System.Windows.Forms.Control]$Parent = $null
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($Width, $Height)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(255, $RGB[0], $RGB[1], $RGB[2])
    $btn.ForeColor = $ForeColor
    $btn.FlatStyle = "Flat"
    $btn.UseMnemonic = $false

    if ($null -ne $Font) {
        $btn.Font = $Font
    } else {
        if ($Parent -is [System.Windows.Forms.Form]) {
            if ($Height -le 30) {
                $btn.AccessibleName = "ToolbarButton"
            } else {
                $btn.AccessibleName = "ModalAction"
            }
        } elseif ($Width -le 45) {
            $btn.AccessibleName = "IconButton"
        } elseif ($Width -le 245) {
            $btn.AccessibleName = "CompactButton"
        } else {
            $btn.AccessibleName = "MainButton"
        }
        $btn.Font = Get-UltixFittedFont -Control $btn -Role $btn.AccessibleName
        $btn.Add_TextChanged({
            if (-not [string]::IsNullOrWhiteSpace($this.AccessibleName)) {
                $this.Font = Get-UltixFittedFont -Control $this -Role $this.AccessibleName
            }
        })
    }

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $btn.AccessibleDescription = $Description
        $btn.Add_MouseEnter({ Show-Description $this.AccessibleDescription })
        $btn.Add_MouseLeave({ Restore-Log })
    }
    if ($null -ne $OnClick) {
        $btn.Add_Click($OnClick)
    }
    if ($null -ne $Parent) {
        $Parent.Controls.Add($btn)
    }
    return $btn
}

function New-UltixActionRow {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$Y,
        [int[]]$MainRGB = @(55, 58, 64),
        [int[]]$AuditRGB = @(72, 76, 82),
        [string]$Description = "",
        [string]$AuditDescription = "",
        [scriptblock]$OnClick = $null,
        [scriptblock]$OnAudit = $null,
        [System.Windows.Forms.Control]$Parent = $null
    )
    $btnMain = New-UltixButton -Text $Text -X 15 -Y $Y -Width 320 -Height 40 -RGB $MainRGB -Description $Description -OnClick $OnClick -Parent $Parent
    $btnAudit = New-UltixButton -Text "?" -X 345 -Y $Y -Width 40 -Height 40 -RGB $AuditRGB -Description $AuditDescription -OnClick $OnAudit -Parent $Parent

    return [PSCustomObject]@{
        MainButton  = $btnMain
        AuditButton = $btnAudit
        Controls    = [System.Windows.Forms.Control[]]@($btnMain, $btnAudit)
    }
}

# ------------------------------------------
# 4. ASYNCHRONOUS RUNSPACE ENGINE & AUDIT DISPATCHER
# ------------------------------------------
function Invoke-AsyncTask {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [array]$Arguments = @(),
        [Parameter(Mandatory=$true)][scriptblock]$OnComplete,
        [scriptblock]$OnError = $null,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [int]$PollIntervalMs = 150
    )

    # Re-entrancy guard: if already executing inside a background Runspace, run synchronously without resetting outer progress
    if ($null -ne $UltixSync) {
        $prevLock = $UltixSync.LockProgress
        $prevProg = $UltixSync.Progress
        $UltixSync.LockProgress = $true
        try {
            $nestedOut = & $ScriptBlock @Arguments
            if ($null -ne $OnComplete) { & $OnComplete $nestedOut }
        } finally {
            $UltixSync.LockProgress = $prevLock
            $UltixSync.Progress     = $prevProg
        }
        return
    }

    foreach ($ctrl in $ControlsToDisable) {
        if ($null -ne $ctrl -and -not $ctrl.IsDisposed) { $ctrl.Enabled = $false }
    }

    $syncContext = [hashtable]::Synchronized(@{
        Logs         = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        Progress     = -1
        LockProgress = $false
    })

    # Pre-hydrate toolkit functions into isolated Runspace InitialSessionState
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $fnRoster = if ($null -ne $Global:UltixToolkitFunctions -and $Global:UltixToolkitFunctions.Count -gt 0) {
        $Global:UltixToolkitFunctions
    } else {
        @("Get-UltixUserProfiles", "Get-UltixFastSize", "Set-ProtectedServiceStart", "Get-UltixPowerAcIndex")
    }

    foreach ($fnName in $fnRoster) {
        if ($fnName -in @("Write-GUI", "Update-Progress", "Show-Description", "Restore-Log")) { continue }
        $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $fnName, $cmd.Definition))
        }
    }

    # Inject thread-safe UI shims so any helper calling Write-GUI / Update-Progress inside a Runspace routes through $UltixSync
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList "Write-GUI", 'param([AllowEmptyString()][string]$Message, [switch]$DeferUpdate) if ($null -ne $UltixSync -and -not [string]::IsNullOrWhiteSpace($Message)) { $UltixSync.Logs.Enqueue($Message) }'))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList "Update-Progress", 'param([int]$Percent) if ($null -ne $UltixSync -and -not $UltixSync.LockProgress) { $UltixSync.Progress = $Percent }'))

    if ($null -eq $global:UltixActiveTasks) {
        $global:UltixActiveTasks = [System.Collections.Generic.List[hashtable]]::new()
    }

    $runspace = $null
    $ps       = $null
    $timer    = $null
    $taskEntry = $null

    try {
        $runspace = [runspacefactory]::CreateRunspace($iss)
        $runspace.ApartmentState = "STA"
        $runspace.ThreadOptions  = "ReuseThread"
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable("UltixSync", $syncContext)
        $runspace.SessionStateProxy.SetVariable("AppVersion", $Global:AppVersion)
        $runspace.SessionStateProxy.SetVariable("ScriptDir", $ScriptDir)

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace
        [void]$ps.AddScript($ScriptBlock)
        foreach ($arg in $Arguments) {
            [void]$ps.AddArgument($arg)
        }

        $asyncResult = $ps.BeginInvoke()

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = $PollIntervalMs
        $taskEntry = @{
            PS           = $ps
            Runspace     = $runspace
            AsyncResult  = $asyncResult
            Controls     = $ControlsToDisable
            OnComplete   = $OnComplete
            OnError      = $OnError
            SyncContext  = $syncContext
            Timer        = $timer
            LastProgress = -1
        }
        $timer.Tag = $taskEntry
        [void]$global:UltixActiveTasks.Add($taskEntry)
    } catch {
        if ($null -ne $ps) { try { $ps.Dispose() } catch { } }
        if ($null -ne $runspace) { try { $runspace.Close(); $runspace.Dispose() } catch { } }
        foreach ($ctrl in $ControlsToDisable) {
            if ($null -ne $ctrl -and -not $ctrl.IsDisposed) { $ctrl.Enabled = $true }
        }
        Write-GUI "  [ERROR] Failed to initialize background Runspace: $($_.Exception.Message)"
        return
    }

    $timer.Add_Tick({
        $state = $this.Tag
        $sync  = $state.SyncContext

        $dequeuedAny = $false
        $logLine = $null
        while ($sync.Logs.TryDequeue([ref]$logLine)) {
            Write-GUI -Message $logLine -DeferUpdate
            $dequeuedAny = $true
        }
        if ($dequeuedAny -and $null -ne $global:infoBox -and -not $global:infoBox.IsDisposed) {
            $global:infoBox.ScrollToCaret()
            $global:infoBox.Update()
        }

        if ($sync.Progress -ge 0 -and $sync.Progress -ne $state.LastProgress) {
            $state.LastProgress = $sync.Progress
            Update-Progress $sync.Progress
        }

        if (-not $state.AsyncResult.IsCompleted) { return }

        $this.Stop()
        $taskOutput = $null
        $taskError  = $null

        try {
            $taskOutput = $state.PS.EndInvoke($state.AsyncResult)
        } catch {
            $taskError = $_
        } finally {
            $dequeuedFinal = $false
            while ($sync.Logs.TryDequeue([ref]$logLine)) {
                Write-GUI -Message $logLine -DeferUpdate
                $dequeuedFinal = $true
            }
            if ($dequeuedFinal -and $null -ne $global:infoBox -and -not $global:infoBox.IsDisposed) {
                $global:infoBox.ScrollToCaret()
                $global:infoBox.Update()
            }
            if ($null -ne $global:UltixActiveTasks) {
                [void]$global:UltixActiveTasks.Remove($state)
            }
            $state.PS.Dispose()
            $state.Runspace.Close()
            $state.Runspace.Dispose()
            $this.Dispose()
            foreach ($ctrl in $state.Controls) {
                if ($null -ne $ctrl -and -not $ctrl.IsDisposed) { $ctrl.Enabled = $true }
            }
        }

        if ($null -ne $taskError) {
            Update-Progress 0
            $errDetail = $taskError.Exception.Message
            if ($null -ne $taskError.Exception.InnerException -and -not [string]::IsNullOrWhiteSpace($taskError.Exception.InnerException.Message)) {
                $errDetail = $taskError.Exception.InnerException.Message
            }
            Write-GUI "  [ERROR] Background task failed: $errDetail"
            if ($null -ne $state.OnError) {
                & $state.OnError $errDetail
            }
            return
        }

        if ($null -ne $state.OnComplete) {
            & $state.OnComplete $taskOutput
        }
    })

    $timer.Start()
}

function Invoke-UltixAuditFlow {
    param(
        [Parameter(Mandatory=$true)][string]$ScannerFunction,
        [array]$ScannerArguments = @(),
        [Parameter(Mandatory=$true)][string]$AuditLabel,
        [string]$ModalTitle = "",
        [string]$ModalDescription = "",
        [string]$ExecutorFunction = "",
        [hashtable]$ExecutorExtraParams = @{},
        [scriptblock]$PostExecuteScript = $null,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [switch]$AuditOnly,
        [switch]$EnableRevert,
        [switch]$SkipModalIfClean,
        [string]$AuditPrefix = "Detected"
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: $AuditLabel (Background Thread) ---"
    } else {
        Write-GUI " -> Scanning $AuditLabel (Background Thread)..."
    }
    Update-Progress 5

    $sb          = (Get-Command -Name $ScannerFunction).ScriptBlock
    $isAuditOnly = $AuditOnly.IsPresent
    $skipClean   = $SkipModalIfClean.IsPresent
    $useRevert   = $EnableRevert.IsPresent

    Invoke-AsyncTask -ScriptBlock $sb -Arguments $ScannerArguments -ControlsToDisable $ControlsToDisable -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$auditData = @($output | Where-Object { $null -ne $_ })
        $detected = @($auditData | Where-Object { $_.IsDetected })

        if ($isAuditOnly) {
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) {
                    $isOpt = (
                        ($d.PSObject.Properties.Match("OptIn").Count -gt 0 -and [bool]$d.OptIn) -or
                        ($null -ne $d.ActionData -and $d.ActionData -is [hashtable] -and $d.ActionData.OptIn -eq $true)
                    )
                    if ($isOpt) {
                        Write-GUI "  [*] Optional (${AuditPrefix}): $($d.UIDisplayName)"
                    } else {
                        Write-GUI "  [!] ${AuditPrefix}: $($d.UIDisplayName)"
                    }
                }
                Write-GUI "-> STATUS: $($detected.Count) item(s) flagged.`n"
            } else {
                Write-GUI "  [OK] Optimized / Clean.`n"
            }
            return
        }

        if ($skipClean -and $detected.Count -eq 0) {
            Write-GUI "  [OK] System is completely clean. Nothing to process.`n"
            return
        }

        $modalRes = Show-ActionModal -Title $ModalTitle -Description $ModalDescription -AuditResults $auditData -EnableRevert:$useRevert
        if ($null -ne $modalRes -and $null -ne $modalRes.Items -and $modalRes.Items.Count -gt 0) {
            $execCmd = Get-Command -Name $ExecutorFunction -ErrorAction SilentlyContinue
            if ($null -ne $execCmd) {
                $invokeParams = @{ SelectedItems = $modalRes.Items }
                if ($execCmd.Parameters.ContainsKey("Operation")) {
                    $invokeParams["Operation"] = $modalRes.Action
                }
                if ($execCmd.Parameters.ContainsKey("ControlsToDisable")) {
                    $invokeParams["ControlsToDisable"] = $ControlsToDisable
                }
                foreach ($kvp in $ExecutorExtraParams.GetEnumerator()) {
                    $invokeParams[$kvp.Key] = $kvp.Value
                }
                & $ExecutorFunction @invokeParams
            }
            if ($null -ne $PostExecuteScript) {
                & $PostExecuteScript $modalRes.Items $modalRes.Action
            }
        } else {
            Write-GUI " -> Operation cancelled.`n"
        }
    }.GetNewClosure())
}

# ------------------------------------------
# 5. INTERACTIVE MODALS (ACTION MODAL & SORTABLE GRID MODAL)
# ------------------------------------------
function Show-ActionModal {
    param (
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$AuditResults,
        [switch]$EnableRevert
    )
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title
    $modal.Size = New-Object System.Drawing.Size(780, 680)
    $modal.MinimumSize = New-Object System.Drawing.Size(780, 520)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "Sizable"
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 26, 27, 30)
    $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = $Description
    $lblDesc.UseMnemonic = $false
    $lblDesc.Location = New-Object System.Drawing.Point(15, 10)
    $lblDesc.Size = New-Object System.Drawing.Size(730, 38)
    $lblDesc.Font = Get-UltixFont -Role "ModalDesc"
    $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 225, 232)
    $lblDesc.Anchor = 'Top, Left, Right'

    $hasValidItems = ($null -ne $AuditResults -and $AuditResults.Count -gt 0)

    $btnSelAll = New-Object System.Windows.Forms.Button
    $btnSelAll.Text = "Select All"
    $btnSelAll.UseMnemonic = $false
    $btnSelAll.Location = New-Object System.Drawing.Point(15, 51)
    $btnSelAll.Size = New-Object System.Drawing.Size(118, 30)
    $btnSelAll.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
    $btnSelAll.ForeColor = [System.Drawing.Color]::White
    $btnSelAll.FlatStyle = "Flat"
    $btnSelAll.Font = Get-UltixFittedFont -Control $btnSelAll -Role "ToolbarButton"
    $btnSelAll.Enabled = $hasValidItems

    $btnSelNone = New-Object System.Windows.Forms.Button
    $btnSelNone.Text = "Deselect All"
    $btnSelNone.UseMnemonic = $false
    $btnSelNone.Location = New-Object System.Drawing.Point(140, 51)
    $btnSelNone.Size = New-Object System.Drawing.Size(118, 30)
    $btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
    $btnSelNone.ForeColor = [System.Drawing.Color]::White
    $btnSelNone.FlatStyle = "Flat"
    $btnSelNone.Font = Get-UltixFittedFont -Control $btnSelNone -Role "ToolbarButton"
    $btnSelNone.Enabled = $hasValidItems

    $btnSelDet = New-Object System.Windows.Forms.Button
    $btnSelDet.Text = "Select Detected"
    $btnSelDet.UseMnemonic = $false
    $btnSelDet.Location = New-Object System.Drawing.Point(265, 51)
    $btnSelDet.Size = New-Object System.Drawing.Size(140, 30)
    $btnSelDet.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
    $btnSelDet.ForeColor = [System.Drawing.Color]::White
    $btnSelDet.FlatStyle = "Flat"
    $btnSelDet.Font = Get-UltixFittedFont -Control $btnSelDet -Role "ToolbarButton"
    $btnSelDet.Enabled = $hasValidItems

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(545, 56)
    $lblCount.Size = New-Object System.Drawing.Size(200, 22)
    $lblCount.Font = New-Object System.Drawing.Font("Consolas", 10.0, [System.Drawing.FontStyle]::Bold)
    $lblCount.ForeColor = [System.Drawing.Color]::LightGray
    $lblCount.TextAlign = "MiddleRight"
    $lblCount.Anchor = 'Top, Right'
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox
    $chkList.Location = New-Object System.Drawing.Point(15, 88)
    $chkList.Size = New-Object System.Drawing.Size(730, 480)
    $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38)
    $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
    $chkList.BorderStyle = "FixedSingle"
    $chkList.Font = Get-UltixFont -Role "GridMono"
    $chkList.CheckOnClick = $false
    $chkList.HorizontalScrollbar = $true
    $chkList.Anchor = 'Top, Bottom, Left, Right'

    if ($hasValidItems) {
        $chkList.BeginUpdate()
        foreach ($item in $AuditResults) {
            $isOptIn = (
                ($item.PSObject.Properties.Match("OptIn").Count -gt 0 -and [bool]$item.OptIn) -or
                ($null -ne $item.ActionData -and $item.ActionData -is [hashtable] -and $item.ActionData.OptIn -eq $true)
            )
            if ($item.IsDetected) {
                if ($isOptIn) {
                    [void]$chkList.Items.Add("[ OPTIONAL ]  " + $item.UIDisplayName, $false)
                } else {
                    [void]$chkList.Items.Add("[ DETECTED ]  " + $item.UIDisplayName, $true)
                }
            } else { 
                [void]$chkList.Items.Add("[ OPTIMIZED ] " + $item.UIDisplayName, $false) 
            }
        }
        $chkList.EndUpdate()
        $lblCount.Text = "Selected: $($chkList.CheckedIndices.Count) / $($AuditResults.Count)"
    } else { 
        [void]$chkList.Items.Add("No actionable items returned from audit scanner.", $false)
        $chkList.Enabled = $false
        $lblCount.Text = "Selected: 0 / 0"
    }

    $updateCounter = ({
        param([int]$Delta = 0)
        $totalChecked = $chkList.CheckedIndices.Count + $Delta
        $lblCount.Text = "Selected: $totalChecked / $($chkList.Items.Count)"
    }.GetNewClosure())

    $chkList.Add_ItemCheck({
        param($src, $e)
        $delta = if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) { 1 } else { -1 }
        & $updateCounter $delta
    }.GetNewClosure())

    $btnSelAll.Add_Click({
        $chkList.BeginUpdate()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) { $chkList.SetItemChecked($i, $true) }
        $chkList.EndUpdate()
        & $updateCounter 0
    }.GetNewClosure())

    $btnSelNone.Add_Click({
        $chkList.BeginUpdate()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) { $chkList.SetItemChecked($i, $false) }
        $chkList.EndUpdate()
        & $updateCounter 0
    }.GetNewClosure())

    $btnSelDet.Add_Click({
        $chkList.BeginUpdate()
        for ($i = 0; $i -lt $AuditResults.Count; $i++) {
            $item = $AuditResults[$i]
            $isOptIn = (
                ($item.PSObject.Properties.Match("OptIn").Count -gt 0 -and [bool]$item.OptIn) -or
                ($null -ne $item.ActionData -and $item.ActionData -is [hashtable] -and $item.ActionData.OptIn -eq $true)
            )
            $chkList.SetItemChecked($i, ([bool]$item.IsDetected -and -not $isOptIn))
        }
        $chkList.EndUpdate()
        & $updateCounter 0
    }.GetNewClosure())

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Execute Selected"
    $btnApply.UseMnemonic = $false
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $btnApply.FlatStyle = "Flat"
    $btnApply.DialogResult = "OK"
    $btnApply.Enabled = $hasValidItems
    $btnApply.Anchor = 'Bottom, Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.UseMnemonic = $false
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.DialogResult = "Cancel"
    $btnCancel.Anchor = 'Bottom, Right'

    $baseControls = @($lblDesc, $btnSelAll, $btnSelNone, $btnSelDet, $lblCount, $chkList)

    if ($EnableRevert) {
        $btnApply.Location = New-Object System.Drawing.Point(15, 585)
        $btnApply.Size = New-Object System.Drawing.Size(235, 36)
        $btnApply.Font = Get-UltixFittedFont -Control $btnApply -Role "ModalAction"

        $btnRevert = New-Object System.Windows.Forms.Button
        $btnRevert.Text = "Revert Selected"
        $btnRevert.UseMnemonic = $false
        $btnRevert.Location = New-Object System.Drawing.Point(262, 585)
        $btnRevert.Size = New-Object System.Drawing.Size(235, 36)
        $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
        $btnRevert.ForeColor = [System.Drawing.Color]::White
        $btnRevert.FlatStyle = "Flat"
        $btnRevert.Font = Get-UltixFittedFont -Control $btnRevert -Role "ModalAction"
        $btnRevert.DialogResult = "Yes"
        $btnRevert.Enabled = $hasValidItems
        $btnRevert.Anchor = 'Bottom, Left'
        
        $btnCancel.Location = New-Object System.Drawing.Point(510, 585)
        $btnCancel.Size = New-Object System.Drawing.Size(235, 36)
        $btnCancel.Font = Get-UltixFittedFont -Control $btnCancel -Role "ModalAction"

        $modal.Controls.AddRange($baseControls + @($btnApply, $btnRevert, $btnCancel))
    } else {
        $btnApply.Location = New-Object System.Drawing.Point(15, 585)
        $btnApply.Size = New-Object System.Drawing.Size(355, 36)
        $btnApply.Font = Get-UltixFittedFont -Control $btnApply -Role "ModalAction"

        $btnCancel.Location = New-Object System.Drawing.Point(390, 585)
        $btnCancel.Size = New-Object System.Drawing.Size(355, 36)
        $btnCancel.Font = Get-UltixFittedFont -Control $btnCancel -Role "ModalAction"

        $modal.Controls.AddRange($baseControls + @($btnApply, $btnCancel))
    }

    $modal.AcceptButton = $btnApply
    $modal.CancelButton = $btnCancel

    try {
        $useOwner = ($null -ne $global:form -and -not $global:form.IsDisposed -and -not $global:form.InvokeRequired)
        $result   = if ($useOwner) { $modal.ShowDialog($global:form) } else { $modal.ShowDialog() }
        if ($hasValidItems -and ($result -eq "OK" -or $result -eq "Yes")) {
            $selectedItems = [System.Collections.Generic.List[object]]::new()
            foreach ($idx in $chkList.CheckedIndices) {
                $selectedItems.Add($AuditResults[$idx])
            }
            # Convenience for single-item modals (e.g. Clean Start Menu Compiler): auto-select the sole item if clicked directly
            if ($selectedItems.Count -eq 0 -and $AuditResults.Count -eq 1) {
                $selectedItems.Add($AuditResults[0])
            }
            $actionData = if ($result -eq "OK") { "Apply" } else { "Revert" }
            return [PSCustomObject]@{ Action = $actionData; Items = @($selectedItems) }
        }
        return $null
    } finally {
        $modal.Dispose()
    }
}

function Show-UltixGridModal {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$Data,
        [Parameter(Mandatory=$true)][array]$Columns,
        [string]$PrimaryButtonText = "Remove Selected",
        [string]$SecondaryButtonText = "",
        [switch]$SecondaryAlwaysEnabled
    )

    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title
    $modal.Size = New-Object System.Drawing.Size(980, 700)
    $modal.MinimumSize = New-Object System.Drawing.Size(980, 560)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "Sizable"
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 26, 27, 30)
    $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = $Description
    $lblDesc.UseMnemonic = $false
    $lblDesc.Location = New-Object System.Drawing.Point(15, 10)
    $lblDesc.Size = New-Object System.Drawing.Size(935, 38)
    $lblDesc.Font = Get-UltixFont -Role "ModalDesc"
    $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 225, 232)
    $lblDesc.Anchor = 'Top, Left, Right'

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Filter:"
    $lblSearch.Location = New-Object System.Drawing.Point(15, 55)
    $lblSearch.Size = New-Object System.Drawing.Size(52, 22)
    $lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
    $lblSearch.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(68, 52)
    $txtSearch.Size = New-Object System.Drawing.Size(265, 26)
    $txtSearch.BackColor = [System.Drawing.Color]::FromArgb(255, 38, 40, 45)
    $txtSearch.ForeColor = [System.Drawing.Color]::White
    $txtSearch.BorderStyle = "FixedSingle"
    $txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)

    $btnSelVis = New-Object System.Windows.Forms.Button
    $btnSelVis.Text = "Select Visible"
    $btnSelVis.UseMnemonic = $false
    $btnSelVis.Location = New-Object System.Drawing.Point(343, 50)
    $btnSelVis.Size = New-Object System.Drawing.Size(124, 30)
    $btnSelVis.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
    $btnSelVis.ForeColor = [System.Drawing.Color]::White
    $btnSelVis.FlatStyle = "Flat"
    $btnSelVis.Font = Get-UltixFittedFont -Control $btnSelVis -Role "ToolbarButton"

    $btnSelNone = New-Object System.Windows.Forms.Button
    $btnSelNone.Text = "Deselect All"
    $btnSelNone.UseMnemonic = $false
    $btnSelNone.Location = New-Object System.Drawing.Point(475, 50)
    $btnSelNone.Size = New-Object System.Drawing.Size(124, 30)
    $btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
    $btnSelNone.ForeColor = [System.Drawing.Color]::White
    $btnSelNone.FlatStyle = "Flat"
    $btnSelNone.Font = Get-UltixFittedFont -Control $btnSelNone -Role "ToolbarButton"

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(605, 55)
    $lblCount.Size = New-Object System.Drawing.Size(340, 22)
    $lblCount.Font = New-Object System.Drawing.Font("Consolas", 10.0, [System.Drawing.FontStyle]::Bold)
    $lblCount.ForeColor = [System.Drawing.Color]::LightGray
    $lblCount.TextAlign = "MiddleRight"
    $lblCount.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 88)
    $listView.Size = New-Object System.Drawing.Size(935, 500)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
    $listView.BorderStyle = "FixedSingle"
    $listView.Font = Get-UltixFont -Role "GridText"
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    # Disable harsh white Win32 gridlines; use alternating dark row shading instead
    $listView.GridLines = $false
    $listView.Anchor = 'Top, Bottom, Left, Right'

    Enable-UltixDoubleBuffer -Control $listView

    $sorter = New-Object WinUltix.ListViewColumnSorter
    $listView.ListViewItemSorter = $sorter

    $totalColWidth = 0
    for ($cIdx = 0; $cIdx -lt $Columns.Count; $cIdx++) {
        $colW = [int]$Columns[$cIdx].Width
        if ($cIdx -eq ($Columns.Count - 1) -and ($totalColWidth + $colW) -lt 905) {
            $colW = 905 - $totalColWidth
        }
        $totalColWidth += $colW
        [void]$listView.Columns.Add($Columns[$cIdx].Header, $colW)
    }

    # High-contrast, zero-glare dark theme palette for grid rows
    $bgEven    = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $bgOdd     = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
    $bgLocked  = [System.Drawing.Color]::FromArgb(255, 54, 26, 28)
    $bgGhost   = [System.Drawing.Color]::FromArgb(255, 48, 38, 20)

    $fgNormal  = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
    $fgLocked  = [System.Drawing.Color]::FromArgb(255, 255, 155, 155)
    $fgGhost   = [System.Drawing.Color]::FromArgb(255, 255, 210, 90)
    $fgStopped = [System.Drawing.Color]::FromArgb(255, 170, 188, 208)
    $fgMuted   = [System.Drawing.Color]::FromArgb(255, 125, 134, 145)

    $indexedData = [System.Collections.Generic.List[PSCustomObject]]::new()
    for ($i = 0; $i -lt $Data.Count; $i++) {
        $indexedData.Add([PSCustomObject]@{
            RowId = $i
            Item  = $Data[$i]
        })
    }
    $checkedIds = [System.Collections.Generic.HashSet[int]]::new()
    $syncGuard  = @{ SuppressEvents = $false }

    $updateCounter = ({
        $lblCount.Text = "Selected: $($checkedIds.Count) / $($indexedData.Count) (Showing: $($listView.Items.Count))"
    }.GetNewClosure())

    $applyRowShading = ({
        for ($r = 0; $r -lt $listView.Items.Count; $r++) {
            $it = $listView.Items[$r]
            $rowObj = $indexedData[[int]$it.Tag].Item
            $isLockedRow = ($rowObj.PSObject.Properties.Match("IsLocked").Count -gt 0 -and [bool]$rowObj.IsLocked)
            $isGhostRow  = ($rowObj.PSObject.Properties.Match("Category").Count -gt 0 -and [string]$rowObj.Category -match "GHOST")

            if ($isLockedRow) {
                $it.BackColor = $bgLocked
            } elseif ($isGhostRow) {
                $it.BackColor = $bgGhost
            } else {
                $it.BackColor = if (($r % 2) -eq 0) { $bgEven } else { $bgOdd }
            }
        }
    }.GetNewClosure())

    $populateList = ({
        param([string]$FilterText = "")
        $syncGuard.SuppressEvents = $true
        $listView.BeginUpdate()
        $listView.ListViewItemSorter = $null
        $listView.Items.Clear()

        $cleanFilter = $FilterText.Trim()
        $visIdx = 0
        foreach ($entry in $indexedData) {
            $obj = $entry.Item
            if ($cleanFilter.Length -gt 0) {
                $matched = $false
                foreach ($col in $Columns) {
                    $val = [string]$obj.($col.Property)
                    if ($val.IndexOf($cleanFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $matched = $true
                        break
                    }
                }
                if (-not $matched) { continue }
            }

            $isLockedRow = ($obj.PSObject.Properties.Match("IsLocked").Count -gt 0 -and [bool]$obj.IsLocked)
            $isGhostRow  = ($obj.PSObject.Properties.Match("Category").Count -gt 0 -and [string]$obj.Category -match "GHOST")

            $firstVal = [string]$obj.($Columns[0].Property)
            $lvItem = New-Object System.Windows.Forms.ListViewItem($firstVal)
            for ($c = 1; $c -lt $Columns.Count; $c++) {
                $subVal = [string]$obj.($Columns[$c].Property)
                [void]$lvItem.SubItems.Add($subVal)
            }
            $lvItem.Tag = $entry.RowId
            $lvItem.Checked = (-not $isLockedRow) -and $checkedIds.Contains($entry.RowId)

            if ($isLockedRow) {
                $lvItem.BackColor = $bgLocked
                $lvItem.ForeColor = $fgLocked
            } elseif ($isGhostRow) {
                $lvItem.BackColor = $bgGhost
                $lvItem.ForeColor = $fgGhost
            } else {
                $lvItem.BackColor = if (($visIdx % 2) -eq 0) { $bgEven } else { $bgOdd }
                if ($obj.PSObject.Properties.Match("State").Count -gt 0 -and [string]$obj.State -match "^Disabled") {
                    $lvItem.ForeColor = $fgMuted
                } elseif ($obj.PSObject.Properties.Match("Status").Count -gt 0 -and [string]$obj.Status -eq "Stopped") {
                    $lvItem.ForeColor = $fgStopped
                } else {
                    $lvItem.ForeColor = $fgNormal
                }
            }

            [void]$listView.Items.Add($lvItem)
            $visIdx++
        }

        $listView.ListViewItemSorter = $sorter
        if ($sorter.OrderOfSort -ne [System.Windows.Forms.SortOrder]::None) {
            & $applyRowShading
        }
        $listView.EndUpdate()
        $syncGuard.SuppressEvents = $false
        & $updateCounter
    }.GetNewClosure())

    $listView.Add_ItemCheck({
        param($src, $e)
        if ($syncGuard.SuppressEvents) { return }
        $lvItem = $src.Items[$e.Index]
        if ($null -ne $lvItem -and $null -ne $lvItem.Tag) {
            $rowObj = $indexedData[[int]$lvItem.Tag].Item
            if ($rowObj.PSObject.Properties.Match("IsLocked").Count -gt 0 -and [bool]$rowObj.IsLocked) {
                $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
            }
        }
    }.GetNewClosure())

    $listView.Add_ItemChecked({
        param($src, $e)
        if ($syncGuard.SuppressEvents) { return }
        $rowId  = [int]$e.Item.Tag
        $rowObj = $indexedData[$rowId].Item
        if ($rowObj.PSObject.Properties.Match("IsLocked").Count -gt 0 -and [bool]$rowObj.IsLocked) {
            if ($e.Item.Checked) {
                $syncGuard.SuppressEvents = $true
                $e.Item.Checked = $false
                $syncGuard.SuppressEvents = $false
            }
            [void]$checkedIds.Remove($rowId)
            return
        }
        if ($e.Item.Checked) {
            [void]$checkedIds.Add($rowId)
        } else {
            [void]$checkedIds.Remove($rowId)
        }
        & $updateCounter
    }.GetNewClosure())

    $listView.Add_ColumnClick({
        param($src, $e)
        $listView.BeginUpdate()
        if ($e.Column -eq $sorter.ColumnToSort) {
            if ($sorter.OrderOfSort -eq [System.Windows.Forms.SortOrder]::Ascending) {
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending
            } else {
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending
            }
        } else {
            $sorter.ColumnToSort = $e.Column
            $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending
        }
        $listView.Sort()
        & $applyRowShading
        $listView.EndUpdate()
    }.GetNewClosure())

    $txtSearch.Add_TextChanged({
        & $populateList $txtSearch.Text
    }.GetNewClosure())

    $btnSelVis.Add_Click({
        $syncGuard.SuppressEvents = $true
        $listView.BeginUpdate()
        foreach ($lvItem in $listView.Items) {
            $rowId  = [int]$lvItem.Tag
            $rowObj = $indexedData[$rowId].Item
            if ($rowObj.PSObject.Properties.Match("IsLocked").Count -gt 0 -and [bool]$rowObj.IsLocked) {
                $lvItem.Checked = $false
                continue
            }
            $lvItem.Checked = $true
            [void]$checkedIds.Add($rowId)
        }
        $listView.EndUpdate()
        $syncGuard.SuppressEvents = $false
        & $updateCounter
    }.GetNewClosure())

    $btnSelNone.Add_Click({
        $syncGuard.SuppressEvents = $true
        $checkedIds.Clear()
        $listView.BeginUpdate()
        foreach ($lvItem in $listView.Items) {
            $lvItem.Checked = $false
        }
        $listView.EndUpdate()
        $syncGuard.SuppressEvents = $false
        & $updateCounter
    }.GetNewClosure())

    & $populateList ""

    $btnPrimary = New-Object System.Windows.Forms.Button
    $btnPrimary.Text = $PrimaryButtonText
    $btnPrimary.UseMnemonic = $false
    $btnPrimary.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnPrimary.ForeColor = [System.Drawing.Color]::White
    $btnPrimary.FlatStyle = "Flat"
    $btnPrimary.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnPrimary.Enabled = ($indexedData.Count -gt 0)
    $btnPrimary.Anchor = 'Bottom, Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.UseMnemonic = $false
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Anchor = 'Bottom, Right'

    $controlsToAdd = @($lblDesc, $lblSearch, $txtSearch, $btnSelVis, $btnSelNone, $lblCount, $listView, $btnPrimary, $btnCancel)

    if (-not [string]::IsNullOrWhiteSpace($SecondaryButtonText)) {
        $btnPrimary.Location = New-Object System.Drawing.Point(15, 602)
        $btnPrimary.Size = New-Object System.Drawing.Size(295, 38)
        $btnPrimary.Font = Get-UltixFittedFont -Control $btnPrimary -Role "ModalAction"

        $btnSecondary = New-Object System.Windows.Forms.Button
        $btnSecondary.Text = $SecondaryButtonText
        $btnSecondary.UseMnemonic = $false
        $btnSecondary.Location = New-Object System.Drawing.Point(322, 602)
        $btnSecondary.Size = New-Object System.Drawing.Size(295, 38)
        $btnSecondary.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
        $btnSecondary.ForeColor = [System.Drawing.Color]::White
        $btnSecondary.FlatStyle = "Flat"
        $btnSecondary.Font = Get-UltixFittedFont -Control $btnSecondary -Role "ModalAction"
        $btnSecondary.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $btnSecondary.Enabled = ($SecondaryAlwaysEnabled.IsPresent -or $indexedData.Count -gt 0)
        $btnSecondary.Anchor = 'Bottom, Left'

        $btnCancel.Location = New-Object System.Drawing.Point(630, 602)
        $btnCancel.Size = New-Object System.Drawing.Size(320, 38)
        $btnCancel.Font = Get-UltixFittedFont -Control $btnCancel -Role "ModalAction"
        $controlsToAdd += $btnSecondary
    } else {
        $btnPrimary.Location = New-Object System.Drawing.Point(15, 602)
        $btnPrimary.Size = New-Object System.Drawing.Size(455, 38)
        $btnPrimary.Font = Get-UltixFittedFont -Control $btnPrimary -Role "ModalAction"

        $btnCancel.Location = New-Object System.Drawing.Point(495, 602)
        $btnCancel.Size = New-Object System.Drawing.Size(455, 38)
        $btnCancel.Font = Get-UltixFittedFont -Control $btnCancel -Role "ModalAction"
    }

    $modal.Controls.AddRange($controlsToAdd)
    $modal.CancelButton = $btnCancel

    try {
        $useOwner = ($null -ne $global:form -and -not $global:form.IsDisposed -and -not $global:form.InvokeRequired)
        $dlgRes   = if ($useOwner) { $modal.ShowDialog($global:form) } else { $modal.ShowDialog() }
        if ($dlgRes -eq [System.Windows.Forms.DialogResult]::Yes -and $SecondaryAlwaysEnabled.IsPresent) {
            $selectedList = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $indexedData) {
                if ($checkedIds.Contains($entry.RowId)) {
                    $selectedList.Add($entry.Item)
                }
            }
            return [PSCustomObject]@{
                Action = "Secondary"
                Items  = @($selectedList)
            }
        }
        if ($checkedIds.Count -gt 0 -and ($dlgRes -eq [System.Windows.Forms.DialogResult]::OK -or $dlgRes -eq [System.Windows.Forms.DialogResult]::Yes)) {
            $selectedList = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $indexedData) {
                if ($checkedIds.Contains($entry.RowId)) {
                    $selectedList.Add($entry.Item)
                }
            }
            $actionName = if ($dlgRes -eq [System.Windows.Forms.DialogResult]::OK) { "Primary" } else { "Secondary" }
            return [PSCustomObject]@{
                Action = $actionName
                Items  = @($selectedList)
            }
        }
        return $null
    } finally {
        $modal.Dispose()
    }
}

# ------------------------------------------
# 6. JSON PROFILE SNAPSHOT ENGINE (EXPORT / IMPORT)
# ------------------------------------------
function Export-WinUltixProfile {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "WinUltix Profile (*.json)|*.json"
    $sfd.Title = "Export WinUltix Configuration Snapshot"
    $sfd.FileName = "WinUltix_Profile_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd').json"
    $sfd.InitialDirectory = [Environment]::GetFolderPath("Desktop")

    try {
        if ($sfd.ShowDialog($global:form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $targetFile = $sfd.FileName
    } finally {
        $sfd.Dispose()
    }

    Write-GUI " -> Auditing live system state for JSON profile export (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($targetFile) -ScriptBlock {
        param([string]$OutFile)

        $UltixSync.Progress = 15
        $regCategories = @(
            "Get-RegState_Taskbar", "Get-RegState_Explorer", "Get-RegState_Annoyances",
            "Get-RegState_Privacy", "Get-RegState_SystemBoot", "Get-RegState_Mouse", "Get-RegState_Gaming"
        )

        $activeRegTweaks = [System.Collections.Generic.List[string]]::new()
        foreach ($fn in $regCategories) {
            if (Get-Command $fn -ErrorAction SilentlyContinue) {
                foreach ($item in (& $fn)) {
                    if (-not $item.IsDetected) {
                        $activeRegTweaks.Add($item.UIDisplayName)
                    }
                }
            }
        }

        # Capture exact numerical Win32PrioritySeparation value so custom Quantum Scheduler presets are preserved
        $prioPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        $rawQuantum = (Get-ItemProperty -LiteralPath $prioPath -Name "Win32PrioritySeparation" -ErrorAction SilentlyContinue).Win32PrioritySeparation
        $exactQuantum = if ($null -ne $rawQuantum) { [int]$rawQuantum } else { 2 }

        $UltixSync.Progress = 40

        $customSrpMap = @{}
        $customSrpKey = "HKLM:\SOFTWARE\WinUltix\SRP"
        if (Test-Path -LiteralPath $customSrpKey) {
            $regObj = Get-Item -LiteralPath $customSrpKey -ErrorAction SilentlyContinue
            if ($null -ne $regObj) {
                try {
                    foreach ($p in $regObj.Property) {
                        $customSrpMap[$p] = $regObj.GetValue($p)
                    }
                } finally {
                    $regObj.Dispose()
                }
            }
        }

        $activeSrpLocks = @()
        if (Get-Command Get-RegState_SRP -ErrorAction SilentlyContinue) {
            $activeSrpLocks = @(Get-RegState_SRP | Where-Object { -not $_.IsDetected } | Select-Object -ExpandProperty UIDisplayName)
        }

        $UltixSync.Progress = 60

        # Merge disabled services across both Office (Light) and Gaming (Heavy) profiles
        $svcSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($svcFn in @("Get-ServicesState_Light", "Get-ServicesState_Heavy")) {
            if (Get-Command $svcFn -ErrorAction SilentlyContinue) {
                foreach ($s in (& $svcFn)) {
                    if (-not $s.IsDetected -and $null -ne $s.ActionData.Name) {
                        [void]$svcSet.Add([string]$s.ActionData.Name)
                    }
                }
            }
        }
        $activeServices = @($svcSet)

        $activeTasks = @()
        if (Get-Command Get-TelemetryTasksState -ErrorAction SilentlyContinue) {
            $activeTasks = @(Get-TelemetryTasksState | Where-Object { -not $_.IsDetected } | Select-Object -ExpandProperty UIDisplayName)
        }

        $UltixSync.Progress = 75

        # Capture 7-Point Power & Display state (strip dynamic '(Current...: ...)' suffix for portable matching)
        $activePowerDisplay = [System.Collections.Generic.List[string]]::new()
        if (Get-Command Get-PowerDisplayState -ErrorAction SilentlyContinue) {
            foreach ($pItem in (Get-PowerDisplayState)) {
                if (-not $pItem.IsDetected) {
                    $cleanKey = ($pItem.UIDisplayName -replace '\s*\(Current[^)]*\)\s*$', '').Trim()
                    $activePowerDisplay.Add($cleanKey)
                }
            }
        }

        # Capture 4-Layer USB Security Guard state
        $activeUsbLayers = [System.Collections.Generic.List[string]]::new()
        if (Get-Command Get-UsbSecurityState -ErrorAction SilentlyContinue) {
            foreach ($uItem in (Get-UsbSecurityState)) {
                if (-not $uItem.IsDetected -and $null -ne $uItem.ActionData.Layer) {
                    $activeUsbLayers.Add([string]$uItem.ActionData.Layer)
                }
            }
        }

        $UltixSync.Progress = 90

        $hwSnapshot = if (Get-Command Export-UltixHardwareSnapshot -ErrorAction SilentlyContinue) {
            Export-UltixHardwareSnapshot
        } else {
            @{ AffinityLasso = @(); CPPCUnhidden = @(); TimerTweaks = @(); NVMeTweaks = @(); GlobalNetwork = @() }
        }

        $isStartMenuClean = $false
        if (Get-Command Get-StartMenuState -ErrorAction SilentlyContinue) {
            $smState = @(Get-StartMenuState) | Select-Object -First 1
            if ($null -ne $smState -and -not $smState.IsDetected) { $isStartMenuClean = $true }
        }

        $dnsProfile = $null
        $primaryNic = @(Get-UltixActiveNetworkAdapters) | Select-Object -First 1
        if ($null -ne $primaryNic -and $primaryNic.ProviderName -notin @("Default (DHCP)", "Custom")) {
            $dnsProfile = [ordered]@{
                Provider   = $primaryNic.ProviderName
                EnableDoH  = [bool]$primaryNic.IsDohActive
                EnableIPv6 = ($primaryNic.DnsV6.Count -gt 0)
            }
        }

        $snapshot = [ordered]@{
            SchemaVersion           = "WinUltix_Snapshot_v1"
            AppVersion              = $AppVersion
            ExportTimestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            SourceMachine           = $env:COMPUTERNAME
            Win32PrioritySeparation = $exactQuantum
            StartMenuClean          = $isStartMenuClean
            DnsProfile              = $dnsProfile
            RegistryTweaks          = @($activeRegTweaks)
            PowerDisplayTweaks      = @($activePowerDisplay)
            UsbSecurityLocks        = @($activeUsbLayers)
            CustomSrpRoster         = $customSrpMap
            ActiveSrpLocks          = @($activeSrpLocks)
            DisabledServices        = @($activeServices)
            DisabledTasks           = @($activeTasks)
            AffinityLasso           = @($hwSnapshot.AffinityLasso)
            HardwareLocks           = [ordered]@{
                CPPCUnhidden  = @($hwSnapshot.CPPCUnhidden)
                TimerTweaks   = @($hwSnapshot.TimerTweaks)
                NVMeTweaks    = @($hwSnapshot.NVMeTweaks)
                GlobalNetwork = @($hwSnapshot.GlobalNetwork)
            }
        }

        Invoke-UltixStep -Command "Export-WinUltixProfile -Path '$OutFile'" -Action {
            $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding UTF8 -Force -ErrorAction Stop
        } -SuccessOutput "Snapshot written ($($activeRegTweaks.Count) Reg, $($activePowerDisplay.Count) Pwr, $($activeUsbLayers.Count) USB, $($activeServices.Count) Svc)" -Module "PROFILE"
        $UltixSync.Progress = 100

        $hwCount = @($hwSnapshot.TimerTweaks).Count + @($hwSnapshot.NVMeTweaks).Count + @($hwSnapshot.CPPCUnhidden).Count + @($hwSnapshot.GlobalNetwork).Count
        return [PSCustomObject]@{
            FilePath  = $OutFile
            RegCount  = $activeRegTweaks.Count
            PwrCount  = $activePowerDisplay.Count
            UsbCount  = $activeUsbLayers.Count
            SvcCount  = $activeServices.Count
            AffCount  = @($hwSnapshot.AffinityLasso).Count
            HwCount   = $hwCount
        }
    } -OnComplete ({
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            Write-GUI " -> [OK] Profile exported ($($res.RegCount) Reg, $($res.PwrCount) Power, $($res.UsbCount) USB, $($res.SvcCount) Svc, $($res.AffCount) Affinity, $($res.HwCount) HW Locks): $($res.FilePath)`n"
        }
    }.GetNewClosure())
}

function Import-WinUltixProfile {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "WinUltix Profile (*.json)|*.json"
    $ofd.Title = "Import WinUltix Configuration Snapshot"
    $ofd.InitialDirectory = [Environment]::GetFolderPath("Desktop")

    try {
        if ($ofd.ShowDialog($global:form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $sourceFile = $ofd.FileName
    } finally {
        $ofd.Dispose()
    }

    try {
        $rawJson = Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8 -ErrorAction Stop
        $profileData = $rawJson | ConvertFrom-Json -ErrorAction Stop
        if ($profileData.SchemaVersion -ne "WinUltix_Snapshot_v1") {
            throw "Unsupported or corrupted WinUltix profile schema."
        }
    } catch {
        Write-GUI " -> [!] Profile import failed: $($_.Exception.Message)`n"
        return
    }

    $regCount = @($profileData.RegistryTweaks).Count
    $pwrCount = if ($profileData.PSObject.Properties.Match("PowerDisplayTweaks").Count -gt 0) { @($profileData.PowerDisplayTweaks).Count } else { 0 }
    $usbCount = if ($profileData.PSObject.Properties.Match("UsbSecurityLocks").Count -gt 0)   { @($profileData.UsbSecurityLocks).Count }   else { 0 }
    $svcCount = @($profileData.DisabledServices).Count
    $tskCount = if ($profileData.PSObject.Properties.Match("DisabledTasks").Count -gt 0)      { @($profileData.DisabledTasks).Count }      else { 0 }
    $srpCount = @($profileData.ActiveSrpLocks).Count
    $affCount = @($profileData.AffinityLasso).Count

    $hwCount = 0
    if ($profileData.PSObject.Properties.Match("HardwareLocks").Count -gt 0 -and $null -ne $profileData.HardwareLocks) {
        $hl = $profileData.HardwareLocks
        $hwCount = @($hl.CPPCUnhidden).Count + @($hl.TimerTweaks).Count + @($hl.NVMeTweaks).Count + @($hl.GlobalNetwork).Count
    }

    $smLabel = if ($profileData.PSObject.Properties.Match("StartMenuClean").Count -gt 0 -and $profileData.StartMenuClean -eq $true) {
        "3-Icon Clean Layout"
    } else {
        "Unchanged"
    }

    $dnsLabel = if ($profileData.PSObject.Properties.Match("DnsProfile").Count -gt 0 -and $null -ne $profileData.DnsProfile -and -not [string]::IsNullOrWhiteSpace($profileData.DnsProfile.Provider)) {
        $dohTag = if ($profileData.DnsProfile.EnableDoH) { " [DoH]" } else { "" }
        "$($profileData.DnsProfile.Provider)$dohTag"
    } else {
        "Unchanged"
    }

    $confirmMsg = "Loaded snapshot from '$($profileData.SourceMachine)' ($($profileData.ExportTimestamp)):`n`n" +
                  " - Registry Tweaks: $regCount`n" +
                  " - Power & Display Optimizations: $pwrCount`n" +
                  " - USB Perimeter Locks: $usbCount`n" +
                  " - Disabled Services / Tasks: $svcCount / $tskCount`n" +
                  " - SRP+IFEO Locks: $srpCount`n" +
                  " - Affinity Lasso / Hardware Locks: $affCount / $hwCount`n" +
                  " - Start Menu Layout: $smLabel`n" +
                  " - DNS Profile: $dnsLabel`n`n" +
                  "Do you want to enforce this profile on the current machine?"

    $ans = [System.Windows.Forms.MessageBox]::Show($confirmMsg, "WinUltix - Import Profile", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-GUI " -> Profile import cancelled.`n"
        return
    }

    Write-GUI "=== IMPORTING PROFILE FROM $($profileData.SourceMachine) (Background Thread) ==="
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($profileData) -ScriptBlock {
        param($Snapshot)

        $modifiedRegItems = @()
        $UltixSync.Progress = 10

        # 1. Custom SRP Roster
        if ($null -ne $Snapshot.CustomSrpRoster) {
            $customSrpKey = "HKLM:\SOFTWARE\WinUltix\SRP"
            foreach ($prop in $Snapshot.CustomSrpRoster.PSObject.Properties) {
                Set-UltixRegValue -Path $customSrpKey -Name $prop.Name -Value $prop.Value -Type String -Module "PROFILE"
            }
        }

        # 2. Registry Tweaks + Exact Win32PrioritySeparation Preservation
        if (@($Snapshot.RegistryTweaks).Count -gt 0) {
            $targetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($t in $Snapshot.RegistryTweaks) { [void]$targetSet.Add([string]$t) }

            $allRegStates = [System.Collections.Generic.List[object]]::new()
            foreach ($fn in @("Get-RegState_Taskbar", "Get-RegState_Explorer", "Get-RegState_Annoyances", "Get-RegState_Privacy", "Get-RegState_SystemBoot", "Get-RegState_Mouse", "Get-RegState_Gaming")) {
                if (Get-Command $fn -ErrorAction SilentlyContinue) {
                    foreach ($st in (& $fn)) { $allRegStates.Add($st) }
                }
            }

            $toApplyReg = @($allRegStates | Where-Object {
                $targetSet.Contains($_.UIDisplayName) -and $_.IsDetected -and $_.ActionData.Name -ne "Win32PrioritySeparation"
            })

            if ($toApplyReg.Count -gt 0) {
                Invoke-ApplyRegistry -SelectedItems $toApplyReg -CategoryName "Imported Profile" -Operation "Apply"
                $modifiedRegItems = $toApplyReg
            }
        }

        if ($Snapshot.PSObject.Properties.Match("Win32PrioritySeparation").Count -gt 0 -and $null -ne $Snapshot.Win32PrioritySeparation) {
            $savedQuantum = [int]$Snapshot.Win32PrioritySeparation
            $prioKey = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
            Set-UltixRegValue -Path $prioKey -Name "Win32PrioritySeparation" -Value $savedQuantum -Type DWord -Module "PROFILE"
            $UltixSync.Logs.Enqueue((" -> Restored Quantum Scheduler (Win32PrioritySeparation = 0x{0:X2} / {0} dec)." -f $savedQuantum))
        }

        $UltixSync.Progress = 35

        # 3. 7-Point Power & Display Tweaks
        if ($Snapshot.PSObject.Properties.Match("PowerDisplayTweaks").Count -gt 0 -and @($Snapshot.PowerDisplayTweaks).Count -gt 0 -and (Get-Command Get-PowerDisplayState -ErrorAction SilentlyContinue)) {
            $pwrSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($p in $Snapshot.PowerDisplayTweaks) {
                [void]$pwrSet.Add((([string]$p) -replace '\s*\(Current[^)]*\)\s*$', '').Trim())
            }
            $toApplyPwr = @(Get-PowerDisplayState | Where-Object {
                $cleanName = ($_.UIDisplayName -replace '\s*\(Current[^)]*\)\s*$', '').Trim()
                $pwrSet.Contains($cleanName) -and $_.IsDetected
            })
            if ($toApplyPwr.Count -gt 0) {
                Invoke-ApplyPowerDisplay -SelectedItems $toApplyPwr -Operation "Apply"
            }
        }

        $UltixSync.Progress = 50

        # 4. 4-Layer USB Security Guard
        if ($Snapshot.PSObject.Properties.Match("UsbSecurityLocks").Count -gt 0 -and @($Snapshot.UsbSecurityLocks).Count -gt 0 -and (Get-Command Get-UsbSecurityState -ErrorAction SilentlyContinue)) {
            $usbSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($u in $Snapshot.UsbSecurityLocks) { [void]$usbSet.Add([string]$u) }
            $toApplyUsb = @(Get-UsbSecurityState | Where-Object {
                ($usbSet.Contains($_.ActionData.Layer) -or $usbSet.Contains($_.UIDisplayName)) -and $_.IsDetected
            })
            if ($toApplyUsb.Count -gt 0) {
                Invoke-ApplyUsbSecurity -SelectedItems $toApplyUsb -Operation "Apply"
            }
        }

        $UltixSync.Progress = 65

        # 5. SRP + IFEO Locks
        if (@($Snapshot.ActiveSrpLocks).Count -gt 0 -and (Get-Command Get-RegState_SRP -ErrorAction SilentlyContinue)) {
            $srpSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($s in $Snapshot.ActiveSrpLocks) { [void]$srpSet.Add([string]$s) }
            $toApplySrp = @(Get-RegState_SRP | Where-Object { $srpSet.Contains($_.UIDisplayName) -and $_.IsDetected })
            if ($toApplySrp.Count -gt 0) {
                Invoke-ApplySRP -SelectedItems $toApplySrp -Operation "Apply"
            }
        }

        $UltixSync.Progress = 80

        # 6. Services (Merged Light + Heavy catalog)
        if (@($Snapshot.DisabledServices).Count -gt 0) {
            $svcTargetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($sv in $Snapshot.DisabledServices) { [void]$svcTargetSet.Add([string]$sv) }

            $mergedSvcCatalog = [System.Collections.Generic.List[object]]::new()
            $seenSvcNames     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($svcFn in @("Get-ServicesState_Light", "Get-ServicesState_Heavy")) {
                if (Get-Command $svcFn -ErrorAction SilentlyContinue) {
                    foreach ($sObj in (& $svcFn)) {
                        if ($seenSvcNames.Add([string]$sObj.ActionData.Name)) {
                            $mergedSvcCatalog.Add($sObj)
                        }
                    }
                }
            }

            $toApplySvc = @($mergedSvcCatalog | Where-Object { $svcTargetSet.Contains($_.ActionData.Name) -and $_.IsDetected })
            if ($toApplySvc.Count -gt 0) {
                Invoke-ApplyServices -SelectedItems $toApplySvc -ProfileName "Imported Profile" -Operation "Apply"
            }
        }

        # 7. Telemetry Scheduled Tasks
        if (@($Snapshot.DisabledTasks).Count -gt 0 -and (Get-Command Get-TelemetryTasksState -ErrorAction SilentlyContinue)) {
            $taskSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($tk in $Snapshot.DisabledTasks) { [void]$taskSet.Add([string]$tk) }
            $toApplyTasks = @(Get-TelemetryTasksState | Where-Object { $taskSet.Contains($_.UIDisplayName) -and $_.IsDetected })
            if ($toApplyTasks.Count -gt 0) {
                Invoke-ApplyTasks -SelectedItems $toApplyTasks -Operation "Apply"
            }
        }

        $UltixSync.Progress = 90

        # 8. Start Menu 3-Icon Layout & Active DNS/DoH Profile
        if ($Snapshot.PSObject.Properties.Match("StartMenuClean").Count -gt 0 -and $Snapshot.StartMenuClean -eq $true -and (Get-Command Clear-StartMenu -ErrorAction SilentlyContinue)) {
            $smCur = @(Get-StartMenuState) | Select-Object -First 1
            if ($null -ne $smCur -and $smCur.IsDetected) {
                Clear-StartMenu -Operation "Apply"
            }
        }

        if ($Snapshot.PSObject.Properties.Match("DnsProfile").Count -gt 0 -and $null -ne $Snapshot.DnsProfile -and -not [string]::IsNullOrWhiteSpace($Snapshot.DnsProfile.Provider) -and (Get-Command Set-CustomDNS -ErrorAction SilentlyContinue)) {
            Set-CustomDNS -Provider ([string]$Snapshot.DnsProfile.Provider) -EnableDoH ([bool]$Snapshot.DnsProfile.EnableDoH) -EnableIPv6 ([bool]$Snapshot.DnsProfile.EnableIPv6)
        }

        # 9. Hardware & Affinity Snapshot
        if (Get-Command Import-UltixHardwareSnapshot -ErrorAction SilentlyContinue) {
            Import-UltixHardwareSnapshot -ProfileData $Snapshot
        } elseif (@($Snapshot.AffinityLasso).Count -gt 0) {
            $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
            foreach ($exe in $Snapshot.AffinityLasso) {
                Set-UltixRegValue -Path $affPath -Name $exe -Value 1 -Type DWord -Module "PROFILE"
            }
            $UltixSync.Logs.Enqueue(" -> Restored $(@($Snapshot.AffinityLasso).Count) process(es) to Affinity Lasso roster.")
        }

        $UltixSync.Progress = 100
        return ,$modifiedRegItems
    } -OnComplete ({
        param($modReg)
        Update-Progress 0
        Update-DNSLabel
        Write-GUI "=== PROFILE IMPORT COMPLETED ===`n"
    }.GetNewClosure())
}