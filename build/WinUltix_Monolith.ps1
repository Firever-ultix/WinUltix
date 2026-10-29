# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# MODULAR MAIN LAUNCHER
# ==========================================
$Global:AppVersion = "v3.0.0"

# ------------------------------------------
# 1. MODULE LOADING (ARCHITECTURE MANIFESTS)
# ------------------------------------------
# $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
# $ModulesDir = Join-Path $ScriptDir "Modules"

# Core_Helpers: Global UI functions, registry engine, and shared modal interfaces.
# >>> INJECTED: Core_Helpers.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# CORE_HELPERS.PS1 - UNIFIED CORE ENGINE (v3.0.0)
# Core_Helpers: Unified C# P/Invoke runtime (DWM, DPI, Shell, Token Privileges, COM AppActivator, CPU Topology, NtDll Timer, ListView Sorter), O(1) UI logger, InitialSessionState async Runspace engine ($UltixSync), UI control factories, shared modals, and JSON profile snapshotter.
# ==========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------
# 1. UNIFIED WIN32 / NTDLL / KERNEL32 P/INVOKE RUNTIME
# ------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'WinUltix.NativeMethods').Type) {
    Add-Type -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing") -TypeDefinition @"
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Runtime.CompilerServices;
    using System.Runtime.InteropServices;
    using System.Windows.Forms;

    namespace WinUltix {
        // DWM Dark Title Bar & High-DPI GDI Scaling
        public static class NativeMethods {
            [DllImport("dwmapi.dll", PreserveSig = true)]
            private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

            public static void EnableDarkTitleBar(IntPtr handle) {
                if (handle == IntPtr.Zero) return;
                int useDark = 1;
                if (DwmSetWindowAttribute(handle, 20, ref useDark, sizeof(int)) != 0) {
                    DwmSetWindowAttribute(handle, 19, ref useDark, sizeof(int));
                }
            }

            public static void EnableGdiDpiScaling() {
                try {
                    SetProcessDpiAwarenessContext(new IntPtr(-5));
                } catch { }
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

        // Token Privilege Escalation for TrustedInstaller-Protected Keys
        public static class PrivilegeEnabler {
            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            private static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            private static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);

            [DllImport("advapi32.dll", SetLastError = true)]
            private static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

            [StructLayout(LayoutKind.Sequential, Pack = 1)]
            private struct TokPriv1Luid {
                public int Count;
                public long Luid;
                public int Attr;
            }

            public static void EnablePrivilege(string privilege) {
                IntPtr htok = IntPtr.Zero;
                if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, 0x00000028, ref htok)) return;
                TokPriv1Luid tp = new TokPriv1Luid { Count = 1, Luid = 0, Attr = 0x00000002 };
                if (LookupPrivilegeValue(null, privilege, ref tp.Luid)) {
                    AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
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

        // Fast Case-Insensitive Column Sorter for WinForms ListViews
        public class ListViewColumnSorter : IComparer {
            public int ColumnToSort = 0;
            public SortOrder OrderOfSort = SortOrder.None;
            private CaseInsensitiveComparer ObjectCompare = new CaseInsensitiveComparer();

            public int Compare(object x, object y) {
                ListViewItem listviewX = (ListViewItem)x;
                ListViewItem listviewY = (ListViewItem)y;

                string textX = (ColumnToSort < listviewX.SubItems.Count) ? listviewX.SubItems[ColumnToSort].Text : "";
                string textY = (ColumnToSort < listviewY.SubItems.Count) ? listviewY.SubItems[ColumnToSort].Text : "";

                int compareResult = ObjectCompare.Compare(textX, textY);
                if (OrderOfSort == SortOrder.Ascending) return compareResult;
                if (OrderOfSort == SortOrder.Descending) return -compareResult;
                return 0;
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
                // 7 tabs * 57px = 399px (fits cleanly inside the 410px TabControl without scroll arrows)
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
                        ? Color.FromArgb(45, 45, 45)
                        : (isHovered ? Color.FromArgb(38, 38, 38) : Color.FromArgb(22, 22, 22));

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

                    // Uses native this.Font (no Bold override) to match button sharpness 1:1
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

        // Custom GDI+ Flat Dark ProgressBar with Centered Percentage Readout
        public class DarkProgressBar : ProgressBar {
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

                using (Font f = new Font("Consolas", 9.0f, FontStyle.Bold)) {
                    TextRenderer.DrawText(
                        g,
                        statusText,
                        f,
                        rect,
                        textColor,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                }
            }
        }
    }
"@ -ErrorAction SilentlyContinue
}

function Enable-WinUltixDarkTitleBar {
    param([Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Form)
    try {
        [WinUltix.NativeMethods]::EnableDarkTitleBar($Form.Handle)
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

    $cimProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction SilentlyContinue)
    foreach ($prof in $cimProfiles) {
        if ([string]::IsNullOrWhiteSpace($prof.LocalPath)) { continue }
        $userName = [System.IO.Path]::GetFileName($prof.LocalPath)
        if ($userName -match '^(Public|Default.*|All Users)$') { continue }

        $sid = [string]$prof.SID
        $hiveRoot = if (-not [string]::IsNullOrWhiteSpace($sid)) { "Registry::HKEY_USERS\$sid" } else { "" }
        $isLoaded = (-not [string]::IsNullOrWhiteSpace($hiveRoot)) -and (Test-Path -Path $hiveRoot)

        if ([string]::IsNullOrWhiteSpace($sid) -or $seenSids.Add($sid)) {
            $results.Add([PSCustomObject]@{
                SID          = $sid
                UserName     = $userName
                LocalPath    = $prof.LocalPath
                HiveRoot     = $hiveRoot
                IsHiveLoaded = $isLoaded
            })
        }
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

function Set-ProtectedServiceStart {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceName,
        [Parameter(Mandatory=$true)][int]$StartValue
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    try {
        Set-ItemProperty -Path $regPath -Name "Start" -Value $StartValue -Type DWord -Force -ErrorAction Stop
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeTakeOwnershipPrivilege")
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeRestorePrivilege")

        $subKeyPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

        $keyOwn = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        if ($null -ne $keyOwn) {
            $aclOwn = $keyOwn.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
            $aclOwn.SetOwner($adminSid)
            $keyOwn.SetAccessControl($aclOwn)
            $keyOwn.Close()
        }

        $keyAcl = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        if ($null -ne $keyAcl) {
            $acl = $keyAcl.GetAccessControl()
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $adminSid,
                [System.Security.AccessControl.RegistryRights]::FullControl,
                [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.SetAccessRule($rule)
            $keyAcl.SetAccessControl($acl)
            $keyAcl.Close()
        }

        Set-ItemProperty -Path $regPath -Name "Start" -Value $StartValue -Type DWord -Force -ErrorAction Stop
    }
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
        [switch]$ForceExplorerRestart
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
        Stop-Process -Name "SearchHost" -Force -ErrorAction SilentlyContinue
        Write-GUI " -> Refreshed Windows Search UI host (SearchHost.exe)."
    }

    if ($needsExplorerRestart) {
        Write-GUI " -> Policy change requires shell reload. Restarting explorer.exe..."
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
            Start-Process "explorer.exe"
        }
    } else {
        Write-GUI " -> Shell & Taskbar refreshed live via Win32 WM_SETTINGCHANGE / SHChangeNotify."
    }
}

# ------------------------------------------
# 3. GLOBAL UI HELPERS & CONTROL FACTORIES
# ------------------------------------------
function Write-GUI { 
    param([AllowEmptyString()][string]$Message)
    if ($null -ne $global:infoBox -and -not $global:infoBox.IsDisposed) {
        if ($global:infoBox -is [System.Windows.Forms.RichTextBox]) {
            if ($Message -eq "") {
                $global:infoBox.AppendText("`r`n")
                $global:infoBox.ScrollToCaret()
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

            $global:infoBox.ScrollToCaret()
            $global:infoBox.Update()
        } else {
            $line = if ($Message -eq "") { "`r`n" } else { "`r`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }
            $global:infoBox.AppendText($line)
            $global:infoBox.Update()
        }
    } else {
        Write-Host $Message -ForegroundColor Cyan
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

function Update-DNSLabel {
    if ($null -eq $global:lblCurrentDNS -or $global:lblCurrentDNS.IsDisposed) { return }

    try {
        # Direct Win32 GetAdaptersAddresses via .NET NetworkInterface (~2ms, zero CIM/CDXML overhead)
        $activeNic = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
            $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
            $_.GetIPProperties().GatewayAddresses.Count -gt 0
        } | Select-Object -First 1

        if ($null -eq $activeNic) {
            $global:lblCurrentDNS.Text = "Current DNS: No active internet route"
            $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::DarkGray
            return
        }

        $ipProps = $activeNic.GetIPProperties()
        $v4Addrs = [System.Collections.Generic.List[string]]::new()
        $v6Addrs = [System.Collections.Generic.List[string]]::new()

        foreach ($dnsIp in $ipProps.DnsAddresses) {
            if ($dnsIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                $v4Addrs.Add($dnsIp.ToString())
            } elseif ($dnsIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and -not $dnsIp.IsIPv6SiteLocal) {
                $v6Addrs.Add($dnsIp.ToString())
            }
        }

        $ifGuid = $activeNic.Id
        $v4RegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$ifGuid"
        $staticNameServer = (Get-ItemProperty -LiteralPath $v4RegKey -Name "NameServer" -ErrorAction SilentlyContinue).NameServer

        if ([string]::IsNullOrWhiteSpace($staticNameServer) -and $v4Addrs.Count -gt 0) {
            $global:lblCurrentDNS.Text = "Current DNS: Default provider (DHCP - $($v4Addrs[0]))"
            $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue
            return
        }

        if ($v4Addrs.Count -eq 0 -and $v6Addrs.Count -eq 0) {
            $global:lblCurrentDNS.Text = "Current DNS: Default provider (DHCP)"
            $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue
            return
        }

        $primaryV4 = if ($v4Addrs.Count -gt 0) { $v4Addrs[0] } else { "" }
        $providerName = switch ($primaryV4) {
            "9.9.9.9"        { "Quad9" }
            "1.1.1.1"        { "Cloudflare" }
            "94.140.14.14"   { "AdGuard" }
            "8.8.8.8"        { "Google" }
            "208.67.222.222" { "OpenDNS" }
            default          { "Custom" }
        }

        $isDohActive = $false
        if (-not [string]::IsNullOrWhiteSpace($ifGuid) -and -not [string]::IsNullOrWhiteSpace($primaryV4)) {
            $dohKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$ifGuid\DohInterfaceSettings\Doh\$primaryV4"
            $flags  = (Get-ItemProperty -LiteralPath $dohKey -Name "DohFlags" -ErrorAction SilentlyContinue).DohFlags
            if ($null -ne $flags -and ($flags -band 1) -eq 1) { $isDohActive = $true }
        }

        $stackBadge = if ($v6Addrs.Count -gt 0) { "IPv4+v6" } else { "IPv4" }
        $dohBadge   = if ($isDohActive) { " [DoH Encrypted]" } else { " [Plaintext]" }

        $global:lblCurrentDNS.Text = "Current DNS: $providerName ($primaryV4 | $stackBadge)$dohBadge"
        $global:lblCurrentDNS.ForeColor = if ($isDohActive) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::LightSkyBlue }
    } catch {
        $global:lblCurrentDNS.Text = "Current DNS: Unknown"
    }
}

function Set-RegKey { 
    param($Path, $Name, $Value, $Type="DWord")
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null }
    if ($null -eq $Value -and $Type -eq "String") { 
        Set-ItemProperty -Path $Path -Name $Name -Value "" -Type String -Force -ErrorAction SilentlyContinue | Out-Null 
    } else { 
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue | Out-Null 
    } 
}

function New-UltixButton {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$X,
        [Parameter(Mandatory=$true)][int]$Y,
        [int]$Width = 370,
        [int]$Height = 40,
        [int[]]$RGB = @(60, 60, 60),
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White,
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
        [int[]]$MainRGB = @(60, 60, 60),
        [int[]]$AuditRGB = @(80, 80, 80),
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
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [int]$PollIntervalMs = 150
    )

    foreach ($ctrl in $ControlsToDisable) {
        if ($null -ne $ctrl -and -not $ctrl.IsDisposed) { $ctrl.Enabled = $false }
    }

    $syncContext = [hashtable]::Synchronized(@{
        Logs     = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        Progress = -1
    })

    # Pre-hydrate shared core functions into isolated Runspace InitialSessionState
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($fnName in @("Get-UltixUserProfiles", "Get-UltixFastSize", "Set-ProtectedServiceStart", "Get-UltixPowerAcIndex")) {
        $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $fnName, $cmd.Definition))
        }
    }

    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("UltixSync", $syncContext)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($ScriptBlock)
    foreach ($arg in $Arguments) {
        [void]$ps.AddArgument($arg)
    }

    $asyncResult = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $PollIntervalMs
    $timer.Tag = @{
        PS           = $ps
        Runspace     = $runspace
        AsyncResult  = $asyncResult
        Controls     = $ControlsToDisable
        OnComplete   = $OnComplete
        SyncContext  = $syncContext
        LastProgress = -1
    }

    $timer.Add_Tick({
        $state = $this.Tag
        $sync  = $state.SyncContext

        $logLine = $null
        while ($sync.Logs.TryDequeue([ref]$logLine)) {
            Write-GUI $logLine
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
            while ($sync.Logs.TryDequeue([ref]$logLine)) {
                Write-GUI $logLine
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
            Write-GUI "  [ERROR] Background task failed: $($taskError.Exception.Message)"
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
                foreach ($d in $detected) { Write-GUI "  [!] ${AuditPrefix}: $($d.UIDisplayName)" }
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
    $modal.Size = New-Object System.Drawing.Size(760, 680)
    $modal.MinimumSize = New-Object System.Drawing.Size(760, 680)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "Sizable"
    $modal.MaximizeBox = $true
    $modal.MinimizeBox = $false
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = $Description
    $lblDesc.Location = New-Object System.Drawing.Point(15, 12)
    $lblDesc.Size = New-Object System.Drawing.Size(710, 38)
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblDesc.Anchor = 'Top, Left, Right'

    $hasValidItems = ($null -ne $AuditResults -and $AuditResults.Count -gt 0)

    $btnSelAll = New-Object System.Windows.Forms.Button
    $btnSelAll.Text = "Select All"
    $btnSelAll.Location = New-Object System.Drawing.Point(15, 54)
    $btnSelAll.Size = New-Object System.Drawing.Size(105, 26)
    $btnSelAll.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 50, 50)
    $btnSelAll.FlatStyle = "Flat"
    $btnSelAll.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $btnSelAll.Enabled = $hasValidItems

    $btnSelNone = New-Object System.Windows.Forms.Button
    $btnSelNone.Text = "Deselect All"
    $btnSelNone.Location = New-Object System.Drawing.Point(128, 54)
    $btnSelNone.Size = New-Object System.Drawing.Size(105, 26)
    $btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 50, 50)
    $btnSelNone.FlatStyle = "Flat"
    $btnSelNone.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $btnSelNone.Enabled = $hasValidItems

    $btnSelDet = New-Object System.Windows.Forms.Button
    $btnSelDet.Text = "Select Detected"
    $btnSelDet.Location = New-Object System.Drawing.Point(241, 54)
    $btnSelDet.Size = New-Object System.Drawing.Size(120, 26)
    $btnSelDet.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 75, 100)
    $btnSelDet.FlatStyle = "Flat"
    $btnSelDet.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $btnSelDet.Enabled = $hasValidItems

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(525, 57)
    $lblCount.Size = New-Object System.Drawing.Size(200, 20)
    $lblCount.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblCount.ForeColor = [System.Drawing.Color]::LightGray
    $lblCount.TextAlign = "MiddleRight"
    $lblCount.Anchor = 'Top, Right'
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox
    $chkList.Location = New-Object System.Drawing.Point(15, 88)
    $chkList.Size = New-Object System.Drawing.Size(710, 480)
    $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $chkList.Font = New-Object System.Drawing.Font("Consolas", 10)
    $chkList.CheckOnClick = $false
    $chkList.HorizontalScrollbar = $true
    $chkList.Anchor = 'Top, Bottom, Left, Right' 

    if ($hasValidItems) {
        $chkList.BeginUpdate()
        foreach ($item in $AuditResults) {
            if ($item.IsDetected) { 
                [void]$chkList.Items.Add("[ DETECTED ]  " + $item.UIDisplayName, $true) 
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

    $updateCounter = {
        param([int]$Delta = 0)
        $totalChecked = $chkList.CheckedIndices.Count + $Delta
        $lblCount.Text = "Selected: $totalChecked / $($chkList.Items.Count)"
    }

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
            $chkList.SetItemChecked($i, [bool]$AuditResults[$i].IsDetected)
        }
        $chkList.EndUpdate()
        & $updateCounter 0
    }.GetNewClosure())

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Execute Selected"
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnApply.FlatStyle = "Flat"
    $btnApply.DialogResult = "OK"
    $btnApply.Enabled = $hasValidItems
    $btnApply.Anchor = 'Bottom, Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.DialogResult = "Cancel"
    $btnCancel.Anchor = 'Bottom, Right'

    $baseControls = @($lblDesc, $btnSelAll, $btnSelNone, $btnSelDet, $lblCount, $chkList)

    if ($EnableRevert) {
        $btnApply.Location = New-Object System.Drawing.Point(15, 585)
        $btnApply.Size = New-Object System.Drawing.Size(230, 35)

        $btnRevert = New-Object System.Windows.Forms.Button
        $btnRevert.Text = "Revert Selected"
        $btnRevert.Location = New-Object System.Drawing.Point(255, 585)
        $btnRevert.Size = New-Object System.Drawing.Size(230, 35)
        $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
        $btnRevert.FlatStyle = "Flat"
        $btnRevert.DialogResult = "Yes"
        $btnRevert.Enabled = $hasValidItems
        $btnRevert.Anchor = 'Bottom, Left'
        
        $btnCancel.Location = New-Object System.Drawing.Point(495, 585)
        $btnCancel.Size = New-Object System.Drawing.Size(230, 35)

        $modal.Controls.AddRange($baseControls + @($btnApply, $btnRevert, $btnCancel))
    } else {
        $btnApply.Location = New-Object System.Drawing.Point(15, 585)
        $btnApply.Size = New-Object System.Drawing.Size(345, 35)
        $btnCancel.Location = New-Object System.Drawing.Point(380, 585)
        $btnCancel.Size = New-Object System.Drawing.Size(345, 35)
        $modal.Controls.AddRange($baseControls + @($btnApply, $btnCancel))
    }

    $modal.AcceptButton = $btnApply
    $modal.CancelButton = $btnCancel

    try {
        $result = $modal.ShowDialog($global:form)
        if ($hasValidItems -and ($result -eq "OK" -or $result -eq "Yes")) {
            $selectedItems = [System.Collections.Generic.List[object]]::new()
            foreach ($idx in $chkList.CheckedIndices) {
                $selectedItems.Add($AuditResults[$idx])
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
        [string]$SecondaryButtonText = ""
    )

    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title
    $modal.Size = New-Object System.Drawing.Size(920, 680)
    $modal.MinimumSize = New-Object System.Drawing.Size(780, 560)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "Sizable"
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = $Description
    $lblDesc.Location = New-Object System.Drawing.Point(15, 12)
    $lblDesc.Size = New-Object System.Drawing.Size(870, 32)
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblDesc.Anchor = 'Top, Left, Right'

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Filter:"
    $lblSearch.Location = New-Object System.Drawing.Point(15, 52)
    $lblSearch.Size = New-Object System.Drawing.Size(45, 22)
    $lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblSearch.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(62, 50)
    $txtSearch.Size = New-Object System.Drawing.Size(260, 25)
    $txtSearch.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $txtSearch.ForeColor = [System.Drawing.Color]::White
    $txtSearch.BorderStyle = "FixedSingle"
    $txtSearch.Font = New-Object System.Drawing.Font("Consolas", 10)

    $btnSelVis = New-Object System.Windows.Forms.Button
    $btnSelVis.Text = "Select Visible"
    $btnSelVis.Location = New-Object System.Drawing.Point(332, 49)
    $btnSelVis.Size = New-Object System.Drawing.Size(110, 26)
    $btnSelVis.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 50, 50)
    $btnSelVis.FlatStyle = "Flat"
    $btnSelVis.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

    $btnSelNone = New-Object System.Windows.Forms.Button
    $btnSelNone.Text = "Deselect All"
    $btnSelNone.Location = New-Object System.Drawing.Point(450, 49)
    $btnSelNone.Size = New-Object System.Drawing.Size(110, 26)
    $btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 50, 50)
    $btnSelNone.FlatStyle = "Flat"
    $btnSelNone.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(570, 52)
    $lblCount.Size = New-Object System.Drawing.Size(315, 20)
    $lblCount.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblCount.ForeColor = [System.Drawing.Color]::LightGray
    $lblCount.TextAlign = "MiddleRight"
    $lblCount.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 85)
    $listView.Size = New-Object System.Drawing.Size(875, 485)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 42, 42, 42)
    $listView.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $listView.Font = New-Object System.Drawing.Font("Consolas", 10)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.Anchor = 'Top, Bottom, Left, Right'

    Enable-UltixDoubleBuffer -Control $listView

    $sorter = New-Object WinUltix.ListViewColumnSorter
    $listView.ListViewItemSorter = $sorter

    foreach ($col in $Columns) {
        [void]$listView.Columns.Add($col.Header, $col.Width)
    }

    $indexedData = [System.Collections.Generic.List[PSCustomObject]]::new()
    for ($i = 0; $i -lt $Data.Count; $i++) {
        $indexedData.Add([PSCustomObject]@{
            RowId = $i
            Item  = $Data[$i]
        })
    }
    $checkedIds = [System.Collections.Generic.HashSet[int]]::new()
    $syncGuard  = @{ SuppressEvents = $false }

    $updateCounter = {
        $lblCount.Text = "Selected: $($checkedIds.Count) / $($indexedData.Count) (Showing: $($listView.Items.Count))"
    }

    $populateList = {
        param([string]$FilterText = "")
        $syncGuard.SuppressEvents = $true
        $listView.BeginUpdate()
        $listView.ListViewItemSorter = $null
        $listView.Items.Clear()

        $cleanFilter = $FilterText.Trim()
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
            $firstVal = [string]$obj.($Columns[0].Property)
            $lvItem = New-Object System.Windows.Forms.ListViewItem($firstVal)
            for ($c = 1; $c -lt $Columns.Count; $c++) {
                $subVal = [string]$obj.($Columns[$c].Property)
                [void]$lvItem.SubItems.Add($subVal)
            }
            $lvItem.Tag = $entry.RowId
            $lvItem.Checked = (-not $isLockedRow) -and $checkedIds.Contains($entry.RowId)

            if ($isLockedRow) {
                $lvItem.ForeColor = [System.Drawing.Color]::IndianRed
            } elseif ($obj.PSObject.Properties.Match("State").Count -gt 0 -and $obj.State -match "^Disabled") {
                $lvItem.ForeColor = [System.Drawing.Color]::DarkGray
            } elseif ($obj.PSObject.Properties.Match("Status").Count -gt 0 -and [string]$obj.Status -eq "Stopped") {
                $lvItem.ForeColor = [System.Drawing.Color]::Silver
            }

            [void]$listView.Items.Add($lvItem)
        }

        $listView.ListViewItemSorter = $sorter
        $listView.EndUpdate()
        $syncGuard.SuppressEvents = $false
        & $updateCounter
    }

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
    $btnPrimary.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnPrimary.ForeColor = [System.Drawing.Color]::White
    $btnPrimary.FlatStyle = "Flat"
    $btnPrimary.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnPrimary.Enabled = ($indexedData.Count -gt 0)
    $btnPrimary.Anchor = 'Bottom, Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Anchor = 'Bottom, Right'

    $controlsToAdd = @($lblDesc, $lblSearch, $txtSearch, $btnSelVis, $btnSelNone, $lblCount, $listView, $btnPrimary, $btnCancel)

    if (-not [string]::IsNullOrWhiteSpace($SecondaryButtonText)) {
        $btnPrimary.Location = New-Object System.Drawing.Point(15, 585)
        $btnPrimary.Size = New-Object System.Drawing.Size(270, 38)

        $btnSecondary = New-Object System.Windows.Forms.Button
        $btnSecondary.Text = $SecondaryButtonText
        $btnSecondary.Location = New-Object System.Drawing.Point(295, 585)
        $btnSecondary.Size = New-Object System.Drawing.Size(270, 38)
        $btnSecondary.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
        $btnSecondary.ForeColor = [System.Drawing.Color]::White
        $btnSecondary.FlatStyle = "Flat"
        $btnSecondary.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $btnSecondary.Enabled = ($indexedData.Count -gt 0)
        $btnSecondary.Anchor = 'Bottom, Left'

        $btnCancel.Location = New-Object System.Drawing.Point(575, 585)
        $btnCancel.Size = New-Object System.Drawing.Size(315, 38)
        $controlsToAdd += $btnSecondary
    } else {
        $btnPrimary.Location = New-Object System.Drawing.Point(15, 585)
        $btnPrimary.Size = New-Object System.Drawing.Size(425, 38)

        $btnCancel.Location = New-Object System.Drawing.Point(465, 585)
        $btnCancel.Size = New-Object System.Drawing.Size(425, 38)
    }

    $modal.Controls.AddRange($controlsToAdd)
    $modal.CancelButton = $btnCancel

    try {
        $dlgRes = $modal.ShowDialog($global:form)
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

Set-Alias -Name Show-Z5GridModal -Value Show-UltixGridModal -Scope Global -ErrorAction SilentlyContinue

# ------------------------------------------
# 6. JSON PROFILE SNAPSHOT ENGINE (EXPORT / IMPORT)
# ------------------------------------------
function Export-WinUltixProfile {
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "WinUltix Profile (*.json)|*.json"
    $sfd.Title = "Export WinUltix Configuration Snapshot"
    $sfd.FileName = "WinUltix_Profile_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd').json"
    $sfd.InitialDirectory = [Environment]::GetFolderPath("Desktop")

    if ($sfd.ShowDialog($global:form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $targetFile = $sfd.FileName
    $sfd.Dispose()

    Write-GUI " -> Auditing live system state for JSON profile export..."
    Update-Progress 20

    $regCategories = @(
        @{ Name = "Taskbar";    Fn = "Get-RegState_Taskbar" }
        @{ Name = "Explorer";   Fn = "Get-RegState_Explorer" }
        @{ Name = "Annoyances"; Fn = "Get-RegState_Annoyances" }
        @{ Name = "Privacy";    Fn = "Get-RegState_Privacy" }
        @{ Name = "SystemBoot"; Fn = "Get-RegState_SystemBoot" }
        @{ Name = "Mouse";      Fn = "Get-RegState_Mouse" }
        @{ Name = "Gaming";     Fn = "Get-RegState_Gaming" }
    )

    $activeRegTweaks = [System.Collections.Generic.List[string]]::new()
    foreach ($cat in $regCategories) {
        if (Get-Command $cat.Fn -ErrorAction SilentlyContinue) {
            $state = & $cat.Fn
            foreach ($item in $state) {
                if (-not $item.IsDetected) {
                    $activeRegTweaks.Add($item.UIDisplayName)
                }
            }
        }
    }

    Update-Progress 50

    $customSrpMap = @{}
    $customSrpKey = "HKLM:\SOFTWARE\WinUltix\SRP"
    if (Test-Path $customSrpKey) {
        $regObj = Get-Item -Path $customSrpKey -ErrorAction SilentlyContinue
        if ($null -ne $regObj) {
            foreach ($p in $regObj.Property) {
                $customSrpMap[$p] = $regObj.GetValue($p)
            }
            $regObj.Dispose()
        }
    }

    $activeSrpLocks = @()
    if (Get-Command Get-RegState_SRP -ErrorAction SilentlyContinue) {
        $activeSrpLocks = @(Get-RegState_SRP | Where-Object { -not $_.IsDetected } | Select-Object -ExpandProperty UIDisplayName)
    }

    $activeServices = @()
    if (Get-Command Get-ServicesState_Heavy -ErrorAction SilentlyContinue) {
        $activeServices = @(Get-ServicesState_Heavy | Where-Object { -not $_.IsDetected } | ForEach-Object { $_.ActionData.Name })
    }

    $activeTasks = @()
    if (Get-Command Get-TelemetryTasksState -ErrorAction SilentlyContinue) {
        $activeTasks = @(Get-TelemetryTasksState | Where-Object { -not $_.IsDetected } | Select-Object -ExpandProperty UIDisplayName)
    }

    $hwSnapshot = if (Get-Command Export-UltixHardwareSnapshot -ErrorAction SilentlyContinue) {
        Export-UltixHardwareSnapshot
    } else {
        @{ AffinityLasso = @(); CPPCUnhidden = @(); TimerTweaks = @(); NVMeTweaks = @(); GlobalNetwork = @() }
    }

    $snapshot = [ordered]@{
        SchemaVersion    = "WinUltix_Snapshot_v1"
        AppVersion       = $Global:AppVersion
        ExportTimestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        SourceMachine    = $env:COMPUTERNAME
        RegistryTweaks   = @($activeRegTweaks)
        CustomSrpRoster  = $customSrpMap
        ActiveSrpLocks   = @($activeSrpLocks)
        DisabledServices = @($activeServices)
        DisabledTasks    = @($activeTasks)
        AffinityLasso    = @($hwSnapshot.AffinityLasso)
        HardwareLocks    = [ordered]@{
            CPPCUnhidden  = @($hwSnapshot.CPPCUnhidden)
            TimerTweaks   = @($hwSnapshot.TimerTweaks)
            NVMeTweaks    = @($hwSnapshot.NVMeTweaks)
            GlobalNetwork = @($hwSnapshot.GlobalNetwork)
        }
    }

    try {
        $snapshot | ConvertTo-Json -Depth 6 | Set-Content -Path $targetFile -Encoding UTF8 -Force -ErrorAction Stop
        Update-Progress 0
        $hwCount = @($hwSnapshot.TimerTweaks).Count + @($hwSnapshot.NVMeTweaks).Count + @($hwSnapshot.CPPCUnhidden).Count
        Write-GUI " -> [OK] Profile exported ($($activeRegTweaks.Count) Reg, $($activeServices.Count) Svc, $($hwSnapshot.AffinityLasso.Count) Affinity, $hwCount HW Locks): $targetFile`n"
    } catch {
        Update-Progress 0
        Write-GUI " -> [!] Failed to export profile: $($_.Exception.Message)`n"
    }
}

function Import-WinUltixProfile {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "WinUltix Profile (*.json)|*.json"
    $ofd.Title = "Import WinUltix Configuration Snapshot"
    $ofd.InitialDirectory = [Environment]::GetFolderPath("Desktop")

    if ($ofd.ShowDialog($global:form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $sourceFile = $ofd.FileName
    $ofd.Dispose()

    try {
        $rawJson = Get-Content -Path $sourceFile -Raw -Encoding UTF8 -ErrorAction Stop
        $profileData = $rawJson | ConvertFrom-Json -ErrorAction Stop
        if ($profileData.SchemaVersion -ne "WinUltix_Snapshot_v1") {
            throw "Unsupported or corrupted WinUltix profile schema."
        }
    } catch {
        Write-GUI " -> [!] Profile import failed: $($_.Exception.Message)`n"
        return
    }

    $regCount = @($profileData.RegistryTweaks).Count
    $svcCount = @($profileData.DisabledServices).Count
    $srpCount = @($profileData.ActiveSrpLocks).Count
    $affCount = @($profileData.AffinityLasso).Count

    $confirmMsg = "Loaded snapshot from '$($profileData.SourceMachine)' ($($profileData.ExportTimestamp)):`n`n" +
                  " - Registry Tweaks: $regCount`n" +
                  " - Disabled Services: $svcCount`n" +
                  " - SRP+IFEO Locks: $srpCount`n" +
                  " - Affinity Lasso Roster: $affCount`n`n" +
                  "Do you want to enforce this profile on the current machine?"

    $ans = [System.Windows.Forms.MessageBox]::Show($confirmMsg, "WinUltix - Import Profile", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-GUI " -> Profile import cancelled.`n"
        return
    }

    Write-GUI "=== IMPORTING PROFILE FROM $($profileData.SourceMachine) ==="

    if ($null -ne $profileData.CustomSrpRoster) {
        $customSrpKey = "HKLM:\SOFTWARE\WinUltix\SRP"
        if (-not (Test-Path $customSrpKey)) { New-Item -Path $customSrpKey -Force | Out-Null }
        foreach ($prop in $profileData.CustomSrpRoster.PSObject.Properties) {
            Set-ItemProperty -Path $customSrpKey -Name $prop.Name -Value $prop.Value -Type String -Force
        }
    }

    if ($regCount -gt 0) {
        $targetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $profileData.RegistryTweaks) { [void]$targetSet.Add($t) }

        $allRegStates = @()
        foreach ($fn in @("Get-RegState_Taskbar", "Get-RegState_Explorer", "Get-RegState_Annoyances", "Get-RegState_Privacy", "Get-RegState_SystemBoot", "Get-RegState_Mouse", "Get-RegState_Gaming")) {
            if (Get-Command $fn -ErrorAction SilentlyContinue) { $allRegStates += (& $fn) }
        }
        $toApplyReg = @($allRegStates | Where-Object { $targetSet.Contains($_.UIDisplayName) -and $_.IsDetected })
        if ($toApplyReg.Count -gt 0) {
            Invoke-ApplyRegistry -SelectedItems $toApplyReg -CategoryName "Imported Profile" -Operation "Apply"
            Update-ShellEnvironment -ModifiedItems $toApplyReg
        }
    }

    if ($srpCount -gt 0 -and (Get-Command Get-RegState_SRP -ErrorAction SilentlyContinue)) {
        $srpSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($s in $profileData.ActiveSrpLocks) { [void]$srpSet.Add($s) }
        $toApplySrp = @(Get-RegState_SRP | Where-Object { $srpSet.Contains($_.UIDisplayName) -and $_.IsDetected })
        if ($toApplySrp.Count -gt 0) {
            Invoke-ApplySRP -SelectedItems $toApplySrp -Operation "Apply"
        }
    }

    if ($svcCount -gt 0 -and (Get-Command Get-ServicesState_Heavy -ErrorAction SilentlyContinue)) {
        $svcSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($sv in $profileData.DisabledServices) { [void]$svcSet.Add($sv) }
        $toApplySvc = @(Get-ServicesState_Heavy | Where-Object { $svcSet.Contains($_.ActionData.Name) -and $_.IsDetected })
        if ($toApplySvc.Count -gt 0) {
            Invoke-ApplyServices -SelectedItems $toApplySvc -ProfileName "Imported Profile" -Operation "Apply"
        }
    }

    if (@($profileData.DisabledTasks).Count -gt 0 -and (Get-Command Get-TelemetryTasksState -ErrorAction SilentlyContinue)) {
        $taskSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($tk in $profileData.DisabledTasks) { [void]$taskSet.Add($tk) }
        $toApplyTasks = @(Get-TelemetryTasksState | Where-Object { $taskSet.Contains($_.UIDisplayName) -and $_.IsDetected })
        if ($toApplyTasks.Count -gt 0) {
            Invoke-ApplyTasks -SelectedItems $toApplyTasks -Operation "Apply"
        }
    }

    if (Get-Command Import-UltixHardwareSnapshot -ErrorAction SilentlyContinue) {
        Import-UltixHardwareSnapshot -ProfileData $profileData
    } elseif ($affCount -gt 0) {
        $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
        if (-not (Test-Path $affPath)) { New-Item -Path $affPath -Force | Out-Null }
        foreach ($exe in $profileData.AffinityLasso) {
            Set-ItemProperty -Path $affPath -Name $exe -Value 1 -Type DWord -Force
        }
        Write-GUI " -> Restored $affCount process(es) to Affinity Lasso roster."
    }

    Update-Progress 0
    Write-GUI "=== PROFILE IMPORT COMPLETED ===`n"
}
# <<< END INJECTED: Core_Helpers.ps1 <<<


# Z1_Cleanup: Deep system cleaning. Removes Windows Update cache, Temp files, Event Viewer logs (wevtutil), and 3rd-party app caches. Enhanced button interactivity and optimized execution flows.
# >>> INJECTED: Z1_Cleanup.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z1_CLEANUP.PS1 - CLEANUP MODULE (v3.0.0)
# Z1_Cleanup: Manages deep system cleaning. Uses Core_Helpers high-speed .NET directory enumeration (Get-UltixFastSize) and asynchronous Runspace workers ($UltixSync) to weigh and purge Windows Update/CBS/DeliveryOptimization caches, Temp/WER/Dump buffers, Event Viewer logs (wevtutil), and multi-profile 3rd-party app/shader caches.
# ==========================================

# ------------------------------------------
# Z1: CLEANUP AUDITS (PURE RUNSPACE WORKER)
# ------------------------------------------
function Get-CleanupState {
    param([string]$Category)
    
    $rules   = [System.Collections.Generic.List[hashtable]]::new()
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($Category -eq "WU") {
        $rules.Add(@{
            UIDisplayName = "Windows Update Download Cache"
            Path          = "$env:windir\SoftwareDistribution\Download"
            Paths         = @("$env:windir\SoftwareDistribution\Download")
            Type          = "Files"
            ServiceGroup  = "WU"
        })
        $rules.Add(@{
            UIDisplayName = "Delivery Optimization Cache"
            Path          = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
            Paths         = @(
                "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache",
                "$env:windir\SoftwareDistribution\DeliveryOptimization"
            )
            Type          = "Files"
            ServiceGroup  = "WU"
        })
        $rules.Add(@{
            UIDisplayName = "Windows Update ETW Logs"
            Path          = "$env:windir\Logs\WindowsUpdate"
            Paths         = @("$env:windir\Logs\WindowsUpdate")
            Type          = "Files"
            ServiceGroup  = "None"
        })
        $rules.Add(@{
            UIDisplayName = "CBS Servicing Logs (Logs\CBS)"
            Path          = "$env:windir\Logs\CBS"
            Paths         = @("$env:windir\Logs\CBS")
            Type          = "Files"
            ServiceGroup  = "CBS"
        })
    }

    if ($Category -eq "Temp") {
        $rules.Add(@{ UIDisplayName = "Windows System Temp"; Path = "$env:windir\Temp"; Paths = @("$env:windir\Temp"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Global User Temp"; Path = "$env:TEMP"; Paths = @("$env:TEMP"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Windows Prefetch"; Path = "$env:windir\Prefetch"; Paths = @("$env:windir\Prefetch"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "WER Report Archive (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "WER Report Queue (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue"); Type = "Files" })

        if ([System.IO.File]::Exists("$env:windir\MEMORY.DMP")) {
            $rules.Add(@{ UIDisplayName = "System Memory Dump"; Path = "$env:windir\MEMORY.DMP"; Paths = @("$env:windir\MEMORY.DMP"); Type = "Files" })
        }
        if ([System.IO.Directory]::Exists("$env:windir\Minidump")) {
            $rules.Add(@{ UIDisplayName = "Minidump Files"; Path = "$env:windir\Minidump"; Paths = @("$env:windir\Minidump"); Type = "Files" })
        }

        foreach ($prof in (Get-UltixUserProfiles)) {
            $userName = $prof.UserName
            $base     = $prof.LocalPath
            $rules.Add(@{ UIDisplayName = "User Temp ($userName)"; Path = "$base\AppData\Local\Temp"; Paths = @("$base\AppData\Local\Temp"); Type = "Files" })
            
            $userWerPaths = @(
                "$base\AppData\Local\Microsoft\Windows\WER\ReportArchive",
                "$base\AppData\Local\Microsoft\Windows\WER\ReportQueue"
            )
            if ([System.IO.Directory]::Exists($userWerPaths[0]) -or [System.IO.Directory]::Exists($userWerPaths[1])) {
                $rules.Add(@{ UIDisplayName = "User WER Reports ($userName)"; Path = $userWerPaths[0]; Paths = $userWerPaths; Type = "Files" })
            }
        }
    }

    if ($Category -eq "EventLogs") {
        $rules.Add(@{ UIDisplayName = "Windows Event Logs"; Path = "$env:windir\System32\winevt\Logs"; Paths = @("$env:windir\System32\winevt\Logs"); Type = "EventLogs" })
    }

    if ($Category -eq "ThirdParty") {
        # Chromium browsers supporting multi-profile (Default + Profile *)
        $chromiumBrowsers = @(
            @{ Name = "Chrome";  RelUserData = "AppData\Local\Google\Chrome\User Data" }
            @{ Name = "Edge";    RelUserData = "AppData\Local\Microsoft\Edge\User Data" }
            @{ Name = "Brave";   RelUserData = "AppData\Local\BraveSoftware\Brave-Browser\User Data" }
            @{ Name = "Vivaldi"; RelUserData = "AppData\Local\Vivaldi\User Data" }
        )

        # Static single-path per-user caches
        $userCaches = @(
            @{ Name = "Opera Cache";       Path = "AppData\Local\Opera Software\Opera Stable\Cache" }
            @{ Name = "Opera Code";        Path = "AppData\Local\Opera Software\Opera Stable\Code Cache" }
            @{ Name = "Opera GPU";         Path = "AppData\Local\Opera Software\Opera Stable\GPUCache" }
            @{ Name = "Opera GX Cache";    Path = "AppData\Local\Opera Software\Opera GX Stable\Cache" }
            @{ Name = "Opera GX Code";     Path = "AppData\Local\Opera Software\Opera GX Stable\Code Cache" }
            @{ Name = "Opera GX GPU";      Path = "AppData\Local\Opera Software\Opera GX Stable\GPUCache" }
            @{ Name = "Discord Cache";     Path = "AppData\Roaming\discord\Cache" }
            @{ Name = "Discord Code";      Path = "AppData\Roaming\discord\Code Cache" }
            @{ Name = "Discord GPU";       Path = "AppData\Roaming\discord\GPUCache" }
            @{ Name = "Steam HTML";        Path = "AppData\Local\Steam\htmlcache" }
            @{ Name = "Epic Games Web";    Path = "AppData\Local\EpicGamesLauncher\Saved\webcache" }
            @{ Name = "Epic Games Http";   Path = "AppData\Local\EpicGamesLauncher\Saved\HttpCache" }
            @{ Name = "Spotify Data";      Path = "AppData\Local\Spotify\Data" }
            @{ Name = "Spotify Browser";   Path = "AppData\Local\Spotify\Browser\Cache" }
            @{ Name = "Deezer";            Path = "AppData\Roaming\deezer-desktop\Cache" }
            @{ Name = "VLC Art";           Path = "AppData\Roaming\vlc\art" }
            @{ Name = "DirectX D3DSCache"; Path = "AppData\Local\D3DSCache" }
            @{ Name = "NVIDIA DXCache";    Path = "AppData\Local\NVIDIA\DXCache" }
            @{ Name = "NVIDIA GLCache";    Path = "AppData\Local\NVIDIA\GLCache" }
            @{ Name = "AMD DxCache";       Path = "AppData\Local\AMD\DxCache" }
        )

        $globalCaches = @(
            @{ Name = "Battle.net"; Path = "$env:ProgramData\Battle.net\Cache" }
            @{ Name = "GOG Galaxy"; Path = "$env:ProgramData\GOG.com\Galaxy\webcache" }
        )

        # Dynamic profile resolution via Core_Helpers Get-UltixUserProfiles (Zero hardcoded C:\Users)
        foreach ($prof in (Get-UltixUserProfiles)) {
            $usr  = $prof.UserName
            $base = $prof.LocalPath

            # 1. Multi-profile Chromium enumeration (Default + Profile *)
            foreach ($browser in $chromiumBrowsers) {
                $userDataDir = Join-Path -Path $base -ChildPath $browser.RelUserData
                if ([System.IO.Directory]::Exists($userDataDir)) {
                    $profDirs = @(Get-ChildItem -LiteralPath $userDataDir -Directory -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" })

                    if ($profDirs.Count -gt 0) {
                        foreach ($profDir in $profDirs) {
                            $pName = $profDir.Name
                            $pFull = $profDir.FullName
                            $rules.Add(@{ UIDisplayName = "$($browser.Name) Cache ($usr - $pName)";      Path = "$pFull\Cache";      Paths = @("$pFull\Cache");      Type = "Files" })
                            $rules.Add(@{ UIDisplayName = "$($browser.Name) Code Cache ($usr - $pName)"; Path = "$pFull\Code Cache"; Paths = @("$pFull\Code Cache"); Type = "Files" })
                            $rules.Add(@{ UIDisplayName = "$($browser.Name) GPUCache ($usr - $pName)";   Path = "$pFull\GPUCache";   Paths = @("$pFull\GPUCache");   Type = "Files" })
                        }
                    } else {
                        $rules.Add(@{ UIDisplayName = "$($browser.Name) Cache ($usr)"; Path = "$userDataDir\Default\Cache"; Paths = @("$userDataDir\Default\Cache"); Type = "Files" })
                    }
                } else {
                    $rules.Add(@{ UIDisplayName = "$($browser.Name) Cache ($usr)"; Path = "$userDataDir\Default\Cache"; Paths = @("$userDataDir\Default\Cache"); Type = "Files" })
                }
            }

            # 2. Standard per-user app & shader caches
            foreach ($app in $userCaches) {
                $fullAppPath = "$base\$($app.Path)"
                $rules.Add(@{ UIDisplayName = "$($app.Name) ($usr)"; Path = $fullAppPath; Paths = @($fullAppPath); Type = "Files" })
            }
            
            # 3. Firefox multi-profile enumeration
            $ffProfilesPath = "$base\AppData\Local\Mozilla\Firefox\Profiles"
            if ([System.IO.Directory]::Exists($ffProfilesPath)) {
                $ffFolders = Get-ChildItem -LiteralPath $ffProfilesPath -Directory -Force -ErrorAction SilentlyContinue
                foreach ($ff in $ffFolders) {
                    $rules.Add(@{ UIDisplayName = "Firefox Cache ($usr - $($ff.Name))";   Path = "$($ff.FullName)\cache2";       Paths = @("$($ff.FullName)\cache2");       Type = "Files" })
                    $rules.Add(@{ UIDisplayName = "Firefox Startup ($usr - $($ff.Name))"; Path = "$($ff.FullName)\startupCache"; Paths = @("$($ff.FullName)\startupCache"); Type = "Files" })
                }
            }
        }

        foreach ($app in $globalCaches) {
            $rules.Add(@{ UIDisplayName = "$($app.Name) Cache (Global)"; Path = $app.Path; Paths = @($app.Path); Type = "Files" })
        }
    }

    if ($Category -eq "RecycleBin") {
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
            $binPath = "$($drive.Root)`$Recycle.Bin"
            $rules.Add(@{ UIDisplayName = "Recycle Bin ($($drive.Name):)"; Path = $binPath; Paths = @($binPath); Type = "RecycleBin" })
        }
    }

    $totalRules = $rules.Count
    $currentIdx = 0

    foreach ($rule in $rules) {
        $currentIdx++
        if ($null -ne $UltixSync -and $totalRules -gt 0) {
            $UltixSync.Progress = [int](($currentIdx / $totalRules) * 100)
        }

        $isDetected = $false
        $sizeMB = 0

        $targetList = if ($rule.ContainsKey("Paths") -and $null -ne $rule.Paths) { [string[]]$rule.Paths } else { [string[]]@($rule.Path) }
        $bytes = Get-UltixFastSize -TargetPaths $targetList

        if ($bytes -gt 0) {
            $sizeMB = [math]::Round(($bytes / 1MB), 2)
        }

        if ($sizeMB -ge 1) {
            $isDetected = $true
            $displayName = "$($rule.UIDisplayName) [ $sizeMB MB ]"
        } else {
            $displayName = "$($rule.UIDisplayName) [ Clean ]"
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = $displayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    
    return $results
}

# ------------------------------------------
# Z1: ASYNCHRONOUS CLEANING ENGINE ($UltixSync)
# ------------------------------------------
function Invoke-InteractiveCleanup {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    if ($SelectedItems.Count -eq 0) { return }

    Write-GUI " -> Dispatching cleanup worker to background Runspace..."
    Update-Progress 5

    # Wrap $SelectedItems as a single-element array @(,$SelectedItems) so Invoke-AsyncTask passes it as one parameter
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)

        $total = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
            }

            $rule = $item.ActionData
            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue(" -> Purging: $($rule.UIDisplayName)...")
            }

            try {
                if ($rule.Type -eq "EventLogs") {
                    $channels = @(wevtutil.exe el 2>$null)
                    $totalCh  = $channels.Count
                    $chIdx    = 0

                    foreach ($ch in $channels) {
                        $chIdx++
                        if ($null -ne $UltixSync -and $totalCh -gt 0 -and ($chIdx % 20 -eq 0)) {
                            $UltixSync.Progress = [int](($chIdx / $totalCh) * 100)
                        }
                        & wevtutil.exe cl "$ch" 2>$null
                    }
                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [OK] Cleared $totalCh Event Viewer channel(s).")
                    }
                }
                elseif ($rule.Type -eq "RecycleBin") {
                    $path = $rule.Path
                    if (Test-Path -LiteralPath $path) {
                        & takeown.exe /F "$path\*" /R /A /D Y 2>$null | Out-Null
                        # Use well-known Administrators SID (*S-1-5-32-544) for locale independence
                        & icacls.exe "$path\*" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                elseif ($rule.Type -eq "Files") {
                    $targetPaths = if ($rule.ContainsKey("Paths") -and $null -ne $rule.Paths) { $rule.Paths } else { @($rule.Path) }
                    $svcGroup    = if ($rule.ContainsKey("ServiceGroup")) { $rule.ServiceGroup } else { "None" }

                    $servicesToManage = switch ($svcGroup) {
                        "WU"  { @("dosvc", "bits", "wuauserv") }
                        "CBS" { @("TrustedInstaller") }
                        default {
                            if ($rule.UIDisplayName -match "Windows Update|Delivery Optimization") {
                                @("dosvc", "bits", "wuauserv")
                            } else {
                                @()
                            }
                        }
                    }

                    $runningServices = [System.Collections.Generic.List[string]]::new()

                    try {
                        # Capture initial service states and stop running instances
                        foreach ($svcName in $servicesToManage) {
                            $svcObj = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                            if ($null -ne $svcObj -and $svcObj.Status -eq 'Running') {
                                $runningServices.Add($svcName)
                                Stop-Service -Name $svcName -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                            }
                        }

                        foreach ($tPath in $targetPaths) {
                            if ([string]::IsNullOrWhiteSpace($tPath) -or -not (Test-Path -LiteralPath $tPath)) { continue }

                            if ($servicesToManage.Count -gt 0) {
                                & takeown.exe /F "$tPath\*" /R /A /D Y 2>$null | Out-Null
                                & icacls.exe "$tPath\*" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                            }

                            if (Test-Path -LiteralPath $tPath -PathType Leaf) {
                                Remove-Item -LiteralPath $tPath -Force -ErrorAction SilentlyContinue
                            } else {
                                Get-ChildItem -LiteralPath $tPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    } finally {
                        # Symmetrically restore only services that were running prior to cleanup (excluding TrustedInstaller demand service)
                        foreach ($svcName in $runningServices) {
                            if ($svcName -ne "TrustedInstaller") {
                                Start-Service -Name $svcName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Partial lock on $($rule.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Cleanup operation completed.`n"
    }
}

# ------------------------------------------
# Z1: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z1UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabClean = New-Object System.Windows.Forms.TabPage
    $tabClean.Text = "Cleanup"
    $tabClean.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    $invokeCategory = {
        param([string]$Cat, [switch]$Audit)
        Invoke-UltixAuditFlow `
            -ScannerFunction "Get-CleanupState" `
            -ScannerArguments @($Cat) `
            -AuditLabel $Cat `
            -ModalTitle "WinUltix - $Cat Purge" `
            -ModalDescription "Select items to empty." `
            -ExecutorFunction "Invoke-InteractiveCleanup" `
            -ControlsToDisable $allTabButtons.ToArray() `
            -AuditOnly:$Audit.IsPresent
    }.GetNewClosure()

    # 1. Windows Update Cache
    $rowWU = New-UltixActionRow -Parent $tabClean -Y 20 `
        -Text "Clean Windows Update Cache" `
        -Description "Analyzes and interactively purges Windows Update (SoftwareDistribution), Delivery Optimization, and CBS Servicing logs safely." `
        -AuditDescription "AUDIT: Calculates the exact megabyte footprint of Windows Update, Delivery Optimization, and CBS log files." `
        -OnClick ({ & $invokeCategory "WU" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "WU" -Audit }.GetNewClosure())

    # 2. Temp & Prefetch Buffers
    $rowTemp = New-UltixActionRow -Parent $tabClean -Y 70 `
        -Text "Clean Temp and Prefetch Buffers" `
        -Description "Scans and weighs System Temp, Prefetch, Windows Error Reporting (WER), Crash Dumps, and local Temp directories across all user profiles." `
        -AuditDescription "AUDIT: Weighs orphaned temporary files, WER reports, crash dumps, and prefetch data globally." `
        -OnClick ({ & $invokeCategory "Temp" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "Temp" -Audit }.GetNewClosure())

    # 3. Event Viewer Logs
    $rowLogs = New-UltixActionRow -Parent $tabClean -Y 120 `
        -Text "Clear Event Viewer Logs" `
        -Description "Calculates the size of Event Logs (.evtx) and asynchronously clears diagnostic history using the native wevtutil engine." `
        -AuditDescription "AUDIT: Checks the current disk space consumed by Windows Event Logs." `
        -OnClick ({ & $invokeCategory "EventLogs" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "EventLogs" -Audit }.GetNewClosure())

    # 4. Third-Party App Cache
    $rowThirdParty = New-UltixActionRow -Parent $tabClean -Y 170 `
        -Text "Clean Third-Party App Cache" `
        -Description "Locates bloated application and shader caches (Multi-profile Chrome/Edge/Brave/Vivaldi/Firefox, Discord, D3DSCache, NVIDIA/AMD DxCache) across all user profiles." `
        -AuditDescription "AUDIT: Aggregates the storage space wasted by third-party browser, launcher, and GPU shader caches." `
        -OnClick ({ & $invokeCategory "ThirdParty" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "ThirdParty" -Audit }.GetNewClosure())

    # 5. Recycle Bin
    $rowRecycle = New-UltixActionRow -Parent $tabClean -Y 220 `
        -Text "Hard Empty Recycle Bin (NTFS)" `
        -MainRGB @(100, 40, 40) -AuditRGB @(100, 40, 40) `
        -Description "Scans all logical partitions for Recycle Bin contents and forcefully purges them in a background thread, bypassing standard file locks." `
        -AuditDescription "AUDIT: Reports the total size of deleted files waiting in the Recycle Bins across all partitions." `
        -OnClick ({ & $invokeCategory "RecycleBin" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "RecycleBin" -Audit }.GetNewClosure())

    foreach ($row in @($rowWU, $rowTemp, $rowLogs, $rowThirdParty, $rowRecycle)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabClean)
}
# <<< END INJECTED: Z1_Cleanup.ps1 <<<


# Z2_Bloatware: Aggressive debloatifier. Incorporates CBS and Appx state verification. Enhanced OneDrive removal across profiles, FOD package management, and intelligent orphaned framework collection (Garbage Collector).
# >>> INJECTED: Z2_Bloatware.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z2_BLOATWARE.PS1 - BLOATWARE & APPS MODULE (v3.0.0)
# Z2_Bloatware: Aggressive debloatifier. Uses Core_Helpers profile/hive discovery (Get-UltixUserProfiles), fast .NET directory sizing (Get-UltixFastSize), and asynchronous Runspace workers ($UltixSync) to amputate OneDrive, remove FOD Capabilities, clean orphaned Appx frameworks, lock down Windows Recall/AI, and purge UWP bloatware.
# ==========================================

# ------------------------------------------
# Z2: BLOATWARE AUDITS (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-OneDriveState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    $userProfiles = @(Get-UltixUserProfiles)
    $loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded })

    # Fallback to HKCU if no loaded SID hives were returned
    if ($loadedHives.Count -eq 0) {
        $loadedHives = @(
            [PSCustomObject]@{
                SID          = "CurrentUser"
                UserName     = $env:USERNAME
                LocalPath    = $env:USERPROFILE
                HiveRoot     = "HKCU:"
                IsHiveLoaded = $true
            }
        )
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 30 }

    # 1. Core Executables & Multi-Profile Run Keys (SystemRoot stubs are left dormant for SFC/DISM integrity)
    $localExe  = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    $liveProc  = Get-Process -Name "OneDrive", "OneDriveSetup" -ErrorAction SilentlyContinue
    $hasRunKey = $false

    foreach ($hive in $loadedHives) {
        $runPath = "$($hive.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path -Path $runPath) {
            $runProps = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
            if ($null -ne $runProps -and ($runProps.PSObject.Properties.Match("OneDriveSetup").Count -gt 0 -or $runProps.PSObject.Properties.Match("OneDrive").Count -gt 0)) {
                $hasRunKey = $true
                break
            }
        }
    }

    foreach ($prof in $userProfiles) {
        if ($hasRunKey) { break }
        if (Test-Path -Path (Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive\OneDrive.exe")) {
            $hasRunKey = $true
            break
        }
    }

    $isCoreDetected = ((Test-Path -Path $localExe) -or $hasRunKey -or ($null -ne $liveProc))

    $results.Add([PSCustomObject]@{
        UIDisplayName = "Core: OneDrive Setup and Startup Routine"
        IsDetected    = $isCoreDetected
        ActionData    = @{ Type = "Core" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 55 }

    # 2. Multi-Profile Zombie Registry Keys (Inspected across all loaded HKEY_USERS\<SID> hives)
    $zombieSubKeys = @("SyncEngine", "Client_Policy", "Accounts")
    foreach ($hive in $loadedHives) {
        foreach ($subKey in $zombieSubKeys) {
            $fullRegPath = "$($hive.HiveRoot)\Software\Microsoft\OneDrive\$subKey"
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Registry ($($hive.UserName)): $subKey"
                IsDetected    = (Test-Path -Path $fullRegPath)
                ActionData    = @{ Type = "Registry"; Path = $fullRegPath }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }

    # 3. System Data Folders
    $staticFolders = @("$env:PROGRAMDATA\Microsoft OneDrive", "$env:SystemDrive\OneDriveTemp")
    foreach ($folder in $staticFolders) {
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Folder: $folder"
            IsDetected    = (Test-Path -Path $folder)
            ActionData    = @{ Type = "Folder"; Path = $folder }
        })
    }

    # 4. Dynamic User Profiles Data Folders (Zero hardcoded C:\Users)
    foreach ($prof in $userProfiles) {
        $userPath = Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"
        $results.Add([PSCustomObject]@{
            UIDisplayName = "User Data: $($prof.UserName)"
            IsDetected    = (Test-Path -Path $userPath)
            ActionData    = @{ Type = "Folder"; Path = $userPath }
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-CapabilitiesState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 15 }
    $capsWildcards = @(
        "*Print.Fax.Scan*", "*App.StepsRecorder*", "*Media.WindowsMediaPlayer*",
        "*MathRecognizer*", "*App.Support.QuickAssist*", "*Microsoft.Windows.WordPad*",
        "*Hello.Face*", "*OneCoreUAP.OneSync*", "*Browser.InternetExplorer*",
        "*Microsoft.Wallpapers.Extended*", "*Print.Management.Console*",
        "*Language.Handwriting*", "*Language.Speech*", "*Wifi.Client*"
    )

    $installedCaps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Installed' })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 65 }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $capsWildcards.Count
    $idx     = 0

    foreach ($capName in $capsWildcards) {
        $idx++
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 65 + [int](($idx / $total) * 35)
        }
        $found      = @($installedCaps | Where-Object { $_.Name -like $capName })
        $isDetected = ($found.Count -gt 0)
        $cleanName  = $capName.Replace("*", "")

        $results.Add([PSCustomObject]@{
            UIDisplayName = "FOD: $cleanName"
            IsDetected    = $isDetected
            ActionData    = $found
        })
    }
    return $results
}

function Get-GarbageCollectorState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if ($null -ne $UltixSync) { $UltixSync.Progress = 35 }

    # Complete protected framework & shared system UI whitelist (Win11 24H2/25H2/26H2 + Gaming Identity)
    $critical = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|MicrosoftWindows\.Client|MicrosoftWindows\.CrossDevice|Windows\.CBSPreview|Windows\.PrintDialog|Microsoft\.AsyncTextService|Microsoft\.AccountsControl|Microsoft\.CredDialogHost|Microsoft\.ECApp|Microsoft\.LockApp|Microsoft\.BioEnrollment|ApplicationCompatibilityEnhancements|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension"

    # 1. Seed active dependencies from all non-framework packages (including NonRemovable SystemApps and ResourcePackages)
    $rootPackages       = @($allPackages | Where-Object { $_.IsFramework -eq $false -or $_.IsResourcePackage -eq $true -or $_.NonRemovable -eq $true -or $_.Name -match $critical })
    $activeDependencies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedNames     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pkg in $allPackages) {
        if (-not [string]::IsNullOrWhiteSpace($pkg.Name)) {
            [void]$installedNames.Add($pkg.Name)
        }
    }

    foreach ($app in $rootPackages) {
        if ($app.Dependencies) {
            foreach ($dep in $app.Dependencies) {
                if (-not [string]::IsNullOrWhiteSpace($dep.PackageFullName)) {
                    [void]$activeDependencies.Add($dep.PackageFullName)
                }
            }
        }
    }

    # 2. Compute transitive closure for Framework -> Framework dependency chains
    $allFrameworks = @($allPackages | Where-Object { $_.IsFramework -eq $true })
    $addedNew = $true
    while ($addedNew) {
        $addedNew = $false
        foreach ($fw in $allFrameworks) {
            if ($activeDependencies.Contains($fw.PackageFullName) -and $fw.Dependencies) {
                foreach ($nestedDep in $fw.Dependencies) {
                    if (-not [string]::IsNullOrWhiteSpace($nestedDep.PackageFullName)) {
                        if ($activeDependencies.Add($nestedDep.PackageFullName)) {
                            $addedNew = $true
                        }
                    }
                }
            }
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 65 }

    # 3. Filter candidate frameworks strictly excluding protected runtimes, non-removable packages, and resource packs
    $candidateFrameworks = @($allFrameworks | Where-Object {
        $_.NonRemovable -eq $false -and
        $_.IsResourcePackage -eq $false -and
        $_.Name -notmatch $critical
    })

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($fw in $candidateFrameworks) {
        if (-not $activeDependencies.Contains($fw.PackageFullName)) {
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Framework: $($fw.Name) ($($fw.Version))"
                IsDetected    = $true
                ActionData    = @{ Type = "Framework"; Target = $fw.PackageFullName }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 85 }

    # 4. Inspect Provisioned packages (shielded by $critical regex)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($prov in $provisioned) {
        if ($prov.DisplayName -match $critical) { continue }
        if (-not $installedNames.Contains($prov.DisplayName)) {
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Base: $($prov.DisplayName)"
                IsDetected    = $true
                ActionData    = @{ Type = "Provisioned"; Target = $prov.PackageName }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-BloatwareState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }

    # Ordered, non-overlapping definitions matching Windows 11 24H2/25H2/26H2 packages
    $appCatalog = @(
        @{ Label = "Windows Recall & AI Snapshots (24H2/25H2/26H2)"; Pattern = "*Recall*|*AIDataAnalysis*"; IsRecall = $true }
        @{ Label = "Windows Copilot & AI Assistant";              Pattern = "*Copilot*" }
        @{ Label = "Microsoft Bing Search (BingSearch)";          Pattern = "*BingSearch*" }
        @{ Label = "Microsoft News (BingNews)";                   Pattern = "*BingNews*" }
        @{ Label = "Microsoft Weather (BingWeather)";             Pattern = "*BingWeather*" }
        @{ Label = "Microsoft Finance / Sports / Food (Bing)";    Pattern = "Microsoft.BingFinance|Microsoft.BingSports|Microsoft.BingFoodAndDrink|Microsoft.BingTravel|Microsoft.BingHealthAndFitness|Microsoft.BingTranslator" }
        @{ Label = "Microsoft To Do (Todos)";                     Pattern = "*Todos*" }
        @{ Label = "Microsoft Sticky Notes (StickyNotes)";        Pattern = "*StickyNotes*" }
        @{ Label = "Microsoft Teams Personal / Work (MSTeams)";   Pattern = "*MSTeams*|*MicrosoftTeams*" }
        @{ Label = "New Outlook for Windows (OutlookForWindows)"; Pattern = "*OutlookForWindows*" }
        @{ Label = "Mail & Calendar (CommunicationsApps)";        Pattern = "*windowscommunicationsapps*" }
        @{ Label = "Microsoft 365 / Office Hub";                  Pattern = "*MicrosoftOfficeHub*" }
        @{ Label = "Microsoft OneNote (UWP)";                     Pattern = "*OneNote*" }
        @{ Label = "Microsoft Family Safety";                     Pattern = "*MicrosoftFamily*|*Family*" }
        @{ Label = "Microsoft Clipchamp Video Editor";            Pattern = "*Clipchamp*" }
        @{ Label = "Windows Dev Home (DevHome)";                  Pattern = "*DevHome*" }
        @{ Label = "Power Automate Desktop";                      Pattern = "*PowerAutomateDesktop*" }
        @{ Label = "Microsoft Edge Game Assist";                  Pattern = "*Edge.GameAssist*" }
        @{ Label = "Windows Widgets (Client.WebExperience)";      Pattern = "*Client.WebExperience*" }
        @{ Label = "Widgets Platform Runtime";                    Pattern = "*WidgetsPlatformRuntime*" }
        @{ Label = "Cross Device Experience Host";                Pattern = "*CrossDevice*" }
        @{ Label = "Phone Link (YourPhone)";                      Pattern = "*YourPhone*" }
        @{ Label = "Quick Assist (Remote Help)";                  Pattern = "*QuickAssist*" }
        @{ Label = "Windows Feedback Hub";                        Pattern = "*FeedbackHub*" }
        @{ Label = "Get Help (Contact Support)";                  Pattern = "*GetHelp*" }
        @{ Label = "Windows Tips (GetStarted)";                   Pattern = "*Getstarted*" }
        @{ Label = "Windows Maps";                                Pattern = "*WindowsMaps*" }
        @{ Label = "Windows Alarms & Clock";                      Pattern = "*WindowsAlarms*" }
        @{ Label = "Windows Voice Recorder (SoundRecorder)";      Pattern = "*SoundRecorder*" }
        @{ Label = "Windows Camera";                              Pattern = "*WindowsCamera*" }
        @{ Label = "Windows Photos";                              Pattern = "*Windows.Photos*" }
        @{ Label = "Media Player / Groove Music (ZuneMusic)";     Pattern = "*ZuneMusic*" }
        @{ Label = "Movies & TV (ZuneVideo)";                     Pattern = "*ZuneVideo*" }
        @{ Label = "Microsoft Solitaire Collection";              Pattern = "*SolitaireCollection*" }
        @{ Label = "Xbox App (GamingApp)";                        Pattern = "*GamingApp*|*XboxApp*" }
        @{ Label = "Xbox Game Bar (XboxGamingOverlay)";           Pattern = "*XboxGamingOverlay*" }
        @{ Label = "Xbox Speech To Text Overlay";                 Pattern = "*XboxSpeechToTextOverlay*" }
        @{ Label = "Xbox TCUI (Live In-Game Experience)";         Pattern = "*Xbox.TCUI*" }
        @{ Label = "Microsoft People";                            Pattern = "*Microsoft.People*" }
        @{ Label = "Skype UWP";                                   Pattern = "*SkypeApp*" }
        @{ Label = "Cortana";                                     Pattern = "*Cortana*" }
        @{ Label = "Mixed Reality Portal";                        Pattern = "*MixedReality*" }
        @{ Label = "3D Builder & 3D Viewer";                      Pattern = "*3DBuilder*|*3DViewer*" }
        @{ Label = "OneDrive UWP Sync Client";                    Pattern = "*OneDriveSync*" }

        # Third-Party Casual Games (Granular)
        @{ Label = "King: Candy Crush Saga";                      Pattern = "*CandyCrush*" }
        @{ Label = "King: Bubble Witch Saga";                     Pattern = "*BubbleWitch*" }
        @{ Label = "King: Farm Heroes Saga";                      Pattern = "*FarmHeroes*" }
        @{ Label = "Gameloft: March of Empires";                  Pattern = "*MarchofEmpires*" }
        @{ Label = "Playrix: Homescapes";                         Pattern = "*Homescapes*" }
        @{ Label = "Playrix: Township";                           Pattern = "*Township*" }
        @{ Label = "Disney Interactive (Magic Kingdoms / Games)"; Pattern = "*Disney*" }

        # Third-Party Social & Streaming Media (Granular)
        @{ Label = "TikTok";                                      Pattern = "*TikTok*" }
        @{ Label = "Meta: Instagram";                             Pattern = "*Instagram*" }
        @{ Label = "Meta: Facebook";                              Pattern = "*Facebook*" }
        @{ Label = "Twitter / X";                                 Pattern = "*Twitter*" }
        @{ Label = "LinkedIn";                                    Pattern = "*LinkedIn*" }
        @{ Label = "Netflix";                                     Pattern = "*Netflix*" }
        @{ Label = "Spotify Music";                               Pattern = "*Spotify*" }
        @{ Label = "Amazon (Prime Video / Shopping)";             Pattern = "*Amazon*" }

        # OEM Software & Trialware Suites (Granular)
        @{ Label = "McAfee Security Suite";                       Pattern = "*McAfee*" }
        @{ Label = "Norton Security Suite";                       Pattern = "*Norton*" }
        @{ Label = "Lenovo OEM Bloatware & Vantage Stubs";        Pattern = "*Lenovo*" }
        @{ Label = "Dell SupportAssist & OEM Stubs";              Pattern = "*Dell*" }
        @{ Label = "HP Support Assistant & OEM Stubs";            Pattern = "*HP*" }
    )

    # Ironclad whitelist protecting Xbox/Steam identity, core system applets, and AI Fabric/AugLoop runtimes
    $protectedRegex = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|WindowsStore|StorePurchaseApp|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension|ApplicationCompatibilityEnhancements|MicrosoftEdge\.Stable"

    $installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedRegex })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }

    $provAppx = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch $protectedRegex })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 40 }

    # Query Recall Optional Feature and AI Data Analysis Policy state
    $recallFeature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
    $isRecallFeatEnabled = ($null -ne $recallFeature -and ($recallFeature.State -eq 'Enabled' -or $recallFeature.State -eq 'EnablePending'))

    $aiPolPathLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    $aiPolPathCU = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
    $aiPolValLM  = (Get-ItemProperty -Path $aiPolPathLM -Name "DisableAIDataAnalysis" -ErrorAction SilentlyContinue).DisableAIDataAnalysis
    $aiPolValCU  = (Get-ItemProperty -Path $aiPolPathCU -Name "DisableAIDataAnalysis" -ErrorAction SilentlyContinue).DisableAIDataAnalysis
    $isRecallPolicyLocked = ($aiPolValLM -eq 1 -and $aiPolValCU -eq 1)

    $seenInstalled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenProv      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results       = [System.Collections.Generic.List[PSCustomObject]]::new()

    $totalEntries = $appCatalog.Count
    $entryIdx     = 0

    foreach ($entry in $appCatalog) {
        $entryIdx++
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 40 + [int](($entryIdx / $totalEntries) * 60)
        }

        $patterns = $entry.Pattern -split '\|'

        $foundInstalled = [System.Collections.Generic.List[object]]::new()
        foreach ($pkg in $installedAppx) {
            if ($seenInstalled.Contains($pkg.PackageFullName)) { continue }
            foreach ($pat in $patterns) {
                if ($pkg.Name -like $pat) {
                    $foundInstalled.Add($pkg)
                    [void]$seenInstalled.Add($pkg.PackageFullName)
                    break
                }
            }
        }

        $foundProv = [System.Collections.Generic.List[object]]::new()
        foreach ($prov in $provAppx) {
            if ($seenProv.Contains($prov.PackageName)) { continue }
            foreach ($pat in $patterns) {
                if ($prov.DisplayName -like $pat) {
                    $foundProv.Add($prov)
                    [void]$seenProv.Add($prov.PackageName)
                    break
                }
            }
        }

        $installLocations = @($foundInstalled | ForEach-Object { $_.InstallLocation } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $totalBytes       = if ($installLocations.Count -gt 0) { Get-UltixFastSize -TargetPaths $installLocations } else { 0 }
        $totalSizeMB      = if ($totalBytes -gt 0) { $totalBytes / 1MB } else { 0 }

        if ($entry.IsRecall) {
            $isDetected = $isRecallFeatEnabled -or (-not $isRecallPolicyLocked) -or ($foundInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)
            $sizeLabel  = ""
            if ($isDetected) {
                if ($isRecallFeatEnabled) {
                    $sizeLabel = " [ OptionalFeature: Enabled ]"
                } elseif (-not $isRecallPolicyLocked) {
                    $sizeLabel = " [ AI Policy: Unlocked ]"
                } elseif ($totalSizeMB -ge 0.5) {
                    $sizeLabel = " [ $([math]::Round($totalSizeMB, 1)) MB ]"
                } else {
                    $sizeLabel = " [ Active Trace ]"
                }
            }

            $results.Add([PSCustomObject]@{
                UIDisplayName = "$($entry.Label)$sizeLabel"
                IsDetected    = $isDetected
                ActionData    = @{
                    IsRecall      = $true
                    RecallFeature = $isRecallFeatEnabled
                    Installed     = @($foundInstalled)
                    Provisioned   = @($foundProv)
                }
            })
            continue
        }

        $isDetected = ($foundInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)

        $sizeLabel = ""
        if ($isDetected) {
            if ($totalSizeMB -ge 0.5) {
                $sizeLabel = " [ $([math]::Round($totalSizeMB, 1)) MB ]"
            } elseif ($foundInstalled.Count -gt 0) {
                $sizeLabel = " [ Installed Stub ]"
            } elseif ($foundProv.Count -gt 0) {
                $sizeLabel = " [ Provisioned Image ]"
            }
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = "$($entry.Label)$sizeLabel"
            IsDetected    = $isDetected
            ActionData    = @{
                IsRecall    = $false
                Installed   = @($foundInstalled)
                Provisioned = @($foundProv)
            }
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-CapabilityStubState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 20 }
    $cbsStubs = @(Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match "(?i)stub" -and $_.PackageState -eq "Installed" })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 80 }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($stub in $cbsStubs) {
        $cleanName = ($stub.PackageName -split '~')[0]
        $results.Add([PSCustomObject]@{
            UIDisplayName = "CBS Stub: $cleanName"
            IsDetected    = $true
            ActionData    = $stub.PackageName
        })
    }
    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

# ------------------------------------------
# Z2: BLOATWARE & APPS ENGINE (ASYNC RUNSPACE EXECUTORS)
# ------------------------------------------
function Invoke-RemoveOneDrive {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No OneDrive components selected. Aborting."; return }

    Write-GUI " -> Engaging asynchronous OneDrive amputation engine (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        # Pre-kill all OneDrive and companion processes holding file/registry handles
        Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
            }

            $data = $item.ActionData
            try {
                if ($data.Type -eq "Core") {
                    $setupX64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
                    $setupX86 = "$env:SystemRoot\System32\OneDriveSetup.exe"

                    if (Test-Path -Path $setupX64) {
                        Start-Process -FilePath $setupX64 -ArgumentList "/uninstall" -NoNewWindow -Wait
                    } elseif (Test-Path -Path $setupX86) {
                        Start-Process -FilePath $setupX86 -ArgumentList "/uninstall" -NoNewWindow -Wait
                    }

                    Start-Sleep -Seconds 2
                    Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue

                    # Neutralize Run keys across HKCU, HKLM, and all loaded HKEY_USERS\<SID> hives while keeping SystemRoot stub for SFC/DISM
                    $runTargets = [System.Collections.Generic.List[string]]::new()
                    $runTargets.Add("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")
                    $runTargets.Add("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
                    $runTargets.Add("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")

                    foreach ($prof in (Get-UltixUserProfiles)) {
                        if ($prof.IsHiveLoaded) {
                            $sidRun = "$($prof.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run"
                            if (Test-Path -Path $sidRun) { $runTargets.Add($sidRun) }
                        }
                    }

                    foreach ($rPath in ($runTargets | Select-Object -Unique)) {
                        if (Test-Path -Path $rPath) {
                            Remove-ItemProperty -Path $rPath -Name "OneDriveSetup" -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -Path $rPath -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                        }
                    }

                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [+] Core installation payloads purged. Multi-profile Run hooks neutralized (SystemRoot stub preserved for SFC).")
                    }
                }
                elseif ($data.Type -eq "Registry") {
                    if (Test-Path -Path $data.Path) {
                        Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Registry key removed: $($data.Path)") }
                    }
                }
                elseif ($data.Type -eq "Folder") {
                    $targetDir = $data.Path
                    if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (Test-Path -LiteralPath $targetDir)) {
                        & takeown.exe /F "$targetDir" /R /A /D Y 2>$null | Out-Null
                        & icacls.exe "$targetDir" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null

                        # Evacuate memory-mapped shell extensions (e.g., FileSyncShell64.dll locked by explorer.exe)
                        $dllFiles = @(Get-ChildItem -LiteralPath $targetDir -Filter "*.dll" -Recurse -File -Force -ErrorAction SilentlyContinue)
                        foreach ($dll in $dllFiles) {
                            $dllPath = $dll.FullName
                            $dllName = $dll.Name
                            if ([string]::IsNullOrWhiteSpace($dllPath)) { continue }

                            try {
                                $dll.Attributes = 'Normal'
                                Remove-Item -LiteralPath $dllPath -Force -ErrorAction Stop
                            } catch {
                                $trashPath = Join-Path -Path $env:TEMP -ChildPath "WinUltix_Locked_${dllName}_$([guid]::NewGuid().ToString('N')).tmp"
                                Move-Item -LiteralPath $dllPath -Destination $trashPath -Force -ErrorAction SilentlyContinue
                            }
                        }

                        # Strip ReadOnly/Hidden/System attributes from remaining items and wipe directory
                        Get-ChildItem -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try { $_.Attributes = 'Normal' } catch {}
                        }
                        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue

                        # Final fallback: if directory still exists due to an open directory handle in Explorer, cycle explorer.exe
                        if (Test-Path -LiteralPath $targetDir) {
                            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [*] Releasing Shell Extension lock via Explorer refresh...") }
                            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 600
                            Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction Stop
                            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                                Start-Process "explorer.exe"
                            }
                        }
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Folder eradicated: $targetDir") }
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Error purging $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Selected OneDrive components eliminated.`n"
    }
}

function Invoke-RemoveCapabilities {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }

    Write-GUI " -> Removing selected Windows Capabilities (CBS Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Removing Capability: $($item.UIDisplayName)")
            }
            foreach ($cap in $item.ActionData) {
                try {
                    Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Removed FOD: $($cap.Name)") }
                } catch {
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Failed to remove $($cap.Name): $($_.Exception.Message)") }
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> System features (FOD) removal completed.`n"
    }
}

function Invoke-GarbageCollector {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> System clean or operation aborted."; return }

    Write-GUI " -> Running Appx Garbage Collector (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Cleaning: $($item.UIDisplayName)")
            }
            try {
                if ($item.ActionData.Type -eq "Framework") {
                    Remove-AppxPackage -Package $item.ActionData.Target -AllUsers -ErrorAction Stop
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Removed orphaned framework: $($item.ActionData.Target)") }
                } elseif ($item.ActionData.Type -eq "Provisioned") {
                    Remove-AppxProvisionedPackage -Online -PackageName $item.ActionData.Target -ErrorAction Stop | Out-Null
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Deprovisioned orphaned base: $($item.ActionData.Target)") }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Error removing $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Appx Garbage Collector finished its run.`n"
    }
}

function Invoke-RemoveBloatware {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }

    Write-GUI " -> Engaging Aggressive Bloatware & AI Removal (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        Stop-Process -Name "Widgets", "WidgetService", "StoreExperienceHost", "WinStore.App", "Copilot", "msteams", "olk", "aixhost" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
            }

            # Handle Windows Recall & AI Data Analysis (24H2/25H2/26H2)
            if ($item.ActionData.IsRecall -eq $true -or $item.UIDisplayName -match "(?i)Recall") {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [*] Enforcing DisableAIDataAnalysis & TurnOffSavingSnapshots GPO locks...")
                }
                $aiPolicies = @(
                    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI",
                    "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
                )
                foreach ($pol in $aiPolicies) {
                    if (-not (Test-Path -Path $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $pol -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $pol -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }

                if ($item.ActionData.RecallFeature -eq $true) {
                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [*] Stripping Windows Recall Optional Feature payload via CBS...")
                    }
                    try {
                        Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -Remove -NoRestart -ErrorAction Stop | Out-Null
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Windows Recall feature disabled and payload removed.") }
                    } catch {
                        try {
                            Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null
                            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Windows Recall feature disabled.") }
                        } catch {
                            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] CBS Recall feature modification skipped: $($_.Exception.Message)") }
                        }
                    }
                }
            }

            # Handle Copilot GPO constraints
            if ($item.UIDisplayName -match "(?i)Copilot") {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [*] Applying local policy constraints for Windows Copilot...")
                }
                $policies = @(
                    "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",
                    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                )
                foreach ($pol in $policies) {
                    if (-not (Test-Path -Path $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $pol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }

            # 1. Process Installed Packages (AllUsers + CurrentUser fallback)
            foreach ($pkg in $item.ActionData.Installed) {
                $pfn = $pkg.PackageFamilyName

                try {
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    } catch {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    }

                    # Register in Deprovisioned store to prevent Windows Update from reinstalling it
                    if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                        if (-not (Test-Path -Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Removed Appx: $($pkg.Name)") }
                } catch {
                    if ($pkg.Name -match "(?i)Copilot|Recall") {
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] API uninstallation blocked for $($pkg.Name). Relying on GPO lockdown.") }
                    } else {
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [-] Error removing $($pkg.Name): $($_.Exception.Message)") }
                    }
                }
            }

            # 2. Process Provisioned Packages (Only if still present after Remove-AppxPackage -AllUsers)
            $remainingProv = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
            foreach ($prov in $item.ActionData.Provisioned) {
                $stillProvisioned = $remainingProv | Where-Object { $_.PackageName -eq $prov.PackageName }
                if ($null -eq $stillProvisioned) { continue }

                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Deprovisioned base image: $($prov.DisplayName)") }
                } catch {
                    if ($_.Exception.Message -notmatch "(?i)nie można odnaleźć|cannot find|0x80070002|0x80070003") {
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [-] Error deprovisioning $($prov.DisplayName): $($_.Exception.Message)") }
                    }
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Aggressive Bloatware Removal completed.`n"
    }
}

function Invoke-RemoveCapabilityStubs {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No stubs selected. Operation aborted."; return }

    Write-GUI " -> Purging selected CBS Stubs (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging CBS Stub: $($item.UIDisplayName)")
            }
            try {
                Remove-WindowsPackage -Online -PackageName $item.ActionData -NoRestart -ErrorAction Stop | Out-Null
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Eradicated stub package: $($item.ActionData)") }
            } catch {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Error purging stub: $($_.Exception.Message)") }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> CBS capability stubs successfully eradicated.`n"
    }
}

# ------------------------------------------
# Z2: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z2UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Bloatware"
    $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. OneDrive
    $rowOneDrive = New-UltixActionRow -Parent $tabApps -Y 20 `
        -Text "Uninstall and Deprovision OneDrive" `
        -MainRGB @(60, 60, 100) `
        -Description "Completely uninstalls OneDrive, burns its keys across all loaded HKEY_USERS hives, and physically deletes folders across all user profiles." `
        -AuditDescription "AUDIT: Scans for active OneDrive installers, multi-profile HKEY_USERS startup keys, and residual folders." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ModalTitle "WinUltix - OneDrive" -ModalDescription "Select specific OneDrive traces to eradicate." -ExecutorFunction "Invoke-RemoveOneDrive" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 2. Capabilities (FOD)
    $rowCaps = New-UltixActionRow -Parent $tabApps -Y 70 `
        -Text "Remove System Features (FOD)" `
        -Description "Interactive removal of optional built-in Features on Demand (FOD) in a background CBS thread." `
        -AuditDescription "AUDIT: Verifies installed unnecessary Capabilities (FOD)." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ModalTitle "WinUltix - FOD Removal" -ModalDescription "Select features to remove." -ExecutorFunction "Invoke-RemoveCapabilities" -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 3. Aggressive Bloatware (Appx)
    $rowBloat = New-UltixActionRow -Parent $tabApps -Y 120 `
        -Text "Aggressive Bloatware Removal (Appx)" `
        -Description "Aggressive, interactive removal of 64 UWP bloatware targets and Windows Recall/AI telemetry from the system." `
        -AuditDescription "AUDIT: Scans the system for target Appx Bloatware, Recall payloads, and prints a detailed footprint report." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ModalTitle "WinUltix - Bloatware Removal" -ModalDescription "Select components to remove. Detected items are checked by default." -ExecutorFunction "Invoke-RemoveBloatware" -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 4. Appx Garbage Collector
    $rowGC = New-UltixActionRow -Parent $tabApps -Y 170 `
        -Text "Run Appx Garbage Collector" `
        -MainRGB @(100, 80, 40) `
        -Description "Resolves transitive Appx dependency graphs and removes orphaned frameworks in a background thread." `
        -AuditDescription "AUDIT: Scans and lists all orphaned frameworks and base packages that can be safely removed." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ModalTitle "WinUltix - Garbage Collector" -ModalDescription "Select orphaned packages to remove." -ExecutorFunction "Invoke-GarbageCollector" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 5. CBS Capability Stubs
    $rowStubs = New-UltixActionRow -Parent $tabApps -Y 220 `
        -Text "Purge Capability Stubs (CBS)" `
        -MainRGB @(100, 60, 100) `
        -Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." `
        -AuditDescription "AUDIT: Queries CBS registry/payload directly for active stubs." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ModalTitle "WinUltix - Stub Purge" -ModalDescription "Select stubs to rip from the CBS store." -ExecutorFunction "Invoke-RemoveCapabilityStubs" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    foreach ($row in @($rowOneDrive, $rowCaps, $rowBloat, $rowGC, $rowStubs)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabApps)
}
# <<< END INJECTED: Z2_Bloatware.ps1 <<<


# Z3_Registry: Main registry engine (Invoke-ApplyRegistry) featuring dedicated revert modals. Manages UI tweaks, telemetry blocks, gaming optimizations (VBS/HVCI, GameDVR), and implements Software Restriction Policies (SRP).
# >>> INJECTED: Z3_Registry.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z3_REGISTRY.PS1 - REGISTRY ENGINE MODULE (v3.0.0)
# Z3_Registry: Main registry engine (Invoke-ApplyRegistry). Modulates UI (classic taskbar, Start menu), disables telemetry and data collection, optimizes background services (Edge, Defender), applies gaming tweaks (MMCSS, MPO, Flip Model, disabling VBS/HVCI, GameDVR), enforces Dual-Layer SRP+IFEO execution locks, and disables mouse acceleration.
# ==========================================

# ------------------------------------------
# Z3: REGISTRY AUDIT ENGINE (HANDLE-CACHED)
# ------------------------------------------
function Invoke-RegistryAudit {
    param([array]$Rules)
    
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $keyCache = @{}

    try {
        foreach ($rule in $Rules) {
            $isDetected   = $true
            $currentValue = $null
            $valueExists  = $false
            $regPath      = $rule.Path

            if (-not $keyCache.ContainsKey($regPath)) {
                $keyCache[$regPath] = if (Test-Path -LiteralPath $regPath) {
                    Get-Item -LiteralPath $regPath -ErrorAction SilentlyContinue
                } else {
                    $null
                }
            }

            $regKey = $keyCache[$regPath]
            if ($null -ne $regKey) {
                $lookupName = if ($rule.Name -eq "" -or $rule.Name -eq "(Default)") { "" } else { $rule.Name }
                $rawVal = $regKey.GetValue($lookupName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                
                # Distinguishes (value not set) [$null] from an initialized empty string [""]
                if ($null -ne $rawVal) {
                    # Convert negative signed Int32 REG_DWORD reads (e.g. -1 for 0xFFFFFFFF) to unsigned UInt32
                    if ($rule.Type -eq "DWord" -and $rawVal -is [int] -and $rawVal -lt 0) {
                        $currentValue = [BitConverter]::ToUInt32([BitConverter]::GetBytes($rawVal), 0)
                    } else {
                        $currentValue = $rawVal
                    }
                    $valueExists = $true
                }
            }
            
            if ($rule.ContainsKey("ValidValues")) {
                if ($valueExists -and ($rule.ValidValues -contains $currentValue)) { 
                    $isDetected = $false 
                }
            } elseif ($rule.ContainsKey("MatchRegex")) {
                if ($valueExists -and ([string]$currentValue -match $rule.MatchRegex)) {
                    $isDetected = $false
                }
            } else {
                if ($valueExists -and ([string]$currentValue -eq [string]$rule.Expected)) { 
                    $isDetected = $false 
                }
            }

            # Fallback check for UCPD-protected keys (e.g., DisableWidgetsBoard on Win11 25H2/26H2)
            if ($isDetected -and $rule.ContainsKey("AltName") -and $null -ne $regKey) {
                $altRaw = $regKey.GetValue($rule.AltName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($null -ne $altRaw -and ([string]$altRaw -eq [string]$rule.AltExpected)) {
                    $isDetected = $false
                }
            }

            $results.Add([PSCustomObject]@{
                UIDisplayName = $rule.UIDisplayName
                IsDetected    = $isDetected
                ActionData    = $rule
            })
        }
    } finally {
        foreach ($k in $keyCache.Values) {
            if ($null -ne $k -and $k -is [System.IDisposable]) { $k.Dispose() }
        }
    }

    return @($results)
}

# ------------------------------------------
# Z3: REGISTRY AUDITS
# ------------------------------------------
function Get-RegState_Taskbar {
    $rules = @(
        @{ UIDisplayName = "Taskbar: Align to Left (Disables Windows 11 center alignment)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Show Seconds in Clock"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowSecondsInSystemClock"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Search Box (Saves space)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Expected = 0; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Disable Dynamic Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Taskbar: Hide Task View Button"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideTaskViewButton"; Expected = 1; Default = 0; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Taskbar: Hide Teams Chat Icon"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Name = "ChatIcon"; Expected = 3; Default = 1; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Taskbar: Enable 'End Task' on right-click (Dev feature)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Enforce Classic Layout"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_Layout"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Web Search (Forces local-only, faster search)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Expected = 1; Default = 0; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Start Menu: Hide Recommended Section"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Expected = 1; Default = 0; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Start Menu: Disable Recent Docs History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "NoRecentDocsHistory"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Search Highlights (Bing bloat)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableSearchBoxSearchHighlights"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Start Menu: Disable Tailored Search Suggestions"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowTailoredSearch"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Widgets: Disable News & Interests (Saves RAM/Network)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Expected = 0; Default = 1; AltName = "DisableWidgetsBoard"; AltExpected = 1; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Bloat: Disable Consumer Features (Stops auto-installing apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Toast Notifications (Flyouts)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "ToastEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Focus Assist (Global)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"; Name = "NOC_GLOBAL_SETTING_TOASTS_ENABLED"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable App Push Notifications (Policy)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoCloudApplicationNotification"; Expected = 1; Default = "DELETE_VALUE"; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable App Toast Notifications (Policy)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoToastApplicationNotification"; Expected = 1; Default = "DELETE_VALUE"; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Bing Web Results (Keeps local queries private)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Expected = 1; Default = 0; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Search: Disable Connected Cloud Search Services"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Search: Disable Location Tracking in Search"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchToUseLocation"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Force Local-Only UI (Disable Bing Search UI)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Search: Disable Search Highlights (Dynamic Web Content)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableDynamicContentInWSB"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Explorer {
    $rules = @(
        @{ UIDisplayName = "Explorer: Open to 'This PC' instead of Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "LaunchTo"; Expected = 1; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show hidden files and folders"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"; Expected = 1; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show known file extensions (Security)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Run folder windows in a separate process (Stability)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "SeparateProcess"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Expand navigation pane to current folder"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "NavPaneExpandToCurrentFolder"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Hide Cloud Files in Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name = "ShowCloudFilesInQuickAccess"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Context Menu: Restore Classic Win10 Style"; Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name = ""; Expected = ""; Default = "DELETE_KEY"; Type = "String" }
        @{ UIDisplayName = "Desktop: Show 'This PC' Icon on Desktop"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Desktop: Show 'This PC' Icon (Classic Start)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (64-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (32-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Reduce Menu Show Delay from 400ms to 50ms"; Path = "HKCU:\Control Panel\Desktop"; Name = "MenuShowDelay"; Expected = "50"; Default = "400"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Annoyances {
    $rules = @(
        @{ UIDisplayName = "Power: Disable Modern Standby S0 (Force Hardware S3 Sleep)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"; Name = "PlatformAoAcOverride"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable AutoPlay for all drives"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Expected = 255; Default = 91; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Autoplay Handlers"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"; Name = "DisableAutoplay"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Accessibility: Disable Sticky Keys prompt (Shift x5)"; Path = "HKCU:\Control Panel\Accessibility\StickyKeys"; Name = "Flags"; Expected = "506"; Default = "510"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Filter Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"; Name = "Flags"; Expected = "122"; Default = "126"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Toggle Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\ToggleKeys"; Name = "Flags"; Expected = "58"; Default = "62"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Privacy {
    $rules = @()
    $rules += @{ UIDisplayName = "Privacy: Suppress UX Experience Reporting (Telemetry)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\ExperienceReporting"; Name = "SuppressExperienceReporting"; Expected = 1; Default = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Block OS Telemetry & Data Collection"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Expected = 0; Default = 3; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable App Advertising ID"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Timeline & Activity History tracking"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Tailored Experiences"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Cloud Speech Recognition"; Path = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Name = "HasAccepted"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Restrict Implicit Ink/Text Collection"; Path = "HKCU:\Software\Microsoft\InputPersonalization"; Name = "RestrictImplicitInkCollection"; Expected = 1; Default = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Background Apps: Block UWP apps from running globally"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Expected = 1; Default = 0; Type = "DWord" }
    
    $uwpBlocks = @("LetAppsRunInBackground", "LetAppsAccessSync", "LetAppsAccessIdentity", "LetAppsAccessBluetooth", "LetAppsActivateWithVoice", "LetAppsAccessNotifications", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessRadios", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar", "LetAppsAccessAccountInfo")
    foreach ($app in $uwpBlocks) { $rules += @{ UIDisplayName = "UWP Permissions: Block $app"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $app; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" } }
    
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessCamera"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessCamera"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" }
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessMicrophone"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessMicrophone"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" }
    
    $rules += @{ UIDisplayName = "Edge: Disable Startup Boost (Background Process)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Edge: Disable Background Mode"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Defender: Prevent automatic sample submission"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"; Name = "SubmitSamplesConsent"; Expected = 2; Default = 1; Type = "DWord" }
    
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $rules += @{ UIDisplayName = "Junk Blocker: Disable Content Delivery ($k)"; Path = $cdm; Name = $k; Expected = 0; Default = 1; Type = "DWord" } }
    
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_SystemBoot {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -Property TotalPhysicalMemory -ErrorAction SilentlyContinue
    $ramKB = if ($null -ne $cs -and $cs.TotalPhysicalMemory -gt 0) {
        [int][math]::Min([int]::MaxValue, [math]::Round($cs.TotalPhysicalMemory / 1KB))
    } else {
        16777216
    }

    $rules = @(
        @{ UIDisplayName = "Boot: Disable Fast Startup (Prevents kernel hibernation bugs)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Boot: Disable Explorer Startup Delay (Instant Desktop Load)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name = "StartupDelayInMSec"; Expected = 0; Default = "DELETE_KEY"; Type = "DWord" }
        @{ UIDisplayName = "Kernel: Consolidate SvcHost Processes (Dynamic RAM Threshold)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control"; Name = "SvcHostSplitThresholdInKB"; Expected = $ramKB; Default = 3670016; ValidValues = @($ramKB, ($ramKB + 1048576)); Type = "DWord" }
        @{ UIDisplayName = "Security: Block BIOS/UEFI Software Injections (WPBT)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Name = "DisableWpbtExecution"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive File Sync Integration"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "DisableFileSyncNGSC"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive Network Traffic Pre-Sign-In"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "PreventNetworkTrafficPreUserSignIn"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Remote Desktop (RDP) access"; Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = "fDenyTSConnections"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Disable Insider Preview Builds"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds"; Name = "AllowBuildPreview"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Boot: Enable Verbose Status Messages"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "verbosestatus"; Expected = 1; Default = 0; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Mouse {
    $rules = @(
        @{ UIDisplayName = "Mouse: Disable 'Enhance pointer precision' (Raw Input)"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseSpeed"; Expected = "0"; Default = "1"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 1"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold1"; Expected = "0"; Default = "6"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 2"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold2"; Expected = "0"; Default = "10"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Gaming {
    $rules = @(
        @{ UIDisplayName = "Gaming: Disable Xbox GameDVR (Reduces stuttering)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Store Config"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Frame Rate Cap (VSync bypass)"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_CapFrameRate"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Optimize FullScreen Exclusive Behavior"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehavior"; Expected = 2; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Enable Hardware Accelerated GPU Scheduling (HAGS)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; Expected = 2; Default = 1; ValidValues = @(2); Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable Multiplane Overlay (MPO - Fixes VRR/Flicker)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayTestMode"; Expected = 5; Default = "DELETE_VALUE"; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Enable Windowed Game Optimizations (Flip Model)"; Path = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"; Name = "DirectXUserGlobalSettings"; Expected = "SwapEffectUpgradeEnable=1;"; Default = "DELETE_VALUE"; MatchRegex = "SwapEffectUpgradeEnable=1"; Type = "String" }
        @{ UIDisplayName = "Kernel: Disable Paging Executive (Keeps core system in RAM)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS: System Responsiveness (Allocate 100% CPU to Games)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "SystemResponsiveness"; Expected = 0; Default = 20; Type = "DWord" }
        @{ UIDisplayName = "Network: Remove MMCSS Network Throttling Index"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; Expected = 4294967295; Default = 10; ValidValues = @(4294967295, -1); Type = "DWord" }
        @{ UIDisplayName = "CPU: Optimize Priority Separation (Focus CPU on foreground)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; Expected = 40; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Power: Disable Windows Power Throttling globally"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: GPU Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Expected = 8; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Expected = 6; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Scheduling Category (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Expected = "High"; Default = "Medium"; Type = "String" }
        @{ UIDisplayName = "Security: Disable Virtualization Based Security (VBS)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Hypervisor-protected Code Integrity (HVCI)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

# ------------------------------------------
# Z3: SRP & IFEO (DUAL-LAYER EXECUTION LOCKS)
# ------------------------------------------
function Get-DeterministicSrpGuid {
    param([Parameter(Mandatory=$true)][string]$InputString)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InputString.ToLowerInvariant()))
    $md5.Dispose()
    return "{" + ([guid]::new($hashBytes)).ToString().ToUpper() + "}"
}

function Get-RegState_SRP {
    $targets = @(
        @{ UIDisplayName = "SRP+IFEO Lock: Windows Widgets (Widgets.exe)"; TargetPath = "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.WebExperience*\Dashboard\Widgets.exe"; ExeName = "Widgets.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: Compatibility Telemetry (CompatTelRunner.exe)"; TargetPath = "$env:windir\System32\CompatTelRunner.exe"; ExeName = "CompatTelRunner.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: Hardware Telemetry (DeviceCensus.exe)"; TargetPath = "$env:windir\System32\DeviceCensus.exe"; ExeName = "DeviceCensus.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: GameBar Telemetry (GameBarPresenceWriter.exe)"; TargetPath = "$env:windir\System32\GameBarPresenceWriter.exe"; ExeName = "GameBarPresenceWriter.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: Edge Background Updater (MicrosoftEdgeUpdate.exe)"; TargetPath = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"; ExeName = "MicrosoftEdgeUpdate.exe"; IsCustom = $false }
    )
    
    $customKey = "HKLM:\SOFTWARE\WinUltix\SRP"
    if (Test-Path -LiteralPath $customKey) {
        $customEntries = Get-Item -LiteralPath $customKey -ErrorAction SilentlyContinue
        if ($customEntries) {
            foreach ($prop in $customEntries.Property) {
                $customPath = $customEntries.GetValue($prop, $null)
                if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                    $exeLeaf = [System.IO.Path]::GetFileName($customPath)
                    $targets += @{ UIDisplayName = "SRP+IFEO Lock (Custom): $prop"; TargetPath = $customPath; ExeName = $exeLeaf; IsCustom = $true }
                }
            }
            $customEntries.Dispose()
        }
    }

    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    $srpBase  = "$srpRoot\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    
    $srpRootProps = Get-ItemProperty -LiteralPath $srpRoot -Name "DefaultLevel", "TransparentEnabled" -ErrorAction SilentlyContinue
    $saferMasterActive = ($null -ne $srpRootProps -and $srpRootProps.DefaultLevel -eq 262144 -and $srpRootProps.TransparentEnabled -eq 1)

    foreach ($target in $targets) {
        $guid = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $ruleKey = "$srpBase\$guid"
        
        $srpRuleProps = Get-ItemProperty -LiteralPath $ruleKey -Name "SaferFlags", "ItemData" -ErrorAction SilentlyContinue
        $srpLocked = ($saferMasterActive -and $null -ne $srpRuleProps -and $srpRuleProps.SaferFlags -eq 0)

        $ifeoKey = "$ifeoBase\$($target.ExeName)"
        $ifeoLocked = $false

        if (Test-Path -LiteralPath $ifeoKey) {
            $ifeoProps = Get-ItemProperty -LiteralPath $ifeoKey -Name "Debugger", "UseFilter" -ErrorAction SilentlyContinue
            if ($target.IsCustom -and $target.TargetPath -notmatch '[\*\?]') {
                $filterSubKey = "$ifeoKey\$guid"
                $subProps = Get-ItemProperty -LiteralPath $filterSubKey -Name "Debugger", "FilterFullPath" -ErrorAction SilentlyContinue
                $ifeoLocked = (
                    ($null -ne $ifeoProps -and $ifeoProps.UseFilter -eq 1 -and $null -ne $subProps -and $subProps.Debugger -match "systray\.exe" -and $subProps.FilterFullPath -eq $target.TargetPath) -or
                    ($null -ne $ifeoProps -and $ifeoProps.Debugger -match "systray\.exe")
                )
            } else {
                $ifeoLocked = ($null -ne $ifeoProps -and $ifeoProps.Debugger -match "systray\.exe")
            }
        }

        $isDetected = -not ($srpLocked -and $ifeoLocked)
        
        $results.Add([PSCustomObject]@{
            UIDisplayName = $target.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $target
        })
    }
    return @($results)
}

function Invoke-ApplySRP {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No execution locks selected."; return }
    $current = 0

    $srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    $srpPaths = "$srpRoot\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $nullStub = "$env:SystemRoot\System32\systray.exe"
    
    if ($Operation -eq 'Apply') {
        if (-not (Test-Path -LiteralPath $srpRoot)) { New-Item -Path $srpRoot -Force | Out-Null }
        
        $srpSettings = @{
            "AuthenticodeEnabled" = 0
            "DefaultLevel"        = 262144
            "TransparentEnabled"  = 1
            "PolicyScope"         = 0
        }
        foreach ($kvp in $srpSettings.GetEnumerator()) {
            Set-ItemProperty -LiteralPath $srpRoot -Name $kvp.Key -Value $kvp.Value -Type DWord -Force
        }
        
        $exeTypes = [string[]]@("BAT","CMD","COM","EXE","HTA","LNK","MSI","OCX","PIF","REG","SCR","VBS","WSF")
        Set-ItemProperty -LiteralPath $srpRoot -Name "ExecutableTypes" -Value $exeTypes -Type MultiString -Force
        
        if (-not (Test-Path -LiteralPath "$srpRoot\0"))      { New-Item -Path "$srpRoot\0" -Force | Out-Null }
        if (-not (Test-Path -LiteralPath "$srpRoot\262144")) { New-Item -Path "$srpRoot\262144" -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $srpPaths))         { New-Item -Path $srpPaths -Force | Out-Null }
    }

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Removing" }
    $policyChanged = $false

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 75)) }
        Write-GUI " -> $($actionVerb) Execution Lock: $($item.UIDisplayName)"
        
        $target       = $item.ActionData
        $guid         = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $ruleKey      = "$srpPaths\$guid"
        $ifeoKey      = "$ifeoBase\$($target.ExeName)"
        $filterSubKey = "$ifeoKey\$guid"
        
        try {
            if ($Operation -eq 'Apply') {
                if (Test-Path -LiteralPath $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)) {
                        $existingData = (Get-ItemProperty -LiteralPath $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($existingData -eq $target.TargetPath -and $subKey.PSChildName -ne $guid) {
                            Remove-Item -LiteralPath $subKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                New-Item -Path $ruleKey -Force | Out-Null
                Set-ItemProperty -LiteralPath $ruleKey -Name "Description" -Value "WinUltix SRP Lockdown" -Type String -Force
                Set-ItemProperty -LiteralPath $ruleKey -Name "ItemData" -Value $target.TargetPath -Type String -Force
                Set-ItemProperty -LiteralPath $ruleKey -Name "SaferFlags" -Value 0 -Type DWord -Force

                if (-not (Test-Path -LiteralPath $ifeoKey)) { New-Item -Path $ifeoKey -Force | Out-Null }

                if ($target.IsCustom -and $target.TargetPath -notmatch '[\*\?]') {
                    # Scoped kernel filter (FilterFullPath) so custom .exe blocks do not collide with other apps sharing the same filename
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Value 1 -Type DWord -Force
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                    if (-not (Test-Path -LiteralPath $filterSubKey)) { New-Item -Path $filterSubKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $filterSubKey -Name "FilterFullPath" -Value $target.TargetPath -Type String -Force
                    Set-ItemProperty -LiteralPath $filterSubKey -Name "Debugger" -Value $nullStub -Type String -Force
                    Set-ItemProperty -LiteralPath $filterSubKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                } else {
                    # Global kernel image lock (intercepts wildcard paths such as WindowsApps\...\Widgets.exe across updates)
                    Remove-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -Value $nullStub -Type String -Force
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                }
                
                $procName = [System.IO.Path]::GetFileNameWithoutExtension($target.ExeName)
                $activeProc = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($activeProc) { 
                    $activeProc | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-GUI "    [OK] Flushed active process ($procName) from memory."
                }
                $policyChanged = $true
            } else {
                if (Test-Path -LiteralPath $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)) {
                        $itemData = (Get-ItemProperty -LiteralPath $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($subKey.PSChildName -eq $guid -or $itemData -eq $target.TargetPath) {
                            Remove-Item -LiteralPath $subKey.PSPath -Force -Recurse -ErrorAction Stop
                            $policyChanged = $true
                        }
                    }
                }

                if (Test-Path -LiteralPath $ifeoKey) {
                    if (Test-Path -LiteralPath $filterSubKey) {
                        Remove-Item -LiteralPath $filterSubKey -Recurse -Force -ErrorAction SilentlyContinue
                        $policyChanged = $true
                    }

                    $isManaged = (Get-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -ErrorAction SilentlyContinue).WinUltixManaged
                    $dbgVal    = (Get-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
                    if ($isManaged -eq 1 -or $dbgVal -match "systray\.exe") {
                        if (-not $target.IsCustom -or $dbgVal -match "systray\.exe") {
                            Remove-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -Force -ErrorAction SilentlyContinue
                        }
                        $remainingSubKeys = @(Get-ChildItem -LiteralPath $ifeoKey -ErrorAction SilentlyContinue)
                        if ($remainingSubKeys.Count -eq 0) {
                            Remove-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Force -ErrorAction SilentlyContinue
                        }
                        $remainingProps = (Get-Item -LiteralPath $ifeoKey -ErrorAction SilentlyContinue).Property
                        if ($remainingSubKeys.Count -eq 0 -and (-not $remainingProps -or $remainingProps.Count -eq 0)) {
                            Remove-Item -LiteralPath $ifeoKey -Force -ErrorAction SilentlyContinue
                        }
                        $policyChanged = $true
                    }
                }
                Write-GUI "    [OK] SRP & IFEO restriction rules purged from registry."
            }
        } catch { Write-GUI "    [!] Failed to modify execution lock: $($_.Exception.Message)" }
    }

    if ($Operation -eq 'Revert' -and (Test-Path -LiteralPath $srpPaths)) {
        $remainingSrp = @(Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)
        if ($remainingSrp.Count -eq 0) {
            Remove-Item -LiteralPath $srpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if ($policyChanged) {
        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
            $UltixSync.Logs.Enqueue(" -> Refreshing Safer API policy tokens (gpupdate.exe /force in background)...")
            $UltixSync.Progress = 85

            $gpProc = Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -WindowStyle Hidden -PassThru
            $gpProc.WaitForExit()
            $exitCode = $gpProc.ExitCode
            $gpProc.Dispose()

            $UltixSync.Progress = 100
            return $exitCode
        } -OnComplete {
            param($exitCode)
            Update-Progress 0
            Write-GUI "    [OK] Kernel IFEO and AuthZ policy tokens updated (ExitCode: $exitCode).`n"
        }
    } else {
        Update-Progress 0
        Write-GUI " -> Execution lock operation completed ($Operation).`n"
    }
}

# ------------------------------------------
# Z3: REGISTRY ENGINE
# ------------------------------------------
function Invoke-ApplyRegistry {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply'
    )
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No tweaks selected."; return }
    $current = 0

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Reverting" }

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        $reg = $item.ActionData
        
        $targetValue = if ($Operation -eq 'Apply') { $reg.Expected } else { $reg.Default }

        if ($null -eq $targetValue -and $Operation -eq 'Revert') {
            Write-GUI "    [!] Missing 'Default' property in array definition. Skipping."
            continue
        }

        try {
            if ($targetValue -eq 'DELETE_KEY') {
                if (Test-Path -LiteralPath $reg.Path) { 
                    Remove-Item -LiteralPath $reg.Path -Recurse -Force -ErrorAction Stop | Out-Null 
                    $parentKey = Split-Path -Path $reg.Path -Parent
                    if ($parentKey -match "\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2\}$" -and (Test-Path -LiteralPath $parentKey)) {
                        Remove-Item -LiteralPath $parentKey -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                continue
            }

            if ($targetValue -eq 'DELETE_VALUE') {
                if (Test-Path -LiteralPath $reg.Path) {
                    if ($reg.Name -eq "DirectXUserGlobalSettings") {
                        $existingDx = (Get-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue).$($reg.Name)
                        $cleanedDx  = ($existingDx -replace "SwapEffectUpgradeEnable=\d+;?", "").Trim()
                        if ([string]::IsNullOrWhiteSpace($cleanedDx)) {
                            Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Force -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $cleanedDx -Type String -Force -ErrorAction Stop | Out-Null
                        }
                    } else {
                        Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Force -ErrorAction Stop | Out-Null
                    }
                }
                continue
            }

            if (-not (Test-Path -LiteralPath $reg.Path)) { New-Item -Path $reg.Path -Force -ErrorAction Stop | Out-Null }

            # Sync 25H2/26H2 DisableWidgetsBoard policy alongside AllowNewsAndInterests
            if ($reg.ContainsKey("AltName")) {
                if ($Operation -eq 'Apply') {
                    Set-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Value $reg.AltExpected -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                    Set-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Force -ErrorAction SilentlyContinue | Out-Null
                    Remove-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            
            if ($reg.Name -eq "" -or $reg.Name -eq "(Default)") {
                # Explicitly write empty or target string into unnamed (Default) value
                Set-Item -LiteralPath $reg.Path -Value ([string]$targetValue) -Force -ErrorAction Stop | Out-Null
            } elseif ($reg.Name -eq "DirectXUserGlobalSettings" -and $Operation -eq 'Apply') {
                $existingDx = (Get-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue).$($reg.Name)
                if ([string]::IsNullOrWhiteSpace($existingDx)) {
                    $newDx = "SwapEffectUpgradeEnable=1;"
                } elseif ($existingDx -match "SwapEffectUpgradeEnable=\d+") {
                    $newDx = $existingDx -replace "SwapEffectUpgradeEnable=\d+", "SwapEffectUpgradeEnable=1"
                } else {
                    $sep   = if ($existingDx.EndsWith(";")) { "" } else { ";" }
                    $newDx = "$existingDx${sep}SwapEffectUpgradeEnable=1;"
                }
                Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $newDx -Type String -Force -ErrorAction Stop | Out-Null
            } else { 
                Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $targetValue -Type $reg.Type -Force -ErrorAction Stop | Out-Null 
            }
        } catch {
            # Handle Windows 11 24H2/25H2/26H2 UCPD.sys kernel filter blocking AllowNewsAndInterests
            if ($reg.ContainsKey("AltName")) {
                try {
                    if ($Operation -eq 'Apply') {
                        Set-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Value $reg.AltExpected -Type DWord -Force -ErrorAction Stop | Out-Null
                        Set-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\UCPD") {
                            Set-ProtectedServiceStart -ServiceName "UCPD" -StartValue 4
                            Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "UCPD velocity" -ErrorAction SilentlyContinue | Out-Null
                        }
                        Write-GUI "    [+] Bypassed UCPD.sys filter via $($reg.AltName)=1 & disarmed UCPD driver."
                    } else {
                        Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Force -ErrorAction SilentlyContinue | Out-Null
                        Remove-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Force -ErrorAction SilentlyContinue | Out-Null
                        Write-GUI "    [+] Reverted $($reg.AltName) policy."
                    }
                } catch {
                    Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)"
                }
            } else {
                Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)"
            }
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $CategoryName registry modifications completed ($Operation)."
}

# ------------------------------------------
# Z3: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z3UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabReg = New-Object System.Windows.Forms.TabPage
    $tabReg.Text = "Registry"
    $tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $invokeRegCategory = {
        param(
            [string]$ScannerFn,
            [string]$CategoryName,
            [string]$ModalTitle,
            [string]$AuditHeader,
            [switch]$RefreshShell,
            [switch]$AuditOnly
        )
        $auditData = & $ScannerFn
        if ($AuditOnly) {
            Write-GUI "--- AUDIT: $AuditHeader ---"
            $detected = @($auditData | Where-Object { $_.IsDetected })
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" }
            } else {
                Write-GUI "  [OK] Optimized."
            }
            Write-GUI ""
            return
        }

        $modalOutput = Show-ActionModal -Title $ModalTitle -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) {
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName $CategoryName -Operation $modalOutput.Action
            if ($RefreshShell) {
                Update-ShellEnvironment -ModifiedItems $modalOutput.Items
            }
            Write-GUI ""
        }
    }.GetNewClosure()

    # 1. Taskbar & Start Menu
    [void](New-UltixActionRow -Parent $tabReg -Y 20 `
        -Text "Taskbar and Start Menu" `
        -Description "Aligns the taskbar to the left, kills Bing assistants, and hides widgets." `
        -AuditDescription "AUDIT: Verifies taskbar alignment policy, Start Menu layouts, and Bing locks." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -RefreshShell }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -AuditOnly }.GetNewClosure()))

    # 2. File Explorer
    [void](New-UltixActionRow -Parent $tabReg -Y 70 `
        -Text "File Explorer and Context Menu" `
        -Description "Restores the full context menu, launches folder processes in isolation." `
        -AuditDescription "AUDIT: Verifies the presence of classic context menu and Explorer performance flags." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -RefreshShell }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -AuditOnly }.GetNewClosure()))

    # 3. OS Annoyances
    [void](New-UltixActionRow -Parent $tabReg -Y 120 `
        -Text "OS Annoyances (AutoRun / Sticky Keys)" `
        -Description "Deactivates AutoPlay and Accessibility shortcuts (Sticky Keys)." `
        -AuditDescription "AUDIT: Verifies AutoPlay and Sticky Keys blockade." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" -AuditOnly }.GetNewClosure()))

    # 4. Privacy
    [void](New-UltixActionRow -Parent $tabReg -Y 170 `
        -Text "Privacy and Background Apps (AppPrivacy)" `
        -Description "Blocks telemetry, background UWP apps execution, and limits Edge processes." `
        -AuditDescription "AUDIT: Checks the registry for telemetry, Edge, and background execution blocks." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy Policies" "Privacy Policies" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy Policies" "Privacy Policies" -AuditOnly }.GetNewClosure()))

    # 5. Boot & Security
    [void](New-UltixActionRow -Parent $tabReg -Y 220 `
        -Text "Boot and WPBT (BIOS/UEFI Block)" `
        -Description "Disables Fast Boot, OneDrive, RDP, and blocks software injections from BIOS/UEFI (WPBT)." `
        -AuditDescription "AUDIT: Verifies kernel hibernation logic (Fast Boot), WPBT, and RDP." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Security" "Boot & Security" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Security" "Boot & Security" -AuditOnly }.GetNewClosure()))

    # 6. Mouse
    [void](New-UltixActionRow -Parent $tabReg -Y 270 `
        -Text "Hard Mouse Acceleration Disable (Raw Input)" `
        -MainRGB @(60, 100, 150) -AuditRGB @(60, 100, 150) `
        -Description "Pure 1:1 input. Hard-disables 'Enhance pointer precision' to eliminate system smoothing." `
        -AuditDescription "AUDIT: Scans registry keys for system pointer acceleration." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" -AuditOnly }.GetNewClosure()))

    # 7. Gaming
    [void](New-UltixActionRow -Parent $tabReg -Y 320 `
        -Text "Hardware and Gaming (Extreme)" `
        -MainRGB @(150, 60, 60) -AuditRGB @(150, 60, 60) `
        -Description "Enforces MMCSS priorities, disables GameDVR, enabling maximum hardware performance." `
        -AuditDescription "AUDIT: Verifies MMCSS limits, CPU priority, and HAGS acceleration." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" -AuditOnly }.GetNewClosure()))

    # 8. SRP Execution Locks (Main + [+], [-], [?])
    $btnRegSRP = New-UltixButton -Parent $tabReg -X 15 -Y 420 -Width 240 -Height 40 -RGB @(60, 60, 60) `
        -Text "Execution Blocks (SRP/Legacy Pro)" `
        -Description "NATIVE KERNEL LOCK (Pro/Enterprise Only): Generates legacy Software Restriction Policies to block execution. May not work on Home editions or future OS builds."

    $btnAddSRP = New-UltixButton -Parent $tabReg -X 260 -Y 420 -Width 40 -Height 40 -RGB @(60, 100, 60) `
        -Text "+" `
        -Description "ADD CUSTOM TARGET: Browse for an .exe file to add to your custom SRP block list." `
        -OnClick {
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = "Executables (*.exe)|*.exe"
            $dlg.Title = "Select Executable to Block (SRP)"
            $dlg.InitialDirectory = "$env:ProgramFiles"
            try {
                if ($dlg.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
                    $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
                    if (-not (Test-Path -LiteralPath $regKey)) { New-Item -Path $regKey -Force | Out-Null }
                    $exeName = [System.IO.Path]::GetFileName($dlg.FileName)
                    Set-ItemProperty -LiteralPath $regKey -Name $exeName -Value $dlg.FileName -Type String -Force
                    Write-GUI " -> Added custom SRP target: $exeName"
                }
            } finally {
                $dlg.Dispose()
            }
        }

    $btnClrSRP = New-UltixButton -Parent $tabReg -X 305 -Y 420 -Width 40 -Height 40 -RGB @(100, 60, 60) `
        -Text "-" `
        -Description "CLEAR CUSTOM TARGETS: Removes all custom executables from the WinUltix tracking list (does not unlock them if currently applied)." `
        -OnClick {
            $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
            if (Test-Path -LiteralPath $regKey) {
                Remove-Item -LiteralPath $regKey -Force -Recurse | Out-Null
                Write-GUI " -> Custom SRP tracking database purged."
            } else {
                Write-GUI " -> Custom SRP roster is already empty."
            }
        }

    $btnAudSRP = New-UltixButton -Parent $tabReg -X 350 -Y 420 -Width 40 -Height 40 -RGB @(80, 80, 80) `
        -Text "?" `
        -Description "AUDIT: Verifies active Software Restriction Policies." `
        -OnClick {
            Write-GUI "--- AUDIT: Software Restriction Policies ---"
            $state = Get-RegState_SRP
            $detected = @($state | Where-Object { $_.IsDetected })
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] To Block: $($d.UIDisplayName)" }
            } else {
                Write-GUI "  [OK] Optimized."
            }
            Write-GUI ""
        }

    $btnRegSRP.Add_Click({
        $auditData = Get-RegState_SRP
        $modalOutput = Show-ActionModal -Title "WinUltix - SRP & IFEO Lockdown" -Description "Select executables to permanently block via OS policies (Apply = Lock, Revert = Unlock)." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) {
            Invoke-ApplySRP -SelectedItems $modalOutput.Items -Operation $modalOutput.Action -ControlsToDisable @($btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP)
        }
    }.GetNewClosure())

    $TabControl.Controls.Add($tabReg)
}
# <<< END INJECTED: Z3_Registry.ps1 <<<


# Z4_Services: Service state management and Task Scheduler control via centralized revert modals. Disables telemetry tasks, configures TCPNoDelay, and enforces strict service operational profiles with improved UI interactivity.
# >>> INJECTED: Z4_Services.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z4_SERVICES.PS1 - SERVICES & SYSTEM MODULE (v3.0.0)
# Z4_Services: Manages services (Set-ProtectedServiceStart with TrustedInstaller DACL escalation), Task Scheduler lockdown, locale-independent Power Plan audits, deterministic Start Menu native compilation (COM AppActivator), Ghost Service sweeping, and Light/Heavy service profiles.
# ==========================================

# ------------------------------------------
# Z4: AUDIT HELPERS
# ------------------------------------------

function Invoke-ServicesAudit {
    param([array]$Rules)
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $Rules.Count
    $current = 0

    foreach ($rule in $Rules) {
        $current++
        if ($null -ne $UltixSync -and $total -gt 0) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }

        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        
        $isDetected = $true
        if ($null -eq $currentStart -or $currentStart -eq $rule.ExpectedStart) {
            $isDetected = $false
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

# ------------------------------------------
# Z4: SERVICES & TASKS AUDITS (RUNSPACE-SAFE WORKERS)
# ------------------------------------------
function Get-TelemetryTasksState { 
    if ($null -ne $UltixSync) { $UltixSync.Progress = 15 }

    $rules = @(
        @{ UIDisplayName = "Task: CEIP (Customer Experience Improvement Program)"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Feedback & Diagnostics"; TaskPath = "\Microsoft\Windows\Feedback\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Performance Trace"; TaskPath = "\Microsoft\Windows\PerformanceTrace\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Error Reporting (WER)"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Xbox Live Game Save DataSync"; TaskPath = "\Microsoft\XblGameSave\*"; ExpectedState = "Disabled" }
    )
    
    # Single COM/CIM query instead of querying Get-ScheduledTask 5 times in a loop
    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    if ($null -ne $UltixSync) { $UltixSync.Progress = 70 }
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($rule in $rules) {
        $activeTasks = @($allTasks | Where-Object { $_.TaskPath -like $rule.TaskPath -and ($_.State -eq 'Ready' -or $_.State -eq 'Running') })
        
        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = ($activeTasks.Count -gt 0)
            ActionData    = $rule
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($results)
}

function Invoke-StartMenuAudit {
    Write-GUI "--- AUDIT: Start Menu Pins Database ---"
    $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($null -eq $pkgDir) {
        Write-GUI "  [OK] StartMenuExperienceHost package not found in current user profile."
        return
    }

    $localState = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
    $binFile    = Get-Item -Path (Join-Path $localState "start2.bin") -Force -ErrorAction SilentlyContinue
    $clearedSz  = (Get-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -ErrorAction SilentlyContinue).StartMenuClearedSize

    if ($null -ne $binFile) {
        $szKB = [math]::Round($binFile.Length / 1KB, 2)
        if ($null -ne $clearedSz -and [math]::Abs($binFile.Length - $clearedSz) -le 512) {
            Write-GUI "  [OK] Clean minimal layout active: start2.bin ($szKB KB - Edge, Settings, Explorer)."
        } else {
            Write-GUI "  [!] Active layout database detected: $($binFile.Name) ($szKB KB)."
        }
    } else {
        Write-GUI "  [OK] Start Menu binary database is not present."
    }

    $policyPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
    $mdmLock = (Get-ItemProperty -Path $policyPath -Name "ConfigureStartPins_ProviderSet" -ErrorAction SilentlyContinue).ConfigureStartPins_ProviderSet
    if ($mdmLock -eq 1) {
        Write-GUI "  [!] Residual MDM Start Menu lock detected in PolicyManager."
    } else {
        Write-GUI "  [OK] No residual MDM Start Menu locks found."
    }
}

function Get-ServicesState_Light {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Bloat: Microsoft Wallet Service (WalletService)"; Name = "WalletService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Payments and NFC/SE Manager (SEMgrSvc)"; Name = "SEMgrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Insider Service (wisvc)"; Name = "wisvc"; ExpectedStart = 4; DefaultStart = 3 }
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $rules.Count
    $current = 0

    foreach ($rule in $rules) {
        $current++
        if ($null -ne $UltixSync -and $total -gt 0) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }
        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        $isDetected   = ($null -ne $currentStart -and $currentStart -ne $rule.ExpectedStart)

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

function Get-ServicesState_Heavy {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Edge: Edge Update Service (edgeupdate)"; Name = "edgeupdate"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Edge: Edge Update Service M (edgeupdatem)"; Name = "edgeupdatem"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Device Inventory Service (InventorySvc)"; Name = "InventorySvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Networking: Connected Devices Platform (CDPSvc)"; Name = "CDPSvc"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Location: Geolocation Service (lfsvc)"; Name = "lfsvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Performance: SysMain / Superfetch - Disables RAM caching (SysMain)"; Name = "SysMain"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Virtualization: Windows Subsystem for Linux (WSLService)"; Name = "WSLService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "AI: Windows AI Fabric Service (WSAIFabricSvc)"; Name = "WSAIFabricSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Printers: Print Spooler - Disables all printing (Spooler)"; Name = "Spooler"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Printers: Print Notify Service (PrintNotify)"; Name = "PrintNotify"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Printers: Fax Service (Fax)"; Name = "Fax"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Remote: Remote Desktop Services (TermService)"; Name = "TermService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Remote: Remote Registry (RemoteRegistry)"; Name = "RemoteRegistry"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Biometrics: Windows Biometric Service (WbioSrvc)"; Name = "WbioSrvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Data Service (SensorDataService)"; Name = "SensorDataService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Service (SensorService)"; Name = "SensorService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Monitoring Service (SensrSvc)"; Name = "SensrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Phone Service (PhoneSvc)"; Name = "PhoneSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: Windows Mobile Hotspot Service (icssvc)"; Name = "icssvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: WWAN AutoConfig (WwanSvc)"; Name = "WwanSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Search: Windows Search - Disables file indexing (WSearch)"; Name = "WSearch"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Networking: Offline Files (CscService)"; Name = "CscService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: Internet Connection Sharing (SharedAccess)"; Name = "SharedAccess"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: WAP Push Message Routing (dmwappushservice)"; Name = "dmwappushservice"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Logitech: Lamp Array Service RGB (logi_lamparray_service)"; Name = "logi_lamparray_service"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Updates: Delivery Optimization (DoSvc)"; Name = "DoSvc"; ExpectedStart = 4; DefaultStart = 2 }

        # Diagnostics & SRUM Disk I/O Elimination
        @{ UIDisplayName = "Diagnostics: Diagnostic Policy Service - Stops SRUM disk logging (DPS)"; Name = "DPS"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Diagnostics: Diagnostic Service Host (WdiServiceHost)"; Name = "WdiServiceHost"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Diagnostics: Diagnostic System Host (WdiSystemHost)"; Name = "WdiSystemHost"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Insider Service (wisvc)"; Name = "wisvc"; ExpectedStart = 4; DefaultStart = 3 }

        # File System & Backup Overhead
        @{ UIDisplayName = "FileSystem: Distributed Link Tracking Client (TrkWks)"; Name = "TrkWks"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Backup: Windows File History Service (fhsvc)"; Name = "fhsvc"; ExpectedStart = 4; DefaultStart = 3 }

        # Mobile, NFC & Time Zone Bloat
        @{ UIDisplayName = "Bloat: Microsoft Wallet Service (WalletService)"; Name = "WalletService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Payments and NFC/SE Manager (SEMgrSvc)"; Name = "SEMgrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Cellular Time Synchronization (autotimesvc)"; Name = "autotimesvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Location: Auto Time Zone Updater (tzautoupdate)"; Name = "tzautoupdate"; ExpectedStart = 4; DefaultStart = 4 }

        # Legacy Network Discovery (UPnP / SSDP / NetBIOS)
        @{ UIDisplayName = "Network: SSDP Multicast Discovery (SSDPSRV)"; Name = "SSDPSRV"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: UPnP Device Host (upnphost)"; Name = "upnphost"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: TCP/IP NetBIOS Helper (lmhosts)"; Name = "lmhosts"; ExpectedStart = 4; DefaultStart = 3 }
        
        @{ UIDisplayName = "Xbox: Xbox Live Auth Manager (XblAuthManager)"; Name = "XblAuthManager"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Game Save (XblGameSave)"; Name = "XblGameSave"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Networking Service (XboxNetApiSvc)"; Name = "XboxNetApiSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Accessory Management (XboxGipSvc)"; Name = "XboxGipSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server (FrameServer)"; Name = "FrameServer"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server Monitor (FrameServerMonitor)"; Name = "FrameServerMonitor"; ExpectedStart = 4; DefaultStart = 3 }
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $rules.Count
    $current = 0

    foreach ($rule in $rules) {
        $current++
        if ($null -ne $UltixSync -and $total -gt 0) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }
        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        $isDetected   = ($null -ne $currentStart -and $currentStart -ne $rule.ExpectedStart)

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

function Get-GhostServicesState {
    $ghosts = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $runningNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.Name) }
    Get-CimInstance -ClassName Win32_SystemDriver -Filter "State = 'Running'" -Property Name -ErrorAction SilentlyContinue | ForEach-Object { [void]$runningNames.Add($_.Name) }

    $services = @(Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue)
    $total = $services.Count
    $current = 0

    foreach ($svc in $services) {
        $current++
        if ($null -ne $UltixSync -and ($current % 15 -eq 0 -or $current -eq $total)) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }

        $svcName = $svc.PSChildName
        if ($runningNames.Contains($svcName)) { continue }

        $props = Get-ItemProperty -Path $svc.PSPath -Name "ImagePath", "Type" -ErrorAction SilentlyContinue
        if ($null -eq $props) { continue }

        # Skip Per-User service templates and dynamic session instances (SERVICE_USER_SERVICE bit 0x40)
        if ($null -ne $props.Type -and (($props.Type -band 0x40) -ne 0)) { continue }

        $imagePath = $props.ImagePath
        if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
        if ($imagePath -match '(?i)^\\(?:Driver|FileSystem)\\') { continue }
        
        # Normalize kernel and relative root prefixes (\SystemRoot\, SystemRoot\, \System32\, system32\)
        $rawPath = $imagePath.Trim()
        $rawPath = $rawPath -replace '^\\+?\?\?\\+', ''
        $rawPath = $rawPath -replace '(?i)^\\?SystemRoot\\', "$env:windir\"
        $rawPath = $rawPath -replace '(?i)^\\?System32\\', "$env:windir\System32\"
        $rawPath = $rawPath -replace '(?i)^\\?SysWOW64\\', "$env:windir\SysWOW64\"
        $rawPath = [System.Environment]::ExpandEnvironmentVariables($rawPath).Trim()
        
        if ($rawPath -match '^"([^"]+)"') { 
            $rawPath = $matches[1] 
        } elseif ($rawPath -match '(?i)^(.+?\.(?:exe|sys|dll))(?:$|\s)') {
            $rawPath = $matches[1]
        } else { 
            $rawPath = $rawPath.Split(' ')[0] 
        }
        
        if (-not [System.IO.Path]::IsPathRooted($rawPath)) {
            $candidateWinDir = Join-Path -Path $env:windir -ChildPath $rawPath
            $candidateSys32  = Join-Path -Path "$env:windir\System32" -ChildPath $rawPath
            $candidateDrv    = Join-Path -Path "$env:windir\System32\drivers" -ChildPath $rawPath
            
            if (Test-Path -LiteralPath $candidateWinDir -PathType Leaf) { $rawPath = $candidateWinDir }
            elseif (Test-Path -LiteralPath $candidateSys32 -PathType Leaf) { $rawPath = $candidateSys32 }
            elseif (Test-Path -LiteralPath $candidateDrv -PathType Leaf) { $rawPath = $candidateDrv }
            else { $rawPath = $candidateWinDir }
        }
        
        if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
            $ghosts.Add([PSCustomObject]@{
                Name          = $svcName
                Path          = $rawPath
                UIDisplayName = "Ghost: $svcName (Missing: $rawPath)"
                IsDetected    = $true
            })
        }
    }
    return $ghosts
}

# ------------------------------------------
# Z4: SERVICES & SYSTEM ENGINE
# ------------------------------------------

function Get-PowerDisplayState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # 1. System Hibernation (hiberfil.sys)
    $hiberVal = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Power: Disable Hibernation & Purge hiberfil.sys"
        IsDetected    = ($null -eq $hiberVal -or $hiberVal -ne 0)
        ActionData    = @{ Type = "Hiber" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }

    # 2. System Standby / Sleep Timeout (SUB_SLEEP -> STANDBYIDLE)
    $standbySec = Get-UltixPowerAcIndex -SubGroupGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" -SettingGuid "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Power: Disable System Sleep / Standby Timeout (Current AC: $(if ($null -ne $standbySec) { "$standbySec s" } else { 'N/A' }))"
        IsDetected    = ($null -eq $standbySec -or $standbySec -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "238c9fa8-0aad-41ed-83f4-97be242c8f20"; Guid = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"; OptAC = 0; OptDC = 0; DefAC = 1800; DefDC = 900 }
    })

    # 3. Display Turn-Off Timeout (SUB_VIDEO -> VIDEOIDLE >= 3600s or 0)
    $videoSec = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Display: Set Monitor Turn-Off Timeout to 60 Min (Current AC: $(if ($null -ne $videoSec) { "$([math]::Round($videoSec / 60)) min" } else { 'N/A' }))"
        IsDetected    = ($null -eq $videoSec -or ($videoSec -ne 0 -and $videoSec -lt 3600))
        ActionData    = @{ Type = "PowerCfg"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"; OptAC = 3600; OptDC = 3600; DefAC = 900; DefDC = 300 }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 50 }

    # 4. Hard Disk / SATA AHCI Spin-Down Timeout (SUB_DISK -> DISKIDLE = 0)
    $diskSec = Get-UltixPowerAcIndex -SubGroupGuid "0012ee47-9041-4b5d-9b77-535fba8b1442" -SettingGuid "6738e2c4-e8a5-4a42-b16a-e040e769756e" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Storage: Disable HDD / SATA Controller Spin-Down (Current AC: $(if ($null -ne $diskSec) { "$diskSec s" } else { 'N/A' }))"
        IsDetected    = ($null -eq $diskSec -or $diskSec -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "0012ee47-9041-4b5d-9b77-535fba8b1442"; Guid = "6738e2c4-e8a5-4a42-b16a-e040e769756e"; OptAC = 0; OptDC = 0; DefAC = 1200; DefDC = 600 }
    })

    # 5. USB Selective Suspend (SUB_USB -> USBSELECTIVESUSPEND = 0)
    $usbVal = Get-UltixPowerAcIndex -SubGroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -IncludeHidden
    $usbLabel = if ($usbVal -eq 0) { "Disabled" } elseif ($usbVal -eq 1) { "Enabled" } else { "N/A" }
    $results.Add([PSCustomObject]@{
        UIDisplayName = "USB: Disable USB Selective Suspend - Protects DACs/VR/Dongles (Current: $usbLabel)"
        IsDetected    = ($null -eq $usbVal -or $usbVal -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "2a737441-1930-4402-8d77-b2bebba308a3"; Guid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 1 }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }

    # 6. Power Plan PCIe Link State Power Management (SUB_PCIEXPRESS -> ASPM = 0)
    $pcieVal = Get-UltixPowerAcIndex -SubGroupGuid "501a4d13-42af-4429-9fd1-a8218c268e20" -SettingGuid "ee12f906-d277-404b-b6da-e5fa1a576df5" -IncludeHidden
    $pcieLabel = switch ($pcieVal) { 0 { "Off" } 1 { "Moderate" } 2 { "Max Saving" } default { "N/A" } }
    $results.Add([PSCustomObject]@{
        UIDisplayName = "PCIe: Disable Plan Link State Power Management (Current AC: $pcieLabel)"
        IsDetected    = ($null -eq $pcieVal -or $pcieVal -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "501a4d13-42af-4429-9fd1-a8218c268e20"; Guid = "ee12f906-d277-404b-b6da-e5fa1a576df5"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 2 }
    })

    # 7. Display Content Adaptive Brightness Control (CABC / Adaptive Dimming = 0)
    $cabcVal = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "aded5e82-b909-4619-9949-f5d71dac0bcb" -IncludeHidden
    $cabcReg = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "DisableCABC" -ErrorAction SilentlyContinue).DisableCABC
    $isCabcOpt = (($null -eq $cabcVal -or $cabcVal -eq 0) -and $cabcReg -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Display: Disable Content Adaptive Brightness (CABC / OLED Auto-Dimming)"
        IsDetected    = (-not $isCabcOpt)
        ActionData    = @{ Type = "CABC"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "aded5e82-b909-4619-9949-f5d71dac0bcb" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($results)
}

function Invoke-ApplyPowerDisplay {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No power/display items selected."; return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
        param([array]$Items, [string]$Op)
        $total   = $Items.Count
        $current = 0
        $verb    = if ($Op -eq 'Apply') { "Enforcing" } else { "Reverting" }

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 90)
                $UltixSync.Logs.Enqueue(" -> $($verb): $($item.UIDisplayName)")
            }

            $d = $item.ActionData
            try {
                if ($d.Type -eq "Hiber") {
                    if ($Op -eq 'Apply') {
                        powercfg.exe /hibernate off 2>$null
                    } else {
                        powercfg.exe /hibernate on 2>$null
                    }
                } elseif ($d.Type -eq "PowerCfg") {
                    $acVal = if ($Op -eq 'Apply') { $d.OptAC } else { $d.DefAC }
                    $dcVal = if ($Op -eq 'Apply') { $d.OptDC } else { $d.DefDC }
                    powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid $acVal 2>$null
                    powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid $dcVal 2>$null
                } elseif ($d.Type -eq "CABC") {
                    $gfxKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
                    if ($Op -eq 'Apply') {
                        powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid 0 2>$null
                        powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid 0 2>$null
                        Set-ItemProperty -Path $gfxKey -Name "DisableCABC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -Path $gfxKey -Name "DisableCABC" -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed on $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }

        powercfg.exe /setactive SCHEME_CURRENT 2>$null
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Power & Display subsystem configuration completed ($Operation).`n"
    }.GetNewClosure()
}
function Invoke-ApplyTasks { 
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No tasks selected."; return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
        param([array]$Items, [string]$Op)
        
        $total = $Items.Count
        $current = 0
        $actionVerb = if ($Op -eq 'Apply') { "Disabling" } else { "Enabling" }
        $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)")
            }
            
            $taskRule = $item.ActionData
            try {
                $tasks = @($allTasks | Where-Object { $_.TaskPath -like $taskRule.TaskPath })
                foreach ($task in $tasks) { 
                    if ($Op -eq 'Apply') {
                        Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
                    } else {
                        Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed to modify task path: $($taskRule.TaskPath)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Telemetry tasks lockdown completed ($Operation).`n"
    }.GetNewClosure()
}

function Invoke-ApplyServices {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No services selected."; return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $ProfileName, $Operation) -ScriptBlock {
        param([array]$Items, [string]$ProfName, [string]$Op)

        $total = $Items.Count
        $current = 0
        $actionVerb = if ($Op -eq 'Apply') { "Configuring" } else { "Reverting" }

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
            }

            $svc = $item.ActionData
            $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"

            if (-not (Test-Path -Path $svcRegPath)) {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> Skipping absent service: $($svc.Name)") }
                continue
            }

            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)") }
            $targetValue = if ($Op -eq 'Apply') { $svc.ExpectedStart } else { $svc.DefaultStart }

            if ($null -eq $targetValue -and $Op -eq 'Revert') {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Missing 'DefaultStart' property. Skipping.") }
                continue
            }

            try {
                if ($Op -eq 'Apply') {
                    Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                }
                # Uses Set-ProtectedServiceStart pre-hydrated by Core_Helpers InitialSessionState
                Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue $targetValue
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed to modify service $($svc.Name): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> $ProfileName services enforcement completed ($Operation).`n"
    }.GetNewClosure()
}

function Clear-StartMenu {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Initializing deterministic Start Menu reset (Pinning: Edge, Settings, Explorer)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($null -eq $pkgDir) {
            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] StartMenuExperienceHost package directory not found. Aborting.") }
            return
        }

        $startStatePath   = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
        $provGuid         = "B5292708-1619-419B-9923-E5D9F3925E71"
        $enrollmentPath   = "HKLM:\SOFTWARE\Microsoft\Enrollments\$provGuid"
        $providerPath     = "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid\default\Device\Start"
        $policyDevicePath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
        $policyLegacyPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\device\Start"
        $policyUserPath   = "HKCU:\Software\Microsoft\PolicyManager\current\user\Start"

        # Minimal 3-icon layout: Microsoft Edge, Windows Settings, File Explorer
        $cleanPinsJson = '{"pinnedList":[{"desktopAppId":"MSEdge"},{"packagedAppId":"windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"},{"desktopAppId":"Microsoft.Windows.Explorer"}]}'

        $createdEnrollment = $false

        try {
            # Stage 1: ContentDeliveryManager lockdown
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 15
                $UltixSync.Logs.Enqueue(" -> [1/7] Disabling ContentDeliveryManager silent tile injection...")
            }
            $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (Test-Path $cdmPath) {
                foreach ($cdmName in @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "SubscribedContentEnabled")) {
                    Set-ItemProperty -Path $cdmPath -Name $cdmName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path "$cdmPath\SuggestedApps") {
                    Remove-Item -Path "$cdmPath\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Stage 2: Temporary MDM Provider Registration
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 30
                $UltixSync.Logs.Enqueue(" -> [2/7] Injecting temporary MDM PolicyManager provider context...")
            }
            if (-not (Test-Path $enrollmentPath)) {
                New-Item -Path $enrollmentPath -Force -ErrorAction Stop | Out-Null
                $createdEnrollment = $true
            }
            Set-ItemProperty -Path $enrollmentPath -Name "EnrollmentState" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $enrollmentPath -Name "EnrollmentType" -Value 6 -Type DWord -Force
            Set-ItemProperty -Path $enrollmentPath -Name "IsFederated" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $enrollmentPath -Name "ProviderID" -Value "MS DM Server" -Type String -Force

            if (-not (Test-Path $providerPath)) {
                New-Item -Path $providerPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $providerPath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
            Set-ItemProperty -Path $providerPath -Name "ConfigureStartPins_LastWrite" -Value 1 -Type DWord -Force

            if (-not (Test-Path $policyDevicePath)) {
                New-Item -Path $policyDevicePath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $policyDevicePath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
            Set-ItemProperty -Path $policyDevicePath -Name "ConfigureStartPins_ProviderSet" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $policyDevicePath -Name "ConfigureStartPins_WinningProvider" -Value $provGuid -Type String -Force

            # Stage 3: Purge CloudStore caches
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 45
                $UltixSync.Logs.Enqueue(" -> [3/7] Purging CloudStore tile grid and Start registry caches...")
            }
            $cloudStoreRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current"
            if (Test-Path $cloudStoreRoot) {
                Get-ChildItem -Path $cloudStoreRoot -ErrorAction SilentlyContinue | Where-Object {
                    $_.PSChildName -match "start\.tilegrid|unifiedtile|start\.allapps|start\.properties"
                } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            $startRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
            if (Test-Path $startRegPath) {
                Remove-Item -Path $startRegPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Stage 4: Stop shell processes and wipe start*.bin
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 60
                $UltixSync.Logs.Enqueue(" -> [4/7] Recycling Explorer & wiping locked start2.bin database...")
            }
            Stop-Process -Name "StartMenuExperienceHost", "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300

            for ($attempt = 1; $attempt -le 6; $attempt++) {
                Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
                Get-ChildItem -Path $startStatePath -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
                if (-not (Test-Path (Join-Path $startStatePath "start2.bin"))) { break }
                Start-Sleep -Milliseconds 50
            }

            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
                Start-Sleep -Milliseconds 800
            }

            # Stage 5: Trigger native compilation via Core_Helpers [WinUltix.AppActivator] COM interop
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 75
                $UltixSync.Logs.Enqueue(" -> [5/7] Invoking COM IApplicationActivationManager to compile clean start2.bin...")
            }
            try {
                $appActivator = New-Object WinUltix.AppActivator
                [uint32]$activatedPid = 0
                [void]$appActivator.ActivateApplication("Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!App", $null, 0, [ref]$activatedPid)
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($appActivator)
            } catch {}

            $compiledBinPath = Join-Path $startStatePath "start2.bin"
            $elapsed = 0
            while ($elapsed -lt 4500) {
                Start-Sleep -Milliseconds 250
                $elapsed += 250
                if (Test-Path -LiteralPath $compiledBinPath) {
                    $fileInfo = Get-Item -LiteralPath $compiledBinPath -Force -ErrorAction SilentlyContinue
                    if ($null -ne $fileInfo -and $fileInfo.Length -gt 1024) {
                        Start-Sleep -Milliseconds 600
                        break
                    }
                }
            }

            if (Test-Path -LiteralPath $compiledBinPath) {
                $newBinSize = (Get-Item -LiteralPath $compiledBinPath -Force).Length
                if (-not (Test-Path "HKCU:\Software\WinUltix")) { New-Item -Path "HKCU:\Software\WinUltix" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -Value $newBinSize -Type DWord -Force
            }

            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue("    [OK] Native start2.bin compiled (Pinned: Edge, Settings, File Explorer).")
            }
        } catch {
            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue("    [!] Error during Start Menu native compilation: $($_.Exception.Message)")
            }
        } finally {
            # Stage 6: Deterministic MDM cleanup so pins remain unlocked
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 90
                $UltixSync.Logs.Enqueue(" -> [6/7] Stripping temporary MDM PolicyManager locks...")
            }
            foreach ($polPath in @($policyDevicePath, $policyLegacyPath, $policyUserPath)) {
                if (Test-Path -Path $polPath) {
                    Remove-ItemProperty -Path $polPath -Name "ConfigureStartPins" -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $polPath -Name "ConfigureStartPins_ProviderSet" -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $polPath -Name "ConfigureStartPins_WinningProvider" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid") {
                Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid" -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($createdEnrollment -and (Test-Path $enrollmentPath)) {
                Remove-Item -Path $enrollmentPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
        }

        # Stage 7: Default User provisioning
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [7/7] Provisioning Default User profile LayoutModification.json...")
        }
        $defaultShellPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
        if (-not (Test-Path -Path $defaultShellPath)) {
            New-Item -Path $defaultShellPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $defaultJsonPath = Join-Path -Path $defaultShellPath -ChildPath "LayoutModification.json"
        Set-Content -Path $defaultJsonPath -Value $cleanPinsJson -Encoding UTF8 -Force -ErrorAction SilentlyContinue

        $defaultPkgPath = "$env:SystemDrive\Users\Default\AppData\Local\Packages"
        if (Test-Path -Path $defaultPkgPath) {
            Get-ChildItem -Path $defaultPkgPath -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem -Path (Join-Path $_.FullName "LocalState") -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        if ($null -ne $UltixSync) {
            $UltixSync.Logs.Enqueue("    [OK] Default User LayoutModification.json provisioned.")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Remove-GhostServices {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        Update-Progress ([int](($current / $total) * 100))
        
        Write-GUI " -> Removing: $($item.Name)"
        # SCM deletion might fail if driver is loaded (unlikely for ghosts) or locked. Registry brute-force is cleaner here.
        Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($item.Name)" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Update-Progress 0
    Write-GUI " -> Ghost services purged from system registry.`n"
}

# ------------------------------------------
# Z4: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z4UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabServices = New-Object System.Windows.Forms.TabPage
    $tabServices.Text = "Services"
    $tabServices.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. Telemetry Scheduled Tasks
    $rowTelemetry = New-UltixActionRow -Parent $tabServices -Y 20 `
        -Text "Disable Telemetry Tasks (Scheduler)" `
        -Description "Paralyzes the Task Scheduler. Disables analytics, error reporting, Windows AI, and feedback." `
        -AuditDescription "AUDIT: Verifies if telemetry tasks are active in the scheduler." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ModalTitle "WinUltix - Scheduled Tasks Lockdown" -ModalDescription "Select tasks to modify (Apply = Disable, Revert = Enable)." -ExecutorFunction "Invoke-ApplyTasks" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Active"
        }.GetNewClosure())

    # 2. Start Menu Reset
    $rowStartMenu = New-UltixActionRow -Parent $tabServices -Y 70 `
        -Text "Reset Start Menu Layout (Unpin All)" `
        -Description "Wipes the internal Start Menu database (start2.bin) and removes MDM locks." `
        -AuditDescription "AUDIT: Scans the size of the current Start Menu layout database." `
        -OnClick ({
            $msgText = "This action will permanently wipe your Start Menu pins and layout database.`n`nStartMenuExperienceHost will be restarted in the background (System Tray remains intact).`n`nDo you want to proceed?"
            $msgResult = [System.Windows.Forms.MessageBox]::Show($msgText, "WinUltix - Destructive Action", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($msgResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Clear-StartMenu -ControlsToDisable $allTabButtons.ToArray()
            } else {
                Write-GUI " -> Start Menu reset aborted by user.`n"
            }
        }.GetNewClosure()) `
        -OnAudit ({ Invoke-StartMenuAudit; Write-GUI "" })

    # 3. Power & Display
    $rowPower = New-UltixActionRow -Parent $tabServices -Y 120 `
        -Text "Optimize Power and Display" `
        -Description "Interactive Power & Display tuner: Hibernation, Sleep/Monitor timeouts, SATA spin-down, USB Selective Suspend, PCIe ASPM, and OLED/CABC dimming." `
        -AuditDescription "AUDIT: Verifies active Power Plan timeouts, USB Selective Suspend, PCIe ASPM, and Hibernation state." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ModalTitle "WinUltix - Power & Display Optimizer" -ModalDescription "Select power and display parameters to enforce or revert to Windows defaults." -ExecutorFunction "Invoke-ApplyPowerDisplay" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Unoptimized"
        }.GetNewClosure())

    # 4. Ghost Services & Drivers
    $rowGhostSvc = New-UltixActionRow -Parent $tabServices -Y 170 `
        -Text "Cleanup Ghost Services" `
        -Description "Scans registry for services/drivers pointing to non-existent binaries and removes them." `
        -AuditDescription "AUDIT: Detects orphaned service/driver registrations." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ModalTitle "WinUltix - Ghost Services Cleanup" -ModalDescription "Select orphaned items to remove." -ExecutorFunction "Remove-GhostServices" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Found"
        }.GetNewClosure())

    # 5. Office Services Profile (Light)
    $rowSvcLight = New-UltixActionRow -Parent $tabServices -Y 270 `
        -Text "Background Services: OFFICE PROFILE" `
        -MainRGB @(60, 100, 150) `
        -Description "OFFICE PROFILE: Kills telemetry and tracking, leaving print and network services intact." `
        -AuditDescription "AUDIT: Verifies standard telemetry and background bloat services." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ModalTitle "WinUltix - Office Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Office Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Disable"
        }.GetNewClosure())

    # 6. Gaming Services Profile (Heavy)
    $rowSvcHeavy = New-UltixActionRow -Parent $tabServices -Y 320 `
        -Text "Background Services: GAMING PROFILE" `
        -MainRGB @(150, 60, 60) `
        -Description "GAMING PROFILE: Disables almost everything in the background, including print spooler and file indexing." `
        -AuditDescription "AUDIT: Verifies heavy background services including indexer and print spooler." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ModalTitle "WinUltix - Gaming Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Gaming Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Configure"
        }.GetNewClosure())

    foreach ($row in @($rowTelemetry, $rowStartMenu, $rowPower, $rowGhostSvc, $rowSvcLight, $rowSvcHeavy)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabServices)
}
# <<< END INJECTED: Z4_Services.ps1 <<<


# Z5_Utilities: Interactive tools and applets via Show-UltixGridModal for selective package and service management. Includes DNS Enforcer and classic Windows applet launchers.
# >>> INJECTED: Z5_Utilities.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z5_UTILITIES.PS1 - UTILITIES & APPLETS MODULE (v3.0.0)
# Z5_Utilities: Asynchronous interactive system inspectors (Appx, Provisioned, FOD, Optional Features, Services with TrustedInstaller DACL escalation, Deep Startup Manager with StartupApproved binary decoding, Scheduled Tasks Inspector for 3rd-party/bloat/ghost tasks), Dual-Stack IPv4/IPv6 + Native DoH DNS Enforcer, and classic Windows applet launchers.
# ==========================================

# ------------------------------------------
# Z5: ASYNC INTERACTIVE GRIDS (APPX, PROV, FOD, OPT, SERVICES)
# ------------------------------------------
function Show-AppxGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Scanning installed Appx packages (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|ShellExperienceHost|StartMenuExperienceHost|immersivecontrolpanel|SecHealthUI|WindowsDefender"
        
        $pkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedPattern } |
            Select-Object Name, PackageFullName, PackageFamilyName, IsFramework, Status |
            Sort-Object Name)
        return $pkgs
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$pkgs = @($output | Where-Object { $null -ne $_ })
        if ($pkgs.Count -eq 0) {
            Write-GUI " -> No removable Appx packages found.`n"
            return
        }

        $cols = @(
            @{ Header = "Package Name";    Property = "Name";            Width = 310 }
            @{ Header = "Framework";       Property = "IsFramework";     Width = 90  }
            @{ Header = "Status";          Property = "Status";          Width = 95  }
            @{ Header = "PackageFullName"; Property = "PackageFullName"; Width = 350 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Installed Appx Packages" `
            -Description "Select Appx packages to remove across all accounts. Protected gaming/system runtimes are hidden." `
            -Data $pkgs -Columns $cols -PrimaryButtonText "Remove Selected Appx"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Appx removal cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($app in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Removing Appx: $($app.Name)")
                try {
                    try {
                        Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
                    } catch {
                        Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
                    }
                    if (-not [string]::IsNullOrWhiteSpace($app.PackageFamilyName)) {
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$($app.PackageFamilyName)"
                        if (-not (Test-Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }
                    $UltixSync.Logs.Enqueue("    [OK] $($app.Name) removed and deprovisioned.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Error removing $($app.Name): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Selected Appx removal routine finished.`n"
        }
    }.GetNewClosure()
}

function Show-AppxProvGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Scanning Provisioned Appx image packages (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"
        
        $pkgs = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -notmatch $protectedPattern } |
            Select-Object DisplayName, Version, PackageName |
            Sort-Object DisplayName)
        return $pkgs
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$pkgs = @($output | Where-Object { $null -ne $_ })
        if ($pkgs.Count -eq 0) {
            Write-GUI " -> No provisioned packages found in system image.`n"
            return
        }

        $cols = @(
            @{ Header = "Display Name"; Property = "DisplayName"; Width = 340 }
            @{ Header = "Version";      Property = "Version";     Width = 140 }
            @{ Header = "Package Name"; Property = "PackageName"; Width = 365 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Provisioned Appx Image Packages" `
            -Description "Select base-image packages to deprovision so they never install for new users." `
            -Data $pkgs -Columns $cols -PrimaryButtonText "Deprovision Selected"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Deprovisioning cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($app in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Deprovisioning: $($app.DisplayName)")
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction Stop | Out-Null
                    $UltixSync.Logs.Enqueue("    [OK] $($app.DisplayName) deprovisioned.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Error deprovisioning $($app.DisplayName): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Selected Provisioned packages removed from image.`n"
        }
    }.GetNewClosure()
}

function Show-CapsGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Querying installed Windows Capabilities / FOD (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $caps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Installed' } |
            Select-Object Name, State |
            Sort-Object Name)
        return $caps
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$caps = @($output | Where-Object { $null -ne $_ })
        if ($caps.Count -eq 0) {
            Write-GUI " -> No installed Capabilities returned.`n"
            return
        }

        $cols = @(
            @{ Header = "Capability Name (FOD)"; Property = "Name";  Width = 680 }
            @{ Header = "State";                 Property = "State"; Width = 160 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Windows Capabilities (FOD)" `
            -Description "Select installed Features on Demand (FOD) to uninstall from the OS image." `
            -Data $caps -Columns $cols -PrimaryButtonText "Uninstall Selected FODs"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Capability removal cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($cap in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Removing capability: $($cap.Name)")
                try {
                    Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                    $UltixSync.Logs.Enqueue("    [OK] $($cap.Name) removed.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Failed to remove $($cap.Name): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Capability removal finished.`n"
        }
    }.GetNewClosure()
}

function Show-OptFeaturesGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Querying enabled Windows Optional Features (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $feats = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Enabled' } |
            Select-Object FeatureName, State |
            Sort-Object FeatureName)
        return $feats
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$feats = @($output | Where-Object { $null -ne $_ })
        if ($feats.Count -eq 0) {
            Write-GUI " -> No enabled Optional Features found.`n"
            return
        }

        $cols = @(
            @{ Header = "Optional Feature Name"; Property = "FeatureName"; Width = 680 }
            @{ Header = "State";                 Property = "State";       Width = 160 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Windows Optional Features" `
            -Description "Select enabled Optional Features to disable (e.g., Legacy Components, SMB1, Hypervisor modules)." `
            -Data $feats -Columns $cols -PrimaryButtonText "Disable Selected Features"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Optional feature configuration cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($feat in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Disabling feature: $($feat.FeatureName)")
                try {
                    Disable-WindowsOptionalFeature -Online -FeatureName $feat.FeatureName -NoRestart -ErrorAction Stop | Out-Null
                    $UltixSync.Logs.Enqueue("    [OK] $($feat.FeatureName) disabled (Reboot may be required).")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Failed to disable $($feat.FeatureName): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Optional Features processing completed.`n"
        }
    }.GetNewClosure()
}

function Show-ServicesGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Generating complete system services table (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        # Critical kernel/SCM/RPC services protected from modification
        $criticalServices = "^(RpcSs|DcomLaunch|RpcEptMapper|LSM|SamSs|PlugPlay|EventLog|BFE|mpssvc|nsi|ProfSvc|gpsvc|CryptSvc|TrustedInstaller|WinDefend|WdNisSvc|SecurityHealthService|Dhcp|Dnscache|Winmgmt|Schedule|UserManager|CoreMessagingRegistrar|SystemEventsBroker|Power|BrokerInfrastructure)$"
        
        $svcs = @(Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
            $isCrit = ($_.Name -match $criticalServices)
            $startDisp = if ($isCrit) { "$($_.StartType) [CRITICAL - LOCKED]" } else { [string]$_.StartType }
            [PSCustomObject]@{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                Status      = [string]$_.Status
                StartType   = $startDisp
                IsLocked    = $isCrit
            }
        } | Sort-Object Status, Name)
        return $svcs
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$svcs = @($output | Where-Object { $null -ne $_ })

        $cols = @(
            @{ Header = "Service Name"; Property = "Name";        Width = 200 }
            @{ Header = "Status";       Property = "Status";      Width = 95  }
            @{ Header = "Start Type";   Property = "StartType";   Width = 175 }
            @{ Header = "Display Name"; Property = "DisplayName"; Width = 375 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - System Services Manager" `
            -Description "Select services to HARD DISABLE or restore to Manual. Critical OS/RPC/Defender services (Red) are visible for inspection but locked against modification." `
            -Data $svcs -Columns $cols -PrimaryButtonText "Stop & Disable Selected" `
            -SecondaryButtonText "Restore to Manual (Demand)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Service modification cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0
            foreach ($svc in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                if ($svc.IsLocked) { continue }

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Disabling service: $($svc.Name) ($($svc.DisplayName))")
                    try {
                        Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue 4
                        $UltixSync.Logs.Enqueue("    [OK] $($svc.Name) stopped and locked to Disabled (Start=4).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to disable $($svc.Name): $($_.Exception.Message)")
                    }
                } else {
                    $UltixSync.Logs.Enqueue(" -> Restoring service to Manual: $($svc.Name)")
                    try {
                        Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue 3
                        $UltixSync.Logs.Enqueue("    [OK] $($svc.Name) set to Manual (Start=3).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to modify $($svc.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Service operations completed.`n"
        }
    }.GetNewClosure()
}

# ------------------------------------------
# Z5: DEEP STARTUP INSPECTOR (RUN, RUNONCE, POLICIES, STARTUPAPPROVED)
# ------------------------------------------
function Get-StartupState_Worker {
    $startupItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    function Resolve-StartupApprovedState {
        param([string]$ApprovedRegPath, [string]$EntryName)
        if ([string]::IsNullOrWhiteSpace($ApprovedRegPath) -or -not (Test-Path $ApprovedRegPath)) {
            return "Enabled"
        }
        try {
            $key = Get-Item -Path $ApprovedRegPath -ErrorAction SilentlyContinue
            if ($null -eq $key) { return "Enabled" }
            try {
                [byte[]]$bin = $key.GetValue($EntryName, $null)
            } finally {
                $key.Dispose()
            }
            if ($null -eq $bin -or $bin.Length -lt 1) { return "Enabled" }

            # In Windows Task Manager, byte[0] == 0x02 or 0x06 indicates Enabled; odd/other bytes (0x03, 0x01) mean Disabled
            $header = [int]$bin[0]
            if ($header -eq 2 -or $header -eq 6) {
                return "Enabled"
            } else {
                if ($bin.Length -ge 12) {
                    $ft = [BitConverter]::ToInt64($bin, 4)
                    if ($ft -gt 0) {
                        $dt = [DateTime]::FromFileTimeUtc($ft).ToLocalTime().ToString("yyyy-MM-dd")
                        return "Disabled ($dt)"
                    }
                }
                return "Disabled (TaskMgr)"
            }
        } catch {
            return "Enabled"
        }
    }

    $regTargets = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKLM Run (x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";       Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"; Label = "HKLM Run (x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKCU Run" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKLM RunOnce (x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce";   Approved = "";                                                                               Label = "HKLM RunOnce (x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKCU RunOnce" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKLM)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKCU)" }
    )

    foreach ($reg in $regTargets) {
        if (Test-Path $reg.Path) {
            $keyObj = Get-Item -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $keyObj) {
                try {
                    foreach ($valName in $keyObj.Property) {
                        $valData = [string]$keyObj.GetValue($valName)
                        $state = if ($reg.Approved -ne "") {
                            Resolve-StartupApprovedState -ApprovedRegPath $reg.Approved -EntryName $valName
                        } else {
                            "Enabled (Always)"
                        }
                        $startupItems.Add([PSCustomObject]@{
                            Name         = $valName
                            State        = $state
                            Location     = $reg.Label
                            Command      = $valData
                            RegPath      = $reg.Path
                            ApprovedPath = $reg.Approved
                            Type         = "Registry"
                        })
                    }
                } finally {
                    $keyObj.Dispose()
                }
            }
        }
    }

    $folderTargets = @(
        @{ Path = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (All Users)" }
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";         Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (Current User)" }
    )

    foreach ($fld in $folderTargets) {
        if (Test-Path $fld.Path) {
            Get-ChildItem -Path $fld.Path -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -ne "desktop.ini") {
                    $state = Resolve-StartupApprovedState -ApprovedRegPath $fld.Approved -EntryName $_.Name
                    $startupItems.Add([PSCustomObject]@{
                        Name         = $_.Name
                        State        = $state
                        Location     = $fld.Label
                        Command      = $_.FullName
                        RegPath      = $null
                        ApprovedPath = $fld.Approved
                        Type         = "File"
                    })
                }
            }
        }
    }

    return @($startupItems | Sort-Object Location, Name)
}

function Show-StartupGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Auditing Run, RunOnce, GPO Run, Startup Folders, and StartupApproved binary states..."
    Update-Progress 20

    $sb = (Get-Command -Name Get-StartupState_Worker).ScriptBlock
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete {
        param($output)
        Update-Progress 0
        [array]$items = @($output | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            Write-GUI " -> No startup items detected across registry or folders.`n"
            return
        }

        $cols = @(
            @{ Header = "Entry Name"; Property = "Name";     Width = 210 }
            @{ Header = "State";      Property = "State";    Width = 145 }
            @{ Header = "Location";   Property = "Location"; Width = 155 }
            @{ Header = "Command";    Property = "Command";  Width = 340 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Deep Startup Inspector" `
            -Description "Inspect Run, RunOnce, GPO, and StartupApproved states. You can permanently delete entries or toggle their TaskMgr state." `
            -Data $items -Columns $cols -PrimaryButtonText "Remove Selected (Permanent)" `
            -SecondaryButtonText "Toggle State (Enable / Disable)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Startup modification cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0

            foreach ($item in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)

                if ($Action -eq "Primary") {
                    # Permanent Removal + StartupApproved orphan cleanup
                    $UltixSync.Logs.Enqueue(" -> Deleting startup entry: $($item.Name) [$($item.Location)]")
                    try {
                        if ($item.Type -eq "Registry") {
                            Remove-ItemProperty -Path $item.RegPath -Name $item.Name -Force -ErrorAction Stop
                        } else {
                            Remove-Item -LiteralPath $item.Command -Force -ErrorAction Stop
                        }
                        if (-not [string]::IsNullOrWhiteSpace($item.ApprovedPath) -and (Test-Path $item.ApprovedPath)) {
                            Remove-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Force -ErrorAction SilentlyContinue
                        }
                        $UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
                    }
                } else {
                    # Non-destructive Toggle via StartupApproved binary header
                    if ([string]::IsNullOrWhiteSpace($item.ApprovedPath)) {
                        $UltixSync.Logs.Enqueue("    [!] $($item.Name) [$($item.Location)] does not support TaskMgr StartupApproved toggling.")
                        continue
                    }
                    try {
                        if (-not (Test-Path $item.ApprovedPath)) {
                            New-Item -Path $item.ApprovedPath -Force | Out-Null
                        }
                        if ($item.State -match "^Disabled") {
                            # Enable: 12-byte array starting with 0x02
                            [byte[]]$enableBytes = @(0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
                            Set-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Value $enableBytes -Type Binary -Force -ErrorAction Stop
                            $UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.Name) [$($item.Location)]")
                        } else {
                            # Disable: 0x03 header + 3 zero padding bytes + 8-byte UTC FILETIME
                            [byte[]]$headerBytes = @(0x03, 0x00, 0x00, 0x00)
                            [byte[]]$timeBytes   = [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())
                            [byte[]]$disableBytes = $headerBytes + $timeBytes
                            Set-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Value $disableBytes -Type Binary -Force -ErrorAction Stop
                            $UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.Name) [$($item.Location)]")
                        }
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Startup configuration updated.`n"
        }
    }.GetNewClosure()
}

# ------------------------------------------
# Z5: SCHEDULED TASKS INSPECTOR (3RD-PARTY, BLOAT & GHOST TASKS)
# ------------------------------------------
function Get-ScheduledTasks_Worker {
    $taskItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Resolve whether an MSFT_TaskExecAction binary exists on disk
    function Test-TaskExecutableExists {
        param([string]$RawExecute)
        if ([string]::IsNullOrWhiteSpace($RawExecute)) { return $true }

        $clean = [System.Environment]::ExpandEnvironmentVariables($RawExecute.Trim().Trim('"')).Trim()
        if ($clean -match '^"([^"]+)"') {
            $clean = $matches[1]
        } elseif ($clean -match '(?i)^(.+?\.(?:exe|bat|cmd|vbs|ps1|msc))(?:$|\s)') {
            $clean = $matches[1]
        } else {
            $clean = $clean.Split(' ')[0]
        }

        # Ignore shell variables or custom protocol handlers
        if ($clean -match '^\$\(' -or $clean -match '^[a-zA-Z]+://') { return $true }

        if ([System.IO.Path]::IsPathRooted($clean)) {
            return [System.IO.File]::Exists($clean)
        } else {
            $leaf = if ($clean -notmatch '\.') { "$clean.exe" } else { $clean }
            foreach ($dir in @("$env:windir\System32", $env:windir, "$env:windir\SysWOW64", "$env:windir\System32\wbem", "$env:windir\System32\WindowsPowerShell\v1.0")) {
                if ([System.IO.File]::Exists((Join-Path $dir $leaf))) { return $true }
            }
            return $true
        }
    }

    # Format CIM triggers into concise engineering tags
    function ConvertTo-TriggerSummary {
        param([array]$Triggers)
        if ($null -eq $Triggers -or $Triggers.Count -eq 0) { return "OnDemand" }
        $tags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $Triggers) {
            $className = [string]$t.CimClass.CimClassName
            switch -Wildcard ($className) {
                "*LogonTrigger*"              { [void]$tags.Add("AtLogon") }
                "*BootTrigger*"               { [void]$tags.Add("AtStartup") }
                "*DailyTrigger*"              { [void]$tags.Add("Daily") }
                "*WeeklyTrigger*"             { [void]$tags.Add("Weekly") }
                "*TimeTrigger*"               { [void]$tags.Add("Time/Once") }
                "*IdleTrigger*"               { [void]$tags.Add("OnIdle") }
                "*EventTrigger*"              { [void]$tags.Add("OnEvent") }
                "*SessionStateChangeTrigger*" { [void]$tags.Add("SessionChange") }
                "*RegistrationTrigger*"       { [void]$tags.Add("OnRegister") }
                default                       { [void]$tags.Add("Custom") }
            }
            if ($null -ne $t.Repetition -and -not [string]::IsNullOrWhiteSpace($t.Repetition.Interval)) {
                [void]$tags.Add("Periodic")
            }
        }
        return ($tags -join ", ")
    }

    # Shield WinUltix internal failsafe and critical OS security tasks
    $protectedTaskNames = "^(WinUltix_CPPC_Failsafe|MpIdleTask|Windows Defender.*|BitLocker.*)$"
    $msTelemetryPaths   = "(?i)^\\Microsoft\\Windows\\(Application Experience|Autochk|Customer Experience Improvement Program|DiskDiagnostic|Feedback|Location|Maps|Mobile Broadband Accounts|NetTrace|Power Efficiency Diagnostics|PushToInstall|RetailDemo|CloudExperienceHost|Windows Error Reporting|WaaSMedic)\\"

    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    $total = [math]::Max(1, $allTasks.Count)
    $idx = 0

    foreach ($task in $allTasks) {
        $idx++
        if ($null -ne $UltixSync -and ($idx % 15 -eq 0 -or $idx -eq $total)) {
            $UltixSync.Progress = [int](($idx / $total) * 100)
        }

        $tName  = [string]$task.TaskName
        $tPath  = [string]$task.TaskPath
        $tState = [string]$task.State

        if ($tName -match $protectedTaskNames) { continue }

        # Extract execution action and verify binary presence
        $execAction = $task.Actions | Where-Object { $null -ne $_.Execute -and $_.Execute -ne "" } | Select-Object -First 1
        $cmdLine = ""
        $isGhost = $false

        if ($null -ne $execAction) {
            $rawExe  = [string]$execAction.Execute
            $rawArgs = [string]$execAction.Arguments
            $cmdLine = "$rawExe $rawArgs".Trim()
            if (-not (Test-TaskExecutableExists -RawExecute $rawExe)) {
                $isGhost = $true
            }
        } else {
            $comAction = $task.Actions | Where-Object { $null -ne $_.ClassId } | Select-Object -First 1
            if ($null -ne $comAction) {
                $cmdLine = "[COM Handler] $($comAction.ClassId)"
            } else {
                $cmdLine = "[Internal Handler]"
            }
        }

        # Categorize and filter out standard non-telemetry Microsoft\Windows OS internals unless orphaned
        $category = ""
        if ($isGhost) {
            $category = "[GHOST / Missing Exe]"
        } elseif ($tPath -notlike "\Microsoft\Windows\*") {
            if ($tPath -like "\Microsoft\*") {
                $category = "[MS App / Updater]"
            } else {
                $category = "[3rd-Party / Root]"
            }
        } elseif ($tPath -match $msTelemetryPaths -or $tPath -like "\Microsoft\XblGameSave\*") {
            $category = "[MS Telemetry / Bloat]"
        } else {
            # Core healthy Windows internal task - skip to keep the grid clean and high-signal
            continue
        }

        $trigSummary = ConvertTo-TriggerSummary -Triggers @($task.Triggers)

        $taskItems.Add([PSCustomObject]@{
            Name     = $tName
            Category = $category
            State    = $tState
            Triggers = $trigSummary
            TaskPath = $tPath
            Command  = $cmdLine
        })
    }

    return @($taskItems | Sort-Object Category, TaskPath, Name)
}

function Show-TasksGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Auditing Task Scheduler for 3rd-party updaters, telemetry, and orphaned ghost tasks..."
    Update-Progress 10

    $sb = (Get-Command -Name Get-ScheduledTasks_Worker).ScriptBlock
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete {
        param($output)
        Update-Progress 0
        [array]$items = @($output | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            Write-GUI " -> No third-party, telemetry, or orphaned scheduled tasks found.`n"
            return
        }

        $cols = @(
            @{ Header = "Task Name"; Property = "Name";     Width = 195 }
            @{ Header = "Category";  Property = "Category"; Width = 155 }
            @{ Header = "State";     Property = "State";    Width = 80  }
            @{ Header = "Triggers";  Property = "Triggers"; Width = 120 }
            @{ Header = "Folder";    Property = "TaskPath"; Width = 140 }
            @{ Header = "Action";    Property = "Command";  Width = 280 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Scheduled Tasks Inspector (3rd-Party, Telemetry & Ghosts)" `
            -Description "Core Windows tasks are hidden. Inspect 3rd-party updaters, MS bloat, and [GHOST] tasks with missing binaries." `
            -Data $items -Columns $cols -PrimaryButtonText "Remove Selected (Unregister)" `
            -SecondaryButtonText "Toggle State (Enable / Disable)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Scheduled tasks operation cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0

            foreach ($item in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Unregistering task: $($item.TaskPath)$($item.Name)")
                    try {
                        Stop-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction SilentlyContinue | Out-Null
                        Unregister-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -Confirm:$false -ErrorAction Stop
                        $UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
                    }
                } else {
                    try {
                        if ($item.State -eq "Disabled") {
                            Enable-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction Stop | Out-Null
                            $UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.TaskPath)$($item.Name)")
                        } else {
                            Stop-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction SilentlyContinue | Out-Null
                            Disable-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction Stop | Out-Null
                            $UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.TaskPath)$($item.Name)")
                        }
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Scheduled Tasks operations completed.`n"
        }
    }.GetNewClosure()
}

# ------------------------------------------
# Z5: DNS ENFORCER (IPV4 + IPV6 + NATIVE WINDOWS 11 DOH)
# ------------------------------------------
function Set-CustomDNS {
    param(
        [Parameter(Mandatory=$true)][string]$Provider,
        [bool]$EnableDoH = $true,
        [bool]$EnableIPv6 = $true,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    Write-GUI " -> Applying DNS profile '$Provider' (DoH: $EnableDoH, IPv6: $EnableIPv6)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($Provider, $EnableDoH, $EnableIPv6) -ScriptBlock {
        param([string]$TargetProvider, [bool]$UseDoH, [bool]$UseIPv6)

        $dnsCatalog = @{
            "Quad9 (9.9.9.9)" = @{
                IPv4     = @("9.9.9.9", "149.112.112.112")
                IPv6     = @("2620:fe::fe", "2620:fe::9")
                Template = "https://dns.quad9.net/dns-query"
            }
            "Cloudflare (1.1.1.1)" = @{
                IPv4     = @("1.1.1.1", "1.0.0.1")
                IPv6     = @("2606:4700:4700::1111", "2606:4700:4700::1001")
                Template = "https://cloudflare-dns.com/dns-query"
            }
            "AdGuard (94.140.14.14)" = @{
                IPv4     = @("94.140.14.14", "94.140.15.15")
                IPv6     = @("2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff")
                Template = "https://dns.adguard-dns.com/dns-query"
            }
            "Google (8.8.8.8)" = @{
                IPv4     = @("8.8.8.8", "8.8.4.4")
                IPv6     = @("2001:4860:4860::8888", "2001:4860:4860::8844")
                Template = "https://dns.google/dns-query"
            }
            "OpenDNS (208.67.222.222)" = @{
                IPv4     = @("208.67.222.222", "208.67.220.220")
                IPv6     = @("2620:119:35::35", "2620:119:53::53")
                Template = "https://doh.opendns.com/dns-query"
            }
        }

        # Discover active routed interfaces
        $routedIndices = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty InterfaceIndex -Unique)

        if ($routedIndices.Count -eq 0) {
            $UltixSync.Logs.Enqueue(" [!] No active network adapters with a default gateway found.")
            return
        }

        $wellKnownBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers"
        $ifSpecBase    = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters"

        foreach ($ifIndex in $routedIndices) {
            $adapter = Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
            if ($null -eq $adapter) { continue }
            $ifGuid  = $adapter.InterfaceGuid
            $ifName  = $adapter.InterfaceDescription

            $dohV4Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh"
            $dohV6Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh6"

            # Wipe previous per-interface DoH bindings first
            if (Test-Path $dohV4Root) { Remove-Item -Path $dohV4Root -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $dohV6Root) { Remove-Item -Path $dohV6Root -Recurse -Force -ErrorAction SilentlyContinue }

            if ($TargetProvider -eq "Default (DHCP)") {
                try {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses -ErrorAction Stop
                    $UltixSync.Logs.Enqueue(" -> [$ifName]: Reverted IPv4/IPv6 DNS to DHCP and cleared DoH locks.")
                } catch {
                    $UltixSync.Logs.Enqueue(" [!] [$ifName]: Failed to reset DNS: $($_.Exception.Message)")
                }
                continue
            }

            $cfg = $dnsCatalog[$TargetProvider]
            if ($null -eq $cfg) { continue }

            $allServers = [System.Collections.Generic.List[string]]::new()
            foreach ($ip4 in $cfg.IPv4) { $allServers.Add($ip4) }
            if ($UseIPv6) {
                foreach ($ip6 in $cfg.IPv6) { $allServers.Add($ip6) }
            }

            try {
                Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($allServers) -ErrorAction Stop
                if (-not $UseIPv6) {
                    # Reset IPv6 DNS to DHCP if user unchecked IPv6 enforcement
                    netsh.exe interface ipv6 set dnsservers name="$($adapter.Name)" source=dhcp 2>$null | Out-Null
                }
                $UltixSync.Logs.Enqueue(" -> [$ifName]: Enforced servers: $($allServers -join ', ')")
            } catch {
                $UltixSync.Logs.Enqueue(" [!] [$ifName]: Error setting DNS servers: $($_.Exception.Message)")
            }

            if ($UseDoH) {
                if (-not (Test-Path $wellKnownBase)) { New-Item -Path $wellKnownBase -Force | Out-Null }

                foreach ($ip in $allServers) {
                    # 1. Register global DoH template in Dnscache well-known store & runtime API
                    $wkKey = "$wellKnownBase\$ip"
                    if (-not (Test-Path $wkKey)) { New-Item -Path $wkKey -Force | Out-Null }
                    Set-ItemProperty -Path $wkKey -Name "Template" -Value $cfg.Template -Type String -Force -ErrorAction SilentlyContinue

                    if (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
                        Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
                        Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
                    }

                    # 2. Enforce per-interface DoH encryption (DohFlags = 1 QWord)
                    $isV6 = ($ip -match ":")
                    $targetDohKey = if ($isV6) { "$dohV6Root\$ip" } else { "$dohV4Root\$ip" }
                    if (-not (Test-Path $targetDohKey)) { New-Item -Path $targetDohKey -Force | Out-Null }
                    Set-ItemProperty -Path $targetDohKey -Name "DohFlags" -Value ([uint64]1) -Type QWord -Force -ErrorAction SilentlyContinue
                }
                $UltixSync.Logs.Enqueue("    [+] Native DoH encryption activated ($($cfg.Template)).")
            }
        }

        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $UltixSync.Progress = 100
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Update-DNSLabel
        Write-GUI " -> DNS configuration completed and resolver cache flushed.`n"
    }
}

# ------------------------------------------
# Z5: CLASSIC APPLETS
# ------------------------------------------
function Start-ClassicNet      { Start-Process "ncpa.cpl" }
function Start-ClassicApps     { Start-Process "appwiz.cpl" }
function Start-ClassicSound    { Start-Process "mmsys.cpl" }
function Start-ClassicPrinters { Start-Process "explorer.exe" -ArgumentList "shell:::{26EE0668-A00A-44D7-9371-BEB064C98683}\0\::{A8A91A66-3A7D-4424-8D24-04E180695C7A}" }
function Start-ClassicSysProp  { Start-Process "SystemPropertiesAdvanced.exe" }
function Start-ClassicPower    { Start-Process "powercfg.cpl" }

# ------------------------------------------
# Z5: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z5UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabUtil = New-Object System.Windows.Forms.TabPage
    $tabUtil.Text = "Utilities"
    $tabUtil.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # 1. Advanced System Inspectors
    $lblInspect = New-Object System.Windows.Forms.Label
    $lblInspect.Text = "WARNING: Advanced System Inspectors"
    $lblInspect.Location = New-Object System.Drawing.Point(15, 15)
    $lblInspect.Size = New-Object System.Drawing.Size(370, 20)
    $lblInspect.ForeColor = [System.Drawing.Color]::OrangeRed
    $lblInspect.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblInspect.TextAlign = "MiddleLeft"

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 40 -Width 180 -Height 40 `
        -Text "Appx (Accounts)" `
        -Description "Opens a native dark table of installed Appx packages with live filtering and Deprovisioned store locking." `
        -OnClick { Show-AppxGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 40 -Width 180 -Height 40 `
        -Text "Appx (Image)" `
        -Description "Opens a native dark table of Provisioned Appx packages cached in the Windows image." `
        -OnClick { Show-AppxProvGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 90 -Width 180 -Height 40 `
        -Text "Capabilities (FOD)" `
        -Description "Asynchronously scans installed Features on Demand (FOD) for selective removal." `
        -OnClick { Show-CapsGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 90 -Width 180 -Height 40 `
        -Text "Optional Features" `
        -Description "Asynchronously scans enabled Windows Optional Features to disable unnecessary OS components." `
        -OnClick { Show-OptFeaturesGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 140 -Width 370 -Height 40 `
        -Text "System Services Inspector" `
        -Description "Interactive Services Manager. Hard-disable unneeded services or restore them to Manual (Critical boot services are shielded)." `
        -OnClick { Show-ServicesGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 190 -Width 370 -Height 40 -RGB @(60, 100, 150) `
        -Text "Deep Startup Manager (Run / StartupApproved)" `
        -Description "Audits Run, RunOnce, GPO Run, Startup folders, and decodes TaskMgr StartupApproved binary headers. Supports Toggle or Delete." `
        -OnClick { Show-StartupGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 240 -Width 370 -Height 40 -RGB @(100, 60, 120) `
        -Text "Scheduled Tasks Inspector (3rd-Party / Ghosts)" `
        -Description "Filters out core OS noise to expose 3rd-party updaters, Microsoft bloat, and orphaned [GHOST] tasks pointing to missing .exe files." `
        -OnClick { Show-TasksGrid -ControlsToDisable @($this) })

    # 2. Classic Windows Control Applets
    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Classic Windows Control Applets"
    $lblClassic.Location = New-Object System.Drawing.Point(15, 295)
    $lblClassic.Size = New-Object System.Drawing.Size(370, 20)
    $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 320 -Width 180 -Height 40 `
        -Text "Network Adapters (ncpa)" `
        -Description "Direct launch of the classic Win32 Network Connections applet (ncpa.cpl)." `
        -OnClick { Start-ClassicNet })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 320 -Width 180 -Height 40 `
        -Text "Sound Subsystem (mmsys)" `
        -Description "Direct launch of playback/recording devices and sample rate properties (mmsys.cpl)." `
        -OnClick { Start-ClassicSound })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 370 -Width 180 -Height 40 `
        -Text "Programs & Features" `
        -Description "Direct launch of the classic Win32 MSI/InstallShield software uninstaller (appwiz.cpl)." `
        -OnClick { Start-ClassicApps })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 370 -Width 180 -Height 40 `
        -Text "Devices and Printers" `
        -Description "Bypasses Windows 11 Settings redirect to open the raw Win32 Devices and Printers shell folder." `
        -OnClick { Start-ClassicPrinters })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 420 -Width 180 -Height 40 `
        -Text "System Properties (Env)" `
        -Description "Opens Advanced System Properties (Pagefile, Performance Flags, and Environment Variables)." `
        -OnClick { Start-ClassicSysProp })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 420 -Width 180 -Height 40 `
        -Text "Power Plans (powercfg)" `
        -Description "Opens the classic Power Options applet to inspect unhidden CPPC parameters." `
        -OnClick { Start-ClassicPower })

    # 3. DNS Enforcer (IPv4 + IPv6 + DoH)
    $lblDNS = New-Object System.Windows.Forms.Label
    $lblDNS.Text = "Hardened DNS & DoH Enforcer (IPv4 / IPv6)"
    $lblDNS.Location = New-Object System.Drawing.Point(15, 480)
    $lblDNS.Size = New-Object System.Drawing.Size(370, 20)
    $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray

    $comboDNS = New-Object System.Windows.Forms.ComboBox
    $comboDNS.Location = New-Object System.Drawing.Point(15, 505)
    $comboDNS.Size = New-Object System.Drawing.Size(240, 25)
    $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $comboDNS.ForeColor = [System.Drawing.Color]::White
    $comboDNS.DropDownStyle = "DropDownList"
    $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)"))
    $comboDNS.SelectedIndex = 0

    $chkDoH = New-Object System.Windows.Forms.CheckBox
    $chkDoH.Text = "Enforce Native DNS-over-HTTPS (DoH)"
    $chkDoH.Location = New-Object System.Drawing.Point(15, 538)
    $chkDoH.Size = New-Object System.Drawing.Size(235, 22)
    $chkDoH.ForeColor = [System.Drawing.Color]::LightGray
    $chkDoH.Checked = $true

    $chkIPv6 = New-Object System.Windows.Forms.CheckBox
    $chkIPv6.Text = "Configure IPv6 DNS"
    $chkIPv6.Location = New-Object System.Drawing.Point(255, 538)
    $chkIPv6.Size = New-Object System.Drawing.Size(135, 22)
    $chkIPv6.ForeColor = [System.Drawing.Color]::LightGray
    $chkIPv6.Checked = $true

    $btnApplyDNS = New-UltixButton -Parent $tabUtil -X 265 -Y 504 -Width 120 -Height 27 -RGB @(100, 40, 40) `
        -Text "Apply DNS" `
        -Description "Enforces IPv4/IPv6 DNS servers, injects kernel Dnscache DoH encryption flags, and flushes resolver cache."
    $btnApplyDNS.Add_Click({
        Set-CustomDNS -Provider $comboDNS.SelectedItem -EnableDoH $chkDoH.Checked -EnableIPv6 $chkIPv6.Checked -ControlsToDisable @($btnApplyDNS)
    }.GetNewClosure())

    $global:lblCurrentDNS = New-Object System.Windows.Forms.Label
    $global:lblCurrentDNS.Text = "Current DNS: Reading from active route..."
    $global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 566)
    $global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 22)
    $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $tabUtil.Controls.AddRange(@(
        $lblInspect, $lblClassic, $lblDNS,
        $comboDNS, $chkDoH, $chkIPv6, $global:lblCurrentDNS
    ))
    $TabControl.Controls.Add($tabUtil)
}
# <<< END INJECTED: Z5_Utilities.ps1 <<<


# Z6_Integrity: Advanced repair and reset module. Features WinSXS compression (DISM /ResetBase) with deployment auditing, full network stack refresh, Print Spooler subsystem reset, and core file repairs.
# >>> INJECTED: Z6_Integrity.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z6_INTEGRITY.PS1 - SYSTEM INTEGRITY MODULE (v3.0.0)
# Z6_Integrity: Service and repair module. Executes real-time streamed WinSxS analysis, ResetBase compression, network stack refresh, Print Spooler reset, Windows Update/Cryptographic First-Aid, WMI repository salvage, Shell Icon/Thumbnail cache purge, and core OS repairs.
# ==========================================

# ------------------------------------------
# Z6: ASYNC EXTERNAL CONSOLE HELPER (REAL EXIT CODE LATCH)
# ------------------------------------------
function Start-ExternalConsoleAsync {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$CommandChain,
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control[]]$ControlsToDisable
    )

    Write-GUI " -> Launching external maintenance console: $Title..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        param($CmdTitle, $CmdChain)
        # /v:on enables delayed environment variable expansion (!ERRORLEVEL! / !WUX_ERR!)
        # Preserves real command exit code across 'pause >nul'
        $fullArgs = "/v:on /c `"title $CmdTitle & color 0A & set WUX_ERR=0 & $CmdChain & if !WUX_ERR! EQU 0 (set WUX_ERR=!ERRORLEVEL!) & echo. & echo Operation finished (Exit Code: !WUX_ERR!). Press any key to close... & pause >nul & exit /b !WUX_ERR!`""
        
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $fullArgs -PassThru
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        $proc.Dispose()

        return [PSCustomObject]@{
            Title    = $CmdTitle
            ExitCode = $exitCode
        }
    } -Arguments @($Title, $CommandChain) -OnComplete {
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            $code = [int]$res.ExitCode
            if ($code -eq 0) {
                Write-GUI " -> [$($res.Title)] completed successfully (Exit Code: 0).`n"
            } elseif ($code -eq 3010) {
                Write-GUI " -> [$($res.Title)] completed (Exit Code: 3010 - Reboot Required to finalize changes).`n"
            } else {
                $hexCode = "0x{0:X8}" -f ([uint32]$code)
                Write-GUI " -> [!] [$($res.Title)] finished with non-zero Exit Code: $code ($hexCode).`n"
            }
        }
    }
}

# ------------------------------------------
# Z6: SYSTEM INTEGRITY ENGINE (REAL-TIME $ULTIXSYNC WORKERS)
# ------------------------------------------
function Get-WinSxSState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dism.exe"
    $psi.Arguments = "/Online /Cleanup-Image /AnalyzeComponentStore /English"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::ASCII
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $sbOutput = [System.Text.StringBuilder]::new()

    # StreamReader.ReadLine() yields on every '\r' progress bar update from dism.exe
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -eq $line) { continue }

        if ($line -match '(\d{1,3})\.\d+%') {
            $pct = [int]$matches[1]
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [math]::Max(5, [math]::Min(95, $pct))
            }
        } else {
            [void]$sbOutput.AppendLine($line)
        }
    }

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    $dismOutput = $sbOutput.ToString()

    $recommended = ($dismOutput -match "Component Store Cleanup Recommended\s*:\s*Yes")
    $sizeMatch   = [regex]::Match($dismOutput, "Actual Size of Component Store\s*:\s*(.+?)(\r?\n|$)")
    $actualSize  = if ($sizeMatch.Success) { $sizeMatch.Groups[1].Value.Trim() } else { "Unknown" }

    $rebootPending = Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

    return [PSCustomObject]@{
        UIDisplayName = "WinSxS Payload (Actual Size: $actualSize)"
        IsDetected    = $recommended
        ActionData    = $actualSize
        RebootPending = $rebootPending
        ExitCode      = $exitCode
    }
}

function Optimize-WinSXS {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $warnMsg = "A pending Windows servicing reboot was detected in the CBS registry.`n`nRunning DISM /ResetBase while a reboot is pending on Windows 11 24H2/26H2 may fail with error 0x800f0806.`n`nDo you still want to force execution?"
        $ans = [System.Windows.Forms.MessageBox]::Show($warnMsg, "WinUltix - CBS Reboot Pending", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-GUI " -> WinSxS ResetBase aborted due to pending reboot.`n"
            return
        }
    }

    $cmd = "echo Aggressive WinSxS compression in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Start-ExternalConsoleAsync -Title "WinUltix - WinSxS ResetBase" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-SystemIntegrity {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo [1/3] Running Online CheckDisk Scan... & chkdsk C: /scan & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [2/3] Running DISM RestoreHealth... & dism /online /cleanup-image /restorehealth & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [3/3] Running SFC Scan... & sfc /scannow & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Start-ExternalConsoleAsync -Title "WinUltix - System Integrity Repair" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Clear-NetworkStack {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo Flushing DNS resolver cache... & ipconfig /flushdns & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo Resetting Winsock Catalog... & netsh winsock reset & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo Resetting TCP/IP Stack... & netsh int ip reset & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Start-ExternalConsoleAsync -Title "WinUltix - Network Stack Refresh" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-PrintSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Print Subsystem First-Aid (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 20
            $spoolerProc = Get-Process -Name "spoolsv" -ErrorAction SilentlyContinue
            if ($spoolerProc) {
                $spoolerProc | Stop-Process -Force -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue(" -> Terminated locked spoolsv.exe process.")
            } else {
                Stop-Service -Name "Spooler" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue(" -> Stopped Print Spooler service.")
            }

            Start-Sleep -Milliseconds 800
            $UltixSync.Progress = 50

            $spoolPath = "$env:windir\System32\spool\PRINTERS"
            if (Test-Path -LiteralPath $spoolPath) {
                $purgedCount = 0
                Get-ChildItem -Path "$spoolPath\*" -Include "*.SHD", "*.SPL", "*.TMP" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $purgedCount++
                    } catch { }
                }
                $UltixSync.Logs.Enqueue(" -> Purged $purgedCount orphaned .SHD/.SPL print queue file(s).")
            }

            $UltixSync.Progress = 80
            $printWorkflow = Get-Service -Name "PrintWorkflowUserSvc*" -ErrorAction SilentlyContinue
            if ($printWorkflow) {
                $printWorkflow | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $printWorkflow | Start-Service -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue(" -> Restarted dynamic PrintWorkflowUserSvc service.")
            }

            Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction Stop
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Print Spooler service is back online.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Failed to reset print subsystem: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Repair-WindowsUpdateSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Windows Update & Cryptographic First-Aid (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $wuServices = @("dosvc", "bits", "wuauserv", "cryptSvc", "msiserver")
        try {
            # Stage 1: Stop WU, BITS, Cryptographic & MSI services
            $UltixSync.Progress = 15
            $UltixSync.Logs.Enqueue(" -> [1/5] Stopping wuauserv, cryptSvc, bits, dosvc, and msiserver...")
            foreach ($svc in $wuServices) {
                Stop-Service -Name $svc -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            Start-Sleep -Milliseconds 800

            # Stage 2: Purge corrupted BITS queue files (qmgr*.dat)
            $UltixSync.Progress = 35
            $bitsPaths = @(
                "$env:ProgramData\Microsoft\Network\Downloader",
                "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader"
            ) | Select-Object -Unique

            $qmgrCount = 0
            foreach ($bPath in $bitsPaths) {
                if (Test-Path -LiteralPath $bPath) {
                    Get-ChildItem -Path "$bPath\qmgr*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $_.Attributes = 'Normal'
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                            $qmgrCount++
                        } catch { }
                    }
                }
            }
            $UltixSync.Logs.Enqueue(" -> [2/5] Purged $qmgrCount corrupted BITS transfer queue file(s) (qmgr*.dat).")

            # Stage 3: Reset Catroot2 signature cache & SoftwareDistribution DataStore
            $UltixSync.Progress = 55
            $catroot2  = "$env:windir\System32\catroot2"
            $dataStore = "$env:windir\SoftwareDistribution\DataStore"
            foreach ($targetDir in @($catroot2, $dataStore)) {
                if (Test-Path -LiteralPath $targetDir) {
                    Get-ChildItem -LiteralPath $targetDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $_.Attributes = 'Normal'
                            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        } catch { }
                    }
                }
            }
            $UltixSync.Logs.Enqueue(" -> [3/5] Flushed Catroot2 cryptographic catalog cache and WU DataStore.")

            # Stage 4: Re-register core cryptographic & Windows Update COM DLLs
            $UltixSync.Progress = 75
            $dlls = @(
                "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
                "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml3.dll", "msxml6.dll",
                "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll",
                "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll",
                "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll",
                "wucltux.dll", "wups.dll", "wups2.dll", "wuwebv.dll", "qmgr.dll", "qmgrprxy.dll"
            )
            foreach ($dll in $dlls) {
                $dllFull = "$env:windir\System32\$dll"
                if (Test-Path -LiteralPath $dllFull) {
                    Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s `"$dllFull`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
                }
            }
            $UltixSync.Logs.Enqueue(" -> [4/5] Re-registered Cryptographic, WinTrust, and Windows Update COM DLLs.")

            # Stage 5: Restart core services
            $UltixSync.Progress = 95
            foreach ($svc in @("cryptSvc", "bits", "wuauserv")) {
                Start-Service -Name $svc -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [5/5] [OK] Windows Update & Cryptographic services restored and online.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Error during Windows Update subsystem repair: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Invoke-WMIAudit {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI "--- AUDIT: WMI / CIM Repository Health (Background Thread) ---"
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $UltixSync.Progress = 40
        $verifyOut = (winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()

        $UltixSync.Progress = 75
        $cimHealthy = $false
        try {
            $null = Get-CimInstance -Namespace "root\cimv2" -ClassName Win32_OperatingSystem -Property Caption -ErrorAction Stop
            $null = Get-CimInstance -Namespace "root\StandardCimv2" -ClassName MSFT_NetAdapter -ErrorAction Stop
            $cimHealthy = $true
        } catch {
            $cimHealthy = $false
        }

        $UltixSync.Progress = 100
        return [PSCustomObject]@{
            VerifyOutput = $verifyOut
            CimHealthy   = $cimHealthy
        }
    } -OnComplete {
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            Write-GUI "  [*] winmgmt /verifyrepository: $($res.VerifyOutput)"
            if ($res.CimHealthy) {
                Write-GUI "  [OK] Core CIM namespaces (root\cimv2 & root\StandardCimv2) responded normally.`n"
            } else {
                Write-GUI "  [!] WARNING: CIM namespace query failed! Run 'Verify & Salvage WMI Repository' immediately.`n"
            }
        }
    }
}

function Repair-WMIRepository {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating WMI / CIM Repository Salvage (Background Thread)..."
    Update-Progress 15

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/3] Running winmgmt /verifyrepository...")
            $verifyOut = (winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
            $UltixSync.Logs.Enqueue("    [*] Status: $verifyOut")

            $UltixSync.Progress = 55
            $UltixSync.Logs.Enqueue(" -> [2/3] Executing non-destructive winmgmt /salvagerepository...")
            $salvageOut = (winmgmt.exe /salvagerepository 2>&1 | Out-String).Trim()
            $UltixSync.Logs.Enqueue("    [*] Result: $salvageOut")

            $UltixSync.Progress = 85
            $UltixSync.Logs.Enqueue(" -> [3/3] Refreshing WMI Performance Adapter (wmiadap /f)...")
            Start-Process -FilePath "wmiadap.exe" -ArgumentList "/f" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] WMI Repository verification and salvage routine finished.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] WMI repair failed: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Clear-ShellIconCache {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Shell Icon & Thumbnail Cache First-Aid (Background Thread)..."
    Update-Progress 15

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/4] Stopping Explorer shell to release memory-mapped .db handles...")
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600

            $UltixSync.Progress = 55
            $explorerCacheDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
            $purgedIcons  = 0
            $purgedThumbs = 0

            if (Test-Path -LiteralPath $explorerCacheDir) {
                Get-ChildItem -Path "$explorerCacheDir\iconcache*.db" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $purgedIcons++
                    } catch { }
                }
                Get-ChildItem -Path "$explorerCacheDir\thumbcache*.db" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $purgedThumbs++
                    } catch { }
                }
            }

            $legacyIconDb = "$env:LOCALAPPDATA\IconCache.db"
            if (Test-Path -LiteralPath $legacyIconDb) {
                try {
                    Remove-Item -LiteralPath $legacyIconDb -Force -ErrorAction Stop
                    $purgedIcons++
                } catch { }
            }

            $UltixSync.Logs.Enqueue(" -> [2/4] Purged $purgedIcons iconcache_*.db and $purgedThumbs thumbcache_*.db file(s).")

            $UltixSync.Progress = 80
            $UltixSync.Logs.Enqueue(" -> [3/4] Triggering ie4uinit.exe cache rebuild...")
            Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue

            $UltixSync.Progress = 95
            $UltixSync.Logs.Enqueue(" -> [4/4] Restarting Windows Explorer shell...")
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Shell Icon & Thumbnail caches rebuilt cleanly.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Failed to rebuild Icon/Thumbnail cache: $($_.Exception.Message)")
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

# ------------------------------------------
# Z6: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z6UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabWinSXS = New-Object System.Windows.Forms.TabPage
    $tabWinSXS.Text = "Integrity"
    $tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. System Scan (ChkDisk + DISM + SFC)
    $btnCheckSystem = New-UltixButton -Parent $tabWinSXS -X 15 -Y 20 -RGB @(60, 60, 60) `
        -Text "Scan System (ChkDisk + SFC + RestoreHealth)" `
        -Description "System First Aid: Scans core Windows OS files for corruption and replaces damaged components using DISM RestoreHealth and SFC without freezing the GUI." `
        -OnClick ({ Repair-SystemIntegrity -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 2. WinSxS ResetBase + Audit [?]
    $rowWinSxS = New-UltixActionRow -Parent $tabWinSXS -Y 70 -MainRGB @(100, 40, 40) `
        -Text "Aggressive Cleanup (ResetBase)" `
        -Description "WinSxS Deep Clean: Permanently deletes superseded Windows Update backup layers (/ResetBase) to reclaim gigabytes of disk space." `
        -AuditDescription "AUDIT: Streams real-time DISM AnalyzeComponentStore progress in a background Runspace and checks for pending CBS reboots." `
        -OnClick ({ Optimize-WinSXS -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({
            Write-GUI "--- AUDIT: CBS Component Store (Background Thread) ---"
            Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
            Update-Progress 5

            $sb = (Get-Command -Name Get-WinSxSState).ScriptBlock
            Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $allTabButtons.ToArray() -OnComplete {
                param($output)
                Update-Progress 0
                $auditResult = $output | Select-Object -First 1
                if ($null -ne $auditResult) {
                    Write-GUI "  [*] Actual Store Size: $($auditResult.ActionData)"
                    if ($auditResult.RebootPending) {
                        Write-GUI "  [!] WARNING: Pending CBS reboot detected! Reboot before running ResetBase to avoid 0x800f0806."
                    }
                    if ($auditResult.IsDetected) {
                        Write-GUI "  [!] Cleanup Recommended by OS."
                    } else {
                        Write-GUI "  [OK] CBS reports no mandatory cleanup, though I can still force ResetBase payload amputation."
                    }
                    Write-GUI ""
                }
            }
        }.GetNewClosure())

    # 3. Network Stack Refresh
    $btnNetFix = New-UltixButton -Parent $tabWinSXS -X 15 -Y 120 -RGB @(0, 100, 100) `
        -Text "Refresh Network (DNS/Winsock)" `
        -Description "Network Fix: Flushes DNS cache, resets Winsock catalog, and resets TCP/IP stack parameters." `
        -OnClick ({ Clear-NetworkStack -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 4. Print Subsystem First-Aid
    $btnFixPrinters = New-UltixButton -Parent $tabWinSXS -X 15 -Y 170 -RGB @(120, 80, 40) `
        -Text "Reset Print Subsystem (Spooler)" `
        -Description "Printer First-Aid: Kills deadlocked spoolsv.exe, purges stuck .SPL/.SHD files in System32, restarts PrintWorkflowUserSvc, and resumes Spooler." `
        -OnClick ({ Repair-PrintSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 5. Windows Update & Cryptographic Subsystem First-Aid
    $btnFixWU = New-UltixButton -Parent $tabWinSXS -X 15 -Y 220 -RGB @(60, 90, 130) `
        -Text "Reset Windows Update & CryptSvc" `
        -Description "WU First-Aid: Stops wuauserv/bits/cryptSvc, purges corrupted qmgr*.dat queues, resets Catroot2 & DataStore, and re-registers core COM DLLs." `
        -OnClick ({ Repair-WindowsUpdateSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 6. WMI / CIM Repository Salvage + Audit [?]
    $rowWMI = New-UltixActionRow -Parent $tabWinSXS -Y 270 -MainRGB @(90, 60, 120) `
        -Text "Verify & Salvage WMI Repository" `
        -Description "WMI First-Aid: Verifies CIM repository consistency, runs non-destructive 'winmgmt /salvagerepository', and refreshes WMI performance counters." `
        -AuditDescription "AUDIT: Runs 'winmgmt /verifyrepository' and tests live CIM queries against root\cimv2 and root\StandardCimv2." `
        -OnClick ({ Repair-WMIRepository -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Invoke-WMIAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 7. Shell Icon & Thumbnail Cache First-Aid
    $btnFixIcons = New-UltixButton -Parent $tabWinSXS -X 15 -Y 320 -RGB @(70, 100, 70) `
        -Text "Rebuild Shell Icon & Thumbnail Cache" `
        -Description "Shell First-Aid: Gracefully cycles Explorer, purges corrupted iconcache_*.db and thumbcache_*.db files, and forces a clean rebuild via ie4uinit." `
        -OnClick ({ Clear-ShellIconCache -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $allTabButtons.AddRange([System.Windows.Forms.Control[]]@(
        $btnCheckSystem,
        $btnNetFix,
        $btnFixPrinters,
        $btnFixWU,
        $btnFixIcons
    ))
    $allTabButtons.AddRange($rowWinSxS.Controls)
    $allTabButtons.AddRange($rowWMI.Controls)

    $TabControl.Controls.Add($tabWinSXS)
}
# <<< END INJECTED: Z6_Integrity.ps1 <<<


# Z7_Hardware: Low-level hardware diagnostics and tuning with interactive modals.
# >>> INJECTED: Z7_Hardware.ps1 <<<
# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z7_HARDWARE.PS1 - HARDWARE & DIAGNOSTICS MODULE (v3.0.0)
# Z7_Hardware: Low-level hardware diagnostics and kernel latency tuning. Uses Core_Helpers P/Invoke runtime ([WinUltix.CpuTopology], [WinUltix.NtDll], [WinUltix.NativeMethods]) and asynchronous Runspace workers ($UltixSync) for Topology-Aware Affinity Lasso, CPPC P-State Unhider & SYSTEM Dead Man's Switch, MSI & IRQ Core 0 Offload Enforcer with Live NtQuerySystemInformation DPC Telemetry, WHEA APIC XML Decoder, Symmetric NDIS/TCP Optimizer, 0.5ms TSC Timer Lock, NVMe APST / PCIe ASPM Lockdown, Profile Snapshot hooks, and Pre-Flight Game Mode macro generation.
# ==========================================

# Cached physical core masks and CPU topology profile from kernel32!GetLogicalProcessorInformationEx
$script:UltixCoreMasks   = $null
$script:UltixCpuTopology = $null

function Get-UltixPhysicalCoreMasks {
    if ($null -eq $script:UltixCoreMasks) {
        $cores = @([WinUltix.CpuTopology]::GetProcessorCores())
        if ($cores.Count -gt 0) {
            $script:UltixCoreMasks = @($cores | ForEach-Object { [int64]$_.Mask })
        } else {
            $lpCount = [Environment]::ProcessorCount
            $fallback = [System.Collections.Generic.List[int64]]::new()
            for ($i = 0; $i -lt $lpCount; $i += 2) {
                $m = ([int64]1 -shl $i)
                if (($i + 1) -lt $lpCount) { $m = $m -bor ([int64]1 -shl ($i + 1)) }
                $fallback.Add($m)
            }
            $script:UltixCoreMasks = @($fallback)
        }
    }
    return $script:UltixCoreMasks
}

# ------------------------------------------
# Z7: SHARED HARDWARE & TOPOLOGY HELPERS
# ------------------------------------------
function Get-CPUTopologyProfile {
    if ($null -ne $script:UltixCpuTopology) {
        return $script:UltixCpuTopology
    }

    $nativeCores  = @([WinUltix.CpuTopology]::GetProcessorCores())
    $nativeCaches = @([WinUltix.CpuTopology]::GetL3Caches())

    $logical = [int][Environment]::ProcessorCount
    $cores   = if ($nativeCores.Count -gt 0) { $nativeCores.Count } else { [math]::Max(1, [int]($logical / 2)) }
    $smt     = ($logical -gt $cores)

    # Read CPU name directly from kernel hardware registry (<0.1ms) instead of slow Win32_Processor WMI query (~1500ms)
    $name = (Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\Description\System\CentralProcessor\0" -Name "ProcessorNameString" -ErrorAction SilentlyContinue).ProcessorNameString
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unknown CPU" }

    $profileResult = $null

    # Case 1: Intel Hybrid Architecture (P+E Cores detected via EfficiencyClass)
    if ($nativeCores.Count -ge 6) {
        $effClasses = @($nativeCores | Select-Object -ExpandProperty EfficiencyClass -Unique | Sort-Object)
        if ($effClasses.Count -gt 1) {
            $minEff = $effClasses[0]
            [int64]$eCoreMask = 0
            $eCoreCount = 0
            foreach ($c in $nativeCores) {
                if ($c.EfficiencyClass -eq $minEff) {
                    $eCoreMask = $eCoreMask -bor $c.Mask
                    $eCoreCount++
                }
            }
            if ($eCoreMask -gt 0) {
                $profileResult = [PSCustomObject]@{
                    IsSupported = $true
                    Mask        = [System.IntPtr]$eCoreMask
                    Label       = "Intel Hybrid ($eCoreCount E-Cores)"
                    CoreDesc    = "E-Core Cluster (Mask: 0x$($eCoreMask.ToString('X')))"
                    SmtEnabled  = $smt
                }
            }
        }
    }

    # Case 2: AMD 8-Core Single-CCD (e.g., 9800X3D, 7800X3D, 5800X3D, 9700X) -> Lock background apps to Cores 0-1
    if ($null -eq $profileResult -and $name -match "AMD" -and $cores -eq 8) {
        [int64]$c01Mask = if ($nativeCores.Count -ge 2) {
            $nativeCores[0].Mask -bor $nativeCores[1].Mask
        } elseif ($smt) { 15 } else { 3 }
        $desc = if ($smt) { "Cores 0-1 (Threads 0-3)" } else { "Cores 0-1 (No SMT)" }
        $profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$c01Mask; Label = "AMD 8C Single-CCD"; CoreDesc = $desc; SmtEnabled = $smt }
    }

    # Case 3: AMD Dual-CCD (12C/16C, e.g., 7900X3D, 7950X3D, 9950X3D) -> Inspect L3 Cache domains to protect 3D V-Cache CCD
    if ($null -eq $profileResult -and $name -match "AMD" -and $cores -gt 8 -and $logical -ge 12) {
        if ($nativeCaches.Count -ge 2) {
            $sortedL3 = @($nativeCaches | Sort-Object SizeBytes)
            $smallestL3 = $sortedL3[0]
            $largestL3  = $sortedL3[$sortedL3.Count - 1]
            $isAsymmetricX3D = ($largestL3.SizeBytes -gt $smallestL3.SizeBytes)

            $targetDomain = if ($isAsymmetricX3D) { $smallestL3 } else { $nativeCaches[$nativeCaches.Count - 1] }
            $tailMask = [WinUltix.CpuTopology]::GetTailThreadsMask($targetDomain.Mask, 4)
            $l3MB = [math]::Round($targetDomain.SizeBytes / 1MB, 0)
            $labelStr = if ($isAsymmetricX3D) { "AMD Dual-CCD X3D" } else { "AMD Dual-CCD" }
            $profileResult = [PSCustomObject]@{
                IsSupported = $true
                Mask        = [System.IntPtr]$tailMask
                Label       = $labelStr
                CoreDesc    = "Secondary CCD (${l3MB}MB L3 Tail, Mask: 0x$($tailMask.ToString('X')))"
                SmtEnabled  = $smt
            }
        } else {
            $shift = [math]::Max(0, ($logical - 4))
            $maskVal = [int64]15 -shl $shift
            $profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "AMD Dual-CCD"; CoreDesc = "CCD1 Tail (Threads $shift-$($logical - 1))"; SmtEnabled = $smt }
        }
    }

    # Case 4: Standard Multi-Core (6+ Core CPUs) -> Isolate background apps to the last 4 threads
    if ($null -eq $profileResult -and $cores -ge 6 -and $logical -ge 8) {
        $shift = [math]::Max(0, ($logical - 4))
        $maskVal = [int64]15 -shl $shift
        $profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "Multi-Core CPU"; CoreDesc = "Tail Threads ($shift-$($logical - 1))"; SmtEnabled = $smt }
    }

    if ($null -eq $profileResult) {
        $profileResult = [PSCustomObject]@{ IsSupported = $false; Mask = [System.IntPtr]15; Label = "Unsupported (<6C)"; CoreDesc = "N/A"; SmtEnabled = $smt }
    }

    $script:UltixCpuTopology = $profileResult
    return $script:UltixCpuTopology
}

function Test-CPUTopology {
    return (Get-CPUTopologyProfile).IsSupported
}

function Get-KernelInterruptSnapshot {
    param([uint32[]]$PreviousCounts = $null)

    [uint32[]]$currentCounts = [WinUltix.NtDll]::GetProcessorDpcCounts()
    if ($null -eq $currentCounts -or $currentCounts.Count -eq 0) {
        return $null
    }

    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    $coreCount = $coreMasks.Count
    [int64]$core0Mask = if ($coreCount -ge 1) { $coreMasks[0] } else { [int64]3 }

    [uint64[]]$bootByCore  = New-Object uint64[] $coreCount
    [uint64[]]$deltaByCore = New-Object uint64[] $coreCount

    [uint64]$bootTotal    = 0
    [uint64]$bootCore0    = 0
    [uint64]$bootPeakVal  = 0
    $bootPeakThread       = 0

    [uint64]$deltaTotal   = 0
    [uint64]$deltaCore0   = 0
    [uint64]$deltaPeakVal = 0
    $deltaPeakThread      = 0

    $hasValidDelta = ($null -ne $PreviousCounts -and $PreviousCounts.Count -eq $currentCounts.Count)

    for ($i = 0; $i -lt $currentCounts.Count; $i++) {
        $threadBit = ([int64]1 -shl $i)
        $isCore0Thread = (($core0Mask -band $threadBit) -ne 0)
        $curVal = [uint64]$currentCounts[$i]

        $bootTotal += $curVal
        if ($isCore0Thread) { $bootCore0 += $curVal }
        if ($curVal -gt $bootPeakVal) {
            $bootPeakVal    = $curVal
            $bootPeakThread = $i
        }

        [uint64]$diff = 0
        if ($hasValidDelta) {
            $prevVal = [uint64]$PreviousCounts[$i]
            $diff = if ($curVal -ge $prevVal) { $curVal - $prevVal } else { 0 }
            $deltaTotal += $diff
            if ($isCore0Thread) { $deltaCore0 += $diff }
            if ($diff -gt $deltaPeakVal) {
                $deltaPeakVal    = $diff
                $deltaPeakThread = $i
            }
        }

        for ($c = 0; $c -lt $coreCount; $c++) {
            if (($coreMasks[$c] -band $threadBit) -ne 0) {
                $bootByCore[$c] += $curVal
                if ($hasValidDelta) { $deltaByCore[$c] += $diff }
                break
            }
        }
    }

    $bootCore0Pct = if ($bootTotal -gt 0) { [math]::Round(($bootCore0 / $bootTotal) * 100.0, 1) } else { 0.0 }
    $bootPeakPct  = if ($bootTotal -gt 0) { [math]::Round(($bootPeakVal / $bootTotal) * 100.0, 1) } else { 0.0 }

    if ($hasValidDelta -and $deltaTotal -gt 0) {
        $liveCore0Pct = [math]::Round(($deltaCore0 / $deltaTotal) * 100.0, 1)
        $hotPct       = [math]::Round(($deltaPeakVal / $deltaTotal) * 100.0, 1)
        $hotThreadIdx = $deltaPeakThread
        $hasLiveDelta = $true
    } else {
        $liveCore0Pct = $bootCore0Pct
        $hotPct       = $bootPeakPct
        $hotThreadIdx = $bootPeakThread
        $hasLiveDelta = $false
    }

    $bootCorePcts = New-Object double[] $coreCount
    $liveCorePcts = New-Object double[] $coreCount
    $bootParts    = [System.Collections.Generic.List[string]]::new()
    $liveParts    = [System.Collections.Generic.List[string]]::new()

    for ($c = 0; $c -lt $coreCount; $c++) {
        $bPct = if ($bootTotal -gt 0) { [math]::Round(($bootByCore[$c] / $bootTotal) * 100.0, 1) } else { 0.0 }
        $lPct = if ($hasLiveDelta -and $deltaTotal -gt 0) { [math]::Round(($deltaByCore[$c] / $deltaTotal) * 100.0, 1) } else { $bPct }
        $bootCorePcts[$c] = $bPct
        $liveCorePcts[$c] = $lPct

        $bootParts.Add(("C{0}:{1,2:0}%" -f $c, [math]::Round($bPct, 0)))
        $liveParts.Add(("C{0}:{1,2:0}%" -f $c, [math]::Round($lPct, 0)))
    }

    return [PSCustomObject]@{
        RawCounts      = $currentCounts
        HasLiveDelta   = $hasLiveDelta
        CoreCount      = $coreCount
        Core0SharePct  = $liveCore0Pct
        HotThread      = $hotThreadIdx
        HotThreadPct   = $hotPct
        DpcRatePerSec  = $deltaTotal
        BootCore0Pct   = $bootCore0Pct
        BootPeakThread = $bootPeakThread
        BootPeakPct    = $bootPeakPct
        BootTotalDpc   = $bootTotal
        BootCorePcts   = $bootCorePcts
        LiveCorePcts   = $liveCorePcts
        BootCoreLine   = ($bootParts -join " ")
        LiveCoreLine   = ($liveParts -join " ")
    }
}

function Update-UltixDpcMonitorUI {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Label]$TargetLabel,
        [Parameter(Mandatory=$true)][hashtable]$State,
        [switch]$CompactMode
    )

    if ($TargetLabel.IsDisposed) { return }

    $snap = Get-KernelInterruptSnapshot -PreviousCounts $State.PrevCounts
    if ($null -eq $snap) {
        $TargetLabel.Text = "BOOT BASELINE | Kernel interrupt telemetry unavailable.`r`nLIVE 1s DELTA | N/A`r`nPER-CORE MAP  | N/A"
        return
    }

    $State.PrevCounts = $snap.RawCounts
    $State.LastSnap   = $snap

    if ($CompactMode) {
        $line1 = "BOOT AVG | C0: $($snap.BootCore0Pct)% | Peak: LP#$($snap.BootPeakThread) ($($snap.BootPeakPct)%)"
        if (-not $State.IsRunning) {
            $line2 = "LIVE 1s  | [Paused - Click Start below for 1Hz stream]"
            $line3 = "CORES AVG| $($snap.BootCoreLine)"
        } elseif ($snap.HasLiveDelta) {
            $line2 = "LIVE 1s  | C0: $($snap.Core0SharePct)% | Hot : LP#$($snap.HotThread) ($($snap.HotThreadPct)%) | $($snap.DpcRatePerSec)/s"
            $line3 = "CORES 1s | $($snap.LiveCoreLine)"
        } else {
            $line2 = "LIVE 1s  | Sampling 1000ms kernel interrupt delta..."
            $line3 = "CORES AVG| $($snap.BootCoreLine)"
        }
    } else {
        $line1 = "BOOT BASELINE | Core 0 Share: $($snap.BootCore0Pct)% | Peak: LP#$($snap.BootPeakThread) ($($snap.BootPeakPct)%) | Total: $($snap.BootTotalDpc.ToString('N0')) DPCs"
        if ($snap.HasLiveDelta) {
            $line2 = "LIVE 1s DELTA | Core 0 Share: $($snap.Core0SharePct)% | Hot : LP#$($snap.HotThread) ($($snap.HotThreadPct)%) | Rate : $($snap.DpcRatePerSec) DPC/s"
            $line3 = "PER-CORE (1s) | $($snap.LiveCoreLine)"
        } else {
            $line2 = "LIVE 1s DELTA | Sampling kernel interrupt counters (1s window)..."
            $line3 = "PER-CORE (AVG)| $($snap.BootCoreLine)"
        }
    }

    $TargetLabel.Text = "$line1`r`n$line2`r`n$line3"

    $activeC0 = if (($State.IsRunning -or -not $CompactMode) -and $snap.HasLiveDelta) { $snap.Core0SharePct } else { $snap.BootCore0Pct }
    if ($activeC0 -ge 55.0) {
        $TargetLabel.ForeColor = [System.Drawing.Color]::OrangeRed
    } elseif ($activeC0 -ge 30.0) {
        $TargetLabel.ForeColor = [System.Drawing.Color]::Yellow
    } else {
        $TargetLabel.ForeColor = [System.Drawing.Color]::LightGreen
    }
}

function Write-UltixDpcReport {
    param([PSCustomObject]$Snapshot = $null)

    if ($null -eq $Snapshot -or -not $Snapshot.HasLiveDelta) {
        Write-GUI " -> Sampling kernel interrupt counters over a 1000ms window..."
        $s1 = Get-KernelInterruptSnapshot
        Start-Sleep -Milliseconds 1000
        $Snapshot = Get-KernelInterruptSnapshot -PreviousCounts $s1.RawCounts
    }
    if ($null -eq $Snapshot) { return }

    [int64[]]$masks = Get-UltixPhysicalCoreMasks
    Write-GUI "=== KERNEL DPC & INTERRUPT DISTRIBUTION REPORT ==="
    Write-GUI " -> Global DPC Rate (1s) : $($Snapshot.DpcRatePerSec) DPC/s (Boot: $($Snapshot.BootTotalDpc.ToString('N0')))"
    Write-GUI " -> Physical Core 0 Load : $($Snapshot.Core0SharePct)% Live | $($Snapshot.BootCore0Pct)% Boot Avg"
    Write-GUI " -> Hottest Thread       : LP#$($Snapshot.HotThread) ($($Snapshot.HotThreadPct)% Live | Boot Peak: LP#$($Snapshot.BootPeakThread))"
    Write-GUI " -> Per-Core Map (C# = Physical Core | LP# = Logical Threads):"

    for ($c = 0; $c -lt $Snapshot.CoreCount; $c++) {
        $m = $masks[$c]
        $lpNums = [System.Collections.Generic.List[string]]::new()
        for ($b = 0; $b -lt 64; $b++) {
            if (($m -band ([int64]1 -shl $b)) -ne 0) { $lpNums.Add(("{0:D2}" -f $b)) }
        }
        $lpStr = "LP#" + ($lpNums -join ",")
        $roleTag = if ($c -eq 0) { "[OS Timer / Default IRQ]" } elseif ($c -eq 1) { "[Core 0 Offload Target]" } else { "[Prime Gaming Core]" }
        Write-GUI ("  * C{0} ({1,-8}) | 1s:{2,5:0.0}% | Boot:{3,5:0.0}% {4}" -f $c, $lpStr, $Snapshot.LiveCorePcts[$c], $Snapshot.BootCorePcts[$c], $roleTag)
    }

    Write-GUI " -> [LEGEND]: Green (<30% C0) = Optimal | Yellow (30-54%) = Moderate"
    Write-GUI "    Red (>=55% C0) = Bottleneck (Offload ★ GPU/NIC to C1 in MSI Modal)`n"
}

# ------------------------------------------
# Z7: HARDWARE & DIAGNOSTICS AUDITS
# ------------------------------------------
function Get-HardwareState_Affinity {
    $whitelist = @("systemsettings.exe", "shellexperiencehost.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "applicationframehost.exe", "rundll32.exe", "dllhost.exe", "ngciso.exe", "wmiadap.exe", "csrss.exe", "lsass.exe", "smss.exe", "services.exe", "svchost.exe", "wininit.exe", "winlogon.exe", "explorer.exe", "System", "Idle", "Registry", "dwm.exe", "fontdrvhost.exe", "Taskmgr.exe", "conhost.exe", "sihost.exe", "taskhostw.exe", "RuntimeBroker.exe", "SearchHost.exe", "StartMenuExperienceHost.exe", "SecurityHealthService.exe", "SecurityHealthSystray.exe", "MsMpEng.exe", "NisSrv.exe", "LsaIso.exe", "audiodg.exe", "WmiPrvSE.exe", "TiWorker.exe", "TrustedInstaller.exe", "spoolsv.exe", "WUDFHost.exe", "System.exe", "Idle.exe", "Registry.exe", "Secure System.exe", "ctfmon.exe", "MpDefenderCoreService.exe", "NVDisplay.Container.exe", "ShellHost.exe", "iFiUsbAudioCpl.exe", "Windows11FirewallService.exe", "Windows11FirewallControl.exe", "AmdPpkgSvc.exe", "nvcontainer.exe", "MoUsoCoreWorker.exe", "SearchIndexer.exe", "smartscreen.exe", "AppActions.exe", "SDXHelper.exe", "QuickControls.exe", "armsvc.exe", "BudsManager.exe")
    $dictionary = @("Discord.exe", "Spotify.exe", "msedgewebview2.exe", "steamwebhelper.exe", "EpicGamesLauncher.exe", "obs64.exe", "ArmouryCrate.exe", "iCUE.exe", "Razer Synapse Service.exe", "firefox.exe", "chrome.exe", "msedge.exe", "brave.exe", "opera.exe", "GalaxyClient.exe", "GOG Galaxy.exe", "EADesktop.exe", "upc.exe", "Battle.net.exe", "WhatsApp.exe", "Telegram.exe", "Teams.exe", "slack.exe", "Overwolf.exe", "LGHUB.exe", "LGHUB_Agent.exe", "MSIAfterburner.exe", "RTSS.exe", "NZXT CAM.exe", "vgc.exe", "vgtray.exe", "OneDrive.exe")
    
    $topo = Get-CPUTopologyProfile
    $targetMask = $topo.Mask

    $cimProcMap = @{}
    Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.ExecutablePath) { $cimProcMap[[int]$_.ProcessId] = $_.ExecutablePath }
    }

    $liveProcsGrouped = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $pName = "$($_.ProcessName).exe"
        if (-not $liveProcsGrouped.ContainsKey($pName)) {
            $liveProcsGrouped[$pName] = $_
        }
    }

    $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
    $savedApps = @()
    if (Test-Path $configPath) {
        $savedApps = (Get-ItemProperty -Path $configPath -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -match "\.exe$" } | Select-Object -ExpandProperty Name
    }

    $combined = ($dictionary + $liveProcsGrouped.Keys + $savedApps) | Where-Object { $_ -notin $whitelist } | Select-Object -Unique

    $listRunning  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $listSaved    = [System.Collections.Generic.List[PSCustomObject]]::new()
    $listTemplate = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($app in $combined) {
        $procName = $app -replace '\.exe$', ''
        $activeProc = $liveProcsGrouped[$app]
        $isDetected = ($app -in $savedApps)
        
        $procPath = ""
        if ($null -ne $activeProc) {
            try { $procPath = $activeProc.Path } catch {}
            if (-not $procPath) { try { $procPath = $activeProc.MainModule.FileName } catch {} }
            if (-not $procPath -and $cimProcMap.ContainsKey($activeProc.Id)) {
                $procPath = $cimProcMap[$activeProc.Id]
            }
            if (-not $procPath) { continue }
        }

        $priority = "---"
        if ($null -ne $activeProc) {
            try { $priority = $activeProc.PriorityClass.ToString() } catch { $priority = "Access Denied" }
            if ($activeProc.ProcessorAffinity -eq $targetMask) {
                $listRunning.Add([PSCustomObject]@{ UIDisplayName = "[LOCKED]   $app"; IsDetected = $isDetected; Path = $procPath; Priority = $priority; ActionData = @{ ExeName = $app; ProcName = $procName } })
            } else {
                $listRunning.Add([PSCustomObject]@{ UIDisplayName = "[RUNNING]  $app"; IsDetected = $isDetected; Path = $procPath; Priority = $priority; ActionData = @{ ExeName = $app; ProcName = $procName } })
            }
        } elseif ($app -in $savedApps) {
            $listSaved.Add([PSCustomObject]@{ UIDisplayName = "[SAVED]    $app"; IsDetected = $true; Path = "---"; Priority = "---"; ActionData = @{ ExeName = $app; ProcName = $procName } })
        } else {
            $listTemplate.Add([PSCustomObject]@{ UIDisplayName = "[TEMPLATE] $app"; IsDetected = $false; Path = "---"; Priority = "---"; ActionData = @{ ExeName = $app; ProcName = $procName } })
        }
    }

    return @(($listRunning | Sort-Object UIDisplayName) + ($listSaved | Sort-Object UIDisplayName) + ($listTemplate | Sort-Object UIDisplayName))
}

function Get-HardwareState_CPPC {
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00"
    
    $e  = Get-UltixPowerAcIndex -SettingGuid '36687f9e-e3a5-4dbf-b1dc-15eb381c6863' -IncludeHidden
    $d  = Get-UltixPowerAcIndex -SettingGuid '4b92d758-5a24-4851-a470-815d78aee119' -IncludeHidden
    $pr = Get-UltixPowerAcIndex -SettingGuid '7b224883-b3cc-4d79-819f-8374152cbe7c' -IncludeHidden

    $dispE  = if ($null -ne $e)  { "$e%" }  else { "Unknown" }
    $dispD  = if ($null -ne $d)  { "$d%" }  else { "Unknown" }
    $dispPr = if ($null -ne $pr) { "$pr%" } else { "Unknown" }

    $rules = @(
        @{ KeyId = "EPP";     UIDisplayName = "Unhide: EPP [Current AC: $dispE]";          Path = "$basePath\36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        @{ KeyId = "Demote";  UIDisplayName = "Unhide: Idle Demote [Current AC: $dispD]";  Path = "$basePath\4b92d758-5a24-4851-a470-815d78aee119"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        @{ KeyId = "Promote"; UIDisplayName = "Unhide: Idle Promote [Current AC: $dispPr]"; Path = "$basePath\7b224883-b3cc-4d79-819f-8374152cbe7c"; Name = "Attributes"; Expected = 2; Type = "Registry" }
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($rule in $rules) {
        $isDetected = $true
        $val = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
        if ($null -ne $val -and $val -eq $rule.Expected) { $isDetected = $false }

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

function Get-HardwareState_IRQ {
    $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    [uint64]$core0Mask  = if ($coreMasks.Count -ge 1) { [uint64]$coreMasks[0] } else { 3 }
    [uint64]$core1Mask  = if ($coreMasks.Count -ge 2) { [uint64]$coreMasks[1] } else { 12 }
    
    $venKeys = Get-ChildItem -Path $pciPath -ErrorAction SilentlyContinue
    
    foreach ($ven in $venKeys) {
        $instances = Get-ChildItem -Path $ven.PSPath -ErrorAction SilentlyContinue
        
        foreach ($inst in $instances) {
            $irqMgmtPath  = "$($inst.PSPath)\Device Parameters\Interrupt Management"
            $msiPath      = "$irqMgmtPath\MessageSignaledInterruptProperties"
            $affinityPath = "$irqMgmtPath\Affinity Policy"
            
            if (Test-Path $msiPath) {
                $instProps = Get-ItemProperty -Path $inst.PSPath -Name "FriendlyName", "DeviceDesc", "Service", "Class" -ErrorAction SilentlyContinue
                $devName   = $instProps.FriendlyName
                if (-not $devName) { $devName = $instProps.DeviceDesc }
                if ($devName -match ";([^;]+)$") { $devName = $matches[1] }
                if (-not $devName) { $devName = "Unknown PCI Device" }

                $svcName  = [string]$instProps.Service
                $devClass = [string]$instProps.Class
                
                $msiVal = (Get-ItemProperty -Path $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
                $isMsiEnabled = ($msiVal -eq 1)

                $prioVal   = $null
                $policyVal = $null
                $maskBytes = $null
                if (Test-Path $affinityPath) {
                    $affProps  = Get-ItemProperty -Path $affinityPath -ErrorAction SilentlyContinue
                    if ($null -ne $affProps) {
                        $prioVal   = $affProps.InterruptPriority
                        $policyVal = $affProps.DevicePolicy
                        $maskBytes = $affProps.AssignmentSetOverride
                    }
                }

                $prioLabel = switch ($prioVal) {
                    1 { "Low" }
                    2 { "Normal" }
                    3 { "High" }
                    default { "Default" }
                }

                $affLabel = "Default"
                [uint64]$maskInt = 0
                if ($policyVal -eq 4 -and $null -ne $maskBytes -and $maskBytes.Length -ge 1) {
                    for ($b = 0; $b -lt [math]::Min(8, $maskBytes.Length); $b++) {
                        $maskInt = $maskInt -bor ([uint64]$maskBytes[$b] -shl ($b * 8))
                    }
                    $coreHint = if ($maskInt -eq $core1Mask) { " (C1)" } elseif (($maskInt -band $core0Mask) -ne 0) { " (C0)" } else { "" }
                    $affLabel = "0x$($maskInt.ToString('X'))$coreHint"
                } elseif ($policyVal -eq 5) {
                    $affLabel = "Spread"
                }

                $isOnCore0 = ($policyVal -ne 5) -and (($policyVal -ne 4) -or (($maskInt -band $core0Mask) -ne 0))
                $isGpu     = ($devClass -match '^(?i)Display$' -or $svcName -match '^(?i)(nvlddmkm|amdkmdag|amdwddmg|igfx)$' -or $devName -match '(?i)(GeForce|Radeon|Arc )')
                $isNic     = ($devClass -match '^(?i)Net$' -or $devName -match '(?i)(Ethernet|GbE|Network|Wi-Fi|Wireless|I225|I226|Killer|Realtek PCIe)')
                $isUsb     = ($devClass -match '^(?i)USB$' -or $svcName -match '^(?i)(USBXHCI|USB4|usbuhci|usbehci)$' -or $devName -match '(?i)(eXtensible Host|USB4)')
                $isStorage = ($policyVal -eq 5 -or $svcName -match '^(?i)(stornvme|secnvme|storahci|iaStor)' -or $devName -match '(?i)(NVM Express|SATA AHCI)')

                $sortRank      = 50
                $adviceText    = "Standard PCI Bus"
                $isRecommended = $false
                $drvTag        = if ($svcName) { "$svcName.sys" } else { "pci.sys" }

                if ($isGpu) {
                    if ($isOnCore0) {
                        $sortRank      = 1
                        $isRecommended = $true
                        $adviceText    = "★ OFFLOAD TO C1 (Heavy GPU DPC)"
                    } else {
                        $sortRank      = 10
                        $adviceText    = "✓ Offloaded ($affLabel)"
                    }
                } elseif ($isNic) {
                    if ($isOnCore0) {
                        $sortRank      = 2
                        $isRecommended = $true
                        $adviceText    = "★ OFFLOAD TO C1 (NDIS Network DPC)"
                    } else {
                        $sortRank      = 11
                        $adviceText    = "✓ Offloaded ($affLabel)"
                    }
                } elseif ($isUsb) {
                    if ($isOnCore0) {
                        $sortRank   = 3
                        $adviceText = "Optional C1 (USB HID Polling)"
                    } else {
                        $sortRank   = 12
                        $adviceText = "✓ Offloaded ($affLabel)"
                    }
                } elseif ($isStorage) {
                    $sortRank   = 40
                    $adviceText = "Keep Spread (Multi-Queue I/O)"
                }

                $msiBadge = if ($isMsiEnabled) { "ON" } else { "OFF" }

                $results.Add([PSCustomObject]@{
                    UIDisplayName        = "$devName [MSI: $msiBadge | Prio: $prioLabel | Mask: $affLabel | $adviceText]"
                    MsiStatus            = $msiBadge
                    RawDeviceName        = $devName
                    ServiceName          = $svcName
                    DriverTag            = $drvTag
                    PrioLabel            = $prioLabel
                    AffinityLabel        = $affLabel
                    AdviceText           = $adviceText
                    IsDetected           = $isMsiEnabled
                    IsRecommendedOffload = $isRecommended
                    SortRank             = $sortRank
                    Priority             = $prioVal
                    DevicePolicy         = $policyVal
                    ActionData           = @{
                        Path         = $msiPath
                        AffinityPath = $affinityPath
                        DevicePath   = $inst.PSPath
                    }
                })
            }
        }
    }
    
    return @($results | Sort-Object SortRank, RawDeviceName)
}

function Get-HardwareState_WHEA {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $nativeCores = @([WinUltix.CpuTopology]::GetProcessorCores())
    $smtEnabled = if ($nativeCores.Count -gt 0) { ([Environment]::ProcessorCount -gt $nativeCores.Count) } else { $true }

    try {
        if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }
        $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 500 -ErrorAction Stop)
        $totalEvents = $events.Count
        $idx = 0

        foreach ($evt in $events) {
            $idx++
            if ($null -ne $UltixSync -and $totalEvents -gt 0 -and ($idx % 10 -eq 0 -or $idx -eq $totalEvents)) {
                $UltixSync.Progress = 25 + [int](($idx / $totalEvents) * 75)
            }

            $apicId = "N/A"
            $coreInfo = ""
            $msg = $evt.Message
            $id = $evt.Id

            try {
                $xml = [xml]$evt.ToXml()
                $xmlApic = ($xml.Event.EventData.Data | Where-Object { $_.Name -match '^(APICId|ProcessorId)$' } | Select-Object -First 1).'#text'
                if ($xmlApic -match '^\d+$') { $apicId = $xmlApic }
                elseif ($xmlApic -match '^0x([0-9a-fA-F]+)$') { $apicId = [convert]::ToInt32($matches[1], 16).ToString() }
            } catch {}

            if ($apicId -eq "N/A" -and $msg -match "APIC ID:\s*(\d+)") { 
                $apicId = $matches[1]
            }

            if ($apicId -match '^\d+$') {
                $coreNum = if ($smtEnabled) { [math]::Floor([int]$apicId / 2) } else { [int]$apicId }
                $coreInfo = "(Core $coreNum)"
            }

            $humanReadable = "Unknown Hardware Error"
            if ($id -eq 18) { 
                $humanReadable = "[CPU] Cache/Core Error -> Vcore too low or Curve Optimizer too aggressive!" 
            } elseif ($id -eq 19) { 
                $humanReadable = "[IF/SoC] Interconnect Error -> FCLK unstable or VSOC/VDDG too low!" 
            } elseif ($id -eq 47) { 
                $humanReadable = "[RAM] Memory Controller -> tREFI/tRFC too tight or VDDQ too low!" 
            } else {
                if ($msg -match "Error Type:\s*(.+?)\r?\n") { $humanReadable = $matches[1] }
            }

            $time = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")

            $results.Add([PSCustomObject]@{
                UIDisplayName = "WHEA ID $id | APIC: $apicId"
                IsDetected    = $true
                Time          = $time
                EventID       = $id
                ApicID        = "$apicId $coreInfo".Trim()
                ErrorType     = $humanReadable
                RawMessage    = $msg
            })
        }
    } catch {}
    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-HardwareState_Network {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # 0. Global TCP/IP Stack Settings
    $globalOffload = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
    if ($globalOffload) {
        $isGlobalRssOpt = ($globalOffload.ReceiveSideScaling -eq 'Enabled')
        $results.Add([PSCustomObject]@{ UIDisplayName = "[Global] TCP Receive-Side Scaling (RSS)"; IsOptimized = $isGlobalRssOpt; ActionData = @{ Type="GlobalRSS" } })
        
        $isGlobalRscOpt = ($globalOffload.ReceiveSegmentCoalescing -eq 'Disabled')
        $results.Add([PSCustomObject]@{ UIDisplayName = "[Global] TCP Recv Segment Coalescing (RSC)"; IsOptimized = $isGlobalRscOpt; ActionData = @{ Type="GlobalRSC" } })
    }

    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
    $totalAdapters = [math]::Max(1, $adapters.Count)
    $adapterIdx = 0

    foreach ($adapter in $adapters) {
        $adapterIdx++
        $baseProg = 15 + [int]((($adapterIdx - 1) / $totalAdapters) * 80)
        if ($null -ne $UltixSync) { $UltixSync.Progress = $baseProg }

        $name = $adapter.Name
        $statusSuffix = if ($adapter.Status -ne 'Up') { " (Offline)" } else { "" }
        $adapterDispName = "$name$statusSuffix"
        
        # 1. TCP NoDelay & AckFrequency
        $tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
        $tcpNoDelay = (Get-ItemProperty -Path $tcpPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay
        $tcpAck = (Get-ItemProperty -Path $tcpPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency
        $isTcpOpt = ($tcpNoDelay -eq 1 -and $tcpAck -eq 1)
        $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] TCPNoDelay & AckFrequency"; IsOptimized = $isTcpOpt; ActionData = @{ Type="TCP"; AdapterName=$name; InterfaceGuid=$adapter.InterfaceGuid } })

        # 2. Power Management (Registry PnPCapabilities)
        $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnPDeviceID)"
        $caps = (Get-ItemProperty -Path $enumPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
        $isPowerOpt = ($caps -eq 24)
        $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Power Management (Sleep)"; IsOptimized = $isPowerOpt; ActionData = @{ Type="Power"; RegPath=$enumPath; InterfaceGuid=$adapter.InterfaceGuid } })

        # 3. NDIS Advanced Properties (Single CIM query per adapter + exact -eq match to prevent *EEE wildcard collisions)
        $ndisTweaks = [ordered]@{
            "*InterruptModeration" = @{ Opt = "0";    Def = "1" }
            "*FlowControl"         = @{ Opt = "0";    Def = "3" }
            "*JumboPacket"         = @{ Opt = "1514"; Def = "1514" }
            "*EEE"                 = @{ Opt = "0";    Def = "1" }
            "EEELinkAdvertisement" = @{ Opt = "0";    Def = "1" }
            "AdvancedEEE"          = @{ Opt = "0";    Def = "1" }
            "EnableGreenEthernet"  = @{ Opt = "0";    Def = "1" }
            "PowerSavingMode"      = @{ Opt = "0";    Def = "1" }
        }
        $allAdvProps = @(Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue)
        foreach ($key in $ndisTweaks.Keys) {
            $prop = $allAdvProps | Where-Object { $_.RegistryKeyword -eq $key } | Select-Object -First 1
            if ($null -ne $prop) {
                $optVal = $ndisTweaks[$key].Opt
                $defVal = $ndisTweaks[$key].Def
                $curVal = [string]($prop.RegistryValue | Select-Object -First 1)
                $isNdisOpt = ($curVal -eq $optVal)
                $propDispName = [string]$prop.DisplayName
                $results.Add([PSCustomObject]@{
                    UIDisplayName = "[$adapterDispName] NDIS: $propDispName"
                    IsOptimized   = $isNdisOpt
                    ActionData    = @{
                        Type          = "NDIS"
                        AdapterName   = $name
                        InterfaceGuid = $adapter.InterfaceGuid
                        Key           = $key
                        Value         = $optVal
                        DefaultValue  = $defVal
                    }
                })
            }
        }

        if ($null -ne $UltixSync) { $UltixSync.Progress = [math]::Min(95, $baseProg + 40) }

        # 4. Offloads & RSS
        $rss = Get-NetAdapterRss -Name $name -ErrorAction SilentlyContinue
        if ($rss) { 
            $isRssOpt = ([bool]$rss.Enabled -eq $true)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Receive Side Scaling (RSS)"; IsOptimized = $isRssOpt; ActionData = @{ Type="RSS"; AdapterName=$name } }) 
        }

        $rsc = Get-NetAdapterRsc -Name $name -ErrorAction SilentlyContinue
        if ($rsc) { 
            $isRscOpt = ([bool]$rsc.IPv4Enabled -eq $false)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Recv Segment Coalescing (RSC)"; IsOptimized = $isRscOpt; ActionData = @{ Type="RSC"; AdapterName=$name } }) 
        }

        $lso = Get-NetAdapterLso -Name $name -ErrorAction SilentlyContinue
        if ($lso) { 
            $isLsoOpt = ([bool]$lso.IPv4Enabled -eq $false)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Large Send Offload (LSO)"; IsOptimized = $isLsoOpt; ActionData = @{ Type="LSO"; AdapterName=$name } }) 
        }

        $cso = Get-NetAdapterChecksumOffload -Name $name -ErrorAction SilentlyContinue
        if ($cso) { 
            $isCsoOpt = ([bool]$cso.IpIPv4Enabled -eq $true -and [bool]$cso.TcpIPv4Enabled -eq $true)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Checksum Offload (CSO)"; IsOptimized = $isCsoOpt; ActionData = @{ Type="CSO"; AdapterName=$name } }) 
        }
    }
    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-HardwareState_Timer {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $val = (Get-ItemProperty -Path $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
    $isGlobalOpt = ($null -ne $val -and $val -eq 1)
    $results.Add([PSCustomObject]@{ UIDisplayName = "Global Timer Resolution (Kernel Fix)"; IsOptimized = $isGlobalOpt; ActionData = @{ Type="Reg"; Path=$regPath; Name="GlobalTimerResolutionRequests"; Value=1 } })
    
    $hpet = Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "PNP0103" }
    if ($null -ne $hpet) {
        $isHpetDisabled = ($hpet.ConfigManagerErrorCode -eq 22)
        $results.Add([PSCustomObject]@{ UIDisplayName = "Disable HPET (Device Manager)"; IsOptimized = $isHpetDisabled; ActionData = @{ Type="PNP"; Instance=$hpet.InstanceId } })
    }

    $bcd = (bcdedit.exe /enum "{current}" 2>$null) -join " "
    
    $dynTickOpt = ($bcd -match "(?i)disabledynamictick\s+(Yes|Tak|True|1)")
    $results.Add([PSCustomObject]@{ UIDisplayName = "Disable Dynamic Tick (Power Saving)"; IsOptimized = $dynTickOpt; ActionData = @{ Type="BCD"; Cmd="disabledynamictick yes" } })
    
    $platClockOpt = ($bcd -match "(?i)useplatformclock\s+(No|Nie|False|0)")
    $results.Add([PSCustomObject]@{ UIDisplayName = "Disable Platform Clock (Force TSC)"; IsOptimized = $platClockOpt; ActionData = @{ Type="BCD"; Cmd="useplatformclock no" } })
	
    return @($results)
}

function Get-CurrentTimerResolution {
    $data = [WinUltix.NtDll]::GetTimerData()
    return [PSCustomObject]@{
        DefaultMs = [math]::Round($data[0] / 10000.0, 4)
        LimitMs   = [math]::Round($data[1] / 10000.0, 4)
        CurrentMs = [math]::Round($data[2] / 10000.0, 4)
    }
}

function Get-HardwareState_NVMe {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters"
    $aspm = (Get-ItemProperty -Path $pciPath -Name "DisableASPM" -ErrorAction SilentlyContinue).DisableASPM
    $isAspmOpt = ($null -ne $aspm -and $aspm -eq 1)
    $results.Add([PSCustomObject]@{ UIDisplayName = "PCIe ASPM Global Bus Lock (DisableASPM)"; IsOptimized = $isAspmOpt; ActionData = @{ Type="Reg"; Path=$pciPath; Name="DisableASPM"; Val=1 } })

    $nvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
    $nvmeIdle = (Get-ItemProperty -Path $nvmePath -Name "IdlePowerMode" -ErrorAction SilentlyContinue).IdlePowerMode
    $isNvmeIdleOpt = ($null -ne $nvmeIdle -and $nvmeIdle -eq 0)
    $results.Add([PSCustomObject]@{ UIDisplayName = "StorNVMe APST Driver Lock (IdlePowerMode)"; IsOptimized = $isNvmeIdleOpt; ActionData = @{ Type="Reg"; Path=$nvmePath; Name="IdlePowerMode"; Val=0 } })

    $mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
    $isMemOpt = ($null -ne $mmAgent -and $mmAgent.MemoryCompression -eq $false)
    $results.Add([PSCustomObject]@{ UIDisplayName = "System Memory Compression (MMAgent)"; IsOptimized = $isMemOpt; ActionData = @{ Type="MMAgent" } })

    return @($results)
}

# ------------------------------------------
# Z7: HARDWARE & DIAGNOSTICS ENGINE
# ------------------------------------------
function Set-AppAffinity {
    param([array]$SelectedItems, [bool]$Execute = $true)
    if ($SelectedItems.Count -eq 0) { return }

    $topo = Get-CPUTopologyProfile
    $targetMask = $topo.Mask

    $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
    if (-not (Test-Path $configPath)) { New-Item -Path $configPath -Force -ErrorAction SilentlyContinue | Out-Null }

    foreach ($item in $SelectedItems) {
        $exeName = $item.ActionData.ExeName
        $procName = $item.ActionData.ProcName
        
        Set-ItemProperty -Path $configPath -Name $exeName -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

        if ($Execute) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) {
                Write-GUI " -> Live Locking ($($topo.CoreDesc)): $exeName ($($procs.Count) instances)"
                foreach ($p in $procs) {
                    try { 
                        $p.ProcessorAffinity = $targetMask 
                        $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                    } catch { Write-GUI "    [!] Access denied: PID $($p.Id) (System lock)" }
                }
            } else { Write-GUI " -> Saved to config (Currently not running): $exeName" }
        } else { Write-GUI " -> Saved to Target Roster: $exeName" }
    }
}

function Remove-AppAffinity {
    param([array]$SelectedItems, [bool]$Execute = $true, [bool]$KeepConfig = $false)
    if ($SelectedItems.Count -eq 0) { return }

    $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
    $lpCount = [Environment]::ProcessorCount
    $fullMaskVal = if ($lpCount -ge 64) { -1 } else { ([int64]1 -shl $lpCount) - 1 }
    $systemAffinity = [System.IntPtr]$fullMaskVal

    foreach ($item in $SelectedItems) {
        $exeName = $item.ActionData.ExeName
        $procName = $item.ActionData.ProcName
        
        if (-not $KeepConfig -and (Test-Path $configPath)) { 
            Remove-ItemProperty -Path $configPath -Name $exeName -ErrorAction SilentlyContinue 
        }

        if ($Execute) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) {
                $needsUnlock = $false
                foreach ($p in $procs) {
                    try {
                        if ($p.ProcessorAffinity -ne $systemAffinity -or $p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::Normal) {
                            $needsUnlock = $true
                            break
                        }
                    } catch {}
                }

                if ($needsUnlock) {
                    Write-GUI " -> Releasing CPU Restraints: $exeName"
                    foreach ($p in $procs) { 
                        try { 
                            $p.ProcessorAffinity = $systemAffinity 
                            $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
                        } catch { } 
                    }
                }
            }
        } else { 
            if (-not $KeepConfig) { Write-GUI " -> Removed from Target Roster: $exeName" }
        }
    }
}

function Invoke-ApplyCPPC {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> CPPC settings are already fully unhidden."; return }

    foreach ($item in $SelectedItems) {
        $rule = $item.ActionData
        Write-GUI " -> Unlocking Visibility: $($rule.UIDisplayName)"
        try {
            Set-ItemProperty -Path $rule.Path -Name $rule.Name -Value $rule.Expected -Type DWord -Force -ErrorAction Stop | Out-Null
        } catch { Write-GUI "    [!] Failed to unhide: $($rule.UIDisplayName)" }
    }
}

function Set-UltixCPPCState {
    param([Parameter(Mandatory=$true)][ValidateSet('Engage', 'Release')][string]$Mode)
    $p = 'HKLM:\SOFTWARE\WinUltix\CPPC'

    if ($Mode -eq 'Engage') {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        $e  = Get-UltixPowerAcIndex -SettingGuid '36687f9e-e3a5-4dbf-b1dc-15eb381c6863' -IncludeHidden
        $d  = Get-UltixPowerAcIndex -SettingGuid '4b92d758-5a24-4851-a470-815d78aee119' -IncludeHidden
        $pr = Get-UltixPowerAcIndex -SettingGuid '7b224883-b3cc-4d79-819f-8374152cbe7c' -IncludeHidden

        # Only archive when current values are neither already Engaged (0/100/100) nor corrupted all-zeros (0/0/0)
        if ($null -ne $e -and -not ($e -eq 0 -and $d -eq 100 -and $pr -eq 100) -and -not ($e -eq 0 -and $d -eq 0 -and $pr -eq 0)) {
            Set-ItemProperty -Path $p -Name 'EPP' -Value $e -Type DWord -Force
            Set-ItemProperty -Path $p -Name 'Demote' -Value $d -Type DWord -Force
            Set-ItemProperty -Path $p -Name 'Promote' -Value $pr -Type DWord -Force
        }

        $tsCmd = "`$p='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path `$p){ `$r=Get-ItemProperty `$p; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
        $tsAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$tsCmd`""
        $tsTriggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogon))
        $tsPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Action $tsAction -Trigger $tsTriggers -Principal $tsPrincipal -Force | Out-Null

        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100
        powercfg.exe /setactive SCHEME_CURRENT
        Write-GUI " -> Engaged Max CPPC (EPP 0%, Demote/Promote 100%). Dead Man's Switch armed."
    } else {
        $e = 50; $d = 40; $pr = 60
        if (Test-Path $p) {
            $reg = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($null -ne $reg.EPP -and $null -ne $reg.Demote -and $null -ne $reg.Promote) {
                # Self-heal if previous regex bug stored 0/0/0 into backup key
                if ($reg.EPP -eq 0 -and $reg.Demote -eq 0 -and $reg.Promote -eq 0) {
                    Remove-ItemProperty -Path $p -Name 'EPP', 'Demote', 'Promote' -Force -ErrorAction SilentlyContinue
                } else {
                    $e  = $reg.EPP
                    $d  = $reg.Demote
                    $pr = $reg.Promote
                }
            }
        }
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $e; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $e
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 $d; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 $d
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c $pr; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c $pr
        powercfg.exe /setactive SCHEME_CURRENT
        
        Unregister-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-GUI " -> Released CPPC lock (Restored EPP: $e%, Demote: $d%, Promote: $pr%). Failsafe disarmed."
    }
}

function Clear-WHEALogs {
    Write-GUI " -> Clearing System Event Log (WHEA Records)..."
    try {
        & wevtutil.exe cl System 2>$null
        Write-GUI "    [OK] System log successfully wiped."
    } catch { 
        Write-GUI "    [!] Failed to clear System log. Administrator privileges missing?" 
    }
}

function Update-NetworkModalList {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Modal,
        [Parameter(Mandatory=$true)][System.Windows.Forms.CheckedListBox]$ChkList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Collections.ArrayList]$LocalData,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable
    )

    if ($Modal.IsDisposed -or $ChkList.IsDisposed) { return }

    $uiModal     = $Modal
    $uiChkList   = $ChkList
    $uiLocalData = $LocalData

    $uiChkList.Items.Clear()
    $uiLocalData.Clear()
    [void]$uiChkList.Items.Add("Scanning physical adapters & NDIS properties in background...", $false)

    $sb = (Get-Command -Name Get-HardwareState_Network).ScriptBlock
    Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $ControlsToDisable -OnComplete ({
        param($output)
        Update-Progress 0
        if ($null -eq $uiModal -or $uiModal.IsDisposed -or $null -eq $uiChkList -or $uiChkList.IsDisposed) { return }

        $uiChkList.BeginUpdate()
        $uiChkList.Items.Clear()
        $uiLocalData.Clear()
        [array]$auditData = @($output | Where-Object { $null -ne $_ })

        foreach ($item in $auditData) {
            [void]$uiLocalData.Add($item)
            if ($item.IsOptimized) {
                [void]$uiChkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false)
            } else {
                [void]$uiChkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true)
            }
        }
        $uiChkList.EndUpdate()
    }.GetNewClosure())
}

function Start-NetworkOptimizationAsync {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Mode = 'Apply',
        [Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Modal,
        [Parameter(Mandatory=$true)][System.Windows.Forms.CheckedListBox]$ChkList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Collections.ArrayList]$LocalData,
        [AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    if ($SelectedItems.Count -eq 0) {
        Write-GUI " -> No network items selected."
        return
    }

    $uiModal     = $Modal
    $uiChkList   = $ChkList
    $uiLocalData = $LocalData
    $uiButtons   = $ControlsToDisable
    $verb        = if ($Mode -eq 'Apply') { "Optimization" } else { "Revert" }

    Write-GUI " -> Dispatching network adapter $verb worker to background Runspace..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $uiButtons -Arguments @($SelectedItems, $Mode) -ScriptBlock {
        param([array]$Items, [string]$Operation)

        $total = $Items.Count
        $current = 0
        $backupRoot = "HKLM:\SOFTWARE\WinUltix\Network_Backup"

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 80)
            }

            $data = $item.ActionData
            $name = if ($data.ContainsKey("AdapterName")) { $data.AdapterName } elseif ($null -ne $data.Adapter) { $data.Adapter.Name } else { "" }
            $guid = if ($data.ContainsKey("InterfaceGuid")) { $data.InterfaceGuid } elseif ($null -ne $data.Adapter) { $data.Adapter.InterfaceGuid } else { "Global" }
            $bKey = "$backupRoot\$guid"

            if ($Operation -eq 'Apply') {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> Optimizing: $($item.UIDisplayName)") }
                try {
                    switch ($data.Type) {
                        "GlobalRSS" { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction Stop }
                        "GlobalRSC" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction Stop }
                        "TCP" {
                            $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
                            New-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null
                            New-ItemProperty -Path $path -Name "TCPNoDelay" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null 
                        }
                        "Power" {
                            if (-not (Test-Path -LiteralPath $bKey)) { New-Item -Path $bKey -Force | Out-Null }
                            if ($null -eq (Get-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities) {
                                $oldPnp = (Get-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
                                if ($null -eq $oldPnp) { $oldPnp = -1 }
                                Set-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -Value $oldPnp -Type DWord -Force
                            }
                            Set-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Value 24 -Type DWord -Force -ErrorAction Stop
                        }
                        "NDIS" {
                            if (-not (Test-Path -LiteralPath $bKey)) { New-Item -Path $bKey -Force | Out-Null }
                            $targetProp = Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue |
                                Where-Object { $_.RegistryKeyword -eq $data.Key } |
                                Select-Object -First 1

                            if ($null -ne $targetProp) {
                                $curVal = [string]($targetProp.RegistryValue | Select-Object -First 1)
                                if ($null -eq (Get-ItemProperty -LiteralPath $bKey -Name $data.Key -ErrorAction SilentlyContinue).$($data.Key)) {
                                    if (-not [string]::IsNullOrWhiteSpace($curVal)) {
                                        Set-ItemProperty -LiteralPath $bKey -Name $data.Key -Value $curVal -Type String -Force
                                    }
                                }
                                $targetProp | Set-NetAdapterAdvancedProperty -RegistryValue $data.Value -NoRestart -ErrorAction Stop
                            }
                        }
                        "RSS"  { Enable-NetAdapterRss -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "RSC"  { Disable-NetAdapterRsc -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "LSO"  { Disable-NetAdapterLso -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "CSO"  { Enable-NetAdapterChecksumOffload -Name $name -IpIPv4 -TcpIPv4 -UdpIPv4 -NoRestart -ErrorAction SilentlyContinue }
                    }
                } catch {
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Failed to apply: $($item.UIDisplayName) ($($_.Exception.Message))") }
                }
            } else {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> Reverting to Default: $($item.UIDisplayName)") }
                try {
                    switch ($data.Type) {
                        "GlobalRSS" { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction Stop }
                        "GlobalRSC" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -ErrorAction Stop }
                        "TCP" {
                            $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
                            Remove-ItemProperty -Path $path -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -Path $path -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
                        }
                        "Power" {
                            $oldPnp = (Get-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
                            if ($null -ne $oldPnp) {
                                if ($oldPnp -eq -1 -or $oldPnp -eq 4294967295) {
                                    Remove-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Force -ErrorAction SilentlyContinue
                                } else {
                                    Set-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Value $oldPnp -Type DWord -Force -ErrorAction SilentlyContinue
                                }
                                Remove-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -Force -ErrorAction SilentlyContinue
                            } else {
                                Set-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            }
                        }
                        "NDIS" {
                            $savedVal = (Get-ItemProperty -LiteralPath $bKey -Name $data.Key -ErrorAction SilentlyContinue).$($data.Key)
                            $targetVal = if (-not [string]::IsNullOrWhiteSpace($savedVal)) { $savedVal } else { $data.DefaultValue }
                            $targetProp = Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue |
                                Where-Object { $_.RegistryKeyword -eq $data.Key } |
                                Select-Object -First 1

                            if ($null -ne $targetProp) {
                                $targetProp | Set-NetAdapterAdvancedProperty -RegistryValue $targetVal -NoRestart -ErrorAction Stop
                            }
                            if (Test-Path -LiteralPath $bKey) {
                                Remove-ItemProperty -LiteralPath $bKey -Name $data.Key -Force -ErrorAction SilentlyContinue
                            }
                        }
                        "RSS"  { Enable-NetAdapterRss -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "RSC"  { Enable-NetAdapterRsc -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "LSO"  { Enable-NetAdapterLso -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "CSO"  { Enable-NetAdapterChecksumOffload -Name $name -IpIPv4 -TcpIPv4 -UdpIPv4 -NoRestart -ErrorAction SilentlyContinue }
                    }
                } catch {
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Failed to revert: $($item.UIDisplayName) ($($_.Exception.Message))") }
                }
            }
        }

        $touchedAdapters = @($Items | ForEach-Object { $_.ActionData.AdapterName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        foreach ($aName in $touchedAdapters) {
            Restart-NetAdapter -Name $aName -ErrorAction SilentlyContinue
        }

        if ($null -ne $UltixSync) {
            $UltixSync.Logs.Enqueue(" -> Waiting for NDIS adapter re-initialization (2s)...")
            $UltixSync.Progress = 95
        }
        Start-Sleep -Seconds 2
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    } -OnComplete ({
        Update-Progress 0
        Write-GUI " -> Network adapter $verb completed.`n"
        Update-NetworkModalList -Modal $uiModal -ChkList $uiChkList -LocalData $uiLocalData -ControlsToDisable $uiButtons
    }.GetNewClosure())
}

function Invoke-ApplyTimerTweaks {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No Timer modifications selected."; return }

    foreach ($item in $SelectedItems) {
        $data = $item.ActionData
        Write-GUI " -> Configuring Timer Subsystem: $($item.UIDisplayName)"
        
        try {
            if ($data.Type -eq "Reg") {
                if (-not (Test-Path $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $data.Path -Name $data.Name -Value $data.Value -Type DWord -Force -ErrorAction Stop
            } elseif ($data.Type -eq "BCD") {
                $cmdArgs = $data.Cmd.Split(' ')
                Start-Process -FilePath "bcdedit.exe" -ArgumentList "/set `{current`} $($cmdArgs[0]) $($cmdArgs[1])" -NoNewWindow -Wait
            } elseif ($data.Type -eq "PNP") {
                Disable-PnpDevice -InstanceId $data.Instance -Confirm:$false -ErrorAction Stop
            }
        } catch { Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)" }
    }
}

function Invoke-ApplyNVMeTweaks {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No I/O or Memory modifications selected."; return }

    foreach ($item in $SelectedItems) {
        $data = $item.ActionData
        Write-GUI " -> Configuring Subsystem: $($item.UIDisplayName)"
        
        try {
            if ($data.Type -eq "Reg") {
                if (-not (Test-Path $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $data.Path -Name $data.Name -Value $data.Val -Type DWord -Force -ErrorAction Stop
            } elseif ($data.Type -eq "MMAgent") {
                Disable-MMAgent -MemoryCompression -ErrorAction Stop
            }
        } catch { 
            Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)"
            Write-GUI "    [DEBUG] $($_.Exception.Message)"
        }
    }
}

# ------------------------------------------
# Z7: PROFILE SNAPSHOT INTEGRATION (EXPORT / IMPORT)
# ------------------------------------------
function Export-UltixHardwareSnapshot {
    $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
    $affinityRoster = if (Test-Path $affPath) {
        @((Get-ItemProperty -Path $affPath -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object { $_.Name -match '\.exe$' } |
            Select-Object -ExpandProperty Name)
    } else { @() }

    $cppcUnhidden = @(Get-HardwareState_CPPC | Where-Object { -not $_.IsDetected } | ForEach-Object { $_.ActionData.KeyId })
    $timerTweaks  = @(Get-HardwareState_Timer | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)
    $nvmeTweaks   = @(Get-HardwareState_NVMe  | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)

    $globalNet = [System.Collections.Generic.List[string]]::new()
    $globalOffload = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
    if ($null -ne $globalOffload) {
        if ($globalOffload.ReceiveSideScaling -eq 'Enabled')         { $globalNet.Add("[Global] TCP Receive-Side Scaling (RSS)") }
        if ($globalOffload.ReceiveSegmentCoalescing -eq 'Disabled')  { $globalNet.Add("[Global] TCP Recv Segment Coalescing (RSC)") }
    }

    return [ordered]@{
        AffinityLasso = @($affinityRoster)
        CPPCUnhidden  = @($cppcUnhidden)
        TimerTweaks   = @($timerTweaks)
        NVMeTweaks    = @($nvmeTweaks)
        GlobalNetwork = @($globalNet)
    }
}

function Import-UltixHardwareSnapshot {
    param([Parameter(Mandatory=$true)]$ProfileData)

    $affList = @($ProfileData.AffinityLasso)
    if ($affList.Count -gt 0) {
        $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
        if (-not (Test-Path $affPath)) { New-Item -Path $affPath -Force | Out-Null }
        foreach ($exe in $affList) {
            Set-ItemProperty -Path $affPath -Name $exe -Value 1 -Type DWord -Force
        }
        Write-GUI " -> Restored $($affList.Count) process(es) to Affinity Lasso roster."
    }

    $hwLocks = $ProfileData.HardwareLocks
    if ($null -eq $hwLocks) { return }

    if (@($hwLocks.CPPCUnhidden).Count -gt 0) {
        $cppcSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($k in $hwLocks.CPPCUnhidden) { [void]$cppcSet.Add([string]$k) }
        $toUnhide = @(Get-HardwareState_CPPC | Where-Object { $cppcSet.Contains($_.ActionData.KeyId) -and $_.IsDetected })
        if ($toUnhide.Count -gt 0) { Invoke-ApplyCPPC -SelectedItems $toUnhide }
    }

    if (@($hwLocks.TimerTweaks).Count -gt 0) {
        $timerSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $hwLocks.TimerTweaks) { [void]$timerSet.Add([string]$t) }
        $toApplyTimer = @(Get-HardwareState_Timer | Where-Object { $timerSet.Contains($_.UIDisplayName) -and -not $_.IsOptimized })
        if ($toApplyTimer.Count -gt 0) { Invoke-ApplyTimerTweaks -SelectedItems $toApplyTimer }
    }

    if (@($hwLocks.NVMeTweaks).Count -gt 0) {
        $nvmeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($n in $hwLocks.NVMeTweaks) { [void]$nvmeSet.Add([string]$n) }
        $toApplyNvme = @(Get-HardwareState_NVMe | Where-Object { $nvmeSet.Contains($_.UIDisplayName) -and -not $_.IsOptimized })
        if ($toApplyNvme.Count -gt 0) { Invoke-ApplyNVMeTweaks -SelectedItems $toApplyNvme }
    }

    if (@($hwLocks.GlobalNetwork).Count -gt 0) {
        foreach ($gNet in $hwLocks.GlobalNetwork) {
            if ($gNet -match "RSS") { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction SilentlyContinue }
            if ($gNet -match "RSC") { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction SilentlyContinue }
        }
        Write-GUI " -> Enforced Global TCP RSS/RSC offload profile."
    }
}

# ------------------------------------------
# Z7: DEDICATED HARDWARE MODALS
# ------------------------------------------
function Show-AffinityModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 720); $modal.MinimumSize = New-Object System.Drawing.Size(850, 720); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh List" -X 715 -Y 15 -Width 100 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView; $listView.Location = New-Object System.Drawing.Point(15, 60); $listView.Size = New-Object System.Drawing.Size(800, 480); $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $listView.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $listView.Font = New-Object System.Drawing.Font("Consolas", 11.5)
    $listView.Anchor = 'Top, Bottom, Left, Right'
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true; $listView.FullRowSelect = $true; $listView.GridLines = $true
    Enable-UltixDoubleBuffer -Control $listView

    $listView.Columns.Add("Status & App Name", 250) | Out-Null
    $listView.Columns.Add("Priority", 110) | Out-Null
    $listView.Columns.Add("Executable Path", 410) | Out-Null
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $listView.BeginUpdate()
        $listView.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_Affinity
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            $lvItem = New-Object System.Windows.Forms.ListViewItem($item.UIDisplayName)
            $lvItem.SubItems.Add($item.Priority)
            $lvItem.SubItems.Add($item.Path)
            $lvItem.Checked = $item.IsDetected
            [void]$listView.Items.Add($lvItem)
        }
        $listView.EndUpdate()
    }
    &$refreshData
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $txtCustom = New-Object System.Windows.Forms.TextBox; $txtCustom.Location = New-Object System.Drawing.Point(15, 555); $txtCustom.Size = New-Object System.Drawing.Size(250, 25); $txtCustom.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $txtCustom.ForeColor = [System.Drawing.Color]::White; $txtCustom.Font = New-Object System.Drawing.Font("Segoe UI", 10); $txtCustom.Anchor = 'Bottom, Left'
    $btnAddExe = New-UltixButton -Parent $modal -Text "+ Add Custom .exe" -X 275 -Y 554 -Width 140 -Height 27 -RGB @(60, 60, 60)
    $btnAddExe.Anchor = 'Bottom, Left'
    $btnAddExe.Add_Click({
        $exe = $txtCustom.Text.Trim()
        if ($exe -ne "" -and $exe -match "\.exe$") {
            $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
            if (-not (Test-Path $configPath)) { New-Item -Path $configPath -Force | Out-Null }
            Set-ItemProperty -Path $configPath -Name $exe -Value 1 -Type DWord -Force | Out-Null
            $txtCustom.Text = ""
            &$refreshData 
        } else { [System.Windows.Forms.MessageBox]::Show("Process must end with .exe", "Invalid Input") }
    }.GetNewClosure())

    $btnDelExe = New-UltixButton -Parent $modal -Text "- Remove Selected" -X 425 -Y 554 -Width 140 -Height 27 -RGB @(100, 60, 60)
    $btnDelExe.Anchor = 'Bottom, Left'
    $btnDelExe.Add_Click({
        $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
        $removed = 0
        foreach ($item in $listView.SelectedItems) {
            $exe = $localData[$item.Index].ActionData.ExeName
            if (Test-Path $configPath) {
                Remove-ItemProperty -Path $configPath -Name $exe -ErrorAction SilentlyContinue | Out-Null
                $removed++
            }
        }
        if ($removed -gt 0) { &$refreshData }
    }.GetNewClosure())

    $getDelta = {
        $apply = @(); $remove = @()
        for ($i = 0; $i -lt $listView.Items.Count; $i++) {
            $item = $localData[$i]
            $wasChecked = $item.IsDetected
            $isChecked = $listView.Items[$i].Checked
            if ($isChecked -and -not $wasChecked) { $apply += $item } elseif (-not $isChecked -and $wasChecked) { $remove += $item }
        }
        return @{ Apply = $apply; Remove = $remove }
    }

    $btnSave = New-UltixButton -Parent $modal -Text "Save Roster" -X 15 -Y 595 -Width 150 -Height 35 -RGB @(60, 100, 150)
    $btnSave.Anchor = 'Bottom, Left'
    $btnSave.Add_Click({
        $delta = &$getDelta
        if ($delta.Apply.Count -gt 0) { Set-AppAffinity -SelectedItems $delta.Apply -Execute $false }
        if ($delta.Remove.Count -gt 0) { Remove-AppAffinity -SelectedItems $delta.Remove -Execute $false -KeepConfig $false }
        &$refreshData
    }.GetNewClosure())

    $btnEngage = New-UltixButton -Parent $modal -Text "ENGAGE (Lock)" -X 175 -Y 595 -Width 150 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $delta = &$getDelta
        if ($delta.Apply.Count -gt 0) { Set-AppAffinity -SelectedItems $delta.Apply -Execute $true }
        if ($delta.Remove.Count -gt 0) { Remove-AppAffinity -SelectedItems $delta.Remove -Execute $true -KeepConfig $false }
        
        $allItems = @()
        for ($i = 0; $i -lt $listView.Items.Count; $i++) { if ($listView.Items[$i].Checked) { $allItems += $localData[$i] } }
        if ($allItems.Count -gt 0) { Set-AppAffinity -SelectedItems $allItems -Execute $true }
        &$refreshData 
    }.GetNewClosure())

    $btnRelease = New-UltixButton -Parent $modal -Text "RELEASE (Unlock)" -X 335 -Y 595 -Width 150 -Height 35 -RGB @(150, 100, 60)
    $btnRelease.Anchor = 'Bottom, Left'
    $btnRelease.Add_Click({
        Remove-AppAffinity -SelectedItems $localData -Execute $true -KeepConfig $true
        &$refreshData 
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 495 -Y 595 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $lblTip = New-Object System.Windows.Forms.Label
    $lblTip.Text = "INFO: 'Save Roster' stores your preset in the registry. You can instantly apply it later before gaming using the 'Pre-Flight' desktop shortcut."
    $lblTip.Location = New-Object System.Drawing.Point(15, 640)
    $lblTip.Size = New-Object System.Drawing.Size(800, 25)
    $lblTip.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblTip.ForeColor = [System.Drawing.Color]::DarkGray
    $lblTip.Anchor = 'Bottom, Left'

    $modal.Controls.AddRange(@($lblDesc, $listView, $txtCustom, $lblTip))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-CPPCModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 450); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 450)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 60); $chkList.Size = New-Object System.Drawing.Size(600, 280); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightGreen; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_CPPC
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if (-not $item.IsDetected) {
                [void]$chkList.Items.Add("[ UNHIDDEN ] " + $item.UIDisplayName, $false)
            } else {
                [void]$chkList.Items.Add("[ HIDDEN ]   " + $item.UIDisplayName, $true)
            }
        }
    }
    &$refreshData 

    $btnUnhide = New-UltixButton -Parent $modal -Text "Unhide Checked" -X 15 -Y 355 -Width 120 -Height 35 -RGB @(60, 100, 150)
    $btnUnhide.Anchor = 'Bottom, Left'
    $btnUnhide.Add_Click({
        $toUnhide = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $toUnhide += $localData[$i] }
        }
        if ($toUnhide.Count -gt 0) { Invoke-ApplyCPPC -SelectedItems $toUnhide }
        &$refreshData 
    }.GetNewClosure())

    $btnEngage = New-UltixButton -Parent $modal -Text "ENGAGE Max CPPC" -X 145 -Y 355 -Width 150 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        Set-UltixCPPCState -Mode 'Engage'
        &$refreshData
    }.GetNewClosure())

    $btnRelease = New-UltixButton -Parent $modal -Text "RELEASE CPPC" -X 305 -Y 355 -Width 130 -Height 35 -RGB @(150, 100, 60)
    $btnRelease.Anchor = 'Bottom, Left'
    $btnRelease.Add_Click({
        Set-UltixCPPCState -Mode 'Release'
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 445 -Y 355 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $chkList))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-MsiModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(920, 660); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(880, 620)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 10); $lblDesc.Size = New-Object System.Drawing.Size(875, 24); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply new MSI vectors, Interrupt Priority, and Core Affinity."; $lblWarning.Location = New-Object System.Drawing.Point(15, 36); $lblWarning.Size = New-Object System.Drawing.Size(875, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $lblDpcMonitor = New-Object System.Windows.Forms.Label
    $lblDpcMonitor.Location = New-Object System.Drawing.Point(15, 60)
    $lblDpcMonitor.Size = New-Object System.Drawing.Size(875, 68)
    $lblDpcMonitor.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblDpcMonitor.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $lblDpcMonitor.Font = New-Object System.Drawing.Font("Consolas", 9.2, [System.Drawing.FontStyle]::Bold)
    $lblDpcMonitor.TextAlign = "TopLeft"
    $lblDpcMonitor.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 4)
    $lblDpcMonitor.BorderStyle = "FixedSingle"
    $lblDpcMonitor.Anchor = 'Top, Left, Right'

    $lblDpcLegend = New-Object System.Windows.Forms.Label
    $lblDpcLegend.Text = "Legend: C0..Cn = Physical Cores (SMT: C0=LP#0-1, C1=LP#2-3) | Green (<30% C0 Optimal), Yellow (30-54%), Red (>=55% C0 Bottleneck - Offload ★ items)"
    $lblDpcLegend.Location = New-Object System.Drawing.Point(15, 131)
    $lblDpcLegend.Size = New-Object System.Drawing.Size(875, 18)
    $lblDpcLegend.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
    $lblDpcLegend.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDpcLegend.Anchor = 'Top, Left, Right'

    $dpcState = @{ PrevCounts = $null; IsRunning = $true; LastSnap = $null }
    Update-UltixDpcMonitorUI -TargetLabel $lblDpcMonitor -State $dpcState

    $dpcTimer = New-Object System.Windows.Forms.Timer
    $dpcTimer.Interval = 1000
    $dpcTimer.Tag = @{
        Modal = $modal
        Label = $lblDpcMonitor
        State = $dpcState
    }
    $dpcTimer.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Modal.IsDisposed -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        Update-UltixDpcMonitorUI -TargetLabel $ctx.Label -State $ctx.State
    })
    $dpcTimer.Start()

    $lblPrio = New-Object System.Windows.Forms.Label
    $lblPrio.Text = "Interrupt Priority:"
    $lblPrio.Location = New-Object System.Drawing.Point(15, 156)
    $lblPrio.Size = New-Object System.Drawing.Size(112, 22)
    $lblPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $lblPrio.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $comboPrio = New-Object System.Windows.Forms.ComboBox
    $comboPrio.Location = New-Object System.Drawing.Point(128, 153)
    $comboPrio.Size = New-Object System.Drawing.Size(165, 25)
    $comboPrio.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $comboPrio.ForeColor = [System.Drawing.Color]::White
    $comboPrio.DropDownStyle = "DropDownList"
    $comboPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    [void]$comboPrio.Items.AddRange(@("Keep Current", "High (3)", "Normal (2)", "Low (1)", "Undefined (Default)"))
    $comboPrio.SelectedIndex = 0

    $chkOffloadCore0 = New-Object System.Windows.Forms.CheckBox
    $chkOffloadCore0.Text = "Offload IRQ from Core 0 (Pin to Secondary Core C1)"
    $chkOffloadCore0.Location = New-Object System.Drawing.Point(305, 154)
    $chkOffloadCore0.Size = New-Object System.Drawing.Size(340, 24)
    $chkOffloadCore0.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $chkOffloadCore0.ForeColor = [System.Drawing.Color]::LightGray
    $chkOffloadCore0.Checked = $false

    $btnSelRec = New-UltixButton -Parent $modal -Text "Select ★ GPU/NIC" -X 695 -Y 152 -Width 195 -Height 27 -RGB @(50, 85, 120)
    $btnSelRec.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $btnSelRec.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 186)
    $listView.Size = New-Object System.Drawing.Size(875, 355)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 42, 42, 42)
    $listView.ForeColor = [System.Drawing.Color]::LightGreen
    $listView.Font = New-Object System.Drawing.Font("Consolas", 9.8)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.Anchor = 'Top, Bottom, Left, Right'
    Enable-UltixDoubleBuffer -Control $listView

    $sorter = New-Object WinUltix.ListViewColumnSorter
    $listView.ListViewItemSorter = $sorter

    [void]$listView.Columns.Add("MSI", 70)
    [void]$listView.Columns.Add("PCI Device Name", 285)
    [void]$listView.Columns.Add("Driver", 110)
    [void]$listView.Columns.Add("Priority", 75)
    [void]$listView.Columns.Add("IRQ Mask", 95)
    [void]$listView.Columns.Add("DPC Assessment / Advice", 215)

    $listView.Add_ColumnClick({
        param($src, $e)
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
    }.GetNewClosure())

    $refreshData = {
        $listView.BeginUpdate()
        $listView.ListViewItemSorter = $null
        $listView.Items.Clear()
        $auditData = Get-HardwareState_IRQ
        foreach ($item in $auditData) {
            $lvItem = New-Object System.Windows.Forms.ListViewItem($item.MsiStatus)
            [void]$lvItem.SubItems.Add($item.RawDeviceName)
            [void]$lvItem.SubItems.Add($item.DriverTag)
            [void]$lvItem.SubItems.Add($item.PrioLabel)
            [void]$lvItem.SubItems.Add($item.AffinityLabel)
            [void]$lvItem.SubItems.Add($item.AdviceText)
            $lvItem.Tag = $item
            $lvItem.Checked = (-not $item.IsDetected)

            if ($item.IsRecommendedOffload) {
                $lvItem.ForeColor = [System.Drawing.Color]::Gold
            } elseif (-not $item.IsDetected) {
                $lvItem.ForeColor = [System.Drawing.Color]::LightSkyBlue
            } else {
                $lvItem.ForeColor = [System.Drawing.Color]::LightGreen
            }
            [void]$listView.Items.Add($lvItem)
        }
        $listView.ListViewItemSorter = $sorter
        $listView.EndUpdate()
    }
    &$refreshData

    $btnSelRec.Tag = @{
        ListView   = $listView
        ChkOffload = $chkOffloadCore0
        ComboPrio  = $comboPrio
    }
    $btnSelRec.Add_Click({
        $ctx = $this.Tag
        $lv  = $ctx.ListView
        $lv.BeginUpdate()
        foreach ($lvItem in $lv.Items) {
            $dev = $lvItem.Tag
            $lvItem.Checked = ($null -ne $dev -and [bool]$dev.IsRecommendedOffload)
        }
        $lv.EndUpdate()
        $ctx.ChkOffload.Checked = $true
        if ($ctx.ComboPrio.SelectedIndex -eq 0) { $ctx.ComboPrio.SelectedIndex = 1 }
    })

    $getOffloadMaskBytes = {
        [int64[]]$masks = Get-UltixPhysicalCoreMasks
        [uint64]$maskVal = if ($masks.Count -ge 2) {
            [uint64]$masks[1]
        } else {
            12
        }
        $fullBytes = [BitConverter]::GetBytes($maskVal)
        $len = 8
        while ($len -gt 1 -and $fullBytes[$len - 1] -eq 0) { $len-- }
        [byte[]]$trimmed = New-Object byte[] $len
        [Array]::Copy($fullBytes, 0, $trimmed, 0, $len)
        return ,$trimmed
    }

    $getSafeBackupKeyName = {
        param([string]$FullMsiPath)
        $relPciPath = $FullMsiPath -replace '^(?i).*?\\Enum\\', '' -replace '(?i)\\Device Parameters\\.*$', ''
        $b64Safe = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($relPciPath)).Replace('/', '_')
        if ($b64Safe.Length -gt 240) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FullMsiPath))).Replace('-', '')
            $md5.Dispose()
            return "PCI_$hash"
        }
        return $b64Safe
    }

    $btnForceMSI = New-UltixButton -Parent $modal -Text "Apply MSI & Policy" -X 15 -Y 555 -Width 180 -Height 35 -RGB @(150, 60, 60)
    $btnForceMSI.Anchor = 'Bottom, Left'
    $btnForceMSI.Add_Click({
        $changed = 0
        $bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
        if (-not (Test-Path -LiteralPath $bRoot)) { New-Item -Path $bRoot -Force | Out-Null }
        $prioSelection = [string]$comboPrio.SelectedItem
        $doOffload     = $chkOffloadCore0.Checked
        [byte[]]$offloadBytes = if ($doOffload) { &$getOffloadMaskBytes } else { $null }
        
        foreach ($lvItem in $listView.CheckedItems) {
            $dev = $lvItem.Tag
            if ($null -eq $dev) { continue }
            $msiPath = $dev.ActionData.Path
            $affPath = $dev.ActionData.AffinityPath
            $safeKey = &$getSafeBackupKeyName $msiPath
            $devBackupKey = "$bRoot\$safeKey"
            
            if (-not (Test-Path -LiteralPath $devBackupKey)) {
                New-Item -Path $devBackupKey -Force | Out-Null
                Set-ItemProperty -LiteralPath $devBackupKey -Name "DeviceName" -Value ([string]$dev.RawDeviceName) -Type String -Force
                $oldMsi = (Get-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
                if ($null -eq $oldMsi) { $oldMsi = 255 }
                Set-ItemProperty -LiteralPath $devBackupKey -Name "MSISupported" -Value $oldMsi -Type DWord -Force

                if (Test-Path -LiteralPath $affPath) {
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "AffinityKeyExisted" -Value 1 -Type DWord -Force
                    $affProps = Get-ItemProperty -LiteralPath $affPath -ErrorAction SilentlyContinue
                    $oldPrio  = if ($null -ne $affProps.InterruptPriority) { $affProps.InterruptPriority } else { 255 }
                    $oldPol   = if ($null -ne $affProps.DevicePolicy) { $affProps.DevicePolicy } else { 255 }
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "InterruptPriority" -Value $oldPrio -Type DWord -Force
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "DevicePolicy" -Value $oldPol -Type DWord -Force
                    if ($null -ne $affProps.AssignmentSetOverride) {
                        Set-ItemProperty -LiteralPath $devBackupKey -Name "AssignmentSetOverride" -Value ([byte[]]$affProps.AssignmentSetOverride) -Type Binary -Force
                    }
                } else {
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "AffinityKeyExisted" -Value 0 -Type DWord -Force
                }
            }

            Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

            if ($prioSelection -ne "Keep Current") {
                if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction SilentlyContinue | Out-Null }
                switch ($prioSelection) {
                    "High (3)"            { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue }
                    "Normal (2)"          { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue }
                    "Low (1)"             { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue }
                    "Undefined (Default)" { Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue }
                }
            }

            if ($doOffload -and $null -ne $offloadBytes) {
                if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction SilentlyContinue | Out-Null }
                Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value $offloadBytes -Type Binary -Force -ErrorAction SilentlyContinue
            }

            Write-GUI " -> Configured IRQ/MSI policy: $($dev.RawDeviceName)"
            $changed++
        }
        &$refreshData
        if ($changed -gt 0) { [System.Windows.Forms.MessageBox]::Show("Successfully configured MSI & IRQ policy for $changed device(s).`nOriginal states backed up.`nPlease reboot your PC.", "Reboot Required") }
    }.GetNewClosure())

    $btnRevertMSI = New-UltixButton -Parent $modal -Text "Restore Original State" -X 205 -Y 555 -Width 190 -Height 35 -RGB @(100, 100, 100)
    $btnRevertMSI.Anchor = 'Bottom, Left'
    $btnRevertMSI.Add_Click({
        $bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
        foreach ($lvItem in $listView.CheckedItems) {
            $dev = $lvItem.Tag
            if ($null -eq $dev) { continue }
            $msiPath = $dev.ActionData.Path
            $affPath = $dev.ActionData.AffinityPath
            $safeKey = &$getSafeBackupKeyName $msiPath
            $devBackupKey = "$bRoot\$safeKey"
            
            if (Test-Path -LiteralPath $devBackupKey) {
                $bProps = Get-ItemProperty -LiteralPath $devBackupKey -ErrorAction SilentlyContinue
                if ($null -ne $bProps.MSISupported) {
                    if ($bProps.MSISupported -eq 255 -or $bProps.MSISupported -eq -1) {
                        Remove-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value $bProps.MSISupported -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                }

                if ($bProps.AffinityKeyExisted -eq 0) {
                    if (Test-Path -LiteralPath $affPath) { Remove-Item -LiteralPath $affPath -Recurse -Force -ErrorAction SilentlyContinue }
                } elseif (Test-Path -LiteralPath $affPath) {
                    if ($bProps.InterruptPriority -eq 255 -or $null -eq $bProps.InterruptPriority) {
                        Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value $bProps.InterruptPriority -Type DWord -Force -ErrorAction SilentlyContinue
                    }

                    if ($bProps.DevicePolicy -eq 255 -or $null -eq $bProps.DevicePolicy) {
                        Remove-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value $bProps.DevicePolicy -Type DWord -Force -ErrorAction SilentlyContinue
                    }

                    if ($null -ne $bProps.AssignmentSetOverride) {
                        Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value ([byte[]]$bProps.AssignmentSetOverride) -Type Binary -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                    }
                }
                Remove-Item -LiteralPath $devBackupKey -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $affPath) {
                    Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority", "DevicePolicy", "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                }
            }
            Write-GUI " -> Reverted IRQ/MSI state to factory defaults: $($dev.RawDeviceName)"
        }
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 405 -Y 555 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $lblDpcMonitor, $lblDpcLegend, $lblPrio, $comboPrio, $chkOffloadCore0, $listView))
    try {
        [void]$modal.ShowDialog($global:form)
    } finally {
        $dpcTimer.Stop()
        $dpcTimer.Dispose()
        $modal.Dispose()
    }
}

function Show-WHEAModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 500); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(850, 500)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
    
    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'

    $btnRefresh = New-UltixButton -Parent $modal -Text "Scan Now" -X 715 -Y 15 -Width 100 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView; $listView.Location = New-Object System.Drawing.Point(15, 60); $listView.Size = New-Object System.Drawing.Size(800, 330); $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $listView.ForeColor = [System.Drawing.Color]::White; $listView.Font = New-Object System.Drawing.Font("Consolas", 10); $listView.Anchor = 'Top, Bottom, Left, Right'; $listView.View = [System.Windows.Forms.View]::Details; $listView.FullRowSelect = $true; $listView.GridLines = $true
    Enable-UltixDoubleBuffer -Control $listView

    $listView.Columns.Add("Time", 170) | Out-Null
    $listView.Columns.Add("Event ID", 90) | Out-Null
    $listView.Columns.Add("APIC ID", 120) | Out-Null
    $listView.Columns.Add("Error Source / Details", 390) | Out-Null

    $btnClear = New-UltixButton -Parent $modal -Text "Wipe Logs (Prepare for Test)" -X 15 -Y 405 -Width 220 -Height 35 -RGB @(150, 60, 60)
    $btnClear.Anchor = 'Bottom, Left'

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 245 -Y 405 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $refreshData = {
        $uiModal    = $modal
        $uiListView = $listView

        $uiListView.Items.Clear()
        $loadingItem = New-Object System.Windows.Forms.ListViewItem("Scanning...")
        $loadingItem.SubItems.Add("---")
        $loadingItem.SubItems.Add("---")
        $loadingItem.SubItems.Add("Parsing System WHEA Event Log in background Runspace...")
        $loadingItem.ForeColor = [System.Drawing.Color]::LightSkyBlue
        [void]$uiListView.Items.Add($loadingItem)

        $sb = (Get-Command -Name Get-HardwareState_WHEA).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnRefresh, $btnClear) -OnComplete ({
            param($output)
            Update-Progress 0
            if ($null -eq $uiModal -or $uiModal.IsDisposed -or $null -eq $uiListView -or $uiListView.IsDisposed) { return }
            
            $uiListView.BeginUpdate()
            $uiListView.Items.Clear()
            [array]$auditData = @($output | Where-Object { $null -ne $_ })
            
            if ($auditData.Count -gt 0) {
                foreach ($item in $auditData) {
                    $lvItem = New-Object System.Windows.Forms.ListViewItem($item.Time)
                    $lvItem.SubItems.Add([string]$item.EventID)
                    
                    if ($item.ApicID -ne "N/A") {
                        $lvItem.UseItemStyleForSubItems = $false
                        $lvItem.SubItems.Add($item.ApicID).ForeColor = [System.Drawing.Color]::OrangeRed
                    } else {
                        $lvItem.SubItems.Add($item.ApicID)
                    }
                    
                    $lvItem.SubItems.Add($item.ErrorType)
                    [void]$uiListView.Items.Add($lvItem)
                }
            } else {
                $lvItem = New-Object System.Windows.Forms.ListViewItem("---")
                $lvItem.SubItems.Add("---")
                $lvItem.SubItems.Add("---")
                $lvItem.SubItems.Add("No WHEA errors found. Hardware is perfectly stable.")
                $lvItem.ForeColor = [System.Drawing.Color]::LightGreen
                [void]$uiListView.Items.Add($lvItem)
            }
            $uiListView.EndUpdate()
        }.GetNewClosure())
    }
    
    &$refreshData
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClear.Add_Click({
        Clear-WHEALogs
        &$refreshData
        [System.Windows.Forms.MessageBox]::Show("System Event Log wiped. Ready for next stability test.", "Logs Cleared")
    }.GetNewClosure())

    $modal.Controls.AddRange(@($lblDesc, $listView))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-NetworkModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(760, 560); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(710, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] Applying or reverting NDIS settings will momentarily re-initialize the network adapter."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(710, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(710, 375); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $btnEngage  = New-UltixButton -Parent $modal -Text "Optimize Checked" -X 15 -Y 470 -Width 175 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'

    $btnRevert  = New-UltixButton -Parent $modal -Text "Restore Checked Defaults" -X 200 -Y 470 -Width 195 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'

    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh Audit" -X 405 -Y 470 -Width 140 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'

    $btnClose   = New-UltixButton -Parent $modal -Text "Close" -X 555 -Y 470 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $actionButtons = @($btnEngage, $btnRevert, $btnRefresh)

    $btnRefresh.Add_Click({
        Update-NetworkModalList -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons
    }.GetNewClosure())

    $btnEngage.Add_Click({
        $queue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i) -and $i -lt $localData.Count) {
                $queue += $localData[$i]
            }
        }
        Start-NetworkOptimizationAsync -SelectedItems $queue -Mode "Apply" -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons
    }.GetNewClosure())

    $btnRevert.Add_Click({
        $queue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i) -and $i -lt $localData.Count) {
                $queue += $localData[$i]
            }
        }
        Start-NetworkOptimizationAsync -SelectedItems $queue -Mode "Revert" -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons
    }.GetNewClosure())

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList))

    Update-NetworkModalList -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons

    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-TimerModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(700, 410); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(700, 410)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] BCD modifications require a system reboot to lock the TSC hardware timer."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(650, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $lblCurrentTimer = New-Object System.Windows.Forms.Label
    $lblCurrentTimer.Location = New-Object System.Drawing.Point(15, 345)
    $lblCurrentTimer.Size = New-Object System.Drawing.Size(650, 20)
    $lblCurrentTimer.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $lblCurrentTimer.ForeColor = [System.Drawing.Color]::Yellow
    $lblCurrentTimer.Anchor = 'Bottom, Left, Right'
	
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(650, 200); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList
    $testLockState = @{ IsLocked = $false }

    $updateTimerLabel = {
        param([System.Windows.Forms.Label]$Lbl)
        if ($null -eq $Lbl -or $Lbl.IsDisposed) { return }
        $tStats = Get-CurrentTimerResolution
        $modeTag = if ($testLockState.IsLocked) { " [0.5ms TEST ACTIVE]" } else { "" }
        $Lbl.Text = "LIVE TIMER (2Hz): $($tStats.CurrentMs) ms (Max precision: $($tStats.LimitMs) ms | Default: $($tStats.DefaultMs) ms)$modeTag"
        if ($tStats.CurrentMs -le 0.55) {
            $Lbl.ForeColor = [System.Drawing.Color]::LightGreen
        } elseif ($tStats.CurrentMs -le 1.05) {
            $Lbl.ForeColor = [System.Drawing.Color]::Yellow
        } else {
            $Lbl.ForeColor = [System.Drawing.Color]::OrangeRed
        }
    }

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_Timer
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) } 
            else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
        }
        &$updateTimerLabel $lblCurrentTimer
    }
    &$refreshData

    $timerPoll = New-Object System.Windows.Forms.Timer
    $timerPoll.Interval = 500
    $timerPoll.Tag = @{
        Modal  = $modal
        Label  = $lblCurrentTimer
        Update = $updateTimerLabel
    }
    $timerPoll.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Modal.IsDisposed -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        & $ctx.Update $ctx.Label
    })
    $timerPoll.Start()

    $btnEngage = New-UltixButton -Parent $modal -Text "Enforce 0.5ms & TSC" -X 15 -Y 300 -Width 155 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $applyQueue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $applyQueue += $localData[$i] }
        }
        if ($applyQueue.Count -gt 0) {
            Invoke-ApplyTimerTweaks -SelectedItems $applyQueue
            [System.Windows.Forms.MessageBox]::Show("Hardware timers optimized. Reboot required for BCD changes.", "Action Completed")
        }
        &$refreshData
    }.GetNewClosure())

    $btnRevert = New-UltixButton -Parent $modal -Text "Restore Defaults" -X 178 -Y 300 -Width 135 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
        Remove-ItemProperty -Path $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue | Out-Null
        
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} disabledynamictick" -NoNewWindow -Wait
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} useplatformclock" -NoNewWindow -Wait
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} useplatformtick" -NoNewWindow -Wait
        
        $hpet = Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "PNP0103" }
        if ($null -ne $hpet -and $hpet.ConfigManagerErrorCode -eq 22) { 
            Enable-PnpDevice -InstanceId $hpet.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null 
        }
        
        Write-GUI " -> Reverted Timer Subsystem & BCD flags to OS defaults."
        [System.Windows.Forms.MessageBox]::Show("Default OS timer mechanisms and BCD values restored. HPET enabled. Reboot required.", "Revert Completed")
        &$refreshData
    }.GetNewClosure())

    $btnTestPulse = New-UltixButton -Parent $modal -Text "Test 0.5ms Lock" -X 321 -Y 300 -Width 140 -Height 35 -RGB @(45, 110, 65)
    $btnTestPulse.Anchor = 'Bottom, Left'
    $btnTestPulse.Add_Click({
        if (-not $testLockState.IsLocked) {
            [void][WinUltix.NtDll]::SetTimerResolution(5000, $true)
            $testLockState.IsLocked = $true
            $this.Text = "Stop 0.5ms Test"
            $this.BackColor = [System.Drawing.Color]::FromArgb(255, 160, 90, 40)
            Write-GUI " -> Engaged live NtSetTimerResolution(5000) 0.5ms kernel clock test."
        } else {
            [void][WinUltix.NtDll]::SetTimerResolution(5000, $false)
            $testLockState.IsLocked = $false
            $this.Text = "Test 0.5ms Lock"
            $this.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 110, 65)
            Write-GUI " -> Released 0.5ms kernel clock test lock."
        }
        &$updateTimerLabel $lblCurrentTimer
    }.GetNewClosure())

    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh" -X 469 -Y 300 -Width 90 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 567 -Y 300 -Width 98 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList, $lblCurrentTimer))
    try {
        [void]$modal.ShowDialog($global:form)
    } finally {
        if ($testLockState.IsLocked) {
            [void][WinUltix.NtDll]::SetTimerResolution(5000, $false)
            Write-GUI " -> Released 0.5ms kernel clock test lock (Modal closed)."
        }
        $timerPoll.Stop()
        $timerPoll.Dispose()
        $modal.Dispose()
    }
}

function Show-NVMeModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 360); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 360)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'

    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply PCI bus and NVMe driver changes."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(600, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 160); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_NVMe
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) } 
            else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
        }
    }
    &$refreshData 

    $btnEngage = New-UltixButton -Parent $modal -Text "Disable Power States" -X 15 -Y 260 -Width 180 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $applyQueue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $applyQueue += $localData[$i] }
        }
        if ($applyQueue.Count -gt 0) {
            Invoke-ApplyNVMeTweaks -SelectedItems $applyQueue
            [System.Windows.Forms.MessageBox]::Show("NVMe APST and PCIe ASPM disabled.", "Optimization Completed")
        }
        &$refreshData
    }.GetNewClosure())

    $btnRevert = New-UltixButton -Parent $modal -Text "Restore OS Defaults" -X 205 -Y 260 -Width 160 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters" -Name "DisableASPM" -ErrorAction SilentlyContinue | Out-Null
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" -Name "IdlePowerMode" -ErrorAction SilentlyContinue | Out-Null
        
        Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        
        Write-GUI " -> Restored default PCI ASPM, StorNVMe APST, and MMAgent settings."
        [System.Windows.Forms.MessageBox]::Show("Standard PCI/NVMe drivers and Memory Compression restored. Reboot is required to apply bus changes.", "Revert Completed")
        &$refreshData
    }.GetNewClosure())

    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh Audit" -X 375 -Y 260 -Width 120 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 505 -Y 260 -Width 115 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $chkList, $lblWarning))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function New-PreFlightShortcut {
    $appDataFolder = "$env:LOCALAPPDATA\WinUltix"
    if (-not (Test-Path $appDataFolder)) { 
        try { New-Item -Path $appDataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null } 
        catch { [System.Windows.Forms.MessageBox]::Show("Failed to create WinUltix AppData directory.", "Error"); return }
    }
    
    $ps1Path = "$appDataFolder\PreFlight.ps1"
    $topo = Get-CPUTopologyProfile
    $maskInt64 = $topo.Mask.ToInt64()

    $affState  = if ($topo.IsSupported) { "`$true" } else { "`$false" }
    $affString = if ($topo.IsSupported) { "Affinity Lasso ($($topo.CoreDesc))" } else { "Affinity Lasso (Unsupported CPU - Disabled)" }
    $affColor  = if ($topo.IsSupported) { "White" } else { "DarkGray" }

    $code = @"
`$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not `$isAdmin) {
    `$argList = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + `$PSCommandPath + '"'
    Start-Process powershell.exe -ArgumentList `$argList -Verb RunAs
    exit
}

if (-not ([System.Management.Automation.PSTypeName]'WinUltix.PreFlightNative').Type) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    namespace WinUltix {
        public static class PreFlightNative {
            [DllImport("dwmapi.dll", PreserveSig = true)]
            private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

            public static void EnableDarkTitleBar(IntPtr handle) {
                if (handle == IntPtr.Zero) return;
                int useDark = 1;
                if (DwmSetWindowAttribute(handle, 20, ref useDark, sizeof(int)) != 0) {
                    DwmSetWindowAttribute(handle, 19, ref useDark, sizeof(int));
                }
            }

            public static void EnableGdiDpiScaling() {
                try { SetProcessDpiAwarenessContext(new IntPtr(-5)); } catch { }
            }
        }
    }
'@ -ErrorAction SilentlyContinue
}

[WinUltix.PreFlightNative]::EnableGdiDpiScaling()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

`$c = 'HKCU:\Software\WinUltix\AffinityLasso'
`$p = 'HKLM:\SOFTWARE\WinUltix\CPPC'
function Get-Pcfg (`$g) {
    `$out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR `$g 2>`$null
    if (-not `$out) { return `$null }
    `$hexLines = @(`$out -match ':\s*(0x[0-9a-fA-F]+)\s*`$')
    if (`$hexLines.Count -ge 2 -and `$hexLines[-2] -match '(0x[0-9a-fA-F]+)\s*`$') {
        return [convert]::ToInt32(`$matches[1], 16)
    }
    return `$null
}

`$curEpp = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
`$failsafeTask = Get-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -ErrorAction SilentlyContinue
`$isEngaged = ((`$null -ne `$failsafeTask) -or (`$curEpp -eq 0))
`$eppDisp = if (`$null -ne `$curEpp) { "`$curEpp%" } else { "N/A" }

`$frm = New-Object System.Windows.Forms.Form
`$frm.Text = "WinUltix - Pre-Flight Game Mode"
`$frm.Size = New-Object System.Drawing.Size(370, 215)
`$frm.StartPosition = "CenterScreen"
`$frm.FormBorderStyle = "FixedDialog"
`$frm.MaximizeBox = `$false
`$frm.MinimizeBox = `$false
`$frm.TopMost = `$true
`$frm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
`$frm.ForeColor = [System.Drawing.Color]::White
`$frm.Add_HandleCreated({ [WinUltix.PreFlightNative]::EnableDarkTitleBar(`$this.Handle) })

`$lblStatus = New-Object System.Windows.Forms.Label
`$lblStatus.Location = New-Object System.Drawing.Point(20, 12)
`$lblStatus.Size = New-Object System.Drawing.Size(320, 22)
`$lblStatus.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
if (`$isEngaged) {
    `$lblStatus.Text = "STATUS: ENGAGED [EPP: `$eppDisp | ARMED]"
    `$lblStatus.ForeColor = [System.Drawing.Color]::LightGreen
} else {
    `$lblStatus.Text = "STATUS: RELEASED [EPP: `$eppDisp | STANDBY]"
    `$lblStatus.ForeColor = [System.Drawing.Color]::LightSkyBlue
}

`$chkAff = New-Object System.Windows.Forms.CheckBox
`$chkAff.Text = "$affString"
`$chkAff.Location = New-Object System.Drawing.Point(20, 42)
`$chkAff.Size = New-Object System.Drawing.Size(320, 25)
`$chkAff.Checked = $affState
`$chkAff.Enabled = $affState
`$chkAff.ForeColor = [System.Drawing.Color]::$affColor

`$chkCPPC = New-Object System.Windows.Forms.CheckBox
`$chkCPPC.Text = "Max CPPC (EPP 0%, Disable C-States)"
`$chkCPPC.Location = New-Object System.Drawing.Point(20, 72)
`$chkCPPC.Size = New-Object System.Drawing.Size(320, 25)
`$chkCPPC.Checked = `$true

`$btnEngage = New-Object System.Windows.Forms.Button
`$btnEngage.Text = "ENGAGE"
`$btnEngage.Location = New-Object System.Drawing.Point(20, 118)
`$btnEngage.Size = New-Object System.Drawing.Size(100, 32)
`$btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
`$btnEngage.FlatStyle = "Flat"
`$btnEngage.DialogResult = "Yes"

`$btnRelease = New-Object System.Windows.Forms.Button
`$btnRelease.Text = "RELEASE"
`$btnRelease.Location = New-Object System.Drawing.Point(128, 118)
`$btnRelease.Size = New-Object System.Drawing.Size(100, 32)
`$btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 100, 60)
`$btnRelease.FlatStyle = "Flat"
`$btnRelease.DialogResult = "No"

`$btnCancel = New-Object System.Windows.Forms.Button
`$btnCancel.Text = "Cancel"
`$btnCancel.Location = New-Object System.Drawing.Point(236, 118)
`$btnCancel.Size = New-Object System.Drawing.Size(100, 32)
`$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
`$btnCancel.FlatStyle = "Flat"
`$btnCancel.DialogResult = "Cancel"

`$frm.Controls.AddRange(@(`$lblStatus, `$chkAff, `$chkCPPC, `$btnEngage, `$btnRelease, `$btnCancel))
`$res = `$frm.ShowDialog()
`$frm.Dispose()

if (`$res -eq "Yes") {
    if (`$chkAff.Checked -and (Test-Path `$c)) { 
        (Get-ItemProperty `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
            `$n = `$_.Name -replace '\.exe`$',''
            Get-Process -Name `$n -ErrorAction SilentlyContinue | ForEach-Object { 
                try { `$_.ProcessorAffinity = [System.IntPtr]([int64]$maskInt64); `$_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch {} 
            } 
        } 
    }
    
    if (`$chkCPPC.Checked) {
        if (-not (Test-Path `$p)) { New-Item -Path `$p -Force | Out-Null }
        `$e = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        `$d = Get-Pcfg '4b92d758-5a24-4851-a470-815d78aee119'
        `$pr = Get-Pcfg '7b224883-b3cc-4d79-819f-8374152cbe7c'
        
        if (`$null -ne `$e -and -not (`$e -eq 0 -and `$d -eq 100 -and `$pr -eq 100) -and -not (`$e -eq 0 -and `$d -eq 0 -and `$pr -eq 0)) {
            Set-ItemProperty -Path `$p -Name 'EPP' -Value `$e -Type DWord -Force
            Set-ItemProperty -Path `$p -Name 'Demote' -Value `$d -Type DWord -Force
            Set-ItemProperty -Path `$p -Name 'Promote' -Value `$pr -Type DWord -Force
        }
        
        `$tsCmd = "`$bp='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path `$bp){ `$r=Get-ItemProperty `$bp; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
        `$tsAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"`$tsCmd`""
        `$tsTriggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogon))
        `$tsPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Action `$tsAction -Trigger `$tsTriggers -Principal `$tsPrincipal -Force | Out-Null

        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setactive SCHEME_CURRENT
    }
} elseif (`$res -eq "No") {
    if (`$chkAff.Checked) { 
        `$lpCount = [Environment]::ProcessorCount
        `$fullMaskVal = if (`$lpCount -ge 64) { -1 } else { ([int64]1 -shl `$lpCount) - 1 }
        `$sys = [System.IntPtr]`$fullMaskVal
        if (Test-Path `$c) { 
            (Get-ItemProperty `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
                `$n = `$_.Name -replace '\.exe`$',''
                Get-Process -Name `$n -ErrorAction SilentlyContinue | ForEach-Object { 
                    try { `$_.ProcessorAffinity = `$sys; `$_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal } catch {} 
                } 
            } 
        } 
    }
    
    if (`$chkCPPC.Checked) {
        `$e = 50; `$d = 40; `$pr = 60
        if (Test-Path `$p) { 
            `$reg = Get-ItemProperty -Path `$p -ErrorAction SilentlyContinue
            if (`$null -ne `$reg.EPP -and `$null -ne `$reg.Demote -and `$null -ne `$reg.Promote) {
                if (-not (`$reg.EPP -eq 0 -and `$reg.Demote -eq 0 -and `$reg.Promote -eq 0)) {
                    `$e = `$reg.EPP; `$d = `$reg.Demote; `$pr = `$reg.Promote
                }
            }
        }
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$e; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$e
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$d; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$d
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$pr; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$pr; powercfg.exe /setactive SCHEME_CURRENT
        
        Unregister-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
    }
}
"@

    try {
        Set-Content -Path $ps1Path -Value $code -Encoding UTF8 -ErrorAction Stop
        $desktop = [Environment]::GetFolderPath("Desktop")
        $WshShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
        $Shortcut = $WshShell.CreateShortcut("$desktop\WinUltix Pre-Flight Mode.lnk")
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""
        $Shortcut.WindowStyle = 7
        $Shortcut.IconLocation = "shell32.dll, 137"
        $Shortcut.Save()
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell)
        
        Write-GUI " -> Generated Pre-Flight shortcut on Desktop ($($topo.Label))."
        [System.Windows.Forms.MessageBox]::Show("Pre-Flight Shortcut generated on Desktop.", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to construct COM object or write file.`n`nError: $($_.Exception.Message)", "Shortcut Generation Failed")
    }
}

# ------------------------------------------
# Z7: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z7UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = "Hardware"
    $tab.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)

    $topo = Get-CPUTopologyProfile

    if ($topo.IsSupported) {
        [void](New-UltixButton -Parent $tab -X 15 -Y 20 -Width 240 -Height 40 -RGB @(150, 60, 60) `
            -Text "Affinity Lasso (CPU Core Lock)" `
            -Description "Lock background apps to specific cores ($($topo.CoreDesc)) to free up prime gaming cores." `
            -OnClick ({ Show-AffinityModal "Affinity Lasso - $($topo.Label)" "Lock background processes to $($topo.CoreDesc) with BelowNormal priority." }.GetNewClosure()))
    } else {
        $btnAffinity = New-UltixButton -Parent $tab -X 15 -Y 20 -Width 240 -Height 40 -RGB @(45, 45, 45) `
            -ForeColor ([System.Drawing.Color]::DarkGray) `
            -Text "Affinity Lasso (Unsupported CPU)"
        $btnAffinity.Enabled = $false
    }

    [void](New-UltixButton -Parent $tab -X 265 -Y 20 -Width 120 -Height 90 -RGB @(60, 100, 150) `
        -Text "Generate Pre-Flight Shortcut" `
        -Description "Create a desktop shortcut to instantly apply Affinity and CPPC rules." `
        -OnClick { New-PreFlightShortcut })

    [void](New-UltixButton -Parent $tab -X 15 -Y 70 -Width 240 -Height 40 -RGB @(100, 60, 150) `
        -Text "CPPC P-State Unhider" `
        -Description "Unhide and manage advanced AMD/Intel CPPC power states." `
        -OnClick { Show-CPPCModal "CPPC Management" "Unhide advanced power plan settings (EPP, Demote, Promote)." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 120 -Width 370 -Height 40 -RGB @(100, 100, 100) `
        -Text "MSI & IRQ Affinity Enforcer" `
        -Description "Force Message Signaled Interrupts (MSI), set Interrupt Priority, offload IRQs from Core 0, and monitor live kernel DPCs." `
        -OnClick { Show-MsiModal "MSI & IRQ Affinity Enforcer" "Force PCI devices into MSI mode, adjust interrupt priority, and offload high-DPC drivers (GPU/NIC) from Core 0." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 170 -Width 370 -Height 40 -RGB @(150, 100, 60) `
        -Text "WHEA Hardware Error Logger" `
        -Description "Scan system logs for hardware instability (Curve Optimizer / RAM)." `
        -OnClick { Show-WHEAModal "WHEA Logger" "Analyze hardware errors to find unstable CPU cores or RAM." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 220 -Width 370 -Height 40 -RGB @(60, 100, 150) `
        -Text "Network NDIS & TCP Optimizer" `
        -Description "Configure low-latency NDIS parameters, TCP properties, and offloads with full symmetric revert." `
        -OnClick { Show-NetworkModal "Network Optimizer" "Disable flow control, power saving, interrupt moderation, and enforce TCPNoDelay." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 270 -Width 370 -Height 40 -RGB @(100, 100, 100) `
        -Text "System Timer & TSC Fix (0.5ms)" `
        -Description "Fix Windows 11 API to allow global 0.5ms High Resolution Timers and force CPU TSC." `
        -OnClick { Show-TimerModal "Timer Resolution Subsystem" "Enable legacy 0.5ms requests globally and stabilize DPC latency." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 320 -Width 370 -Height 40 -RGB @(100, 60, 150) `
        -Text "I/O & Memory Latency Optimizer" `
        -Description "Disable NVMe APST, PCIe ASPM, and System Memory Compression to reduce CPU overhead and micro-stuttering." `
        -OnClick { Show-NVMeModal "I/O & Memory Optimizer" "Prevent NVMe and PCIe bus from entering low-power states (D3hot/L1.2) and disable RAM compression." })

    # Dedicated 3-Line Live Kernel Interrupt / DPC Telemetry Panel on Hardware Tab
    $lblDpcHeader = New-Object System.Windows.Forms.Label
    $lblDpcHeader.Text = "Live Kernel Interrupt / DPC Distribution Monitor (ntdll.dll)"
    $lblDpcHeader.Location = New-Object System.Drawing.Point(15, 374)
    $lblDpcHeader.Size = New-Object System.Drawing.Size(370, 20)
    $lblDpcHeader.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDpcHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblTabDpc = New-Object System.Windows.Forms.Label
    $lblTabDpc.Location = New-Object System.Drawing.Point(15, 396)
    $lblTabDpc.Size = New-Object System.Drawing.Size(370, 68)
    $lblTabDpc.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblTabDpc.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $lblTabDpc.Font = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Bold)
    $lblTabDpc.TextAlign = "TopLeft"
    $lblTabDpc.BorderStyle = "FixedSingle"
    $lblTabDpc.Padding = New-Object System.Windows.Forms.Padding(5, 5, 5, 4)

    $lblTabLegend = New-Object System.Windows.Forms.Label
    $lblTabLegend.Text = "C0..Cn = Physical Cores (SMT: 2 LP#/Core) | LP# = Logical Thread`r`nColor = Core 0 Load: Green (<30%) | Yellow (30-54%) | Red (>=55%)"
    $lblTabLegend.Location = New-Object System.Drawing.Point(15, 468)
    $lblTabLegend.Size = New-Object System.Drawing.Size(370, 30)
    $lblTabLegend.ForeColor = [System.Drawing.Color]::DarkGray
    $lblTabLegend.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)

    $tabDpcState = @{ PrevCounts = $null; IsRunning = $false; LastSnap = $null }
    Update-UltixDpcMonitorUI -TargetLabel $lblTabDpc -State $tabDpcState -CompactMode

    $tabDpcTimer = New-Object System.Windows.Forms.Timer
    $tabDpcTimer.Interval = 1000
    $tabDpcTimer.Tag = @{
        TabControl = $TabControl
        Tab        = $tab
        Label      = $lblTabDpc
        State      = $tabDpcState
    }
    $tabDpcTimer.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        if ($ctx.TabControl.SelectedTab -eq $ctx.Tab) {
            Update-UltixDpcMonitorUI -TargetLabel $ctx.Label -State $ctx.State -CompactMode
        }
    })

    $btnToggleDpc = New-UltixButton -Parent $tab -X 15 -Y 502 -Width 320 -Height 34 -RGB @(50, 75, 100) `
        -Text "Start Live DPC Monitor (1Hz Stream)" `
        -Description "Toggles real-time 1Hz polling of ntdll!NtQuerySystemInformation (SystemInterruptInformation). Automatically pauses if you switch tabs."

    $btnHelpDpc = New-UltixButton -Parent $tab -X 345 -Y 502 -Width 40 -Height 34 -RGB @(80, 80, 80) `
        -Text "?" `
        -Description "DPC LEGEND & REPORT: Samples per-core DPC distribution over 1s and prints a compact breakdown of all physical cores (C0..Cn) and logical threads (LP#) to the log."

    $uiContext = @{
        Timer = $tabDpcTimer
        Label = $lblTabDpc
        State = $tabDpcState
    }
    $btnToggleDpc.Tag = $uiContext
    $btnHelpDpc.Tag   = $uiContext

    $btnToggleDpc.Add_Click({
        $ctx   = $this.Tag
        $state = $ctx.State
        $timer = $ctx.Timer
        $lbl   = $ctx.Label

        if (-not $state.IsRunning) {
            $state.IsRunning  = $true
            $state.PrevCounts = $null
            $this.Text        = "Stop Live DPC Monitor [ACTIVE - 1Hz]"
            $this.BackColor   = [System.Drawing.Color]::FromArgb(255, 45, 110, 65)
            Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
            $timer.Start()
            Write-GUI " -> Live Kernel DPC Monitor started (1Hz polling)."
        } else {
            $timer.Stop()
            $state.IsRunning = $false
            $this.Text       = "Start Live DPC Monitor (1Hz Stream)"
            $this.BackColor  = [System.Drawing.Color]::FromArgb(255, 50, 75, 100)
            if ($null -ne $state.LastSnap -and $state.LastSnap.HasLiveDelta) {
                Write-UltixDpcReport -Snapshot $state.LastSnap
            } else {
                Write-GUI " -> Live Kernel DPC Monitor stopped.`n"
            }
            Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
        }
    })

    $btnHelpDpc.Add_Click({
        $ctx   = $this.Tag
        $state = $ctx.State
        $lbl   = $ctx.Label
        Write-UltixDpcReport -Snapshot $state.LastSnap
        Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
    })

    $tab.Tag = $tabDpcTimer
    $tab.Add_Disposed({
        $t = $this.Tag
        if ($null -ne $t) {
            $t.Stop()
            $t.Dispose()
        }
    })

    $tab.Controls.AddRange(@($lblDpcHeader, $lblTabDpc, $lblTabLegend))
    $TabControl.Controls.Add($tab)
}
# <<< END INJECTED: Z7_Hardware.ps1 <<<


# Promote all loaded toolkit functions to Global scope so .GetNewClosure() dynamic modules always resolve them
foreach ($fn in (Get-ChildItem -Path Function:\)) {
    Set-Item -Path "Function:\global:$($fn.Name)" -Value $fn.ScriptBlock -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ------------------------------------------
# 2. GLOBAL UI COMPONENTS
# ------------------------------------------
[WinUltix.NativeMethods]::EnableGdiDpiScaling()

$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "WinUltix - Ultimate System Toolkit $AppVersion"
$global:form.Size = New-Object System.Drawing.Size(1200, 800)
$global:form.MinimumSize = New-Object System.Drawing.Size(1200, 800)
$global:form.StartPosition = "CenterScreen"
$global:form.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$global:form.FormBorderStyle = "Sizable"
$global:form.MaximizeBox = $true
$global:form.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

$global:descBox = New-Object System.Windows.Forms.TextBox
$global:descBox.Multiline = $true; $global:descBox.Location = New-Object System.Drawing.Point(440, 20)
$global:descBox.Size = New-Object System.Drawing.Size(720, 80)
$global:descBox.BackColor = [System.Drawing.Color]::FromArgb(255, 25, 25, 25); $global:descBox.ForeColor = [System.Drawing.Color]::LightSkyBlue; $global:descBox.ReadOnly = $true; $global:descBox.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Italic)
$global:descBox.Text = "Hover over any button to see operation details."
$global:descBox.Anchor = 'Top, Left, Right'

$global:infoBox = New-Object System.Windows.Forms.RichTextBox
$global:infoBox.Multiline = $true
$global:infoBox.Location = New-Object System.Drawing.Point(440, 110)
$global:infoBox.Size = New-Object System.Drawing.Size(720, 610)
$global:infoBox.BackColor = [System.Drawing.Color]::FromArgb(255, 15, 15, 15)
$global:infoBox.ForeColor = [System.Drawing.Color]::LightGray
$global:infoBox.BorderStyle = "FixedSingle"
$global:infoBox.ReadOnly = $true
$global:infoBox.DetectUrls = $false
$global:infoBox.ScrollBars = "Vertical"
$global:infoBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$global:infoBox.Anchor = 'Top, Bottom, Left, Right'
$global:infoBox.SelectionColor = [System.Drawing.Color]::Cyan
$global:infoBox.AppendText("--- WINULTIX $AppVersion ---`r`n`r`n")
$global:infoBox.SelectionColor = [System.Drawing.Color]::LightGreen
$global:infoBox.AppendText("Ready for deployment. Modular architecture loaded successfully.`r`n")

$global:tabControl = New-Object WinUltix.DarkTabControl
$global:tabControl.Location = New-Object System.Drawing.Point(10, 20)
$global:tabControl.Size = New-Object System.Drawing.Size(410, 700)
$global:tabControl.Anchor = 'Top, Bottom, Left'

$global:progBar = New-Object WinUltix.DarkProgressBar
$global:progBar.Location = New-Object System.Drawing.Point(440, 725)
$global:progBar.Size = New-Object System.Drawing.Size(400, 25)
$global:progBar.Minimum = 0
$global:progBar.Maximum = 100
$global:progBar.Anchor = 'Bottom, Left, Right'

# ------------------------------------------
# 3. MODULE INJECTION (TAB ORDER DEFINED HERE)
# ------------------------------------------
Initialize-Z1UI -TabControl $global:tabControl
Initialize-Z2UI -TabControl $global:tabControl
Initialize-Z3UI -TabControl $global:tabControl
Initialize-Z4UI -TabControl $global:tabControl
Initialize-Z5UI -TabControl $global:tabControl
Initialize-Z6UI -TabControl $global:tabControl
Initialize-Z7UI -TabControl $global:tabControl

# ------------------------------------------
# 4. GLOBAL FOOTER BUTTONS
# ------------------------------------------
$btnExportLog = New-Object System.Windows.Forms.Button
$btnExportLog.Text = "Export Log to Desktop"
$btnExportLog.Location = New-Object System.Drawing.Point(890, 725)
$btnExportLog.Size = New-Object System.Drawing.Size(150, 25)
$btnExportLog.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
$btnExportLog.ForeColor = [System.Drawing.Color]::White
$btnExportLog.FlatStyle = "Flat"
$btnExportLog.Anchor = 'Bottom, Right'
$btnExportLog.Add_Click({ 
    if ($global:infoBox.Text.Length -gt 0) { 
        $desktop = [Environment]::GetFolderPath("Desktop")
        $logPath = "$desktop\WinUltix_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $global:infoBox.Text | Out-File -FilePath $logPath -Encoding UTF8
        Write-GUI "-> Log successfully exported to: $logPath" 
    } else { 
        [System.Windows.Forms.MessageBox]::Show("Log is empty.", "Export Failed") 
    } 
})

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = "[ Clear Log ]"
$btnClearLog.Location = New-Object System.Drawing.Point(1050, 725)
$btnClearLog.Size = New-Object System.Drawing.Size(110, 25)
$btnClearLog.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$btnClearLog.ForeColor = [System.Drawing.Color]::LightGray
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Anchor = 'Bottom, Right'
$btnClearLog.Add_Click({ 
    $global:infoBox.Clear()
    $global:infoBox.SelectionColor = [System.Drawing.Color]::Cyan
    $global:infoBox.AppendText("--- WINULTIX $AppVersion ---`r`n`r`n")
    $global:infoBox.SelectionColor = [System.Drawing.Color]::LightGreen
    $global:infoBox.AppendText("Ready for deployment.`r`n")
})

$btnCredits = New-Object System.Windows.Forms.Button
$btnCredits.Text = "[ About / GitHub ]"
$btnCredits.Location = New-Object System.Drawing.Point(10, 725)
$btnCredits.Size = New-Object System.Drawing.Size(130, 25)
$btnCredits.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 40)
$btnCredits.ForeColor = [System.Drawing.Color]::LightGray
$btnCredits.FlatStyle = "Flat"
$btnCredits.Anchor = 'Bottom, Left'
$btnCredits.Add_Click({ 
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = "About WinUltix"
    $aboutForm.Size = New-Object System.Drawing.Size(380, 265)
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.FormBorderStyle = "FixedDialog"
    $aboutForm.MaximizeBox = $false
    $aboutForm.MinimizeBox = $false
    $aboutForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $aboutForm.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
    
    $lblAbout = New-Object System.Windows.Forms.Label
    $lblAbout.Location = New-Object System.Drawing.Point(20, 20)
    $lblAbout.Size = New-Object System.Drawing.Size(340, 80)
    $lblAbout.ForeColor = [System.Drawing.Color]::LightGray
    $lblAbout.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblAbout.Text = "WinUltix - Ultimate System Toolkit $AppVersion`n`nConcept, architecture and combat tests: Firever`nCoding assistance: Gemini AI`n`nLet your hardware breathe!"
    
    $linkGit = New-Object System.Windows.Forms.LinkLabel
    $linkGit.Location = New-Object System.Drawing.Point(20, 115)
    $linkGit.Size = New-Object System.Drawing.Size(340, 20)
    $linkGit.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkGit.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkGit.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkGit.Text = "https://github.com/Firever-ultix/WinUltix"
    $linkGit.Add_LinkClicked({ Start-Process "https://github.com/Firever-ultix/WinUltix" -ErrorAction SilentlyContinue })
    
    $linkcoffee = New-Object System.Windows.Forms.LinkLabel
    $linkcoffee.Location = New-Object System.Drawing.Point(20, 140)
    $linkcoffee.Size = New-Object System.Drawing.Size(340, 20)
    $linkcoffee.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkcoffee.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkcoffee.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkcoffee.Text = "https://buymeacoffee.com/firever"
    $linkcoffee.Add_LinkClicked({ Start-Process "https://buymeacoffee.com/firever" -ErrorAction SilentlyContinue })
    
    $btnAboutOK = New-Object System.Windows.Forms.Button
    $btnAboutOK.Text = "Close"
    $btnAboutOK.Location = New-Object System.Drawing.Point(140, 185)
    $btnAboutOK.Size = New-Object System.Drawing.Size(80, 25)
    $btnAboutOK.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnAboutOK.ForeColor = [System.Drawing.Color]::White
    $btnAboutOK.FlatStyle = "Flat"
    $btnAboutOK.Add_Click({ $aboutForm.Close() })
    
    $aboutForm.Controls.AddRange(@($lblAbout, $linkGit, $linkcoffee, $btnAboutOK))
    try {
        [void]$aboutForm.ShowDialog($global:form)
    } finally {
        $aboutForm.Dispose()
    }
})

$btnExportProfile = New-Object System.Windows.Forms.Button
$btnExportProfile.Text = "[ Export Profile ]"
$btnExportProfile.Location = New-Object System.Drawing.Point(150, 725)
$btnExportProfile.Size = New-Object System.Drawing.Size(130, 25)
$btnExportProfile.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 65, 85)
$btnExportProfile.ForeColor = [System.Drawing.Color]::White
$btnExportProfile.FlatStyle = "Flat"
$btnExportProfile.Anchor = 'Bottom, Left'
$btnExportProfile.Add_MouseEnter({ Show-Description "Exports your active Registry tweaks, SRP locks, Services state, and Affinity Lasso roster into a portable JSON snapshot." })
$btnExportProfile.Add_MouseLeave({ Restore-Log })
$btnExportProfile.Add_Click({ Export-WinUltixProfile })

$btnImportProfile = New-Object System.Windows.Forms.Button
$btnImportProfile.Text = "[ Import Profile ]"
$btnImportProfile.Location = New-Object System.Drawing.Point(290, 725)
$btnImportProfile.Size = New-Object System.Drawing.Size(130, 25)
$btnImportProfile.BackColor = [System.Drawing.Color]::FromArgb(255, 85, 50, 50)
$btnImportProfile.ForeColor = [System.Drawing.Color]::White
$btnImportProfile.FlatStyle = "Flat"
$btnImportProfile.Anchor = 'Bottom, Left'
$btnImportProfile.Add_MouseEnter({ Show-Description "Imports and enforces a previously saved WinUltix JSON configuration snapshot on this machine." })
$btnImportProfile.Add_MouseLeave({ Restore-Log })
$btnImportProfile.Add_Click({ Import-WinUltixProfile })

$global:form.Controls.AddRange(@(
    $btnClearLog, $btnExportLog, $global:progBar, 
    $btnCredits, $btnExportProfile, $btnImportProfile, 
    $global:descBox, $global:tabControl, $global:infoBox
))

# ------------------------------------------
# 5. INITIALIZE AND LAUNCH
# ------------------------------------------
foreach ($tab in $global:tabControl.TabPages) { 
    foreach ($ctrl in $tab.Controls) { 
        if ($ctrl -is [System.Windows.Forms.Button]) {
            $ctrl.Add_MouseLeave({ Restore-Log }) 
        }
    } 
}

Update-DNSLabel
try {
    [void]$global:form.ShowDialog()
} finally {
    $global:form.Dispose()
}
