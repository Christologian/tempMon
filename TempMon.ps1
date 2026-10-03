# ============================================================================
# TempMon.ps1 - tiny CPU temperature widget (WinForms).
#   Tab 1  Temp     : big TEMP number (blue=normal/yellow=warm/red=danger),
#                     small CPU% (bottom-left) and MEM% (bottom-right) corners.
#   Tab 2  Graph    : TEMP over time (driving line) + CPU% and MEM% overlaid.
#                     Temp uses its own scale; CPU/MEM are %, mapped 100% -> 100 deg.
#   Tab 3  Settings : set Max processor state (AC) cap to curb thermal sleeps.
# ============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- thresholds (edit to taste), in Celsius ----
$script:YellowAt = 78      # at/above = WARM (yellow)
$script:RedAt    = 90      # at/above = DANGER (red)
$script:useF     = $false  # numeric display unit: $false = Celsius, $true = Fahrenheit
$script:lastTemp = $null   # last raw Celsius reading (so the unit toggle can refresh instantly)

# ---- series colors ----
$script:ColCpu = [System.Drawing.Color]::Lime
$script:ColMem = [System.Drawing.Color]::Magenta

$script:bufTemp = New-Object System.Collections.Generic.List[double]
$script:bufCpu  = New-Object System.Collections.Generic.List[double]
$script:bufMem  = New-Object System.Collections.Generic.List[double]
$script:maxBuf  = 180      # ~6 min at 2s sampling

# ---------------------------------------------------------------------------
function Get-CpuTempC {
  try {
    $zones = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
    $valid = @()
    foreach ($z in $zones) { $t = $z.CurrentTemperature; if ($t -ne $null -and $t -lt 3000000) { $valid += [math]::Round($t/10 - 273.15, 1) } }
    if ($valid.Count) { return ($valid | Measure-Object -Maximum).Maximum }
  } catch {}
  return $null
}
function Get-CpuLoad {
  try { return [int]((Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average) } catch { return $null }
}
function Get-MemPct {
  try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; return [int]((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100) } catch { return $null }
}
function Get-MaxProcStateAC {
  try { $line = (powercfg /q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>$null | Select-String 'Current AC Power Setting Index').Line
        if ($line -match '0x([0-9a-fA-F]+)') { return [convert]::ToInt32($matches[1],16) } } catch {}
  return $null
}
function Set-MaxProcStateAC([int]$pct) {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $pct 2>$null | Out-Null
  powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null
}

# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'TempMon'
$form.ClientSize = New-Object System.Drawing.Size(250, 300)
$form.MinimumSize = New-Object System.Drawing.Size(210, 240)
$form.TopMost = $true
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(40, 40)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

# ---- Tab 1: Temp ----------------------------------------------------------
$tabTemp = New-Object System.Windows.Forms.TabPage
$tabTemp.Text = 'Temp'; $tabTemp.BackColor = [System.Drawing.Color]::Black
$tabs.TabPages.Add($tabTemp)

$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 22; $bottom.BackColor = [System.Drawing.Color]::Black
$tabTemp.Controls.Add($bottom)

$lblCpu = New-Object System.Windows.Forms.Label
$lblCpu.Dock = 'Left'; $lblCpu.Width = 80; $lblCpu.TextAlign = 'MiddleLeft'
$lblCpu.Font = New-Object System.Drawing.Font('Segoe UI', 8); $lblCpu.ForeColor = $script:ColCpu
$lblCpu.BackColor = [System.Drawing.Color]::Black; $lblCpu.Text = 'CPU --%'
$bottom.Controls.Add($lblCpu)

$lblMem = New-Object System.Windows.Forms.Label
$lblMem.Dock = 'Right'; $lblMem.Width = 80; $lblMem.TextAlign = 'MiddleRight'
$lblMem.Font = New-Object System.Drawing.Font('Segoe UI', 8); $lblMem.ForeColor = $script:ColMem
$lblMem.BackColor = [System.Drawing.Color]::Black; $lblMem.Text = 'MEM --%'
$bottom.Controls.Add($lblMem)

# bottom-center C/F toggle (affects the numeric display only; the graph stays Celsius)
$btnUnit = New-Object System.Windows.Forms.Button
$btnUnit.Dock = 'Fill'
$btnUnit.FlatStyle = 'Flat'
$btnUnit.FlatAppearance.BorderSize = 1
$btnUnit.ForeColor = [System.Drawing.Color]::Gainsboro
$btnUnit.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$btnUnit.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$btnUnit.TabStop = $false
$btnUnit.Text = [char]0x2192 + [char]176 + 'F'
$btnUnit.Add_Click({
  $script:useF = -not $script:useF
  if ($script:useF) { $btnUnit.Text = [char]0x2192 + [char]176 + 'C' } else { $btnUnit.Text = [char]0x2192 + [char]176 + 'F' }
  Update-TempDisplay
})
$bottom.Controls.Add($btnUnit)

$lblTemp = New-Object System.Windows.Forms.Label
$lblTemp.Dock = 'Fill'; $lblTemp.TextAlign = 'MiddleCenter'
$lblTemp.Font = New-Object System.Drawing.Font('Segoe UI', 46, [System.Drawing.FontStyle]::Bold)
$lblTemp.ForeColor = [System.Drawing.Color]::DeepSkyBlue; $lblTemp.BackColor = [System.Drawing.Color]::Black
$lblTemp.Text = '--'
$tabTemp.Controls.Add($lblTemp)

# ---- Tab 2: Graph ---------------------------------------------------------
$tabGraph = New-Object System.Windows.Forms.TabPage
$tabGraph.Text = 'Graph'; $tabGraph.BackColor = [System.Drawing.Color]::Black
$tabs.TabPages.Add($tabGraph)

$graph = New-Object System.Windows.Forms.Panel
$graph.Dock = 'Fill'; $graph.BackColor = [System.Drawing.Color]::Black
$tabGraph.Controls.Add($graph)

$graph.Add_Paint({
  param($s, $e)
  $g = $e.Graphics
  $w = $graph.ClientSize.Width
  $h = $graph.ClientSize.Height
  $minT = 40.0; $maxT = 105.0
  $yFor = { param($v) [float]($h - (([math]::Max($minT,[math]::Min($maxT,$v)) - $minT) / ($maxT - $minT) * $h)) }

  # threshold lines (temp scale)
  $penY = New-Object System.Drawing.Pen ([System.Drawing.Color]::Gold); $penY.DashStyle = 'Dash'
  $penR = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red);  $penR.DashStyle = 'Dash'
  $g.DrawLine($penY, 0, (& $yFor $script:YellowAt), $w, (& $yFor $script:YellowAt))
  $g.DrawLine($penR, 0, (& $yFor $script:RedAt),    $w, (& $yFor $script:RedAt))
  $grayBr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Gray)
  $small = New-Object System.Drawing.Font('Segoe UI', 7)
  $g.DrawString("$([int]$maxT)", $small, $grayBr, 2, 1)
  $g.DrawString("$([int]$minT)", $small, $grayBr, 2, ($h - 14))

  function DrawSeries($buf, $color, $width) {
    $n = $buf.Count
    if ($n -lt 2) { return }
    $pts = @()
    for ($i = 0; $i -lt $n; $i++) {
      $x = [float]($i / [math]::Max(1, ($script:maxBuf - 1)) * $w)
      $pts += New-Object System.Drawing.PointF($x, (& $yFor $buf[$i]))
    }
    $p = New-Object System.Drawing.Pen ($color, $width)
    $g.DrawLines($p, [System.Drawing.PointF[]]$pts)
  }

  # CPU and MEM first (background), TEMP last (driving line, on top)
  DrawSeries $script:bufCpu $script:ColCpu 1
  DrawSeries $script:bufMem $script:ColMem 1
  $tempColor = [System.Drawing.Color]::DeepSkyBlue
  if ($script:bufTemp.Count) {
    $cur = $script:bufTemp[$script:bufTemp.Count - 1]
    if ($cur -ge $script:RedAt) { $tempColor = [System.Drawing.Color]::Red }
    elseif ($cur -ge $script:YellowAt) { $tempColor = [System.Drawing.Color]::Gold }
  }
  DrawSeries $script:bufTemp $tempColor 2

  # legend
  $lf = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
  $g.DrawString('TEMP', $lf, (New-Object System.Drawing.SolidBrush ($tempColor)), ($w - 120), 1)
  $g.DrawString('CPU',  $lf, (New-Object System.Drawing.SolidBrush ($script:ColCpu)), ($w - 82), 1)
  $g.DrawString('MEM',  $lf, (New-Object System.Drawing.SolidBrush ($script:ColMem)), ($w - 50), 1)
})

# ---- Tab 3: Settings ------------------------------------------------------
$tabSet = New-Object System.Windows.Forms.TabPage
$tabSet.Text = 'Settings'
$tabs.TabPages.Add($tabSet)

$lblCurMax = New-Object System.Windows.Forms.Label
$lblCurMax.Location = New-Object System.Drawing.Point(10, 12); $lblCurMax.Size = New-Object System.Drawing.Size(225, 34)
$lblCurMax.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblCurMax.Text = 'Current Max processor state (AC): ...'
$tabSet.Controls.Add($lblCurMax)

$lblSet = New-Object System.Windows.Forms.Label
$lblSet.Location = New-Object System.Drawing.Point(10, 56); $lblSet.Size = New-Object System.Drawing.Size(130, 22)
$lblSet.Text = 'Set CPU max (%):'
$tabSet.Controls.Add($lblSet)

$num = New-Object System.Windows.Forms.NumericUpDown
$num.Location = New-Object System.Drawing.Point(140, 54); $num.Size = New-Object System.Drawing.Size(60, 24)
$num.Minimum = 1; $num.Maximum = 100; $num.Value = 100
$tabSet.Controls.Add($num)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Location = New-Object System.Drawing.Point(10, 86); $btnApply.Size = New-Object System.Drawing.Size(80, 28); $btnApply.Text = 'Apply'
$tabSet.Controls.Add($btnApply)
$btn70 = New-Object System.Windows.Forms.Button
$btn70.Location = New-Object System.Drawing.Point(96, 86); $btn70.Size = New-Object System.Drawing.Size(55, 28); $btn70.Text = 'Cap 70'
$tabSet.Controls.Add($btn70)
$btn100 = New-Object System.Windows.Forms.Button
$btn100.Location = New-Object System.Drawing.Point(157, 86); $btn100.Size = New-Object System.Drawing.Size(68, 28); $btn100.Text = 'Full 100'
$tabSet.Controls.Add($btn100)

$chkTop = New-Object System.Windows.Forms.CheckBox
$chkTop.Location = New-Object System.Drawing.Point(10, 122); $chkTop.Size = New-Object System.Drawing.Size(150, 22)
$chkTop.Text = 'Always on top'; $chkTop.Checked = $true
$tabSet.Controls.Add($chkTop)

$note = New-Object System.Windows.Forms.Label
$note.Location = New-Object System.Drawing.Point(10, 150); $note.Size = New-Object System.Drawing.Size(225, 110)
$note.ForeColor = [System.Drawing.Color]::DimGray
$note.Text = "Max processor state caps CPU speed on AC, lowering peak heat so the machine stops thermal-sleeping. Lower = cooler + slower. A bandage; the real fix is a heatsink clean/repaste."
$tabSet.Controls.Add($note)

function Refresh-Max {
  $m = Get-MaxProcStateAC
  if ($m -ne $null) { $lblCurMax.Text = "Current Max processor state (AC): $m%"; try { $num.Value = $m } catch {} }
  else { $lblCurMax.Text = 'Current Max processor state (AC): unknown' }
}
$btnApply.Add_Click({ Set-MaxProcStateAC ([int]$num.Value); Refresh-Max })
$btn70.Add_Click({ Set-MaxProcStateAC 70; Refresh-Max })
$btn100.Add_Click({ Set-MaxProcStateAC 100; Refresh-Max })
$chkTop.Add_CheckedChanged({ $form.TopMost = $chkTop.Checked })
$tabs.Add_SelectedIndexChanged({ if ($tabs.SelectedTab -eq $tabSet) { Refresh-Max } })

function Update-TempDisplay {
  $t = $script:lastTemp
  if ($t -eq $null) { $lblTemp.Text = 'n/a'; $lblTemp.ForeColor = [System.Drawing.Color]::Gray; return }
  if ($script:useF) { $d = [math]::Round($t * 9 / 5 + 32); $u = 'F' } else { $d = [math]::Round($t); $u = 'C' }
  $lblTemp.Text = ('{0:N0}' -f $d) + [char]176 + $u
  if ($t -ge $script:RedAt)        { $lblTemp.ForeColor = [System.Drawing.Color]::Red }
  elseif ($t -ge $script:YellowAt) { $lblTemp.ForeColor = [System.Drawing.Color]::Gold }
  else                             { $lblTemp.ForeColor = [System.Drawing.Color]::DeepSkyBlue }
}

# ---- polling timer --------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
  $t = Get-CpuTempC
  $c = Get-CpuLoad
  $m = Get-MemPct

  if ($c -ne $null) { $lblCpu.Text = "CPU $c%" } else { $lblCpu.Text = 'CPU --%' }
  if ($m -ne $null) { $lblMem.Text = "MEM $m%" } else { $lblMem.Text = 'MEM --%' }

  $script:lastTemp = $t
  Update-TempDisplay
  if ($t -ne $null) {
    # advance all three series together (temp drives the sample); graph stays in Celsius
    $script:bufTemp.Add([double]$t)
    $script:bufCpu.Add([double]$(if ($c -ne $null){$c}else{0}))
    $script:bufMem.Add([double]$(if ($m -ne $null){$m}else{0}))
    while ($script:bufTemp.Count -gt $script:maxBuf) { $script:bufTemp.RemoveAt(0); $script:bufCpu.RemoveAt(0); $script:bufMem.RemoveAt(0) }
  }
  if ($tabs.SelectedTab -eq $tabGraph) { $graph.Invalidate() }
})

Refresh-Max
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
$timer.Stop()
