# Electrolux AC tray app. Uses the official Electrolux Group API (developer.electrolux.one).
# Left click on the tray icon opens the flyout; right click has Sair. -Show opens the flyout at start.
param([switch]$Show)
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms, System.Drawing
$ErrorActionPreference = 'Stop'
# Hidden window: surface fatal errors (bad token, missing config) instead of dying silently.
trap { [Windows.Forms.MessageBox]::Show("$_", 'ArTray') | Out-Null; exit 1 }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Single instance: a new launch tells the running one to quit, so restarting = replacing.
$quit = New-Object Threading.EventWaitHandle $false, 'AutoReset', 'Local\ArTray.Quit'
[void]$quit.Set(); Start-Sleep -Milliseconds 1500; [void]$quit.Reset()

$Base = 'https://api.developer.electrolux.one/api/v1'
$CfgPath = Join-Path $PSScriptRoot 'config.json'
$Cfg = Get-Content $CfgPath -Raw | ConvertFrom-Json

function Save-Cfg { $Cfg | ConvertTo-Json | Set-Content $CfgPath -Encoding UTF8 }

# Access token is persisted too: the API rejects refreshes made shortly after another (cas_3404),
# so restarting the app must reuse the cached token instead of refreshing.
function Get-Token {
    if ($Cfg.accessToken -and (Get-Date) -lt [DateTime]$Cfg.accessExpiry) { return $Cfg.accessToken }
    $r = Invoke-RestMethod -Method Post -Uri "$Base/token/refresh" -ContentType 'application/json' `
        -Headers @{ 'x-api-key' = $Cfg.apiKey } -Body (@{ refreshToken = $Cfg.refreshToken } | ConvertTo-Json)
    # Refresh token rotates: persist it or the next start fails.
    $Cfg.refreshToken = $r.refreshToken
    $Cfg | Add-Member -Force accessToken $r.accessToken
    $Cfg | Add-Member -Force accessExpiry (Get-Date).AddSeconds([int]$r.expiresIn - 600).ToString('o')
    Save-Cfg
    $Cfg.accessToken
}

function Api($method, $path, $body) {
    $h = @{ 'x-api-key' = $Cfg.apiKey; Authorization = "Bearer $(Get-Token)" }
    $p = @{ Method = $method; Uri = "$Base/$path"; Headers = $h; ContentType = 'application/json' }
    if ($body) { $p.Body = $body | ConvertTo-Json -Compress }
    Invoke-RestMethod @p
}

$appliance = @(Api Get 'appliances') | Where-Object { -not $Cfg.applianceId -or $_.applianceId -eq $Cfg.applianceId } | Select-Object -First 1
if (-not $appliance) { throw 'Nenhum aparelho na conta Electrolux.' }
if (-not $Cfg.applianceId) { $Cfg | Add-Member -Force applianceId $appliance.applianceId; Save-Cfg }
$Id = $Cfg.applianceId

Add-Type -Namespace W -Name Dwm -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
[StructLayout(LayoutKind.Sequential)] public struct Margins { public int L, R, T, B; }
[DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref Margins m);
'@

# --- Theme (follows Windows light/dark). Glass = translucent layers over the acrylic backdrop. ---
$light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 1
$T = if ($light) {
    @{ Fg = '#1A1A1A'; Fg2 = '#8C000000'; Glass = '#59FFFFFF'; Glass2 = '#D9FFFFFF'; Stroke = '#1F000000'; Accent = '#0067C0'; OnAccent = '#FFFFFF'; Solid = '#F2F3F3F3' }
} else {
    @{ Fg = '#FFFFFF'; Fg2 = '#A6FFFFFF'; Glass = '#14FFFFFF'; Glass2 = '#38FFFFFF'; Stroke = '#24FFFFFF'; Accent = '#4CC2FF'; OnAccent = '#000000'; Solid = '#F0202020' }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" Background="Transparent" ShowInTaskbar="False" Topmost="True"
        SizeToContent="WidthAndHeight" FontFamily="Segoe UI Variable Text, Segoe UI" Foreground="{Fg}">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="0" GlassFrameThickness="-1" ResizeBorderThickness="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="Fg2" Color="{Fg2}"/>
    <SolidColorBrush x:Key="Glass" Color="{Glass}"/>
    <SolidColorBrush x:Key="Glass2" Color="{Glass2}"/>
    <SolidColorBrush x:Key="Stroke" Color="{Stroke}"/>
    <SolidColorBrush x:Key="Accent" Color="{Accent}"/>
    <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>

    <Style x:Key="Pill" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Fg2}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" Background="Transparent" CornerRadius="13" Padding="0,5" Margin="2">
            <ContentPresenter HorizontalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Glass}"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource Glass2}"/>
              <Setter Property="Foreground" Value="{Fg}"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style x:Key="Icon" TargetType="ButtonBase">
      <Setter Property="Foreground" Value="{Fg}"/>
      <Setter Property="FontFamily" Value="{StaticResource Icons}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Width" Value="32"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ButtonBase">
          <Border x:Name="b" Background="{StaticResource Glass}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="16">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{StaticResource Glass2}"/></Trigger>
            <Trigger Property="ToggleButton.IsChecked" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource Accent}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/>
              <Setter Property="Foreground" Value="{OnAccent}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>

  <Grid x:Name="Root" Width="300">
    <StackPanel Margin="18,16,18,16">
      <Grid>
        <TextBlock x:Name="Title" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <ToggleButton x:Name="Swing" Style="{StaticResource Icon}" Content="&#xE7AD;" ToolTip="Oscilar" Margin="0,0,6,0"/>
          <ToggleButton x:Name="Power" Style="{StaticResource Icon}" Content="&#xE7E8;" ToolTip="Ligar / desligar"/>
        </StackPanel>
      </Grid>

      <!-- Illustration: AC unit + animated air drawn into Air by Draw-Air -->
      <Grid Height="170" Margin="0,10,0,0">
        <Canvas x:Name="Air" ClipToBounds="True"/>
        <Border Width="210" Height="48" VerticalAlignment="Top" Margin="0,4,0,0" CornerRadius="14"
                Background="{StaticResource Glass2}" BorderBrush="{StaticResource Stroke}" BorderThickness="1">
          <Grid>
            <Rectangle Height="3" RadiusX="1.5" RadiusY="1.5" Fill="{StaticResource Fg2}" Opacity="0.45" Margin="26,0,26,9" VerticalAlignment="Bottom"/>
            <Ellipse x:Name="Led" Width="5" Height="5" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,10,14,0" Fill="{StaticResource Fg2}"/>
          </Grid>
        </Border>
      </Grid>

      <Grid Margin="0,2,0,0">
        <Button x:Name="Minus" Style="{StaticResource Icon}" Content="&#xE738;" HorizontalAlignment="Left" VerticalAlignment="Center"/>
        <StackPanel HorizontalAlignment="Center">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
            <TextBlock x:Name="Temp" FontSize="44" FontWeight="Light" FontFamily="Segoe UI Variable Display, Segoe UI"/>
            <TextBlock Text="&#xB0;" FontSize="26" FontWeight="Light" Margin="1,4,0,0"/>
          </StackPanel>
          <TextBlock x:Name="Sub" FontSize="11" Foreground="{StaticResource Fg2}" HorizontalAlignment="Center" Margin="0,-4,0,0"/>
        </StackPanel>
        <Button x:Name="Plus" Style="{StaticResource Icon}" Content="&#xE710;" HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>

      <Border CornerRadius="15" Background="{StaticResource Glass}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" Margin="0,16,0,0">
        <UniformGrid x:Name="Modes" Columns="3">
          <RadioButton Style="{StaticResource Pill}" GroupName="m" Tag="COOL" Content="Frio"/>
          <RadioButton Style="{StaticResource Pill}" GroupName="m" Tag="AUTO" Content="Auto"/>
          <RadioButton Style="{StaticResource Pill}" GroupName="m" Tag="FANONLY" Content="Ventilar"/>
        </UniformGrid>
      </Border>
      <Border CornerRadius="15" Background="{StaticResource Glass}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" Margin="0,8,0,0">
        <UniformGrid x:Name="Fans" Columns="4">
          <RadioButton Style="{StaticResource Pill}" GroupName="f" Tag="LOW" Content="Baixa"/>
          <RadioButton Style="{StaticResource Pill}" GroupName="f" Tag="MIDDLE" Content="M&#xE9;dia"/>
          <RadioButton Style="{StaticResource Pill}" GroupName="f" Tag="HIGH" Content="Alta"/>
          <RadioButton Style="{StaticResource Pill}" GroupName="f" Tag="TURBO" Content="Turbo"/>
        </UniformGrid>
      </Border>
    </StackPanel>
  </Grid>
</Window>
'@
foreach ($k in $T.Keys) { $xaml = $xaml.Replace("{$k}", $T[$k]) }
$win = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
'Root', 'Title', 'Sub', 'Power', 'Swing', 'Air', 'Led', 'Minus', 'Plus', 'Temp', 'Modes', 'Fans' | ForEach-Object { $ui[$_] = $win.FindName($_) }
$ui.Title.Text = $appliance.applianceName

# Windows 11 acrylic backdrop + rounded corners. If DWM refuses (older Windows), fall back to a solid panel.
$win.add_SourceInitialized({
    $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
    [Windows.Interop.HwndSource]::FromHwnd($h).CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
    $m = New-Object W.Dwm+Margins; $m.L = -1; $m.R = -1; $m.T = -1; $m.B = -1
    [void][W.Dwm]::DwmExtendFrameIntoClientArea($h, [ref]$m)
    $v = [int](-not $light); [void][W.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)  # immersive dark mode
    $v = 2; [void][W.Dwm]::DwmSetWindowAttribute($h, 33, [ref]$v, 4)                  # round corners
    $v = 3                                                                             # acrylic backdrop
    if ([W.Dwm]::DwmSetWindowAttribute($h, 38, [ref]$v, 4) -ne 0) { $ui.Root.Background = (New-Object Windows.Media.BrushConverter).ConvertFrom($T.Solid) }
})

# --- Air illustration: color follows target temperature, amount/length/speed follow fan speed ---
$inv = [Globalization.CultureInfo]::InvariantCulture
$FanLevel = @{ LOW = 1; MIDDLE = 2; HIGH = 3; TURBO = 4 }

function Air-Color {
    if ($script:Mode -eq 'FANONLY') { return [Windows.Media.Color]::FromRgb(0xDD, 0xE6, 0xEE) }
    $k = ($script:Target - 16) / 14.0                    # 16C icy blue -> 30C warm amber
    $c1 = 0x3A, 0xA0, 0xFF; $c2 = 0xFF, 0xB0, 0x6A
    $c = 0..2 | ForEach-Object { [byte]($c1[$_] + ($c2[$_] - $c1[$_]) * $k) }
    [Windows.Media.Color]::FromRgb($c[0], $c[1], $c[2])
}

function Draw-Air {
    $ui.Air.Children.Clear()
    $ui.Led.Fill = if ($script:On) { [Windows.Media.SolidColorBrush](Air-Color) } else { $win.FindResource('Fg2') }
    if (-not $script:On) { return }
    $lvl = $FanLevel[$script:Fan]; if (-not $lvl) { $lvl = 2 }
    $n = 2 + $lvl                      # streams
    $len = 50 + 22 * $lvl              # how far the air reaches
    $secs = 2.2 - 0.35 * $lvl          # flow speed
    $color = Air-Color
    $w = $ui.Air.ActualWidth; if (-not $w) { $w = 264 }
    for ($i = 0; $i -lt $n; $i++) {
        $f = if ($n -gt 1) { $i / ($n - 1) } else { 0.5 }
        $x0 = $w / 2 - 70 + 140 * $f
        $spread = ($f - 0.5) * 60      # streams fan outwards
        $pts = for ($t = 0; $t -le 24; $t++) {
            $u = $t / 24
            $x = $x0 + $spread * $u + 5 * [Math]::Sin($u * 9 + $i * 1.3) * $u
            [string]::Format($inv, '{0:0.#},{1:0.#}', $x, 44 + $len * $u)
        }
        $path = New-Object Windows.Shapes.Path
        $path.Data = [Windows.Media.Geometry]::Parse('M ' + ($pts -join ' L '))
        $grad = New-Object Windows.Media.LinearGradientBrush
        $grad.StartPoint = '0,0'; $grad.EndPoint = '0,1'
        $grad.GradientStops.Add((New-Object Windows.Media.GradientStop $color, 0))
        $grad.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, $color.R, $color.G, $color.B)), 1))
        $path.Stroke = $grad
        $path.StrokeThickness = 2.5
        $path.StrokeDashCap = 'Round'; $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'
        $path.StrokeDashArray = [Windows.Media.DoubleCollection]::Parse('4 3')
        $anim = [Windows.Media.Animation.DoubleAnimation]::new(-$i * 2, -$i * 2 - 7, [Windows.Duration]::new([TimeSpan]::FromSeconds($secs)))
        $anim.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $path.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, $anim)
        [void]$ui.Air.Children.Add($path)
    }
    $glow = New-Object Windows.Media.Effects.DropShadowEffect
    $glow.Color = $color; $glow.ShadowDepth = 0; $glow.BlurRadius = 10; $glow.Opacity = 0.7
    $ui.Air.Effect = $glow
}

# --- Tray icon: circle with the target temperature, accent when running ---
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Visible = $true
$tray.ContextMenuStrip = New-Object Windows.Forms.ContextMenuStrip
$tray.ContextMenuStrip.Items.Add('Sair').add_Click({ $tray.Visible = $false; $win.Dispatcher.InvokeShutdown() })

function Set-TrayIcon($text, $on) {
    $bmp = New-Object Drawing.Bitmap 32, 32
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $color = if ($on) { [Drawing.ColorTranslator]::FromHtml('#0078D4') } else { [Drawing.Color]::FromArgb(110, 110, 110) }
    $g.FillEllipse((New-Object Drawing.SolidBrush $color), 0, 0, 31, 31)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString($text, (New-Object Drawing.Font 'Segoe UI', 13, 'Bold', 'Pixel'), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 1, 32, 32), $sf)
    $old = $tray.Icon
    $tray.Icon = [Drawing.Icon]::FromHandle($bmp.GetHicon())
    if ($old) { $old.Dispose() }
    $g.Dispose(); $bmp.Dispose()
}
Set-TrayIcon '..' $false

# --- State ---
$script:Target = 21
$script:On = $false
$script:Fan = 'MIDDLE'
$script:Mode = 'COOL'

function Show-State { $ui.Temp.Text = $script:Target; Set-TrayIcon "$script:Target" $script:On; Draw-Air }

function Refresh-State {
    try {
        $s = (Api Get "appliances/$Id/state").properties.reported
        $script:On = $s.applianceState -eq 'RUNNING'
        $script:Target = [int]$s.targetTemperatureC
        $script:Fan = $s.fanSpeedSetting
        $script:Mode = $s.mode
        $ui.Power.IsChecked = $script:On
        $ui.Sub.Text = 'ambiente {0}°' -f $s.ambientTemperatureC
        foreach ($rb in $ui.Modes.Children) { $rb.IsChecked = $rb.Tag -eq $s.mode }
        foreach ($rb in $ui.Fans.Children) { $rb.IsChecked = $rb.Tag -eq $s.fanSpeedSetting }
        $ui.Swing.IsChecked = $s.flapOscillate -eq 'ON'
        Show-State
        $tray.Text = '{0}: {1}, alvo {2}°C, ambiente {3}°C' -f $appliance.applianceName, $(if ($script:On) { 'ligado' } else { 'desligado' }), $script:Target, $s.ambientTemperatureC
    } catch {
        $ui.Sub.Text = 'sem conexão'
        $tray.Text = 'Ar: erro ao atualizar'
    }
}

# One-shot timer: give the cloud a moment to apply a command before re-reading state.
$soon = New-Object Windows.Threading.DispatcherTimer
$soon.Interval = [TimeSpan]::FromSeconds(3)
$soon.add_Tick({ $soon.Stop(); Refresh-State })

function Send($cmd) {
    # UI was already updated optimistically; flush the render before the blocking HTTP call.
    $win.Dispatcher.Invoke([Action] {}, 'Background')
    try { Api Put "appliances/$Id/command" $cmd | Out-Null }
    catch { $ui.Sub.Text = 'falhou: ' + $_.Exception.Message }
    $soon.Stop(); $soon.Start()
}

# Click (not Checked) so programmatic updates in Refresh-State don't send commands.
$ui.Power.add_Click({
    $script:On = [bool]$ui.Power.IsChecked; Show-State
    Send @{ executeCommand = $(if ($script:On) { 'ON' } else { 'OFF' }) }
})
foreach ($rb in $ui.Modes.Children) { $rb.add_Click({ $script:Mode = $this.Tag; Draw-Air; Send @{ mode = $this.Tag } }) }
foreach ($rb in $ui.Fans.Children) { $rb.add_Click({ $script:Fan = $this.Tag; Draw-Air; Send @{ fanSpeedSetting = $this.Tag } }) }
$ui.Swing.add_Click({ Send @{ flapOscillate = $(if ($ui.Swing.IsChecked) { 'ON' } else { 'OFF' }) } })

# +/- only moves the number; the command goes out once clicks stop (one request, not one per click).
$tempDebounce = New-Object Windows.Threading.DispatcherTimer
$tempDebounce.Interval = [TimeSpan]::FromMilliseconds(800)
$tempDebounce.add_Tick({ $tempDebounce.Stop(); Send @{ targetTemperatureC = $script:Target } })
function Step($d) {
    $script:Target = [Math]::Max(16, [Math]::Min(30, $script:Target + $d))
    Show-State
    $tempDebounce.Stop(); $tempDebounce.Start()
}
$ui.Minus.add_Click({ Step -1 })
$ui.Plus.add_Click({ Step 1 })

# --- Flyout behaviour: opens above the tray, hides when it loses focus ---
function Open-Flyout {
    $win.Show(); $win.UpdateLayout()
    $wa = [Windows.SystemParameters]::WorkArea
    $win.Left = $wa.Right - $win.ActualWidth - 12
    $win.Top = $wa.Bottom - $win.ActualHeight - 12
    $win.Activate() | Out-Null
    Refresh-State
}
$script:HiddenAt = [DateTime]::MinValue
$win.add_Deactivated({ $win.Hide(); $script:HiddenAt = Get-Date })
$tray.add_MouseClick({
    if ($_.Button -ne 'Left') { return }
    # The click that deactivated the open flyout should close it, not reopen it.
    if (((Get-Date) - $script:HiddenAt).TotalMilliseconds -lt 300) { return }
    Open-Flyout
})

# An exception escaping a click/timer handler would kill the whole app: log it and keep running.
$LogPath = Join-Path $PSScriptRoot 'artray.log'
$win.Dispatcher.add_UnhandledException({
    Add-Content $LogPath "$(Get-Date -f s) $($_.Exception)"
    $_.Handled = $true
})

$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromSeconds(60)
$poll.add_Tick({ Refresh-State })
$poll.Start()
$quitCheck = New-Object Windows.Threading.DispatcherTimer
$quitCheck.Interval = [TimeSpan]::FromSeconds(1)
$quitCheck.add_Tick({ if ($quit.WaitOne(0)) { $tray.Visible = $false; $win.Dispatcher.InvokeShutdown() } })
$quitCheck.Start()
if ($Show) { Open-Flyout } else { Refresh-State }
[Windows.Threading.Dispatcher]::Run()
