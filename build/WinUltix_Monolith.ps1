# WINULTIX v3.14 - ZERO-WMI MONOLITH (https://github.com/Firever-ultix/WinUltix)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path -LiteralPath $PSCommandPath)) {
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
} else {
Write-Warning "WinUltix requires Administrator privileges. Please launch PowerShell / Terminal as Administrator."
}
return
}
$Global:AppVersion = "v3.14"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($script:MyInvocation.MyCommand.Path) { Split-Path $script:MyInvocation.MyCommand.Path } else { "" }
$baselineFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($fn in (Get-ChildItem -Path Function:\)) {
[void]$baselineFunctions.Add($fn.Name)
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ([System.Management.Automation.PSTypeName]'WinUltix.NativeMethods').Type -and
-not [string]::IsNullOrWhiteSpace($env:WINULTIX_HOST_EXE) -and
[System.IO.File]::Exists($env:WINULTIX_HOST_EXE)) {
try { [void][System.Reflection.Assembly]::LoadFrom($env:WINULTIX_HOST_EXE) } catch { }
}
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
public static class PrivilegeEnabler {
private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
private const uint TOKEN_DUPLICATE = 0x0002;
private const uint TOKEN_IMPERSONATE = 0x0004;
private const uint TOKEN_QUERY = 0x0008;
private const uint TOKEN_ALL_ACCESS = 0x000F01FF;
private const uint SC_MANAGER_CONNECT = 0x0001;
private const uint SERVICE_CHANGE_CONFIG = 0x0002;
private const uint SERVICE_START = 0x0010;
private const uint SERVICE_NO_CHANGE = 0xFFFFFFFF;
[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
private static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
private static extern bool OpenProcessToken(IntPtr h, uint acc, ref IntPtr phtok);
[DllImport("advapi32.dll", SetLastError = true)]
private static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
[DllImport("advapi32.dll", SetLastError = true)]
private static extern bool DuplicateTokenEx(
IntPtr hExistingToken, uint dwDesiredAccess, IntPtr lpTokenAttributes,
int ImpersonationLevel, int TokenType, out IntPtr phNewToken);
[DllImport("advapi32.dll", SetLastError = true)]
private static extern bool ImpersonateLoggedOnUser(IntPtr hToken);
[DllImport("advapi32.dll", SetLastError = true)]
private static extern bool RevertToSelf();
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
private static extern bool CloseServiceHandle(IntPtr hSCObject);
[DllImport("kernel32.dll", ExactSpelling = true)]
private static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll", SetLastError = true)]
private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
[DllImport("kernel32.dll", SetLastError = true)]
private static extern bool CloseHandle(IntPtr hObject);
[StructLayout(LayoutKind.Sequential, Pack = 1)]
private struct TokPriv1Luid {
public int Count;
public long Luid;
public int Attr;
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
private static bool ImpersonateSystem() {
EnablePrivilege("SeDebugPrivilege");
foreach (string procName in new string[] { "winlogon", "services" }) {
System.Diagnostics.Process[] procs = System.Diagnostics.Process.GetProcessesByName(procName);
foreach (System.Diagnostics.Process p in procs) {
IntPtr hProc = IntPtr.Zero;
IntPtr hTok  = IntPtr.Zero;
IntPtr hDup  = IntPtr.Zero;
try {
hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, p.Id);
if (hProc == IntPtr.Zero) continue;
if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_IMPERSONATE | TOKEN_QUERY, ref hTok)) continue;
if (!DuplicateTokenEx(hTok, TOKEN_ALL_ACCESS, IntPtr.Zero, 2, 2, out hDup)) continue;
if (ImpersonateLoggedOnUser(hDup)) return true;
} catch {
} finally {
if (hDup  != IntPtr.Zero) CloseHandle(hDup);
if (hTok  != IntPtr.Zero) CloseHandle(hTok);
if (hProc != IntPtr.Zero) CloseHandle(hProc);
p.Dispose();
}
}
}
return false;
}
private const uint SERVICE_STOP = 0x0020;
private const uint SERVICE_CONTROL_STOP = 0x00000001;
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
[DllImport("advapi32.dll", SetLastError = true)]
private static extern bool ControlService(IntPtr hService, uint dwControl, out SERVICE_STATUS lpServiceStatus);
public static bool SetServiceConfigLive(string serviceName, int startType, bool startNow) {
if (string.IsNullOrWhiteSpace(serviceName)) return false;
bool changeConfig = (startType >= 0 && startType <= 4);
uint access = (changeConfig ? SERVICE_CHANGE_CONFIG : 0U) | (startNow ? SERVICE_START : 0U);
if (access == 0U) return false;
bool impersonated = false;
IntPtr hScm = IntPtr.Zero;
IntPtr hSvc = IntPtr.Zero;
try {
hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
if (hScm != IntPtr.Zero) {
hSvc = OpenServiceW(hScm, serviceName, access);
}
if (hSvc == IntPtr.Zero) {
if (hScm != IntPtr.Zero) { CloseServiceHandle(hScm); hScm = IntPtr.Zero; }
impersonated = ImpersonateSystem();
if (!impersonated) return false;
hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
if (hScm == IntPtr.Zero) return false;
hSvc = OpenServiceW(hScm, serviceName, access);
if (hSvc == IntPtr.Zero) return false;
}
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
if (impersonated) RevertToSelf();
}
}
public static bool StopServiceLive(string serviceName) {
if (string.IsNullOrWhiteSpace(serviceName)) return false;
bool impersonated = false;
IntPtr hScm = IntPtr.Zero;
IntPtr hSvc = IntPtr.Zero;
try {
hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
if (hScm != IntPtr.Zero) {
hSvc = OpenServiceW(hScm, serviceName, SERVICE_STOP);
}
if (hSvc == IntPtr.Zero) {
if (hScm != IntPtr.Zero) { CloseServiceHandle(hScm); hScm = IntPtr.Zero; }
impersonated = ImpersonateSystem();
if (!impersonated) return false;
hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
if (hScm == IntPtr.Zero) return false;
hSvc = OpenServiceW(hScm, serviceName, SERVICE_STOP);
if (hSvc == IntPtr.Zero) return false;
}
SERVICE_STATUS status;
return ControlService(hSvc, SERVICE_CONTROL_STOP, out status);
} finally {
if (hSvc != IntPtr.Zero) CloseServiceHandle(hSvc);
if (hScm != IntPtr.Zero) CloseServiceHandle(hScm);
if (impersonated) RevertToSelf();
}
}
}
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IApplicationActivationManager {
IntPtr ActivateApplication([In] String appUserModelId, [In] String arguments, [In] UInt32 options, [Out] out UInt32 processId);
}
[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
public class AppActivator : IApplicationActivationManager {
[MethodImpl(MethodImplOptions.InternalCall, MethodCodeType = MethodCodeType.Runtime)]
public extern IntPtr ActivateApplication([In] String appUserModelId, [In] String arguments, [In] UInt32 options, [Out] out UInt32 processId);
}
public class ListViewColumnSorter : IComparer {
public int ColumnToSort = 0;
public SortOrder OrderOfSort = SortOrder.None;
private CaseInsensitiveComparer ObjectCompare = new CaseInsensitiveComparer();
private static bool TryParseSortableNumber(string s, out double val) {
val = 0;
if (string.IsNullOrWhiteSpace(s)) return false;
string clean = s.Trim();
if (clean.Length > 7 && clean.StartsWith("oem", StringComparison.OrdinalIgnoreCase) && clean.EndsWith(".inf", StringComparison.OrdinalIgnoreCase)) {
string numPart = clean.Substring(3, clean.Length - 7);
if (double.TryParse(numPart, NumberStyles.Integer, CultureInfo.InvariantCulture, out val)) return true;
}
if (clean.StartsWith("Max:", StringComparison.OrdinalIgnoreCase)) {
clean = clean.Substring(4).Trim();
}
int usIdx = clean.IndexOf(" \u00B5s", StringComparison.OrdinalIgnoreCase);
if (usIdx < 0) usIdx = clean.IndexOf(" us", StringComparison.OrdinalIgnoreCase);
if (usIdx > 0) {
clean = clean.Substring(0, usIdx).Trim();
}
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
if (compareResult == 0 && listviewX.SubItems.Count > 1 && listviewY.SubItems.Count > 1) {
compareResult = ObjectCompare.Compare(listviewX.SubItems[1].Text, listviewY.SubItems[1].Text);
}
return compareResult;
}
}
public class CoreRecord {
public byte Flags;
public byte EfficiencyClass;
public long Mask;
}
public class L3CacheRecord {
public uint SizeBytes;
public long Mask;
}
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
dpcCounts[i] = (uint)Marshal.ReadInt32(buf, (i * structSize) + 4);
}
return dpcCounts;
} finally {
Marshal.FreeHGlobal(buf);
}
}
}
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
private static volatile bool _running = false;
private static string _activeSessionName = "WinUltix_DpcProfiler";
private static ulong _sessionHandle = 0;
private static ulong _traceHandle = 0;
private static System.Threading.Thread _workerThread = null;
private static KernelModuleRange[] _modules = new KernelModuleRange[0];
private static long[] _windowTicks = new long[0];
private static long[] _windowCounts = new long[0];
private static long[] _totalTicks = new long[0];
private static long[] _totalCounts = new long[0];
private static long[] _sessionPeakTicks = new long[0];
private static long _sessionStartQpc = 0;
private static long _qpcFreq = 10000000L;
private static long _maxSaneTicks = 5000000L;
public static bool IsRunning { get { return _running; } }
private static void LoadKernelModules() {
PrivilegeEnabler.EnablePrivilege("SeDebugPrivilege");
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
_modules          = list.ToArray();
_windowTicks      = new long[_modules.Length];
_windowCounts     = new long[_modules.Length];
_totalTicks       = new long[_modules.Length];
_totalCounts      = new long[_modules.Length];
_sessionPeakTicks = new long[_modules.Length];
QueryPerformanceCounter(out _sessionStartQpc);
} finally {
Marshal.FreeHGlobal(buf);
}
}
public static void ResetStats() {
long now;
QueryPerformanceCounter(out now);
System.Threading.Interlocked.Exchange(ref _sessionStartQpc, now);
for (int i = 0; i < _modules.Length; i++) {
System.Threading.Interlocked.Exchange(ref _windowTicks[i], 0);
System.Threading.Interlocked.Exchange(ref _windowCounts[i], 0);
System.Threading.Interlocked.Exchange(ref _totalTicks[i], 0);
System.Threading.Interlocked.Exchange(ref _totalCounts[i], 0);
System.Threading.Interlocked.Exchange(ref _sessionPeakTicks[i], 0);
}
}
private static int FindModuleIndex(ulong routineAddr) {
KernelModuleRange[] mods = _modules;
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
int idx = FindModuleIndex(routine);
if (idx < 0) return;
long delta = exitTs - initTs;
if (delta < 0 || delta > _maxSaneTicks) delta = 0;
System.Threading.Interlocked.Add(ref _windowTicks[idx], delta);
System.Threading.Interlocked.Increment(ref _windowCounts[idx]);
System.Threading.Interlocked.Add(ref _totalTicks[idx], delta);
System.Threading.Interlocked.Increment(ref _totalCounts[idx]);
long curPeak = System.Threading.Interlocked.Read(ref _sessionPeakTicks[idx]);
if (delta > curPeak) {
System.Threading.Interlocked.Exchange(ref _sessionPeakTicks[idx], delta);
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
if (_running) return true;
if (IntPtr.Size != 8) return false;
long freq;
if (QueryPerformanceFrequency(out freq) && freq > 0) {
_qpcFreq = freq;
_maxSaneTicks = freq / 2;
}
LoadKernelModules();
if (_modules.Length == 0) return false;
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
IntPtr logfile = Marshal.AllocHGlobal(448);
IntPtr loggerNamePtr = Marshal.StringToHGlobalUni(_activeSessionName);
try {
for (int i = 0; i < 448; i++) Marshal.WriteByte(logfile, i, 0);
Marshal.WriteIntPtr(logfile, 8, loggerNamePtr);
uint traceMode = PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD | PROCESS_TRACE_MODE_RAW_TIMESTAMP;
Marshal.WriteInt32(logfile, 28, unchecked((int)traceMode));
IntPtr cbPtr = Marshal.GetFunctionPointerForDelegate(_callbackDelegate);
Marshal.WriteIntPtr(logfile, 424, cbPtr);
_traceHandle = OpenTraceW(logfile);
} finally {
Marshal.FreeHGlobal(loggerNamePtr);
Marshal.FreeHGlobal(logfile);
}
if (_traceHandle == 0 || _traceHandle == unchecked((ulong)-1L)) {
Stop();
return false;
}
QueryPerformanceCounter(out _sessionStartQpc);
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
public static void Stop() {
_running = false;
if (_traceHandle != 0 && _traceHandle != unchecked((ulong)-1L)) {
try { CloseTrace(_traceHandle); } catch { }
_traceHandle = 0;
}
if (_sessionHandle != 0 || !string.IsNullOrEmpty(_activeSessionName)) {
IntPtr props = AllocTraceProperties(_activeSessionName, SystemTraceControlGuid, EVENT_TRACE_REAL_TIME_MODE);
try { ControlTraceW(_sessionHandle, _activeSessionName, props, EVENT_TRACE_CONTROL_STOP); } catch { }
finally { Marshal.FreeHGlobal(props); }
_sessionHandle = 0;
}
if (_workerThread != null && _workerThread.IsAlive) {
try { _workerThread.Join(400); } catch { }
_workerThread = null;
}
}
public static List<DriverLoadRecord> SampleDriverLoads() {
var results = new List<DriverLoadRecord>();
if (!_running || _modules.Length == 0) return results;
long nowQpc;
QueryPerformanceCounter(out nowQpc);
long startQpc = System.Threading.Interlocked.Read(ref _sessionStartQpc);
double elapsedSec = Math.Max(1.0, (double)(nowQpc - startQpc) / (double)_qpcFreq);
int elapsedInt = Math.Max(1, (int)Math.Round(elapsedSec));
double tickToUs = 1000000.0 / (double)_qpcFreq;
for (int i = 0; i < _modules.Length; i++) {
long winTicks  = System.Threading.Interlocked.Exchange(ref _windowTicks[i], 0);
long winCounts = System.Threading.Interlocked.Exchange(ref _windowCounts[i], 0);
long totTicks  = System.Threading.Interlocked.Read(ref _totalTicks[i]);
long totCounts = System.Threading.Interlocked.Read(ref _totalCounts[i]);
long peakTicks = System.Threading.Interlocked.Read(ref _sessionPeakTicks[i]);
if (totCounts > 0 || winCounts > 0 || peakTicks > 0) {
results.Add(new DriverLoadRecord {
DriverName  = _modules[i].DriverName,
ServiceKey  = _modules[i].ServiceKey,
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
var res = new HubProbeResult();
if (string.IsNullOrEmpty(hubInstanceId)) return res;
string symPath = @"\\?\" + hubInstanceId.Replace('\\', '#') + "#{f18a0e88-c30c-11d0-8815-00a0c906bed8}";
IntPtr hHub = CreateFileW(symPath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
if (hHub == IntPtr.Zero || hHub == new IntPtr(-1)) {
hHub = CreateFileW(symPath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
}
if (hHub == IntPtr.Zero || hHub == new IntPtr(-1)) return res;
IntPtr bufNode = Marshal.AllocHGlobal(128);
IntPtr bufV2   = Marshal.AllocHGlobal(32);
IntPtr bufEx   = Marshal.AllocHGlobal(64);
try {
for (int i = 0; i < 128; i++) Marshal.WriteByte(bufNode, i, 0);
uint ret = 0;
if (!DeviceIoControl(hHub, IOCTL_USB_GET_NODE_INFORMATION, bufNode, 76, bufNode, 76, out ret, IntPtr.Zero)) {
return res;
}
int numPorts = Marshal.ReadByte(bufNode, 6);
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
bool isOperatingSsPlus = ((v2Flags & 0x04) != 0);
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
} finally {
Marshal.FreeHGlobal(bufNode);
Marshal.FreeHGlobal(bufV2);
Marshal.FreeHGlobal(bufEx);
CloseHandle(hHub);
}
return res;
}
}
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
if ([string]::IsNullOrWhiteSpace($resolvedIco)) {
$cacheDir = Join-Path $env:LOCALAPPDATA "WinUltix"
$cacheIco = Join-Path $cacheDir "WinUltix.ico"
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
if ($results.Count -eq 0) {
$cimProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction SilentlyContinue)
foreach ($prof in $cimProfiles) {
if ([string]::IsNullOrWhiteSpace($prof.LocalPath)) { continue }
$localPath = $prof.LocalPath.TrimEnd('\')
$userName  = [System.IO.Path]::GetFileName($localPath)
if ($userName -match '^(?i)(Public|Default.*|All Users)$') { continue }
$sid      = [string]$prof.SID
$hiveRoot = if (-not [string]::IsNullOrWhiteSpace($sid)) { "Registry::HKEY_USERS\$sid" } else { "" }
$isLoaded = (-not [string]::IsNullOrWhiteSpace($hiveRoot)) -and (Test-Path -LiteralPath $hiveRoot)
if ([string]::IsNullOrWhiteSpace($sid) -or $seenSids.Add($sid)) {
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
[Parameter(Mandatory=$true)][int]$StartValue,
[switch]$StartService
)
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
if (-not (Test-Path -LiteralPath $regPath)) { return }
try {
Set-ItemProperty -LiteralPath $regPath -Name "Start" -Value $StartValue -Type DWord -Force -ErrorAction Stop
} catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
[WinUltix.PrivilegeEnabler]::EnablePrivilege("SeTakeOwnershipPrivilege")
[WinUltix.PrivilegeEnabler]::EnablePrivilege("SeRestorePrivilege")
$subKeyPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"
$adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
$keyOwn = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
if ($null -ne $keyOwn) {
try {
$aclOwn = $keyOwn.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
$aclOwn.SetOwner($adminSid)
$keyOwn.SetAccessControl($aclOwn)
} finally {
$keyOwn.Dispose()
}
}
$keyAcl = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
if ($null -ne $keyAcl) {
try {
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
} finally {
$keyAcl.Dispose()
}
}
Set-ItemProperty -LiteralPath $regPath -Name "Start" -Value $StartValue -Type DWord -Force -ErrorAction Stop
}
if ($null -ne ([WinUltix.PrivilegeEnabler].GetMethod("SetServiceConfigLive"))) {
[void][WinUltix.PrivilegeEnabler]::SetServiceConfigLive($ServiceName, $StartValue, $StartService.IsPresent)
} elseif ($StartService.IsPresent -and $StartValue -ne 4) {
Start-Service -Name $ServiceName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
"usbhub3.inf" {
if ($infToken -match 'usb30hub') { return "Generic SuperSpeed USB Hub" }
if ($infToken -match 'usb20hub') { return "Generic USB Hub" }
}
}
$clean = $restPart
}
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
$ntCur = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName", "DisplayVersion", "ReleaseId", "CurrentBuild", "UBR" -ErrorAction SilentlyContinue
$prodName = if ($null -ne $ntCur -and $ntCur.ProductName) { [string]$ntCur.ProductName } else { "Windows OS" }
$buildNum = if ($null -ne $ntCur -and $ntCur.CurrentBuild) { [int]$ntCur.CurrentBuild } else { [Environment]::OSVersion.Version.Build }
if ($buildNum -ge 22000 -and $prodName -match 'Windows 10') {
$prodName = $prodName -replace 'Windows 10', 'Windows 11'
}
$dispVer = if ($null -ne $ntCur -and $ntCur.DisplayVersion) { [string]$ntCur.DisplayVersion } elseif ($null -ne $ntCur -and $ntCur.ReleaseId) { [string]$ntCur.ReleaseId } else { "" }
$ubr     = if ($null -ne $ntCur -and $null -ne $ntCur.UBR) { ".$($ntCur.UBR)" } else { "" }
$osStr   = "$prodName $(if($dispVer){"$dispVer "})(Build $buildNum$ubr)"
$biosProps = Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\Description\System\BIOS" -Name "BaseBoardProduct" -ErrorAction SilentlyContinue
$boardStr  = if ($null -ne $biosProps -and -not [string]::IsNullOrWhiteSpace($biosProps.BaseBoardProduct)) { " | Board: $($biosProps.BaseBoardProduct.Trim())" } else { "" }
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
$rawRamKB = [uint64][WinUltix.NativeMethods]::GetTotalPhysicalMemoryKB()
$ramStr   = [WinUltix.SmbiosRamInfo]::GetRamSummary($rawRamKB)
$activeMt = if ($ramStr -match '@\s*(\d+)\s*MT/s') { [int]$matches[1] } else { 0 }
$specMt = 0
$specCl = 0
if ($ramStr -match '(?i)(?:^|[^0-9])([2-9]\d00)[A-Z0-9]{0,5}?(?:CL|[CJZL])(\d{2})(?:[^0-9]|$)') {
$specMt = [int]$matches[1]
$specCl = [int]$matches[2]
}
elseif ($ramStr -match '(?i)(?:KF[45]|G)(\d{2,3})C(\d{2})\b') {
$rawSpd = [int]$matches[1]
$specMt = if ($rawSpd -lt 100) { $rawSpd * 100 } else { $rawSpd * 10 }
$specCl = [int]$matches[2]
}
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
function Update-DNSLabel {
if ($null -eq $global:lblCurrentDNS -or $global:lblCurrentDNS.IsDisposed) { return }
try {
$activeNic = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
$_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
$_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
@($_.GetIPProperties().GatewayAddresses | Where-Object { $_.Address.ToString() -notin @("0.0.0.0", "::") }).Count -gt 0
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
$global:UltixColors = @{
Standard  = @(55, 58, 64)    # Matte Slate: Standard OS tweaks, cleaners, and repairs
Inspector = @(45, 85, 125)   # Steel Blue: Interactive grid inspectors, analyzers, and safe profiles
Danger    = @(135, 50, 50)   # Deep Crimson: Aggressive/destructive actions and hard kernel locks
Audit     = @(72, 76, 82)    # Neutral Gray: All [?] audit buttons
Add       = @(45, 95, 60)    # Muted Green: [+] add target buttons
TabBg     = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
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
function Invoke-AsyncTask {
param(
[Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
[array]$Arguments = @(),
[Parameter(Mandatory=$true)][scriptblock]$OnComplete,
[System.Windows.Forms.Control[]]$ControlsToDisable = @(),
[int]$PollIntervalMs = 150
)
if ($null -ne $UltixSync) {
$nestedOut = & $ScriptBlock @Arguments
if ($null -ne $OnComplete) { & $OnComplete $nestedOut }
return
}
foreach ($ctrl in $ControlsToDisable) {
if ($null -ne $ctrl -and -not $ctrl.IsDisposed) { $ctrl.Enabled = $false }
}
$syncContext = [hashtable]::Synchronized(@{
Logs     = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
Progress = -1
})
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
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList "Write-GUI", 'param([AllowEmptyString()][string]$Message, [switch]$DeferUpdate) if ($null -ne $UltixSync -and -not [string]::IsNullOrWhiteSpace($Message)) { $UltixSync.Logs.Enqueue($Message) }'))
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList "Update-Progress", 'param([int]$Percent) if ($null -ne $UltixSync) { $UltixSync.Progress = $Percent }'))
$runspace = [runspacefactory]::CreateRunspace($iss)
$runspace.ApartmentState = "STA"
$runspace.ThreadOptions  = "ReuseThread"
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("UltixSync", $syncContext)
$runspace.SessionStateProxy.SetVariable("AppVersion", $Global:AppVersion)
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
$modal.MinimumSize = New-Object System.Drawing.Size(780, 680)
$modal.StartPosition = "CenterParent"
$modal.FormBorderStyle = "Sizable"
$modal.MaximizeBox = $true
$modal.MinimizeBox = $false
$modal.BackColor = [System.Drawing.Color]::FromArgb(255, 26, 27, 30)
$modal.ForeColor = [System.Drawing.Color]::White
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = $Description
$lblDesc.Location = New-Object System.Drawing.Point(15, 12)
$lblDesc.Size = New-Object System.Drawing.Size(730, 38)
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(255, 215, 220, 228)
$lblDesc.Anchor = 'Top, Left, Right'
$hasValidItems = ($null -ne $AuditResults -and $AuditResults.Count -gt 0)
$btnSelAll = New-Object System.Windows.Forms.Button
$btnSelAll.Text = "Select All"
$btnSelAll.Location = New-Object System.Drawing.Point(15, 54)
$btnSelAll.Size = New-Object System.Drawing.Size(105, 26)
$btnSelAll.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
$btnSelAll.FlatStyle = "Flat"
$btnSelAll.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSelAll.Enabled = $hasValidItems
$btnSelNone = New-Object System.Windows.Forms.Button
$btnSelNone.Text = "Deselect All"
$btnSelNone.Location = New-Object System.Drawing.Point(128, 54)
$btnSelNone.Size = New-Object System.Drawing.Size(105, 26)
$btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
$btnSelNone.FlatStyle = "Flat"
$btnSelNone.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSelNone.Enabled = $hasValidItems
$btnSelDet = New-Object System.Windows.Forms.Button
$btnSelDet.Text = "Select Detected"
$btnSelDet.Location = New-Object System.Drawing.Point(241, 54)
$btnSelDet.Size = New-Object System.Drawing.Size(120, 26)
$btnSelDet.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnSelDet.FlatStyle = "Flat"
$btnSelDet.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSelDet.Enabled = $hasValidItems
$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Location = New-Object System.Drawing.Point(545, 57)
$lblCount.Size = New-Object System.Drawing.Size(200, 20)
$lblCount.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
$lblCount.ForeColor = [System.Drawing.Color]::LightGray
$lblCount.TextAlign = "MiddleRight"
$lblCount.Anchor = 'Top, Right'
$chkList = New-Object System.Windows.Forms.CheckedListBox
$chkList.Location = New-Object System.Drawing.Point(15, 88)
$chkList.Size = New-Object System.Drawing.Size(730, 480)
$chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38)
$chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
$chkList.BorderStyle = "FixedSingle"
$chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5)
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
$btnApply.Size = New-Object System.Drawing.Size(235, 35)
$btnRevert = New-Object System.Windows.Forms.Button
$btnRevert.Text = "Revert Selected"
$btnRevert.Location = New-Object System.Drawing.Point(262, 585)
$btnRevert.Size = New-Object System.Drawing.Size(235, 35)
$btnRevert.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnRevert.FlatStyle = "Flat"
$btnRevert.DialogResult = "Yes"
$btnRevert.Enabled = $hasValidItems
$btnRevert.Anchor = 'Bottom, Left'
$btnCancel.Location = New-Object System.Drawing.Point(510, 585)
$btnCancel.Size = New-Object System.Drawing.Size(235, 35)
$modal.Controls.AddRange($baseControls + @($btnApply, $btnRevert, $btnCancel))
} else {
$btnApply.Location = New-Object System.Drawing.Point(15, 585)
$btnApply.Size = New-Object System.Drawing.Size(355, 35)
$btnCancel.Location = New-Object System.Drawing.Point(390, 585)
$btnCancel.Size = New-Object System.Drawing.Size(355, 35)
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
[string]$SecondaryButtonText = "",
[switch]$SecondaryAlwaysEnabled
)
$modal = New-Object System.Windows.Forms.Form
$modal.Text = $Title
$modal.Size = New-Object System.Drawing.Size(980, 700)
$modal.MinimumSize = New-Object System.Drawing.Size(820, 560)
$modal.StartPosition = "CenterParent"
$modal.FormBorderStyle = "Sizable"
$modal.BackColor = [System.Drawing.Color]::FromArgb(255, 26, 27, 30)
$modal.ForeColor = [System.Drawing.Color]::White
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = $Description
$lblDesc.Location = New-Object System.Drawing.Point(15, 12)
$lblDesc.Size = New-Object System.Drawing.Size(930, 32)
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(255, 215, 220, 228)
$lblDesc.Anchor = 'Top, Left, Right'
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Filter:"
$lblSearch.Location = New-Object System.Drawing.Point(15, 52)
$lblSearch.Size = New-Object System.Drawing.Size(48, 22)
$lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblSearch.ForeColor = [System.Drawing.Color]::LightSkyBlue
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(65, 50)
$txtSearch.Size = New-Object System.Drawing.Size(270, 25)
$txtSearch.BackColor = [System.Drawing.Color]::FromArgb(255, 38, 40, 45)
$txtSearch.ForeColor = [System.Drawing.Color]::White
$txtSearch.BorderStyle = "FixedSingle"
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnSelVis = New-Object System.Windows.Forms.Button
$btnSelVis.Text = "Select Visible"
$btnSelVis.Location = New-Object System.Drawing.Point(345, 49)
$btnSelVis.Size = New-Object System.Drawing.Size(115, 26)
$btnSelVis.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
$btnSelVis.FlatStyle = "Flat"
$btnSelVis.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSelNone = New-Object System.Windows.Forms.Button
$btnSelNone.Text = "Deselect All"
$btnSelNone.Location = New-Object System.Drawing.Point(468, 49)
$btnSelNone.Size = New-Object System.Drawing.Size(115, 26)
$btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
$btnSelNone.FlatStyle = "Flat"
$btnSelNone.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Location = New-Object System.Drawing.Point(600, 52)
$lblCount.Size = New-Object System.Drawing.Size(345, 20)
$lblCount.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
$lblCount.ForeColor = [System.Drawing.Color]::LightGray
$lblCount.TextAlign = "MiddleRight"
$lblCount.Anchor = 'Top, Right'
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, 84)
$listView.Size = New-Object System.Drawing.Size(935, 504)
$listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
$listView.BorderStyle = "FixedSingle"
$listView.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Regular)
$listView.View = [System.Windows.Forms.View]::Details
$listView.CheckBoxes = $true
$listView.FullRowSelect = $true
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
$updateCounter = {
$lblCount.Text = "Selected: $($checkedIds.Count) / $($indexedData.Count) (Showing: $($listView.Items.Count))"
}
$applyRowShading = {
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
}
$populateList = {
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
$btnPrimary.Location = New-Object System.Drawing.Point(15, 602)
$btnPrimary.Size = New-Object System.Drawing.Size(295, 38)
$btnSecondary = New-Object System.Windows.Forms.Button
$btnSecondary.Text = $SecondaryButtonText
$btnSecondary.Location = New-Object System.Drawing.Point(322, 602)
$btnSecondary.Size = New-Object System.Drawing.Size(295, 38)
$btnSecondary.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnSecondary.ForeColor = [System.Drawing.Color]::White
$btnSecondary.FlatStyle = "Flat"
$btnSecondary.DialogResult = [System.Windows.Forms.DialogResult]::Yes
$btnSecondary.Enabled = ($SecondaryAlwaysEnabled.IsPresent -or $indexedData.Count -gt 0)
$btnSecondary.Anchor = 'Bottom, Left'
$btnCancel.Location = New-Object System.Drawing.Point(630, 602)
$btnCancel.Size = New-Object System.Drawing.Size(320, 38)
$controlsToAdd += $btnSecondary
} else {
$btnPrimary.Location = New-Object System.Drawing.Point(15, 602)
$btnPrimary.Size = New-Object System.Drawing.Size(455, 38)
$btnCancel.Location = New-Object System.Drawing.Point(495, 602)
$btnCancel.Size = New-Object System.Drawing.Size(455, 38)
}
$modal.Controls.AddRange($controlsToAdd)
$modal.CancelButton = $btnCancel
try {
$dlgRes = $modal.ShowDialog($global:form)
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
$activePowerDisplay = [System.Collections.Generic.List[string]]::new()
if (Get-Command Get-PowerDisplayState -ErrorAction SilentlyContinue) {
foreach ($pItem in (Get-PowerDisplayState)) {
if (-not $pItem.IsDetected) {
$cleanKey = ($pItem.UIDisplayName -replace '\s*\(Current[^)]*\)\s*$', '').Trim()
$activePowerDisplay.Add($cleanKey)
}
}
}
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
$snapshot = [ordered]@{
SchemaVersion           = "WinUltix_Snapshot_v1"
AppVersion              = $AppVersion
ExportTimestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
SourceMachine           = $env:COMPUTERNAME
Win32PrioritySeparation = $exactQuantum
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
$snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding UTF8 -Force -ErrorAction Stop
$UltixSync.Progress = 100
$hwCount = @($hwSnapshot.TimerTweaks).Count + @($hwSnapshot.NVMeTweaks).Count + @($hwSnapshot.CPPCUnhidden).Count
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
$srpCount = @($profileData.ActiveSrpLocks).Count
$affCount = @($profileData.AffinityLasso).Count
$confirmMsg = "Loaded snapshot from '$($profileData.SourceMachine)' ($($profileData.ExportTimestamp)):`n`n" +
" - Registry Tweaks: $regCount`n" +
" - Power & Display Optimizations: $pwrCount`n" +
" - USB Perimeter Locks: $usbCount`n" +
" - Disabled Services: $svcCount`n" +
" - SRP+IFEO Locks: $srpCount`n" +
" - Affinity Lasso Roster: $affCount`n`n" +
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
if ($null -ne $Snapshot.CustomSrpRoster) {
$customSrpKey = "HKLM:\SOFTWARE\WinUltix\SRP"
if (-not (Test-Path -LiteralPath $customSrpKey)) { New-Item -Path $customSrpKey -Force | Out-Null }
foreach ($prop in $Snapshot.CustomSrpRoster.PSObject.Properties) {
Set-ItemProperty -LiteralPath $customSrpKey -Name $prop.Name -Value $prop.Value -Type String -Force
}
}
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
if (-not (Test-Path -LiteralPath $prioKey)) { New-Item -Path $prioKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $prioKey -Name "Win32PrioritySeparation" -Value $savedQuantum -Type DWord -Force
$UltixSync.Logs.Enqueue((" -> Restored Quantum Scheduler (Win32PrioritySeparation = 0x{0:X2} / {0} dec)." -f $savedQuantum))
}
$UltixSync.Progress = 35
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
if (@($Snapshot.ActiveSrpLocks).Count -gt 0 -and (Get-Command Get-RegState_SRP -ErrorAction SilentlyContinue)) {
$srpSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($s in $Snapshot.ActiveSrpLocks) { [void]$srpSet.Add([string]$s) }
$toApplySrp = @(Get-RegState_SRP | Where-Object { $srpSet.Contains($_.UIDisplayName) -and $_.IsDetected })
if ($toApplySrp.Count -gt 0) {
Invoke-ApplySRP -SelectedItems $toApplySrp -Operation "Apply"
}
}
$UltixSync.Progress = 80
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
if (@($Snapshot.DisabledTasks).Count -gt 0 -and (Get-Command Get-TelemetryTasksState -ErrorAction SilentlyContinue)) {
$taskSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($tk in $Snapshot.DisabledTasks) { [void]$taskSet.Add([string]$tk) }
$toApplyTasks = @(Get-TelemetryTasksState | Where-Object { $taskSet.Contains($_.UIDisplayName) -and $_.IsDetected })
if ($toApplyTasks.Count -gt 0) {
Invoke-ApplyTasks -SelectedItems $toApplyTasks -Operation "Apply"
}
}
$UltixSync.Progress = 90
if (Get-Command Import-UltixHardwareSnapshot -ErrorAction SilentlyContinue) {
Import-UltixHardwareSnapshot -ProfileData $Snapshot
} elseif (@($Snapshot.AffinityLasso).Count -gt 0) {
$affPath = "HKCU:\Software\WinUltix\AffinityLasso"
if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force | Out-Null }
foreach ($exe in $Snapshot.AffinityLasso) {
Set-ItemProperty -LiteralPath $affPath -Name $exe -Value 1 -Type DWord -Force
}
$UltixSync.Logs.Enqueue(" -> Restored $(@($Snapshot.AffinityLasso).Count) process(es) to Affinity Lasso roster.")
}
$UltixSync.Progress = 100
return ,$modifiedRegItems
} -OnComplete ({
param($modReg)
Update-Progress 0
if ($null -ne $modReg -and @($modReg).Count -gt 0) {
Update-ShellEnvironment -ModifiedItems @($modReg)
}
Write-GUI "=== PROFILE IMPORT COMPLETED ===`n"
}.GetNewClosure())
}
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
$rules.Add(@{ UIDisplayName = "Windows Prefetch"; Path = "$env:windir\Prefetch"; Paths = @("$env:windir\Prefetch"); Type = "Files" })
$rules.Add(@{ UIDisplayName = "WER Report Archive (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive"); Type = "Files" })
$rules.Add(@{ UIDisplayName = "WER Report Queue (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue"); Type = "Files" })
if ([System.IO.File]::Exists("$env:windir\MEMORY.DMP")) {
$rules.Add(@{ UIDisplayName = "System Memory Dump"; Path = "$env:windir\MEMORY.DMP"; Paths = @("$env:windir\MEMORY.DMP"); Type = "Files" })
}
if ([System.IO.Directory]::Exists("$env:windir\Minidump")) {
$rules.Add(@{ UIDisplayName = "Minidump Files"; Path = "$env:windir\Minidump"; Paths = @("$env:windir\Minidump"); Type = "Files" })
}
$userProfiles    = @(Get-UltixUserProfiles)
$profileTempDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($prof in $userProfiles) {
$userName = $prof.UserName
$base     = $prof.LocalPath
$uTemp    = "$base\AppData\Local\Temp"
try {
[void]$profileTempDirs.Add([System.IO.Path]::GetFullPath($uTemp).TrimEnd('\'))
} catch {
[void]$profileTempDirs.Add($uTemp.TrimEnd('\'))
}
$rules.Add(@{ UIDisplayName = "User Temp ($userName)"; Path = $uTemp; Paths = @($uTemp); Type = "Files" })
$userWerPaths = @(
"$base\AppData\Local\Microsoft\Windows\WER\ReportArchive",
"$base\AppData\Local\Microsoft\Windows\WER\ReportQueue"
)
if ([System.IO.Directory]::Exists($userWerPaths[0]) -or [System.IO.Directory]::Exists($userWerPaths[1])) {
$rules.Add(@{ UIDisplayName = "User WER Reports ($userName)"; Path = $userWerPaths[0]; Paths = $userWerPaths; Type = "Files" })
}
}
if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
$envTempNorm = try { [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') } catch { $env:TEMP.TrimEnd('\') }
if (-not $profileTempDirs.Contains($envTempNorm) -and [System.IO.Directory]::Exists($envTempNorm)) {
$rules.Add(@{ UIDisplayName = "Custom Environment Temp ($envTempNorm)"; Path = $envTempNorm; Paths = @($envTempNorm); Type = "Files" })
}
}
}
if ($Category -eq "EventLogs") {
$rules.Add(@{ UIDisplayName = "Windows Event Logs"; Path = "$env:windir\System32\winevt\Logs"; Paths = @("$env:windir\System32\winevt\Logs"); Type = "EventLogs" })
}
if ($Category -eq "ThirdParty") {
$chromiumBrowsers = @(
@{ Name = "Chrome";  RelUserData = "AppData\Local\Google\Chrome\User Data" }
@{ Name = "Edge";    RelUserData = "AppData\Local\Microsoft\Edge\User Data" }
@{ Name = "Brave";   RelUserData = "AppData\Local\BraveSoftware\Brave-Browser\User Data" }
@{ Name = "Vivaldi"; RelUserData = "AppData\Local\Vivaldi\User Data" }
)
$userCaches = @(
@{
Name      = "Opera Cache"
DetectDir = "AppData\Local\Opera Software\Opera Stable"
RelPaths  = @(
"AppData\Local\Opera Software\Opera Stable\Cache",
"AppData\Local\Opera Software\Opera Stable\Cache\Cache_Data",
"AppData\Local\Opera Software\Opera Stable\Network\Cache",
"AppData\Local\Opera Software\Opera Stable\Code Cache",
"AppData\Local\Opera Software\Opera Stable\GPUCache"
)
}
@{
Name      = "Opera GX Cache"
DetectDir = "AppData\Local\Opera Software\Opera GX Stable"
RelPaths  = @(
"AppData\Local\Opera Software\Opera GX Stable\Cache",
"AppData\Local\Opera Software\Opera GX Stable\Cache\Cache_Data",
"AppData\Local\Opera Software\Opera GX Stable\Network\Cache",
"AppData\Local\Opera Software\Opera GX Stable\Code Cache",
"AppData\Local\Opera Software\Opera GX Stable\GPUCache"
)
}
@{
Name      = "Discord Cache"
DetectDir = "AppData\Roaming\discord"
RelPaths  = @(
"AppData\Roaming\discord\Cache",
"AppData\Roaming\discord\Cache\Cache_Data",
"AppData\Roaming\discord\Code Cache",
"AppData\Roaming\discord\GPUCache"
)
}
@{
Name      = "Steam HTML Cache"
DetectDir = "AppData\Local\Steam"
RelPaths  = @("AppData\Local\Steam\htmlcache")
}
@{
Name      = "Epic Games Cache"
DetectDir = "AppData\Local\EpicGamesLauncher"
RelPaths  = @(
"AppData\Local\EpicGamesLauncher\Saved\webcache",
"AppData\Local\EpicGamesLauncher\Saved\webcache_4430",
"AppData\Local\EpicGamesLauncher\Saved\HttpCache"
)
}
@{
Name      = "Spotify Cache"
DetectDir = "AppData\Local\Spotify"
RelPaths  = @(
"AppData\Local\Spotify\Data",
"AppData\Local\Spotify\Browser\Cache"
)
}
@{
Name      = "Deezer Cache"
DetectDir = "AppData\Roaming\deezer-desktop"
RelPaths  = @("AppData\Roaming\deezer-desktop\Cache")
}
@{
Name      = "VLC Art Cache"
DetectDir = "AppData\Roaming\vlc"
RelPaths  = @("AppData\Roaming\vlc\art")
}
@{
Name      = "DirectX D3DSCache"
DetectDir = "AppData\Local\D3DSCache"
RelPaths  = @("AppData\Local\D3DSCache")
}
@{
Name      = "NVIDIA DX & GL Shader Cache"
DetectDir = "AppData\Local\NVIDIA"
RelPaths  = @(
"AppData\Local\NVIDIA\DXCache",
"AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache",
"AppData\Local\NVIDIA\GLCache",
"AppData\Roaming\NVIDIA\ComputeCache"
)
}
@{
Name      = "AMD DX & Vulkan Shader Cache"
DetectDir = "AppData\Local\AMD"
RelPaths  = @(
"AppData\Local\AMD\DxCache",
"AppData\Local\AMD\DxcCache",
"AppData\Local\AMD\VkCache",
"AppData\Local\AMD\GLCache"
)
}
)
$globalCaches = @(
@{ Name = "Battle.net"; DetectDir = "$env:ProgramData\Battle.net";     Path = "$env:ProgramData\Battle.net\Cache" }
@{ Name = "GOG Galaxy"; DetectDir = "$env:ProgramData\GOG.com\Galaxy"; Path = "$env:ProgramData\GOG.com\Galaxy\webcache" }
)
foreach ($prof in (Get-UltixUserProfiles)) {
$usr  = $prof.UserName
$base = $prof.LocalPath
foreach ($browser in $chromiumBrowsers) {
$userDataDir = Join-Path -Path $base -ChildPath $browser.RelUserData
if (-not [System.IO.Directory]::Exists($userDataDir)) { continue }
$profDirs = @(Get-ChildItem -LiteralPath $userDataDir -Directory -Force -ErrorAction SilentlyContinue |
Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" })
if ($profDirs.Count -gt 0) {
$isFirstProf = $true
foreach ($profDir in $profDirs) {
$pName = $profDir.Name
$pFull = $profDir.FullName
$cPaths = [System.Collections.Generic.List[string]]::new()
foreach ($relSub in @("Cache", "Network\Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage", "Service Worker\ScriptCache")) {
$cPaths.Add("$pFull\$relSub")
}
if ($isFirstProf) {
$cPaths.Add("$userDataDir\ShaderCache")
$cPaths.Add("$userDataDir\GrShaderCache")
$isFirstProf = $false
}
$rules.Add(@{
UIDisplayName = "$($browser.Name) Cache ($usr - $pName)"
Path          = "$pFull\Cache"
Paths         = @($cPaths)
Type          = "Files"
})
}
}
}
foreach ($app in $userCaches) {
$detectFull = Join-Path -Path $base -ChildPath $app.DetectDir
$fullPaths  = @($app.RelPaths | ForEach-Object { Join-Path -Path $base -ChildPath $_ })
$isInstalled = [System.IO.Directory]::Exists($detectFull)
if (-not $isInstalled) {
foreach ($fp in $fullPaths) {
if ([System.IO.Directory]::Exists($fp)) { $isInstalled = $true; break }
}
}
if ($isInstalled) {
$rules.Add(@{
UIDisplayName = "$($app.Name) ($usr)"
Path          = $fullPaths[0]
Paths         = $fullPaths
Type          = "Files"
})
}
}
$ffProfilesPath = "$base\AppData\Local\Mozilla\Firefox\Profiles"
if ([System.IO.Directory]::Exists($ffProfilesPath)) {
$ffFolders = @(Get-ChildItem -LiteralPath $ffProfilesPath -Directory -Force -ErrorAction SilentlyContinue)
foreach ($ff in $ffFolders) {
$ffPaths = @(
"$($ff.FullName)\cache2",
"$($ff.FullName)\startupCache",
"$($ff.FullName)\jumpListCache"
)
$rules.Add(@{
UIDisplayName = "Firefox Cache ($usr - $($ff.Name))"
Path          = $ffPaths[0]
Paths         = $ffPaths
Type          = "Files"
})
}
}
}
foreach ($app in $globalCaches) {
if ([System.IO.Directory]::Exists($app.DetectDir) -or [System.IO.Directory]::Exists($app.Path)) {
$rules.Add(@{ UIDisplayName = "$($app.Name) Cache (Global)"; Path = $app.Path; Paths = @($app.Path); Type = "Files" })
}
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
function Invoke-InteractiveCleanup {
param(
[Parameter(Mandatory=$true)][array]$SelectedItems,
[System.Windows.Forms.Control[]]$ControlsToDisable = @()
)
if ($SelectedItems.Count -eq 0) { return }
Write-GUI " -> Dispatching cleanup worker to background Runspace..."
Update-Progress 5
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
foreach ($svcName in $servicesToManage) {
$svcObj = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($null -ne $svcObj -and $svcObj.Status -eq 'Running') {
$runningServices.Add($svcName)
Stop-Service -Name $svcName -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
}
}
if ($svcGroup -eq "CBS") {
Stop-Process -Name "TiWorker" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
}
foreach ($tPath in $targetPaths) {
if ([string]::IsNullOrWhiteSpace($tPath) -or -not (Test-Path -LiteralPath $tPath)) { continue }
if (Test-Path -LiteralPath $tPath -PathType Leaf) {
Remove-Item -LiteralPath $tPath -Force -ErrorAction SilentlyContinue
} else {
Get-ChildItem -LiteralPath $tPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
}
}
} finally {
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
function Get-DriverStoreOrphans_Worker {
if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
$activeOemInfs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$devDrvOut = (pnputil.exe /enum-devices /drivers 2>$null) -join "`n"
if (-not [string]::IsNullOrWhiteSpace($devDrvOut)) {
foreach ($m in [regex]::Matches($devDrvOut, '(?i)\b(oem\d+\.inf)\b')) {
[void]$activeOemInfs.Add($m.Groups[1].Value.ToLowerInvariant())
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 30 }
$boundDeviceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$enumRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum", $false)
if ($null -ne $enumRoot) {
try {
foreach ($busName in $enumRoot.GetSubKeyNames()) {
$busKey = $enumRoot.OpenSubKey($busName, $false)
if ($null -eq $busKey) { continue }
try {
foreach ($devName in $busKey.GetSubKeyNames()) {
$devKey = $busKey.OpenSubKey($devName, $false)
if ($null -eq $devKey) { continue }
try {
foreach ($instName in $devKey.GetSubKeyNames()) {
$instKey = $devKey.OpenSubKey($instName, $false)
if ($null -eq $instKey) { continue }
try {
$drvLink = [string]$instKey.GetValue("Driver", "")
if (-not [string]::IsNullOrWhiteSpace($drvLink)) {
[void]$boundDeviceIds.Add($drvLink)
}
} finally {
$instKey.Dispose()
}
}
} finally {
$devKey.Dispose()
}
}
} finally {
$busKey.Dispose()
}
}
} finally {
$enumRoot.Dispose()
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 45 }
$alwaysLockClasses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$alwaysLockClasses.Add("{e2f84ce7-8efa-411c-aa69-97454ca4cb57}") # Extension INF Class
[void]$alwaysLockClasses.Add("{5c4c3332-344d-483c-8739-259e934c9cc8}") # SoftwareComponent Class
$classRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Class", $false)
if ($null -ne $classRoot) {
try {
foreach ($clsGuid in $classRoot.GetSubKeyNames()) {
$clsKey = $classRoot.OpenSubKey($clsGuid, $false)
if ($null -eq $clsKey) { continue }
try {
$isAlwaysLockedClass = $alwaysLockClasses.Contains($clsGuid)
foreach ($subName in $clsKey.GetSubKeyNames()) {
if ($subName -notmatch '^\d{4}$') { continue }
$subKey = $clsKey.OpenSubKey($subName, $false)
if ($null -eq $subKey) { continue }
try {
$infPath = [string]$subKey.GetValue("InfPath", "")
if ($infPath -match '^(?i)(oem\d+\.inf)$') {
$relDrv = "$clsGuid\$subName"
if ($isAlwaysLockedClass -or $boundDeviceIds.Contains($relDrv)) {
[void]$activeOemInfs.Add($matches[1].ToLowerInvariant())
}
}
} finally {
$subKey.Dispose()
}
}
} finally {
$clsKey.Dispose()
}
}
} finally {
$classRoot.Dispose()
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 60 }
$repoBase  = "$env:SystemRoot\System32\DriverStore\FileRepository"
$oemToRepo = @{}
$drvDbRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\DriverDatabase\DriverPackages", $false)
if ($null -ne $drvDbRoot) {
try {
foreach ($pkgName in $drvDbRoot.GetSubKeyNames()) {
$pkgKey = $drvDbRoot.OpenSubKey($pkgName, $false)
if ($null -eq $pkgKey) { continue }
try {
$oemVal = [string]$pkgKey.GetValue("", "")
if ($oemVal -match '^(?i)(oem\d+\.inf)$') {
$oemToRepo[$matches[1].ToLowerInvariant()] = Join-Path $repoBase $pkgName
}
} catch {
} finally {
$pkgKey.Dispose()
}
}
} finally {
$drvDbRoot.Dispose()
}
}
$rawPnp = (pnputil.exe /enum-drivers 2>$null) -join "`n"
$blocks = $rawPnp -split "(?:\r?\n){2,}"
$parsedDrivers = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($blk in $blocks) {
if ($blk -notmatch '(?im)^\s*[^:]+:\s*(oem\d+\.inf)\s*$') { continue }
$oemInf = $matches[1].ToLowerInvariant()
$lines = @($blk -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match ':' })
$origInf   = "Unknown.inf"
$provider  = ""
$className = ""
$verDate   = "N/A"
foreach ($ln in $lines) {
$val = ($ln -split ':\s*', 2)[1].Trim()
if ([string]::IsNullOrWhiteSpace($val) -or $val -eq $oemInf) { continue }
elseif ($val -match '^\{[0-9a-fA-F\-]{36}\}$') { continue }
elseif ($origInf -eq "Unknown.inf" -and $val -match '(?i)^[a-z0-9_\-\.]+\.inf$') { $origInf = $val }
elseif ($val -match '^\d{1,4}[/\.\-]\d{1,2}[/\.\-]\d{1,4}\s+[\d\.]+$') { $verDate = $val }
elseif ([string]::IsNullOrEmpty($provider))  { $provider  = $val }
elseif ([string]::IsNullOrEmpty($className)) { $className = $val }
}
if ([string]::IsNullOrEmpty($provider))  { $provider  = "Unknown" }
if ([string]::IsNullOrEmpty($className)) { $className = "System" }
$repoDir = $oemToRepo[$oemInf]
if ([string]::IsNullOrWhiteSpace($repoDir) -and $origInf -ne "Unknown.inf") {
$cand = Get-ChildItem -LiteralPath $repoBase -Filter "$($origInf)_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $cand) { $repoDir = $cand.FullName }
}
$bytes  = if (-not [string]::IsNullOrWhiteSpace($repoDir) -and [System.IO.Directory]::Exists($repoDir)) { Get-UltixFastSize -TargetPaths @($repoDir) } else { 0 }
$sizeMB = [math]::Round($bytes / 1MB, 2)
$isActive  = $activeOemInfs.Contains($oemInf)
$statusStr = if ($isActive) { "[ACTIVE - LOCKED]" } else { "[ORPHAN / OLD]" }
$parsedDrivers.Add([PSCustomObject]@{
OemInf        = $oemInf
OriginalInf   = $origInf
Provider      = $provider
DriverClass   = $className
VersionDate   = $verDate
SizeMB        = $sizeMB
SizeDisplay = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0,7:0.00} MB", $sizeMB)
Status        = $statusStr
IsLocked      = $isActive
IsDetected    = (-not $isActive)
UIDisplayName = "$oemInf ($origInf | $provider | $verDate) [ $sizeMB MB ]"
})
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return @($parsedDrivers | Sort-Object IsLocked, @{Expression="SizeMB"; Descending=$true}, OriginalInf)
}
function Show-DriverStoreSweeper {
param(
[System.Windows.Forms.Control[]]$ControlsToDisable = @(),
[switch]$AuditOnly
)
if ($AuditOnly) {
Write-GUI "--- AUDIT: DriverStore FileRepository (Background Thread) ---"
} else {
Write-GUI " -> Scanning DriverStore FileRepository & PnP bindings (Background Thread)..."
}
Update-Progress 10
$sb = (Get-Command -Name Get-DriverStoreOrphans_Worker).ScriptBlock
$isAudit = $AuditOnly.IsPresent
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
param($output)
Update-Progress 0
[array]$allDrv = @($output | Where-Object { $null -ne $_ })
$orphans = @($allDrv | Where-Object { -not $_.IsLocked })
$totalOrphanMB = [math]::Round((($orphans | Measure-Object -Property SizeMB -Sum).Sum), 2)
if ($isAudit) {
if ($orphans.Count -gt 0) {
foreach ($o in $orphans) {
Write-GUI "  [!] Orphaned Package: $($o.UIDisplayName)"
}
Write-GUI "-> STATUS: $($orphans.Count) orphaned/superseded driver package(s) found (Reclaimable: $totalOrphanMB MB).`n"
} else {
Write-GUI "  [OK] DriverStore is completely clean. Zero orphaned driver packages found.`n"
}
return
}
if ($allDrv.Count -eq 0) {
Write-GUI "  [OK] No third-party OEM driver packages found in DriverStore.`n"
return
}
$cols = @(
@{ Header = "OEM INF";      Property = "OemInf";      Width = 95  }
@{ Header = "Status";       Property = "Status";      Width = 140 }
@{ Header = "Size";         Property = "SizeDisplay"; Width = 95  }
@{ Header = "Original INF"; Property = "OriginalInf"; Width = 145 }
@{ Header = "Provider";     Property = "Provider";    Width = 150 }
@{ Header = "Class";        Property = "DriverClass"; Width = 120 }
@{ Header = "Date & Ver";   Property = "VersionDate"; Width = 165 }
)
$res = Show-UltixGridModal -Title "WinUltix - DriverStore Orphan Sweeper (Reclaimable: $totalOrphanMB MB)" `
-Description "Active drivers bound to hardware are locked in RED. Select orphaned/superseded OEM packages to purge from FileRepository." `
-Data $allDrv -Columns $cols -PrimaryButtonText "Delete Selected Orphans (pnputil)"
if ($null -eq $res -or $res.Items.Count -eq 0) {
Write-GUI " -> DriverStore cleanup cancelled.`n"
return
}
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
param([array]$Selected)
$total = $Selected.Count
$cur   = 0
[double]$freedMB = 0
foreach ($drv in $Selected) {
$cur++
if ($null -ne $UltixSync) { $UltixSync.Progress = [int](($cur / $total) * 100) }
if ($drv.IsLocked) { continue }
$UltixSync.Logs.Enqueue(" -> Deleting DriverStore package: $($drv.OemInf) ($($drv.OriginalInf) - $($drv.SizeDisplay.Trim()))...")
$null = pnputil.exe /delete-driver $drv.OemInf 2>&1
if ($LASTEXITCODE -eq 0) {
$freedMB += $drv.SizeMB
$UltixSync.Logs.Enqueue("    [OK] Purged $($drv.OemInf) from DriverStore.")
} else {
$UltixSync.Logs.Enqueue("    [!] OS protected $($drv.OemInf) (Still referenced by a device node). Skipped.")
}
}
return [math]::Round($freedMB, 2)
} -OnComplete ({
param($reclaimed)
Update-Progress 0
Write-GUI " -> DriverStore sweep completed. Reclaimed: $reclaimed MB.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Get-InstallerOrphans_Worker {
if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }
$installerDir = "$env:windir\Installer"
if (-not [System.IO.Directory]::Exists($installerDir)) { return @() }
$activePackages = @{}
$patchLookup    = @{}
$activePatchIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$userDataRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData", $false)
if ($null -ne $userDataRoot) {
try {
foreach ($sidName in $userDataRoot.GetSubKeyNames()) {
$sidKey = $userDataRoot.OpenSubKey($sidName, $false)
if ($null -eq $sidKey) { continue }
try {
$patchesKey = $sidKey.OpenSubKey("Patches", $false)
if ($null -ne $patchesKey) {
try {
foreach ($patchId in $patchesKey.GetSubKeyNames()) {
$pKey = $patchesKey.OpenSubKey($patchId, $false)
if ($null -eq $pKey) { continue }
try {
$lp = [string]$pKey.GetValue("LocalPackage", "")
if (-not [string]::IsNullOrWhiteSpace($lp)) {
$dn = [string]$pKey.GetValue("DisplayName", "")
$patchLookup[$patchId] = [PSCustomObject]@{
Path = $lp.Trim()
Name = if (-not [string]::IsNullOrWhiteSpace($dn)) { $dn } else { "Registered OS/App Patch" }
}
}
} finally {
$pKey.Dispose()
}
}
} finally {
$patchesKey.Dispose()
}
}
$prodsKey = $sidKey.OpenSubKey("Products", $false)
if ($null -ne $prodsKey) {
try {
foreach ($prodGuid in $prodsKey.GetSubKeyNames()) {
$prodKey = $prodsKey.OpenSubKey($prodGuid, $false)
if ($null -eq $prodKey) { continue }
try {
$instPropKey = $prodKey.OpenSubKey("InstallProperties", $false)
if ($null -ne $instPropKey) {
try {
$lp = [string]$instPropKey.GetValue("LocalPackage", "")
if (-not [string]::IsNullOrWhiteSpace($lp)) {
$dn   = [string]$instPropKey.GetValue("DisplayName", "")
$pub  = [string]$instPropKey.GetValue("Publisher", "")
$leaf = [System.IO.Path]::GetFileName($lp.Trim()).ToLowerInvariant()
$activePackages[$leaf] = [PSCustomObject]@{
ProductName = if (-not [string]::IsNullOrWhiteSpace($dn))  { $dn }  else { "Installed MSI Product" }
Publisher   = if (-not [string]::IsNullOrWhiteSpace($pub)) { $pub } else { "Microsoft / OEM" }
}
}
} finally {
$instPropKey.Dispose()
}
}
$prodPatchesKey = $prodKey.OpenSubKey("Patches", $false)
if ($null -ne $prodPatchesKey) {
try {
foreach ($boundPatchId in $prodPatchesKey.GetSubKeyNames()) {
[void]$activePatchIds.Add($boundPatchId)
}
} finally {
$prodPatchesKey.Dispose()
}
}
} finally {
$prodKey.Dispose()
}
}
} finally {
$prodsKey.Dispose()
}
}
} finally {
$sidKey.Dispose()
}
}
} finally {
$userDataRoot.Dispose()
}
}
foreach ($patchId in $activePatchIds) {
if ($patchLookup.ContainsKey($patchId)) {
$pInfo = $patchLookup[$patchId]
$leaf  = [System.IO.Path]::GetFileName($pInfo.Path).ToLowerInvariant()
if (-not $activePackages.ContainsKey($leaf)) {
$activePackages[$leaf] = [PSCustomObject]@{
ProductName = $pInfo.Name
Publisher   = "Active MSP Patch"
}
}
}
}
foreach ($uninstSubPath in @("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
$uninstRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($uninstSubPath, $false)
if ($null -eq $uninstRoot) { continue }
try {
foreach ($uName in $uninstRoot.GetSubKeyNames()) {
$uKey = $uninstRoot.OpenSubKey($uName, $false)
if ($null -eq $uKey) { continue }
try {
$lp = [string]$uKey.GetValue("LocalPackage", "")
if (-not [string]::IsNullOrWhiteSpace($lp)) {
$leaf = [System.IO.Path]::GetFileName($lp.Trim()).ToLowerInvariant()
if (-not $activePackages.ContainsKey($leaf)) {
$dn  = [string]$uKey.GetValue("DisplayName", "")
$pub = [string]$uKey.GetValue("Publisher", "")
$activePackages[$leaf] = [PSCustomObject]@{
ProductName = if (-not [string]::IsNullOrWhiteSpace($dn))  { $dn }  else { $uName }
Publisher   = if (-not [string]::IsNullOrWhiteSpace($pub)) { $pub } else { "Installed App" }
}
}
}
} finally {
$uKey.Dispose()
}
}
} finally {
$uninstRoot.Dispose()
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 40 }
$files = @(Get-ChildItem -LiteralPath $installerDir -File -Force -ErrorAction SilentlyContinue |
Where-Object { $_.Extension -match '^\.(?i)(msi|msp)$' })
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$wiCom = $null
try { $wiCom = New-Object -ComObject WindowsInstaller.Installer -ErrorAction SilentlyContinue } catch { }
$totalFiles = [math]::Max(1, $files.Count)
$idx = 0
foreach ($file in $files) {
$idx++
if ($null -ne $UltixSync -and ($idx % 15 -eq 0 -or $idx -eq $totalFiles)) {
$UltixSync.Progress = 40 + [int](($idx / $totalFiles) * 55)
}
$leafLower = $file.Name.ToLowerInvariant()
$sizeMB    = [math]::Round($file.Length / 1MB, 2)
if ($sizeMB -lt 0.05) { continue }
$isActive = $activePackages.ContainsKey($leafLower)
$prodName = "Orphaned Installer Package"
$pubName  = "Unknown Vendor"
if ($isActive) {
$prodName = $activePackages[$leafLower].ProductName
$pubName  = $activePackages[$leafLower].Publisher
} elseif ($null -ne $wiCom) {
$sumInfo = $null
try {
$sumInfo = $wiCom.SummaryInformation($file.FullName, 0)
$subj = [string]$sumInfo.Property(3)
$auth = [string]$sumInfo.Property(4)
if (-not [string]::IsNullOrWhiteSpace($subj)) { $prodName = $subj.Trim() }
if (-not [string]::IsNullOrWhiteSpace($auth)) { $pubName  = $auth.Trim() }
} catch {
} finally {
if ($null -ne $sumInfo) {
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sumInfo)
}
}
}
$statusTag = if ($isActive) { "[ACTIVE - LOCKED]" } else { "[ORPHAN / SAFE]" }
$results.Add([PSCustomObject]@{
FileName      = $file.Name
Status        = $statusTag
SizeMB        = $sizeMB
SizeDisplay = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0,7:0.00} MB", $sizeMB)
ProductName   = $prodName
Publisher     = $pubName
FullPath      = $file.FullName
IsDirectory   = $false
IsLocked      = $isActive
IsDetected    = (-not $isActive)
UIDisplayName = "$($file.Name) ($prodName | $pubName) [ $sizeMB MB ]"
})
}
if ($null -ne $wiCom) {
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wiCom)
}
$patchCacheDir = "$installerDir\`$PatchCache`$\Managed"
if ([System.IO.Directory]::Exists($patchCacheDir)) {
$pcBytes = Get-UltixFastSize -TargetPaths @($patchCacheDir)
$pcMB    = [math]::Round($pcBytes / 1MB, 2)
if ($pcMB -ge 1.0) {
$results.Add([PSCustomObject]@{
FileName      = "`$PatchCache`$"
Status        = "[ORPHAN / CACHE]"
SizeMB        = $pcMB
SizeDisplay   = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0,7:0.00} MB", $pcMB)
ProductName   = "Windows Installer Baseline RTM Patch Cache (Safe to empty)"
Publisher     = "Microsoft Corporation"
FullPath      = $patchCacheDir
IsDirectory   = $true
IsLocked      = $false
IsDetected    = $true
UIDisplayName = "`$PatchCache`$\Managed (Baseline RTM Cache) [ $pcMB MB ]"
})
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return @($results | Sort-Object IsLocked, @{Expression="SizeMB"; Descending=$true}, ProductName)
}
function Show-InstallerSweeper {
param(
[System.Windows.Forms.Control[]]$ControlsToDisable = @(),
[switch]$AuditOnly
)
if ($AuditOnly) {
Write-GUI "--- AUDIT: Windows Installer (C:\Windows\Installer) Orphans ---"
} else {
Write-GUI " -> Auditing C:\Windows\Installer packages & UserData bindings (Background Thread)..."
}
Update-Progress 10
$sb = (Get-Command -Name Get-InstallerOrphans_Worker).ScriptBlock
$isAudit = $AuditOnly.IsPresent
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
param($output)
Update-Progress 0
[array]$allItems = @($output | Where-Object { $null -ne $_ })
$orphans = @($allItems | Where-Object { -not $_.IsLocked })
$totalOrphanMB = [math]::Round((($orphans | Measure-Object -Property SizeMB -Sum).Sum), 2)
if ($isAudit) {
if ($orphans.Count -gt 0) {
foreach ($o in $orphans) {
Write-GUI "  [!] Orphaned MSI/MSP: $($o.UIDisplayName)"
}
Write-GUI "-> STATUS: $($orphans.Count) orphaned installer package(s) found (Reclaimable: $totalOrphanMB MB).`n"
} else {
Write-GUI "  [OK] C:\Windows\Installer has zero orphaned packages.`n"
}
return
}
if ($allItems.Count -eq 0) {
Write-GUI "  [OK] No MSI/MSP packages found in C:\Windows\Installer.`n"
return
}
$cols = @(
@{ Header = "Package";      Property = "FileName";    Width = 110 }
@{ Header = "Status";       Property = "Status";      Width = 140 }
@{ Header = "Size";         Property = "SizeDisplay"; Width = 95  }
@{ Header = "Product Name"; Property = "ProductName"; Width = 335 }
@{ Header = "Publisher";    Property = "Publisher";   Width = 175 }
)
$res = Show-UltixGridModal -Title "WinUltix - Windows Installer (MSI/MSP) Orphan Sweeper (Reclaimable: $totalOrphanMB MB)" `
-Description "Active MSI/MSP packages required for app uninstallation are locked in RED. Select orphaned packages to permanently delete." `
-Data $allItems -Columns $cols -PrimaryButtonText "Purge Selected Orphans"
if ($null -eq $res -or $res.Items.Count -eq 0) {
Write-GUI " -> Windows Installer cleanup cancelled.`n"
return
}
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
param([array]$Selected)
$total = $Selected.Count
$cur   = 0
[double]$freedMB = 0
foreach ($pkg in $Selected) {
$cur++
if ($null -ne $UltixSync) { $UltixSync.Progress = [int](($cur / $total) * 100) }
if ($pkg.IsLocked) { continue }
try {
if ($pkg.IsDirectory) {
Get-ChildItem -LiteralPath $pkg.FullPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
$freedMB += $pkg.SizeMB
$UltixSync.Logs.Enqueue("    [OK] Purged Windows Installer `$PatchCache`$ ($($pkg.SizeDisplay.Trim())).")
} elseif (Test-Path -LiteralPath $pkg.FullPath -PathType Leaf) {
$fItem = Get-Item -LiteralPath $pkg.FullPath -Force -ErrorAction SilentlyContinue
if ($null -ne $fItem) { $fItem.Attributes = 'Normal' }
Remove-Item -LiteralPath $pkg.FullPath -Force -ErrorAction Stop
$freedMB += $pkg.SizeMB
$UltixSync.Logs.Enqueue("    [OK] Deleted orphaned $($pkg.FileName) ($($pkg.ProductName) - $($pkg.SizeDisplay.Trim())).")
}
} catch {
$UltixSync.Logs.Enqueue("    [!] Locked/Skipped $($pkg.FileName): $($_.Exception.Message)")
}
}
return [math]::Round($freedMB, 2)
} -OnComplete ({
param($reclaimed)
Update-Progress 0
Write-GUI " -> Windows Installer sweep completed. Reclaimed: $reclaimed MB.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Get-RegistryOrphans_Worker {
if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }
$orphans = [System.Collections.Generic.List[PSCustomObject]]::new()
$readyDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($drv in ([System.IO.DriveInfo]::GetDrives())) {
if ($drv.IsReady) { [void]$readyDrives.Add($drv.Name.Substring(0, 1)) }
}
function Test-IsOrphanedDiskPath {
param([string]$RawPath, [switch]$IsDirectory)
if ([string]::IsNullOrWhiteSpace($RawPath)) { return $false }
$clean = [System.Environment]::ExpandEnvironmentVariables($RawPath.Trim().Trim('"')).Trim()
if ($clean -notmatch '^([a-zA-Z]):\\') { return $false }
$driveLetter = $matches[1]
if (-not $readyDrives.Contains($driveLetter)) { return $false }
if ($clean -match '(?i)^[a-z]:\\Windows(\\|$)' -or $clean -match '(?i)\\WindowsApps\\') { return $false }
if ($IsDirectory) {
return (-not [System.IO.Directory]::Exists($clean))
} else {
return (-not [System.IO.File]::Exists($clean))
}
}
$fwPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
if (Test-Path -LiteralPath $fwPath) {
$fwKey = Get-Item -LiteralPath $fwPath -ErrorAction SilentlyContinue
if ($null -ne $fwKey) {
try {
foreach ($valName in $fwKey.Property) {
$ruleStr = [string]$fwKey.GetValue($valName)
if ($ruleStr -match '\|App=([^|]+)\|') {
$appPath = $matches[1]
if (Test-IsOrphanedDiskPath -RawPath $appPath) {
$ruleTitle = if ($ruleStr -match '\|Name=([^|]+)\|') { $matches[1] } else { $valName }
$orphans.Add([PSCustomObject]@{
Category      = "[Firewall Rule]"
TargetName    = $ruleTitle
MissingPath   = $appPath
RegPath       = $fwPath
ValueName     = $valName
RawValueData  = $ruleStr
ValueKind     = "String"
EntryType     = "Value"
IsDetected    = $true
UIDisplayName = "[Firewall Rule] $ruleTitle -> $appPath"
})
}
}
}
} finally { $fwKey.Dispose() }
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 30 }
$compatKeys = @(
"HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
"HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
"HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
)
foreach ($cPath in $compatKeys) {
if (-not (Test-Path -LiteralPath $cPath)) { continue }
$cKey = Get-Item -LiteralPath $cPath -ErrorAction SilentlyContinue
if ($null -ne $cKey) {
try {
foreach ($valName in $cKey.Property) {
if (Test-IsOrphanedDiskPath -RawPath $valName) {
$leaf   = [System.IO.Path]::GetFileName($valName)
$rawObj = $cKey.GetValue($valName)
$vKind  = if ($rawObj -is [byte[]]) { "Binary" } else { "String" }
$vData  = if ($rawObj -is [byte[]]) { [Convert]::ToBase64String($rawObj) } else { [string]$rawObj }
$orphans.Add([PSCustomObject]@{
Category      = "[AppCompat Cache]"
TargetName    = $leaf
MissingPath   = $valName
RegPath       = $cPath
ValueName     = $valName
RawValueData  = $vData
ValueKind     = $vKind
EntryType     = "Value"
IsDetected    = $true
UIDisplayName = "[AppCompat Cache] $leaf -> $valName"
})
}
}
} finally { $cKey.Dispose() }
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 55 }
$dxPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
if (Test-Path -LiteralPath $dxPath) {
$dxKey = Get-Item -LiteralPath $dxPath -ErrorAction SilentlyContinue
if ($null -ne $dxKey) {
try {
foreach ($valName in $dxKey.Property) {
if ($valName -eq "DirectXUserGlobalSettings") { continue }
if (Test-IsOrphanedDiskPath -RawPath $valName) {
$leaf = [System.IO.Path]::GetFileName($valName)
$orphans.Add([PSCustomObject]@{
Category      = "[GPU Preference]"
TargetName    = $leaf
MissingPath   = $valName
RegPath       = $dxPath
ValueName     = $valName
RawValueData  = [string]$dxKey.GetValue($valName)
ValueKind     = "String"
EntryType     = "Value"
IsDetected    = $true
UIDisplayName = "[GPU Preference] $leaf -> $valName"
})
}
}
} finally { $dxKey.Dispose() }
}
}
$sharedDllPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDlls"
if (Test-Path -LiteralPath $sharedDllPath) {
$sdKey = Get-Item -LiteralPath $sharedDllPath -ErrorAction SilentlyContinue
if ($null -ne $sdKey) {
try {
foreach ($valName in $sdKey.Property) {
if (Test-IsOrphanedDiskPath -RawPath $valName) {
$leaf = [System.IO.Path]::GetFileName($valName)
$orphans.Add([PSCustomObject]@{
Category      = "[SharedDLLs]"
TargetName    = $leaf
MissingPath   = $valName
RegPath       = $sharedDllPath
ValueName     = $valName
RawValueData  = [string]$sdKey.GetValue($valName)
ValueKind     = "DWord"
EntryType     = "Value"
IsDetected    = $true
UIDisplayName = "[SharedDLLs] $leaf -> $valName"
})
}
}
} finally { $sdKey.Dispose() }
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 80 }
$msiFoldersPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders"
if (Test-Path -LiteralPath $msiFoldersPath) {
$mfKey = Get-Item -LiteralPath $msiFoldersPath -ErrorAction SilentlyContinue
if ($null -ne $mfKey) {
try {
foreach ($valName in $mfKey.Property) {
if ($valName -match '(?i)\\Microsoft\\|\\Common Files\\|\\Windows\\') { continue }
if (Test-IsOrphanedDiskPath -RawPath $valName -IsDirectory) {
$dirName = [System.IO.Path]::GetFileName($valName.TrimEnd('\'))
$orphans.Add([PSCustomObject]@{
Category      = "[MSI Folder Ref]"
TargetName    = $dirName
MissingPath   = $valName
RegPath       = $msiFoldersPath
ValueName     = $valName
RawValueData  = [string]$mfKey.GetValue($valName)
ValueKind     = "String"
EntryType     = "Value"
IsDetected    = $true
UIDisplayName = "[MSI Folder Ref] $dirName -> $valName"
})
}
}
} finally { $mfKey.Dispose() }
}
}
foreach ($apRoot in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths", "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths")) {
if (-not (Test-Path -LiteralPath $apRoot)) { continue }
foreach ($sub in (Get-ChildItem -LiteralPath $apRoot -ErrorAction SilentlyContinue)) {
try {
$defVal = [string]$sub.GetValue("")
if ([string]::IsNullOrWhiteSpace($defVal)) { continue }
$exePath = [System.Environment]::ExpandEnvironmentVariables($defVal.Trim()).Trim()
if ($exePath -match '^"([^"]+)"') {
$exePath = $matches[1]
} elseif ($exePath -match '(?i)^(.+?\.(?:exe|com|bat|cmd|msc))(?:$|\s)') {
$exePath = $matches[1]
} else {
$exePath = $exePath.Trim('"')
}
if (Test-IsOrphanedDiskPath -RawPath $exePath) {
$orphans.Add([PSCustomObject]@{
Category      = "[App Paths]"
TargetName    = $sub.PSChildName
MissingPath   = $exePath
RegPath       = $sub.PSPath
ValueName     = "(Default)"
RawValueData  = $defVal
ValueKind     = "String"
EntryType     = "SubKey"
IsDetected    = $true
UIDisplayName = "[App Paths] $($sub.PSChildName) -> $exePath"
})
}
} catch {
} finally {
$sub.Dispose()
}
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return @($orphans | Sort-Object Category, TargetName)
}
function Show-RegistryOrphanSweeper {
param(
[System.Windows.Forms.Control[]]$ControlsToDisable = @(),
[switch]$AuditOnly
)
if ($AuditOnly) {
Write-GUI "--- AUDIT: Surgical Registry Orphan Sweeper (Background Thread) ---"
} else {
Write-GUI " -> Scanning Firewall, AppCompat, DirectX GPU, SharedDLLs & AppPaths for dead file paths..."
}
Update-Progress 10
$sb = (Get-Command -Name Get-RegistryOrphans_Worker).ScriptBlock
$isAudit = $AuditOnly.IsPresent
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
param($output)
Update-Progress 0
[array]$orphans = @($output | Where-Object { $null -ne $_ })
if ($isAudit) {
if ($orphans.Count -gt 0) {
$grouped = $orphans | Group-Object Category
foreach ($g in $grouped) {
Write-GUI "  [!] $($g.Name): $($g.Count) orphaned registry reference(s)"
}
Write-GUI "-> STATUS: $($orphans.Count) total orphaned registry path reference(s) detected.`n"
} else {
Write-GUI "  [OK] Zero orphaned path references found in registry.`n"
}
return
}
$cols = @(
@{ Header = "Category";            Property = "Category";    Width = 145 }
@{ Header = "Application / Entry"; Property = "TargetName";  Width = 210 }
@{ Header = "Missing Disk Path";   Property = "MissingPath"; Width = 500 }
)
$res = Show-UltixGridModal -Title "WinUltix - Surgical Registry Orphan Sweeper ($($orphans.Count) Orphans)" `
-Description "100% path-verified registry orphans left behind by uninstalled apps/games. You will choose where to save the JSON backup before purging, or click 'Restore Backup (JSON)...' to import an existing backup." `
-Data $orphans -Columns $cols -PrimaryButtonText "Purge Selected Orphans..." -SecondaryButtonText "Restore Backup (JSON)..." -SecondaryAlwaysEnabled
if ($null -eq $res) {
Write-GUI " -> Registry orphan sweep cancelled.`n"
return
}
if ($res.Action -eq "Secondary") {
$ofd = New-Object System.Windows.Forms.OpenFileDialog
$ofd.Filter = "WinUltix Registry Backup (*.json)|*.json"
$ofd.Title = "Select Registry Orphans JSON Backup to Restore"
$ofd.InitialDirectory = [Environment]::GetFolderPath("Desktop")
$selectedBackup = $null
try {
if ($ofd.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
$selectedBackup = $ofd.FileName
}
} finally {
$ofd.Dispose()
}
if ([string]::IsNullOrWhiteSpace($selectedBackup) -or -not (Test-Path -LiteralPath $selectedBackup)) {
Write-GUI " -> Registry backup restore cancelled.`n"
return
}
try {
$restored = 0
$bData = @(Get-Content -LiteralPath $selectedBackup -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
foreach ($entry in $bData) {
if ($null -eq $entry -or [string]::IsNullOrWhiteSpace($entry.RegPath)) { continue }
if ($entry.EntryType -eq "SubKey") {
if (-not (Test-Path -LiteralPath $entry.RegPath)) { New-Item -Path $entry.RegPath -Force | Out-Null }
Set-Item -LiteralPath $entry.RegPath -Value ([string]$entry.RawValueData) -Force -ErrorAction SilentlyContinue
$restored++
} else {
if (-not (Test-Path -LiteralPath $entry.RegPath)) { New-Item -Path $entry.RegPath -Force | Out-Null }
$kind = if ($entry.PSObject.Properties.Match("ValueKind").Count -gt 0 -and $entry.ValueKind) { [string]$entry.ValueKind } else { "String" }
$regItem = Get-Item -LiteralPath $entry.RegPath -ErrorAction SilentlyContinue
if ($null -ne $regItem) {
$wKey = $regItem.OpenSubKey("", $true)
$regItem.Dispose()
if ($null -ne $wKey) {
try {
if ($kind -eq "Binary" -and -not [string]::IsNullOrWhiteSpace($entry.RawValueData)) {
[byte[]]$bytes = [Convert]::FromBase64String([string]$entry.RawValueData)
$wKey.SetValue([string]$entry.ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
} elseif ($kind -eq "DWord") {
$dw = if ($entry.RawValueData -match '^\d+$') { [int]$entry.RawValueData } else { 1 }
$wKey.SetValue([string]$entry.ValueName, $dw, [Microsoft.Win32.RegistryValueKind]::DWord)
} else {
$wKey.SetValue([string]$entry.ValueName, [string]$entry.RawValueData, [Microsoft.Win32.RegistryValueKind]::String)
}
$restored++
} finally {
$wKey.Dispose()
}
}
}
}
}
Write-GUI " -> [OK] Restored $restored registry entry(s) from: $selectedBackup`n"
} catch {
Write-GUI " -> [!] Failed to restore registry backup: $($_.Exception.Message)`n"
}
return
}
if ($res.Items.Count -eq 0) { return }
$sfd = New-Object System.Windows.Forms.SaveFileDialog
$sfd.Filter = "WinUltix Registry Backup (*.json)|*.json"
$sfd.Title = "Save Registry Orphans Backup Before Purging"
$sfd.FileName = "WinUltix_RegOrphans_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$sfd.InitialDirectory = [Environment]::GetFolderPath("Desktop")
$targetBackupFile = $null
try {
if ($sfd.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
$targetBackupFile = $sfd.FileName
}
} finally {
$sfd.Dispose()
}
if ([string]::IsNullOrWhiteSpace($targetBackupFile)) {
Write-GUI " -> Registry orphan purge cancelled (No backup file selected).`n"
return
}
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $targetBackupFile) -ScriptBlock {
param([array]$Selected, [string]$BackupPath)
$parentDir = Split-Path -Path $BackupPath -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
}
$jsonPayload = @($Selected) | ConvertTo-Json -Depth 4
$jsonPayload | Set-Content -LiteralPath $BackupPath -Encoding UTF8 -Force -ErrorAction Stop
$shadowDir = "$env:LOCALAPPDATA\WinUltix"
if (-not (Test-Path -LiteralPath $shadowDir)) { New-Item -Path $shadowDir -ItemType Directory -Force | Out-Null }
$jsonPayload | Set-Content -LiteralPath "$shadowDir\RegOrphans_LastBackup.json" -Encoding UTF8 -Force -ErrorAction SilentlyContinue
$total   = $Selected.Count
$cur     = 0
$removed = 0
foreach ($item in $Selected) {
$cur++
if ($null -ne $UltixSync -and ($cur % 10 -eq 0 -or $cur -eq $total)) {
$UltixSync.Progress = [int](($cur / $total) * 100)
}
try {
if ($item.EntryType -eq "SubKey") {
if (Test-Path -LiteralPath $item.RegPath) {
Remove-Item -LiteralPath $item.RegPath -Recurse -Force -ErrorAction Stop
$removed++
}
} else {
$regItem = Get-Item -LiteralPath $item.RegPath -ErrorAction Stop
if ($null -ne $regItem) {
$wKey = $regItem.OpenSubKey("", $true)
$regItem.Dispose()
if ($null -ne $wKey) {
try {
$wKey.DeleteValue([string]$item.ValueName, $true)
$removed++
} finally {
$wKey.Dispose()
}
}
}
}
} catch { }
}
return [PSCustomObject]@{
RemovedCount = $removed
SavedPath    = $BackupPath
}
} -OnComplete ({
param($resObj)
Update-Progress 0
if ($null -ne $resObj) {
Write-GUI " -> [OK] Purged $($resObj.RemovedCount) orphaned registry reference(s). Backup saved to: $($resObj.SavedPath)`n"
}
}.GetNewClosure())
}.GetNewClosure())
}
function Get-GhostServicesState {
$ghosts = [System.Collections.Generic.List[PSCustomObject]]::new()
$readyDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($drv in ([System.IO.DriveInfo]::GetDrives())) {
if ($drv.IsReady) { [void]$readyDrives.Add($drv.Name.Substring(0, 1)) }
}
$runningNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[System.ServiceProcess.ServiceController]::GetServices() | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.ServiceName) }
[System.ServiceProcess.ServiceController]::GetDevices()  | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.ServiceName) }
$svcRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services", $false)
if ($null -eq $svcRoot) { return $ghosts }
try {
$svcNames = $svcRoot.GetSubKeyNames()
$total    = $svcNames.Count
$current  = 0
foreach ($svcName in $svcNames) {
$current++
if ($null -ne $UltixSync -and ($current % 25 -eq 0 -or $current -eq $total)) {
$UltixSync.Progress = [int](($current / $total) * 100)
}
if ($runningNames.Contains($svcName)) { continue }
$svcKey = $null
try {
$svcKey = $svcRoot.OpenSubKey($svcName, $true)
} catch {
continue
}
if ($null -eq $svcKey) { continue }
try {
$svcType = $svcKey.GetValue("Type", $null)
if ($null -ne $svcType -and (([int]$svcType -band 0x40) -ne 0)) { continue }
$imagePath = [string]$svcKey.GetValue("ImagePath", "")
} finally {
$svcKey.Dispose()
}
if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
if ($imagePath -match '(?i)^\\(?:Driver|FileSystem|KernelObjects)\\') { continue }
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
if ([System.IO.File]::Exists($candidateWinDir))    { $rawPath = $candidateWinDir }
elseif ([System.IO.File]::Exists($candidateSys32)) { $rawPath = $candidateSys32 }
elseif ([System.IO.File]::Exists($candidateDrv))   { $rawPath = $candidateDrv }
else { $rawPath = $candidateWinDir }
}
if ($rawPath -match '^([a-zA-Z]):\\') {
if (-not $readyDrives.Contains($matches[1])) { continue }
}
if (-not [System.IO.File]::Exists($rawPath)) {
$ghosts.Add([PSCustomObject]@{
Name          = $svcName
Path          = $rawPath
UIDisplayName = "Ghost: $svcName (Missing: $rawPath)"
IsDetected    = $true
})
}
}
} finally {
$svcRoot.Dispose()
}
return $ghosts
}
function Remove-GhostServices {
param(
[Parameter(Mandatory=$true)][array]$SelectedItems,
[System.Windows.Forms.Control[]]$ControlsToDisable = @()
)
if ($SelectedItems.Count -eq 0) { return }
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
param([array]$Items)
$total   = $Items.Count
$current = 0
foreach ($item in $Items) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 100)
$UltixSync.Logs.Enqueue(" -> Removing Ghost Service: $($item.Name)")
}
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($item.Name)" -Recurse -Force -ErrorAction SilentlyContinue
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Ghost services purged from system registry.`n"
}.GetNewClosure())
}
function Initialize-Z1UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tabClean = New-Object System.Windows.Forms.TabPage
$tabClean.Text = "Cleanup"
$tabClean.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$invokeCategory = ({
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
}.GetNewClosure())
$rowWU = New-UltixActionRow -Parent $tabClean -Y 20 -MainRGB @(55, 58, 64) `
-Text "Clean Windows Update & CBS Cache" `
-Description "Analyzes and interactively purges Windows Update (SoftwareDistribution), Delivery Optimization, and CBS Servicing logs safely." `
-AuditDescription "AUDIT: Calculates the exact megabyte footprint of Windows Update, Delivery Optimization, and CBS log files." `
-OnClick ({ & $invokeCategory "WU" }.GetNewClosure()) `
-OnAudit ({ & $invokeCategory "WU" -Audit }.GetNewClosure())
$rowTemp = New-UltixActionRow -Parent $tabClean -Y 70 -MainRGB @(55, 58, 64) `
-Text "Clean Temp, Prefetch & Dumps" `
-Description "Scans and weighs System Temp, Prefetch, Windows Error Reporting (WER), Crash Dumps, and local Temp directories across all user profiles." `
-AuditDescription "AUDIT: Weighs orphaned temporary files, WER reports, crash dumps, and prefetch data globally." `
-OnClick ({ & $invokeCategory "Temp" }.GetNewClosure()) `
-OnAudit ({ & $invokeCategory "Temp" -Audit }.GetNewClosure())
$rowThirdParty = New-UltixActionRow -Parent $tabClean -Y 120 -MainRGB @(55, 58, 64) `
-Text "Clean 3rd-Party & Shader Cache" `
-Description "Locates bloated application and shader caches (Multi-profile Chrome/Edge/Brave/Vivaldi/Firefox, Discord, D3DSCache, NVIDIA/AMD DxCache) across all user profiles." `
-AuditDescription "AUDIT: Aggregates the storage space wasted by third-party browser, launcher, and GPU shader caches." `
-OnClick ({ & $invokeCategory "ThirdParty" }.GetNewClosure()) `
-OnAudit ({ & $invokeCategory "ThirdParty" -Audit }.GetNewClosure())
$rowLogs = New-UltixActionRow -Parent $tabClean -Y 170 -MainRGB @(55, 58, 64) `
-Text "Clear Event Viewer Logs (wevtutil)" `
-Description "Calculates the size of Event Logs (.evtx) and asynchronously clears diagnostic history using the native wevtutil engine." `
-AuditDescription "AUDIT: Checks the current disk space consumed by Windows Event Logs." `
-OnClick ({ & $invokeCategory "EventLogs" }.GetNewClosure()) `
-OnAudit ({ & $invokeCategory "EventLogs" -Audit }.GetNewClosure())
$rowDrvStore = New-UltixActionRow -Parent $tabClean -Y 220 -MainRGB @(45, 85, 125) `
-Text "DriverStore Orphan Sweeper (OEM INF)" `
-Description "Scans C:\Windows\System32\DriverStore\FileRepository for superseded/orphaned OEM driver packages (NVIDIA, AMD, Intel, Realtek) while locking active hardware drivers." `
-AuditDescription "AUDIT: Calculates total gigabytes/megabytes wasted by old, superseded driver packages in DriverStore." `
-OnClick ({ Show-DriverStoreSweeper -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
-OnAudit ({ Show-DriverStoreSweeper -ControlsToDisable $allTabButtons.ToArray() -AuditOnly }.GetNewClosure())
$rowMsiStore = New-UltixActionRow -Parent $tabClean -Y 270 -MainRGB @(45, 85, 125) `
-Text "Windows Installer Orphan Sweeper (MSI)" `
-Description "Cross-references C:\Windows\Installer (.msi / .msp / `$PatchCache`$) against active UserData registrations. Locks active uninstallers and purges orphaned packages." `
-AuditDescription "AUDIT: Calculates disk space wasted by orphaned .msi/.msp packages in C:\Windows\Installer." `
-OnClick ({ Show-InstallerSweeper -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
-OnAudit ({ Show-InstallerSweeper -ControlsToDisable $allTabButtons.ToArray() -AuditOnly }.GetNewClosure())
$rowRegOrphans = New-UltixActionRow -Parent $tabClean -Y 320 -MainRGB @(45, 85, 125) `
-Text "Surgical Registry Orphan Sweeper" `
-Description "Scans Firewall Rules, AppCompat Store/Layers, DirectX GPU Preferences, SharedDLLs, MSI Folders, and App Paths for dead file paths with JSON backup." `
-AuditDescription "AUDIT: Counts dead file/folder references left behind in the registry by uninstalled applications and games." `
-OnClick ({ Show-RegistryOrphanSweeper -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
-OnAudit ({ Show-RegistryOrphanSweeper -ControlsToDisable $allTabButtons.ToArray() -AuditOnly }.GetNewClosure())
$rowGhostSvc = New-UltixActionRow -Parent $tabClean -Y 370 -MainRGB @(55, 58, 64) `
-Text "Cleanup Ghost Services & Drivers" `
-Description "Scans HKLM\...\Services for orphaned service and driver keys pointing to non-existent binaries (.exe/.sys) and removes them." `
-AuditDescription "AUDIT: Detects orphaned service and kernel driver registrations pointing to missing disk files." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ModalTitle "WinUltix - Ghost Services Cleanup" -ModalDescription "Select orphaned service/driver keys to remove." -ExecutorFunction "Remove-GhostServices" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Found"
}.GetNewClosure())
$rowRecycle = New-UltixActionRow -Parent $tabClean -Y 420 -MainRGB @(135, 50, 50) `
-Text "Hard Empty Recycle Bin (NTFS)" `
-Description "Scans all logical partitions for Recycle Bin contents and forcefully purges them in a background thread, bypassing standard file locks." `
-AuditDescription "AUDIT: Reports the total size of deleted files waiting in the Recycle Bins across all partitions." `
-OnClick ({ & $invokeCategory "RecycleBin" }.GetNewClosure()) `
-OnAudit ({ & $invokeCategory "RecycleBin" -Audit }.GetNewClosure())
foreach ($row in @($rowWU, $rowTemp, $rowThirdParty, $rowLogs, $rowDrvStore, $rowMsiStore, $rowRegOrphans, $rowGhostSvc, $rowRecycle)) {
$allTabButtons.AddRange($row.Controls)
}
$TabControl.Controls.Add($tabClean)
}
function Get-UltixProtectedAppxRegex {
return "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|ShellExperienceHost|StartMenuExperienceHost|immersivecontrolpanel|SecHealthUI|WindowsDefender|WindowsStore|StorePurchaseApp|DesktopAppInstaller|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|MicrosoftEdge\.Stable|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|MicrosoftWindows\.Client\.(?!WebExperience)|Windows\.CBSPreview|Windows\.PrintDialog|Microsoft\.AsyncTextService|Microsoft\.AccountsControl|Microsoft\.CredDialogHost|Microsoft\.ECApp|Microsoft\.LockApp|Microsoft\.BioEnrollment|ApplicationCompatibilityEnhancements|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension|MPEG2VideoExtension"
}
function Get-OneDriveState {
if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$userProfiles = @(Get-UltixUserProfiles)
$loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })
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
$exeCandidates = @(
"$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
"$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
"${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
)
foreach ($prof in $userProfiles) {
if (-not [string]::IsNullOrWhiteSpace($prof.LocalPath)) {
$exeCandidates += (Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive\OneDrive.exe")
}
}
$hasBinary = $false
foreach ($exePath in ($exeCandidates | Select-Object -Unique)) {
if ([System.IO.File]::Exists($exePath)) {
$hasBinary = $true
break
}
}
$liveProc  = Get-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -ErrorAction SilentlyContinue
$odTasks   = @(Get-ScheduledTask -TaskName "*OneDrive*" -ErrorAction SilentlyContinue)
$hasRunKey = $false
$runRoots = [System.Collections.Generic.List[string]]::new()
$runRoots.Add("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
$runRoots.Add("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
foreach ($hive in $loadedHives) {
$runRoots.Add("$($hive.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run")
$runRoots.Add("$($hive.HiveRoot)\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
}
foreach ($runPath in ($runRoots | Select-Object -Unique)) {
if (Test-Path -LiteralPath $runPath) {
$runProps = Get-ItemProperty -LiteralPath $runPath -ErrorAction SilentlyContinue
if ($null -ne $runProps -and ($runProps.PSObject.Properties.Match("OneDrive*").Count -gt 0)) {
$hasRunKey = $true
break
}
}
}
$isCoreDetected = ($hasBinary -or $hasRunKey -or ($null -ne $liveProc) -or ($odTasks.Count -gt 0))
$results.Add([PSCustomObject]@{
UIDisplayName = "Core: OneDrive Setup and Startup Routine"
IsDetected    = $isCoreDetected
ActionData    = @{ Type = "Core" }
})
if ($null -ne $UltixSync) { $UltixSync.Progress = 55 }
$zombieSubKeys = @("SyncEngine", "Client_Policy", "Accounts")
$knownNsGuids  = @("{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "{04271989-C4D2-430F-9D0E-2A48B44B1A5C}")
foreach ($hive in $loadedHives) {
foreach ($subKey in $zombieSubKeys) {
$fullRegPath = "$($hive.HiveRoot)\Software\Microsoft\OneDrive\$subKey"
$results.Add([PSCustomObject]@{
UIDisplayName = "Registry ($($hive.UserName)): $subKey"
IsDetected    = (Test-Path -LiteralPath $fullRegPath)
ActionData    = @{ Type = "Registry"; Path = $fullRegPath }
})
}
$nsRoot = "$($hive.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace"
$foundNsKeys = [System.Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $nsRoot) {
foreach ($nsSub in (Get-ChildItem -LiteralPath $nsRoot -ErrorAction SilentlyContinue)) {
try {
$childName = $nsSub.PSChildName
$defVal    = [string]$nsSub.GetValue("", "")
if ($childName -in $knownNsGuids -or $defVal -match '(?i)OneDrive') {
$foundNsKeys.Add($childName)
}
} catch {
} finally {
$nsSub.Dispose()
}
}
}
if ($foundNsKeys.Count -gt 0) {
foreach ($nsGuid in $foundNsKeys) {
$results.Add([PSCustomObject]@{
UIDisplayName = "Shell NameSpace ($($hive.UserName)): $nsGuid"
IsDetected    = $true
ActionData    = @{ Type = "Registry"; Path = "$nsRoot\$nsGuid" }
})
}
} else {
$results.Add([PSCustomObject]@{
UIDisplayName = "Shell NameSpace ($($hive.UserName)): {018D5C66-4533-4307-9B53-224DE2ED1FE6}"
IsDetected    = $false
ActionData    = @{ Type = "Registry"; Path = "$nsRoot\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" }
})
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }
$staticFolders = @(
"$env:ProgramFiles\Microsoft OneDrive",
"${env:ProgramFiles(x86)}\Microsoft OneDrive",
"$env:PROGRAMDATA\Microsoft OneDrive",
"$env:SystemDrive\OneDriveTemp"
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
foreach ($folder in $staticFolders) {
$results.Add([PSCustomObject]@{
UIDisplayName = "Folder: $folder"
IsDetected    = (Test-Path -LiteralPath $folder)
ActionData    = @{ Type = "Folder"; Path = $folder }
})
}
foreach ($prof in $userProfiles) {
$userPath = Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"
$results.Add([PSCustomObject]@{
UIDisplayName = "User Data: $($prof.UserName)"
IsDetected    = (Test-Path -LiteralPath $userPath)
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
$critical = Get-UltixProtectedAppxRegex
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
@{ Label = "King: Candy Crush Saga";                      Pattern = "*CandyCrush*" }
@{ Label = "King: Bubble Witch Saga";                     Pattern = "*BubbleWitch*" }
@{ Label = "King: Farm Heroes Saga";                      Pattern = "*FarmHeroes*" }
@{ Label = "Gameloft: March of Empires";                  Pattern = "*MarchofEmpires*" }
@{ Label = "Playrix: Homescapes";                         Pattern = "*Homescapes*" }
@{ Label = "Playrix: Township";                           Pattern = "*Township*" }
@{ Label = "Disney Interactive (Magic Kingdoms / Games)"; Pattern = "*Disney*" }
@{ Label = "TikTok";                                      Pattern = "*TikTok*" }
@{ Label = "Meta: Instagram";                             Pattern = "*Instagram*" }
@{ Label = "Meta: Facebook";                              Pattern = "*Facebook*" }
@{ Label = "Twitter / X";                                 Pattern = "*Twitter*" }
@{ Label = "LinkedIn";                                    Pattern = "*LinkedIn*" }
@{ Label = "Netflix";                                     Pattern = "*Netflix*" }
@{ Label = "Spotify Music";                               Pattern = "*Spotify*" }
@{ Label = "Amazon (Prime Video / Shopping)";             Pattern = "*Amazon*" }
@{ Label = "McAfee Security Suite";                       Pattern = "*McAfee*" }
@{ Label = "Norton Security Suite";                       Pattern = "*Norton*" }
@{ Label = "Lenovo OEM Bloatware & Vantage Stubs";        Pattern = "*Lenovo*" }
@{ Label = "Dell SupportAssist & OEM Stubs";              Pattern = "*Dell*" }
@{ Label = "HP Support Assistant & OEM Stubs";            Pattern = "*HP*" }
)
$protectedRegex = Get-UltixProtectedAppxRegex
$installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedRegex })
if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }
$provAppx = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch $protectedRegex })
if ($null -ne $UltixSync) { $UltixSync.Progress = 40 }
$recallFeature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
$isRecallFeatEnabled = ($null -ne $recallFeature -and ($recallFeature.State -eq 'Enabled' -or $recallFeature.State -eq 'EnablePending'))
$aiPolPathLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
$aiPolPathCU = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
$aiPropsLM   = Get-ItemProperty -LiteralPath $aiPolPathLM -Name "DisableAIDataAnalysis", "TurnOffSavingSnapshots" -ErrorAction SilentlyContinue
$aiPropsCU   = Get-ItemProperty -LiteralPath $aiPolPathCU -Name "DisableAIDataAnalysis", "TurnOffSavingSnapshots" -ErrorAction SilentlyContinue
$isRecallPolicyLocked = (
$null -ne $aiPropsLM -and $aiPropsLM.DisableAIDataAnalysis -eq 1 -and $aiPropsLM.TurnOffSavingSnapshots -eq 1 -and
$null -ne $aiPropsCU -and $aiPropsCU.DisableAIDataAnalysis -eq 1 -and $aiPropsCU.TurnOffSavingSnapshots -eq 1
)
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
function Remove-UltixOneDriveDirectory {
param([string]$TargetDir)
if ([string]::IsNullOrWhiteSpace($TargetDir) -or -not (Test-Path -LiteralPath $TargetDir)) { return }
& takeown.exe /F "$TargetDir" /R /A /D Y 2>$null | Out-Null
& icacls.exe "$TargetDir" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
$binFiles = @(Get-ChildItem -LiteralPath $TargetDir -Include "*.dll", "*.exe" -Recurse -File -Force -ErrorAction SilentlyContinue)
foreach ($bin in $binFiles) {
$binPath = $bin.FullName
$binName = $bin.Name
if ([string]::IsNullOrWhiteSpace($binPath)) { continue }
try {
$bin.Attributes = 'Normal'
Remove-Item -LiteralPath $binPath -Force -ErrorAction Stop
} catch {
$trashPath = Join-Path -Path $env:TEMP -ChildPath "WinUltix_Locked_${binName}_$([guid]::NewGuid().ToString('N')).tmp"
Move-Item -LiteralPath $binPath -Destination $trashPath -Force -ErrorAction SilentlyContinue
}
}
Get-ChildItem -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
try { $_.Attributes = 'Normal' } catch {}
}
Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $TargetDir) {
if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [*] Releasing Shell Extension lock via Explorer refresh...") }
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
Start-Process "explorer.exe"
}
}
}
Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
$userProfiles = @(Get-UltixUserProfiles)
$loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })
if ($loadedHives.Count -eq 0) {
$loadedHives = @([PSCustomObject]@{ SID = "CurrentUser"; UserName = $env:USERNAME; LocalPath = $env:USERPROFILE; HiveRoot = "HKCU:"; IsHiveLoaded = $true })
}
$registryTargetsToVerify = [System.Collections.Generic.List[string]]::new()
foreach ($item in $Items) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 90)
$UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
}
$data = $item.ActionData
try {
if ($data.Type -eq "Core") {
Get-ScheduledTask -TaskName "*OneDrive*" -ErrorAction SilentlyContinue | ForEach-Object {
Stop-ScheduledTask -InputObject $_ -ErrorAction SilentlyContinue | Out-Null
Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue
}
$installDirs = [System.Collections.Generic.List[string]]::new()
foreach ($d in @("$env:ProgramFiles\Microsoft OneDrive", "${env:ProgramFiles(x86)}\Microsoft OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive")) {
if (-not [string]::IsNullOrWhiteSpace($d)) { $installDirs.Add($d) }
}
foreach ($prof in $userProfiles) {
if (-not [string]::IsNullOrWhiteSpace($prof.LocalPath)) {
$installDirs.Add((Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"))
}
}
$activeExeFound = $false
foreach ($dir in ($installDirs | Select-Object -Unique)) {
if ([System.IO.File]::Exists((Join-Path $dir "OneDrive.exe"))) {
$activeExeFound = $true
break
}
}
if ($activeExeFound) {
$setupCandidates = [System.Collections.Generic.List[string]]::new()
foreach ($dir in ($installDirs | Select-Object -Unique)) {
if ([System.IO.Directory]::Exists($dir)) {
Get-ChildItem -LiteralPath $dir -Filter "OneDriveSetup.exe" -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
$setupCandidates.Add($_.FullName)
}
}
}
$setupCandidates.Add("$env:SystemRoot\SysWOW64\OneDriveSetup.exe")
$setupCandidates.Add("$env:SystemRoot\System32\OneDriveSetup.exe")
foreach ($setupExe in ($setupCandidates | Select-Object -Unique)) {
if ([System.IO.File]::Exists($setupExe)) {
Start-Process -FilePath $setupExe -ArgumentList "/uninstall" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
Start-Process -FilePath $setupExe -ArgumentList "/uninstall /allusers" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
break
}
}
$childProcs = @(Get-Process -Name "OneDriveSetup", "OneDrive", "OneDriveStandaloneUpdater", "FileCoAuth" -ErrorAction SilentlyContinue)
if ($childProcs.Count -gt 0) {
$childProcs | Wait-Process -Timeout 8 -ErrorAction SilentlyContinue
Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500
}
foreach ($dir in ($installDirs | Select-Object -Unique)) {
if ($dir -like "$env:ProgramFiles*" -or $dir -like "${env:ProgramFiles(x86)}*") {
if (Test-Path -LiteralPath $dir) {
Remove-UltixOneDriveDirectory -TargetDir $dir
}
} elseif ([System.IO.File]::Exists((Join-Path $dir "OneDrive.exe"))) {
Remove-UltixOneDriveDirectory -TargetDir $dir
}
}
$runTargets = [System.Collections.Generic.List[string]]::new()
$runTargets.Add("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")
$runTargets.Add("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
$runTargets.Add("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
$nsRoots = [System.Collections.Generic.List[string]]::new()
$nsRoots.Add("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")
foreach ($prof in $loadedHives) {
$runTargets.Add("$($prof.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run")
$runTargets.Add("$($prof.HiveRoot)\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
$nsRoots.Add("$($prof.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")
}
foreach ($rPath in ($runTargets | Select-Object -Unique)) {
if (Test-Path -LiteralPath $rPath) {
$rKey = Get-Item -LiteralPath $rPath -ErrorAction SilentlyContinue
if ($null -ne $rKey) {
try {
foreach ($valName in $rKey.Property) {
if ($valName -like "OneDrive*") {
Remove-ItemProperty -LiteralPath $rPath -Name $valName -Force -ErrorAction SilentlyContinue
}
}
} finally {
$rKey.Dispose()
}
}
}
}
$knownNsGuids = @("{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "{04271989-C4D2-430F-9D0E-2A48B44B1A5C}")
foreach ($nsPath in ($nsRoots | Select-Object -Unique)) {
if (Test-Path -LiteralPath $nsPath) {
foreach ($sub in (Get-ChildItem -LiteralPath $nsPath -ErrorAction SilentlyContinue)) {
$shouldRemove = $false
$cName = ""
try {
$cName  = $sub.PSChildName
$defVal = [string]$sub.GetValue("", "")
if ($cName -in $knownNsGuids -or $defVal -match '(?i)OneDrive') {
$shouldRemove = $true
}
} catch {
} finally {
$sub.Dispose()
}
if ($shouldRemove -and -not [string]::IsNullOrWhiteSpace($cName)) {
Remove-Item -LiteralPath "$nsPath\$cName" -Recurse -Force -ErrorAction SilentlyContinue
}
}
}
}
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [+] Core installation payloads, tasks & multi-profile Run/NameSpace hooks neutralized (SystemRoot stub preserved for SFC).")
}
}
elseif ($data.Type -eq "Registry") {
$registryTargetsToVerify.Add([string]$data.Path)
if (Test-Path -LiteralPath $data.Path) {
Remove-Item -LiteralPath $data.Path -Recurse -Force -ErrorAction Stop
if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Registry key removed: $($data.Path)") }
}
}
elseif ($data.Type -eq "Folder") {
$targetDir = $data.Path
if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (Test-Path -LiteralPath $targetDir)) {
Remove-UltixOneDriveDirectory -TargetDir $targetDir
if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Folder eradicated: $targetDir") }
}
}
} catch {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [!] Error purging $($item.UIDisplayName): $($_.Exception.Message)")
}
}
}
Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
foreach ($regPath in ($registryTargetsToVerify | Select-Object -Unique)) {
if (-not [string]::IsNullOrWhiteSpace($regPath) -and (Test-Path -LiteralPath $regPath)) {
Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction SilentlyContinue
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
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
Stop-Process -Name "Widgets", "WidgetService", "StoreExperienceHost", "WinStore.App", "Copilot", "msteams", "olk", "aixhost", "GameBar" -Force -ErrorAction SilentlyContinue
$provisionedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($p in (Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)) {
if (-not [string]::IsNullOrWhiteSpace($p.PackageName)) {
[void]$provisionedSet.Add($p.PackageName)
}
}
$loadedHives = @(Get-UltixUserProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })
foreach ($item in $Items) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 100)
$UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
}
if ($item.ActionData.IsRecall -eq $true -or $item.UIDisplayName -match "(?i)Recall") {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [*] Enforcing DisableAIDataAnalysis & TurnOffSavingSnapshots GPO locks...")
}
$aiPolicies = [System.Collections.Generic.List[string]]::new()
$aiPolicies.Add("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI")
$aiPolicies.Add("HKCU:\Software\Policies\Microsoft\Windows\WindowsAI")
foreach ($h in $loadedHives) {
$aiPolicies.Add("$($h.HiveRoot)\Software\Policies\Microsoft\Windows\WindowsAI")
}
foreach ($pol in ($aiPolicies | Select-Object -Unique)) {
if (-not (Test-Path -LiteralPath $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -LiteralPath $pol -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $pol -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
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
if ($item.UIDisplayName -match "(?i)Copilot") {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [*] Applying local policy constraints for Windows Copilot...")
}
$policies = [System.Collections.Generic.List[string]]::new()
$policies.Add("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")
$policies.Add("HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")
foreach ($h in $loadedHives) {
$policies.Add("$($h.HiveRoot)\Software\Policies\Microsoft\Windows\WindowsCopilot")
}
foreach ($pol in ($policies | Select-Object -Unique)) {
if (-not (Test-Path -LiteralPath $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -LiteralPath $pol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}
}
foreach ($pkg in $item.ActionData.Installed) {
$pfn = $pkg.PackageFamilyName
try {
try {
Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
[void]$provisionedSet.Remove($pkg.PackageFullName)
} catch {
Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
}
if (-not [string]::IsNullOrWhiteSpace($pfn)) {
$deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
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
foreach ($prov in $item.ActionData.Provisioned) {
if (-not $provisionedSet.Contains($prov.PackageName)) { continue }
try {
Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
[void]$provisionedSet.Remove($prov.PackageName)
$pkgParts = $prov.PackageName -split '_'
if ($pkgParts.Count -ge 5 -and -not [string]::IsNullOrWhiteSpace($pkgParts[0]) -and -not [string]::IsNullOrWhiteSpace($pkgParts[4])) {
$provPfn = "$($pkgParts[0])_$($pkgParts[4])"
$deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$provPfn"
if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
}
if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Deprovisioned base image: $($prov.DisplayName)") }
} catch {
[void]$provisionedSet.Remove($prov.PackageName)
if ($_.Exception.HResult -notin @(-2147024894, -2147024893) -and $_.Exception.Message -notmatch "(?i)0x80070002|0x80070003") {
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
function Show-AppxGrid {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI " -> Scanning installed Appx packages (Background Thread)..."
Update-Progress 20
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
$protectedPattern = Get-UltixProtectedAppxRegex
$pkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
Where-Object { $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedPattern } |
Select-Object Name, PackageFullName, PackageFamilyName, IsFramework, Status |
Sort-Object Name)
return $pkgs
} -OnComplete ({
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
if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
}
$UltixSync.Logs.Enqueue("    [OK] $($app.Name) removed and deprovisioned.")
} catch {
$UltixSync.Logs.Enqueue("    [!] Error removing $($app.Name): $($_.Exception.Message)")
}
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Selected Appx removal routine finished.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Show-AppxProvGrid {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI " -> Scanning Provisioned Appx image packages (Background Thread)..."
Update-Progress 20
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
$protectedPattern = Get-UltixProtectedAppxRegex
$pkgs = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
Where-Object { $_.DisplayName -notmatch $protectedPattern } |
Select-Object DisplayName, Version, PackageName |
Sort-Object DisplayName)
return $pkgs
} -OnComplete ({
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
$pkgParts = $app.PackageName -split '_'
if ($pkgParts.Count -ge 5 -and -not [string]::IsNullOrWhiteSpace($pkgParts[0]) -and -not [string]::IsNullOrWhiteSpace($pkgParts[4])) {
$provPfn = "$($pkgParts[0])_$($pkgParts[4])"
$deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$provPfn"
if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
}
$UltixSync.Logs.Enqueue("    [OK] $($app.DisplayName) deprovisioned.")
} catch {
$UltixSync.Logs.Enqueue("    [!] Error deprovisioning $($app.DisplayName): $($_.Exception.Message)")
}
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Selected Provisioned packages removed from image.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Show-CapsGrid {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI " -> Querying installed Windows Capabilities / FOD (Background Thread)..."
Update-Progress 25
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
$criticalFodRegex = '^(?i)(DirectX\.Configuration\.Database|Microsoft\.Windows\.Ethernet\.Client|Microsoft\.Windows\.Sense\.Client)'
$caps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
Where-Object { $_.State -eq 'Installed' } |
ForEach-Object {
$isCrit = ($_.Name -match $criticalFodRegex)
$stateDisp = if ($isCrit) { "Installed [CRITICAL - LOCKED]" } else { [string]$_.State }
[PSCustomObject]@{
Name     = $_.Name
State    = $stateDisp
IsLocked = $isCrit
}
} | Sort-Object IsLocked, Name)
return $caps
} -OnComplete ({
param($output)
Update-Progress 0
[array]$caps = @($output | Where-Object { $null -ne $_ })
if ($caps.Count -eq 0) {
Write-GUI " -> No installed Capabilities returned.`n"
return
}
$cols = @(
@{ Header = "Capability Name (FOD)"; Property = "Name";  Width = 650 }
@{ Header = "State";                 Property = "State"; Width = 190 }
)
$res = Show-UltixGridModal -Title "WinUltix - Windows Capabilities (FOD)" `
-Description "Select installed Features on Demand (FOD) to uninstall. Critical DirectX, Ethernet LAN, and Defender FODs (Red) are locked." `
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
if ($cap.IsLocked) { continue }
$UltixSync.Logs.Enqueue(" -> Removing capability: $($cap.Name)")
try {
Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
$UltixSync.Logs.Enqueue("    [OK] $($cap.Name) removed.")
} catch {
$UltixSync.Logs.Enqueue("    [!] Failed to remove $($cap.Name): $($_.Exception.Message)")
}
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Capability removal finished.`n"
}.GetNewClosure())
}.GetNewClosure())
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
} -OnComplete ({
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
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Optional Features processing completed.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Initialize-Z2UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Debloat"
$tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$rowOneDrive = New-UltixActionRow -Parent $tabApps -Y 20 -MainRGB @(55, 58, 64) `
-Text "Uninstall and Deprovision OneDrive" `
-Description "Completely uninstalls OneDrive, burns its keys across all loaded HKEY_USERS hives, and physically deletes folders across all user profiles." `
-AuditDescription "AUDIT: Scans for active OneDrive installers, multi-profile HKEY_USERS startup keys, and residual folders." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ModalTitle "WinUltix - OneDrive" -ModalDescription "Select specific OneDrive traces to eradicate." -ExecutorFunction "Invoke-RemoveOneDrive" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
}.GetNewClosure())
$rowBloat = New-UltixActionRow -Parent $tabApps -Y 70 -MainRGB @(135, 50, 50) `
-Text "Aggressive Bloatware & AI Removal" `
-Description "Aggressive, interactive removal of 64 UWP bloatware targets and Windows Recall/Copilot AI telemetry from the system." `
-AuditDescription "AUDIT: Scans the system for target Appx Bloatware, Recall payloads, and prints a detailed footprint report." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ModalTitle "WinUltix - Bloatware & AI Removal" -ModalDescription "Select components to remove. Detected items are checked by default." -ExecutorFunction "Invoke-RemoveBloatware" -ControlsToDisable $allTabButtons.ToArray()
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
}.GetNewClosure())
$rowCaps = New-UltixActionRow -Parent $tabApps -Y 120 -MainRGB @(55, 58, 64) `
-Text "Remove System Features (FOD Preset)" `
-Description "Interactive removal of 14 unnecessary built-in Features on Demand (Steps Recorder, Quick Assist, WordPad, Fax, Hello Face) in a background CBS thread." `
-AuditDescription "AUDIT: Verifies installed unnecessary Capabilities (FOD)." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ModalTitle "WinUltix - FOD Removal" -ModalDescription "Select features to remove." -ExecutorFunction "Invoke-RemoveCapabilities" -ControlsToDisable $allTabButtons.ToArray()
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
}.GetNewClosure())
$rowGC = New-UltixActionRow -Parent $tabApps -Y 170 -MainRGB @(55, 58, 64) `
-Text "Run Appx Framework Garbage Collector" `
-Description "Resolves transitive Appx dependency graphs and removes orphaned UWP frameworks in a background thread." `
-AuditDescription "AUDIT: Scans and lists all orphaned frameworks and base packages that can be safely removed." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ModalTitle "WinUltix - Garbage Collector" -ModalDescription "Select orphaned packages to remove." -ExecutorFunction "Invoke-GarbageCollector" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
}.GetNewClosure())
$rowStubs = New-UltixActionRow -Parent $tabApps -Y 220 -MainRGB @(55, 58, 64) `
-Text "Purge Capability Stubs (CBS)" `
-Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." `
-AuditDescription "AUDIT: Queries CBS registry/payload directly for active stubs." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ModalTitle "WinUltix - Stub Purge" -ModalDescription "Select stubs to rip from the CBS store." -ExecutorFunction "Invoke-RemoveCapabilityStubs" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
}.GetNewClosure())
$lblInspect = New-Object System.Windows.Forms.Label
$lblInspect.Text = "Manual Package & Feature Inspectors (Sortable Grids)"
$lblInspect.Location = New-Object System.Drawing.Point(15, 272)
$lblInspect.Size = New-Object System.Drawing.Size(370, 18)
$lblInspect.ForeColor = [System.Drawing.Color]::DarkGray
$lblInspect.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblWarnInspect = New-Object System.Windows.Forms.Label
$lblWarnInspect.Text = "[!] MANUAL INSPECTORS ONLY -- DO NOT SELECT ALL!`r`nFor targeted inspection of what remains after presets."
$lblWarnInspect.Location = New-Object System.Drawing.Point(15, 293)
$lblWarnInspect.Size = New-Object System.Drawing.Size(370, 40)
$lblWarnInspect.BackColor = [System.Drawing.Color]::FromArgb(255, 58, 35, 20)
$lblWarnInspect.ForeColor = [System.Drawing.Color]::Gold
$lblWarnInspect.BorderStyle = "FixedSingle"
$lblWarnInspect.TextAlign = "MiddleCenter"
$lblWarnInspect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tabApps.Controls.AddRange(@($lblInspect, $lblWarnInspect))
$btnAppxUser = New-UltixButton -Parent $tabApps -X 15 -Y 342 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "Appx (User Accounts)" `
-Description "MANUAL INSPECTOR: Opens a table of all remaining installed Appx packages. Do NOT blindly delete all!" `
-OnClick ({ Show-AppxGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnAppxImg = New-UltixButton -Parent $tabApps -X 205 -Y 342 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "Appx (Base Image)" `
-Description "MANUAL INSPECTOR: Opens a table of Provisioned Appx packages cached in the Windows image." `
-OnClick ({ Show-AppxProvGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnCapsGrid = New-UltixButton -Parent $tabApps -X 15 -Y 392 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "Capabilities (Full FOD)" `
-Description "MANUAL INSPECTOR: Scans all installed Features on Demand (FOD) for selective manual removal." `
-OnClick ({ Show-CapsGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnOptGrid = New-UltixButton -Parent $tabApps -X 205 -Y 392 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "Optional Features (DISM)" `
-Description "MANUAL INSPECTOR: Scans enabled Windows Optional Features (SMB1, Hypervisor, Legacy Components) for selective disabling." `
-OnClick ({ Show-OptFeaturesGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
foreach ($row in @($rowOneDrive, $rowBloat, $rowCaps, $rowGC, $rowStubs)) {
$allTabButtons.AddRange($row.Controls)
}
$allTabButtons.AddRange([System.Windows.Forms.Control[]]@($btnAppxUser, $btnAppxImg, $btnCapsGrid, $btnOptGrid))
$TabControl.Controls.Add($tabApps)
}
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
if ($null -ne $rawVal) {
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
@{ UIDisplayName = "Start Menu: Force Classic Alphabetical List (Disables 26H2 Category Tiles)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"; Name = "AllAppsViewMode"; Expected = 2; Default = 0; Type = "DWord"; RestartShell = $true }
@{ UIDisplayName = "Start Menu: Hide Recently Opened Files & Jump Lists"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_TrackDocs"; Expected = 0; Default = 1; Type = "DWord" }
@{ UIDisplayName = "Start Menu: Hide Recently Added & Most Used Apps"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_TrackProgs"; Expected = 0; Default = 1; Type = "DWord" }
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
$ramKB = [WinUltix.NativeMethods]::GetTotalPhysicalMemoryKB()
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
@{ UIDisplayName = "CPU: Optimize Priority Separation (Focus CPU on foreground)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; Expected = 40; Default = 2; ValidValues = @(38, 40, 42, 22, 24); Type = "DWord" }
@{ UIDisplayName = "Power: Disable Windows Power Throttling globally"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; Expected = 1; Default = 0; Type = "DWord" }
@{ UIDisplayName = "MMCSS Profile: GPU Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Expected = 8; Default = 2; Type = "DWord" }
@{ UIDisplayName = "MMCSS Profile: Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Expected = 6; Default = 2; Type = "DWord" }
@{ UIDisplayName = "MMCSS Profile: Scheduling Category (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Expected = "High"; Default = "Medium"; Type = "String" }
@{ UIDisplayName = "Security: Disable Virtualization Based Security (VBS)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Expected = 0; Default = 1; Type = "DWord" }
@{ UIDisplayName = "Security: Disable Hypervisor-protected Code Integrity (HVCI)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
)
return Invoke-RegistryAudit -Rules $rules
}
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
if ($SelectedItems.Count -eq 0) {
Write-GUI " -> No execution locks selected."
return
}
Update-Progress 5
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
param([array]$Items, [string]$Op)
$total   = $Items.Count
$current = 0
$srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
$srpPaths = "$srpRoot\0\Paths"
$ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$nullStub = "$env:SystemRoot\System32\systray.exe"
if ($Op -eq 'Apply') {
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
$actionVerb    = if ($Op -eq 'Apply') { "Enforcing" } else { "Removing" }
$policyChanged = $false
foreach ($item in $Items) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 75)
$UltixSync.Logs.Enqueue(" -> $($actionVerb) Execution Lock: $($item.UIDisplayName)")
}
$target       = $item.ActionData
$guid         = Get-DeterministicSrpGuid -InputString $target.TargetPath
$ruleKey      = "$srpPaths\$guid"
$ifeoKey      = "$ifeoBase\$($target.ExeName)"
$filterSubKey = "$ifeoKey\$guid"
try {
if ($Op -eq 'Apply') {
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
Set-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
if (-not (Test-Path -LiteralPath $filterSubKey)) { New-Item -Path $filterSubKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $filterSubKey -Name "FilterFullPath" -Value $target.TargetPath -Type String -Force
Set-ItemProperty -LiteralPath $filterSubKey -Name "Debugger" -Value $nullStub -Type String -Force
Set-ItemProperty -LiteralPath $filterSubKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
} else {
Remove-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -Value $nullStub -Type String -Force
Set-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
}
$procName = [System.IO.Path]::GetFileNameWithoutExtension($target.ExeName)
$activeProc = Get-Process -Name $procName -ErrorAction SilentlyContinue
if ($activeProc) {
$activeProc | Stop-Process -Force -ErrorAction SilentlyContinue
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [OK] Flushed active process ($procName) from memory.")
}
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
$remainingProps = @()
$ifeoItem = Get-Item -LiteralPath $ifeoKey -ErrorAction SilentlyContinue
if ($null -ne $ifeoItem) {
try { $remainingProps = @($ifeoItem.Property) } finally { $ifeoItem.Dispose() }
}
if ($remainingSubKeys.Count -eq 0 -and $remainingProps.Count -eq 0) {
Remove-Item -LiteralPath $ifeoKey -Force -ErrorAction SilentlyContinue
}
$policyChanged = $true
}
}
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [OK] SRP & IFEO restriction rules purged from registry.")
}
}
} catch {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [!] Failed to modify execution lock: $($_.Exception.Message)")
}
}
}
if ($Op -eq 'Revert' -and (Test-Path -LiteralPath $srpPaths)) {
$remainingSrp = @(Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)
if ($remainingSrp.Count -eq 0) {
Remove-Item -LiteralPath $srpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
}
$exitCode = $null
if ($policyChanged) {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue(" -> Refreshing Safer API policy tokens (gpupdate.exe /force in background)...")
$UltixSync.Progress = 85
}
$gpProc = Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -WindowStyle Hidden -PassThru
$gpProc.WaitForExit()
$exitCode = $gpProc.ExitCode
$gpProc.Dispose()
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return [PSCustomObject]@{
PolicyChanged = $policyChanged
ExitCode      = $exitCode
Operation     = $Op
}
} -OnComplete ({
param($res)
Update-Progress 0
if ($null -ne $res -and $res.PolicyChanged) {
Write-GUI "    [OK] Kernel IFEO and AuthZ policy tokens updated (ExitCode: $($res.ExitCode)).`n"
} else {
Write-GUI " -> Execution lock operation completed ($Operation).`n"
}
}.GetNewClosure())
}
function Invoke-ApplyRegistry {
param(
[Parameter(Mandatory=$true)][array]$SelectedItems,
[Parameter(Mandatory=$true)][string]$CategoryName,
[ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
[System.Windows.Forms.Control[]]$ControlsToDisable = @(),
[switch]$RefreshShell
)
if ($SelectedItems.Count -eq 0) {
Write-GUI " -> No tweaks selected."
return
}
$doShellRefresh = $RefreshShell.IsPresent
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $CategoryName, $Operation) -ScriptBlock {
param([array]$Items, [string]$CatName, [string]$Op)
$total        = $Items.Count
$current      = 0
$touchedMouse = $false
$actionVerb   = if ($Op -eq 'Apply') { "Enforcing" } else { "Reverting" }
foreach ($item in $Items) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 100)
$UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)")
} else {
Update-Progress ([int](($current / $total) * 100))
Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
}
$reg = $item.ActionData
if ($reg.Path -eq "HKCU:\Control Panel\Mouse") {
$touchedMouse = $true
}
$targetValue = if ($Op -eq 'Apply') { $reg.Expected } else { $reg.Default }
if ($null -eq $targetValue -and $Op -eq 'Revert') {
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
if ($Op -eq 'Apply' -and $reg.ContainsKey("ValidValues")) {
$curRaw = (Get-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue).$($reg.Name)
if ($null -ne $curRaw) {
$curNorm = if ($reg.Type -eq "DWord" -and $curRaw -is [int] -and $curRaw -lt 0) {
[BitConverter]::ToUInt32([BitConverter]::GetBytes($curRaw), 0)
} else {
$curRaw
}
if ($reg.ValidValues -contains $curNorm -or $reg.ValidValues -contains $curRaw) {
if ($reg.Name -eq "Win32PrioritySeparation" -and $curNorm -ne $reg.Expected) {
Write-GUI ("    [OK] Preserved active Quantum Scheduler preset (0x{0:X2} / {0} dec)." -f [int]$curNorm)
}
continue
}
}
}
if ($reg.ContainsKey("AltName")) {
if ($Op -eq 'Apply') {
Set-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Value $reg.AltExpected -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
} else {
Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Force -ErrorAction SilentlyContinue | Out-Null
Remove-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Force -ErrorAction SilentlyContinue | Out-Null
}
}
if ($reg.Name -eq "" -or $reg.Name -eq "(Default)") {
Set-Item -LiteralPath $reg.Path -Value ([string]$targetValue) -Force -ErrorAction Stop | Out-Null
} elseif ($reg.Name -eq "DirectXUserGlobalSettings" -and $Op -eq 'Apply') {
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
$writeVal = $targetValue
if ($reg.Type -eq "DWord" -and $writeVal -is [long] -and $writeVal -gt [int]::MaxValue) {
$writeVal = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$writeVal), 0)
}
Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $writeVal -Type $reg.Type -Force -ErrorAction Stop | Out-Null
}
} catch {
if ($reg.ContainsKey("AltName")) {
try {
if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UCPD") {
Set-ProtectedServiceStart -ServiceName "UCPD" -StartValue 4
Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "UCPD velocity" -ErrorAction SilentlyContinue | Out-Null
}
if ($Op -eq 'Apply') {
Set-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Value $reg.AltExpected -Type DWord -Force -ErrorAction Stop | Out-Null
Set-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
Write-GUI "    [+] Bypassed UCPD.sys filter via $($reg.AltName)=1 & disarmed UCPD driver."
} else {
Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Force -ErrorAction SilentlyContinue | Out-Null
Remove-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Force -ErrorAction SilentlyContinue | Out-Null
Write-GUI "    [+] Reverted $($reg.AltName) policy & disarmed UCPD filter (Reboot unlocks $($reg.Name))."
}
} catch {
Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)"
}
} else {
Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)"
}
}
}
if ($touchedMouse) {
try {
$mProps = Get-ItemProperty -LiteralPath "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1", "MouseThreshold2", "MouseSpeed" -ErrorAction SilentlyContinue
$t1 = if ($null -ne $mProps -and $mProps.MouseThreshold1 -match '^\d+$') { [int]$mProps.MouseThreshold1 } else { 0 }
$t2 = if ($null -ne $mProps -and $mProps.MouseThreshold2 -match '^\d+$') { [int]$mProps.MouseThreshold2 } else { 0 }
$sp = if ($null -ne $mProps -and $mProps.MouseSpeed -match '^\d+$')      { [int]$mProps.MouseSpeed }      else { 0 }
if ([WinUltix.NativeMethods]::ApplyLiveMouseParams($t1, $t2, $sp)) {
Write-GUI "    [OK] Live-reloaded win32kfull.sys pointer acceleration table (SPI_SETMOUSE: $t1/$t2/$sp)."
}
} catch { }
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> $CategoryName registry modifications completed ($Operation)."
if ($doShellRefresh) {
Update-ShellEnvironment -ModifiedItems $SelectedItems
}
if ($null -eq $UltixSync) {
Write-GUI ""
}
}.GetNewClosure())
}
function Invoke-StartMenuAudit {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI "--- AUDIT: Start Menu Pins & Layout Mode (Background Thread) ---"
Update-Progress 15
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
$UltixSync.Progress = 35
$pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $pkgDir) {
$UltixSync.Logs.Enqueue("  [OK] StartMenuExperienceHost package not found in current user profile.")
$UltixSync.Progress = 100
return
}
$localState = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
$binFile    = Get-Item -Path (Join-Path $localState "start2.bin") -Force -ErrorAction SilentlyContinue
$clearedSz  = (Get-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -ErrorAction SilentlyContinue).StartMenuClearedSize
if ($null -ne $binFile) {
$szKB = [math]::Round($binFile.Length / 1KB, 2)
if ($null -ne $clearedSz -and [math]::Abs($binFile.Length - $clearedSz) -le 512) {
$UltixSync.Logs.Enqueue("  [OK] Clean minimal layout active: start2.bin ($szKB KB - Edge, Settings, Explorer).")
} else {
$UltixSync.Logs.Enqueue("  [!] Active layout database detected: $($binFile.Name) ($szKB KB).")
}
} else {
$UltixSync.Logs.Enqueue("  [OK] Start Menu binary database is not present.")
}
$UltixSync.Progress = 70
$viewMode  = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "AllAppsViewMode" -ErrorAction SilentlyContinue).AllAppsViewMode
$trackDocs = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -ErrorAction SilentlyContinue).Start_TrackDocs
if ($viewMode -eq 2 -and $trackDocs -eq 0) {
$UltixSync.Logs.Enqueue("  [OK] All Apps View: Classic Alphabetical List (AllAppsViewMode=2) & Recent Files hidden.")
} else {
$UltixSync.Logs.Enqueue("  [!] All Apps View / Recent Files not yet locked to Classic List (Current ViewMode: $(if($null -ne $viewMode){$viewMode}else{'0 - Category Tiles'})).")
}
$provGuid   = "B5292708-1619-419B-9923-E5D9F3925E71"
$policyPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
$mdmLock    = (Get-ItemProperty -LiteralPath $policyPath -Name "ConfigureStartPins_ProviderSet" -ErrorAction SilentlyContinue).ConfigureStartPins_ProviderSet
$hasProvKey = (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid") -or
(Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Enrollments\$provGuid")
if ($mdmLock -eq 1 -or $hasProvKey) {
$UltixSync.Logs.Enqueue("  [!] Residual MDM Start Menu provider/lock detected in PolicyManager ($provGuid).")
} else {
$UltixSync.Logs.Enqueue("  [OK] No residual MDM Start Menu locks or orphaned provider keys found.")
}
$UltixSync.Progress = 100
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI ""
}.GetNewClosure())
}
function Clear-StartMenu {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI " -> Initializing deterministic Start Menu reset (3-Icon + Classic List + No Recent Files)..."
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
$policyUserPath   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PolicyManager\current\user\Start"
$cleanPinsJson = '{"pinnedList":[{"desktopAppId":"MSEdge"},{"packagedAppId":"windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"},{"desktopAppId":"Microsoft.Windows.Explorer"}]}'
$createdEnrollment = $false
try {
if ($null -ne $UltixSync) {
$UltixSync.Progress = 15
$UltixSync.Logs.Enqueue(" -> [1/7] Disabling ContentDeliveryManager, Recent Files & forcing Classic Alphabetical List...")
}
$cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
if (Test-Path -LiteralPath $cdmPath) {
foreach ($cdmName in @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "SubscribedContentEnabled")) {
Set-ItemProperty -LiteralPath $cdmPath -Name $cdmName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath "$cdmPath\SuggestedApps") {
Remove-Item -LiteralPath "$cdmPath\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue
}
}
$advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
if (Test-Path -LiteralPath $advPath) {
Set-ItemProperty -LiteralPath $advPath -Name "Start_TrackDocs" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $advPath -Name "Start_TrackProgs" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $advPath -Name "Start_IrisRecommendations" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $advPath -Name "Start_AccountNotifications" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $advPath -Name "Start_Layout" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}
$expPolPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path -LiteralPath $expPolPath)) { New-Item -Path $expPolPath -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -LiteralPath $expPolPath -Name "HideRecommendedSection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $expPolPath -Name "NoRecentDocsHistory" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
$recentDir = "$env:APPDATA\Microsoft\Windows\Recent"
if (Test-Path -LiteralPath $recentDir) {
Get-ChildItem -LiteralPath $recentDir -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath "$recentDir\AutomaticDestinations") {
Get-ChildItem -LiteralPath "$recentDir\AutomaticDestinations" -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
}
if ($null -ne $UltixSync) {
$UltixSync.Progress = 30
$UltixSync.Logs.Enqueue(" -> [2/7] Injecting temporary MDM PolicyManager provider context...")
}
if (-not (Test-Path -LiteralPath $enrollmentPath)) {
New-Item -Path $enrollmentPath -Force -ErrorAction Stop | Out-Null
$createdEnrollment = $true
}
Set-ItemProperty -LiteralPath $enrollmentPath -Name "EnrollmentState" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $enrollmentPath -Name "EnrollmentType" -Value 6 -Type DWord -Force
Set-ItemProperty -LiteralPath $enrollmentPath -Name "IsFederated" -Value 0 -Type DWord -Force
Set-ItemProperty -LiteralPath $enrollmentPath -Name "ProviderID" -Value "MS DM Server" -Type String -Force
if (-not (Test-Path -LiteralPath $providerPath)) {
New-Item -Path $providerPath -Force -ErrorAction Stop | Out-Null
}
Set-ItemProperty -LiteralPath $providerPath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
Set-ItemProperty -LiteralPath $providerPath -Name "ConfigureStartPins_LastWrite" -Value 1 -Type DWord -Force
if (-not (Test-Path -LiteralPath $policyDevicePath)) {
New-Item -Path $policyDevicePath -Force -ErrorAction Stop | Out-Null
}
Set-ItemProperty -LiteralPath $policyDevicePath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
Set-ItemProperty -LiteralPath $policyDevicePath -Name "ConfigureStartPins_ProviderSet" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $policyDevicePath -Name "ConfigureStartPins_WinningProvider" -Value $provGuid -Type String -Force
if ($null -ne $UltixSync) {
$UltixSync.Progress = 45
$UltixSync.Logs.Enqueue(" -> [3/7] Purging CloudStore tile grid and enforcing AllAppsViewMode=2 (List View)...")
}
$cloudStoreRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current"
if (Test-Path -LiteralPath $cloudStoreRoot) {
Get-ChildItem -LiteralPath $cloudStoreRoot -ErrorAction SilentlyContinue | Where-Object {
$_.PSChildName -match "start\.tilegrid|unifiedtile|start\.allapps|start\.properties"
} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
$startRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
if (Test-Path -LiteralPath $startRegPath) {
Remove-Item -LiteralPath $startRegPath -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $startRegPath -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -LiteralPath $startRegPath -Name "AllAppsViewMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $startRegPath -Name "ShowRecentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $startRegPath -Name "ShowFrequentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
if ($null -ne $UltixSync) {
$UltixSync.Progress = 60
$UltixSync.Logs.Enqueue(" -> [4/7] Recycling Explorer & wiping locked start2.bin database...")
}
Stop-Process -Name "StartMenuExperienceHost", "ShellExperienceHost", "explorer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
for ($attempt = 1; $attempt -le 6; $attempt++) {
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $startStatePath -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
$binFull = $_.FullName
try {
$_.Attributes = 'Normal'
Remove-Item -LiteralPath $binFull -Force -ErrorAction Stop
} catch {
$trashBin = Join-Path -Path $env:TEMP -ChildPath "WinUltix_StartBin_$([guid]::NewGuid().ToString('N')).tmp"
Move-Item -LiteralPath $binFull -Destination $trashBin -Force -ErrorAction SilentlyContinue
}
}
if (-not (Test-Path -LiteralPath (Join-Path $startStatePath "start2.bin"))) { break }
Start-Sleep -Milliseconds 60
}
if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
Start-Process "explorer.exe"
Start-Sleep -Milliseconds 800
}
if ($null -ne $UltixSync) {
$UltixSync.Progress = 75
$UltixSync.Logs.Enqueue(" -> [5/7] Invoking COM IApplicationActivationManager to compile clean start2.bin...")
}
$appActivator = $null
try {
$appActivator = New-Object WinUltix.AppActivator
[uint32]$activatedPid = 0
[void]$appActivator.ActivateApplication("Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!App", $null, 0, [ref]$activatedPid)
} catch {
} finally {
if ($null -ne $appActivator -and [System.Runtime.InteropServices.Marshal]::IsComObject($appActivator)) {
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($appActivator)
}
}
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
if (-not (Test-Path -LiteralPath "HKCU:\Software\WinUltix")) { New-Item -Path "HKCU:\Software\WinUltix" -Force | Out-Null }
Set-ItemProperty -LiteralPath "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -Value $newBinSize -Type DWord -Force
}
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [OK] Native start2.bin compiled (3-Icon + Classic Alphabetical List + No Recent Files).")
}
} catch {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [!] Error during Start Menu native compilation: $($_.Exception.Message)")
}
} finally {
if ($null -ne $UltixSync) {
$UltixSync.Progress = 90
$UltixSync.Logs.Enqueue(" -> [6/7] Stripping temporary MDM PolicyManager locks...")
}
foreach ($polPath in @($policyDevicePath, $policyLegacyPath, $policyUserPath, "HKCU:\Software\Microsoft\PolicyManager\current\user\Start")) {
if (Test-Path -LiteralPath $polPath) {
Remove-ItemProperty -LiteralPath $polPath -Name "ConfigureStartPins" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -LiteralPath $polPath -Name "ConfigureStartPins_ProviderSet" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -LiteralPath $polPath -Name "ConfigureStartPins_WinningProvider" -Force -ErrorAction SilentlyContinue
}
}
if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid") {
Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid" -Recurse -Force -ErrorAction SilentlyContinue
}
if ($createdEnrollment -and (Test-Path -LiteralPath $enrollmentPath)) {
Remove-Item -LiteralPath $enrollmentPath -Recurse -Force -ErrorAction SilentlyContinue
}
Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
Start-Process "explorer.exe"
}
}
if ($null -ne $UltixSync) {
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [7/7] Provisioning Default User profile LayoutModification.json...")
}
$defaultShellPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
if (-not (Test-Path -LiteralPath $defaultShellPath)) {
New-Item -Path $defaultShellPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}
$defaultJsonPath = Join-Path -Path $defaultShellPath -ChildPath "LayoutModification.json"
Set-Content -LiteralPath $defaultJsonPath -Value $cleanPinsJson -Encoding UTF8 -Force -ErrorAction SilentlyContinue
$defaultPkgPath = "$env:SystemDrive\Users\Default\AppData\Local\Packages"
if (Test-Path -LiteralPath $defaultPkgPath) {
Get-ChildItem -Path $defaultPkgPath -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
Get-ChildItem -Path (Join-Path $_.FullName "LocalState") -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
}
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [OK] Default User LayoutModification.json provisioned.")
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI ""
}.GetNewClosure())
}
function Get-PowerDisplayState {
if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$hiberVal = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled
$results.Add([PSCustomObject]@{
UIDisplayName = "Power: Disable Hibernation & Purge hiberfil.sys"
IsDetected    = ($null -eq $hiberVal -or $hiberVal -ne 0)
ActionData    = @{ Type = "Hiber" }
})
if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }
$standbySec = Get-UltixPowerAcIndex -SubGroupGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" -SettingGuid "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" -IncludeHidden
$results.Add([PSCustomObject]@{
UIDisplayName = "Power: Disable System Sleep / Standby Timeout (Current AC: $(if ($null -ne $standbySec) { "$standbySec s" } else { 'N/A' }))"
IsDetected    = ($null -eq $standbySec -or $standbySec -ne 0)
ActionData    = @{ Type = "PowerCfg"; Sub = "238c9fa8-0aad-41ed-83f4-97be242c8f20"; Guid = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"; OptAC = 0; OptDC = 0; DefAC = 1800; DefDC = 900 }
})
$videoSec = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" -IncludeHidden
$results.Add([PSCustomObject]@{
UIDisplayName = "Display: Set Monitor Turn-Off Timeout to 60 Min (Current AC: $(if ($null -ne $videoSec) { "$([math]::Round($videoSec / 60)) min" } else { 'N/A' }))"
IsDetected    = ($null -eq $videoSec -or ($videoSec -ne 0 -and $videoSec -lt 3600))
ActionData    = @{ Type = "PowerCfg"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"; OptAC = 3600; OptDC = 3600; DefAC = 900; DefDC = 300 }
})
if ($null -ne $UltixSync) { $UltixSync.Progress = 50 }
$diskSec = Get-UltixPowerAcIndex -SubGroupGuid "0012ee47-9041-4b5d-9b77-535fba8b1442" -SettingGuid "6738e2c4-e8a5-4a42-b16a-e040e769756e" -IncludeHidden
$results.Add([PSCustomObject]@{
UIDisplayName = "Storage: Disable HDD / SATA Controller Spin-Down (Current AC: $(if ($null -ne $diskSec) { "$diskSec s" } else { 'N/A' }))"
IsDetected    = ($null -eq $diskSec -or $diskSec -ne 0)
ActionData    = @{ Type = "PowerCfg"; Sub = "0012ee47-9041-4b5d-9b77-535fba8b1442"; Guid = "6738e2c4-e8a5-4a42-b16a-e040e769756e"; OptAC = 0; OptDC = 0; DefAC = 1200; DefDC = 600 }
})
$usbVal = Get-UltixPowerAcIndex -SubGroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -IncludeHidden
$usbLabel = if ($usbVal -eq 0) { "Disabled" } elseif ($usbVal -eq 1) { "Enabled" } else { "N/A" }
$results.Add([PSCustomObject]@{
UIDisplayName = "USB: Disable USB Selective Suspend - Protects DACs/VR/Dongles (Current: $usbLabel)"
IsDetected    = ($null -eq $usbVal -or $usbVal -ne 0)
ActionData    = @{ Type = "PowerCfg"; Sub = "2a737441-1930-4402-8d77-b2bebba308a3"; Guid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 1 }
})
if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }
$pcieVal = Get-UltixPowerAcIndex -SubGroupGuid "501a4d13-42af-4429-9fd1-a8218c268e20" -SettingGuid "ee12f906-d277-404b-b6da-e5fa1a576df5" -IncludeHidden
$pcieLabel = switch ($pcieVal) { 0 { "Off" } 1 { "Moderate" } 2 { "Max Saving" } default { "N/A" } }
$results.Add([PSCustomObject]@{
UIDisplayName = "PCIe: Disable Plan Link State Power Management (Current AC: $pcieLabel)"
IsDetected    = ($null -eq $pcieVal -or $pcieVal -ne 0)
ActionData    = @{ Type = "PowerCfg"; Sub = "501a4d13-42af-4429-9fd1-a8218c268e20"; Guid = "ee12f906-d277-404b-b6da-e5fa1a576df5"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 2 }
})
$cabcVal = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "aded5e82-b909-4619-9949-f5d71dac0bcb" -IncludeHidden
$cabcReg = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "DisableCABC" -ErrorAction SilentlyContinue).DisableCABC
$isCabcOpt = (($null -eq $cabcVal -or $cabcVal -eq 0) -and $cabcReg -eq 1)
$results.Add([PSCustomObject]@{
UIDisplayName = "Display: Disable Content Adaptive Brightness (CABC / OLED Auto-Dimming)"
IsDetected    = (-not $isCabcOpt)
ActionData    = @{ Type = "CABC"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "aded5e82-b909-4619-9949-f5d71dac0bcb"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 1 }
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
powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.OptAC 2>$null
powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.OptDC 2>$null
if (-not (Test-Path -LiteralPath $gfxKey)) { New-Item -Path $gfxKey -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -LiteralPath $gfxKey -Name "DisableCABC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
} else {
powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.DefAC 2>$null
powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.DefDC 2>$null
Remove-ItemProperty -LiteralPath $gfxKey -Name "DisableCABC" -Force -ErrorAction SilentlyContinue
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
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Power & Display subsystem configuration completed ($Operation).`n"
}.GetNewClosure())
}
function Initialize-Z3UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tabReg = New-Object System.Windows.Forms.TabPage
$tabReg.Text = "Tweaks"
$tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$invokeRegCategory = ({
param(
[string]$ScannerFn,
[string]$CategoryName,
[string]$ModalTitle,
[string]$AuditHeader,
[switch]$RefreshShell,
[switch]$AuditOnly
)
Invoke-UltixAuditFlow `
-ScannerFunction $ScannerFn `
-AuditLabel $AuditHeader `
-ModalTitle $ModalTitle `
-ModalDescription "Select tweaks to apply or revert." `
-ExecutorFunction "Invoke-ApplyRegistry" `
-ExecutorExtraParams @{
CategoryName = $CategoryName
RefreshShell = $RefreshShell.IsPresent
} `
-ControlsToDisable $allTabButtons.ToArray() `
-AuditOnly:$AuditOnly.IsPresent `
-AuditPrefix "To Optimize" `
-EnableRevert
}.GetNewClosure())
$rowTaskbar = New-UltixActionRow -Parent $tabReg -Y 20 -MainRGB @(55, 58, 64) `
-Text "Taskbar and Start Menu Tweaks" `
-Description "Aligns the taskbar to the left, kills Bing search assistants, disables notifications bloat, and hides Widgets (with UCPD.sys bypass)." `
-AuditDescription "AUDIT: Verifies taskbar alignment policy, Start Menu layouts, Widgets state, and Bing locks." `
-OnClick ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -RefreshShell }.GetNewClosure()) `
-OnAudit ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -AuditOnly }.GetNewClosure())
$rowStartMenu = New-UltixActionRow -Parent $tabReg -Y 70 -MainRGB @(55, 58, 64) `
-Text "Reset Start Menu Layout (Clean 3-Icon)" `
-Description "Wipes promotional Start Menu tiles (start2.bin) and compiles a clean 3-icon layout (Edge, Settings, Explorer) with zero MDM locks left behind." `
-AuditDescription "AUDIT: Scans the size of the current Start Menu layout database (start2.bin) and checks for residual MDM locks." `
-OnClick ({
$msgText = "This action will permanently wipe your Start Menu pins and layout database.`n`nStartMenuExperienceHost will be restarted in the background (System Tray remains intact).`n`nDo you want to proceed?"
$msgResult = [System.Windows.Forms.MessageBox]::Show($msgText, "WinUltix - Reset Start Menu", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
if ($msgResult -eq [System.Windows.Forms.DialogResult]::Yes) {
Clear-StartMenu -ControlsToDisable $allTabButtons.ToArray()
} else {
Write-GUI " -> Start Menu reset aborted by user.`n"
}
}.GetNewClosure()) `
-OnAudit ({ Invoke-StartMenuAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$rowExplorer = New-UltixActionRow -Parent $tabReg -Y 120 -MainRGB @(55, 58, 64) `
-Text "File Explorer and Context Menu" `
-Description "Restores the classic Windows 10 right-click context menu, shows file extensions, unpins OneDrive, and runs folder windows in a separate process." `
-AuditDescription "AUDIT: Verifies classic context menu CLSID registration and File Explorer performance flags." `
-OnClick ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -RefreshShell }.GetNewClosure()) `
-OnAudit ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -AuditOnly }.GetNewClosure())
$rowAnnoy = New-UltixActionRow -Parent $tabReg -Y 170 -MainRGB @(55, 58, 64) `
-Text "OS Annoyances (Modern Standby / Keys)" `
-Description "Disables Modern Standby S0 (forces hardware S3 sleep), blocks AutoPlay across all drives, and disables Sticky/Filter/Toggle Keys popups." `
-AuditDescription "AUDIT: Verifies Modern Standby S0 override, AutoPlay policy, and Sticky Keys blockade." `
-OnClick ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" }.GetNewClosure()) `
-OnAudit ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" -AuditOnly }.GetNewClosure())
$rowPower = New-UltixActionRow -Parent $tabReg -Y 220 -MainRGB @(55, 58, 64) `
-Text "Optimize Power and Display (7-Point)" `
-Description "7-Point Power & Display tuner: Disables Hibernation (hiberfil.sys), Sleep/SATA spin-down, USB Selective Suspend (protects DACs/8K mice), PCIe ASPM, and OLED CABC dimming." `
-AuditDescription "AUDIT: Verifies active Power Plan timeouts, USB Selective Suspend, PCIe ASPM, CABC, and Hibernation state." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ModalTitle "WinUltix - Power & Display Optimizer" -ModalDescription "Select power and display parameters to enforce or revert to Windows defaults." -ExecutorFunction "Invoke-ApplyPowerDisplay" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Unoptimized"
}.GetNewClosure())
$rowMouse = New-UltixActionRow -Parent $tabReg -Y 270 -MainRGB @(45, 85, 125) `
-Text "Hard Mouse Acceleration Disable (1:1)" `
-Description "Enforces pure 1:1 raw pointer input by disabling 'Enhance pointer precision' and zeroing acceleration thresholds." `
-AuditDescription "AUDIT: Scans HKCU\Control Panel\Mouse for pointer acceleration thresholds." `
-OnClick ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" }.GetNewClosure()) `
-OnAudit ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" -AuditOnly }.GetNewClosure())
$rowGaming = New-UltixActionRow -Parent $tabReg -Y 320 -MainRGB @(135, 50, 50) `
-Text "Hardware and Gaming Registry (Extreme)" `
-Description "Enforces MMCSS gaming thread priorities, disables GameDVR, disables Multiplane Overlay (MPO - fixes VRR/OLED flicker), enables Flip Model, and tunes VBS/HVCI." `
-AuditDescription "AUDIT: Verifies MMCSS limits, MPO state, GameDVR, HAGS, and VBS/HVCI flags." `
-OnClick ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" }.GetNewClosure()) `
-OnAudit ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" -AuditOnly }.GetNewClosure())
foreach ($row in @($rowTaskbar, $rowStartMenu, $rowExplorer, $rowAnnoy, $rowPower, $rowMouse, $rowGaming)) {
$allTabButtons.AddRange($row.Controls)
}
$TabControl.Controls.Add($tabReg)
}
function Invoke-ServicesAudit {
param([Parameter(Mandatory=$true)][array]$Rules)
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$total   = $Rules.Count
$current = 0
$svcRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services", $false)
try {
foreach ($rule in $Rules) {
$current++
if ($null -ne $UltixSync -and $total -gt 0) {
$UltixSync.Progress = [int](($current / $total) * 100)
}
$currentStart = $null
if ($null -ne $svcRoot) {
$svcKey = $svcRoot.OpenSubKey($rule.Name, $false)
if ($null -ne $svcKey) {
try {
$currentStart = $svcKey.GetValue("Start", $null)
} finally {
$svcKey.Dispose()
}
}
}
$isDetected = ($null -ne $currentStart -and [int]$currentStart -ne [int]$rule.ExpectedStart)
$results.Add([PSCustomObject]@{
UIDisplayName = $rule.UIDisplayName
IsDetected    = $isDetected
ActionData    = $rule
})
}
} finally {
if ($null -ne $svcRoot) { $svcRoot.Dispose() }
}
return @($results)
}
function Test-UltixTaskAdminWritable {
param(
[Parameter(Mandatory=$true)][string]$TaskPath,
[Parameter(Mandatory=$true)][string]$TaskName
)
$relPath  = ($TaskPath.Trim('\') + "\" + $TaskName).TrimStart('\')
$treePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\$relPath"
if (Test-Path -LiteralPath $treePath) {
try {
[byte[]]$sdBytes = (Get-ItemProperty -LiteralPath $treePath -Name "SD" -ErrorAction SilentlyContinue).SD
if ($null -ne $sdBytes -and $sdBytes.Length -ge 20) {
$rawSd = New-Object System.Security.AccessControl.RawSecurityDescriptor($sdBytes, 0)
if ($null -ne $rawSd.DiscretionaryAcl) {
$adminWritable = $false
foreach ($ace in $rawSd.DiscretionaryAcl) {
if ([int]$ace.AceQualifier -ne 0) { continue }
$sidVal = $ace.SecurityIdentifier.Value
if ($sidVal -in @("S-1-5-32-544", "S-1-5-32-545", "S-1-5-11", "S-1-1-0")) {
if (($ace.AccessMask -band 0x50000006) -ne 0) {
$adminWritable = $true
break
}
}
}
if (-not $adminWritable) { return $false }
}
}
} catch { }
}
return $true
}
function Get-TelemetryTasksState {
if ($null -ne $UltixSync) { $UltixSync.Progress = 15 }
$rules = @(
@{ UIDisplayName = "Task: CEIP (Customer Experience Improvement Program)"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Application Experience (CompatTelRunner / Appraiser)"; TaskPath = "\Microsoft\Windows\Application Experience\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Autochk Proxy & Disk Diagnostic Telemetry"; TaskPath = "\Microsoft\Windows\Autochk\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Disk Diagnostic Data Collector"; TaskPath = "\Microsoft\Windows\DiskDiagnostic\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Windows Feedback & Diagnostics (Siuf)"; TaskPath = "\Microsoft\Windows\Feedback\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Windows Performance Trace & WDI Resolution"; TaskPath = "\Microsoft\Windows\PerformanceTrace\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Windows Error Reporting (QueueReporting)"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\*"; ExpectedState = "Disabled" }
@{ UIDisplayName = "Task: Xbox Live Game Save Background Sync"; TaskPath = "\Microsoft\XblGameSave\*"; ExpectedState = "Disabled" }
)
$protectedSdbTasks = '^(?i)(PcaPatchDbTask|SdbinstMergeDbTask)$'
$allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
if ($null -ne $UltixSync) { $UltixSync.Progress = 70 }
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($rule in $rules) {
$activeTasks = @($allTasks | Where-Object {
$_.TaskPath -like $rule.TaskPath -and
$_.TaskName -notmatch $protectedSdbTasks -and
($_.State -eq 'Ready' -or $_.State -eq 'Running') -and
(Test-UltixTaskAdminWritable -TaskPath $_.TaskPath -TaskName $_.TaskName)
})
$results.Add([PSCustomObject]@{
UIDisplayName = $rule.UIDisplayName
IsDetected    = ($activeTasks.Count -gt 0)
ActionData    = $rule
})
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return @($results)
}
function Get-ServicesState_Light {
$rules = @(
@{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Telemetry: WAP Push Message Routing (dmwappushservice)"; Name = "dmwappushservice"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Device Inventory Service (InventorySvc)"; Name = "InventorySvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Problem Reports Control Panel Support (wercplsupport)"; Name = "wercplsupport"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Telemetry: Windows Insider Service (wisvc)"; Name = "wisvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Bloat: Microsoft Wallet Service (WalletService)"; Name = "WalletService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Mobile: Payments and NFC/SE Manager (SEMgrSvc)"; Name = "SEMgrSvc"; ExpectedStart = 4; DefaultStart = 3 }
)
return Invoke-ServicesAudit -Rules $rules
}
function Get-ServicesState_Heavy {
$rules = @(
@{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Telemetry: WAP Push Message Routing (dmwappushservice)"; Name = "dmwappushservice"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Device Inventory Service (InventorySvc)"; Name = "InventorySvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Problem Reports Control Panel Support (wercplsupport)"; Name = "wercplsupport"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Telemetry: Windows Insider Service (wisvc)"; Name = "wisvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Diagnostics: Diagnostic Policy Service - Stops SRUM disk logging (DPS)"; Name = "DPS"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Diagnostics: Diagnostic Service Host (WdiServiceHost)"; Name = "WdiServiceHost"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Diagnostics: Diagnostic System Host (WdiSystemHost)"; Name = "WdiSystemHost"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Diagnostics: Performance Logs & Alerts (pla)"; Name = "pla"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Updates: Delivery Optimization P2P (DoSvc)"; Name = "DoSvc"; ExpectedStart = 3; DefaultStart = 2 }
@{ UIDisplayName = "Edge: Edge Update Service (edgeupdate)"; Name = "edgeupdate"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Edge: Edge Update Service M (edgeupdatem)"; Name = "edgeupdatem"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Performance: SysMain / Superfetch - Disables RAM caching (SysMain)"; Name = "SysMain"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Search: Windows Search - Disables file indexing (WSearch)"; Name = "WSearch"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "FileSystem: Distributed Link Tracking Client (TrkWks)"; Name = "TrkWks"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Backup: Windows File History Service (fhsvc)"; Name = "fhsvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Networking: Offline Files (CscService)"; Name = "CscService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Networking: Connected Devices Platform (CDPSvc)"; Name = "CDPSvc"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Per-User: Connected Devices User Service Template (CDPUserSvc)"; Name = "CDPUserSvc"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Per-User: Sync Host Background Mail/Calendar Template (OneSyncSvc)"; Name = "OneSyncSvc"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Per-User: Contact Data Indexer Template (PimIndexMaintenanceSvc)"; Name = "PimIndexMaintenanceSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Per-User: User Data Storage Template (UnistoreSvc)"; Name = "UnistoreSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Per-User: User Data Access Template (UserDataSvc)"; Name = "UserDataSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "AI: Windows AI Fabric Service (WSAIFabricSvc)"; Name = "WSAIFabricSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Virtualization: Windows Subsystem for Linux (WSLService)"; Name = "WSLService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Input: Microsoft GameInput Service - Fixes HID stutter (GameInputSvc)"; Name = "GameInputSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Logitech: Lamp Array Service RGB (logi_lamparray_service)"; Name = "logi_lamparray_service"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Printers: Print Spooler - Disables all printing (Spooler)"; Name = "Spooler"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Printers: Print Notify Service (PrintNotify)"; Name = "PrintNotify"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Printers: Fax Service (Fax)"; Name = "Fax"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Remote: Remote Desktop Services (TermService)"; Name = "TermService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Remote: Remote Registry (RemoteRegistry)"; Name = "RemoteRegistry"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Security: Smart Card Reader Service (SCardSvr)"; Name = "SCardSvr"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Location: Geolocation Service (lfsvc)"; Name = "lfsvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Location: Auto Time Zone Updater (tzautoupdate)"; Name = "tzautoupdate"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
@{ UIDisplayName = "Biometrics: Windows Biometric Service (WbioSrvc)"; Name = "WbioSrvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Camera: Windows Camera Frame Server (FrameServer)"; Name = "FrameServer"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Camera: Windows Camera Frame Server Monitor (FrameServerMonitor)"; Name = "FrameServerMonitor"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Sensors: Sensor Data Service (SensorDataService)"; Name = "SensorDataService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Sensors: Sensor Service (SensorService)"; Name = "SensorService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Sensors: Sensor Monitoring Service (SensrSvc)"; Name = "SensrSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Bloat: Microsoft Wallet Service (WalletService)"; Name = "WalletService"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Mobile: Payments and NFC/SE Manager (SEMgrSvc)"; Name = "SEMgrSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Mobile: Phone Service (PhoneSvc)"; Name = "PhoneSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Mobile: Cellular Time Synchronization (autotimesvc)"; Name = "autotimesvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Network: Windows Mobile Hotspot Service (icssvc)"; Name = "icssvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Network: WWAN Cellular AutoConfig (WwanSvc)"; Name = "WwanSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Network: Internet Connection Sharing (SharedAccess)"; Name = "SharedAccess"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Network: SSDP Multicast Discovery (SSDPSRV)"; Name = "SSDPSRV"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Network: UPnP Device Host (upnphost)"; Name = "upnphost"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Network: TCP/IP NetBIOS Helper (lmhosts)"; Name = "lmhosts"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Xbox: Xbox Live Auth Manager (XblAuthManager)"; Name = "XblAuthManager"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Xbox: Xbox Live Game Save (XblGameSave)"; Name = "XblGameSave"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Xbox: Xbox Live Networking Service (XboxNetApiSvc)"; Name = "XboxNetApiSvc"; ExpectedStart = 4; DefaultStart = 3 }
@{ UIDisplayName = "Xbox: Xbox Accessory Management (XboxGipSvc)"; Name = "XboxGipSvc"; ExpectedStart = 4; DefaultStart = 3 }
)
return Invoke-ServicesAudit -Rules $rules
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
$protectedSdbTasks = '^(?i)(PcaPatchDbTask|SdbinstMergeDbTask)$'
$allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
foreach ($item in $Items) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 100)
$UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)")
}
$taskRule = $item.ActionData
$tasks = @($allTasks | Where-Object {
$_.TaskPath -like $taskRule.TaskPath -and
$_.TaskName -notmatch $protectedSdbTasks
})
if ($tasks.Count -eq 0) { continue }
$okCount   = 0
$skipCount = 0
foreach ($task in $tasks) {
try {
if ($Op -eq 'Apply') {
Stop-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
} else {
Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
}
$okCount++
} catch {
$skipCount++
}
}
if ($null -ne $UltixSync) {
if ($okCount -gt 0) {
$UltixSync.Logs.Enqueue("    [OK] Updated $okCount task(s) in $($taskRule.TaskPath)")
} elseif ($skipCount -gt 0) {
$UltixSync.Logs.Enqueue("    [*] Skipped $skipCount OS-protected task(s) in $($taskRule.TaskPath)")
}
}
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Telemetry tasks lockdown completed ($Operation).`n"
}.GetNewClosure())
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
if (-not (Test-Path -LiteralPath $svcRegPath)) {
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
$shouldAutoStart = ($Op -eq 'Revert' -and $targetValue -eq 2)
Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue $targetValue -StartService:$shouldAutoStart
$svcType = (Get-ItemProperty -LiteralPath $svcRegPath -Name "Type" -ErrorAction SilentlyContinue).Type
$isPerUserTemplate = ($null -ne $svcType -and (([int]$svcType -band 0x40) -ne 0))
if ($isPerUserTemplate) {
$flagVal = if ($Op -eq 'Apply') { 0 } else { 3 }
Set-ItemProperty -LiteralPath $svcRegPath -Name "UserServiceFlags" -Value $flagVal -Type DWord -Force -ErrorAction SilentlyContinue
}
if ($Op -eq 'Apply') {
Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($isPerUserTemplate) {
Get-Service -Name "$($svc.Name)_*" -ErrorAction SilentlyContinue | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
}
}
} catch {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue("    [!] Failed to modify service $($svc.Name): $($_.Exception.Message)")
}
}
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> $ProfileName services enforcement completed ($Operation).`n"
}.GetNewClosure())
}
function Get-SystemServicesTable_Worker {
$criticalServices = "^(?i)(RpcSs|DcomLaunch|RpcEptMapper|LSM|SamSs|PlugPlay|EventLog|BFE|mpssvc|nsi|ProfSvc|gpsvc|CryptSvc|TrustedInstaller|WinDefend|WdNisSvc|MpDefenderCoreService|SecurityHealthService|wscsvc|Dhcp|Dnscache|Winmgmt|Schedule|UserManager|CoreMessagingRegistrar|SystemEventsBroker|Power|BrokerInfrastructure|Appinfo|StateRepository|TextInputManagementService|TimeBrokerSvc|ClipSVC|AppIDSvc|KeyIso|VaultSvc|Netlogon|LanmanWorkstation|LanmanServer|Wcmsvc|NlaSvc|AudioSrv|AudioEndpointBuilder|MMCSS|FontCache|StorSvc|vds|volmgr|partmgr|mountmgr|stornvme|storahci|Ntfs|FltMgr|Tcpip|AFD)$"
$svcRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services", $false)
$rawServices = @(Get-Service -ErrorAction SilentlyContinue)
$total = [math]::Max(1, $rawServices.Count)
$idx = 0
$svcs = [System.Collections.Generic.List[PSCustomObject]]::new($total)
try {
foreach ($s in $rawServices) {
$idx++
if ($null -ne $UltixSync -and ($idx % 40 -eq 0 -or $idx -eq $total)) {
$UltixSync.Progress = [int](($idx / $total) * 100)
}
$sName  = $s.Name
$isCrit = ($sName -match $criticalServices)
$startCode = $null
$delayed   = 0
if ($null -ne $svcRoot) {
$sKey = $svcRoot.OpenSubKey($sName, $false)
if ($null -eq $sKey -and $sName -match '^(.+)_[0-9a-fA-F]{2,}$') {
$sKey = $svcRoot.OpenSubKey($matches[1], $false)
}
if ($null -ne $sKey) {
try {
$startCode = $sKey.GetValue("Start", $null)
$delayed   = $sKey.GetValue("DelayedAutostart", 0)
} finally {
$sKey.Dispose()
}
}
}
$startLabel = switch ($startCode) {
0 { "Boot" }
1 { "System" }
2 { if ($delayed -eq 1) { "Automatic (Delayed)" } else { "Automatic" } }
3 { "Manual" }
4 { "Disabled" }
default { [string]$s.StartType }
}
if ($startCode -in @(0, 1)) { $isCrit = $true }
$startDisp = if ($isCrit) { "$startLabel [CRITICAL - LOCKED]" } else { $startLabel }
$svcs.Add([PSCustomObject]@{
Name        = $sName
DisplayName = $s.DisplayName
Status      = [string]$s.Status
StartType   = $startDisp
RawStart    = if ($null -ne $startCode) { [int]$startCode } else { 3 }
IsLocked    = $isCrit
})
}
} finally {
if ($null -ne $svcRoot) { $svcRoot.Dispose() }
}
return @($svcs | Sort-Object Status, Name)
}
function Show-ServicesGrid {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI " -> Generating complete system services table (Background Thread)..."
Update-Progress 20
$sb = (Get-Command -Name Get-SystemServicesTable_Worker).ScriptBlock
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
param($output)
Update-Progress 0
[array]$initialSvcs = @($output | Where-Object { $null -ne $_ })
$modal = New-Object System.Windows.Forms.Form
$modal.Text = "WinUltix - System Services Manager"
$modal.Size = New-Object System.Drawing.Size(980, 700)
$modal.MinimumSize = New-Object System.Drawing.Size(960, 580)
$modal.StartPosition = "CenterParent"
$modal.FormBorderStyle = "Sizable"
$modal.BackColor = [System.Drawing.Color]::FromArgb(255, 26, 27, 30)
$modal.ForeColor = [System.Drawing.Color]::White
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = "Full live control over Windows Services. 'Start' automatically unlocks Disabled (Start=4) services to Manual before starting. Critical OS services (Red) are locked."
$lblDesc.Location = New-Object System.Drawing.Point(15, 12)
$lblDesc.Size = New-Object System.Drawing.Size(935, 32)
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9.8)
$lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(255, 215, 220, 228)
$lblDesc.Anchor = 'Top, Left, Right'
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Filter:"
$lblSearch.Location = New-Object System.Drawing.Point(15, 52)
$lblSearch.Size = New-Object System.Drawing.Size(48, 22)
$lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblSearch.ForeColor = [System.Drawing.Color]::LightSkyBlue
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(65, 50)
$txtSearch.Size = New-Object System.Drawing.Size(270, 25)
$txtSearch.BackColor = [System.Drawing.Color]::FromArgb(255, 38, 40, 45)
$txtSearch.ForeColor = [System.Drawing.Color]::White
$txtSearch.BorderStyle = "FixedSingle"
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnSelVis = New-Object System.Windows.Forms.Button
$btnSelVis.Text = "Select Visible"
$btnSelVis.Location = New-Object System.Drawing.Point(345, 49)
$btnSelVis.Size = New-Object System.Drawing.Size(110, 26)
$btnSelVis.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
$btnSelVis.FlatStyle = "Flat"
$btnSelVis.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSelNone = New-Object System.Windows.Forms.Button
$btnSelNone.Text = "Deselect All"
$btnSelNone.Location = New-Object System.Drawing.Point(462, 49)
$btnSelNone.Size = New-Object System.Drawing.Size(110, 26)
$btnSelNone.BackColor = [System.Drawing.Color]::FromArgb(255, 50, 53, 58)
$btnSelNone.FlatStyle = "Flat"
$btnSelNone.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh Table"
$btnRefresh.Location = New-Object System.Drawing.Point(579, 49)
$btnRefresh.Size = New-Object System.Drawing.Size(110, 26)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Location = New-Object System.Drawing.Point(695, 52)
$lblCount.Size = New-Object System.Drawing.Size(255, 20)
$lblCount.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
$lblCount.ForeColor = [System.Drawing.Color]::LightGray
$lblCount.TextAlign = "MiddleRight"
$lblCount.Anchor = 'Top, Right'
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, 84)
$listView.Size = New-Object System.Drawing.Size(935, 504)
$listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
$listView.BorderStyle = "FixedSingle"
$listView.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$listView.View = [System.Windows.Forms.View]::Details
$listView.CheckBoxes = $true
$listView.FullRowSelect = $true
$listView.GridLines = $false
$listView.Anchor = 'Top, Bottom, Left, Right'
Enable-UltixDoubleBuffer -Control $listView
$sorter = New-Object WinUltix.ListViewColumnSorter
$listView.ListViewItemSorter = $sorter
[void]$listView.Columns.Add("Service Name", 200)
[void]$listView.Columns.Add("Status", 95)
[void]$listView.Columns.Add("Start Type", 185)
[void]$listView.Columns.Add("Display Name", 425)
$bgEven    = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$bgOdd     = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
$bgLocked  = [System.Drawing.Color]::FromArgb(255, 54, 26, 28)
$fgRunning = [System.Drawing.Color]::FromArgb(255, 155, 235, 175)
$fgLocked  = [System.Drawing.Color]::FromArgb(255, 255, 155, 155)
$fgStopped = [System.Drawing.Color]::FromArgb(255, 170, 188, 208)
$fgMuted   = [System.Drawing.Color]::FromArgb(255, 125, 134, 145)
$state = @{
AllServices    = $initialSvcs
ServiceMap     = @{}
CheckedNames   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
SuppressEvents = $false
}
$rebuildMap = {
$state.ServiceMap.Clear()
foreach ($s in $state.AllServices) {
$state.ServiceMap[$s.Name] = $s
}
}
& $rebuildMap
$updateCounter = {
$lblCount.Text = "Selected: $($state.CheckedNames.Count) / $($state.AllServices.Count) (Shown: $($listView.Items.Count))"
}
$styleRow = {
param([System.Windows.Forms.ListViewItem]$It, [int]$RowIdx)
$obj = $state.ServiceMap[[string]$It.Tag]
if ($null -eq $obj) { return }
if ($obj.IsLocked) {
$It.BackColor = $bgLocked
$It.ForeColor = $fgLocked
} else {
$It.BackColor = if (($RowIdx % 2) -eq 0) { $bgEven } else { $bgOdd }
if ($obj.StartType -match "^Disabled") {
$It.ForeColor = $fgMuted
} elseif ($obj.Status -eq "Running") {
$It.ForeColor = $fgRunning
} else {
$It.ForeColor = $fgStopped
}
}
}
$applyRowShading = {
for ($r = 0; $r -lt $listView.Items.Count; $r++) {
& $styleRow $listView.Items[$r] $r
}
}
$populateList = {
param([string]$FilterText = "")
$state.SuppressEvents = $true
$listView.BeginUpdate()
$listView.ListViewItemSorter = $null
$listView.Items.Clear()
$cleanFilter = $FilterText.Trim()
$visIdx = 0
foreach ($obj in $state.AllServices) {
if ($cleanFilter.Length -gt 0) {
$matched = (
$obj.Name.IndexOf($cleanFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
$obj.DisplayName.IndexOf($cleanFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
$obj.Status.IndexOf($cleanFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
$obj.StartType.IndexOf($cleanFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
)
if (-not $matched) { continue }
}
$lvItem = New-Object System.Windows.Forms.ListViewItem([string]$obj.Name)
[void]$lvItem.SubItems.Add([string]$obj.Status)
[void]$lvItem.SubItems.Add([string]$obj.StartType)
[void]$lvItem.SubItems.Add([string]$obj.DisplayName)
$lvItem.Tag = $obj.Name
$lvItem.Checked = (-not $obj.IsLocked) -and $state.CheckedNames.Contains($obj.Name)
& $styleRow $lvItem $visIdx
[void]$listView.Items.Add($lvItem)
$visIdx++
}
$listView.ListViewItemSorter = $sorter
if ($sorter.OrderOfSort -ne [System.Windows.Forms.SortOrder]::None) {
$listView.Sort()
& $applyRowShading
}
$listView.EndUpdate()
$state.SuppressEvents = $false
& $updateCounter
}
$listView.Add_ItemCheck({
param($src, $e)
if ($state.SuppressEvents) { return }
$lvItem = $src.Items[$e.Index]
if ($null -ne $lvItem -and $null -ne $lvItem.Tag) {
$obj = $state.ServiceMap[[string]$lvItem.Tag]
if ($null -ne $obj -and $obj.IsLocked) {
$e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
}
}
}.GetNewClosure())
$listView.Add_ItemChecked({
param($src, $e)
if ($state.SuppressEvents) { return }
$sName = [string]$e.Item.Tag
$obj   = $state.ServiceMap[$sName]
if ($null -ne $obj -and $obj.IsLocked) {
if ($e.Item.Checked) {
$state.SuppressEvents = $true
$e.Item.Checked = $false
$state.SuppressEvents = $false
}
[void]$state.CheckedNames.Remove($sName)
return
}
if ($e.Item.Checked) {
[void]$state.CheckedNames.Add($sName)
} else {
[void]$state.CheckedNames.Remove($sName)
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
$txtSearch.Add_TextChanged({ & $populateList $txtSearch.Text }.GetNewClosure())
$btnSelVis.Add_Click({
$state.SuppressEvents = $true
$listView.BeginUpdate()
foreach ($lvItem in $listView.Items) {
$sName = [string]$lvItem.Tag
$obj   = $state.ServiceMap[$sName]
if ($null -ne $obj -and $obj.IsLocked) {
$lvItem.Checked = $false
continue
}
$lvItem.Checked = $true
[void]$state.CheckedNames.Add($sName)
}
$listView.EndUpdate()
$state.SuppressEvents = $false
& $updateCounter
}.GetNewClosure())
$btnSelNone.Add_Click({
$state.SuppressEvents = $true
$state.CheckedNames.Clear()
$listView.BeginUpdate()
foreach ($lvItem in $listView.Items) { $lvItem.Checked = $false }
$listView.EndUpdate()
$state.SuppressEvents = $false
& $updateCounter
}.GetNewClosure())
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start"
$btnStart.Location = New-Object System.Drawing.Point(15, 602)
$btnStart.Size = New-Object System.Drawing.Size(140, 38)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 95, 60)
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = "Flat"
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStart.Anchor = 'Bottom, Left'
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Location = New-Object System.Drawing.Point(163, 602)
$btnStop.Size = New-Object System.Drawing.Size(140, 38)
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(255, 140, 85, 40)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = "Flat"
$btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStop.Anchor = 'Bottom, Left'
$btnSetAuto = New-Object System.Windows.Forms.Button
$btnSetAuto.Text = "Set Automatic"
$btnSetAuto.Location = New-Object System.Drawing.Point(311, 602)
$btnSetAuto.Size = New-Object System.Drawing.Size(155, 38)
$btnSetAuto.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnSetAuto.ForeColor = [System.Drawing.Color]::White
$btnSetAuto.FlatStyle = "Flat"
$btnSetAuto.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnSetAuto.Anchor = 'Bottom, Left'
$btnSetManual = New-Object System.Windows.Forms.Button
$btnSetManual.Text = "Set Manual"
$btnSetManual.Location = New-Object System.Drawing.Point(474, 602)
$btnSetManual.Size = New-Object System.Drawing.Size(155, 38)
$btnSetManual.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnSetManual.ForeColor = [System.Drawing.Color]::White
$btnSetManual.FlatStyle = "Flat"
$btnSetManual.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnSetManual.Anchor = 'Bottom, Left'
$btnSetDisabled = New-Object System.Windows.Forms.Button
$btnSetDisabled.Text = "Set Disabled"
$btnSetDisabled.Location = New-Object System.Drawing.Point(637, 602)
$btnSetDisabled.Size = New-Object System.Drawing.Size(155, 38)
$btnSetDisabled.BackColor = [System.Drawing.Color]::FromArgb(255, 135, 50, 50)
$btnSetDisabled.ForeColor = [System.Drawing.Color]::White
$btnSetDisabled.FlatStyle = "Flat"
$btnSetDisabled.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnSetDisabled.Anchor = 'Bottom, Left'
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(800, 602)
$btnClose.Size = New-Object System.Drawing.Size(150, 38)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.FlatStyle = "Flat"
$btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$btnClose.Anchor = 'Bottom, Right'
$modalButtons = [System.Windows.Forms.Control[]]@($btnStart, $btnStop, $btnSetAuto, $btnSetManual, $btnSetDisabled, $btnSelVis, $btnSelNone, $btnRefresh)
$refreshLiveTable = {
$workerSb = (Get-Command -Name Get-SystemServicesTable_Worker).ScriptBlock
Invoke-AsyncTask -ControlsToDisable $modalButtons -ScriptBlock $workerSb -OnComplete ({
param($freshOut)
Update-Progress 0
if ($modal.IsDisposed -or $listView.IsDisposed) { return }
$state.AllServices = @($freshOut | Where-Object { $null -ne $_ })
& $rebuildMap
& $populateList $txtSearch.Text
}.GetNewClosure())
}
$btnRefresh.Add_Click({ & $refreshLiveTable }.GetNewClosure())
$invokeServiceAction = {
param([ValidateSet("Start", "Stop", "Auto", "Manual", "Disabled")][string]$Mode)
if ($state.CheckedNames.Count -eq 0) {
[System.Windows.Forms.MessageBox]::Show("Check at least one service in the table first.", "WinUltix - System Services Manager") | Out-Null
return
}
$selectedItems = [System.Collections.Generic.List[object]]::new()
foreach ($sName in $state.CheckedNames) {
if ($state.ServiceMap.ContainsKey($sName)) {
$obj = $state.ServiceMap[$sName]
if (-not $obj.IsLocked) { $selectedItems.Add($obj) }
}
}
if ($selectedItems.Count -eq 0) { return }
Invoke-AsyncTask -ControlsToDisable $modalButtons -Arguments @(@($selectedItems), $Mode) -ScriptBlock {
param([array]$Selected, [string]$OpMode)
$total   = $Selected.Count
$current = 0
foreach ($svc in $Selected) {
$current++
$UltixSync.Progress = [int](($current / $total) * 100)
if ($svc.IsLocked) { continue }
$sName       = $svc.Name
$baseSvcName = if ($sName -match '^(.+)_[0-9a-fA-F]{2,}$') { $matches[1] } else { $sName }
$svcRegPath  = "HKLM:\SYSTEM\CurrentControlSet\Services\$sName"
$baseRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$baseSvcName"
try {
switch ($OpMode) {
"Start" {
$curStart  = (Get-ItemProperty -LiteralPath $svcRegPath -Name "Start" -ErrorAction SilentlyContinue).Start
$baseStart = (Get-ItemProperty -LiteralPath $baseRegPath -Name "Start" -ErrorAction SilentlyContinue).Start
if ($curStart -eq 4 -or $baseStart -eq 4) {
$UltixSync.Logs.Enqueue(" -> Auto-unlocking Disabled service '$sName' to Manual (Start=3) & Starting...")
Set-ProtectedServiceStart -ServiceName $sName -StartValue 3 -StartService
if ($baseSvcName -ne $sName -and (Test-Path -LiteralPath $baseRegPath)) {
Set-ProtectedServiceStart -ServiceName $baseSvcName -StartValue 3 -StartService
}
$svcType = (Get-ItemProperty -LiteralPath $baseRegPath -Name "Type" -ErrorAction SilentlyContinue).Type
if ($null -ne $svcType -and (([int]$svcType -band 0x40) -ne 0)) {
Set-ItemProperty -LiteralPath $baseRegPath -Name "UserServiceFlags" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
}
} else {
$UltixSync.Logs.Enqueue(" -> Starting service: $sName ($($svc.DisplayName))")
if ($null -ne ([WinUltix.PrivilegeEnabler].GetMethod("SetServiceConfigLive"))) {
[void][WinUltix.PrivilegeEnabler]::SetServiceConfigLive($sName, -1, $true)
}
}
Start-Service -Name $sName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
$curStatus = (Get-Service -Name $sName -ErrorAction SilentlyContinue).Status
$UltixSync.Logs.Enqueue("    [OK] ${sName} -> Status: $curStatus.")
}
"Stop" {
$UltixSync.Logs.Enqueue(" -> Stopping service: $sName ($($svc.DisplayName))")
Stop-Service -Name $sName -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($baseSvcName -ne $sName) {
Get-Service -Name "${baseSvcName}_*" -ErrorAction SilentlyContinue | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
}
$afterStop = (Get-Service -Name $sName -ErrorAction SilentlyContinue).Status
if ($afterStop -eq 'Running' -and $null -ne ([WinUltix.PrivilegeEnabler].GetMethod("StopServiceLive"))) {
[void][WinUltix.PrivilegeEnabler]::StopServiceLive($sName)
Start-Sleep -Milliseconds 250
$afterStop = (Get-Service -Name $sName -ErrorAction SilentlyContinue).Status
}
$UltixSync.Logs.Enqueue("    [OK] ${sName} -> Status: $afterStop.")
}
default {
$targetStart = switch ($OpMode) {
"Auto"     { 2 }
"Manual"   { 3 }
"Disabled" { 4 }
}
$flagVal   = if ($targetStart -eq 4) { 0 } else { 3 }
$modeLabel = if ($targetStart -eq 2) { "Automatic (2)" } elseif ($targetStart -eq 3) { "Manual (3)" } else { "Disabled (4)" }
$UltixSync.Logs.Enqueue(" -> Setting StartType [$modeLabel]: $sName ($($svc.DisplayName))")
Set-ProtectedServiceStart -ServiceName $sName -StartValue $targetStart
if (Test-Path -LiteralPath $baseRegPath) {
if ($baseSvcName -ne $sName) {
Set-ProtectedServiceStart -ServiceName $baseSvcName -StartValue $targetStart
}
$svcType = (Get-ItemProperty -LiteralPath $baseRegPath -Name "Type" -ErrorAction SilentlyContinue).Type
if ($null -ne $svcType -and (([int]$svcType -band 0x40) -ne 0)) {
Set-ItemProperty -LiteralPath $baseRegPath -Name "UserServiceFlags" -Value $flagVal -Type DWord -Force -ErrorAction SilentlyContinue
}
if ($targetStart -in @(3, 4)) {
Remove-ItemProperty -LiteralPath $baseRegPath -Name "DelayedAutostart" -Force -ErrorAction SilentlyContinue
}
}
if ($targetStart -eq 4) {
Stop-Service -Name $sName -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
Get-Service -Name "${baseSvcName}_*" -ErrorAction SilentlyContinue | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ((Get-Service -Name $sName -ErrorAction SilentlyContinue).Status -eq 'Running' -and $null -ne ([WinUltix.PrivilegeEnabler].GetMethod("StopServiceLive"))) {
[void][WinUltix.PrivilegeEnabler]::StopServiceLive($sName)
}
$UltixSync.Logs.Enqueue("    [OK] $sName locked to Disabled (Start=4) and stopped.")
} else {
$UltixSync.Logs.Enqueue("    [OK] $sName StartType updated to $modeLabel in Registry & live SCM.")
}
}
}
} catch {
$UltixSync.Logs.Enqueue("    [!] Failed on ${sName}: $($_.Exception.Message)")
}
}
} -OnComplete ({
param($nullOut)
& $refreshLiveTable
}.GetNewClosure())
}
$btnStart.Add_Click({ & $invokeServiceAction "Start" }.GetNewClosure())
$btnStop.Add_Click({ & $invokeServiceAction "Stop" }.GetNewClosure())
$btnSetAuto.Add_Click({ & $invokeServiceAction "Auto" }.GetNewClosure())
$btnSetManual.Add_Click({ & $invokeServiceAction "Manual" }.GetNewClosure())
$btnSetDisabled.Add_Click({ & $invokeServiceAction "Disabled" }.GetNewClosure())
& $populateList ""
$modal.Controls.AddRange(@(
$lblDesc, $lblSearch, $txtSearch, $btnSelVis, $btnSelNone, $btnRefresh, $lblCount,
$listView, $btnStart, $btnStop, $btnSetAuto, $btnSetManual, $btnSetDisabled, $btnClose
))
$modal.CancelButton = $btnClose
try {
[void]$modal.ShowDialog($global:form)
} finally {
$modal.Dispose()
}
}.GetNewClosure())
}
function Get-StartupState_Worker {
$startupItems  = [System.Collections.Generic.List[PSCustomObject]]::new()
$approvedCache = @{}
function Resolve-StartupApprovedState {
param([string]$ApprovedRegPath, [string]$EntryName)
if ([string]::IsNullOrWhiteSpace($ApprovedRegPath)) { return "Enabled" }
if (-not $approvedCache.ContainsKey($ApprovedRegPath)) {
$valMap = @{}
if (Test-Path -LiteralPath $ApprovedRegPath) {
$key = Get-Item -LiteralPath $ApprovedRegPath -ErrorAction SilentlyContinue
if ($null -ne $key) {
try {
foreach ($vName in $key.Property) {
$valMap[$vName] = $key.GetValue($vName, $null)
}
} finally {
$key.Dispose()
}
}
}
$approvedCache[$ApprovedRegPath] = $valMap
}
$cachedMap = $approvedCache[$ApprovedRegPath]
if (-not $cachedMap.ContainsKey($EntryName)) { return "Enabled" }
[byte[]]$bin = $cachedMap[$EntryName]
if ($null -eq $bin -or $bin.Length -lt 1) { return "Enabled" }
$header = [int]$bin[0]
if ($header -eq 2 -or $header -eq 6) {
return "Enabled"
} else {
if ($bin.Length -ge 12) {
try {
$ft = [BitConverter]::ToInt64($bin, 4)
if ($ft -gt 0) {
$dt = [DateTime]::FromFileTimeUtc($ft).ToLocalTime().ToString("yyyy-MM-dd")
return "Disabled ($dt)"
}
} catch { }
}
return "Disabled (TaskMgr)"
}
}
$regTargets = [System.Collections.Generic.List[hashtable]]::new()
$regTargets.Add(@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKLM Run (x64)" })
$regTargets.Add(@{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";       Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"; Label = "HKLM Run (x86)" })
$regTargets.Add(@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKLM RunOnce (x64)" })
$regTargets.Add(@{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce";   Approved = "";                                                                               Label = "HKLM RunOnce (x86)" })
$regTargets.Add(@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKLM)" })
$folderTargets = [System.Collections.Generic.List[hashtable]]::new()
$folderTargets.Add(@{ Path = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (All Users)" })
$userProfiles = @(Get-UltixUserProfiles)
$loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })
if ($loadedHives.Count -gt 0) {
foreach ($prof in $loadedHives) {
$uName = $prof.UserName
$hRoot = $prof.HiveRoot
$regTargets.Add(@{ Path = "$hRoot\Software\Microsoft\Windows\CurrentVersion\Run";                   Approved = "$hRoot\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKU Run ($uName)" })
$regTargets.Add(@{ Path = "$hRoot\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";       Approved = "$hRoot\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"; Label = "HKU Run x86 ($uName)" })
$regTargets.Add(@{ Path = "$hRoot\Software\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                                Label = "HKU RunOnce ($uName)" })
$regTargets.Add(@{ Path = "$hRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                                Label = "GPO Run ($uName)" })
if (-not [string]::IsNullOrWhiteSpace($prof.LocalPath)) {
$uStartupDir = Join-Path -Path $prof.LocalPath -ChildPath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
$folderTargets.Add(@{ Path = $uStartupDir; Approved = "$hRoot\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder ($uName)" })
}
}
} else {
$regTargets.Add(@{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKCU Run" })
$regTargets.Add(@{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKCU RunOnce" })
$regTargets.Add(@{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKCU)" })
$folderTargets.Add(@{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";         Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (Current User)" })
}
foreach ($reg in $regTargets) {
if (Test-Path -LiteralPath $reg.Path) {
$keyObj = Get-Item -LiteralPath $reg.Path -ErrorAction SilentlyContinue
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
foreach ($fld in $folderTargets) {
if (Test-Path -LiteralPath $fld.Path) {
Get-ChildItem -LiteralPath $fld.Path -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
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
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return @($startupItems | Sort-Object Location, Name)
}
function Show-StartupGrid {
param([System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI " -> Auditing Run, RunOnce, GPO Run, Startup Folders, and StartupApproved binary states..."
Update-Progress 20
$sb = (Get-Command -Name Get-StartupState_Worker).ScriptBlock
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
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
-Description "Inspect Run, RunOnce, GPO, and StartupApproved states across all loaded profiles. Permanently delete entries or toggle their TaskMgr state." `
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
$UltixSync.Logs.Enqueue(" -> Deleting startup entry: $($item.Name) [$($item.Location)]")
try {
if ($item.Type -eq "Registry") {
Remove-ItemProperty -LiteralPath $item.RegPath -Name $item.Name -Force -ErrorAction Stop
} else {
Remove-Item -LiteralPath $item.Command -Force -ErrorAction Stop
}
if (-not [string]::IsNullOrWhiteSpace($item.ApprovedPath) -and (Test-Path -LiteralPath $item.ApprovedPath)) {
Remove-ItemProperty -LiteralPath $item.ApprovedPath -Name $item.Name -Force -ErrorAction SilentlyContinue
}
$UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
} catch {
$UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
}
} else {
if ([string]::IsNullOrWhiteSpace($item.ApprovedPath)) {
$UltixSync.Logs.Enqueue("    [!] $($item.Name) [$($item.Location)] does not support TaskMgr StartupApproved toggling.")
continue
}
try {
if (-not (Test-Path -LiteralPath $item.ApprovedPath)) {
New-Item -Path $item.ApprovedPath -Force | Out-Null
}
if ($item.State -match "^Disabled") {
[byte[]]$enableBytes = @(0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
Set-ItemProperty -LiteralPath $item.ApprovedPath -Name $item.Name -Value $enableBytes -Type Binary -Force -ErrorAction Stop
$UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.Name) [$($item.Location)]")
} else {
[byte[]]$headerBytes  = @(0x03, 0x00, 0x00, 0x00)
[byte[]]$timeBytes    = [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())
[byte[]]$disableBytes = $headerBytes + $timeBytes
Set-ItemProperty -LiteralPath $item.ApprovedPath -Name $item.Name -Value $disableBytes -Type Binary -Force -ErrorAction Stop
$UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.Name) [$($item.Location)]")
}
} catch {
$UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
}
}
}
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Startup configuration updated.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Get-ScheduledTasks_Worker {
$taskItems = [System.Collections.Generic.List[PSCustomObject]]::new()
$readyDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($drv in ([System.IO.DriveInfo]::GetDrives())) {
if ($drv.IsReady) { [void]$readyDrives.Add($drv.Name.Substring(0, 1)) }
}
$searchDirs = [System.Collections.Generic.List[string]]::new()
foreach ($baseDir in @(
"$env:windir\System32",
$env:windir,
"$env:windir\SysWOW64",
"$env:windir\System32\wbem",
"$env:windir\System32\WindowsPowerShell\v1.0",
"$env:windir\System32\OpenSSH"
)) {
if (-not [string]::IsNullOrWhiteSpace($baseDir) -and [System.IO.Directory]::Exists($baseDir)) {
$searchDirs.Add($baseDir)
}
}
if (-not [string]::IsNullOrWhiteSpace($env:PATH)) {
foreach ($pDir in ($env:PATH -split ';')) {
$trimmed = $pDir.Trim().Trim('"')
if (-not [string]::IsNullOrWhiteSpace($trimmed) -and [System.IO.Directory]::Exists($trimmed) -and -not $searchDirs.Contains($trimmed)) {
$searchDirs.Add($trimmed)
}
}
}
function Test-TaskExecutableExists {
param(
[string]$RawExecute,
[string]$WorkingDirectory = ""
)
if ([string]::IsNullOrWhiteSpace($RawExecute)) { return $true }
$clean = [System.Environment]::ExpandEnvironmentVariables($RawExecute.Trim()).Trim()
if ($clean -match '^"([^"]+)"') {
$clean = $matches[1].Trim()
} elseif ($clean -match '(?i)^(.+?\.(?:exe|bat|cmd|vbs|ps1|msc|com|scr|hta|js|wsf))(?:$|\s)') {
$clean = $matches[1].Trim()
} else {
$clean = ($clean.Trim('"') -split '\s+')[0]
}
if ([string]::IsNullOrWhiteSpace($clean) -or $clean -match '^\$\(' -or $clean -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
return $true
}
$clean = $clean -replace '(?i)^\\?SystemRoot\\', "$env:windir\"
$clean = $clean -replace '(?i)^\\?System32\\', "$env:windir\System32\"
$clean = $clean -replace '(?i)^\\?SysWOW64\\', "$env:windir\SysWOW64\"
if ([System.IO.Path]::IsPathRooted($clean)) {
if ($clean -match '^([a-zA-Z]):\\' -and -not $readyDrives.Contains($matches[1])) {
return $true
}
if ([System.IO.File]::Exists($clean)) { return $true }
if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($clean)) -and [System.IO.File]::Exists("$clean.exe")) {
return $true
}
return $false
} else {
if ($clean -match '^(?i)(cmd|powershell|pwsh|wscript|cscript|mshta|rundll32|regsvr32|conhost|explorer)$') {
return $true
}
$candidates = if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($clean))) {
@("$clean.exe", "$clean.cmd", "$clean.bat", "$clean.com", $clean)
} else {
@($clean)
}
if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
$expWorkDir = [System.Environment]::ExpandEnvironmentVariables($WorkingDirectory.Trim().Trim('"')).Trim()
if ([System.IO.Directory]::Exists($expWorkDir)) {
foreach ($cand in $candidates) {
if ([System.IO.File]::Exists((Join-Path $expWorkDir $cand))) { return $true }
}
}
}
foreach ($dir in $searchDirs) {
foreach ($cand in $candidates) {
if ([System.IO.File]::Exists((Join-Path $dir $cand))) { return $true }
}
}
return $false
}
}
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
$protectedTaskNames = "^(?i)(WinUltix_CPPC_Failsafe|MpIdleTask|Windows Defender.*|BitLocker.*|PcaPatchDbTask|SdbinstMergeDbTask)$"
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
$isCoreWindowsFolder = ($tPath -like "\Microsoft\Windows\*")
$isTelemetryFolder   = ($tPath -match $msTelemetryPaths -or $tPath -like "\Microsoft\XblGameSave\*")
if ($isCoreWindowsFolder -and -not $isTelemetryFolder) { continue }
if (-not (Test-UltixTaskAdminWritable -TaskPath $tPath -TaskName $tName)) { continue }
$execAction = $task.Actions | Where-Object { $null -ne $_.Execute -and $_.Execute -ne "" } | Select-Object -First 1
$cmdLine = ""
$isGhost = $false
if ($null -ne $execAction) {
$rawExe  = [string]$execAction.Execute
$rawArgs = [string]$execAction.Arguments
$workDir = [string]$execAction.WorkingDirectory
$cmdLine = "$rawExe $rawArgs".Trim()
if (-not (Test-TaskExecutableExists -RawExecute $rawExe -WorkingDirectory $workDir)) {
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
$category = ""
if ($isGhost) {
$category = "[GHOST / Missing Exe]"
} elseif (-not $isCoreWindowsFolder) {
if ($tPath -like "\Microsoft\*") {
$category = "[MS App / Updater]"
} else {
$category = "[3rd-Party / Root]"
}
} elseif ($isTelemetryFolder) {
$category = "[MS Telemetry / Bloat]"
} else {
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
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
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
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> Scheduled Tasks operations completed.`n"
}.GetNewClosure())
}.GetNewClosure())
}
function Initialize-Z4UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tabServices = New-Object System.Windows.Forms.TabPage
$tabServices.Text = "Services"
$tabServices.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$rowSvcLight = New-UltixActionRow -Parent $tabServices -Y 20 -MainRGB @(45, 85, 125) `
-Text "Background Services: OFFICE PROFILE" `
-Description "OFFICE PROFILE (Light): Symmetrically disables 12 telemetry and diagnostics services while keeping Printing, Windows Search, and LAN sharing 100% intact." `
-AuditDescription "AUDIT: Verifies 12 standard telemetry and background bloat services." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ModalTitle "WinUltix - Office Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Office Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Disable"
}.GetNewClosure())
$rowSvcHeavy = New-UltixActionRow -Parent $tabServices -Y 70 -MainRGB @(135, 50, 50) `
-Text "Background Services: GAMING PROFILE" `
-Description "GAMING PROFILE (Heavy): Symmetrically disables up to 60 background services (SysMain, WSearch, Spooler, DPS/SRUM disk logging, Per-User Sync templates, GameInputSvc, Xbox)." `
-AuditDescription "AUDIT: Verifies 60 heavy background services including indexer, SRUM, Per-User templates, and print spooler." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ModalTitle "WinUltix - Gaming Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Gaming Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Configure"
}.GetNewClosure())
$rowTelemetry = New-UltixActionRow -Parent $tabServices -Y 120 -MainRGB @(55, 58, 64) `
-Text "Disable Telemetry Tasks (Scheduler)" `
-Description "Disables 8 core Microsoft telemetry task branches in Task Scheduler: CEIP, CompatTelRunner/Appraiser, Autochk, DiskDiagnostic, Feedback, PerformanceTrace, WER, and XblGameSave." `
-AuditDescription "AUDIT: Verifies if Microsoft telemetry scheduled tasks are active in Task Scheduler." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ModalTitle "WinUltix - Scheduled Tasks Lockdown" -ModalDescription "Select tasks to modify (Apply = Disable, Revert = Enable)." -ExecutorFunction "Invoke-ApplyTasks" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Active"
}.GetNewClosure())
$lblManagers = New-Object System.Windows.Forms.Label
$lblManagers.Text = "Interactive Service, Task & Startup Inspectors"
$lblManagers.Location = New-Object System.Drawing.Point(15, 172)
$lblManagers.Size = New-Object System.Drawing.Size(370, 18)
$lblManagers.ForeColor = [System.Drawing.Color]::DarkGray
$lblManagers.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblWarnMgr = New-Object System.Windows.Forms.Label
$lblWarnMgr.Text = "[!] MANUAL INSPECTORS ONLY -- DO NOT SELECT ALL!`r`nUse to inspect remaining services/tasks after running profiles."
$lblWarnMgr.Location = New-Object System.Drawing.Point(15, 193)
$lblWarnMgr.Size = New-Object System.Drawing.Size(370, 40)
$lblWarnMgr.BackColor = [System.Drawing.Color]::FromArgb(255, 58, 35, 20)
$lblWarnMgr.ForeColor = [System.Drawing.Color]::Gold
$lblWarnMgr.BorderStyle = "FixedSingle"
$lblWarnMgr.TextAlign = "MiddleCenter"
$lblWarnMgr.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tabServices.Controls.AddRange(@($lblManagers, $lblWarnMgr))
$btnSvcGrid = New-UltixButton -Parent $tabServices -X 15 -Y 242 -Width 370 -Height 40 -RGB @(45, 85, 125) `
-Text "System Services Manager (Interactive Grid)" `
-Description "MANUAL INSPECTOR: Sortable dark Services Manager with instant live search. Inspect remaining services (Critical OS services are locked in Red)." `
-OnClick ({ Show-ServicesGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnTasksGrid = New-UltixButton -Parent $tabServices -X 15 -Y 292 -Width 370 -Height 40 -RGB @(45, 85, 125) `
-Text "Scheduled Tasks Inspector (3rd-Party / Ghosts)" `
-Description "MANUAL INSPECTOR: Exposes 3rd-party updaters, Microsoft telemetry bloat, and orphaned [GHOST] tasks pointing to missing .exe files." `
-OnClick ({ Show-TasksGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnStartupGrid = New-UltixButton -Parent $tabServices -X 15 -Y 342 -Width 370 -Height 40 -RGB @(45, 85, 125) `
-Text "Deep Startup Manager (Run / StartupApproved)" `
-Description "MANUAL INSPECTOR: Audits Run, RunOnce, GPO Run, and Startup folders across x64/x86 hives, and decodes Task Manager StartupApproved binary states." `
-OnClick ({ Show-StartupGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
foreach ($row in @($rowSvcLight, $rowSvcHeavy, $rowTelemetry)) {
$allTabButtons.AddRange($row.Controls)
}
$allTabButtons.AddRange([System.Windows.Forms.Control[]]@($btnSvcGrid, $btnTasksGrid, $btnStartupGrid))
$TabControl.Controls.Add($tabServices)
}
function Get-UsbSecurityState {
if ($null -ne $UltixSync) { $UltixSync.Progress = 20 }
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$remGuidKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"
$wpVal = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies" -Name "WriteProtect" -ErrorAction SilentlyContinue).WriteProtect
$denyWritePol = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -ErrorAction SilentlyContinue).Deny_Write
$isReadOnlyActive = ($wpVal -eq 1 -and $denyWritePol -eq 1)
$results.Add([PSCustomObject]@{
UIDisplayName = "USB Read-Only Guard: Block Writing to USB Drives & MTP Phones (Prevents Data Leak)"
IsDetected    = (-not $isReadOnlyActive)
ActionData    = @{ Layer = "WriteProtect" }
})
$denyExecPol = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Execute" -ErrorAction SilentlyContinue).Deny_Execute
$results.Add([PSCustomObject]@{
UIDisplayName = "USB Execution Guard: Block Running Executables (.exe) from Removable Drives"
IsDetected    = ($denyExecPol -ne 1)
ActionData    = @{ Layer = "DenyExecute" }
})
$usbstorStart  = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR" -Name "Start" -ErrorAction SilentlyContinue).Start
$uaspstorStart = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor" -Name "Start" -ErrorAction SilentlyContinue).Start
$denyReadPol   = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -ErrorAction SilentlyContinue).Deny_Read
$isHardLocked  = ($usbstorStart -eq 4 -and $uaspstorStart -eq 4 -and $denyReadPol -eq 1)
$results.Add([PSCustomObject]@{
UIDisplayName = "USB Total Blackout: Disable USBSTOR + UASPStor Drivers (Blocks all USB Sticks & SSDs)"
IsDetected    = (-not $isHardLocked)
ActionData    = @{ Layer = "TotalBlock" }
})
$dmaLock = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\FVE" -Name "DisableExternalDMAUnderLock" -ErrorAction SilentlyContinue).DisableExternalDMAUnderLock
$usbLock = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "DisableUsbEnumerationOnLock" -ErrorAction SilentlyContinue).DisableUsbEnumerationOnLock
$isBadUsbLocked = ($dmaLock -eq 1 -and $usbLock -eq 1)
$results.Add([PSCustomObject]@{
UIDisplayName = "Anti-BadUSB & DMA Guard: Block New USB/PCIe Device Enumeration While Screen is Locked"
IsDetected    = (-not $isBadUsbLocked)
ActionData    = @{ Layer = "LockScreenGuard" }
})
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
return @($results)
}
function Invoke-ApplyUsbSecurity {
param(
[Parameter(Mandatory=$true)][array]$SelectedItems,
[ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
[System.Windows.Forms.Control[]]$ControlsToDisable = @()
)
if ($SelectedItems.Count -eq 0) { return }
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
param([array]$Items, [string]$Op)
$remBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
$remGuidKey = "$remBase\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"
$wpdGuids   = @(
"$remBase\{6ac27878-a6fa-4155-ba85-f98f491d4f33}",
"$remBase\{f33fdc04-d1ac-4e8e-9a30-19bbd4b108ae}"
)
$storPolKey = "HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies"
$fveKey     = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
$pwrKey     = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
$verb    = if ($Op -eq 'Apply') { "Enforcing" } else { "Reverting" }
$total   = [math]::Max(1, $Items.Count)
$current = 0
$orderedItems = if ($Op -eq 'Revert') {
@($Items | Sort-Object { if ($_.ActionData.Layer -eq 'WriteProtect') { 0 } else { 1 } })
} else {
$Items
}
foreach ($item in $orderedItems) {
$current++
if ($null -ne $UltixSync) {
$UltixSync.Progress = [int](($current / $total) * 100)
$UltixSync.Logs.Enqueue(" -> $verb USB Security Layer: $($item.UIDisplayName)")
}
$layer = $item.ActionData.Layer
if (-not (Test-Path -LiteralPath $remGuidKey)) { New-Item -Path $remGuidKey -Force | Out-Null }
if (-not (Test-Path -LiteralPath $storPolKey)) { New-Item -Path $storPolKey -Force | Out-Null }
switch ($layer) {
"WriteProtect" {
if ($Op -eq 'Apply') {
Set-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Value 1 -Type DWord -Force
foreach ($wpdKey in $wpdGuids) {
if (-not (Test-Path -LiteralPath $wpdKey)) { New-Item -Path $wpdKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Value 1 -Type DWord -Force
}
} else {
Set-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -Value 0 -Type DWord -Force
$denyReadActive = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -ErrorAction SilentlyContinue).Deny_Read
if ($denyReadActive -ne 1) {
Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
foreach ($wpdKey in $wpdGuids) {
if (Test-Path -LiteralPath $wpdKey) {
Remove-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
}
}
}
}
}
"DenyExecute" {
if ($Op -eq 'Apply') {
Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Execute" -Value 1 -Type DWord -Force
} else {
Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Execute" -Force -ErrorAction SilentlyContinue
}
}
"TotalBlock" {
if ($Op -eq 'Apply') {
Set-ProtectedServiceStart -ServiceName "USBSTOR" -StartValue 4
Set-ProtectedServiceStart -ServiceName "UASPStor" -StartValue 4
Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Value 1 -Type DWord -Force
foreach ($wpdKey in $wpdGuids) {
if (-not (Test-Path -LiteralPath $wpdKey)) { New-Item -Path $wpdKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $wpdKey -Name "Deny_Read" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Value 1 -Type DWord -Force
}
} else {
Set-ProtectedServiceStart -ServiceName "USBSTOR" -StartValue 3
Set-ProtectedServiceStart -ServiceName "UASPStor" -StartValue 3
Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -Force -ErrorAction SilentlyContinue
foreach ($wpdKey in $wpdGuids) {
if (Test-Path -LiteralPath $wpdKey) {
Remove-ItemProperty -LiteralPath $wpdKey -Name "Deny_Read" -Force -ErrorAction SilentlyContinue
}
}
$wpActive = (Get-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -ErrorAction SilentlyContinue).WriteProtect
if ($null -eq $wpActive -or $wpActive -eq 0) {
Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
foreach ($wpdKey in $wpdGuids) {
if (Test-Path -LiteralPath $wpdKey) {
Remove-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
}
}
}
}
}
"LockScreenGuard" {
if (-not (Test-Path -LiteralPath $fveKey)) { New-Item -Path $fveKey -Force | Out-Null }
if ($Op -eq 'Apply') {
Set-ItemProperty -LiteralPath $fveKey -Name "DisableExternalDMAUnderLock" -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $pwrKey -Name "DisableUsbEnumerationOnLock" -Value 1 -Type DWord -Force
} else {
Remove-ItemProperty -LiteralPath $fveKey -Name "DisableExternalDMAUnderLock" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -LiteralPath $pwrKey -Name "DisableUsbEnumerationOnLock" -Force -ErrorAction SilentlyContinue
}
}
}
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
} -OnComplete ({
param($nullOut)
Update-Progress 0
Write-GUI " -> USB Perimeter Security configuration completed ($Operation).`n"
}.GetNewClosure())
}
function Set-CustomDNS {
param(
[Parameter(Mandatory=$true)][string]$Provider,
[bool]$EnableDoH = $true,
[bool]$EnableIPv6 = $true,
[System.Windows.Forms.Control[]]$ControlsToDisable = @()
)
Write-GUI " -> Applying DNS profile '$Provider' (DoH: $EnableDoH, IPv6: $EnableIPv6)..."
Update-Progress 20
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
$routedAdapters = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }
try {
$ipProps = $nic.GetIPProperties()
$validGw = @($ipProps.GatewayAddresses | Where-Object { $_.Address.ToString() -notin @("0.0.0.0", "::") })
if ($null -eq $ipProps -or $validGw.Count -eq 0) { continue }
$v4Props = $ipProps.GetIPv4Properties()
if ($null -eq $v4Props -or $v4Props.Index -le 0) { continue }
$routedAdapters.Add([PSCustomObject]@{
InterfaceIndex = [int]$v4Props.Index
InterfaceGuid  = [string]$nic.Id
InterfaceName  = [string]$nic.Description
InterfaceAlias = [string]$nic.Name
})
} catch { }
}
if ($routedAdapters.Count -eq 0) {
$UltixSync.Logs.Enqueue(" [!] No active network adapters with a default gateway found.")
return
}
$wellKnownBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers"
$ifSpecBase    = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters"
$hasDohCmd     = ($null -ne (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue))
$totalNics = $routedAdapters.Count
$nicIdx    = 0
foreach ($nicInfo in $routedAdapters) {
$nicIdx++
if ($null -ne $UltixSync) {
$UltixSync.Progress = 20 + [int](($nicIdx / $totalNics) * 70)
}
$ifIndex = $nicInfo.InterfaceIndex
$ifGuid  = $nicInfo.InterfaceGuid
$ifName  = $nicInfo.InterfaceName
$dohV4Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh"
$dohV6Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh6"
if (Test-Path -LiteralPath $dohV4Root) { Remove-Item -LiteralPath $dohV4Root -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $dohV6Root) { Remove-Item -LiteralPath $dohV6Root -Recurse -Force -ErrorAction SilentlyContinue }
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
$tcp6IfKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$ifGuid"
if (Test-Path -LiteralPath $tcp6IfKey) {
Set-ItemProperty -LiteralPath $tcp6IfKey -Name "NameServer" -Value "" -Type String -Force -ErrorAction SilentlyContinue
}
}
$UltixSync.Logs.Enqueue(" -> [$ifName]: Enforced servers: $($allServers -join ', ')")
} catch {
$UltixSync.Logs.Enqueue(" [!] [$ifName]: Error setting DNS servers: $($_.Exception.Message)")
}
if ($UseDoH) {
if (-not (Test-Path -LiteralPath $wellKnownBase)) { New-Item -Path $wellKnownBase -Force | Out-Null }
foreach ($ip in $allServers) {
$wkKey = "$wellKnownBase\$ip"
if (-not (Test-Path -LiteralPath $wkKey)) { New-Item -Path $wkKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $wkKey -Name "Template" -Value $cfg.Template -Type String -Force -ErrorAction SilentlyContinue
if ($hasDohCmd) {
Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
}
$isV6 = ($ip -match ":")
$targetDohKey = if ($isV6) { "$dohV6Root\$ip" } else { "$dohV4Root\$ip" }
if (-not (Test-Path -LiteralPath $targetDohKey)) { New-Item -Path $targetDohKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $targetDohKey -Name "DohFlags" -Value ([uint64]1) -Type QWord -Force -ErrorAction SilentlyContinue
}
$UltixSync.Logs.Enqueue("    [+] Native DoH encryption activated ($($cfg.Template)).")
}
}
Clear-DnsClientCache -ErrorAction SilentlyContinue
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
} -OnComplete ({
param($nullOut)
Update-Progress 0
Update-DNSLabel
Write-GUI " -> DNS configuration completed and resolver cache flushed.`n"
}.GetNewClosure())
}
function Start-ClassicNet      { Start-Process "ncpa.cpl" }
function Start-ClassicApps     { Start-Process "appwiz.cpl" }
function Start-ClassicSound    { Start-Process "mmsys.cpl" }
function Start-ClassicPrinters { Start-Process "explorer.exe" -ArgumentList "shell:::{26EE0668-A00A-44D7-9371-BEB064C98683}\0\::{A8A91A66-3A7D-4424-8D24-04E180695C7A}" }
function Start-ClassicSysProp  { Start-Process "SystemPropertiesAdvanced.exe" }
function Start-ClassicPower    { Start-Process "powercfg.cpl" }
function Start-ClassicGpoOrReg {
if ([System.IO.File]::Exists("$env:windir\System32\gpedit.msc")) {
Start-Process "mmc.exe" -ArgumentList "`"$env:windir\System32\gpedit.msc`""
} else {
Start-Process "regedit.exe"
}
}
function Start-ClassicCompMgmt { Start-Process "compmgmt.msc" }
function Initialize-Z5UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tabSec = New-Object System.Windows.Forms.TabPage
$tabSec.Text = "Security"
$tabSec.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$invokeSecReg = ({
param(
[string]$ScannerFn,
[string]$CategoryName,
[string]$ModalTitle,
[string]$AuditHeader,
[switch]$AuditOnly
)
Invoke-UltixAuditFlow `
-ScannerFunction $ScannerFn `
-AuditLabel $AuditHeader `
-ModalTitle $ModalTitle `
-ModalDescription "Select security & privacy policies to apply or revert." `
-ExecutorFunction "Invoke-ApplyRegistry" `
-ExecutorExtraParams @{
CategoryName = $CategoryName
RefreshShell = $true
} `
-ControlsToDisable $allTabButtons.ToArray() `
-AuditOnly:$AuditOnly.IsPresent `
-AuditPrefix "To Optimize" `
-EnableRevert
}.GetNewClosure())
$rowPrivacy = New-UltixActionRow -Parent $tabSec -Y 20 -MainRGB @(55, 58, 64) `
-Text "Privacy & Background Apps (AppPrivacy)" `
-Description "Blocks OS telemetry, locks 28 UWP background permissions (Camera, Mic, Location, Contacts), disables Edge background boost, and stops ContentDeliveryManager." `
-AuditDescription "AUDIT: Checks the registry for telemetry, UWP AppPrivacy, Edge, and ContentDeliveryManager blocks." `
-OnClick ({ & $invokeSecReg "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy & AppPrivacy Policies" "Privacy Policies" }.GetNewClosure()) `
-OnAudit ({ & $invokeSecReg "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy & AppPrivacy Policies" "Privacy Policies" -AuditOnly }.GetNewClosure())
$rowBoot = New-UltixActionRow -Parent $tabSec -Y 70 -MainRGB @(55, 58, 64) `
-Text "Boot, SvcHost & WPBT (BIOS Block)" `
-Description "Blocks motherboard BIOS/UEFI binary injection (DisableWpbtExecution), disables Fast Startup hibernation bugs, blocks RDP, and consolidates SvcHost processes." `
-AuditDescription "AUDIT: Verifies WPBT BIOS block, Fast Startup, SvcHost RAM threshold, and RDP locks." `
-OnClick ({ & $invokeSecReg "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Kernel Security" "Boot & Kernel Security" }.GetNewClosure()) `
-OnAudit ({ & $invokeSecReg "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Kernel Security" "Boot & Kernel Security" -AuditOnly }.GetNewClosure())
$rowUsbGuard = New-UltixActionRow -Parent $tabSec -Y 120 -MainRGB @(135, 50, 50) `
-Text "USB Storage & BadUSB Guard (Lockdown)" `
-Description "4-Layer USB & MTP perimeter defense: Read-Only Write Protection, Execute-Deny (.exe), Full USBSTOR + UASPStor driver blackout, and Lock-Screen BadUSB/DMA guard." `
-AuditDescription "AUDIT: Checks USB/MTP Write-Protect, USBSTOR/UASPStor driver states, and Lock-Screen DMA/BadUSB policies." `
-OnClick ({
Invoke-UltixAuditFlow -ScannerFunction "Get-UsbSecurityState" -AuditLabel "USB Perimeter Security" -ModalTitle "WinUltix - USB Storage & BadUSB Guard" -ModalDescription "Select USB protection layers to enforce (Apply = Lock, Revert = Unlock to Windows Defaults)." -ExecutorFunction "Invoke-ApplyUsbSecurity" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
}.GetNewClosure()) `
-OnAudit ({
Invoke-UltixAuditFlow -ScannerFunction "Get-UsbSecurityState" -AuditLabel "USB Perimeter Security" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Unlocked"
}.GetNewClosure())
$btnRegSRP = New-UltixButton -Parent $tabSec -X 15 -Y 170 -Width 235 -Height 40 -RGB @(135, 50, 50) `
-Text "Execution Blocks (SRP + IFEO)" `
-Description "DUAL-LAYER KERNEL LOCK: Combines Software Restriction Policies (Safer API) with Image File Execution Options (IFEO) to permanently block telemetry or custom .exe files." `
-OnClick ({
Invoke-UltixAuditFlow `
-ScannerFunction "Get-RegState_SRP" `
-AuditLabel "Dual-Layer Execution Locks (SRP + IFEO)" `
-ModalTitle "WinUltix - SRP & IFEO Lockdown" `
-ModalDescription "Select executables to permanently block via OS policies (Apply = Lock, Revert = Unlock)." `
-ExecutorFunction "Invoke-ApplySRP" `
-ControlsToDisable $allTabButtons.ToArray() `
-EnableRevert
}.GetNewClosure())
$btnAddSRP = New-UltixButton -Parent $tabSec -X 255 -Y 170 -Width 40 -Height 40 -RGB @(45, 95, 60) `
-Text "+" `
-Description "ADD CUSTOM TARGET: Browse for an .exe file to add to your custom SRP+IFEO block list." `
-OnClick ({
$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Filter = "Executables (*.exe)|*.exe"
$dlg.Title = "Select Executable to Block (SRP+IFEO)"
$dlg.InitialDirectory = "$env:ProgramFiles"
try {
if ($dlg.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
$exeName = [System.IO.Path]::GetFileName($dlg.FileName)
$protectedCoreBins = '^(?i)(explorer|svchost|lsass|csrss|smss|wininit|winlogon|services|dwm|sihost|taskhostw|conhost|cmd|powershell|pwsh|regedit|mmc|taskmgr|systray|gpupdate|WinUltix)\.exe$'
if ($exeName -match $protectedCoreBins) {
[System.Windows.Forms.MessageBox]::Show("Blocking core Windows shell/kernel binary '$exeName' is forbidden to prevent OS lockout.", "WinUltix - Safety Guard", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
return
}
$regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
if (-not (Test-Path -LiteralPath $regKey)) { New-Item -Path $regKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $regKey -Name $exeName -Value $dlg.FileName -Type String -Force
Write-GUI " -> Added custom SRP+IFEO target: $exeName ($($dlg.FileName))"
}
} finally {
$dlg.Dispose()
}
}.GetNewClosure())
$btnClrSRP = New-UltixButton -Parent $tabSec -X 300 -Y 170 -Width 40 -Height 40 -RGB @(55, 58, 64) `
-Text "-" `
-Description "CLEAR CUSTOM TARGETS: Unlocks any active custom SRP+IFEO blocks and purges the custom tracking list." `
-OnClick ({
$regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
if (-not (Test-Path -LiteralPath $regKey)) {
Write-GUI " -> Custom SRP+IFEO roster is already empty.`n"
return
}
$customItems = @(Get-RegState_SRP | Where-Object { $_.ActionData.IsCustom -eq $true })
Remove-Item -LiteralPath $regKey -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
if ($customItems.Count -gt 0) {
Write-GUI " -> Purging custom SRP+IFEO tracking list and reverting $($customItems.Count) custom rule(s)..."
Invoke-ApplySRP -SelectedItems $customItems -Operation "Revert" -ControlsToDisable $allTabButtons.ToArray()
} else {
Write-GUI " -> Custom SRP+IFEO tracking database purged.`n"
}
}.GetNewClosure())
$btnAudSRP = New-UltixButton -Parent $tabSec -X 345 -Y 170 -Width 40 -Height 40 -RGB @(72, 76, 82) `
-Text "?" `
-Description "AUDIT: Verifies active Software Restriction Policies (SRP) and IFEO kernel locks." `
-OnClick ({
Invoke-UltixAuditFlow `
-ScannerFunction "Get-RegState_SRP" `
-AuditLabel "Dual-Layer Execution Locks (SRP + IFEO)" `
-ControlsToDisable $allTabButtons.ToArray() `
-AuditOnly `
-AuditPrefix "To Block"
}.GetNewClosure())
$lblDNS = New-Object System.Windows.Forms.Label
$lblDNS.Text = "Hardened DNS & Native DoH Enforcer (IPv4 / IPv6)"
$lblDNS.Location = New-Object System.Drawing.Point(15, 228)
$lblDNS.Size = New-Object System.Drawing.Size(370, 20)
$lblDNS.ForeColor = [System.Drawing.Color]::DarkGray
$lblDNS.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$comboDNS = New-Object System.Windows.Forms.ComboBox
$comboDNS.Location = New-Object System.Drawing.Point(15, 252)
$comboDNS.Size = New-Object System.Drawing.Size(240, 25)
$comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
$comboDNS.ForeColor = [System.Drawing.Color]::White
$comboDNS.DropDownStyle = "DropDownList"
$comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)"))
$comboDNS.SelectedIndex = 0
$chkDoH = New-Object System.Windows.Forms.CheckBox
$chkDoH.Text = "Enforce Native DNS-over-HTTPS (DoH)"
$chkDoH.Location = New-Object System.Drawing.Point(15, 284)
$chkDoH.Size = New-Object System.Drawing.Size(235, 22)
$chkDoH.ForeColor = [System.Drawing.Color]::LightGray
$chkDoH.Checked = $true
$chkIPv6 = New-Object System.Windows.Forms.CheckBox
$chkIPv6.Text = "Configure IPv6 DNS"
$chkIPv6.Location = New-Object System.Drawing.Point(255, 284)
$chkIPv6.Size = New-Object System.Drawing.Size(135, 22)
$chkIPv6.ForeColor = [System.Drawing.Color]::LightGray
$chkIPv6.Checked = $true
$comboDNS.Add_SelectedIndexChanged({
$isStatic = ([string]$comboDNS.SelectedItem -ne "Default (DHCP)")
$chkDoH.Enabled  = $isStatic
$chkIPv6.Enabled = $isStatic
}.GetNewClosure())
$btnApplyDNS = New-UltixButton -Parent $tabSec -X 265 -Y 251 -Width 120 -Height 27 -RGB @(45, 85, 125) `
-Text "Apply DNS" `
-Description "Enforces IPv4/IPv6 DNS servers, injects kernel Dnscache DoH encryption flags, and flushes resolver cache." `
-OnClick ({
Set-CustomDNS -Provider ([string]$comboDNS.SelectedItem) -EnableDoH $chkDoH.Checked -EnableIPv6 $chkIPv6.Checked -ControlsToDisable $allTabButtons.ToArray()
}.GetNewClosure())
$global:lblCurrentDNS = New-Object System.Windows.Forms.Label
$global:lblCurrentDNS.Text = "Current DNS: Reading from active route..."
$global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 310)
$global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 22)
$global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue
$global:lblCurrentDNS.Cursor = [System.Windows.Forms.Cursors]::Hand
$global:lblCurrentDNS.Add_Click({ Update-DNSLabel })
$lblClassic = New-Object System.Windows.Forms.Label
$lblClassic.Text = "Classic Win32 Control & Admin Applets"
$lblClassic.Location = New-Object System.Drawing.Point(15, 345)
$lblClassic.Size = New-Object System.Drawing.Size(370, 20)
$lblClassic.ForeColor = [System.Drawing.Color]::DarkGray
$lblClassic.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnNetCpl = New-UltixButton -Parent $tabSec -X 15 -Y 370 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Network Adapters (ncpa)" `
-Description "Direct launch of the classic Win32 Network Connections applet (ncpa.cpl)." `
-OnClick { Start-ClassicNet }
$btnSndCpl = New-UltixButton -Parent $tabSec -X 205 -Y 370 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Sound Subsystem (mmsys)" `
-Description "Direct launch of playback/recording devices and sample rate properties (mmsys.cpl)." `
-OnClick { Start-ClassicSound }
$btnAppCpl = New-UltixButton -Parent $tabSec -X 15 -Y 420 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Programs & Features" `
-Description "Direct launch of the classic Win32 MSI/InstallShield software uninstaller (appwiz.cpl)." `
-OnClick { Start-ClassicApps }
$btnPrnCpl = New-UltixButton -Parent $tabSec -X 205 -Y 420 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Devices and Printers" `
-Description "Bypasses Windows 11 Settings redirect to open the raw Win32 Devices and Printers shell folder." `
-OnClick { Start-ClassicPrinters }
$btnSysCpl = New-UltixButton -Parent $tabSec -X 15 -Y 470 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "System Properties (Env)" `
-Description "Opens Advanced System Properties (Pagefile, Performance Flags, and Environment Variables)." `
-OnClick { Start-ClassicSysProp }
$btnPwrCpl = New-UltixButton -Parent $tabSec -X 205 -Y 470 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Power Plans (powercfg)" `
-Description "Opens the classic Power Options applet to inspect unhidden CPPC parameters." `
-OnClick { Start-ClassicPower }
$btnGpoCpl = New-UltixButton -Parent $tabSec -X 15 -Y 520 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Group Policy / RegEdit" `
-Description "Opens Local Group Policy Editor (gpedit.msc) or falls back to Registry Editor (regedit.exe) on Home SKUs." `
-OnClick { Start-ClassicGpoOrReg }
$btnMgmtCpl = New-UltixButton -Parent $tabSec -X 205 -Y 520 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Computer Mgmt (MSC)" `
-Description "Opens Computer Management (compmgmt.msc) for Disk Management, Local Users, Event Viewer, and Device Manager." `
-OnClick { Start-ClassicCompMgmt }
foreach ($row in @($rowPrivacy, $rowBoot, $rowUsbGuard)) {
$allTabButtons.AddRange($row.Controls)
}
$allTabButtons.AddRange([System.Windows.Forms.Control[]]@(
$btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP,
$comboDNS, $chkDoH, $chkIPv6, $btnApplyDNS,
$btnNetCpl, $btnSndCpl, $btnAppCpl, $btnPrnCpl, $btnSysCpl, $btnPwrCpl, $btnGpoCpl, $btnMgmtCpl
))
$tabSec.Controls.AddRange(@(
$lblDNS, $comboDNS, $chkDoH, $chkIPv6, $global:lblCurrentDNS, $lblClassic
))
$TabControl.Controls.Add($tabSec)
}
function Start-ExternalConsoleAsync {
param(
[Parameter(Mandatory=$true)][string]$Title,
[Parameter(Mandatory=$true)][string]$CommandChain,
[AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable = @()
)
$validControls = @($ControlsToDisable | Where-Object { $null -ne $_ })
Write-GUI " -> Launching external maintenance console: $Title..."
Update-Progress 20
Invoke-AsyncTask -ControlsToDisable $validControls -ScriptBlock {
param($CmdTitle, $CmdChain)
$fullArgs = "/v:on /c `"title $CmdTitle & color 0A & set WUX_ERR=0 & $CmdChain & if !WUX_ERR! EQU 0 (set WUX_ERR=!ERRORLEVEL!) & echo. & echo Operation finished (Exit Code: !WUX_ERR!). Press any key to close... & pause >nul & exit /b !WUX_ERR!`""
$exitCode = -1
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList $fullArgs -PassThru -ErrorAction Stop
try {
$proc.WaitForExit()
$exitCode = $proc.ExitCode
} finally {
$proc.Dispose()
}
return [PSCustomObject]@{
Title    = $CmdTitle
ExitCode = $exitCode
}
} -Arguments @($Title, $CommandChain) -OnComplete ({
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
}.GetNewClosure())
}
function Get-WinSxSState {
if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }
$tiRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller"
$tiStart   = (Get-ItemProperty -LiteralPath $tiRegPath -Name "Start" -ErrorAction SilentlyContinue).Start
if ($tiStart -eq 4) {
Set-ProtectedServiceStart -ServiceName "TrustedInstaller" -StartValue 3
}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = "dism.exe"
$psi.Arguments              = "/Online /Cleanup-Image /AnalyzeComponentStore /English"
$psi.UseShellExecute        = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.RedirectStandardInput  = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.CreateNoWindow         = $true
$sbOutput       = [System.Text.StringBuilder]::new()
$exitCode       = -1
$proc           = $null
$loggedFinalize = $false
try {
$proc = [System.Diagnostics.Process]::Start($psi)
if ($null -ne $proc) {
try { $proc.StandardInput.Close() } catch { }
[void]$proc.StandardError.ReadToEndAsync()
$charBuf  = New-Object char[] 1024
$readTask = $proc.StandardOutput.ReadAsync($charBuf, 0, $charBuf.Length)
$idleTicksAfterTable = 0
while ($true) {
if ($readTask.Wait(250)) {
$charsRead = $readTask.Result
if ($charsRead -le 0) { break }
$chunk = [string]::new($charBuf, 0, $charsRead)
[void]$sbOutput.Append($chunk)
$pctMatches = [regex]::Matches($chunk, '(\d{1,3})\.\d+%')
if ($pctMatches.Count -gt 0) {
$lastPct = [int]$pctMatches[$pctMatches.Count - 1].Groups[1].Value
if ($null -ne $UltixSync) {
$UltixSync.Progress = [math]::Max(5, [math]::Min(99, $lastPct))
if ($lastPct -ge 100 -and -not $loggedFinalize) {
$loggedFinalize = $true
$UltixSync.Logs.Enqueue("  [*] 100% scan reached -- waiting for CBS (TiWorker) to finalize WinSxS size table...")
}
}
}
$readTask = $proc.StandardOutput.ReadAsync($charBuf, 0, $charBuf.Length)
$idleTicksAfterTable = 0
} else {
$curText = $sbOutput.ToString()
$hasTableEnd = (
$curText -match '(?s)\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}.*?:\s*\d+\s*\r?\n[^\r\n:]+:\s*\S+' -or
$curText -match '(?im)(Recommended|Zalecane|Empfohlen|Recommand).*?:\s*\S+'
)
if ($proc.HasExited) {
$idleTicksAfterTable++
if ($idleTicksAfterTable -ge 2) { break }
} elseif ($hasTableEnd) {
$idleTicksAfterTable++
if ($idleTicksAfterTable -ge 6) { break }
}
}
}
[void]$proc.WaitForExit(3000)
if ($proc.HasExited) {
$exitCode = $proc.ExitCode
} else {
$exitCode = 0
}
}
} catch {
if ($null -ne $UltixSync) {
$UltixSync.Logs.Enqueue(" [!] DISM component store analysis failed: $($_.Exception.Message)")
}
} finally {
if ($null -ne $proc) { $proc.Dispose() }
}
if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
$dismOutput = $sbOutput.ToString()
$sizeMatches = @([regex]::Matches($dismOutput, '(?im):\s*([\d\.,]+\s*[MGK]B)\b'))
$actualSize  = if ($sizeMatches.Count -ge 2) {
$sizeMatches[1].Groups[1].Value.Trim()
} elseif ($sizeMatches.Count -eq 1) {
$sizeMatches[0].Groups[1].Value.Trim()
} else {
"Unknown"
}
$reclaimableCount = 0
if ($dismOutput -match '(?s)\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s*\r?\n[^\r\n:]+:\s*(\d+)\b') {
$reclaimableCount = [int]$matches[1]
}
$recommended = (
$reclaimableCount -gt 0 -or
($dismOutput -match "(?im)(Recommended|Zalecane|Empfohlen|Recommand).*?:\s*(Yes|Tak|Ja|Oui|S[i\u00ED]|True|1)\b")
)
$rebootPending = Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
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
if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
$warnMsg = "A pending Windows servicing reboot was detected in the CBS registry.`n`nRunning DISM /ResetBase while a reboot is pending on Windows 11 24H2/26H2 may fail with error 0x800f0806.`n`nDo you still want to force execution?"
$ans = [System.Windows.Forms.MessageBox]::Show($warnMsg, "WinUltix - CBS Reboot Pending", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
Write-GUI " -> WinSxS ResetBase aborted due to pending reboot.`n"
return
}
}
$cmd = "echo Aggressive WinSxS compression in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
$tiReg = "HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller"
if ((Get-ItemProperty -LiteralPath $tiReg -Name "Start" -ErrorAction SilentlyContinue).Start -eq 4) {
Set-ProtectedServiceStart -ServiceName "TrustedInstaller" -StartValue 3
}
Start-ExternalConsoleAsync -Title "WinUltix - WinSxS ResetBase" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}
function Invoke-SystemHealthAudit {
param([AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable = @())
Write-GUI "--- AUDIT: OS Image, CBS & NTFS Volume Health (Background Thread) ---"
Update-Progress 15
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
$tiReg = "HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller"
if ((Get-ItemProperty -LiteralPath $tiReg -Name "Start" -ErrorAction SilentlyContinue).Start -eq 4) {
Set-ProtectedServiceStart -ServiceName "TrustedInstaller" -StartValue 3
}
$UltixSync.Progress = 35
$null = & dism.exe /Online /Cleanup-Image /CheckHealth /English 2>&1
$dismExit = $LASTEXITCODE
$cbsKey     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"
$cbsProps   = Get-ItemProperty -LiteralPath $cbsKey -Name "CorruptionFlags", "StoreCorrupt", "UnavailableRepairCount" -ErrorAction SilentlyContinue
$hasRegCorr = ($null -ne $cbsProps) -and (
($null -ne $cbsProps.CorruptionFlags -and $cbsProps.CorruptionFlags -ne 0) -or
($null -ne $cbsProps.StoreCorrupt -and $cbsProps.StoreCorrupt -ne 0) -or
($null -ne $cbsProps.UnavailableRepairCount -and $cbsProps.UnavailableRepairCount -gt 0)
)
$isHealthy = ($dismExit -eq 0 -and -not $hasRegCorr)
$UltixSync.Progress = 70
$sysDrive = $env:SystemDrive.TrimEnd('\')
$isDirty  = $false
$dirtyCode = [WinUltix.NativeMethods]::IsVolumeDirty($sysDrive)
if ($dirtyCode -ge 0) {
$isDirty = ($dirtyCode -eq 1)
} else {
$fsOut = (& fsutil.exe dirty query $sysDrive 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($fsOut)) {
if ($fsOut -notmatch '(?i)\b(NOT|NIE|NICHT|PAS|NON|NO|NIET|N[A\u00C3]O|EI|INTE|IKKE|NE|NINCS)\b') {
$isDirty = $true
}
}
}
$UltixSync.Progress = 90
$cbsReboot = Test-Path -LiteralPath "$cbsKey\RebootPending"
$sfcPend   = Test-Path -LiteralPath "$cbsKey\PackagesPending"
$UltixSync.Progress = 100
return [PSCustomObject]@{
ImageHealthy = $isHealthy
NtfsDirty    = $isDirty
DriveName    = $sysDrive
CbsReboot    = $cbsReboot
SfcPending   = $sfcPend
}
} -OnComplete ({
param($res)
Update-Progress 0
if ($null -ne $res) {
if ($res.ImageHealthy) {
Write-GUI "  [OK] DISM CheckHealth: No component store corruption detected (CBS Store Clean)."
} else {
Write-GUI "  [!] WARNING: DISM flagged component store corruption! Run 'Scan System' repair."
}
if (-not $res.NtfsDirty) {
Write-GUI "  [OK] NTFS Volume ($($res.DriveName)): Clean (VolumeDirty = False)."
} else {
Write-GUI "  [!] WARNING: NTFS Volume ($($res.DriveName)) has Dirty Bit set! Run 'Scan System' repair."
}
if ($res.CbsReboot -or $res.SfcPending) {
Write-GUI "  [!] CBS Servicing Status: Pending reboot / package repair detected.`n"
} else {
Write-GUI "  [OK] CBS Servicing Queue: Clean (Zero pending repairs).`n"
}
}
}.GetNewClosure())
}
function Repair-SystemIntegrity {
param([System.Windows.Forms.Control[]]$ControlsToDisable)
$sysDrive = $env:SystemDrive.TrimEnd('\')
$msg = "This operation will open an external maintenance console and execute:`n`n" +
"  1. Online CheckDisk Scan (chkdsk $sysDrive /scan)`n" +
"  2. DISM Image Repair (DISM /Online /Cleanup-Image /RestoreHealth)`n" +
"  3. System File Checker (sfc /scannow)`n`n" +
"Full verification typically takes 5 to 15 minutes. Do you want to proceed?"
$ans = [System.Windows.Forms.MessageBox]::Show($msg, "WinUltix - System Integrity Repair", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
Write-GUI " -> System Integrity Repair cancelled by user.`n"
return
}
$cmd = "echo [1/3] Running Online CheckDisk Scan... & chkdsk $sysDrive /scan & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [2/3] Running DISM RestoreHealth... & dism /online /cleanup-image /restorehealth & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [3/3] Running SFC Scan... & sfc /scannow & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
$tiReg = "HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller"
if ((Get-ItemProperty -LiteralPath $tiReg -Name "Start" -ErrorAction SilentlyContinue).Start -eq 4) {
Set-ProtectedServiceStart -ServiceName "TrustedInstaller" -StartValue 3
}
Start-ExternalConsoleAsync -Title "WinUltix - System Integrity Repair" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}
function Clear-NetworkStack {
param([System.Windows.Forms.Control[]]$ControlsToDisable)
Write-GUI " -> Initiating Full Network Stack Refresh (Background Thread)..."
Update-Progress 10
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
try {
$UltixSync.Progress = 25
$UltixSync.Logs.Enqueue(" -> [1/4] Flushing DNS Resolver Cache (ipconfig /flushdns)...")
$null = & ipconfig.exe /flushdns 2>&1
$UltixSync.Progress = 50
$UltixSync.Logs.Enqueue(" -> [2/4] Clearing ARP routing tables & resetting WinHTTP proxy...")
$null = & arp.exe -d * 2>&1
$null = & netsh.exe winhttp reset proxy 2>&1
$UltixSync.Progress = 75
$UltixSync.Logs.Enqueue(" -> [3/4] Resetting Winsock Catalog (netsh winsock reset)...")
$null = & netsh.exe winsock reset 2>&1
$UltixSync.Progress = 95
$UltixSync.Logs.Enqueue(" -> [4/4] Resetting TCP/IPv4 & IPv6 Stack (netsh int ip/ipv6 reset)...")
$null = & netsh.exe int ip reset 2>&1
$null = & netsh.exe int ipv6 reset 2>&1
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [OK] Network stack refreshed (Reboot recommended to finalize Winsock reset).")
} catch {
$UltixSync.Logs.Enqueue(" [!] Network stack refresh failed: $($_.Exception.Message)")
}
} -OnComplete {
param($nullOut)
Update-Progress 0
Write-GUI ""
}
}
function Repair-PrintSubsystem {
param([System.Windows.Forms.Control[]]$ControlsToDisable)
Write-GUI " -> Initiating Print Subsystem First-Aid (Background Thread)..."
Update-Progress 10
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
try {
$UltixSync.Progress = 20
$spoolReg = "HKLM:\SYSTEM\CurrentControlSet\Services\Spooler"
$curStart = (Get-ItemProperty -LiteralPath $spoolReg -Name "Start" -ErrorAction SilentlyContinue).Start
if ($curStart -eq 4) {
Set-ProtectedServiceStart -ServiceName "Spooler" -StartValue 2
$UltixSync.Logs.Enqueue(" -> Re-enabled Print Spooler service (Was locked to Disabled by Gaming Profile).")
}
$spoolerProcs = @(Get-Process -Name "spoolsv" -ErrorAction SilentlyContinue)
if ($spoolerProcs.Count -gt 0) {
foreach ($p in $spoolerProcs) {
try { $p.Kill() } catch { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
finally { $p.Dispose() }
}
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
$printWorkflow = @(Get-Service -Name "PrintWorkflowUserSvc*" -ErrorAction SilentlyContinue)
if ($printWorkflow.Count -gt 0) {
foreach ($wfSvc in $printWorkflow) {
try {
Stop-Service -InputObject $wfSvc -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
Start-Service -InputObject $wfSvc -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
} finally {
$wfSvc.Dispose()
}
}
$UltixSync.Logs.Enqueue(" -> Restarted dynamic PrintWorkflowUserSvc service.")
}
Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction Stop
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [OK] Print Spooler service is back online.")
} catch {
$UltixSync.Logs.Enqueue(" [!] Failed to reset print subsystem: $($_.Exception.Message)")
Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
$UltixSync.Progress = 15
$UltixSync.Logs.Enqueue(" -> [1/5] Stopping wuauserv, cryptSvc, bits, dosvc, and msiserver...")
foreach ($svc in $wuServices) {
Stop-Service -Name $svc -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 800
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
$UltixSync.Progress = 75
$modernDlls = @(
"atl.dll", "urlmon.dll", "jscript.dll", "vbscript.dll", "scrrun.dll",
"msxml3.dll", "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll",
"dssenh.dll", "rsaenh.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll",
"shell32.dll", "wuapi.dll", "wuaueng.dll", "wups.dll", "wups2.dll", "qmgr.dll"
)
$validDllPaths = [System.Collections.Generic.List[string]]::new()
foreach ($dll in $modernDlls) {
$dllFull = "$env:windir\System32\$dll"
if ([System.IO.File]::Exists($dllFull)) {
$validDllPaths.Add("`"$dllFull`"")
}
}
if ($validDllPaths.Count -gt 0) {
$batchArgs = "/s " + ($validDllPaths -join " ")
$regProc = Start-Process -FilePath "regsvr32.exe" -ArgumentList $batchArgs -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
if ($null -ne $regProc) {
try { $regProc.WaitForExit(15000) | Out-Null } finally { $regProc.Dispose() }
}
}
$UltixSync.Logs.Enqueue(" -> [4/5] Batch re-registered $($validDllPaths.Count) Cryptographic, WinTrust, and WU COM DLLs.")
} catch {
$UltixSync.Logs.Enqueue(" [!] Error during Windows Update subsystem repair: $($_.Exception.Message)")
} finally {
$UltixSync.Progress = 95
$svcDefaults = @{ "cryptSvc" = 2; "bits" = 3; "wuauserv" = 3; "dosvc" = 2; "msiserver" = 3 }
foreach ($svc in @("cryptSvc", "bits", "wuauserv", "dosvc", "msiserver")) {
$sPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
$curSt = (Get-ItemProperty -LiteralPath $sPath -Name "Start" -ErrorAction SilentlyContinue).Start
$targetSt = if ($curSt -eq 4) { $svcDefaults[$svc] } else { [int]$curSt }
$startNow = ($svc -in @("cryptSvc", "bits", "wuauserv", "dosvc"))
Set-ProtectedServiceStart -ServiceName $svc -StartValue $targetSt -StartService:$startNow
}
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [5/5] [OK] Windows Update, Delivery Optimization & Cryptographic services restored and online.")
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
$verifyOut = (& winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
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
$verifyOut = (& winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
$UltixSync.Logs.Enqueue("    [*] Status: $verifyOut")
$UltixSync.Progress = 55
$UltixSync.Logs.Enqueue(" -> [2/3] Executing non-destructive winmgmt /salvagerepository...")
$salvageOut = (& winmgmt.exe /salvagerepository 2>&1 | Out-String).Trim()
$UltixSync.Logs.Enqueue("    [*] Result: $salvageOut")
$UltixSync.Progress = 85
$UltixSync.Logs.Enqueue(" -> [3/3] Refreshing WMI Performance Adapter (wmiadap /f)...")
$adapProc = Start-Process -FilePath "wmiadap.exe" -ArgumentList "/f" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
if ($null -ne $adapProc) {
try { $adapProc.WaitForExit(15000) | Out-Null } finally { $adapProc.Dispose() }
}
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
$item = Get-Item -LiteralPath $legacyIconDb -Force -ErrorAction SilentlyContinue
if ($null -ne $item) { $item.Attributes = 'Normal' }
Remove-Item -LiteralPath $legacyIconDb -Force -ErrorAction Stop
$purgedIcons++
} catch { }
}
$UltixSync.Logs.Enqueue(" -> [2/4] Purged $purgedIcons iconcache_*.db and $purgedThumbs thumbcache_*.db file(s).")
$UltixSync.Progress = 80
$UltixSync.Logs.Enqueue(" -> [3/4] Triggering ie4uinit.exe cache rebuild...")
$ieProc = Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
if ($null -ne $ieProc) {
try { $ieProc.WaitForExit(10000) | Out-Null } finally { $ieProc.Dispose() }
}
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [4/4] [OK] Shell Icon & Thumbnail caches rebuilt cleanly.")
} catch {
$UltixSync.Logs.Enqueue(" [!] Failed to rebuild Icon/Thumbnail cache: $($_.Exception.Message)")
} finally {
$expProcs = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)
if ($expProcs.Count -eq 0) {
Start-Process "explorer.exe"
} else {
foreach ($ep in $expProcs) { $ep.Dispose() }
}
}
} -OnComplete {
param($nullOut)
Update-Progress 0
Write-GUI ""
}
}
function Repair-TimeSynchronization {
param([System.Windows.Forms.Control[]]$ControlsToDisable)
Write-GUI " -> Initiating Time & NTP Clock Synchronization First-Aid (Background Thread)..."
Update-Progress 10
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
try {
$UltixSync.Progress = 25
$UltixSync.Logs.Enqueue(" -> [1/4] Enforcing UTC hardware RTC clock (RealTimeIsUniversal=1) & unlocking W32Time...")
$tzPath = "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation"
if (Test-Path -LiteralPath $tzPath) {
Set-ItemProperty -LiteralPath $tzPath -Name "RealTimeIsUniversal" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}
Stop-Service -Name "W32Time" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
& w32tm.exe /unregister 2>$null | Out-Null
Start-Sleep -Milliseconds 300
& w32tm.exe /register 2>$null | Out-Null
Set-ProtectedServiceStart -ServiceName "W32Time" -StartValue 3
$UltixSync.Progress = 55
$UltixSync.Logs.Enqueue(" -> [2/4] Starting Windows Time service & configuring resilient NTP pool (Cloudflare / Pool.ntp / MS)...")
Start-Service -Name "W32Time" -WarningAction SilentlyContinue -ErrorAction Stop
& w32tm.exe /config /manualpeerlist:"pool.ntp.org,0x8 time.cloudflare.com,0x8 time.windows.com,0x9" /syncfromflags:manual /reliable:yes /update 2>$null | Out-Null
$UltixSync.Progress = 85
$UltixSync.Logs.Enqueue(" -> [3/4] Triggering immediate NTP clock resynchronization (w32tm /resync /rediscover)...")
$null = & w32tm.exe /resync /rediscover 2>&1
$srcOut = (& w32tm.exe /query /source 2>&1 | Out-String).Trim()
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [4/4] [OK] System clock synchronized (Active NTP Source: $srcOut).")
} catch {
$UltixSync.Logs.Enqueue(" [!] Time synchronization repair failed: $($_.Exception.Message)")
}
} -OnComplete {
param($nullOut)
Update-Progress 0
Write-GUI ""
}
}
function Repair-UwpGamingRuntime {
param([System.Windows.Forms.Control[]]$ControlsToDisable)
Write-GUI " -> Initiating UWP Shell, Store & Xbox Gaming Services First-Aid (Background Thread)..."
Update-Progress 10
Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
try {
$UltixSync.Progress = 20
$UltixSync.Logs.Enqueue(" -> [1/4] Verifying core UWP licensing, Delivery Optimization & Xbox Gaming Services...")
foreach ($svc in @("AppXSvc", "ClipSVC", "StateRepository", "LicenseManager", "InstallService", "dosvc", "wuauserv", "GamingServices", "GamingServicesNet")) {
$sPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
if (Test-Path -LiteralPath $sPath) {
$curSt = (Get-ItemProperty -LiteralPath $sPath -Name "Start" -ErrorAction SilentlyContinue).Start
$targetSt = if ($curSt -eq 4) { 3 } else { [int]$curSt }
Set-ProtectedServiceStart -ServiceName $svc -StartValue $targetSt -StartService
}
}
$UltixSync.Progress = 45
$UltixSync.Logs.Enqueue(" -> [2/4] Flushing corrupted Microsoft Store LocalCache & running wsreset -i...")
Stop-Process -Name "WinStore.App", "StoreExperienceHost" -Force -ErrorAction SilentlyContinue
$storeCache = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_*\LocalCache" -Directory -ErrorAction SilentlyContinue
foreach ($dir in $storeCache) {
Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
$wsProc = Start-Process -FilePath "wsreset.exe" -ArgumentList "-i" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
if ($null -ne $wsProc) {
try { $wsProc.WaitForExit(10000) | Out-Null } finally { $wsProc.Dispose() }
}
$UltixSync.Progress = 75
$UltixSync.Logs.Enqueue(" -> [3/4] Re-registering existing Shell, Store & Runtime AppxManifests (Preserving debloat state)...")
$corePattern = "WindowsStore|StorePurchaseApp|DesktopAppInstaller|XboxIdentityProvider|XboxGameCallableUI|GamingServices|SecHealthUI|WindowsDefender|ShellExperienceHost|StartMenuExperienceHost|immersivecontrolpanel|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|Microsoft\.VCLibs|Microsoft\.UI\.Xaml|Microsoft\.WindowsAppRuntime"
$targetPkgs  = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $corePattern })
$reRegCount = 0
foreach ($pkg in $targetPkgs) {
if (-not [string]::IsNullOrWhiteSpace($pkg.InstallLocation)) {
$manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
if ([System.IO.File]::Exists($manifest)) {
try {
Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
$reRegCount++
} catch { }
}
}
}
$UltixSync.Progress = 100
$UltixSync.Logs.Enqueue(" -> [4/4] [OK] Re-registered $reRegCount core UWP/Gaming manifests and flushed Store cache.")
} catch {
$UltixSync.Logs.Enqueue(" [!] UWP & Gaming runtime repair failed: $($_.Exception.Message)")
}
} -OnComplete {
param($nullOut)
Update-Progress 0
Write-GUI ""
}
}
function Initialize-Z6UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tabWinSXS = New-Object System.Windows.Forms.TabPage
$tabWinSXS.Text = "Integrity"
$tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
$rowCheckSystem = New-UltixActionRow -Parent $tabWinSXS -Y 20 -MainRGB @(55, 58, 64) `
-Text "Scan System (ChkDisk + SFC + DISM)" `
-Description "System First-Aid: Scans core Windows OS files for corruption and replaces damaged components using ChkDisk, DISM RestoreHealth, and SFC." `
-AuditDescription "AUDIT: Runs a fast (<3s) DISM /CheckHealth scan, checks the NTFS dirty bit via fsutil, and inspects CBS pending repair flags." `
-OnClick ({ Repair-SystemIntegrity -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
-OnAudit ({ Invoke-SystemHealthAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$rowWinSxS = New-UltixActionRow -Parent $tabWinSXS -Y 70 -MainRGB @(135, 50, 50) `
-Text "WinSxS Store Compression (ResetBase)" `
-Description "WinSxS Deep Clean: Permanently deletes superseded Windows Update backup layers (/ResetBase) to reclaim gigabytes of disk space." `
-AuditDescription "AUDIT: Streams real-time DISM AnalyzeComponentStore progress in a background Runspace and checks for pending CBS reboots." `
-OnClick ({ Optimize-WinSXS -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
-OnAudit ({
Write-GUI "--- AUDIT: CBS Component Store (Background Thread) ---"
Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
Update-Progress 5
$sb = (Get-Command -Name Get-WinSxSState).ScriptBlock
Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $allTabButtons.ToArray() -OnComplete ({
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
}.GetNewClosure())
}.GetNewClosure())
$rowWMI = New-UltixActionRow -Parent $tabWinSXS -Y 120 -MainRGB @(55, 58, 64) `
-Text "Verify & Salvage WMI Repository" `
-Description "WMI First-Aid: Verifies CIM repository consistency, runs non-destructive 'winmgmt /salvagerepository', and refreshes WMI performance counters." `
-AuditDescription "AUDIT: Runs 'winmgmt /verifyrepository' and tests live CIM queries against root\cimv2 and root\StandardCimv2." `
-OnClick ({ Repair-WMIRepository -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
-OnAudit ({ Invoke-WMIAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnFixWU = New-UltixButton -Parent $tabWinSXS -X 15 -Y 170 -RGB @(55, 58, 64) `
-Text "Reset Windows Update & CryptSvc" `
-Description "WU First-Aid: Stops wuauserv/bits/cryptSvc, purges corrupted qmgr*.dat queues, resets Catroot2 & DataStore, and batch re-registers 21 core COM DLLs." `
-OnClick ({ Repair-WindowsUpdateSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnNetFix = New-UltixButton -Parent $tabWinSXS -X 15 -Y 220 -RGB @(55, 58, 64) `
-Text "Refresh Network Stack (DNS / Winsock)" `
-Description "Network First-Aid: Flushes DNS cache, clears ARP tables, resets WinHTTP proxy, resets Winsock catalog, and resets TCP/IPv4 & IPv6 stack." `
-OnClick ({ Clear-NetworkStack -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnFixPrinters = New-UltixButton -Parent $tabWinSXS -X 15 -Y 270 -RGB @(55, 58, 64) `
-Text "Reset Print Subsystem (Spooler)" `
-Description "Printer First-Aid: Auto-unlocks Spooler if disabled, kills deadlocked spoolsv.exe, purges stuck .SPL/.SHD files, and restarts PrintWorkflowUserSvc." `
-OnClick ({ Repair-PrintSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnFixIcons = New-UltixButton -Parent $tabWinSXS -X 15 -Y 320 -RGB @(55, 58, 64) `
-Text "Rebuild Shell Icon & Thumbnail Cache" `
-Description "Shell First-Aid: Gracefully cycles Explorer, purges corrupted iconcache_*.db and thumbcache_*.db files, and forces a clean rebuild via ie4uinit." `
-OnClick ({ Clear-ShellIconCache -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnFixTime = New-UltixButton -Parent $tabWinSXS -X 15 -Y 370 -RGB @(55, 58, 64) `
-Text "Repair Time & NTP Clock Sync (w32time)" `
-Description "Time First-Aid: Enforces UTC hardware RTC clock (fixes dual-boot drift), re-registers W32Time, sets Cloudflare/NTP.org peers, and forces immediate clock resync." `
-OnClick ({ Repair-TimeSynchronization -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
$btnFixUwp = New-UltixButton -Parent $tabWinSXS -X 15 -Y 420 -RGB @(45, 85, 125) `
-Text "Repair UWP, Store & Gaming Services" `
-Description "UWP & Gaming First-Aid: Unlocks ClipSVC/AppXSvc/GamingServices, runs silent wsreset -i, and re-registers existing Shell, Store & Xbox manifests without restoring bloatware." `
-OnClick ({ Repair-UwpGamingRuntime -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())
foreach ($row in @($rowCheckSystem, $rowWinSxS, $rowWMI)) {
$allTabButtons.AddRange($row.Controls)
}
$allTabButtons.AddRange([System.Windows.Forms.Control[]]@(
$btnFixWU, $btnNetFix, $btnFixPrinters, $btnFixIcons, $btnFixTime, $btnFixUwp
))
$TabControl.Controls.Add($tabWinSXS)
}
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
function Get-CPUTopologyProfile {
if ($null -ne $script:UltixCpuTopology) {
return $script:UltixCpuTopology
}
$nativeCores  = @([WinUltix.CpuTopology]::GetProcessorCores())
$nativeCaches = @([WinUltix.CpuTopology]::GetL3Caches())
$logical = [int][Environment]::ProcessorCount
$cores   = if ($nativeCores.Count -gt 0) { $nativeCores.Count } else { [math]::Max(1, [int]($logical / 2)) }
$smt     = ($logical -gt $cores)
$name = (Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\Description\System\CentralProcessor\0" -Name "ProcessorNameString" -ErrorAction SilentlyContinue).ProcessorNameString
if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unknown CPU" }
$profileResult = $null
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
if ($null -eq $profileResult -and $name -match "AMD" -and $cores -eq 8) {
[int64]$c01Mask = if ($nativeCores.Count -ge 2) {
$nativeCores[0].Mask -bor $nativeCores[1].Mask
} elseif ($smt) { 15 } else { 3 }
$desc = if ($smt) { "Cores 0-1 (Threads 0-3)" } else { "Cores 0-1 (No SMT)" }
$profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$c01Mask; Label = "AMD 8C Single-CCD"; CoreDesc = $desc; SmtEnabled = $smt }
}
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
if ($null -eq $profileResult -and $cores -ge 6 -and $logical -ge 8) {
$shift = [math]::Max(0, ($logical - 4))
$maskVal = [int64]15 -shl $shift
$profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "Multi-Core CPU"; CoreDesc = "Tail Threads ($shift-$($logical - 1))"; SmtEnabled = $smt }
}
if ($null -eq $profileResult) {
$profileResult = [PSCustomObject]@{ IsSupported = $false; Mask = [System.IntPtr]15; Label = "Standard (<6C - Lasso Off)"; CoreDesc = "N/A"; SmtEnabled = $smt }
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
Write-GUI "    Red (>=55% C0) = Bottleneck (Offload $([char]0x2605) GPU/NIC to C1 in MSI Modal)`n"
}
function Get-HardwareState_Affinity {
$whitelist = @(
"systemsettings.exe", "shellexperiencehost.exe", "cmd.exe", "powershell.exe", "pwsh.exe",
"applicationframehost.exe", "rundll32.exe", "dllhost.exe", "ngciso.exe", "wmiadap.exe",
"csrss.exe", "lsass.exe", "smss.exe", "services.exe", "svchost.exe", "wininit.exe",
"winlogon.exe", "explorer.exe", "System", "Idle", "Registry", "dwm.exe", "fontdrvhost.exe",
"Taskmgr.exe", "conhost.exe", "sihost.exe", "taskhostw.exe", "RuntimeBroker.exe",
"SearchHost.exe", "StartMenuExperienceHost.exe", "SecurityHealthService.exe",
"SecurityHealthSystray.exe", "MsMpEng.exe", "NisSrv.exe", "LsaIso.exe", "audiodg.exe",
"WmiPrvSE.exe", "TiWorker.exe", "TrustedInstaller.exe", "spoolsv.exe", "WUDFHost.exe",
"System.exe", "Idle.exe", "Registry.exe", "Secure System.exe", "ctfmon.exe",
"MpDefenderCoreService.exe", "NVDisplay.Container.exe", "ShellHost.exe",
"iFiUsbAudioCpl.exe", "Windows11FirewallService.exe", "Windows11FirewallControl.exe",
"AmdPpkgSvc.exe", "nvcontainer.exe", "MoUsoCoreWorker.exe", "SearchIndexer.exe",
"smartscreen.exe", "AppActions.exe", "SDXHelper.exe", "QuickControls.exe",
"armsvc.exe", "BudsManager.exe", "WinUltix.exe"
)
$dictionary = @(
"Discord.exe", "Spotify.exe", "msedgewebview2.exe", "steamwebhelper.exe",
"EpicGamesLauncher.exe", "obs64.exe", "ArmouryCrate.exe", "iCUE.exe",
"Razer Synapse Service.exe", "firefox.exe", "chrome.exe", "msedge.exe",
"brave.exe", "opera.exe", "GalaxyClient.exe", "GOG Galaxy.exe", "EADesktop.exe",
"upc.exe", "Battle.net.exe", "WhatsApp.exe", "Telegram.exe", "Teams.exe",
"slack.exe", "Overwolf.exe", "LGHUB.exe", "LGHUB_Agent.exe", "MSIAfterburner.exe",
"RTSS.exe", "NZXT CAM.exe", "vgc.exe", "vgtray.exe", "OneDrive.exe"
)
$whitelistSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($w in $whitelist) { [void]$whitelistSet.Add($w) }
$topo = Get-CPUTopologyProfile
$targetMask = $topo.Mask
$liveProcsGrouped = @{}
$allProcs = @(Get-Process -ErrorAction SilentlyContinue)
try {
foreach ($p in $allProcs) {
$pName = "$($p.ProcessName).exe"
if (-not $liveProcsGrouped.ContainsKey($pName)) {
$liveProcsGrouped[$pName] = $p
} else {
$p.Dispose()
}
}
$configPath = "HKCU:\Software\WinUltix\AffinityLasso"
$savedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $configPath) {
$regProps = (Get-ItemProperty -LiteralPath $configPath -ErrorAction SilentlyContinue).PSObject.Properties
foreach ($prop in $regProps) {
if ($prop.Name -match '\.exe$') { [void]$savedSet.Add($prop.Name) }
}
}
$combinedMap = [ordered]@{}
foreach ($src in @($dictionary, @($savedSet), @($liveProcsGrouped.Keys))) {
foreach ($exe in $src) {
if ([string]::IsNullOrWhiteSpace($exe) -or $whitelistSet.Contains($exe)) { continue }
$keyLower = $exe.ToLowerInvariant()
if (-not $combinedMap.Contains($keyLower)) {
$combinedMap[$keyLower] = $exe
}
}
}
$listRunning  = [System.Collections.Generic.List[PSCustomObject]]::new()
$listSaved    = [System.Collections.Generic.List[PSCustomObject]]::new()
$listTemplate = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($app in $combinedMap.Values) {
$procName   = $app -replace '\.exe$', ''
$activeProc = $liveProcsGrouped[$app]
$isDetected = $savedSet.Contains($app)
if ($null -ne $activeProc) {
$procPath = [WinUltix.NativeMethods]::GetProcessExecutablePath([int]$activeProc.Id)
if ([string]::IsNullOrWhiteSpace($procPath)) {
if ($isDetected) {
$procPath = "[Protected Process]"
} else {
continue
}
}
$priority = "---"
try { $priority = $activeProc.PriorityClass.ToString() } catch { $priority = "Protected" }
$isLockedNow = $false
try { $isLockedNow = ($activeProc.ProcessorAffinity -eq $targetMask) } catch { }
$statusTag = if ($isLockedNow) { "[LOCKED]  " } else { "[RUNNING] " }
$listRunning.Add([PSCustomObject]@{
UIDisplayName = "$statusTag $app"
IsDetected    = $isDetected
Path          = $procPath
Priority      = $priority
ActionData    = @{ ExeName = $app; ProcName = $procName }
})
} elseif ($isDetected) {
$listSaved.Add([PSCustomObject]@{
UIDisplayName = "[SAVED]    $app"
IsDetected    = $true
Path          = "---"
Priority      = "---"
ActionData    = @{ ExeName = $app; ProcName = $procName }
})
} else {
$listTemplate.Add([PSCustomObject]@{
UIDisplayName = "[TEMPLATE] $app"
IsDetected    = $false
Path          = "---"
Priority      = "---"
ActionData    = @{ ExeName = $app; ProcName = $procName }
})
}
}
return @(($listRunning | Sort-Object UIDisplayName) + ($listSaved | Sort-Object UIDisplayName) + ($listTemplate | Sort-Object UIDisplayName))
} finally {
foreach ($p in $liveProcsGrouped.Values) {
if ($null -ne $p) { $p.Dispose() }
}
}
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
function Grant-UltixRegistryKeyAccess {
param([Parameter(Mandatory=$true)][string]$RegistryPath)
$subKeyPath = $RegistryPath -replace '^(?i)(HKLM:\\|Registry::HKEY_LOCAL_MACHINE\\)', ''
if ([string]::IsNullOrWhiteSpace($subKeyPath)) { return }
try {
[WinUltix.PrivilegeEnabler]::EnablePrivilege("SeTakeOwnershipPrivilege")
[WinUltix.PrivilegeEnabler]::EnablePrivilege("SeRestorePrivilege")
$adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
$keyOwn = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
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
$keyAcl = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
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
function Get-HardwareState_IRQ {
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
[int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
[uint64]$core0Mask  = if ($coreMasks.Count -ge 1) { [uint64]$coreMasks[0] } else { 3 }
$pciRoot   = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum\PCI", $false)
$enumRoot  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum", $false)
$svcRoot   = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services", $false)
$classRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Class", $false)
if ($null -eq $pciRoot) {
if ($null -ne $enumRoot)  { $enumRoot.Dispose() }
if ($null -ne $svcRoot)   { $svcRoot.Dispose() }
if ($null -ne $classRoot) { $classRoot.Dispose() }
return @()
}
$svcBinaryCache = @{}
try {
foreach ($venName in $pciRoot.GetSubKeyNames()) {
$venKey = $pciRoot.OpenSubKey($venName, $false)
if ($null -eq $venKey) { continue }
try {
foreach ($instName in $venKey.GetSubKeyNames()) {
$instanceId = "PCI\$venName\$instName"
if ([WinUltix.PnpTree]::GetDeviceConfigStatus($instanceId) -ne 0) { continue }
$instKey = $venKey.OpenSubKey($instName, $false)
if ($null -eq $instKey) { continue }
try {
$msiKey = $instKey.OpenSubKey("Device Parameters\Interrupt Management\MessageSignaledInterruptProperties", $false)
if ($null -eq $msiKey) { continue }
$msiVal = $null
try {
$msiVal = $msiKey.GetValue("MSISupported", $null)
} finally {
$msiKey.Dispose()
}
$rawDevName = [string]$instKey.GetValue("FriendlyName", "")
if ([string]::IsNullOrWhiteSpace($rawDevName)) { $rawDevName = [string]$instKey.GetValue("DeviceDesc", "") }
$devName = Format-UltixDeviceName -RawName $rawDevName
if ([string]::IsNullOrWhiteSpace($devName)) { $devName = "Unknown PCI Device" }
$svcName  = [string]$instKey.GetValue("Service", "")
$devClass = [string]$instKey.GetValue("Class", "")
$clsGuid  = [string]$instKey.GetValue("ClassGUID", "")
$locInfo  = [string]$instKey.GetValue("LocationInformation", "")
$isMsiEnabled = ($msiVal -eq 1)
$bdfTag = ""
if ($locInfo -match '\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)\s*$') {
$bdfTag = ("B{0:X2}:{1:X2}.{2}" -f [int]$matches[1], [int]$matches[2], [int]$matches[3])
}
$etwModuleKey = ""
$drvTag       = "N/A (Bus)"
if (-not [string]::IsNullOrWhiteSpace($svcName)) {
$etwModuleKey = $svcName.ToLowerInvariant()
$drvTag       = "$etwModuleKey.sys"
if ($null -ne $svcRoot) {
if (-not $svcBinaryCache.ContainsKey($svcName)) {
$resolvedMod = $svcName.ToLowerInvariant()
$sKey = $svcRoot.OpenSubKey($svcName, $false)
if ($null -ne $sKey) {
try {
$imgPath = [string]$sKey.GetValue("ImagePath", "")
if ($imgPath -match '(?i)([^\\]+\.sys)\b') {
$resolvedMod = [System.IO.Path]::GetFileNameWithoutExtension($matches[1]).ToLowerInvariant()
}
} finally {
$sKey.Dispose()
}
}
$svcBinaryCache[$svcName] = $resolvedMod
}
$etwModuleKey = $svcBinaryCache[$svcName]
$drvTag       = "$etwModuleKey.sys"
}
}
$prioVal   = $null
$policyVal = $null
[byte[]]$maskBytes = $null
$affKey = $instKey.OpenSubKey("Device Parameters\Interrupt Management\Affinity Policy", $false)
if ($null -ne $affKey) {
try {
$prioVal   = $affKey.GetValue("InterruptPriority", $null)
$policyVal = $affKey.GetValue("DevicePolicy", $null)
$maskBytes = $affKey.GetValue("AssignmentSetOverride", $null)
} finally {
$affKey.Dispose()
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
$coreHint = ""
for ($cIdx = 0; $cIdx -lt $coreMasks.Count; $cIdx++) {
$cm = [uint64]$coreMasks[$cIdx]
if ($maskInt -ne 0 -and (($maskInt -band $cm) -eq $maskInt)) {
$coreHint = " (C$cIdx)"
break
}
}
if ([string]::IsNullOrEmpty($coreHint) -and ($maskInt -band $core0Mask) -ne 0) {
$coreHint = " (C0+)"
}
$affLabel = "0x$($maskInt.ToString('X'))$coreHint"
} elseif ($policyVal -eq 5) {
$affLabel = "Spread"
}
$isOnCore0 = ($policyVal -ne 5) -and (($policyVal -ne 4) -or (($maskInt -band $core0Mask) -ne 0))
$isGpu     = ($devClass -match '^(?i)Display$' -or $clsGuid -match '(?i)4d36e968-e325-11ce-bfc1-08002be10318' -or $svcName -match '^(?i)(nvlddmkm|amdkmdag|amdwddmg|igfx|igfxn)$' -or $devName -match '(?i)(GeForce|Radeon|Arc |HD Graphics|UHD Graphics|Iris)')
$isNic     = ($devClass -match '^(?i)Net$' -or $clsGuid -match '(?i)4d36e972-e325-11ce-bfc1-08002be10318' -or $devName -match '(?i)(Ethernet|GbE|Network|Wi-Fi|WiFi|Wireless|802\.11|I219|I225|I226|Killer|Realtek PCI|AQtion|ConnectX)')
$isUsb     = ($devClass -match '^(?i)USB$' -or $clsGuid -match '(?i)36fc9e60-c465-11cf-8056-444553540000' -or $svcName -match '^(?i)(USBXHCI|USB4|usbuhci|usbehci)$' -or $devName -match '(?i)(eXtensible Host|Enhanced Host|USB4)')
$isStorage = ($policyVal -eq 5 -or $clsGuid -match '(?i)(4d36e96a|4d36e97b)-e325-11ce-bfc1-08002be10318' -or $svcName -match '^(?i)(stornvme|secnvme|storahci|iaStor)' -or $devName -match '(?i)(NVM Express|SATA AHCI)')
$isAudio   = ($devClass -match '^(?i)(MEDIA|Sound)$' -or $clsGuid -match '(?i)4d36e96c-e325-11ce-bfc1-08002be10318' -or $svcName -match '^(?i)(HDAudBus|IntcAzAudAddService|IntcOED)$' -or $devName -match '(?i)High Definition Audio')
if ($isStorage -and $null -ne $enumRoot) {
$diskNames = [System.Collections.Generic.List[string]]::new()
foreach ($descEntry in ([WinUltix.PnpTree]::GetDescendants($instanceId))) {
$childId = ($descEntry -split '\|', 2)[1]
if ([string]::IsNullOrWhiteSpace($childId)) { continue }
$childKey = $enumRoot.OpenSubKey($childId, $false)
if ($null -ne $childKey) {
try {
$cClass = [string]$childKey.GetValue("Class", "")
$cName  = [string]$childKey.GetValue("FriendlyName", "")
if ($cClass -eq "DiskDrive" -and -not [string]::IsNullOrWhiteSpace($cName)) {
$shortDisk = ($cName -replace '(?i)\s*(SCSI Disk Device|NVMe Disk Device|ATA Device)\s*$', '').Trim()
if ($shortDisk.Length -gt 22) { $shortDisk = $shortDisk.Substring(0, 22).Trim() }
$diskNames.Add($shortDisk)
}
} finally {
$childKey.Dispose()
}
}
}
$shortCtrl = if ($svcName -match '^(?i)(stornvme|secnvme)$' -or $rawDevName -match '^(?i)@stornvme\.inf,') {
"NVMe Controller"
} elseif ($svcName -match '^(?i)(storahci|iaStor)' -or $rawDevName -match '^(?i)@mshdc\.inf,') {
"SATA AHCI Controller"
} else {
($devName -replace '^(?i)(Standard|Standardowy)\s+', '').Trim()
}
if ($diskNames.Count -gt 0) {
$devName = "$shortCtrl [$($diskNames -join ', ')]"
} elseif (-not [string]::IsNullOrEmpty($bdfTag)) {
$devName = "$shortCtrl [Empty $bdfTag]"
} else {
$devName = $shortCtrl
}
} elseif ($isUsb -and -not [string]::IsNullOrEmpty($bdfTag)) {
$shortUsb = ($devName -replace '(?i)^(Rozszerzalny kontroler hosta|Kontroler hosta)\s+', '' -replace '\s*[----]\s*\d+[\.,]\d+\s*\(Microsoft\)', '' -replace '\s*\(Microsoft\)', '' -replace '(?i)eXtensible Host Controller', 'XHCI').Trim()
if ($shortUsb -notmatch '(?i)XHCI' -and $svcName -match '^(?i)USBXHCI$') {
$shortUsb = "$shortUsb XHCI"
}
$devName = "$shortUsb [$bdfTag]"
} elseif ($isAudio) {
$codecNames = [System.Collections.Generic.List[string]]::new()
if ($null -ne $enumRoot) {
foreach ($descEntry in ([WinUltix.PnpTree]::GetDescendants($instanceId))) {
$childId = ($descEntry -split '\|', 2)[1]
if ([string]::IsNullOrWhiteSpace($childId)) { continue }
$childKey = $enumRoot.OpenSubKey($childId, $false)
if ($null -ne $childKey) {
try {
$cClass   = [string]$childKey.GetValue("Class", "")
$cDrvRel  = [string]$childKey.GetValue("Driver", "")
$cRawDesc = [string]$childKey.GetValue("DeviceDesc", "")
if ($cClass -notmatch '^(?i)(MEDIA|Sound)$' -and $childId -notmatch '^(?i)(HDAUDIO|INTELAUDIO|ACP)\\') { continue }
$cInfPath  = ""
$cResolved = [string]$childKey.GetValue("FriendlyName", "")
if ($null -ne $classRoot -and -not [string]::IsNullOrWhiteSpace($cDrvRel)) {
$cDrvKey = $classRoot.OpenSubKey($cDrvRel, $false)
if ($null -ne $cDrvKey) {
try {
$cInfPath = [string]$cDrvKey.GetValue("InfPath", "")
if ([string]::IsNullOrWhiteSpace($cResolved)) {
$cResolved = [string]$cDrvKey.GetValue("DriverDesc", "")
}
} finally {
$cDrvKey.Dispose()
}
}
}
if ([string]::IsNullOrWhiteSpace($cResolved)) {
$cResolved = Format-UltixDeviceName -RawName $cRawDesc
}
$isGenericInbox = ($cRawDesc -match '^(?i)@hdaudio\.inf,' -or $cInfPath -match '^(?i)hdaudio\.inf$')
$cClean = ($cResolved -replace '(?i)\(R\)|\(TM\)', '' -replace '(?i)\s*High Definition Audio(\s+Device|\s+Controller)?', ' HD Audio' -replace '(?i)\s*Audio Device\s*$', ' Audio' -replace '\s+', ' ').Trim()
if ($isGenericInbox -or [string]::IsNullOrWhiteSpace($cClean) -or $cClean -match '^(?i)(HD Audio|Microsoft.*|Urządzenie.*|Kontroler.*)$') {
$cClean = if ($childId -match 'VEN_10DE')     { "NVIDIA HD Audio" }
elseif ($childId -match 'VEN_10EC')           { "Realtek HD Audio" }
elseif ($childId -match 'VEN_1002')           { "AMD HDMI Audio" }
elseif ($childId -match 'VEN_8086')           { "Intel Display Audio" }
elseif ($childId -match 'VEN_1102')           { "Creative Audio" }
elseif ($childId -match 'VEN_13F6')           { "C-Media Audio" }
elseif ($childId -match 'VEN_14F1')           { "Conexant Audio" }
elseif ($childId -match 'VEN_1106')           { "VIA HD Audio" }
else { "" }
}
if (-not [string]::IsNullOrWhiteSpace($cClean) -and -not $codecNames.Contains($cClean)) {
$codecNames.Add($cClean)
}
} finally {
$childKey.Dispose()
}
}
}
}
if ($codecNames.Count -eq 0) {
$pciAudioVendor = if ($venName -match 'VEN_10DE')                        { "NVIDIA GPU Audio" }
elseif ($venName -match 'VEN_1002')                                      { "AMD HDMI Audio" }
elseif ($venName -match 'VEN_1022&DEV_(1640|1637|15DE)')                 { "AMD Display Audio" }
elseif ($venName -match 'VEN_1022')                                      { "AMD SoC Audio" }
elseif ($venName -match 'VEN_8086')                                      { "Intel PCH Audio" }
elseif ($venName -match 'VEN_1102')                                      { "Creative Audio" }
else                                                                     { "PCI Audio" }
$fallbackLabel = if (-not [string]::IsNullOrEmpty($bdfTag)) { "$pciAudioVendor $bdfTag" } else { $pciAudioVendor }
$codecNames.Add($fallbackLabel)
}
$shortAudio = if ($svcName -match '^(?i)HDAudBus$' -or $rawDevName -match '^(?i)@hdaudbus\.inf,' -or $devName -match '(?i)High Definition Audio') {
"HD Audio"
} else {
$devName.Trim()
}
$joinedCodecs = ($codecNames -join ', ')
if ($shortAudio -notmatch [regex]::Escape($joinedCodecs)) {
$devName = "$shortAudio [$joinedCodecs]"
}
}
$deviceRole    = "Other"
$sortRank      = 50
$adviceText    = "Standard PCI Bus"
$isRecommended = $false
if ($isGpu) {
$deviceRole = "GPU"
if ($isOnCore0) {
$sortRank      = 1
$isRecommended = $true
$adviceText    = "$([char]0x2605) OFFLOAD TO C1 (Heavy GPU DPC)"
} else {
$sortRank   = 3
$adviceText = "$([char]0x2713) Offloaded (Drives dxgkrnl)"
}
} elseif ($isNic) {
$deviceRole = "NIC"
if ($isOnCore0) {
$sortRank      = 2
$isRecommended = $true
$adviceText    = "$([char]0x2605) OFFLOAD TO C1 (Drives ndis.sys)"
} else {
$sortRank   = 4
$adviceText = "$([char]0x2713) Offloaded (Drives ndis.sys)"
}
} elseif ($isUsb) {
$deviceRole = "USB"
if ($isOnCore0) {
$sortRank   = 10
$adviceText = "Optional C1 (HID via Wdf01000)"
} else {
$sortRank   = 11
$adviceText = "$([char]0x2713) Offloaded (HID via Wdf01000)"
}
} elseif ($isStorage) {
$deviceRole = "Storage"
$sortRank   = 20
$adviceText = "Keep Spread (Multi-Queue I/O)"
} elseif ($isAudio) {
$deviceRole = "Audio"
$sortRank   = 30
$adviceText = "Audio Bus (Keep Default MSI)"
}
$msiBadge     = if ($isMsiEnabled) { "ON" } else { "OFF" }
$instFullPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId"
$irqMgmtPath  = "$instFullPath\Device Parameters\Interrupt Management"
$results.Add([PSCustomObject]@{
UIDisplayName        = "$devName [MSI: $msiBadge | Prio: $prioLabel | Mask: $affLabel | $adviceText]"
MsiStatus            = $msiBadge
RawDeviceName        = $devName
BdfTag               = $bdfTag
DeviceRole           = $deviceRole
ServiceName          = $etwModuleKey
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
IrqMgmtPath  = $irqMgmtPath
Path         = "$irqMgmtPath\MessageSignaledInterruptProperties"
AffinityPath = "$irqMgmtPath\Affinity Policy"
DevicePath   = $instFullPath
}
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
if ($null -ne $enumRoot)  { $enumRoot.Dispose() }
if ($null -ne $svcRoot)   { $svcRoot.Dispose() }
if ($null -ne $classRoot) { $classRoot.Dispose() }
}
$nameCounts = @{}
foreach ($r in $results) {
$n = $r.RawDeviceName
$nameCounts[$n] = if ($nameCounts.ContainsKey($n)) { $nameCounts[$n] + 1 } else { 1 }
}
foreach ($r in $results) {
if ($nameCounts[$r.RawDeviceName] -gt 1 -and -not [string]::IsNullOrEmpty($r.BdfTag) -and $r.RawDeviceName -notmatch [regex]::Escape($r.BdfTag)) {
$r.RawDeviceName = "$($r.RawDeviceName) ($($r.BdfTag))"
$r.UIDisplayName = "$($r.RawDeviceName) [MSI: $($r.MsiStatus) | Prio: $($r.PrioLabel) | Mask: $($r.AffinityLabel) | $($r.AdviceText)]"
}
}
return @($results | Sort-Object SortRank, RawDeviceName)
}
function Get-HardwareState_WHEA {
if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
[int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
$coreCount = $coreMasks.Count
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
$apicId   = "N/A"
$coreInfo = ""
$msg      = $evt.Message
$id       = $evt.Id
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
$lpIdx = [int]$apicId
$matchedCore = -1
if ($lpIdx -ge 0 -and $lpIdx -lt 63) {
$threadBit = ([int64]1 -shl $lpIdx)
for ($c = 0; $c -lt $coreCount; $c++) {
if (($coreMasks[$c] -band $threadBit) -ne 0) {
$matchedCore = $c
break
}
}
}
if ($matchedCore -ge 0) {
$coreInfo = "(Core $matchedCore)"
} else {
$coreInfo = "(LP#$lpIdx)"
}
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
$tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
$tcpNoDelay = (Get-ItemProperty -Path $tcpPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay
$tcpAck = (Get-ItemProperty -Path $tcpPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency
$isTcpOpt = ($tcpNoDelay -eq 1 -and $tcpAck -eq 1)
$results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] TCPNoDelay & AckFrequency"; IsOptimized = $isTcpOpt; ActionData = @{ Type="TCP"; AdapterName=$name; InterfaceGuid=$adapter.InterfaceGuid } })
$enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnPDeviceID)"
$caps = (Get-ItemProperty -Path $enumPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
$isPowerOpt = ($caps -eq 24)
$results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Power Management (Sleep)"; IsOptimized = $isPowerOpt; ActionData = @{ Type="Power"; RegPath=$enumPath; InterfaceGuid=$adapter.InterfaceGuid } })
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
$val = (Get-ItemProperty -LiteralPath $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
$isGlobalOpt = ($null -ne $val -and $val -eq 1)
$results.Add([PSCustomObject]@{
UIDisplayName = "Global Timer Resolution (Kernel Fix)"
IsOptimized   = $isGlobalOpt
ActionData    = @{ Type = "Reg"; Path = $regPath; Name = "GlobalTimerResolutionRequests"; Value = 1 }
})
$hpetInstance = $null
$hpetRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\PNP0103"
if (Test-Path -LiteralPath $hpetRoot) {
foreach ($sub in (Get-ChildItem -LiteralPath $hpetRoot -ErrorAction SilentlyContinue)) {
$candId = "ACPI\PNP0103\$($sub.PSChildName)"
if ([WinUltix.PnpTree]::GetDeviceConfigStatus($candId) -ge 0) {
$hpetInstance = $candId
break
}
}
}
if (-not [string]::IsNullOrWhiteSpace($hpetInstance)) {
$isHpetDisabled = [WinUltix.PnpTree]::IsDeviceDisabled($hpetInstance)
$results.Add([PSCustomObject]@{
UIDisplayName = "Disable HPET (Device Manager)"
IsOptimized   = $isHpetDisabled
ActionData    = @{ Type = "PNP"; Instance = $hpetInstance }
})
}
$bcdVerbose = (bcdedit.exe /enum "{current}" /v 2>$null) -join " "
$dynTickOpt   = $false
$platClockOpt = $true
if ($bcdVerbose -match '(\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\})') {
$bcdElemBase = "HKLM:\BCD00000000\Objects\$($matches[1])\Elements"
if (Test-Path -LiteralPath $bcdElemBase) {
[byte[]]$dynBytes = (Get-ItemProperty -LiteralPath "$bcdElemBase\250000f0" -Name "Element" -ErrorAction SilentlyContinue).Element
if ($null -ne $dynBytes -and $dynBytes.Length -ge 1) {
$dynTickOpt = ($dynBytes[0] -eq 1)
}
[byte[]]$platBytes = (Get-ItemProperty -LiteralPath "$bcdElemBase\250000c2" -Name "Element" -ErrorAction SilentlyContinue).Element
if ($null -ne $platBytes -and $platBytes.Length -ge 1 -and $platBytes[0] -eq 1) {
$platClockOpt = $false
}
} else {
$dynTickOpt   = ($bcdVerbose -match "(?i)disabledynamictick\s+(Yes|Tak|Ja|Oui|S[i\u00ED]|True|1)")
$platClockOpt = (-not ($bcdVerbose -match "(?i)useplatformclock\s+(Yes|Tak|Ja|Oui|S[i\u00ED]|True|1)"))
}
}
$results.Add([PSCustomObject]@{
UIDisplayName = "Disable Dynamic Tick (Power Saving)"
IsOptimized   = $dynTickOpt
ActionData    = @{ Type = "BCD"; Cmd = "disabledynamictick yes" }
})
$results.Add([PSCustomObject]@{
UIDisplayName = "Disable Platform Clock (Force TSC)"
IsOptimized   = $platClockOpt
ActionData    = @{ Type = "BCD"; Cmd = "useplatformclock no" }
})
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
$aspm = (Get-ItemProperty -LiteralPath $pciPath -Name "DisableASPM" -ErrorAction SilentlyContinue).DisableASPM
$isAspmOpt = ($null -ne $aspm -and $aspm -eq 1)
$results.Add([PSCustomObject]@{ UIDisplayName = "PCIe ASPM Global Bus Lock (DisableASPM)"; IsOptimized = $isAspmOpt; ActionData = @{ Type="Reg"; Path=$pciPath; Name="DisableASPM"; Val=1 } })
$nvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
$nvmeIdle = (Get-ItemProperty -LiteralPath $nvmePath -Name "IdlePowerMode" -ErrorAction SilentlyContinue).IdlePowerMode
$isNvmeIdleOpt = ($null -ne $nvmeIdle -and $nvmeIdle -eq 0)
$results.Add([PSCustomObject]@{ UIDisplayName = "StorNVMe APST Driver Lock (IdlePowerMode)"; IsOptimized = $isNvmeIdleOpt; ActionData = @{ Type="Reg"; Path=$nvmePath; Name="IdlePowerMode"; Val=0 } })
$mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
$isMemOpt = ($null -ne $mmAgent -and $mmAgent.MemoryCompression -eq $false)
$results.Add([PSCustomObject]@{ UIDisplayName = "System Memory Compression (MMAgent)"; IsOptimized = $isMemOpt; ActionData = @{ Type="MMAgent" } })
return @($results)
}
function Set-AppAffinity {
param([array]$SelectedItems, [bool]$Execute = $true)
if ($SelectedItems.Count -eq 0) { return }
$topo = Get-CPUTopologyProfile
$targetMask = $topo.Mask
$configPath = "HKCU:\Software\WinUltix\AffinityLasso"
if (-not (Test-Path -LiteralPath $configPath)) { New-Item -Path $configPath -Force -ErrorAction SilentlyContinue | Out-Null }
foreach ($item in $SelectedItems) {
$exeName  = $item.ActionData.ExeName
$procName = $item.ActionData.ProcName
Set-ItemProperty -LiteralPath $configPath -Name $exeName -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
if ($Execute) {
$procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
try {
Write-GUI " -> Live Locking ($($topo.CoreDesc)): $exeName ($($procs.Count) instances)"
foreach ($p in $procs) {
try {
$p.ProcessorAffinity = $targetMask
$p.PriorityClass     = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
} catch {
Write-GUI "    [!] Access denied: PID $($p.Id) (System lock)"
}
}
} finally {
foreach ($p in $procs) { if ($null -ne $p) { $p.Dispose() } }
}
} else {
Write-GUI " -> Saved to config (Currently not running): $exeName"
}
} else {
Write-GUI " -> Saved to Target Roster: $exeName"
}
}
}
function Remove-AppAffinity {
param([array]$SelectedItems, [bool]$Execute = $true, [bool]$KeepConfig = $false)
if ($SelectedItems.Count -eq 0) { return }
$configPath     = "HKCU:\Software\WinUltix\AffinityLasso"
$lpCount        = [Environment]::ProcessorCount
$fullMaskVal    = if ($lpCount -ge 64) { -1 } else { ([int64]1 -shl $lpCount) - 1 }
$systemAffinity = [System.IntPtr]$fullMaskVal
foreach ($item in $SelectedItems) {
$exeName  = $item.ActionData.ExeName
$procName = $item.ActionData.ProcName
if (-not $KeepConfig -and (Test-Path -LiteralPath $configPath)) {
Remove-ItemProperty -LiteralPath $configPath -Name $exeName -Force -ErrorAction SilentlyContinue
}
if ($Execute) {
$procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
try {
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
$p.PriorityClass     = [System.Diagnostics.ProcessPriorityClass]::Normal
} catch { }
}
}
} finally {
foreach ($p in $procs) { if ($null -ne $p) { $p.Dispose() } }
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
if (-not (Test-Path -LiteralPath $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
Set-ItemProperty -LiteralPath $data.Path -Name $data.Name -Value $data.Value -Type DWord -Force -ErrorAction Stop
} elseif ($data.Type -eq "BCD") {
$cmdArgs = $data.Cmd.Split(' ')
if ($cmdArgs[0] -eq "useplatformclock" -and $cmdArgs[1] -eq "no") {
$null = & bcdedit.exe /deletevalue "{current}" useplatformclock 2>&1
} else {
$null = & bcdedit.exe /set "{current}" $cmdArgs[0] $cmdArgs[1] 2>&1
}
} elseif ($data.Type -eq "PNP") {
$null = & pnputil.exe /disable-device "$($data.Instance)" 2>&1
if (-not [WinUltix.PnpTree]::IsDeviceDisabled($data.Instance)) {
throw "pnputil failed to disable $($data.Instance)"
}
}
} catch {
Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)"
}
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
if (-not (Test-Path -LiteralPath $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
Set-ItemProperty -LiteralPath $data.Path -Name $data.Name -Value $data.Val -Type DWord -Force -ErrorAction Stop
} elseif ($data.Type -eq "MMAgent") {
Disable-MMAgent -MemoryCompression -ErrorAction Stop
}
} catch {
Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)"
Write-GUI "    [DEBUG] $($_.Exception.Message)"
}
}
}
function Export-UltixHardwareSnapshot {
$affRoster = [System.Collections.Generic.List[string]]::new()
$affPath   = "HKCU:\Software\WinUltix\AffinityLasso"
if (Test-Path -LiteralPath $affPath) {
$regObj = Get-Item -LiteralPath $affPath -ErrorAction SilentlyContinue
if ($null -ne $regObj) {
try {
foreach ($p in $regObj.Property) {
if ($p -match '\.exe$') { $affRoster.Add($p) }
}
} finally {
$regObj.Dispose()
}
}
}
$cppcUnhidden = @(Get-HardwareState_CPPC | Where-Object { -not $_.IsDetected } | ForEach-Object { [string]$_.ActionData.KeyId })
$timerOpt     = @(Get-HardwareState_Timer | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)
$nvmeOpt      = @(Get-HardwareState_NVMe  | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)
$globalNet = [System.Collections.Generic.List[string]]::new()
$offload   = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
if ($null -ne $offload) {
if ($offload.ReceiveSideScaling -eq 'Enabled')          { $globalNet.Add("[Global] TCP Receive-Side Scaling (RSS)") }
if ($offload.ReceiveSegmentCoalescing -eq 'Disabled')   { $globalNet.Add("[Global] TCP Recv Segment Coalescing (RSC)") }
}
return [ordered]@{
AffinityLasso = @($affRoster)
CPPCUnhidden  = @($cppcUnhidden)
TimerTweaks   = @($timerOpt)
NVMeTweaks    = @($nvmeOpt)
GlobalNetwork = @($globalNet)
}
}
function Import-UltixHardwareSnapshot {
param([Parameter(Mandatory=$true)]$ProfileData)
$affList = @($ProfileData.AffinityLasso)
if ($affList.Count -gt 0) {
$affPath = "HKCU:\Software\WinUltix\AffinityLasso"
if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force | Out-Null }
$affItems = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($exe in $affList) {
if ([string]::IsNullOrWhiteSpace($exe)) { continue }
Set-ItemProperty -LiteralPath $affPath -Name $exe -Value 1 -Type DWord -Force
$affItems.Add([PSCustomObject]@{
ActionData = @{
ExeName  = [string]$exe
ProcName = ([string]$exe -replace '\.exe$', '')
}
})
}
$topo = Get-CPUTopologyProfile
if ($topo.IsSupported -and $affItems.Count -gt 0) {
Set-AppAffinity -SelectedItems @($affItems) -Execute $true
} else {
Write-GUI " -> Restored $($affList.Count) process(es) to Affinity Lasso roster."
}
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
function Show-AffinityModal {
param ([string]$Title, [string]$Description)
$modal = New-Object System.Windows.Forms.Form
$modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 720); $modal.MinimumSize = New-Object System.Drawing.Size(850, 720); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
$btnRefresh = New-UltixButton -Parent $modal -Text "Refresh List" -X 715 -Y 15 -Width 100 -Height 35 -RGB @(60, 100, 150)
$btnRefresh.Anchor = 'Top, Right'
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, 60)
$listView.Size = New-Object System.Drawing.Size(800, 480)
$listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
$listView.BorderStyle = "FixedSingle"
$listView.Font = New-Object System.Drawing.Font("Consolas", 10.5)
$listView.Anchor = 'Top, Bottom, Left, Right'
$listView.View = [System.Windows.Forms.View]::Details
$listView.CheckBoxes = $true
$listView.FullRowSelect = $true
$listView.GridLines = $false
Enable-UltixDoubleBuffer -Control $listView
$listView.Columns.Add("Status & App Name", 250) | Out-Null
$listView.Columns.Add("Priority", 110) | Out-Null
$listView.Columns.Add("Executable Path", 415) | Out-Null
$bgEven = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$bgOdd  = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
$localData = New-Object System.Collections.ArrayList
$refreshData = {
$listView.BeginUpdate()
$listView.Items.Clear(); $localData.Clear()
$auditData = Get-HardwareState_Affinity
$rIdx = 0
foreach ($item in $auditData) {
[void]$localData.Add($item)
$lvItem = New-Object System.Windows.Forms.ListViewItem($item.UIDisplayName)
$lvItem.SubItems.Add($item.Priority)
$lvItem.SubItems.Add($item.Path)
$lvItem.Checked = $item.IsDetected
$lvItem.BackColor = if (($rIdx % 2) -eq 0) { $bgEven } else { $bgOdd }
if ($item.UIDisplayName -match '^\[LOCKED\]') {
$lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 145, 230, 165)
} elseif ($item.UIDisplayName -match '^\[RUNNING\]') {
$lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 175, 215, 250)
} elseif ($item.UIDisplayName -match '^\[SAVED\]') {
$lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 225, 232)
} else {
$lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 148, 158)
}
[void]$listView.Items.Add($lvItem)
$rIdx++
}
$listView.EndUpdate()
}
&$refreshData
$btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())
$txtCustom = New-Object System.Windows.Forms.TextBox; $txtCustom.Location = New-Object System.Drawing.Point(15, 555); $txtCustom.Size = New-Object System.Drawing.Size(250, 25); $txtCustom.BackColor = [System.Drawing.Color]::FromArgb(255, 38, 40, 45); $txtCustom.ForeColor = [System.Drawing.Color]::White; $txtCustom.BorderStyle = "FixedSingle"; $txtCustom.Font = New-Object System.Drawing.Font("Segoe UI", 10); $txtCustom.Anchor = 'Bottom, Left'
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
$toRemove = @()
foreach ($item in $listView.SelectedItems) {
if ($item.Index -ge 0 -and $item.Index -lt $localData.Count) {
$toRemove += $localData[$item.Index]
}
}
if ($toRemove.Count -gt 0) {
Remove-AppAffinity -SelectedItems $toRemove -Execute $true -KeepConfig $false
&$refreshData
}
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
$chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 60); $chkList.Size = New-Object System.Drawing.Size(600, 280); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
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
$modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(1280, 800); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
$modal.MinimumSize = New-Object System.Drawing.Size(1180, 700)
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 10); $lblDesc.Size = New-Object System.Drawing.Size(1235, 22); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
$lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply new MSI vectors, Interrupt Priority, and Core Affinity."; $lblWarning.Location = New-Object System.Drawing.Point(15, 34); $lblWarning.Size = New-Object System.Drawing.Size(1235, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'
$lblDpcMonitor = New-Object System.Windows.Forms.Label
$lblDpcMonitor.Location = New-Object System.Drawing.Point(15, 58)
$lblDpcMonitor.Size = New-Object System.Drawing.Size(1235, 84)
$lblDpcMonitor.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
$lblDpcMonitor.ForeColor = [System.Drawing.Color]::LightSkyBlue
$lblDpcMonitor.Font = New-Object System.Drawing.Font("Consolas", 9.0, [System.Drawing.FontStyle]::Bold)
$lblDpcMonitor.TextAlign = "TopLeft"
$lblDpcMonitor.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 4)
$lblDpcMonitor.BorderStyle = "FixedSingle"
$lblDpcMonitor.Anchor = 'Top, Left, Right'
$lblDpcLegend = New-Object System.Windows.Forms.Label
$lblDpcLegend.Text = "Metrics: Avg Load = Session average ($([char]0x00B5)s/s) | Max = Worst single-call latency spike ($([char]0x00B5)s) | 1s = Last second total ($([char]0x00B5)s/s) | Colors: Orange (Max >=350 $([char]0x00B5)s) | Red (Max >=1000 $([char]0x00B5)s)"
$lblDpcLegend.Location = New-Object System.Drawing.Point(15, 145)
$lblDpcLegend.Size = New-Object System.Drawing.Size(1235, 18)
$lblDpcLegend.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
$lblDpcLegend.ForeColor = [System.Drawing.Color]::DarkGray
$lblDpcLegend.Anchor = 'Top, Left, Right'
$lblPrio = New-Object System.Windows.Forms.Label
$lblPrio.Text = "Priority:"
$lblPrio.Location = New-Object System.Drawing.Point(15, 170)
$lblPrio.Size = New-Object System.Drawing.Size(55, 22)
$lblPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblPrio.ForeColor = [System.Drawing.Color]::LightSkyBlue
$comboPrio = New-Object System.Windows.Forms.ComboBox
$comboPrio.Location = New-Object System.Drawing.Point(72, 167)
$comboPrio.Size = New-Object System.Drawing.Size(140, 25)
$comboPrio.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$comboPrio.ForeColor = [System.Drawing.Color]::White
$comboPrio.DropDownStyle = "DropDownList"
$comboPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
[void]$comboPrio.Items.AddRange(@("Keep Current", "High (3)", "Normal (2)", "Low (1)", "Undefined (Default)"))
$comboPrio.SelectedIndex = 0
$chkOffloadCore0 = New-Object System.Windows.Forms.CheckBox
$chkOffloadCore0.Text = "Offload C0 -> C1"
$chkOffloadCore0.Location = New-Object System.Drawing.Point(222, 168)
$chkOffloadCore0.Size = New-Object System.Drawing.Size(135, 24)
$chkOffloadCore0.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$chkOffloadCore0.ForeColor = [System.Drawing.Color]::LightGray
$chkOffloadCore0.Checked = $false
$chkShowKernel = New-Object System.Windows.Forms.CheckBox
$chkShowKernel.Text = "Show OS Kernel .sys"
$chkShowKernel.Location = New-Object System.Drawing.Point(362, 168)
$chkShowKernel.Size = New-Object System.Drawing.Size(150, 24)
$chkShowKernel.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$chkShowKernel.ForeColor = [System.Drawing.Color]::Cyan
$chkShowKernel.Checked = $true
$lblSort = New-Object System.Windows.Forms.Label
$lblSort.Text = "Sort By:"
$lblSort.Location = New-Object System.Drawing.Point(518, 170)
$lblSort.Size = New-Object System.Drawing.Size(52, 22)
$lblSort.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblSort.ForeColor = [System.Drawing.Color]::LightSkyBlue
$comboSort = New-Object System.Windows.Forms.ComboBox
$comboSort.Location = New-Object System.Drawing.Point(572, 167)
$comboSort.Size = New-Object System.Drawing.Size(225, 25)
$comboSort.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$comboSort.ForeColor = [System.Drawing.Color]::White
$comboSort.DropDownStyle = "DropDownList"
$comboSort.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
[void]$comboSort.Items.AddRange(@(
"Default (Offload Advice $([char]0x2605))",
"Avg Driver Load ($([char]0x00B5)s/s) [Reliable]",
"Peak Driver Spike (Max $([char]0x00B5)s)",
"Live 1s Driver Load ($([char]0x00B5)s/s)",
"Device / Subsystem Name (A-Z)",
"Driver Name (.sys)"
))
$comboSort.SelectedIndex = 0
$btnResetStats = New-UltixButton -Parent $modal -Text "Reset Stats" -X 940 -Y 166 -Width 110 -Height 27 -RGB @(65, 70, 78)
$btnResetStats.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnResetStats.Anchor = 'Top, Right'
$btnSelRec = New-UltixButton -Parent $modal -Text "Select $([char]0x2605) GPU/NIC" -X 1060 -Y 166 -Width 190 -Height 27 -RGB @(50, 85, 120)
$btnSelRec.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnSelRec.Anchor = 'Top, Right'
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, 200)
$listView.Size = New-Object System.Drawing.Size(1235, 498)
$listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 236, 242)
$listView.BorderStyle = "FixedSingle"
$listView.Font = New-Object System.Drawing.Font("Consolas", 9.0)
$listView.View = [System.Windows.Forms.View]::Details
$listView.CheckBoxes = $true
$listView.FullRowSelect = $true
$listView.GridLines = $false
$listView.Anchor = 'Top, Bottom, Left, Right'
Enable-UltixDoubleBuffer -Control $listView
$bgEven   = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$bgOdd    = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
$bgRec    = [System.Drawing.Color]::FromArgb(255, 44, 38, 22)
$bgWarn   = [System.Drawing.Color]::FromArgb(255, 48, 36, 20)
$bgSpike  = [System.Drawing.Color]::FromArgb(255, 54, 26, 28)
$fgPciOk  = [System.Drawing.Color]::FromArgb(255, 225, 232, 240)
$fgMsiOff = [System.Drawing.Color]::FromArgb(255, 165, 205, 245)
$fgRec    = [System.Drawing.Color]::FromArgb(255, 255, 215, 105)
$fgKernel = [System.Drawing.Color]::FromArgb(255, 135, 195, 225)
$fgWarn   = [System.Drawing.Color]::FromArgb(255, 255, 190, 95)
$fgSpike  = [System.Drawing.Color]::FromArgb(255, 255, 150, 150)
$sorter = New-Object WinUltix.ListViewColumnSorter
$listView.ListViewItemSorter = $sorter
[void]$listView.Columns.Add("MSI", 78)
[void]$listView.Columns.Add("PCI Device / OS Subsystem", 275)
[void]$listView.Columns.Add("Driver", 140)
[void]$listView.Columns.Add("Avg ($([char]0x00B5)s/s)", 100)
[void]$listView.Columns.Add("Peak | 1s Load", 206)
[void]$listView.Columns.Add("Priority", 70)
[void]$listView.Columns.Add("IRQ Mask", 95)
[void]$listView.Columns.Add("DPC Assessment", 248)
$styleMsiRow = {
param(
[System.Windows.Forms.ListViewItem]$LvItem,
[int]$RowIndex,
$LoadRecord = $null
)
$dev = $LvItem.Tag
$targetBg = if (($RowIndex % 2) -eq 0) { $bgEven } else { $bgOdd }
$targetFg = $fgPciOk
if ($null -ne $LoadRecord -and ($LoadRecord.MaxPeakUs -ge 1000.0 -or $LoadRecord.AvgUsPerSec -ge 50000.0)) {
$targetBg = $bgSpike
$targetFg = $fgSpike
} elseif ($null -ne $LoadRecord -and $LoadRecord.MaxPeakUs -ge 350.0) {
$targetBg = $bgWarn
$targetFg = $fgWarn
} elseif ($null -ne $dev) {
if ($dev.IsKernelOnly -eq $true) {
$targetFg = $fgKernel
} elseif ($dev.IsRecommendedOffload) {
$targetBg = $bgRec
$targetFg = $fgRec
} elseif (-not $dev.IsDetected) {
$targetFg = $fgMsiOff
}
}
if ($LvItem.BackColor -ne $targetBg) { $LvItem.BackColor = $targetBg }
if ($LvItem.ForeColor -ne $targetFg) { $LvItem.ForeColor = $targetFg }
}
$reapplyAllRowShading = {
for ($idx = 0; $idx -lt $listView.Items.Count; $idx++) {
$it = $listView.Items[$idx]
$dev = $it.Tag
$curBg = $it.BackColor
if ($curBg -ne $bgSpike -and $curBg -ne $bgWarn) {
$newBg = if ($null -ne $dev -and $dev.IsRecommendedOffload -and $dev.IsKernelOnly -ne $true) {
$bgRec
} elseif (($idx % 2) -eq 0) {
$bgEven
} else {
$bgOdd
}
if ($it.BackColor -ne $newBg) { $it.BackColor = $newBg }
}
}
}
$listView.Add_ItemCheck({
param($src, $e)
$lvItem = $src.Items[$e.Index]
if ($null -ne $lvItem -and $null -ne $lvItem.Tag -and $lvItem.Tag.IsKernelOnly -eq $true) {
$e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
}
})
$sortSyncGuard = @{ SuppressCombo = $false }
$applySortMode = {
$listView.BeginUpdate()
switch ($comboSort.SelectedIndex) {
0 {
$listView.ListViewItemSorter = $null
$sortedItems = @($listView.Items | Sort-Object { $_.Tag.SortRank }, { $_.Tag.RawDeviceName })
$listView.Items.Clear()
foreach ($si in $sortedItems) { [void]$listView.Items.Add($si) }
$sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::None
$listView.ListViewItemSorter = $sorter
}
1 { $sorter.ColumnToSort = 3;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending; $listView.Sort() }
2 { $sorter.ColumnToSort = 4;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending; $listView.Sort() }
3 { $sorter.ColumnToSort = -1; $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending; $listView.Sort() }
4 { $sorter.ColumnToSort = 1;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending;  $listView.Sort() }
5 { $sorter.ColumnToSort = 2;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending;  $listView.Sort() }
}
& $reapplyAllRowShading
$listView.EndUpdate()
}
$comboSort.Add_SelectedIndexChanged({
if ($sortSyncGuard.SuppressCombo) { return }
if ($comboSort.SelectedIndex -ge 0) {
& $applySortMode
}
}.GetNewClosure())
$chkShowKernel.Add_CheckedChanged({
if (-not $chkShowKernel.Checked) {
$listView.BeginUpdate()
for ($i = $listView.Items.Count - 1; $i -ge 0; $i--) {
if ($listView.Items[$i].Tag.IsKernelOnly -eq $true) {
$listView.Items.RemoveAt($i)
}
}
& $reapplyAllRowShading
$listView.EndUpdate()
}
}.GetNewClosure())
$listView.Add_ColumnClick({
param($src, $e)
$listView.BeginUpdate()
if ($e.Column -eq $sorter.ColumnToSort) {
if ($sorter.OrderOfSort -eq [System.Windows.Forms.SortOrder]::Descending) {
$sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending
} else {
$sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending
}
} else {
$sorter.ColumnToSort = $e.Column
$sorter.OrderOfSort = if ($e.Column -in @(3, 4)) {
[System.Windows.Forms.SortOrder]::Descending
} else {
[System.Windows.Forms.SortOrder]::Ascending
}
}
$listView.Sort()
& $reapplyAllRowShading
$listView.EndUpdate()
$sortSyncGuard.SuppressCombo = $true
$comboSort.SelectedIndex = -1
$sortSyncGuard.SuppressCombo = $false
}.GetNewClosure())
$etwStarted = $false
try { $etwStarted = [WinUltix.DpcDriverProfiler]::Start() } catch { $etwStarted = $false }
$btnResetStats.Add_Click({
if ($etwStarted) {
[WinUltix.DpcDriverProfiler]::ResetStats()
$listView.BeginUpdate()
for ($i = $listView.Items.Count - 1; $i -ge 0; $i--) {
$lvItem = $listView.Items[$i]
$dev = $lvItem.Tag
if ($null -ne $dev -and $dev.IsKernelOnly -eq $true) {
$listView.Items.RemoveAt($i)
continue
}
$lvItem.SubItems[3].Text = "   0.0 $([char]0x00B5)s/s"
$lvItem.SubItems[4].Text = "Max:    0 $([char]0x00B5)s (1s: 0.0)"
}
for ($r = 0; $r -lt $listView.Items.Count; $r++) {
& $styleMsiRow $listView.Items[$r] $r $null
}
$listView.EndUpdate()
}
}.GetNewClosure())
$pciServiceKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$roleMaskMap    = @{
"GPU"     = "-> Default"
"NIC"     = "-> Default"
"USB"     = "-> Default"
"Storage" = "-> Spread"
"Audio"   = "-> Default"
"System"  = "All / C0"
}
$kernelRoleCatalog = @{
"dxgkrnl"   = @{ Name = "[OS] DirectX Graphics Kernel";        Role = "GPU";     Advice = "Follows GPU IRQ (nvlddmkm/amdkmdag)" }
"dxgmms2"   = @{ Name = "[OS] DirectX Video Memory Manager";   Role = "GPU";     Advice = "Follows GPU VRAM Paging / IRQ" }
"wdf01000"  = @{ Name = "[OS] KMDF Driver Framework Runtime";  Role = "USB";     Advice = "Aggregates USBXHCI / HID / Audio DPCs" }
"ndis"      = @{ Name = "[OS] NDIS Network Subsystem";         Role = "NIC";     Advice = "Aggregates NIC IRQ (Offload NIC -> C1)" }
"tcpip"     = @{ Name = "[OS] Windows TCP/IP Network Stack";   Role = "NIC";     Advice = "Follows NIC RSS / Interrupt Core" }
"usbport"   = @{ Name = "[OS] USB 2.0 EHCI Port Driver";       Role = "USB";     Advice = "Legacy USB 2.0 EHCI Host Wrapper" }
"usbaudio2" = @{ Name = "[OS] USB Audio 2.0 Class Driver";     Role = "USB";     Advice = "Follows USB XHCI Controller Core" }
"portcls"   = @{ Name = "[OS] PortCls Audio Class Driver";     Role = "Audio";   Advice = "Follows HD Audio / PCIe Sound Core" }
"ks"        = @{ Name = "[OS] Kernel Streaming Audio/Video";   Role = "Audio";   Advice = "Audio/Video Kernel Pin Dispatcher" }
"ntoskrnl"  = @{ Name = "[OS] Windows NT Executive & Timer";   Role = "System";  Advice = "OS Scheduler & Timer (Core 0 / All)" }
"hal"       = @{ Name = "[OS] Hardware Abstraction Layer";     Role = "System";  Advice = "Hardware Timer & APIC Routing" }
"acpi"      = @{ Name = "[OS] ACPI Power & Thermal Driver";    Role = "System";  Advice = "BIOS AML / EC Polling (Core 0)" }
"storport"  = @{ Name = "[OS] Storage Port Miniport Driver";   Role = "Storage"; Advice = "Aggregates NVMe / SATA Multi-Queue" }
"classpnp"  = @{ Name = "[OS] Storage Class PnP Driver";       Role = "Storage"; Advice = "Follows Disk / Storage I/O Stack" }
"fltmgr"    = @{ Name = "[OS] Filesystem Filter Manager";      Role = "Storage"; Advice = "Storage I/O Minifilter Stack" }
"ntfs"      = @{ Name = "[OS] NTFS File System Driver";        Role = "Storage"; Advice = "Volume Metadata & File I/O Stack" }
"iorate"    = @{ Name = "[OS] Volume I/O Rate Filter Driver";  Role = "Storage"; Advice = "OS Disk QoS & Storage I/O Limiter" }
"symcryptk" = @{ Name = "[OS] Windows Kernel Crypto Library";  Role = "System";  Advice = "IPsec / SMB / TLS Kernel Crypto" }
"mouclass"  = @{ Name = "[OS] Mouse Class Driver";             Role = "USB";     Advice = "Follows USB XHCI / HID Core" }
"kbdclass"  = @{ Name = "[OS] Keyboard Class Driver";          Role = "USB";     Advice = "Follows USB XHCI / HID Core" }
}
$refreshData = {
$previouslyChecked = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($chkIt in $listView.CheckedItems) {
if ($null -ne $chkIt.Tag -and $null -ne $chkIt.Tag.ActionData -and $chkIt.Tag.ActionData.DevicePath) {
[void]$previouslyChecked.Add([string]$chkIt.Tag.ActionData.DevicePath)
}
}
if ($comboSort.SelectedIndex -lt 0) {
$sortSyncGuard.SuppressCombo = $true
$comboSort.SelectedIndex = 0
$sortSyncGuard.SuppressCombo = $false
}
$listView.BeginUpdate()
$listView.ListViewItemSorter = $null
$listView.Items.Clear()
$pciServiceKeys.Clear()
$auditData = Get-HardwareState_IRQ
foreach ($rName in @("GPU", "NIC", "USB", "Storage", "Audio")) {
$rItems = @($auditData | Where-Object { $_.DeviceRole -eq $rName })
if ($rItems.Count -eq 0) {
$roleMaskMap[$rName] = if ($rName -eq "Storage") { "-> Spread" } else { "-> Default" }
continue
}
$uMasks = @($rItems | Select-Object -ExpandProperty AffinityLabel -Unique)
if ($uMasks.Count -eq 1) {
$roleMaskMap[$rName] = "-> $($uMasks[0])"
} else {
$customMasks = @($uMasks | Where-Object { $_ -ne "Default" -and $_ -ne "Spread" })
if ($customMasks.Count -gt 0) {
$roleMaskMap[$rName] = "-> $($customMasks[0])*"
} elseif ($uMasks -contains "Spread") {
$roleMaskMap[$rName] = "-> Spread"
} else {
$roleMaskMap[$rName] = "-> Default"
}
}
}
$rIdx = 0
foreach ($item in $auditData) {
if (-not [string]::IsNullOrWhiteSpace($item.ServiceName)) {
[void]$pciServiceKeys.Add($item.ServiceName.ToLowerInvariant())
}
$item | Add-Member -NotePropertyName IsKernelOnly -NotePropertyValue $false -Force
$lvItem = New-Object System.Windows.Forms.ListViewItem($item.MsiStatus)
[void]$lvItem.SubItems.Add($item.RawDeviceName)
[void]$lvItem.SubItems.Add($item.DriverTag)
$initAvg  = if ($etwStarted) { "   0.0 $([char]0x00B5)s/s" } else { "N/A (ETW Busy)" }
$initPeak = if ($etwStarted) { "Max:    0 $([char]0x00B5)s (1s: 0.0)" } else { "N/A" }
[void]$lvItem.SubItems.Add($initAvg)
[void]$lvItem.SubItems.Add($initPeak)
[void]$lvItem.SubItems.Add($item.PrioLabel)
[void]$lvItem.SubItems.Add($item.AffinityLabel)
[void]$lvItem.SubItems.Add($item.AdviceText)
$lvItem.Tag = $item
$lvItem.Checked = $previouslyChecked.Contains([string]$item.ActionData.DevicePath)
& $styleMsiRow $lvItem $rIdx $null
[void]$listView.Items.Add($lvItem)
$rIdx++
}
$listView.ListViewItemSorter = $sorter
$listView.EndUpdate()
& $applySortMode
}
&$refreshData
$dpcState = @{ PrevCounts = $null; IsRunning = $true; LastSnap = $null }
Update-UltixDpcMonitorUI -TargetLabel $lblDpcMonitor -State $dpcState
if ($etwStarted) {
$lblDpcMonitor.Text += "`r`nTOP .SYS (AVG) | Sampling real-time kernel ETW ISR/DPC driver routines..."
} else {
$lblDpcMonitor.Text += "`r`nTOP .SYS (AVG) | [Kernel ETW session occupied by another profiler]"
}
$dpcTimer = New-Object System.Windows.Forms.Timer
$dpcTimer.Interval = 1000
$dpcTimer.Tag = @{
Modal          = $modal
Label          = $lblDpcMonitor
ListView       = $listView
Sorter         = $sorter
ChkKernel      = $chkShowKernel
PciKeys        = $pciServiceKeys
KernelCatalog  = $kernelRoleCatalog
RoleMasks      = $roleMaskMap
State          = $dpcState
EtwEnabled     = $etwStarted
StyleRow       = $styleMsiRow
}
$dpcTimer.Add_Tick({
$ctx = $this.Tag
if ($null -eq $ctx -or $ctx.Modal.IsDisposed -or $ctx.Label.IsDisposed) {
$this.Stop()
return
}
Update-UltixDpcMonitorUI -TargetLabel $ctx.Label -State $ctx.State
if (-not $ctx.EtwEnabled) {
$ctx.Label.Text += "`r`nTOP .SYS (AVG) | [Kernel ETW session occupied by another profiler]"
return
}
$drvSamples = @([WinUltix.DpcDriverProfiler]::SampleDriverLoads())
$drvLookup  = @{}
$elapsedSec = 1
foreach ($rec in $drvSamples) {
$drvLookup[$rec.ServiceKey] = $rec
if ($rec.ElapsedSec -gt $elapsedSec) { $elapsedSec = $rec.ElapsedSec }
}
$topDrivers = @($drvSamples | Sort-Object @{Expression="AvgUsPerSec"; Descending=$true}, @{Expression="MaxPeakUs"; Descending=$true} | Select-Object -First 3)
$timeTag = if ($elapsedSec -ge 600) { "{0}m" -f [int]($elapsedSec / 60) } else { "{0}s" -f $elapsedSec }
$hdrTag  = ("TOP .SYS ({0,4})" -f $timeTag)
if ($topDrivers.Count -gt 0) {
$topParts = [System.Collections.Generic.List[string]]::new()
$rank = 1
foreach ($td in $topDrivers) {
$topParts.Add("$rank. $($td.DriverName) (Avg: $($td.AvgUsPerSec) $([char]0x00B5)s/s | Max: $([math]::Round($td.MaxPeakUs, 0)) $([char]0x00B5)s)")
$rank++
}
$ctx.Label.Text += "`r`n$hdrTag | " + ($topParts -join "   ")
} else {
$ctx.Label.Text += "`r`n$hdrTag | Idle (<0.1 $([char]0x00B5)s/s kernel driver ISR/DPC activity)"
}
$lv = $ctx.ListView
$st = $ctx.Sorter
if ($null -ne $lv -and -not $lv.IsDisposed) {
$existingKernelRows = @{}
$addedKernelRow     = $false
for ($r = 0; $r -lt $lv.Items.Count; $r++) {
$lvItem = $lv.Items[$r]
$dev = $lvItem.Tag
if ($null -eq $dev) { continue }
$svcKey = if ($dev.ServiceName) { $dev.ServiceName.ToLowerInvariant() } else { "pci" }
if ($dev.IsKernelOnly -eq $true) {
$existingKernelRows[$svcKey] = $lvItem
$kMeta = $ctx.KernelCatalog[$svcKey]
$kRole = if ($null -ne $kMeta -and $kMeta.Role) { $kMeta.Role } else { "System" }
$inheritedMask = if ($ctx.RoleMasks.ContainsKey($kRole)) { $ctx.RoleMasks[$kRole] } else { "All / C0" }
if ($lvItem.SubItems[6].Text -ne $inheritedMask) { $lvItem.SubItems[6].Text = $inheritedMask }
}
$rec = $drvLookup[$svcKey]
if ($null -ne $rec -and ($rec.AvgUsPerSec -gt 0 -or $rec.MaxPeakUs -gt 0)) {
$avgText  = ("{0,6:0.0} $([char]0x00B5)s/s" -f $rec.AvgUsPerSec)
$peakText = ("Max: {0,4:0} $([char]0x00B5)s (1s: {1:0.0})" -f $rec.MaxPeakUs, $rec.UsPerSec)
} else {
$avgText = "   0.0 $([char]0x00B5)s/s"
if ($svcKey -match '^(usbxhci|usb4hostrouter|hdaudbus)$') {
$peakText = "Max:    0 $([char]0x00B5)s (via Wdf01000)"
} elseif ($dev.SortRank -in @(2, 4)) {
$peakText = "Max:    0 $([char]0x00B5)s (via ndis.sys)"
} elseif ($svcKey -match '^(storahci|stornvme|secnvme|iastor)') {
$peakText = "Max:    0 $([char]0x00B5)s (via storport)"
} else {
$peakText = "Max:    0 $([char]0x00B5)s (1s: 0.0)"
}
}
if ($lvItem.SubItems[3].Text -ne $avgText)  { $lvItem.SubItems[3].Text = $avgText }
if ($lvItem.SubItems[4].Text -ne $peakText) { $lvItem.SubItems[4].Text = $peakText }
& $ctx.StyleRow $lvItem $r $rec
}
if ($ctx.ChkKernel.Checked) {
foreach ($rec in $drvSamples) {
if ($ctx.PciKeys.Contains($rec.ServiceKey)) { continue }
if ($existingKernelRows.ContainsKey($rec.ServiceKey)) { continue }
if ($rec.AvgUsPerSec -lt 1.0 -and $rec.MaxPeakUs -lt 15.0) { continue }
$meta = $ctx.KernelCatalog[$rec.ServiceKey]
$sysTitle  = if ($null -ne $meta) { $meta.Name } else { "[OS] $($rec.DriverName) Subsystem" }
$sysAdvice = if ($null -ne $meta) { $meta.Advice } else { "OS Kernel Driver (Non-PCI)" }
$sysRole   = if ($null -ne $meta -and $meta.Role) { $meta.Role } else { "System" }
$sysMask   = if ($ctx.RoleMasks.ContainsKey($sysRole)) { $ctx.RoleMasks[$sysRole] } else { "All / C0" }
$kItemObj = [PSCustomObject]@{
RawDeviceName        = $sysTitle
ServiceName          = $rec.ServiceKey
DriverTag            = $rec.DriverName
IsDetected           = $true
IsRecommendedOffload = $false
IsKernelOnly         = $true
SortRank             = 90
}
$kLv = New-Object System.Windows.Forms.ListViewItem("KERNEL")
[void]$kLv.SubItems.Add($sysTitle)
[void]$kLv.SubItems.Add($rec.DriverName)
[void]$kLv.SubItems.Add(("{0,6:0.0} $([char]0x00B5)s/s" -f $rec.AvgUsPerSec))
[void]$kLv.SubItems.Add(("Max: {0,4:0} $([char]0x00B5)s (1s: {1:0.0})" -f $rec.MaxPeakUs, $rec.UsPerSec))
[void]$kLv.SubItems.Add("System")
[void]$kLv.SubItems.Add($sysMask)
[void]$kLv.SubItems.Add($sysAdvice)
$kLv.Tag = $kItemObj
& $ctx.StyleRow $kLv $lv.Items.Count $rec
[void]$lv.Items.Add($kLv)
$addedKernelRow = $true
}
}
if ($st.OrderOfSort -ne [System.Windows.Forms.SortOrder]::None -and
($st.ColumnToSort -in @(3, 4, -1) -or $addedKernelRow) -and
[System.Windows.Forms.Control]::MouseButtons -eq [System.Windows.Forms.MouseButtons]::None) {
$needsResort = $addedKernelRow
if (-not $needsResort) {
for ($i = 0; $i -lt ($lv.Items.Count - 1); $i++) {
if ($st.Compare($lv.Items[$i], $lv.Items[$i + 1]) -gt 0) {
$needsResort = $true
break
}
}
}
if ($needsResort) {
$lv.BeginUpdate()
$lv.Sort()
for ($r = 0; $r -lt $lv.Items.Count; $r++) {
$it  = $lv.Items[$r]
$dev = $it.Tag
$svcKey = if ($null -ne $dev -and $dev.ServiceName) { $dev.ServiceName.ToLowerInvariant() } else { "pci" }
& $ctx.StyleRow $it $r $drvLookup[$svcKey]
}
$lv.EndUpdate()
}
}
}
})
$dpcTimer.Start()
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
$lvItem.Checked = ($null -ne $dev -and $dev.IsKernelOnly -ne $true -and [bool]$dev.IsRecommendedOffload)
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
$btnForceMSI = New-UltixButton -Parent $modal -Text "Apply MSI & Policy" -X 15 -Y 708 -Width 180 -Height 38 -RGB @(150, 60, 60)
$btnForceMSI.Anchor = 'Bottom, Left'
$btnForceMSI.Add_Click({
if ($listView.CheckedItems.Count -eq 0) {
[System.Windows.Forms.MessageBox]::Show("No PCI devices selected. Check the devices you want to configure (or click 'Select $([char]0x2605) GPU/NIC').", "WinUltix - MSI & IRQ Enforcer") | Out-Null
return
}
$changed = 0
$bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
if (-not (Test-Path -LiteralPath $bRoot)) { New-Item -Path $bRoot -Force | Out-Null }
$prioSelection = [string]$comboPrio.SelectedItem
$doOffload     = $chkOffloadCore0.Checked
[byte[]]$offloadBytes = if ($doOffload) { &$getOffloadMaskBytes } else { $null }
foreach ($lvItem in $listView.CheckedItems) {
$dev = $lvItem.Tag
if ($null -eq $dev -or $dev.IsKernelOnly -eq $true) { continue }
$irqRoot = $dev.ActionData.IrqMgmtPath
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
$isStorageSpread = ($dev.DeviceRole -eq "Storage" -or $dev.DevicePolicy -eq 5)
$applyBlock = {
Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop | Out-Null
if ($prioSelection -ne "Keep Current") {
if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
switch ($prioSelection) {
"High (3)"            { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 3 -Type DWord -Force -ErrorAction Stop }
"Normal (2)"          { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 2 -Type DWord -Force -ErrorAction Stop }
"Low (1)"             { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 1 -Type DWord -Force -ErrorAction Stop }
"Undefined (Default)" { Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue }
}
}
if ($doOffload -and $null -ne $offloadBytes) {
if ($isStorageSpread) {
Write-GUI "    [*] Preserved Multi-Queue 'Spread' policy on storage controller: $($dev.RawDeviceName)"
} else {
if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value 4 -Type DWord -Force -ErrorAction Stop
Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value $offloadBytes -Type Binary -Force -ErrorAction Stop
}
}
}
try {
try {
& $applyBlock
} catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
Grant-UltixRegistryKeyAccess -RegistryPath $irqRoot
Grant-UltixRegistryKeyAccess -RegistryPath $msiPath
if (Test-Path -LiteralPath $affPath) { Grant-UltixRegistryKeyAccess -RegistryPath $affPath }
& $applyBlock
}
Write-GUI " -> Configured IRQ/MSI policy: $($dev.RawDeviceName)"
$changed++
} catch {
Write-GUI " -> [!] Failed to modify IRQ/MSI policy for $($dev.RawDeviceName): $($_.Exception.Message)"
}
}
&$refreshData
if ($changed -gt 0) { [System.Windows.Forms.MessageBox]::Show("Successfully configured MSI & IRQ policy for $changed device(s).`nOriginal states backed up.`nPlease reboot your PC.", "Reboot Required") }
}.GetNewClosure())
$btnRevertMSI = New-UltixButton -Parent $modal -Text "Restore Original State" -X 205 -Y 708 -Width 190 -Height 38 -RGB @(100, 100, 100)
$btnRevertMSI.Anchor = 'Bottom, Left'
$btnRevertMSI.Add_Click({
if ($listView.CheckedItems.Count -eq 0) {
[System.Windows.Forms.MessageBox]::Show("Check the PCI device(s) you want to restore to factory defaults.", "WinUltix - Restore MSI State") | Out-Null
return
}
$bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
foreach ($lvItem in $listView.CheckedItems) {
$dev = $lvItem.Tag
if ($null -eq $dev -or $dev.IsKernelOnly -eq $true) { continue }
$irqRoot = $dev.ActionData.IrqMgmtPath
$msiPath = $dev.ActionData.Path
$affPath = $dev.ActionData.AffinityPath
$safeKey = &$getSafeBackupKeyName $msiPath
$devBackupKey = "$bRoot\$safeKey"
$revertBlock = {
if (Test-Path -LiteralPath $devBackupKey) {
$bProps = Get-ItemProperty -LiteralPath $devBackupKey -ErrorAction SilentlyContinue
if ($null -ne $bProps.MSISupported) {
if ($bProps.MSISupported -eq 255 -or $bProps.MSISupported -eq -1) {
Remove-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Force -ErrorAction SilentlyContinue
} else {
Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value $bProps.MSISupported -Type DWord -Force -ErrorAction Stop
}
}
if ($bProps.AffinityKeyExisted -eq 0) {
if (Test-Path -LiteralPath $affPath) { Remove-Item -LiteralPath $affPath -Recurse -Force -ErrorAction Stop }
} elseif (Test-Path -LiteralPath $affPath) {
if ($bProps.InterruptPriority -eq 255 -or $null -eq $bProps.InterruptPriority) {
Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue
} else {
Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value $bProps.InterruptPriority -Type DWord -Force -ErrorAction Stop
}
if ($bProps.DevicePolicy -eq 255 -or $null -eq $bProps.DevicePolicy) {
Remove-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Force -ErrorAction SilentlyContinue
} else {
Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value $bProps.DevicePolicy -Type DWord -Force -ErrorAction Stop
}
if ($null -ne $bProps.AssignmentSetOverride) {
Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value ([byte[]]$bProps.AssignmentSetOverride) -Type Binary -Force -ErrorAction Stop
} else {
Remove-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
}
}
Remove-Item -LiteralPath $devBackupKey -Recurse -Force -ErrorAction SilentlyContinue
} elseif ($dev.DeviceRole -eq "Storage") {
Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop
if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value 5 -Type DWord -Force -ErrorAction Stop
Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority", "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
} else {
if (Test-Path -LiteralPath $affPath) {
Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority", "DevicePolicy", "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
}
}
}
try {
try {
& $revertBlock
} catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
Grant-UltixRegistryKeyAccess -RegistryPath $irqRoot
Grant-UltixRegistryKeyAccess -RegistryPath $msiPath
if (Test-Path -LiteralPath $affPath) { Grant-UltixRegistryKeyAccess -RegistryPath $affPath }
& $revertBlock
}
Write-GUI " -> Reverted IRQ/MSI state to factory defaults: $($dev.RawDeviceName)"
} catch {
Write-GUI " -> [!] Failed to revert IRQ/MSI state for $($dev.RawDeviceName): $($_.Exception.Message)"
}
}
&$refreshData
}.GetNewClosure())
$btnClose = New-UltixButton -Parent $modal -Text "Close" -X 405 -Y 708 -Width 120 -Height 38 -RGB @(60, 60, 60)
$btnClose.Anchor = 'Bottom, Left'
$btnClose.DialogResult = "Cancel"
$lblIrqLegend = New-Object System.Windows.Forms.Label
$lblIrqLegend.Text = "IRQ MASK : Default = Core 0 | 0x.. (C#) = Hex Thread Mask (e.g. 0xC = LP#2,3 -> Core 1) | Spread = All Cores`r`nKERNEL   : -> Mask = Inherited from PCI device | -> Mask* = Mixed PCI masks | All / C0 = OS Timer"
$lblIrqLegend.Location = New-Object System.Drawing.Point(538, 708)
$lblIrqLegend.Size = New-Object System.Drawing.Size(712, 38)
$lblIrqLegend.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
$lblIrqLegend.ForeColor = [System.Drawing.Color]::FromArgb(255, 175, 185, 195)
$lblIrqLegend.Font = New-Object System.Drawing.Font("Consolas", 8.2)
$lblIrqLegend.BorderStyle = "FixedSingle"
$lblIrqLegend.Padding = New-Object System.Windows.Forms.Padding(6, 3, 4, 2)
$lblIrqLegend.Anchor = 'Bottom, Left, Right'
$modal.Controls.AddRange(@($lblDesc, $lblWarning, $lblDpcMonitor, $lblDpcLegend, $lblPrio, $comboPrio, $chkOffloadCore0, $chkShowKernel, $lblSort, $comboSort, $listView, $lblIrqLegend))
try {
[void]$modal.ShowDialog($global:form)
} finally {
$dpcTimer.Stop()
$dpcTimer.Dispose()
try { [WinUltix.DpcDriverProfiler]::Stop() } catch { }
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
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, 60)
$listView.Size = New-Object System.Drawing.Size(800, 330)
$listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
$listView.BorderStyle = "FixedSingle"
$listView.Font = New-Object System.Drawing.Font("Consolas", 10)
$listView.Anchor = 'Top, Bottom, Left, Right'
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $false
Enable-UltixDoubleBuffer -Control $listView
$listView.Columns.Add("Time", 170) | Out-Null
$listView.Columns.Add("Event ID", 90) | Out-Null
$listView.Columns.Add("APIC ID", 120) | Out-Null
$listView.Columns.Add("Error Source / Details", 405) | Out-Null
$btnClear = New-UltixButton -Parent $modal -Text "Wipe Logs (Prepare for Test)" -X 15 -Y 405 -Width 220 -Height 35 -RGB @(150, 60, 60)
$btnClear.Anchor = 'Bottom, Left'
$btnClose = New-UltixButton -Parent $modal -Text "Close" -X 245 -Y 405 -Width 120 -Height 35 -RGB @(60, 60, 60)
$btnClose.Anchor = 'Bottom, Left'
$btnClose.DialogResult = "Cancel"
$refreshData = {
$uiModal    = $modal
$uiListView = $listView
$bgEven     = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
$bgOdd      = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
$bgAlert    = [System.Drawing.Color]::FromArgb(255, 50, 26, 28)
$uiListView.Items.Clear()
$loadingItem = New-Object System.Windows.Forms.ListViewItem("Scanning...")
[void]$loadingItem.SubItems.Add("---")
[void]$loadingItem.SubItems.Add("---")
[void]$loadingItem.SubItems.Add("Parsing System WHEA Event Log in background Runspace...")
$loadingItem.BackColor = $bgEven
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
$rIdx = 0
foreach ($item in $auditData) {
$rowBg = if (($rIdx % 2) -eq 0) { $bgEven } else { $bgOdd }
$lvItem = New-Object System.Windows.Forms.ListViewItem([string]$item.Time)
$lvItem.BackColor = $rowBg
$idSub = $lvItem.SubItems.Add([string]$item.EventID)
$idSub.BackColor = $rowBg
$apicSub = $lvItem.SubItems.Add([string]$item.ApicID)
$apicSub.BackColor = $rowBg
if ($item.ApicID -ne "N/A") {
$lvItem.UseItemStyleForSubItems = $false
$apicSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 150, 150)
$apicSub.BackColor = $bgAlert
}
$errSub = $lvItem.SubItems.Add([string]$item.ErrorType)
$errSub.BackColor = $rowBg
$errSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
[void]$uiListView.Items.Add($lvItem)
$rIdx++
}
} else {
$lvItem = New-Object System.Windows.Forms.ListViewItem("---")
[void]$lvItem.SubItems.Add("---")
[void]$lvItem.SubItems.Add("---")
[void]$lvItem.SubItems.Add("No WHEA errors found. Hardware is perfectly stable.")
$lvItem.BackColor = $bgEven
$lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 145, 230, 165)
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
$chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(710, 375); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
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
$chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(650, 200); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
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
Remove-ItemProperty -LiteralPath $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue | Out-Null
$null = & bcdedit.exe /deletevalue "{current}" disabledynamictick 2>&1
$null = & bcdedit.exe /deletevalue "{current}" useplatformclock 2>&1
$null = & bcdedit.exe /deletevalue "{current}" useplatformtick 2>&1
$hpetRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\PNP0103"
if (Test-Path -LiteralPath $hpetRoot) {
foreach ($sub in (Get-ChildItem -LiteralPath $hpetRoot -ErrorAction SilentlyContinue)) {
$hpetId = "ACPI\PNP0103\$($sub.PSChildName)"
if ([WinUltix.PnpTree]::IsDeviceDisabled($hpetId)) {
$null = & pnputil.exe /enable-device "$hpetId" 2>&1
}
}
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
$chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 160); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
$localData = New-Object System.Collections.ArrayList
$refreshData = {
$modal.UseWaitCursor = $true
[System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
try {
$chkList.BeginUpdate()
$chkList.Items.Clear(); $localData.Clear()
$auditData = Get-HardwareState_NVMe
foreach ($item in $auditData) {
[void]$localData.Add($item)
if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) }
else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
}
$chkList.EndUpdate()
} finally {
$modal.UseWaitCursor = $false
[System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
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
$modal.UseWaitCursor = $true
[System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
try {
Invoke-ApplyNVMeTweaks -SelectedItems $applyQueue
} finally {
$modal.UseWaitCursor = $false
[System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
}
[System.Windows.Forms.MessageBox]::Show("Selected I/O and Memory optimizations applied.`nReboot is required for PCIe/NVMe bus changes.", "Optimization Completed")
}
&$refreshData
}.GetNewClosure())
$btnRevert = New-UltixButton -Parent $modal -Text "Restore OS Defaults" -X 205 -Y 260 -Width 160 -Height 35 -RGB @(100, 100, 100)
$btnRevert.Anchor = 'Bottom, Left'
$btnRevert.Add_Click({
$modal.UseWaitCursor = $true
[System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
try {
Remove-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters" -Name "DisableASPM" -Force -ErrorAction SilentlyContinue | Out-Null
Remove-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" -Name "IdlePowerMode" -Force -ErrorAction SilentlyContinue | Out-Null
Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
} finally {
$modal.UseWaitCursor = $false
[System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
}
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
if (-not (Test-Path -LiteralPath $appDataFolder)) {
try { New-Item -Path $appDataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null }
catch { [System.Windows.Forms.MessageBox]::Show("Failed to create WinUltix AppData directory.", "Error"); return }
}
$ps1Path = "$appDataFolder\PreFlight.ps1"
$icoPath = "$appDataFolder\WinUltix.ico"
if (-not (Test-Path -LiteralPath $icoPath)) {
if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
$parentDir = Split-Path -Path $ScriptDir -Parent
foreach ($cand in @((Join-Path $ScriptDir "assets\WinUltix.ico"), (Join-Path $parentDir "assets\WinUltix.ico"))) {
if (Test-Path -LiteralPath $cand) {
Copy-Item -LiteralPath $cand -Destination $icoPath -Force -ErrorAction SilentlyContinue
break
}
}
}
if (-not (Test-Path -LiteralPath $icoPath)) {
Initialize-WinUltixIcon
if ($null -ne $global:UltixAppIcon) {
try {
$fs = [System.IO.File]::Create($icoPath)
try { $global:UltixAppIcon.Save($fs) } finally { $fs.Dispose() }
} catch { }
}
}
}
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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
[System.Windows.Forms.Application]::EnableVisualStyles()

`$c = 'HKCU:\Software\WinUltix\AffinityLasso'
`$p = 'HKLM:\SOFTWARE\WinUltix\CPPC'
function Get-Pcfg (`$g) {
    `$out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR `$g 2>`$null
    if (-not `$out) { return `$null }
    `$hexLines = @(`$out -match ':\s*(0x[0-9a-fA-F]+)\s*`$')
    if (`$hexLines.Count -ge 2 -and `$hexLines[-2] -match '(0x[0-9a-fA-F]+)\s*`$') {
        return [convert]::ToInt32(`$matches[1], 16)
    } elseif (`$hexLines.Count -eq 1 -and `$hexLines[0] -match '(0x[0-9a-fA-F]+)\s*`$') {
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
`$icoFile = "`$env:LOCALAPPDATA\WinUltix\WinUltix.ico"
if (Test-Path -LiteralPath `$icoFile) {
    try { `$frm.Icon = New-Object System.Drawing.Icon(`$icoFile, 32, 32) } catch { }
}
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
`$btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 135, 50, 50)
`$btnEngage.FlatStyle = "Flat"
`$btnEngage.DialogResult = "Yes"

`$btnRelease = New-Object System.Windows.Forms.Button
`$btnRelease.Text = "RELEASE"
`$btnRelease.Location = New-Object System.Drawing.Point(128, 118)
`$btnRelease.Size = New-Object System.Drawing.Size(100, 32)
`$btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
`$btnRelease.FlatStyle = "Flat"
`$btnRelease.DialogResult = "No"

`$btnCancel = New-Object System.Windows.Forms.Button
`$btnCancel.Text = "Cancel"
`$btnCancel.Location = New-Object System.Drawing.Point(236, 118)
`$btnCancel.Size = New-Object System.Drawing.Size(100, 32)
`$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
`$btnCancel.FlatStyle = "Flat"
`$btnCancel.DialogResult = "Cancel"

`$frm.Controls.AddRange(@(`$lblStatus, `$chkAff, `$chkCPPC, `$btnEngage, `$btnRelease, `$btnCancel))
`$res = `$frm.ShowDialog()
if (`$null -ne `$frm.Icon) { `$frm.Icon.Dispose() }
`$frm.Dispose()

if (`$res -eq "Yes") {
    if (`$chkAff.Checked -and (Test-Path -LiteralPath `$c)) { 
        (Get-ItemProperty -LiteralPath `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
            `$n = `$_.Name -replace '\.exe`$',''
            foreach (`$proc in @(Get-Process -Name `$n -ErrorAction SilentlyContinue)) {
                try {
                    `$proc.ProcessorAffinity = [System.IntPtr]([int64]$maskInt64)
                    `$proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                } catch {} finally {
                    `$proc.Dispose()
                }
            }
        } 
    }
    
    if (`$chkCPPC.Checked) {
        if (-not (Test-Path -LiteralPath `$p)) { New-Item -Path `$p -Force | Out-Null }
        `$e  = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        `$d  = Get-Pcfg '4b92d758-5a24-4851-a470-815d78aee119'
        `$pr = Get-Pcfg '7b224883-b3cc-4d79-819f-8374152cbe7c'
        
        if (`$null -ne `$e -and -not (`$e -eq 0 -and `$d -eq 100 -and `$pr -eq 100) -and -not (`$e -eq 0 -and `$d -eq 0 -and `$pr -eq 0)) {
            Set-ItemProperty -LiteralPath `$p -Name 'EPP' -Value `$e -Type DWord -Force
            Set-ItemProperty -LiteralPath `$p -Name 'Demote' -Value `$d -Type DWord -Force
            Set-ItemProperty -LiteralPath `$p -Name 'Promote' -Value `$pr -Type DWord -Force
        }
        
        `$tsCmd = "`$bp='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path -LiteralPath `$bp){ `$r=Get-ItemProperty -LiteralPath `$bp; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
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
        if (Test-Path -LiteralPath `$c) { 
            (Get-ItemProperty -LiteralPath `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
                `$n = `$_.Name -replace '\.exe`$',''
                foreach (`$proc in @(Get-Process -Name `$n -ErrorAction SilentlyContinue)) {
                    try {
                        `$proc.ProcessorAffinity = `$sys
                        `$proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
                    } catch {} finally {
                        `$proc.Dispose()
                    }
                }
            } 
        } 
    }
    
    if (`$chkCPPC.Checked) {
        `$e = 50; `$d = 40; `$pr = 60
        if (Test-Path -LiteralPath `$p) { 
            `$reg = Get-ItemProperty -LiteralPath `$p -ErrorAction SilentlyContinue
            if (`$null -ne `$reg.EPP -and `$null -ne `$reg.Demote -and `$null -ne `$reg.Promote) {
                if (`$reg.EPP -eq 0 -and `$reg.Demote -eq 0 -and `$reg.Promote -eq 0) {
                    Remove-ItemProperty -LiteralPath `$p -Name 'EPP', 'Demote', 'Promote' -Force -ErrorAction SilentlyContinue
                } else {
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
Set-Content -LiteralPath $ps1Path -Value $code -Encoding UTF8 -ErrorAction Stop
$desktop  = [Environment]::GetFolderPath("Desktop")
$WshShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
$Shortcut = $WshShell.CreateShortcut("$desktop\WinUltix Pre-Flight Mode.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""
$Shortcut.WindowStyle = 7
$Shortcut.IconLocation = if (Test-Path -LiteralPath $icoPath) { "$icoPath, 0" } else { "shell32.dll, 137" }
$Shortcut.Save()
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell)
Write-GUI " -> Generated Pre-Flight shortcut on Desktop ($($topo.Label))."
[System.Windows.Forms.MessageBox]::Show("Pre-Flight Shortcut generated on Desktop.", "Success")
} catch {
[System.Windows.Forms.MessageBox]::Show("Failed to construct COM object or write file.`n`nError: $($_.Exception.Message)", "Shortcut Generation Failed")
}
}
function Get-UsbTopologyMap {
param([switch]$IncludeRawHubs)
$controllers = [System.Collections.Generic.List[PSCustomObject]]::new()
[int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
[uint64]$core0Mask  = if ($coreMasks.Count -ge 1) { [uint64]$coreMasks[0] } else { 3 }
[uint64]$core1Mask  = if ($coreMasks.Count -ge 2) { [uint64]$coreMasks[1] } else { 12 }
$pciRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
if (-not (Test-Path -LiteralPath $pciRoot)) { return @() }
foreach ($venKey in (Get-ChildItem -LiteralPath $pciRoot -ErrorAction SilentlyContinue)) {
foreach ($instKey in (Get-ChildItem -LiteralPath $venKey.PSPath -ErrorAction SilentlyContinue)) {
$props = Get-ItemProperty -LiteralPath $instKey.PSPath -Name "Service", "FriendlyName", "DeviceDesc", "LocationInformation" -ErrorAction SilentlyContinue
if ($null -eq $props -or $props.Service -notmatch '^(?i)(USBXHCI|USB4|usbehci)$') { continue }
$instanceId = "PCI\$($venKey.PSChildName)\$($instKey.PSChildName)"
if ([WinUltix.PnpTree]::GetDeviceConfigStatus($instanceId) -ne 0) { continue }
$rawCtrlName = if ($props.FriendlyName) { $props.FriendlyName } else { $props.DeviceDesc }
$ctrlName    = Format-UltixDeviceName -RawName $rawCtrlName
$parents = @([WinUltix.PnpTree]::GetParentChain($instanceId))
$pciBridgeHops = @($parents | Where-Object { $_ -like "PCI\*" }).Count
$routingBadge = if ($venKey.PSChildName -match 'DEV_43[A-F0-9]{2}' -or $ctrlName -match '(?i)Chipset') {
if ($pciBridgeHops -ge 3) { "[CHIPSET PCH (Daisy-Chained / $pciBridgeHops Hops)]" }
else { "[CHIPSET PCH ($pciBridgeHops PCIe Hops)]" }
} elseif ($pciBridgeHops -le 1) {
"[CPU DIRECT SoC LANES (1 PCIe Hop - Lowest Latency)]"
} else {
"[SECONDARY BRIDGE ($pciBridgeHops PCIe Hops)]"
}
$msiPath = "$($instKey.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
$affPath = "$($instKey.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
$msiOn   = ((Get-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported -eq 1)
$affProps = Get-ItemProperty -LiteralPath $affPath -ErrorAction SilentlyContinue
$irqTag  = "Core 0 (Default)"
if ($null -ne $affProps -and $affProps.DevicePolicy -eq 4 -and $null -ne $affProps.AssignmentSetOverride) {
[uint64]$mVal = 0
for ($b = 0; $b -lt [math]::Min(8, $affProps.AssignmentSetOverride.Length); $b++) {
$mVal = $mVal -bor ([uint64]$affProps.AssignmentSetOverride[$b] -shl ($b * 8))
}
$cHint = if ($mVal -eq $core1Mask) { " (C1 Offloaded)" } elseif (($mVal -band $core0Mask) -ne 0) { " (C0)" } else { "" }
$irqTag = "0x$($mVal.ToString('X'))$cHint"
}
$descendants  = @([WinUltix.PnpTree]::GetDescendants($instanceId))
$endpoints    = [System.Collections.Generic.List[PSCustomObject]]::new()
$hubNames     = [System.Collections.Generic.List[string]]::new()
$hasMouse     = $false
$hasAudio     = $false
$hasStorage   = $false
$hasVr        = $false
$mouseLabel   = ""
$conflictList = [System.Collections.Generic.List[string]]::new()
$rootHubInfo  = $null
$hubSpeedMap  = @{}
$physDevices  = [System.Collections.Generic.List[PSCustomObject]]::new()
$currentPhys  = $null
foreach ($entry in $descendants) {
$parts = $entry -split '\|', 2
$depth = [int]$parts[0]
$devId = $parts[1]
foreach ($staleDepth in @($hubSpeedMap.Keys)) {
if ($staleDepth -ge $depth) {
[void]$hubSpeedMap.Remove($staleDepth)
}
}
if ($devId -match '^USB\\ROOT_HUB') {
$rootHubInfo = [WinUltix.UsbProberV2]::ProbeHub($devId)
$hubSpeedMap[$depth] = $rootHubInfo.PortSpeeds
continue
}
if ($devId -match '^(?i)(BTHENUM|BTHLE|SWD|MMDEVAPI)\\') { continue }
$regNode = "HKLM:\SYSTEM\CurrentControlSet\Enum\$devId"
$dProps  = Get-ItemProperty -LiteralPath $regNode -Name "FriendlyName", "DeviceDesc", "Service", "Class", "Address", "LocationInformation" -ErrorAction SilentlyContinue
if ($null -eq $dProps) { continue }
$rawDName = if ($dProps.FriendlyName) { $dProps.FriendlyName } else { $dProps.DeviceDesc }
$dName    = Format-UltixDeviceName -RawName $rawDName
$dSvc     = [string]$dProps.Service
$dCls     = [string]$dProps.Class
$busDesc  = [WinUltix.UsbProberV2]::GetBusReportedDesc($devId)
if ($dSvc -match '^(?i)(USBHUB3|usbhub)$') {
$subHub = [WinUltix.UsbProberV2]::ProbeHub($devId)
$hubSpeedMap[$depth] = $subHub.PortSpeeds
}
$parentHubDepth = $depth - 1
$isDirectChildOfHub = $hubSpeedMap.ContainsKey($parentHubDepth)
$isPhysicalUsbNode  = (
$isDirectChildOfHub -and
$devId -match '^USB\\(?!ROOT_HUB)[^\\]+\\[^\\]+$' -and
$devId -notmatch '(?i)&MI_' -and
(-not [string]::IsNullOrWhiteSpace($dSvc))
)
if ($isPhysicalUsbNode) {
$portNum = if ($null -ne $dProps.Address -and $dProps.Address -gt 0) {
[int]$dProps.Address
} elseif ($dProps.LocationInformation -match 'Port_#0*(\d+)') {
[int]$matches[1]
} else { 0 }
$negSpeed = ""
if ($portNum -gt 0 -and $hubSpeedMap[$parentHubDepth].ContainsKey($portNum)) {
$negSpeed = $hubSpeedMap[$parentHubDepth][$portNum]
}
$currentPhys = [PSCustomObject]@{
Depth       = $depth
DevId       = $devId
PortNumber  = $portNum
LinkSpeed   = $negSpeed
BusName     = $busDesc
BaseName    = $dName
BaseService = $dSvc
BaseClass   = $dCls
Children    = [System.Collections.Generic.List[PSCustomObject]]::new()
}
$physDevices.Add($currentPhys)
} elseif ($null -ne $currentPhys -and $depth -gt $currentPhys.Depth) {
$currentPhys.Children.Add([PSCustomObject]@{
Depth   = $depth
DevId   = $devId
Name    = $dName
BusName = $busDesc
Service = $dSvc
Class   = $dCls
})
}
}
foreach ($phys in $physDevices) {
$deviceNodes = @([PSCustomObject]@{ DevId = $phys.DevId; Name = $phys.BaseName; BusName = $phys.BusName; Service = $phys.BaseService; Class = $phys.BaseClass }) + @($phys.Children)
$bestName = $phys.BusName
if ([string]::IsNullOrWhiteSpace($bestName) -or $bestName -match '^(?i)(USB Receiver|USB Composite Device|Generic|USB Input Device|HID-compliant)') {
foreach ($n in $deviceNodes) {
if (-not [string]::IsNullOrWhiteSpace($n.BusName) -and $n.BusName -notmatch '^(?i)(USB Receiver|USB Composite Device|Generic|USB Input Device)') {
$bestName = $n.BusName
break
}
}
}
if ([string]::IsNullOrWhiteSpace($bestName) -or $bestName -match '^(?i)(USB Composite Device|Generic|USB Input Device|HID-compliant)') {
foreach ($n in $deviceNodes) {
if (-not [string]::IsNullOrWhiteSpace($n.Name) -and $n.Name -notmatch '^(?i)(USB Composite Device|Urz.dzenie kompozytowe|USB Input Device|Urz.dzenie wej.ciowe|HID Keyboard Device|Urz.dzenie klawiatury HID|HID-compliant|Zgodne z HID|Generic)') {
$bestName = $n.Name
break
}
}
}
if ([string]::IsNullOrWhiteSpace($bestName)) { $bestName = $phys.BaseName }
$role      = "[USB DEVICE]"
$activeSvc = if ($phys.BaseService) { $phys.BaseService } else { $phys.BaseClass }
$isStorage    = $false; $isCardReader = $false; $isAudio = $false; $isVr = $false; $isCam = $false; $isBt = $false; $isHub = $false
$isOnboardMcu = ($bestName -match '(?i)(AURA\s*LED|Mystic\s*Light|RGB\s*Fusion|Polychrome|ITE\s*Device|Nuvoton)')
$isWirelessRx = ($bestName -match '(?i)(Receiver|Lightspeed|HyperSpeed|Dongle|2\.4G|Unifying|Bolt)')
$hasMou       = $false; $hasKbd = $false
$mi00IsKbd    = $false; $mi00IsMou = $false
if ($phys.BaseClass -eq "Bluetooth" -or $phys.BaseService -match '^(?i)(BTHUSB|BTHMINI|ibtusb|BtFilter|RtkBtFilter)$' -or $bestName -match '(?i)\b(BT|Bluetooth)\b') {
$isBt = $true
$activeSvc = if ($phys.BaseService) { $phys.BaseService } else { "BTHUSB" }
}
foreach ($n in $deviceNodes) {
if ($isBt) { break }
if ($n.Service -match '^(?i)(AmUStor|rtsuer)$' -or $bestName -match '(?i)Card\s*Reader') {
$isCardReader = $true
if ($n.Service) { $activeSvc = $n.Service }
}
elseif ($n.Service -match '^(?i)(USBSTOR|UASPStor)$' -or $n.Class -eq "DiskDrive") {
$isStorage = $true
if ($n.Service -match '^(?i)(USBSTOR|UASPStor)$') { $activeSvc = $n.Service }
}
elseif ($n.Class -eq "Bluetooth" -or $n.Service -match '^(?i)(BTHUSB|BTHMINI|ibtusb)$') {
$isBt = $true
$activeSvc = if ($phys.BaseService) { $phys.BaseService } else { "BTHUSB" }
}
elseif ($n.Class -eq "Media" -or $n.Service -match '^(?i)(usbaudio|usbaudio2|iFiUsbAudio)' -or $n.Name -match '(?i)(DAC|iFi|Audio|Headset|Microphone|Sound)') {
if ($n.Class -ne "AudioEndpoint" -and $n.Class -ne "SoftwareDevice") {
$isAudio = $true
if ($n.Service) { $activeSvc = $n.Service }
}
}
elseif ($n.Name -match '(?i)(Index|Steam Frame|VR|HMD|Watchman|Tracker|Beyond)') { $isVr = $true; if ($n.Service) { $activeSvc = $n.Service } }
elseif ($n.Service -eq "usbvideo" -or $n.Class -in @("Camera", "Image")) { $isCam = $true; if ($n.Service) { $activeSvc = $n.Service } }
elseif ($n.Service -match '^(?i)(USBHUB3|usbhub)$') { $isHub = $true; $activeSvc = $n.Service }
elseif ($n.Service -eq "mouhid" -or $n.Class -eq "Mouse") {
$hasMou = $true
if ($n.DevId -match '(?i)&MI_00' -or $n.DevId -notmatch '(?i)&MI_0[1-9]') { $mi00IsMou = $true }
}
elseif ($n.Service -eq "kbdhid" -or $n.Class -eq "Keyboard") {
$hasKbd = $true
if ($n.DevId -match '(?i)&MI_00' -or $n.DevId -notmatch '(?i)&MI_0[1-9]') { $mi00IsKbd = $true }
}
}
if ($isHub)             { $role = "[USB HUB]" }
elseif ($isOnboardMcu)  { $role = "[ONBOARD MCU]"; $activeSvc = "Internal PCB RGB - Idle" }
elseif ($isBt)          { $role = "[BLUETOOTH]" }
elseif ($isCardReader)  { $role = "[CARD READER]" }
elseif ($isStorage)     { $role = "[STORAGE]";     $hasStorage = $true; $conflictList.Add("Storage: $bestName") }
elseif ($isVr)          { $role = "[VR / HMD]";    $hasVr      = $true }
elseif ($isAudio)       { $role = "[AUDIO / DAC]"; $hasAudio   = $true; $conflictList.Add("DAC: $bestName") }
elseif ($isCam)         { $role = "[VIDEO / CAM]"; $hasAudio   = $true; $conflictList.Add("Cam: $bestName") }
elseif ($hasMou -and $hasKbd) {
if ($isWirelessRx -or $mi00IsMou -or -not $mi00IsKbd) {
$role       = "[MOUSE / HID]"
$activeSvc  = "mouhid"
$hasMouse   = $true
$mouseLabel = $bestName
} else {
$role      = "[KEYBOARD]"
$activeSvc = "kbdhid"
}
}
elseif ($hasMou) { $role = "[MOUSE / HID]"; $activeSvc = "mouhid"; $hasMouse = $true; $mouseLabel = $bestName }
elseif ($hasKbd) { $role = "[KEYBOARD]";    $activeSvc = "kbdhid" }
elseif ($phys.Children | Where-Object { $_.Class -eq "HIDClass" -or $_.Service -eq "HidUsb" }) {
$role      = "[HID / INPUT]"
$activeSvc = "HidUsb"
}
$portBadge = if ($phys.PortNumber -gt 0) {
$pPrefix = if ($phys.Depth -le 2) { "Port #$($phys.PortNumber)" } else { "Hub Port #$($phys.PortNumber)" }
if ($phys.LinkSpeed) { " [$pPrefix | $($phys.LinkSpeed)]" } else { " [$pPrefix]" }
} else { "" }
if ($isHub) {
$hubNames.Add($bestName)
if (-not $IncludeRawHubs) { continue }
}
$endpoints.Add([PSCustomObject]@{
Role       = $role
Name       = "$bestName$portBadge"
InstanceId = $phys.DevId
Service    = $activeSvc
Depth      = $phys.Depth
})
}
if (-not $IncludeRawHubs -and $hubNames.Count -gt 0) {
$uniqueHubs = @($hubNames | Select-Object -Unique) -join ", "
$endpoints.Add([PSCustomObject]@{
Role       = "[ONBOARD HUBS]"
Name       = "$($hubNames.Count)x Passive USB 2.0/3.x Port Splitters ($uniqueHubs)"
InstanceId = "HUB_SUMMARY"
Service    = "0% DMA Load"
Depth      = 99
})
}
$portMapSummary = if ($venKey.PSChildName -match 'DEV_15B8') {
"1 Internal SoC Line (USB 2.0 480 Mbps - Unrouted on Desktop PCB)"
} elseif ($null -ne $rootHubInfo -and $rootHubInfo.TotalPorts -gt 0) {
$ssLabel = if ($ctrlName -match '(?i)(USB4|40G)' -or $venKey.PSChildName -match 'DEV_2426') {
"USB4 40 Gbps"
} elseif ($rootHubInfo.SsPlusPorts -gt 0 -or $ctrlName -match '(?i)(3\.2|3\.1)') {
"USB 3.x SuperSpeed (5/10/20 Gbps)"
} else {
"USB 3.0 SuperSpeed (5 Gbps)"
}
"$($rootHubInfo.TotalPorts) Logical Lines ($($rootHubInfo.Usb3Ports)x $ssLabel + $($rootHubInfo.Usb2Ports)x USB 2.0 High-Speed [480 Mbps] | Active: $($rootHubInfo.ActivePorts))"
} else {
"Root Hub port descriptor unavailable"
}
$statusAdvice = "Optimal Isolation"
$severity     = "Green"
if ($hasMouse -and ($hasAudio -or $hasStorage)) {
$confTargets  = ($conflictList | Select-Object -Unique) -join ", "
$statusAdvice = "[!] CONTENTION: Mouse ($mouseLabel) shares XHCI bus with $confTargets!"
$severity     = "Red"
} elseif (($hasMouse -or $hasVr) -and $routingBadge -match "CHIPSET") {
$statusAdvice = "[*] Notice: Latency-sensitive Mouse/VR is on Chipset PCH instead of CPU Direct lanes"
$severity     = "Yellow"
} elseif ($endpoints.Count -eq 0) {
if ($venKey.PSChildName -match 'DEV_15B8') {
$statusAdvice = "[Internal SoC USB 2.0 Node - Unrouted on Desktop PCB]"
} else {
$statusAdvice = "[Idle Root Hub - Free Ports Available]"
}
$severity = "Gray"
}
$controllers.Add([PSCustomObject]@{
ControllerName = $ctrlName
InstanceId     = $instanceId
RoutingBadge   = $routingBadge
PortSummary    = $portMapSummary
PciHops        = $pciBridgeHops
MsiEnabled     = $msiOn
IrqAffinity    = $irqTag
Endpoints      = @($endpoints)
Advice         = $statusAdvice
Severity       = $severity
})
}
}
return @($controllers | Sort-Object PciHops, ControllerName)
}
function Show-UsbTopologyModal {
$modal = New-Object System.Windows.Forms.Form
$modal.Text = "WinUltix - USB XHCI Root-Hub Topology & Contention Mapper"
$modal.Size = New-Object System.Drawing.Size(940, 680)
$modal.MinimumSize = New-Object System.Drawing.Size(880, 580)
$modal.StartPosition = "CenterParent"
$modal.FormBorderStyle = "Sizable"
$modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$modal.ForeColor = [System.Drawing.Color]::White
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = "Maps every physical USB XHCI controller back to the PCIe Root Complex. Keep 4K/8KHz mice and VR headsets on [CPU DIRECT SoC LANES] and isolate them from USB Audio DACs or external SSDs."
$lblDesc.Location = New-Object System.Drawing.Point(15, 12)
$lblDesc.Size = New-Object System.Drawing.Size(895, 36)
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblDesc.Anchor = 'Top, Left, Right'
$rtbMap = New-Object System.Windows.Forms.RichTextBox
$rtbMap.Location = New-Object System.Drawing.Point(15, 52)
$rtbMap.Size = New-Object System.Drawing.Size(895, 525)
$rtbMap.BackColor = [System.Drawing.Color]::FromArgb(255, 18, 18, 18)
$rtbMap.ForeColor = [System.Drawing.Color]::LightGray
$rtbMap.BorderStyle = "FixedSingle"
$rtbMap.ReadOnly = $true
$rtbMap.Font = New-Object System.Drawing.Font("Consolas", 9.8)
$rtbMap.Anchor = 'Top, Bottom, Left, Right'
$chkShowHubs = New-Object System.Windows.Forms.CheckBox
$chkShowHubs.Text = "Show Raw USB Hub Nodes"
$chkShowHubs.Location = New-Object System.Drawing.Point(440, 595)
$chkShowHubs.Size = New-Object System.Drawing.Size(210, 24)
$chkShowHubs.ForeColor = [System.Drawing.Color]::LightGray
$chkShowHubs.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$chkShowHubs.Anchor = 'Bottom, Left'
$chkShowHubs.Checked = $false
$appendColored = {
param([string]$Text, [System.Drawing.Color]$Color)
$rtbMap.SelectionStart  = $rtbMap.TextLength
$rtbMap.SelectionLength = 0
$rtbMap.SelectionColor  = $Color
$rtbMap.AppendText($Text)
}
$renderTopology = {
$rtbMap.Clear()
& $appendColored "================================================================================`r`n" ([System.Drawing.Color]::FromArgb(255, 70, 70, 70))
& $appendColored "QUICK WIRING GUIDE & HOW TO READ THIS TOPOLOGY MAP:`r`n" ([System.Drawing.Color]::Gold)
& $appendColored "  1. [CPU DIRECT SoC] : Wired straight to CPU silicon (1 Hop). Best for 4K/8KHz Mice & VR.`r`n" ([System.Drawing.Color]::Cyan)
& $appendColored "  2. [CHIPSET PCH]    : Routed via motherboard chipset. Ideal for USB Audio DACs, Keyboards & Drives.`r`n" ([System.Drawing.Color]::LightSkyBlue)
& $appendColored "  3. XHCI Isolation   : NEVER share one controller between an 8KHz Mouse and an Audio DAC or USB Drive.`r`n" ([System.Drawing.Color]::LightGreen)
& $appendColored "  4. Logical Lines    : Every physical USB 3.x port contains 2 logical lines (1x SuperSpeed + 1x USB 2.0).`r`n" ([System.Drawing.Color]::Silver)
& $appendColored "  5. Onboard Hubs/MCU : Passive PCB splitters (ASM107x) & static RGB (AURA) do NOT disturb Audio DACs.`r`n" ([System.Drawing.Color]::DarkGray)
$map = Get-UsbTopologyMap -IncludeRawHubs:($chkShowHubs.Checked)
$idx = 0
foreach ($ctrl in $map) {
$idx++
$hdrColor = if ($ctrl.RoutingBadge -match "CPU DIRECT") { [System.Drawing.Color]::Cyan } else { [System.Drawing.Color]::LightSkyBlue }
& $appendColored "================================================================================`r`n" ([System.Drawing.Color]::FromArgb(255, 70, 70, 70))
& $appendColored "CONTROLLER #$idx : $($ctrl.ControllerName)`r`n" $hdrColor
& $appendColored "  PCIe Routing : $($ctrl.RoutingBadge)`r`n" $hdrColor
& $appendColored "  PCI ID & IRQ : $($ctrl.InstanceId) | MSI: $(if($ctrl.MsiEnabled){'ON'}else{'OFF'}) | IRQ: $($ctrl.IrqAffinity)`r`n" ([System.Drawing.Color]::Silver)
& $appendColored "  Root Hub Map : $($ctrl.PortSummary)`r`n" ([System.Drawing.Color]::LightSkyBlue)
$advColor = switch ($ctrl.Severity) {
"Red"    { [System.Drawing.Color]::OrangeRed; break }
"Yellow" { [System.Drawing.Color]::Gold;      break }
"Green"  { [System.Drawing.Color]::LightGreen; break }
default  { [System.Drawing.Color]::DarkGray;  break }
}
& $appendColored "  Assessment   : $($ctrl.Advice)`r`n" $advColor
if ($ctrl.Endpoints.Count -gt 0) {
& $appendColored "  Connected Endpoints:`r`n" ([System.Drawing.Color]::White)
foreach ($ep in $ctrl.Endpoints) {
$epColor = switch -Wildcard ($ep.Role) {
"*MOUSE*"   { [System.Drawing.Color]::LightGreen; break }
"*AUDIO*"   { [System.Drawing.Color]::Violet;     break }
"*VR*"      { [System.Drawing.Color]::Cyan;       break }
"*STORAGE*" { [System.Drawing.Color]::Orange;     break }
"*ONBOARD*" { [System.Drawing.Color]::DarkGray;   break }
"*HUB*"     { [System.Drawing.Color]::DarkGray;   break }
default     { [System.Drawing.Color]::LightGray;  break }
}
& $appendColored ("    +-- {0,-15} {1} ({2})`r`n" -f $ep.Role, $ep.Name, $ep.Service) $epColor
}
} else {
& $appendColored "    +-- (No active external USB endpoints attached)`r`n" ([System.Drawing.Color]::DarkGray)
}
& $appendColored "`r`n" ([System.Drawing.Color]::LightGray)
}
$rtbMap.SelectionStart = 0
$rtbMap.ScrollToCaret()
}
&$renderTopology
$chkShowHubs.Add_CheckedChanged({ &$renderTopology }.GetNewClosure())
$btnRefresh = New-UltixButton -Parent $modal -Text "Rescan USB Tree (Live)" -X 15 -Y 590 -Width 200 -Height 35 -RGB @(60, 100, 150)
$btnRefresh.Anchor = 'Bottom, Left'
$btnRefresh.Add_Click({ &$renderTopology }.GetNewClosure())
$btnExportLog = New-UltixButton -Parent $modal -Text "Print Map to Main Log" -X 225 -Y 590 -Width 200 -Height 35 -RGB @(50, 110, 70)
$btnExportLog.Anchor = 'Bottom, Left'
$btnExportLog.Add_Click({
Write-GUI "=== USB XHCI ROOT-HUB & PCIE TOPOLOGY MAP ==="
foreach ($line in ($rtbMap.Text -split '\r?\n')) {
if (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^===') {
Write-GUI "  $line"
}
}
Write-GUI ""
}.GetNewClosure())
$btnClose = New-UltixButton -Parent $modal -Text "Close" -X 790 -Y 590 -Width 120 -Height 35 -RGB @(60, 60, 60)
$btnClose.Anchor = 'Bottom, Right'
$btnClose.DialogResult = "Cancel"
$modal.Controls.AddRange(@($lblDesc, $rtbMap, $chkShowHubs))
try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}
function Get-QuantumSchedulerInfo {
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
$rawVal  = (Get-ItemProperty -LiteralPath $regPath -Name "Win32PrioritySeparation" -ErrorAction SilentlyContinue).Win32PrioritySeparation
if ($null -eq $rawVal) { $rawVal = 2 }
$lenBits   = ($rawVal -shr 4) -band 3
$varBits   = ($rawVal -shr 2) -band 3
$boostBits = $rawVal -band 3
$lenStr = switch ($lenBits) {
2 { "Short Quantum (Low Input Latency)" }
1 { "Long Quantum (High Throughput / Workstation)" }
default { "OS Default (Short on Client SKU)" }
}
$varStr = switch ($varBits) {
1 { "Variable (Foreground Boosted vs Background)" }
2 { "Fixed (Equal Determinism Across Threads)" }
default { "OS Default (Variable on Client SKU)" }
}
$boostStr = switch ($boostBits) {
2 { "3:1 Foreground Ratio (Max Gaming Boost)" }
1 { "2:1 Foreground Ratio (Moderate Boost)" }
default { "1:1 Equal Slice (No Foreground Bias)" }
}
$binStr = [Convert]::ToString(([int]$rawVal -band 0x3F), 2).PadLeft(6, '0')
$bitFormatted = "$($binStr.Substring(0,2))|$($binStr.Substring(2,2))|$($binStr.Substring(4,2))"
return [PSCustomObject]@{
DecimalValue = [int]$rawVal
HexValue     = ("0x{0:X2}" -f [int]$rawVal)
BitMask      = $bitFormatted
LengthDesc   = $lenStr
VarDesc      = $varStr
BoostDesc    = $boostStr
}
}
function Show-QuantumSchedulerModal {
$modal = New-Object System.Windows.Forms.Form
$modal.Text = "WinUltix - Quantum Scheduler Matrix (Win32PrioritySeparation)"
$modal.Size = New-Object System.Drawing.Size(760, 520)
$modal.MinimumSize = New-Object System.Drawing.Size(760, 520)
$modal.StartPosition = "CenterParent"
$modal.FormBorderStyle = "FixedDialog"
$modal.MaximizeBox = $false
$modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$modal.ForeColor = [System.Drawing.Color]::White
$modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = "Modifies HKLM\...\PriorityControl\Win32PrioritySeparation. The Windows kernel (PsChangeQuantumTable) applies changes INSTANTLY in real time without a reboot, allowing live A/B testing in games."
$lblDesc.Location = New-Object System.Drawing.Point(15, 12)
$lblDesc.Size = New-Object System.Drawing.Size(715, 38)
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblTelemetry = New-Object System.Windows.Forms.Label
$lblTelemetry.Location = New-Object System.Drawing.Point(15, 55)
$lblTelemetry.Size = New-Object System.Drawing.Size(715, 72)
$lblTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
$lblTelemetry.ForeColor = [System.Drawing.Color]::LightGreen
$lblTelemetry.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTelemetry.BorderStyle = "FixedSingle"
$lblTelemetry.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$profiles = @(
[PSCustomObject]@{ Value = 38; Hex = "0x26"; Name = "0x26 (38 dec) | Short | Variable | 3:1 Foreground Boost [Competitive FPS]"; Desc = "Fastest context switching + 3x CPU time slice for the active game window. Best for CS2, Valorant, Overwatch, and Apex." }
[PSCustomObject]@{ Value = 40; Hex = "0x28"; Name = "0x28 (40 dec) | Short | Fixed    | 1:1 Equal Slice      [WinUltix Heavy Default]"; Desc = "Deterministic fixed quantum. Prevents foreground render threads from starving audio (audiodg) or worker threads in UE5/heavy titles." }
[PSCustomObject]@{ Value = 42; Hex = "0x2A"; Name = "0x2A (42 dec) | Short | Fixed    | 3:1 Hybrid Matrix    [Enthusiast Low-Jitter]"; Desc = "Combines Fixed quantum bitmask (10) with maximum quantum table index (10). Popular among competitive latency tuners." }
[PSCustomObject]@{ Value = 22; Hex = "0x16"; Name = "0x16 (22 dec) | Long  | Variable | 3:1 Foreground Boost [Cache-Heavy Simulators]"; Desc = "Longer execution slices reduce context-switch L1/L2 cache flushes. Useful in MSFS, Tarkov, or strategy sims." }
[PSCustomObject]@{ Value = 2;  Hex = "0x02"; Name = "0x02 (2 dec)  | OS Default       | 3:1 Standard Client  [Windows 11 Factory]"; Desc = "Standard Windows 11 out-of-the-box scheduler behavior (6:2 quantum ticks)." }
)
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(15, 140)
$listBox.Size = New-Object System.Drawing.Size(715, 165)
$listBox.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38)
$listBox.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
$listBox.BorderStyle = "FixedSingle"
$listBox.Font = New-Object System.Drawing.Font("Consolas", 10.5)
foreach ($p in $profiles) { [void]$listBox.Items.Add($p.Name) }
$lblDetail = New-Object System.Windows.Forms.Label
$lblDetail.Location = New-Object System.Drawing.Point(15, 315)
$lblDetail.Size = New-Object System.Drawing.Size(715, 45)
$lblDetail.ForeColor = [System.Drawing.Color]::Silver
$lblDetail.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Italic)
$refreshInfo = {
$info = Get-QuantumSchedulerInfo
$lblTelemetry.Text = "ACTIVE KERNEL STATE : $($info.HexValue) ($($info.DecimalValue) dec) | 6-Bit Mask (AA|BB|CC): [$($info.BitMask)]`r`n" +
"QUANTUM LENGTH      : $($info.LengthDesc)`r`n" +
"SCHEDULER MODE      : $($info.VarDesc) | $($info.BoostDesc)"
for ($i = 0; $i -lt $profiles.Count; $i++) {
if ($profiles[$i].Value -eq $info.DecimalValue) {
$listBox.SelectedIndex = $i
break
}
}
}
$listBox.Add_SelectedIndexChanged({
if ($listBox.SelectedIndex -ge 0) {
$lblDetail.Text = "Engineering Note: " + $profiles[$listBox.SelectedIndex].Desc
}
}.GetNewClosure())
&$refreshInfo
if ($listBox.SelectedIndex -lt 0) { $listBox.SelectedIndex = 0 }
$btnApply = New-UltixButton -Parent $modal -Text "Apply Selected Quantum (Live - Zero Reboot)" -X 15 -Y 425 -Width 330 -Height 38 -RGB @(150, 60, 60)
$btnApply.Add_Click({
if ($listBox.SelectedIndex -lt 0) { return }
$sel = $profiles[$listBox.SelectedIndex]
Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value $sel.Value -Type DWord -Force
Write-GUI " -> [LIVE QUANTUM] Enforced Win32PrioritySeparation = $($sel.Hex) ($($sel.Value) dec) [$($sel.Name)]"
&$refreshInfo
}.GetNewClosure())
$btnReset = New-UltixButton -Parent $modal -Text "Restore Factory (0x02)" -X 355 -Y 425 -Width 200 -Height 38 -RGB @(60, 100, 150)
$btnReset.Add_Click({
Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force
Write-GUI " -> [LIVE QUANTUM] Restored factory Win32PrioritySeparation = 0x02 (2 dec)."
&$refreshInfo
}.GetNewClosure())
$btnClose = New-UltixButton -Parent $modal -Text "Close" -X 610 -Y 425 -Width 120 -Height 38 -RGB @(60, 60, 60)
$btnClose.DialogResult = "Cancel"
$modal.Controls.AddRange(@($lblDesc, $lblTelemetry, $listBox, $lblDetail))
try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}
function Initialize-Z7UI {
param([System.Windows.Forms.TabControl]$TabControl)
$tab = New-Object System.Windows.Forms.TabPage
$tab.Text = "Hardware"
$tab.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)
$topo = Get-CPUTopologyProfile
$lblPreFlight = New-Object System.Windows.Forms.Label
$lblPreFlight.Text = "Pre-Flight CPU Affinity & CPPC P-State Control"
$lblPreFlight.Location = New-Object System.Drawing.Point(15, 14)
$lblPreFlight.Size = New-Object System.Drawing.Size(370, 18)
$lblPreFlight.ForeColor = [System.Drawing.Color]::DarkGray
$lblPreFlight.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
if ($topo.IsSupported) {
[void](New-UltixButton -Parent $tab -X 15 -Y 36 -Width 240 -Height 40 -RGB @(135, 50, 50) `
-Text "Affinity Lasso (CPU Core Lock)" `
-Description "Lock background apps to specific cores ($($topo.CoreDesc)) to free up prime gaming cores." `
-OnClick ({ Show-AffinityModal "Affinity Lasso - $($topo.Label)" "Lock background processes to $($topo.CoreDesc) with BelowNormal priority." }.GetNewClosure()))
} else {
$btnAffinity = New-UltixButton -Parent $tab -X 15 -Y 36 -Width 240 -Height 40 -RGB @(45, 45, 48) `
-ForeColor ([System.Drawing.Color]::DarkGray) `
-Text "Affinity Lasso (Requires 6+ Cores)" `
-Description "Affinity Lasso is disabled on 2-Core and 4-Core CPUs because locking background threads leaves too few cores for games."
$btnAffinity.Enabled = $false
}
[void](New-UltixButton -Parent $tab -X 15 -Y 86 -Width 240 -Height 40 -RGB @(55, 58, 64) `
-Text "CPPC P-State Unhider" `
-Description "Unhide and manage advanced AMD/Intel CPPC power states with an automatic SYSTEM Dead Man's Switch." `
-OnClick { Show-CPPCModal "CPPC Management" "Unhide advanced power plan settings (EPP, Demote, Promote)." })
[void](New-UltixButton -Parent $tab -X 265 -Y 36 -Width 120 -Height 90 -RGB @(45, 85, 125) `
-Text "Generate Pre-Flight Shortcut" `
-Description "Create a desktop shortcut to instantly toggle CPU Affinity Lasso and Max CPPC rules right before launching a game." `
-OnClick { New-PreFlightShortcut })
$lblColLeft = New-Object System.Windows.Forms.Label
$lblColLeft.Text = "Scheduler, Timer & Bus"
$lblColLeft.Location = New-Object System.Drawing.Point(15, 138)
$lblColLeft.Size = New-Object System.Drawing.Size(180, 18)
$lblColLeft.ForeColor = [System.Drawing.Color]::DarkGray
$lblColLeft.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblColRight = New-Object System.Windows.Forms.Label
$lblColRight.Text = "IRQ, USB & OC Diagnostics"
$lblColRight.Location = New-Object System.Drawing.Point(205, 138)
$lblColRight.Size = New-Object System.Drawing.Size(180, 18)
$lblColRight.ForeColor = [System.Drawing.Color]::DarkGray
$lblColRight.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
[void](New-UltixButton -Parent $tab -X 15 -Y 160 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "Quantum Scheduler Matrix" `
-Description "Live Win32PrioritySeparation quantum tuner (0x26, 0x28, 0x2A, 0x16, 0x02). Changes apply in real time without rebooting." `
-OnClick { Show-QuantumSchedulerModal })
[void](New-UltixButton -Parent $tab -X 205 -Y 160 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "MSI & IRQ Affinity Enforcer" `
-Description "Force Message Signaled Interrupts (MSI), set Interrupt Priority, offload IRQs from Core 0, and monitor live kernel DPCs." `
-OnClick { Show-MsiModal "MSI & IRQ Affinity Enforcer" "Force PCI devices into MSI mode, adjust interrupt priority, and offload high-DPC drivers (GPU/NIC) from Core 0." })
[void](New-UltixButton -Parent $tab -X 15 -Y 210 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "System Timer & TSC (0.5ms)" `
-Description "Fix Windows 11 API to allow global 0.5ms High Resolution Timers and force CPU TSC." `
-OnClick { Show-TimerModal "Timer Resolution Subsystem" "Enable legacy 0.5ms requests globally and stabilize DPC latency." })
[void](New-UltixButton -Parent $tab -X 205 -Y 210 -Width 180 -Height 40 -RGB @(45, 85, 125) `
-Text "USB XHCI Topology Map" `
-Description "Maps physical USB XHCI controllers to CPU Direct PCIe lanes vs Chipset PCH bridges, and spots Mouse/DAC/VR bus contention." `
-OnClick { Show-UsbTopologyModal })
[void](New-UltixButton -Parent $tab -X 15 -Y 260 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "I/O & Memory Optimizer" `
-Description "Disable NVMe APST, PCIe ASPM, and System Memory Compression to reduce CPU overhead and micro-stuttering." `
-OnClick { Show-NVMeModal "I/O & Memory Optimizer" "Prevent NVMe and PCIe bus from entering low-power states (D3hot/L1.2) and disable RAM compression." })
[void](New-UltixButton -Parent $tab -X 205 -Y 260 -Width 180 -Height 40 -RGB @(55, 58, 64) `
-Text "Network NDIS & TCP Tuner" `
-Description "Configure low-latency NDIS parameters, TCP properties, and offloads with full symmetric revert." `
-OnClick { Show-NetworkModal "Network Optimizer" "Disable flow control, power saving, interrupt moderation, and enforce TCPNoDelay." })
[void](New-UltixButton -Parent $tab -X 15 -Y 310 -Width 370 -Height 40 -RGB @(45, 85, 125) `
-Text "WHEA Hardware Error Logger & OC Decoder" `
-Description "Scan system logs for hardware instability (Curve Optimizer / FCLK / DDR5 timings) and decode APIC IDs to physical CPU cores." `
-OnClick { Show-WHEAModal "WHEA Logger" "Analyze hardware errors to find unstable CPU cores or RAM." })
$lblDpcHeader = New-Object System.Windows.Forms.Label
$lblDpcHeader.Text = "Live Kernel Interrupt / DPC Distribution Monitor (ntdll.dll)"
$lblDpcHeader.Location = New-Object System.Drawing.Point(15, 365)
$lblDpcHeader.Size = New-Object System.Drawing.Size(370, 20)
$lblDpcHeader.ForeColor = [System.Drawing.Color]::DarkGray
$lblDpcHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTabDpc = New-Object System.Windows.Forms.Label
$lblTabDpc.Location = New-Object System.Drawing.Point(15, 387)
$lblTabDpc.Size = New-Object System.Drawing.Size(370, 68)
$lblTabDpc.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
$lblTabDpc.ForeColor = [System.Drawing.Color]::LightSkyBlue
$lblTabDpc.Font = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Bold)
$lblTabDpc.TextAlign = "TopLeft"
$lblTabDpc.BorderStyle = "FixedSingle"
$lblTabDpc.Padding = New-Object System.Windows.Forms.Padding(5, 5, 5, 4)
$lblTabLegend = New-Object System.Windows.Forms.Label
$lblTabLegend.Text = "C0..Cn = Physical Cores (SMT: 2 LP#/Core) | LP# = Logical Thread`r`nColor = Core 0 Load: Green (<30%) | Yellow (30-54%) | Red (>=55%)"
$lblTabLegend.Location = New-Object System.Drawing.Point(15, 459)
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
$btnToggleDpc = New-UltixButton -Parent $tab -X 15 -Y 495 -Width 320 -Height 36 -RGB @(45, 85, 125) `
-Text "Start Live DPC Monitor (1Hz Stream)" `
-Description "Toggles real-time 1Hz polling of ntdll!NtQuerySystemInformation (SystemInterruptInformation). Automatically pauses if you switch tabs."
$btnHelpDpc = New-UltixButton -Parent $tab -X 345 -Y 495 -Width 40 -Height 36 -RGB @(72, 76, 82) `
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
$this.BackColor   = [System.Drawing.Color]::FromArgb(255, 45, 95, 60)
Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
$timer.Start()
Write-GUI " -> Live Kernel DPC Monitor started (1Hz polling)."
} else {
$timer.Stop()
$state.IsRunning = $false
$this.Text       = "Start Live DPC Monitor (1Hz Stream)"
$this.BackColor  = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
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
$tab.Controls.AddRange(@($lblPreFlight, $lblColLeft, $lblColRight, $lblDpcHeader, $lblTabDpc, $lblTabLegend))
$TabControl.Controls.Add($tab)
}
$Global:UltixToolkitFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($fn in (Get-ChildItem -Path Function:\)) {
if (-not $baselineFunctions.Contains($fn.Name)) {
$Global:UltixToolkitFunctions.Add($fn.Name)
Set-Item -Path "Function:\global:$($fn.Name)" -Value $fn.ScriptBlock -Force -ErrorAction SilentlyContinue
}
}
[WinUltix.NativeMethods]::EnableGdiDpiScaling()
[System.Windows.Forms.Application]::EnableVisualStyles()
$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "WinUltix - Ultimate System Toolkit $AppVersion"
$global:form.Size = New-Object System.Drawing.Size(1280, 800)
$global:form.MinimumSize = New-Object System.Drawing.Size(1260, 750)
$global:form.StartPosition = "CenterScreen"
$global:form.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$global:form.FormBorderStyle = "Sizable"
$global:form.MaximizeBox = $true
$global:form.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$global:descBox = New-Object System.Windows.Forms.TextBox
$global:descBox.Multiline = $true; $global:descBox.Location = New-Object System.Drawing.Point(440, 20)
$global:descBox.Size = New-Object System.Drawing.Size(800, 80)
$global:descBox.BackColor = [System.Drawing.Color]::FromArgb(255, 25, 25, 25); $global:descBox.ForeColor = [System.Drawing.Color]::LightSkyBlue; $global:descBox.ReadOnly = $true; $global:descBox.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Italic)
$global:descBox.Text = "Hover over any button to see operation details."
$global:descBox.Anchor = 'Top, Left, Right'
$global:infoBox = New-Object System.Windows.Forms.RichTextBox
$global:infoBox.Multiline = $true
$global:infoBox.Location = New-Object System.Drawing.Point(440, 110)
$global:infoBox.Size = New-Object System.Drawing.Size(800, 610)
$global:infoBox.BackColor = [System.Drawing.Color]::FromArgb(255, 15, 15, 15)
$global:infoBox.ForeColor = [System.Drawing.Color]::LightGray
$global:infoBox.BorderStyle = "FixedSingle"
$global:infoBox.ReadOnly = $true
$global:infoBox.DetectUrls = $false
$global:infoBox.ScrollBars = "Vertical"
$global:infoBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$global:infoBox.Anchor = 'Top, Bottom, Left, Right'
Write-UltixSystemBanner -StatusMessage "Ready for deployment. Modular architecture loaded successfully."
$global:tabControl = New-Object WinUltix.DarkTabControl
$global:tabControl.Location = New-Object System.Drawing.Point(10, 20)
$global:tabControl.Size = New-Object System.Drawing.Size(410, 700)
$global:tabControl.Anchor = 'Top, Bottom, Left'
$global:progBar = New-Object WinUltix.DarkProgressBar
$global:progBar.Location = New-Object System.Drawing.Point(440, 725)
$global:progBar.Size = New-Object System.Drawing.Size(510, 25)
$global:progBar.Minimum = 0
$global:progBar.Maximum = 100
$global:progBar.Anchor = 'Bottom, Left, Right'
Initialize-Z1UI -TabControl $global:tabControl
Initialize-Z2UI -TabControl $global:tabControl
Initialize-Z3UI -TabControl $global:tabControl
Initialize-Z4UI -TabControl $global:tabControl
Initialize-Z5UI -TabControl $global:tabControl
Initialize-Z6UI -TabControl $global:tabControl
Initialize-Z7UI -TabControl $global:tabControl
$btnExportLog = New-Object System.Windows.Forms.Button
$btnExportLog.Text = "Export Log to Desktop"
$btnExportLog.Location = New-Object System.Drawing.Point(970, 725)
$btnExportLog.Size = New-Object System.Drawing.Size(150, 25)
$btnExportLog.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
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
$btnClearLog.Location = New-Object System.Drawing.Point(1130, 725)
$btnClearLog.Size = New-Object System.Drawing.Size(110, 25)
$btnClearLog.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 48)
$btnClearLog.ForeColor = [System.Drawing.Color]::LightGray
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Anchor = 'Bottom, Right'
$btnClearLog.Add_Click({
$global:infoBox.Clear()
Write-UltixSystemBanner -StatusMessage "Ready for deployment."
})
$btnCredits = New-Object System.Windows.Forms.Button
$btnCredits.Text = "[ About / GitHub ]"
$btnCredits.Location = New-Object System.Drawing.Point(10, 725)
$btnCredits.Size = New-Object System.Drawing.Size(130, 25)
$btnCredits.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 48)
$btnCredits.ForeColor = [System.Drawing.Color]::LightGray
$btnCredits.FlatStyle = "Flat"
$btnCredits.Anchor = 'Bottom, Left'
$btnCredits.Add_Click({
$aboutForm = New-Object System.Windows.Forms.Form
$aboutForm.Text = "About WinUltix"
$aboutForm.Size = New-Object System.Drawing.Size(420, 270)
$aboutForm.StartPosition = "CenterParent"
$aboutForm.FormBorderStyle = "FixedDialog"
$aboutForm.MaximizeBox = $false
$aboutForm.MinimizeBox = $false
$aboutForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$aboutForm.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = New-Object System.Drawing.Point(20, 22)
$picLogo.Size = New-Object System.Drawing.Size(64, 64)
$picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$srcLogo = if ($null -ne $global:UltixHighResLogo) {
$global:UltixHighResLogo
} elseif ($null -ne $global:UltixAppIcon) {
$global:UltixAppIcon.ToBitmap()
} else { $null }
if ($null -ne $srcLogo) {
$bmpLogo = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gLogo   = [System.Drawing.Graphics]::FromImage($bmpLogo)
$gLogo.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gLogo.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gLogo.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gLogo.DrawImage($srcLogo, 0, 0, 64, 64)
$gLogo.Dispose()
$picLogo.Image = $bmpLogo
}
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = New-Object System.Drawing.Point(98, 20)
$lblTitle.Size = New-Object System.Drawing.Size(295, 24)
$lblTitle.ForeColor = [System.Drawing.Color]::Cyan
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.Text = "WinUltix $AppVersion"
$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.Location = New-Object System.Drawing.Point(98, 46)
$lblAbout.Size = New-Object System.Drawing.Size(295, 65)
$lblAbout.ForeColor = [System.Drawing.Color]::LightGray
$lblAbout.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblAbout.Text = "Ultimate Windows System and Hardware Toolkit`nConcept, architecture and combat tests: Firever`nCoding assistance: Gemini AI"
$linkGit = New-Object System.Windows.Forms.LinkLabel
$linkGit.Location = New-Object System.Drawing.Point(20, 120)
$linkGit.Size = New-Object System.Drawing.Size(370, 20)
$linkGit.LinkColor = [System.Drawing.Color]::LightSkyBlue
$linkGit.ActiveLinkColor = [System.Drawing.Color]::Cyan
$linkGit.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$linkGit.Text = "https://github.com/Firever-ultix/WinUltix"
$linkGit.Add_LinkClicked({ Start-Process "https://github.com/Firever-ultix/WinUltix" -ErrorAction SilentlyContinue })
$linkcoffee = New-Object System.Windows.Forms.LinkLabel
$linkcoffee.Location = New-Object System.Drawing.Point(20, 145)
$linkcoffee.Size = New-Object System.Drawing.Size(370, 20)
$linkcoffee.LinkColor = [System.Drawing.Color]::LightSkyBlue
$linkcoffee.ActiveLinkColor = [System.Drawing.Color]::Cyan
$linkcoffee.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$linkcoffee.Text = "https://buymeacoffee.com/firever"
$linkcoffee.Add_LinkClicked({ Start-Process "https://buymeacoffee.com/firever" -ErrorAction SilentlyContinue })
$btnAboutOK = New-Object System.Windows.Forms.Button
$btnAboutOK.Text = "Close"
$btnAboutOK.Location = New-Object System.Drawing.Point(160, 185)
$btnAboutOK.Size = New-Object System.Drawing.Size(90, 28)
$btnAboutOK.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
$btnAboutOK.ForeColor = [System.Drawing.Color]::White
$btnAboutOK.FlatStyle = "Flat"
$btnAboutOK.Add_Click({ $aboutForm.Close() })
$aboutForm.Controls.AddRange(@($picLogo, $lblTitle, $lblAbout, $linkGit, $linkcoffee, $btnAboutOK))
try {
[void]$aboutForm.ShowDialog($global:form)
} finally {
if ($null -ne $picLogo.Image) { $picLogo.Image.Dispose() }
$aboutForm.Dispose()
}
})
$btnExportProfile = New-Object System.Windows.Forms.Button
$btnExportProfile.Text = "[ Export Profile ]"
$btnExportProfile.Location = New-Object System.Drawing.Point(150, 725)
$btnExportProfile.Size = New-Object System.Drawing.Size(130, 25)
$btnExportProfile.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnExportProfile.ForeColor = [System.Drawing.Color]::White
$btnExportProfile.FlatStyle = "Flat"
$btnExportProfile.Anchor = 'Bottom, Left'
$btnExportProfile.Add_MouseEnter({ Show-Description "Exports your active Registry tweaks, SRP locks, Services state, and Affinity Lasso roster into a portable JSON snapshot." })
$btnExportProfile.Add_MouseLeave({ Restore-Log })
$btnExportProfile.Add_Click({ Export-WinUltixProfile -ControlsToDisable @($btnExportProfile, $btnImportProfile) })
$btnImportProfile = New-Object System.Windows.Forms.Button
$btnImportProfile.Text = "[ Import Profile ]"
$btnImportProfile.Location = New-Object System.Drawing.Point(290, 725)
$btnImportProfile.Size = New-Object System.Drawing.Size(130, 25)
$btnImportProfile.BackColor = [System.Drawing.Color]::FromArgb(255, 135, 50, 50)
$btnImportProfile.ForeColor = [System.Drawing.Color]::White
$btnImportProfile.FlatStyle = "Flat"
$btnImportProfile.Anchor = 'Bottom, Left'
$btnImportProfile.Add_MouseEnter({ Show-Description "Imports and enforces a previously saved WinUltix JSON configuration snapshot on this machine." })
$btnImportProfile.Add_MouseLeave({ Restore-Log })
$btnImportProfile.Add_Click({ Import-WinUltixProfile -ControlsToDisable @($btnExportProfile, $btnImportProfile) })
$global:form.Controls.AddRange(@(
$btnClearLog, $btnExportLog, $global:progBar,
$btnCredits, $btnExportProfile, $btnImportProfile,
$global:descBox, $global:tabControl, $global:infoBox
))
foreach ($tab in $global:tabControl.TabPages) {
foreach ($ctrl in $tab.Controls) {
if ($ctrl -is [System.Windows.Forms.Button]) {
$ctrl.Add_MouseLeave({ Restore-Log })
}
}
}
$global:form.Add_Shown({
try {
$ev = [System.Threading.EventWaitHandle]::OpenExisting("Local\WinUltix_Splash_Close")
[void]$ev.Set()
$ev.Dispose()
} catch { }
$this.Activate()
})
Update-DNSLabel
try {
[void]$global:form.ShowDialog()
} finally {
$global:form.Dispose()
if ($null -ne $global:UltixHighResLogo) {
$global:UltixHighResLogo.Dispose()
$global:UltixHighResLogo = $null
}
if ($null -ne $global:UltixAppIcon) {
$global:UltixAppIcon.Dispose()
$global:UltixAppIcon = $null
}
}
