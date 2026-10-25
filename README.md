> 🔗 **Part of the Ultix Ecosystem:**
> Looking for a clean, pre-debloated Windows 11 ISO deployment? Check out **[AutoUltixed](https://github.com/Firever-ultix/AutoUltixed)**.
> Looking for live post-install hardware & OS tuning? You are at **[WinUltix Pro](https://github.com/Firever-ultix/WinUltix)**.

# WinUltix Pro 2.7 🚀
**An Advanced, Portable, Zero-Dependency Windows 11 (24H2 / 25H2 / 26H2) Optimizer & Hardware Tuning Toolkit**

For years, I’ve been collecting various registry tweaks, optimization scripts, and diagnostics scattered across the internet. WinUltix was born to unify them.

With version 2.7, the project has evolved from a simple debloater into a heavily engineered, asynchronous diagnostic and low-level tuning suite (~300KB across 9 modular files). I completely abandoned legacy WMI functions and `wmic.exe` dependencies in favor of strict modular encapsulation, native CIM pipelines, isolated multithreaded Runspaces, direct kernel-level registry manipulation, and deep hardware inspection.

Most "optimizers" on the market are black boxes that silently hijack OS privileges and break system integrity. WinUltix Pro is a **100% transparent, interactive, and symmetrically reversible** toolkit that puts *you* in complete control of your OS, network stack, and hardware interrupts.

![WinUltix Main Interface](assets/1.jpg)

### 🛡️ Core Architecture & Philosophy
* **Modular Encapsulation:** The main `WinUltix_Pro.ps1` is purely a lightweight UI launcher with deterministic GDI/HWND resource disposal. All execution logic is safely sandboxed across `Core_Helpers.ps1` and isolated `Z1` to `Z7` modules.
* **Global Asynchronous Runspace Engine (`Invoke-AsyncTask`):** Heavy I/O, COM, and servicing operations—including Appx dependency scans, WinSxS `AnalyzeComponentStore`, Task Scheduler audits, Ghost Service sweeps, NDIS adapter inspection, and WHEA XML log parsing—run inside isolated background Runspaces polled by non-blocking 150ms WinForms timers, eliminating GUI freezes (ANR).
* **Symmetric Revert Engine:** Complete peace of mind. Registry (`Z3`), Service (`Z4`), and Scheduled Task modules feature a unified `Show-ActionModal` supporting bidirectional state control (`Apply` vs. `Revert`), including `DELETE_KEY` and `DELETE_VALUE` tokens that strip residual GPO policy banners back to clean Windows factory defaults.
* **Zero-Dependency & Windows 11 26H2 Ready:** A standalone, native PowerShell / WinForms application engineered for modern Windows 11 builds (24H2–26H2) with zero reliance on deprecated WMIC or VBScript binaries.

---

### ⚙️ Feature Highlights (v2.7)

![WinUltix Z7](assets/7.jpg)

#### 1. Hardware & Latency Tuning (Z7)
* **Topology-Aware Affinity Lasso:** Dynamically detects CPU architecture (`Get-CPUTopologyProfile`) and locks background applications (Discord, Browsers, Launchers, Overlays) with `BelowNormal` priority to dedicated threads—isolating them to Cores 0–1 on AMD 8-Core Single-CCD chips (SMT-aware `0x0F` / `0x03`), the tail 4 threads of CCD1 on AMD Dual-CCD processors (protecting 3D V-Cache on CCD0), or the E-Core cluster on Intel Hybrid CPUs.
* **CPPC P-State Unhider & SYSTEM Dead Man's Switch:** Unlocks hidden AMD/Intel power attributes (`EPP`, `Idle Demote`, `Idle Promote`) directly in the active Power Plan using a locale-independent hex parser. Engaging Max CPPC (`EPP 0%`, `Demote/Promote 100%`) backs up factory values to `HKLM:\SOFTWARE\WinUltix\CPPC` and arms a `NT AUTHORITY\SYSTEM` Scheduled Task (`AtStartup` + `AtLogon`) to guarantee automatic rollback if an unstable undervolt causes a crash.
* **MSI Interrupt Enforcer:** Scans PCI bus enumeration keys and forces Message Signaled Interrupts (`MSISupported = 1`) to bypass IRQ sharing and reduce DPC latency, backed by an idempotent Base64 registry backup mechanism.
* **Asynchronous WHEA XML Decoder:** Parses `Microsoft-Windows-WHEA-Logger` XML payloads in a background Runspace, decoding raw `APICId` / `ProcessorId` attributes into physical CPU cores (SMT-aware) to pinpoint failing PBO/Curve Optimizer cores (Event ID 18), FCLK/SoC instability (ID 19), or unstable DDR5 memory timings (ID 47).
* **Kernel Timer & NVMe Power Lock:** Queries real-time clock intervals via native P/Invoke (`NtQueryTimerResolution` in `ntdll.dll`), injects `GlobalTimerResolutionRequests = 1` to fix the Windows 11 0.5ms timer bug, enforces CPU TSC in BCD (`disabledynamictick yes`, `useplatformclock no`), and disables PCIe ASPM (`pci.sys`), StorNVMe APST (`stornvme.sys`), and RAM compression (`MMAgent`).
* **Asynchronous NDIS & TCP Optimizer:** Audits physical network adapters in a background thread to disable Interrupt Moderation, Flow Control, EEE/Green Ethernet power saving, and RSC/LSO offloads while enforcing `TCPNoDelay` and `TcpAckFrequency`.
* **Pre-Flight Game Mode Generator:** Generates an elevated, topology-aware desktop macro shortcut to instantly engage or release Affinity Lasso and Max CPPC locks before launching a game.

#### 2. Deep Bloatware, OneDrive & Junk Removal (Z1 & Z2)
* **Curated 26H2 Bloatware Catalog & Deprovision Lock:** Scans 46 non-overlapping UWP bloatware categories (including Copilot, DevHome, New Outlook, MSTeams, Edge Game Assist, Clipchamp, and Widgets) without size blind spots—detecting full payloads, installed stubs, and provisioned image packages while locking `AppxAllUserStore\Deprovisioned` so Windows Update never reinstalls them.
* **Asynchronous Appx Garbage Collector:** Scans package dependency graphs in the background to eradicate orphaned UWP frameworks while strictly protecting critical gaming and system runtimes (`XboxIdentityProvider`, `XboxGameCallableUI`, `VCLibs`, `.NET`, `UI.Xaml`, `WindowsAppRuntime`, `WindowsAppSDK`, `DirectX`, `Graphics.Canvas`, `AIFabric`, `AugLoop`).
* **SFC-Safe OneDrive Amputation with DLL Evacuation:** Dynamically maps user profiles via `Win32_UserProfile` (zero hardcoded `C:\Users` paths) to purge OneDrive payloads and registry remnants while keeping dormant `%SystemRoot%` stubs intact for DISM/SFC integrity. Automatically evacuates memory-mapped shell extensions (`FileSyncShell64.dll`) locked by `explorer.exe` to `%TEMP%` for clean folder eradication.
* **Lock-Bypassing Cache Cleanup:** Asynchronously weighs and purges Windows Update caches (stopping `wuauserv`/`bits` and asserting ownership via locale-independent SID `*S-1-5-32-544`), Event Viewer logs (`wevtutil`), NTFS Recycle Bins across all partitions, and third-party caches (NVIDIA DXCache/GLCache, AMD DxCache, Discord, Steam, Browsers).

#### 3. Registry, Dual-Layer SRP+IFEO & Privacy Lockdown (Z3)
* **Dual-Layer Execution Locks (Safer API + Kernel IFEO):** Combines deterministic MD5-hashed Software Restriction Policies (Safer API) with kernel-level `Image File Execution Options` (`IFEO`) debugger hooks (`Debugger = "systray.exe"`) to permanently block persistent executables (`Widgets.exe`, `CompatTelRunner.exe`, `DeviceCensus.exe`, `GameBarPresenceWriter.exe`, `MicrosoftEdgeUpdate.exe`, or custom `.exe` targets) across all Windows 11 24H2–26H2 editions.
* **Clean GPO Privacy Lockdown:** Blocks UWP background permissions (`AppPrivacy`, Camera, Microphone), Content Delivery Manager silent installs, and WPBT BIOS/UEFI binary injections, while symmetrically deleting policy values (`DELETE_VALUE`) on revert so Windows Settings never displays residual *"Some settings are managed by your organization"* banners.
* **Raw Mouse Input & Extreme Gaming Profile:** Hard-disables pointer acceleration (`MouseSpeed`, `MouseThreshold1/2`) for 1:1 sensor tracking, elevates game threads via Multimedia Class Scheduler (`MMCSS`) tweaks (`SystemResponsiveness = 0`, `GPU Priority = 8`), enforces HAGS, disables VBS/HVCI overhead, and locks the kernel executive in RAM.

#### 4. Services, Native Start Menu Compiler & Integrity (Z4 & Z6)
* **Deterministic Start Menu Reset (24H2/26H2 Native Compiler):** Replaces brittle binary blob replacement with an automated native compiler. Temporarily registers an MDM Enrollment & PolicyManager context (`ConfigureStartPins`), purges `CloudStore` tile caches, and activates `StartMenuExperienceHost.exe` via COM (`IApplicationActivationManager`) to compile a build-native `start2.bin` containing only **Microsoft Edge, Windows Settings, and File Explorer**, before stripping all MDM locks so you can freely customize pins. Also provisions `LayoutModification.json` for the `Default` user profile.
* **Heavy/Light Service & Task Profiles:** Pre-configured, symmetrically reversible profiles to strip background telemetry services (`DiagTrack`, `WerSvc`, `WaaSMedicSvc`, `PcaSvc`) and Scheduled Tasks (`CEIP`, `WER`, `XblGameSave`), tailored for Office PCs or dedicated Gaming rigs.
* **Ghost Service & Driver Sweeper:** Asynchronously audits `HKLM:\SYSTEM\CurrentControlSet\Services` against active Win32 services and kernel drivers (`Win32_SystemDriver`) using non-greedy binary path resolution to eradicate orphaned entries pointing to missing files.
* **Asynchronous CBS/WinSxS ResetBase & Subsystem First-Aid:** Analyzes true Component Store footprint in a background Runspace, checks for `RebootPending` locks to prevent `0x800f0806` errors prior to `DISM /ResetBase`, refreshes the Winsock/TCP stack, and repairs deadlocked print queues by purging stuck `.SPL`/`.SHD` jobs in a background thread.

#### 5. Interactive System Utilities & CIM DNS Enforcer (Z5)
* **Protected `Out-GridView` Inspectors:** Selectively audit and remove installed Appx packages, provisioned base-image payloads, Features on Demand (FOD), Optional Features, and Services through interactive tables—shielded by a built-in regex filter that hides critical Xbox/Steam identity packages and core UWP runtimes.
* **Deep Startup Inspector & CIM DNS Switcher:** Audit autorun entries across `HKLM` (x64 and `WOW6432Node` x86), `HKCU`, and startup folders without PowerShell metadata clutter, or switch active network adapters between hardened DNS providers (Quad9, Cloudflare, AdGuard, Google, OpenDNS) and DHCP in one click via native CIM methods.

![WinUltix Main tabs](assets/6.png)

---

### 🚀 Getting Started

**Option A: No installation required.**
1. Download `WinUltix_Pro_EN.exe` (or run `WinUltix_Pro.ps1`) from the Releases tab.
2. Right-click -> **Run as Administrator** (UAC prompt will appear automatically).

**Option B: Instant PowerShell Launch (Zero-Download)**
Open PowerShell as Administrator and run:
```powershell
irm https://raw.githubusercontent.com/Firever-ultix/WinUltix/main/build/WinUltix_Monolith_EN.ps1 | iex
```

### ⚖️ License
This project is licensed under the **MIT License**.

### ⚠️ Disclaimer
*Provided "AS IS". While WinUltix Pro strictly relies on documented OS policies, safe cache clearing, and built-in API hooks, low-level registry manipulation and hardware interrupt enforcement always carry inherent risks. Creating a system restore point before deployment is highly recommended.*

### ☕ Coffee
This project is, and always will be, free of charge. However, if you appreciate it, you can buy me a coffee.<br>
https://buymeacoffee.com/firever<br>
Thank you!