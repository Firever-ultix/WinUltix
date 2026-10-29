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