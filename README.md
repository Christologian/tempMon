# TempMon

A tiny always-on CPU-temperature widget (WinForms via Windows PowerShell — no build step).

## Run
Double-click **`TempMon.cmd`** (or run it from a shell). A small window opens.

- **Temp tab** — big number. **Blue** = normal (<78°C), **Yellow** = warm (78–89°C), **Red** = DANGER (≥90°C).
- **Graph tab** — temperature over the last ~6 minutes, with dashed yellow/red threshold lines.
- **Settings tab** — shows the current **Max processor state (AC)** and lets you change it:
  - `Apply` sets the value in the spinner, or use **Cap 70** (interim fix when overheating) / **Full 100** (remove cap).
  - This is the same CPU cap as `temp.cmd` — lower % = cooler + slower; it curbs the thermal sleeps.
  - "Always on top" keeps the widget visible (on by default).

Edit the thresholds near the top of `TempMon.ps1` (`$YellowAt`, `$RedAt`).

## If the temp shows "n/a (run as admin?)"
Reading the thermal sensor can require elevation. Use the elevated autostart below.

## Always running (autostart at login)
**Simple (may need admin for the sensor):** put a shortcut to `TempMon.cmd` in the Startup folder — press `Win+R`, type `shell:startup`, drop a shortcut there.

**Recommended (elevated, no UAC prompt, so the sensor always reads):** a logon scheduled task:
```
schtasks /create /tn "TempMon" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"C:\repos\tempMon\TempMon.ps1\"" /sc onlogon /rl highest /f
```
Remove it with: `schtasks /delete /tn "TempMon" /f`

## Note
The CPU cap is a **bandage** that stops the thermal sleeps by lowering peak heat. The real fix for your ~87°C-at-light-load readings is a heatsink clean / thermal repaste (likely in warranty on a ThinkPad 21KV).
