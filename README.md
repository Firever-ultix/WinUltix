
> 🔗 **Part of the Ultix Ecosystem:**
> Looking for a clean, pre-debloated Windows 11 ISO deployment? Check out **[AutoUltixed](https://github.com/Firever-ultix/AutoUltixed)**.
> Looking for live post-install hardware, kernel & OS tuning? You are at **[WinUltix](https://github.com/Firever-ultix/WinUltix)**.

# WinUltix 3.0 🚀
**The Ultimate ~500 KB Windows 11 & 10 Hardware Tuner, Debloater, and System First-Aid Toolkit**

Most Windows "optimizers" fall into two traps: they are either bloated 150 MB apps that eat your RAM in the background, or reckless "black-box" scripts that nuke core system files, break Windows Update, and ruin your Xbox/Steam logins.

I built **WinUltix** to be the exact opposite: **a fast, 100% transparent, zero-dependency toolkit (~500 KB)** that gives you surgical control over Windows 11 (24H2 / 25H2 / 26H2) and Windows 10. Every single tweak is explained on hover, runs asynchronously without freezing the interface, and features a built-in **Revert (Undo)** engine so you can restore factory defaults at any time.

![WinUltix Main Interface](assets/1.png)

---

### ⚡ Quick Start (Zero Download)
Launch WinUltix directly in memory from an **Administrator** PowerShell / Terminal window:
```powershell
irm https://raw.githubusercontent.com/Firever-ultix/WinUltix/main/build/WinUltix_Monolith.ps1 | iex
```

*(Prefer a traditional `.exe`? Grab the standalone executable from the **[Releases](https://github.com/Firever-ultix/WinUltix/releases)** tab).*

---

### 🔥 Why WinUltix Stands Out

Normally, you need 6 or 7 separate utilities (*MSI Utility, Process Lasso, LatencyMon, TimerResolution, Autoruns, DDU/Cleaners*) to properly tune a gaming or workstation PC. WinUltix unifies all of them into a single, native dark interface:

#### 1. Eliminate Micro-Stutters & DPC Latency (`Hardware` Tab)

![WinUltix Z7](assets/3.png)

By default, Windows piles your graphics card, network adapter, and system timers onto **CPU Core 0**. When they collide, you get audio crackles, input lag, and 1% low FPS drops.

* **Live 1Hz Kernel DPC Monitor:** Watch real-time interrupt load across every physical CPU core (`C0..Cn`) and spot bottlenecks instantly.
* **Smart Core 0 IRQ Offload & MSI Enforcer:** A sortable 6-column PCI table that automatically highlights heavy GPU and Network drivers choking Core 0 (`★ OFFLOAD TO C1`). Switch devices to MSI mode and move their interrupts to a secondary core in one click—with full backup and restore.
* **0.5ms Hardware Timer + Live Test Button:** Unlocks global `0.5ms` timer precision in Windows 11, forces the low-latency CPU TSC clock, and includes a live **`Test 0.5ms Lock`** button so you can watch your system clock drop to `0.5000 ms` in real time.

#### 2. Smart CPU Affinity & Overclocking Diagnostics (`Hardware` Tab)

* **Topology-Aware Affinity Lasso:** Automatically detects **AMD 3D V-Cache** chips (e.g., 7800X3D, 9800X3D, 7950X3D, 9950X3D) and **Intel Hybrid P+E Core** CPUs. Locks background resource hogs (Discord, Spotify, Browsers, Game Launchers) to secondary cores or E-Cores so your prime gaming cores stay 100% free.
* **WHEA Overclocking / Undervolt Decoder:** Tuning PBO Curve Optimizer or DDR5 timings? WinUltix scans Windows hardware error logs and translates cryptic `APIC IDs` into exact **physical CPU core numbers**—telling you immediately whether a crash was caused by an aggressive Curve Optimizer core (ID 18), unstable FCLK/SoC (ID 19), or tight RAM timings (ID 47).
* **CPPC Power Unhider with "Dead Man's Switch":** Unlocks hidden CPU power settings (`EPP`, `Idle Demote/Promote`). If you engage maximum performance (`EPP 0%`) and your PC crashes from an unstable undervolt, a built-in failsafe automatically restores safe settings on the next boot.
* **Desktop "Pre-Flight" Game Mode Shortcut:** Generate a lightweight desktop toggle to arm or disarm your CPU Affinity and CPPC rules right before launching a game.

#### 3. The Admin Tools Microsoft Forgot to Build (`Utilities` Tab)

* **A Services Manager With an Actual Search Bar:** Microsoft's `services.msc` hasn't changed in 25 years. WinUltix gives you a fast, dark, sortable Services Manager with **instant live search**. Critical boot and security services are highlighted in red (`[CRITICAL - LOCKED]`) so you can inspect everything without ever accidentally bricking your OS.
* **High-Signal Scheduled Tasks Inspector:** Hides ~180 noisy internal Windows tasks to immediately expose **3rd-Party Updaters**, **Microsoft Telemetry**, and broken **`[GHOST / Missing Exe]`** tasks left behind by uninstalled software.
* **Deep Startup Manager:** Scans every hidden autorun location (`Run`, `RunOnce`, Group Policies, Startup folders) and decodes Task Manager's binary states—letting you toggle or permanently delete entries.
* **1-Click Encrypted DNS (IPv4 + IPv6 + Native DoH):** Switch between Quad9, Cloudflare, AdGuard, Google, or OpenDNS with native Windows 11 **DNS-over-HTTPS (DoH)** encryption enabled automatically.

---

### 🧰 Complete Feature Overview

* **🧹 Deep System & Shader Cleanup (`Cleanup` Tab):**
Weighs and purges gigabytes of junk in seconds: Windows Update & Delivery Optimization caches, DirectX / NVIDIA / AMD GPU shader caches (great for fixing shader stutter after driver updates), multi-profile browser caches (Chrome, Edge, Brave, Vivaldi, Firefox, Opera), crash dumps, and Event Viewer logs.
* **🗑️ Safe Debloater, Recall Killer & OneDrive Amputation (`Bloatware` Tab):**
Selectively remove **64 pre-installed bloatware apps**, disable **Windows Recall & Copilot AI**, purge orphaned UWP frameworks (Garbage Collector), and completely eradicate OneDrive across all user accounts—while strictly protecting Xbox Game Bar/Identity, Microsoft Store, and `sfc /scannow` system integrity.
* **🛡️ Registry, Privacy & Raw Input Tuning (`Registry` Tab):**
Restore the classic Windows 10 right-click menu, align the taskbar left, kill Bing search in the Start Menu, enforce **1:1 Raw Mouse Input** (zero acceleration), disable Multiplane Overlay (**MPO**—fixes VRR/OLED screen flickering), boost gaming thread priorities (`MMCSS`), and block stubborn telemetry `.exe` files (`CompatTelRunner.exe`, `Widgets.exe`) from ever running again.
* **⚙️ Service Profiles, Clean Start Menu & OLED/Power Tuner (`Services` Tab):**
* **Office & Gaming Service Profiles:** Symmetrically disable up to 51 background services (including disk-thrashing diagnostics and telemetry) and revert them anytime.
* **8-Point Power & Display Optimizer:** Disable Hibernation (`hiberfil.sys`), stop SATA HDD spin-down lag, disable **USB Selective Suspend** (prevents disconnects on external audio DACs, VR headsets, and 4K/8KHz wireless mice), and turn off **Content Adaptive Brightness (CABC)** to stop annoying auto-dimming on OLED/IPS monitors.
* **1-Click Clean Start Menu:** Wipes pre-installed promotional tiles (TikTok, Instagram, Candy Crush) and compiles a clean, native 3-icon Start Menu (*Edge, Settings, File Explorer*) with zero MDM policy locks left behind.


* **🔧 One-Click System First-Aid (`Integrity` Tab):**
* **Print Spooler First-Aid:** Fixes stuck printers by killing deadlocked spooler processes and clearing corrupted `.SPL`/`.SHD` queue files.
* **Windows Update & Cryptographic Repair:** Fixes stuck updates by flushing corrupted BITS queues, resetting `catroot2` / `SoftwareDistribution`, and re-registering 31 core DLLs.
* **WMI Repository Salvage & Icon Cache Rebuild:** Repairs broken system monitoring (`winmgmt`) and fixes blank white desktop/Explorer icons in seconds.
* **WinSxS ResetBase Compression:** Safely compresses superseded Windows Update backups to reclaim 5–15 GB of SSD space.

![WinUltix Main tabs](assets/9.png)

* **💾 Portable JSON Profiles:**
Configuring a new PC or helping a friend? Click **`[ Export Profile ]`** to save all your active tweaks, service states, and hardware locks into a single `.json` file, and apply them on any machine via **`[ Import Profile ]`**.

---

### 🛡️ Antivirus Detections & Transparency (False Positives)

Because WinUltix modifies low-level kernel registry keys, adjusts hardware power states, and disables OS telemetry services, some overzealous antivirus heuristics may flag the compiled `.exe`:

* **Why?** The standalone executable is unsigned and requests Administrator privileges to configure hardware and system services.
* **100% Open Source:** Every line of code is readable right here in the repository. You can audit the `/Modules` folder yourself, run the raw PowerShell script directly in memory (`irm ... | iex`), or compile your own `.exe` using `Compile-WinUltix.ps1`.

---

### ⚖️ License & Disclaimer

* Licensed under the **MIT License**.
* *Provided "AS IS". While WinUltix is engineered with strict safety checks, critical service locks, and a symmetric Revert engine, low-level OS and hardware tuning always carries inherent risk. Creating a System Restore Point before applying heavy modifications is recommended.*

### ☕ Support the Project

WinUltix is—and will always be—100% free, open-source, and ad-free. If this toolkit saved you time, fixed a stubborn Windows bug, or smoothed out your frametimes, you can buy me a coffee:

👉 ** https://buymeacoffee.com/firever

Thank you.
