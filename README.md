# WinUltix Pro 2.1 🚀
**A ~240KB, Portable, Zero-Dependency Windows 11 Optimizer**

For years, I’ve been collecting various registry tweaks, optimization scripts, and diagnostics scattered across the internet. I finally decided to put them all together in one project so everything is in one place. That's how WinUltix was born.

Most "debloaters" on the market are black boxes. They force you to click a magic button, silently hijack OS privileges, and leave you guessing what actually changed when your system becomes unstable. I wanted to build something completely different.

**WinUltix Pro 2.1** is my personal toolkit built for IT professionals, hardware enthusiasts, and gamers. It surgically removes telemetry, bloatware, and background noise, but most importantly—it is a **100% transparent, interactive, and fully reversible** toolkit that puts *you* in complete control.

![WinUltix Main Interface](assets/1.jpg)

### 🛡️ Why WinUltix Pro?
* **Micro-Sized & Portable:** A standalone `~240KB .exe`. No installations, no web-views, no background telemetry, and zero dependencies. Run it straight from a USB drive for a rapid system refresh.
* **Interactive Modals:** Total granular control. Every major action opens an interactive checklist. You can precisely select which specific registry key, service, Appx package, or directory to modify.
* **Absolute Transparency:** WinUltix reads your live system state before acting. It dynamically weighs your junk files in MBs, flags unoptimized settings as `[ DETECTED ]`, and clearly shows what was already scanned and safe as `[ OPTIMIZED ]` or `[ Clean ]`. Nothing happens behind your back.
* **100% Reversible:** The onboard **Interactive Rescue Module** scans for changes made and allows you to symmetrically revert any registry tweak or service state back to Windows factory defaults.

---

### ⚙️ Feature Highlights

#### 1. Hardware & Extreme Gaming Profile
* **Raw Mouse Input:** Hard-disables pointer acceleration at the registry level for true 1:1 sensor tracking.
* **Network Latency Reduction:** Injects `TCPNoDelay` into active network adapters to prevent packet queuing in competitive gaming.
* **Priority Tuning:** Forces SystemResponsiveness limits to 0% and elevates gaming processes via Multimedia Class Scheduler (MMCSS) tweaks.
* **Safe Core Services:** Safely sets Xbox Live APIs and Camera services to Manual instead of forcefully disabling them, ensuring full compatibility.

#### 2. Advanced Telemetry & Privacy Decimation
* **Task Scheduler Purge:** Safely disables Customer Experience tasks, Windows Error Reporting, and background feedback loops.
* **PowerShell & Defender Telemetry Block:** Injects machine-level variables to stop Microsoft from collecting background samples.
* **Hard MDM Policies:** Permanently blocks Windows 11 from silently downloading promoted store apps.

#### 3. Deep Bloatware Removal & Smart Garbage Collection
* **Aggressive Appx Cleansing:** Interactively uninstalls and *deprovisions* consumer bloatware (TikTok, Xbox Game Bar, Copilot) across all user profiles.
* **Intelligent Garbage Collector:** Scans application dependency trees and automatically targets orphaned UWP frameworks left behind by old apps.
* **Storage Purge:** Safely weighs and cleans Windows Update caches, Temp folders, and third-party app caches without forcibly stopping background services.

#### 4. Utilities & Fast Diagnostics
* **Diagnostic Audits (`?`):** Generate instant, read-only reports in the console without modifying your system.
* **Start Menu Reset:** Wipes the internal `start2.bin` database for a fresh, fully customizable layout.
* **Fast DNS Switch:** Rapidly apply secure DNS providers (Cloudflare, Quad9, AdGuard) with a single click.

![WinUltix Tabs Overview](assets/8.jpg)

### 🚀 Getting Started

**No installation required.** 
1. Download `WinUltix_Pro_EN.exe` from the Releases tab.
2. Right-click -> **Run as Administrator** (UAC prompt will appear automatically).

### ⚖️ License
This project is licensed under the **MIT License**.

### ⚠️ Disclaimer
*Provided "AS IS". While WinUltix Pro uses safe MDM policies, cache clearing, and standard service configurations rather than destructive file-deletion hacks, registry manipulation always carries inherent risks. Creating a system restore point before deployment is highly recommended.*

### ☕ Coffee
This project is, and always will be, free of charge. However, if you like it, you can buy me a coffee.<br>
https://buymeacoffee.com/firever<br>
Thank you!