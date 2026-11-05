# The wizard window. It loads the XAML pages, collects your choices, starts the runner and shows
# its progress. All UI work happens on this thread; the background runner talks to it only through
# $Context.Sync (see src\Core\Runner.ps1), which a DispatcherTimer reads several times a second.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:Wizard = $null

$script:StatusGlyphs = @{
    Pending = @{ Glyph = [string][char]0xEA3A; Color = '#9CA3AF' }
    Running = @{ Glyph = [string][char]0xE768; Color = '#2563EB' }
    Success = @{ Glyph = [string][char]0xE73E; Color = '#16A34A' }
    Skipped = @{ Glyph = [string][char]0xE738; Color = '#D97706' }
    Failed  = @{ Glyph = [string][char]0xE711; Color = '#DC2626' }
}

function Import-UdpXaml {
    param([Parameter(Mandatory)][string]$Path)
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($Path)
    $reader = New-Object System.Xml.XmlNodeReader($xml)
    return [System.Windows.Markup.XamlReader]::Load($reader)
}

# Styles are added to the application resources so every page can use them while it is loaded.
function Initialize-UdpApplication {
    param([Parameter(Mandatory)][string]$Root)
    $app = [System.Windows.Application]::Current
    if (-not $app) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }
    $app.Resources.MergedDictionaries.Add((Import-UdpXaml -Path (Join-Path $Root 'ui\Styles.xaml')))
}

function New-UdpBrush {
    param([string]$Color)
    return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Color)
}

function New-UdpTextBlock {
    param([string]$Text, [string]$Style = 'Body', [System.Windows.Thickness]$Margin)
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Text
    $block.Style = [System.Windows.Application]::Current.FindResource($Style)
    if ($Margin) { $block.Margin = $Margin }
    return $block
}

function Get-UdpPage {
    param([string]$Id)
    return ($script:Wizard.Pages | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Get-UdpPageControl {
    param([string]$PageId, [string]$Name)
    return (Get-UdpPage -Id $PageId).Root.FindName($Name)
}

function Get-UdpVisiblePages {
    return @($script:Wizard.Pages | Where-Object { & $_.Visible })
}

# ---------------------------------------------------------------- page setup

function Initialize-UdpWelcomePage {
    $ctx = $script:Wizard.Context
    $system = $ctx.System

    (Get-UdpPageControl 'welcome' 'SystemInfo').Text = Format-UdpSystemInfo -System $system
    (Get-UdpPageControl 'welcome' 'DryRunCheck').IsChecked = [bool]$ctx.DryRun

    $warnings = @()
    if (-not $system.IsSupportedOS) { $warnings += 'This version of Windows is not supported. UDP targets Windows 11 and Windows 10.' }
    if (-not $system.Internet) { $warnings += 'No internet connection: the tools cannot be downloaded, so their steps are unavailable.' }
    if (-not $system.Winget) { $warnings += 'winget was not found. Install "App Installer" from the Microsoft Store for the best results; UDP uses official direct downloads where it can.' }
    if (-not $system.IsWindows11 -and $system.IsSupportedOS) { $warnings += 'Windows 10 detected: options that only exist on Windows 11 are hidden.' }
    if ($warnings.Count -gt 0) {
        (Get-UdpPageControl 'welcome' 'PreflightWarningsText').Text = ($warnings -join "`r`n")
        (Get-UdpPageControl 'welcome' 'PreflightWarnings').Visibility = 'Visible'
    }

    $agree = Get-UdpPageControl 'welcome' 'AgreeCheck'
    $agree.Add_Checked({ Update-UdpNavigation })
    $agree.Add_Unchecked({ Update-UdpNavigation })

    (Get-UdpPageControl 'welcome' 'RevertPoliciesButton').Add_Click({
            $question = 'Remove the browser extension policies that UDP created? Policies that existed before UDP are not touched.'
            $answer = [System.Windows.MessageBox]::Show($question, 'UDP', 'YesNo', 'Question')
            if ($answer -ne 'Yes') { return }
            try {
                $count = Remove-UdpBrowserPolicies -Context $script:Wizard.Context
                [System.Windows.MessageBox]::Show("Done. $count extension entries removed. Restart the browser to apply.", 'UDP', 'OK', 'Information') | Out-Null
            }
            catch {
                [System.Windows.MessageBox]::Show("Revert failed: $($_.Exception.Message)", 'UDP', 'OK', 'Error') | Out-Null
            }
        })
}

# Common part of every tool page: disable it with a reason when the step cannot run on this PC.
function Initialize-UdpToolAvailability {
    param([string]$PageId, [string]$StepId)
    $step = Get-UdpStepCatalog | Where-Object { $_.Id -eq $StepId }
    $availability = & $step.Available -Context $script:Wizard.Context
    if (-not $availability.Available) {
        $check = Get-UdpPageControl $PageId 'EnableCheck'
        $check.IsChecked = $false
        $check.IsEnabled = $false
        $note = Get-UdpPageControl $PageId 'UnavailableNote'
        $note.Text = "Not available on this PC: $($availability.Reason)"
        $note.Visibility = 'Visible'
    }
}

function Initialize-UdpWin11DebloatPage {
    $panel = Get-UdpPageControl 'win11debloat' 'CustomOptionsPanel'
    $group = $null
    foreach ($option in (Get-UdpWin11DebloatOptionsForBuild -Context $script:Wizard.Context)) {
        if ($option.group -ne $group) {
            $group = $option.group
            $margin = New-Object System.Windows.Thickness(0, 8, 0, 2)
            if ($panel.Children.Count -eq 0) { $margin = New-Object System.Windows.Thickness(0, 0, 0, 2) }
            [void]$panel.Children.Add((New-UdpTextBlock -Text $group -Style 'SectionTitle' -Margin $margin))
        }
        $check = New-Object System.Windows.Controls.CheckBox
        $check.Content = $option.label
        $check.Tag = $option.switch
        $check.IsChecked = [bool]$option.default
        $check.ToolTip = "-$($option.switch)"
        [void]$panel.Children.Add($check)
    }

    $customPanel = Get-UdpPageControl 'win11debloat' 'CustomPanel'
    (Get-UdpPageControl 'win11debloat' 'ModeCustom').Add_Checked({ (Get-UdpPageControl 'win11debloat' 'CustomPanel').Visibility = 'Visible' })
    (Get-UdpPageControl 'win11debloat' 'ModeDefaults').Add_Checked({ (Get-UdpPageControl 'win11debloat' 'CustomPanel').Visibility = 'Collapsed' })
    $customPanel.Visibility = 'Collapsed'

    # Apps to remove: Win11Debloat's own list, pre-ticked with its recommended selection.
    $catalog = $script:Wizard.Context.Win11DebloatCatalog
    $script:Wizard.AppChoice = @{}
    if (-not $catalog) {
        foreach ($name in 'AppsSummary', 'AppsTools', 'AppsCard') { (Get-UdpPageControl 'win11debloat' $name).Visibility = 'Collapsed' }
        (Get-UdpPageControl 'win11debloat' 'AppsFallback').Visibility = 'Visible'
        return
    }
    foreach ($app in $catalog.Apps) { $script:Wizard.AppChoice[$app.Id] = $app.Default }
    (Get-UdpPageControl 'win11debloat' 'AppsRecommendedButton').Add_Click({
            foreach ($app in $script:Wizard.Context.Win11DebloatCatalog.Apps) { $script:Wizard.AppChoice[$app.Id] = $app.Default }
            Update-UdpAppsList
        })
    (Get-UdpPageControl 'win11debloat' 'AppsNoneButton').Add_Click({
            foreach ($app in $script:Wizard.Context.Win11DebloatCatalog.Apps) { $script:Wizard.AppChoice[$app.Id] = $false }
            Update-UdpAppsList
        })
    $showAll = Get-UdpPageControl 'win11debloat' 'AppsShowAllCheck'
    $showAll.Add_Checked({ Update-UdpAppsList })
    $showAll.Add_Unchecked({ Update-UdpAppsList })
    Update-UdpAppsList
}

$script:RecommendationGroups = @(
    @{ Key = 'safe'; Title = 'Safe to remove'; Color = '#15803D' }
    @{ Key = 'optional'; Title = 'Optional: remove only if you do not use them'; Color = '#4B5563' }
    @{ Key = 'unsafe'; Title = 'Not recommended: removing these can break Windows features'; Color = '#DC2626' }
)

function Test-UdpAppsCustomized {
    $w = $script:Wizard
    foreach ($app in $w.Context.Win11DebloatCatalog.Apps) {
        if ([bool]$w.AppChoice[$app.Id] -ne $app.Default) { return $true }
    }
    return $false
}

function Update-UdpAppsSummary {
    $w = $script:Wizard
    $onPc = @($w.Context.Win11DebloatCatalog.Apps | Where-Object { $_.Installed -ne $false })
    $chosen = @($onPc | Where-Object { $w.AppChoice[$_.Id] })
    $which = 'Win11Debloat''s recommended selection'
    if (Test-UdpAppsCustomized) { $which = 'your selection' }
    (Get-UdpPageControl 'win11debloat' 'AppsSummary').Text = "$($chosen.Count) of the $($onPc.Count) apps found on this PC will be removed ($which). Point at an app to see what it is."
}

# Rebuilds the app checkboxes from $script:Wizard.AppChoice, grouped by Win11Debloat's recommendation.
function Update-UdpAppsList {
    $w = $script:Wizard
    $panel = Get-UdpPageControl 'win11debloat' 'AppsPanel'
    $showAll = [bool](Get-UdpPageControl 'win11debloat' 'AppsShowAllCheck').IsChecked
    $panel.Children.Clear()
    foreach ($group in $script:RecommendationGroups) {
        $apps = @($w.Context.Win11DebloatCatalog.Apps |
                Where-Object { $_.Recommendation -eq $group.Key -and ($showAll -or $_.Installed -ne $false) } | Sort-Object Name)
        if ($apps.Count -eq 0) { continue }
        $top = 10
        if ($panel.Children.Count -eq 0) { $top = 2 }
        $header = New-UdpTextBlock -Text $group.Title -Style 'SectionTitle' -Margin (New-Object System.Windows.Thickness(0, $top, 0, 2))
        $header.Foreground = New-UdpBrush $group.Color
        [void]$panel.Children.Add($header)
        foreach ($app in $apps) {
            $check = New-Object System.Windows.Controls.CheckBox
            $check.Tag = $app.Id
            $check.IsChecked = [bool]$w.AppChoice[$app.Id]
            $label = $app.Name
            if ($app.Installed -eq $false) { $label += '  (not installed)' }
            $check.Content = $label
            $tip = $app.Id
            if ($app.Description) { $tip = "$($app.Description)`n$($app.Id)" }
            $check.ToolTip = $tip
            $check.Add_Checked({ $script:Wizard.AppChoice[[string]$this.Tag] = $true; Update-UdpAppsSummary })
            $check.Add_Unchecked({ $script:Wizard.AppChoice[[string]$this.Tag] = $false; Update-UdpAppsSummary })
            [void]$panel.Children.Add($check)
        }
    }
    Update-UdpAppsSummary
}

# The apps part of the Win11Debloat selection (see Get-UdpWin11DebloatArguments).
function Get-UdpWin11DebloatAppSelection {
    $w = $script:Wizard
    if (-not $w.Context.Win11DebloatCatalog) {
        return @{ Apps = $null; AppsCustomized = $false; RemoveDefaultApps = [bool](Get-UdpPageControl 'win11debloat' 'RemoveDefaultAppsCheck').IsChecked }
    }
    $apps = @($w.Context.Win11DebloatCatalog.Apps | Where-Object { $w.AppChoice[$_.Id] } | ForEach-Object { $_.Ids })
    return @{ Apps = $apps; AppsCustomized = (Test-UdpAppsCustomized); RemoveDefaultApps = $true }
}

function Initialize-UdpShutUp10Page {
    $path = Get-UdpShutUp10ConfigPath -Context $script:Wizard.Context
    $note = Get-UdpPageControl 'shutup10' 'SilentNote'
    $silent = Get-UdpPageControl 'shutup10' 'ModeSilent'
    if (Test-Path -LiteralPath $path) {
        $note.Text = "Settings file found: $path"
    }
    else {
        $note.Text = "Not available yet: no settings file at $path (see below)."
        $silent.IsEnabled = $false
    }
}

function Initialize-UdpBcuPage {
    $note = Get-UdpPageControl 'bcu' 'RunOnceNote'
    if ($script:Wizard.Context.System.TarSupports7z) {
        $note.Text = 'The portable build is downloaded from the official GitHub release and nothing is installed.'
    }
    else {
        $note.Text = 'This Windows cannot extract the portable .7z archive, so for "Run once" UDP installs BCU with winget and uninstalls it at the end.'
    }
}

function Get-UdpSelectedBrowserId {
    if ((Get-UdpPageControl 'browser' 'ChromeRadio').IsChecked) { return 'chrome' }
    if ((Get-UdpPageControl 'browser' 'BraveRadio').IsChecked) { return 'brave' }
    return 'firefox'
}

$script:ManagedNotes = @{
    firefox = 'Extensions are installed through Firefox''s enterprise policy (installation mode "normal_installed"): Firefox installs them by itself and you can still disable them. Firefox then shows "Your browser is being managed by your organization" in its settings. That only means a policy is set on this PC; nothing is sent anywhere.'
    chrome  = 'uBlock Origin no longer works in Chrome (Manifest V2 extensions were removed), so UDP installs uBlock Origin Lite instead. Extensions are installed through Chrome''s policy (installation mode "normal_installed"): Chrome installs them by itself and you can still disable them. Chrome then shows "Managed by your organization". That only means a policy is set on this PC; nothing is sent anywhere.'
    brave   = 'Brave already blocks ads and trackers with Shields, so extensions are optional and unticked. The full uBlock Origin still runs in Brave, but only as a copy hosted by Brave that you switch on yourself in Brave''s extension settings (Manifest V2 section); it cannot be installed by policy. UDP can add uBlock Origin Lite and Privacy Badger through Brave''s policy instead; Brave then shows "Managed by your organization".'
}

function Update-UdpBrowserPage {
    $ctx = $script:Wizard.Context
    $id = Get-UdpSelectedBrowserId
    $browser = Get-UdpBrowserConfig -Context $ctx -BrowserId $id

    $installed = Get-UdpPageControl 'browser' 'InstalledNote'
    if (Test-UdpBrowserInstalled -Browser $browser) { $installed.Text = "$($browser.name) is already installed: UDP skips the installation and only applies the options below." }
    else { $installed.Text = "$($browser.name) will be installed with winget ($($browser.winget))." }

    $panel = Get-UdpPageControl 'browser' 'ExtensionsPanel'
    $panel.Children.Clear()
    foreach ($extension in $browser.extensions) {
        $check = New-Object System.Windows.Controls.CheckBox
        $check.Content = "$($extension.name)  ($($extension.id))"
        $check.Tag = $extension.id
        $check.IsChecked = [bool]$extension.default
        [void]$panel.Children.Add($check)
    }
    $panel.IsEnabled = [bool](Get-UdpPageControl 'browser' 'ExtensionsCheck').IsChecked
    (Get-UdpPageControl 'browser' 'ManagedNote').Text = $script:ManagedNotes[$id]

    $taskbarNote = Get-UdpPageControl 'browser' 'TaskbarNote'
    if (Test-UdpTaskbarLayoutSupported -Context $ctx) {
        $taskbarNote.Text = "Edge's pin is removed and $($browser.name) is pinned next to File Explorer; the Microsoft Store stays pinned. Applied at your next sign-in."
    }
    else {
        $taskbarNote.Text = 'Not available on this PC: needs Windows 11 24H2 (or 22H2/23H2) with the June 2025 update or later. You can pin the browser yourself: right-click it in the Start menu > Pin to taskbar.'
    }
    $defaultsNote = Get-UdpPageControl 'browser' 'DefaultsNote'
    $support = Test-UdpDefaultAssociationsSupported -Context $ctx
    if ($support.Available) {
        $defaultsNote.Text = "Every link and file type $($browser.name) registers with Windows (for example http, https, .html, .pdf, .svg) opens in $($browser.name). Applied once, at your next sign-in."
    }
    else {
        $defaultsNote.Text = "Not available on this PC: the policy $($support.Reason). UDP opens Settings > Default apps instead and shows you the two clicks needed."
    }
    Update-UdpPolicyWarning
}

# The policy explanation is shown while an option that uses a Windows policy is ticked.
function Update-UdpPolicyWarning {
    $warning = Get-UdpPageControl 'browser' 'PolicyWarning'
    $visible = $false
    foreach ($name in 'TaskbarCheck', 'DefaultsCheck') {
        $check = Get-UdpPageControl 'browser' $name
        if ($check.IsChecked -and $check.IsEnabled) { $visible = $true }
    }
    if ($visible) { $warning.Visibility = 'Visible' } else { $warning.Visibility = 'Collapsed' }
}

function Initialize-UdpBrowserPage {
    foreach ($name in 'FirefoxRadio', 'ChromeRadio', 'BraveRadio') {
        (Get-UdpPageControl 'browser' $name).Add_Checked({ Update-UdpBrowserPage })
    }
    $extensions = Get-UdpPageControl 'browser' 'ExtensionsCheck'
    $extensions.Add_Checked({ (Get-UdpPageControl 'browser' 'ExtensionsPanel').IsEnabled = $true })
    $extensions.Add_Unchecked({ (Get-UdpPageControl 'browser' 'ExtensionsPanel').IsEnabled = $false })
    $taskbar = Get-UdpPageControl 'browser' 'TaskbarCheck'
    if (-not (Test-UdpTaskbarLayoutSupported -Context $script:Wizard.Context)) {
        $taskbar.IsChecked = $false
        $taskbar.IsEnabled = $false
    }
    $taskbar.Add_Checked({ Update-UdpPolicyWarning })
    $taskbar.Add_Unchecked({ Update-UdpPolicyWarning })
    $defaults = Get-UdpPageControl 'browser' 'DefaultsCheck'
    if (-not (Test-UdpDefaultAssociationsSupported -Context $script:Wizard.Context).Available) {
        $defaults.IsChecked = $false
        $defaults.IsEnabled = $false
    }
    $defaults.Add_Checked({ Update-UdpPolicyWarning })
    $defaults.Add_Unchecked({ Update-UdpPolicyWarning })
    Update-UdpBrowserPage
}

# Edge removal needs another browser: warn when none is installed and none will be.
function Update-UdpEdgePage {
    $ctx = $script:Wizard.Context
    $edgeOn = [bool](Get-UdpPageControl 'edge' 'EnableCheck').IsChecked
    $browserOn = [bool](Get-UdpPageControl 'browser' 'EnableCheck').IsChecked
    $noBrowser = ($ctx.System.InstalledBrowsers.Count -eq 0 -and -not $browserOn)
    $warning = Get-UdpPageControl 'edge' 'NoBrowserWarning'
    if ($edgeOn -and $noBrowser) { $warning.Visibility = 'Visible' } else { $warning.Visibility = 'Collapsed' }
}

function Initialize-UdpEdgePage {
    if (-not (Test-UdpEdgeInstalled) -and @(Get-UdpEdgeShortcuts).Count -gt 0) {
        $note = Get-UdpPageControl 'edge' 'UnavailableNote'
        $note.Text = 'Edge is already removed. Tick the box to remove the Edge shortcuts it left on the desktop and in the Start menu.'
        $note.Visibility = 'Visible'
    }
    $check = Get-UdpPageControl 'edge' 'EnableCheck'
    $check.Add_Checked({ Update-UdpEdgePage })
    $check.Add_Unchecked({ Update-UdpEdgePage })
}

function Initialize-UdpNVCleanstallPage {
    $names = @($script:Wizard.Context.System.GpuNames | Where-Object { $_ -match 'NVIDIA' })
    (Get-UdpPageControl 'nvcleanstall' 'GpuNote').Text = "Detected: $($names -join ', ')"
}

# ---------------------------------------------------------------- selection and summary

function Get-UdpCheckedTags {
    param($Panel)
    return @($Panel.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked } | ForEach-Object { [string]$_.Tag })
}

function Get-UdpWizardSelection {
    $enabled = {
        param($PageId)
        $page = Get-UdpPage -Id $PageId
        if (-not (& $page.Visible)) { return $false }
        return [bool]$page.Root.FindName('EnableCheck').IsChecked
    }

    $w11Mode = 'Defaults'
    if ((Get-UdpPageControl 'win11debloat' 'ModeCustom').IsChecked) { $w11Mode = 'Custom' }
    $oosuMode = 'Gui'
    if ((Get-UdpPageControl 'shutup10' 'ModeSilent').IsChecked) { $oosuMode = 'Silent' }
    $bcuMode = 'RunOnce'
    if ((Get-UdpPageControl 'bcu' 'ModeInstall').IsChecked) { $bcuMode = 'Install' }

    $w11Apps = Get-UdpWin11DebloatAppSelection

    return @{
        win11debloat = @{
            Enabled           = (& $enabled 'win11debloat')
            Mode              = $w11Mode
            Switches          = (Get-UdpCheckedTags (Get-UdpPageControl 'win11debloat' 'CustomOptionsPanel'))
            Apps              = $w11Apps.Apps
            AppsCustomized    = $w11Apps.AppsCustomized
            RemoveDefaultApps = $w11Apps.RemoveDefaultApps
        }
        shutup10     = @{ Enabled = (& $enabled 'shutup10'); Mode = $oosuMode }
        bcu          = @{ Enabled = (& $enabled 'bcu'); Mode = $bcuMode }
        browser      = @{
            Enabled      = (& $enabled 'browser')
            Browser      = (Get-UdpSelectedBrowserId)
            Extensions   = [bool](Get-UdpPageControl 'browser' 'ExtensionsCheck').IsChecked
            ExtensionIds = (Get-UdpCheckedTags (Get-UdpPageControl 'browser' 'ExtensionsPanel'))
            Taskbar      = [bool]((Get-UdpPageControl 'browser' 'TaskbarCheck').IsChecked -and (Get-UdpPageControl 'browser' 'TaskbarCheck').IsEnabled)
            SetDefault   = [bool]((Get-UdpPageControl 'browser' 'DefaultsCheck').IsChecked -and (Get-UdpPageControl 'browser' 'DefaultsCheck').IsEnabled)
        }
        edge         = @{
            Enabled            = (& $enabled 'edge')
            RemoveWidgets      = [bool](Get-UdpPageControl 'edge' 'WidgetsCheck').IsChecked
            RemoveXSocial      = [bool](Get-UdpPageControl 'edge' 'XSocialCheck').IsChecked
            ConfirmedNoBrowser = [bool](Get-UdpPageControl 'edge' 'ConfirmNoBrowserCheck').IsChecked
        }
        nvcleanstall = @{ Enabled = (& $enabled 'nvcleanstall') }
        autoruns     = @{ Enabled = (& $enabled 'autoruns') }
    }
}

function Update-UdpSummaryPage {
    $ctx = $script:Wizard.Context
    $ctx.DryRun = [bool](Get-UdpPageControl 'welcome' 'DryRunCheck').IsChecked
    $selection = Get-UdpWizardSelection
    $script:Wizard.Selection = $selection

    $banner = Get-UdpPageControl 'summary' 'DryRunBanner'
    if ($ctx.DryRun) { $banner.Visibility = 'Visible' } else { $banner.Visibility = 'Collapsed' }

    $panel = Get-UdpPageControl 'summary' 'SummaryPanel'
    $panel.Children.Clear()

    $add = {
        param([string]$Title, [string[]]$Lines)
        $card = New-Object System.Windows.Controls.Border
        $card.Style = [System.Windows.Application]::Current.FindResource('Card')
        $stack = New-Object System.Windows.Controls.StackPanel
        [void]$stack.Children.Add((New-UdpTextBlock -Text $Title -Style 'SectionTitle' -Margin (New-Object System.Windows.Thickness(0, 0, 0, 2))))
        foreach ($line in $Lines) { [void]$stack.Children.Add((New-UdpTextBlock -Text "- $line" -Style 'Body' -Margin (New-Object System.Windows.Thickness(0, 0, 0, 1)))) }
        $card.Child = $stack
        [void]$panel.Children.Add($card)
    }

    $number = 1
    & $add "$number. System Restore point" @("Turn on System Protection for $env:SystemDrive if needed and create a restore point")
    $plan = @(Get-UdpRunPlan -Context $ctx -Selection $selection)
    foreach ($step in $plan) {
        $number++
        $lines = @(& $step.Plan -Context $ctx -Options $selection[$step.Id])
        & $add "$number. $($step.Name)" $lines
    }
    $number++
    & $add "$number. Finish" @('Show the result of every step and the log file location', 'Ask you to restart Windows once')

    $skipped = @(Get-UdpStepCatalog | Where-Object { $plan.Id -notcontains $_.Id } | ForEach-Object { $_.Name })
    if ($skipped.Count -gt 0) {
        [void]$panel.Children.Add((New-UdpTextBlock -Text "Not run: $($skipped -join ', ')" -Style 'Muted'))
    }
}

# ---------------------------------------------------------------- navigation

function Update-UdpNavigation {
    $w = $script:Wizard
    $c = $w.Controls
    $visible = Get-UdpVisiblePages
    $page = $visible[$w.Index]

    # Sidebar
    $c.NavList.Children.Clear()
    for ($i = 0; $i -lt $visible.Count; $i++) {
        $item = New-Object System.Windows.Controls.Border
        $item.Padding = New-Object System.Windows.Thickness(18, 7, 12, 7)
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = $visible[$i].Title
        $text.FontSize = 13
        if ($i -eq $w.Index) {
            $item.Background = New-UdpBrush '#374151'
            $text.Foreground = New-UdpBrush '#FFFFFF'
            $text.FontWeight = 'SemiBold'
        }
        elseif ($i -lt $w.Index) { $text.Foreground = New-UdpBrush '#D1D5DB' }
        else { $text.Foreground = New-UdpBrush '#9CA3AF' }
        $item.Child = $text
        [void]$c.NavList.Children.Add($item)
    }

    # Footer buttons
    switch ($page.Id) {
        'welcome' {
            $c.BackButton.IsEnabled = $false
            $c.NextButton.Visibility = 'Visible'
            $c.NextButton.IsEnabled = [bool](Get-UdpPageControl 'welcome' 'AgreeCheck').IsChecked
            $c.NextButton.Content = 'Next'
        }
        'summary' {
            $c.BackButton.IsEnabled = $true
            $c.NextButton.IsEnabled = $true
            if ($w.Context.DryRun) { $c.NextButton.Content = 'Start dry run' } else { $c.NextButton.Content = 'Start' }
        }
        'run' {
            $c.BackButton.IsEnabled = $false
            $c.NextButton.IsEnabled = $false
            $c.NextButton.Content = 'Next'
        }
        'finish' {
            $c.BackButton.Visibility = 'Collapsed'
            $c.NextButton.Visibility = 'Collapsed'
        }
        default {
            $c.BackButton.IsEnabled = $true
            $c.NextButton.IsEnabled = $true
            $c.NextButton.Content = 'Next'
        }
    }
    if (-not $w.Running) { $c.FooterStatus.Text = "Step $($w.Index + 1) of $($visible.Count): $($page.Title)" }
}

function Show-UdpPage {
    param([int]$Index)
    $w = $script:Wizard
    $visible = Get-UdpVisiblePages
    $w.Index = [Math]::Max(0, [Math]::Min($Index, $visible.Count - 1))
    $page = $visible[$w.Index]

    switch ($page.Id) {
        'edge' { Update-UdpEdgePage }
        'summary' { Update-UdpSummaryPage }
    }
    $w.Controls.PageHost.Content = $page.Root
    $page.Root.ScrollToTop()
    Update-UdpNavigation
}

function Show-UdpPageById {
    param([string]$Id)
    $visible = Get-UdpVisiblePages
    for ($i = 0; $i -lt $visible.Count; $i++) {
        if ($visible[$i].Id -eq $Id) { Show-UdpPage -Index $i; return }
    }
}

# Checks done when leaving a page with Next. Returns $false to stay on the page.
function Test-UdpPageCanLeave {
    param($Page)
    switch ($Page.Id) {
        'edge' {
            $warning = Get-UdpPageControl 'edge' 'NoBrowserWarning'
            if ($warning.Visibility -eq 'Visible' -and -not (Get-UdpPageControl 'edge' 'ConfirmNoBrowserCheck').IsChecked) {
                [System.Windows.MessageBox]::Show('Please confirm that you want to remove Edge without another browser, untick Edge removal, or go back and enable the browser step.', 'UDP', 'OK', 'Warning') | Out-Null
                return $false
            }
        }
    }
    return $true
}

function Invoke-UdpNext {
    $w = $script:Wizard
    $visible = Get-UdpVisiblePages
    $page = $visible[$w.Index]
    if (-not (Test-UdpPageCanLeave -Page $page)) { return }
    if ($page.Id -eq 'summary') { Start-UdpWizardRun; return }
    Show-UdpPage -Index ($w.Index + 1)
}

function Invoke-UdpBack {
    Show-UdpPage -Index ($script:Wizard.Index - 1)
}

# ---------------------------------------------------------------- run

function New-UdpStepRow {
    param([string]$Id, [string]$Name)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = New-Object System.Windows.GridLength(28)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)

    $glyph = New-Object System.Windows.Controls.TextBlock
    $glyph.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets')
    $glyph.FontSize = 14
    $glyph.VerticalAlignment = 'Center'
    $glyph.Text = $script:StatusGlyphs.Pending.Glyph
    $glyph.Foreground = New-UdpBrush $script:StatusGlyphs.Pending.Color

    $stack = New-Object System.Windows.Controls.StackPanel
    $label = New-UdpTextBlock -Text $Name -Style 'Body' -Margin (New-Object System.Windows.Thickness(0))
    $label.FontWeight = 'SemiBold'
    $message = New-UdpTextBlock -Text '' -Style 'Muted' -Margin (New-Object System.Windows.Thickness(0))
    [void]$stack.Children.Add($label)
    [void]$stack.Children.Add($message)

    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    [void]$grid.Children.Add($glyph)
    [void]$grid.Children.Add($stack)
    return [pscustomobject]@{ Id = $Id; Root = $grid; Glyph = $glyph; Message = $message }
}

function Set-UdpStepRowState {
    param($Row, [string]$Status, [string]$Message)
    $style = $script:StatusGlyphs[$Status]
    if (-not $style) { $style = $script:StatusGlyphs.Pending }
    $Row.Glyph.Text = $style.Glyph
    $Row.Glyph.Foreground = New-UdpBrush $style.Color
    $Row.Message.Text = $Message
}

function Start-UdpWizardRun {
    $w = $script:Wizard
    $ctx = $w.Context
    $selection = $w.Selection
    $plan = @(Get-UdpRunPlan -Context $ctx -Selection $selection)

    $list = Get-UdpPageControl 'run' 'StepList'
    $list.Children.Clear()
    $w.StepRows = @{}
    $rows = @(@{ Id = 'restorepoint'; Name = 'System Restore point' }) + @($plan | ForEach-Object { @{ Id = $_.Id; Name = $_.Name } })
    foreach ($entry in $rows) {
        $row = New-UdpStepRow -Id $entry.Id -Name $entry.Name
        $w.StepRows[$entry.Id] = $row
        [void]$list.Children.Add($row.Root)
    }
    if ($ctx.DryRun) { (Get-UdpPageControl 'run' 'RunTitle').Text = 'Dry run in progress' }

    $w.Running = $true
    $w.Controls.RunProgress.Visibility = 'Visible'
    $w.Controls.RunProgress.Value = 0
    $w.Controls.LogExpander.IsExpanded = $true
    Write-UdpLog "Selection: $(ConvertTo-Json -InputObject $selection -Depth 4 -Compress)" -Level Detail

    Show-UdpPageById -Id 'run'
    $w.Runner = Start-UdpRunner -Context $ctx -Selection $selection
}

function Complete-UdpRequest {
    param([string]$Answer)
    $sync = $script:Wizard.Context.Sync
    $script:Wizard.Controls.Overlay.Visibility = 'Collapsed'
    if ($script:Wizard.LogWasExpanded) { $script:Wizard.Controls.LogExpander.IsExpanded = $true }
    $sync.Response = $Answer
    [void]$sync.ResponseEvent.Set()
}

# One line of a list: a marker column (bullet or step number) and wrapped text with a hanging indent.
function New-UdpListItem {
    param([string]$Marker, [string]$Text)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(4, 0, 0, 4)
    $markerColumn = New-Object System.Windows.Controls.ColumnDefinition
    $markerColumn.Width = New-Object System.Windows.GridLength(22)
    [void]$grid.ColumnDefinitions.Add($markerColumn)
    [void]$grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $markerBlock = New-UdpTextBlock -Text $Marker -Style 'Body' -Margin (New-Object System.Windows.Thickness(0))
    $markerBlock.Foreground = New-UdpBrush '#2563EB'
    $markerBlock.FontWeight = 'SemiBold'
    $textBlock = New-UdpTextBlock -Text $Text -Style 'Body' -Margin (New-Object System.Windows.Thickness(0))
    [System.Windows.Controls.Grid]::SetColumn($textBlock, 1)
    [void]$grid.Children.Add($markerBlock)
    [void]$grid.Children.Add($textBlock)
    return $grid
}

# Shows the guides written in the step files. They use a few simple markers:
#   "## Title" heading, "- item" bullet, "1. step" numbered step, "> text" highlighted note.
# Any other line is a paragraph; text without markers (questions, errors) shows as plain paragraphs.
function Add-UdpFormattedText {
    param($Panel, [string]$Text)
    $Panel.Children.Clear()
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed.StartsWith('## ')) {
            $top = 10
            if ($Panel.Children.Count -eq 0) { $top = 0 }
            [void]$Panel.Children.Add((New-UdpTextBlock -Text $trimmed.Substring(3) -Style 'SectionTitle' -Margin (New-Object System.Windows.Thickness(0, $top, 0, 4))))
        }
        elseif ($trimmed.StartsWith('- ')) {
            [void]$Panel.Children.Add((New-UdpListItem -Marker ([string][char]0x2022) -Text $trimmed.Substring(2)))
        }
        elseif ($trimmed -match '^(\d+)\.\s+(.+)$') {
            [void]$Panel.Children.Add((New-UdpListItem -Marker "$($Matches[1])." -Text $Matches[2]))
        }
        elseif ($trimmed.StartsWith('> ')) {
            $box = New-Object System.Windows.Controls.Border
            $box.Style = [System.Windows.Application]::Current.FindResource('InfoBox')
            $box.Margin = New-Object System.Windows.Thickness(0, 10, 0, 2)
            $box.Child = New-UdpTextBlock -Text $trimmed.Substring(2) -Style 'Body' -Margin (New-Object System.Windows.Thickness(0))
            [void]$Panel.Children.Add($box)
        }
        else {
            [void]$Panel.Children.Add((New-UdpTextBlock -Text $trimmed -Style 'Body'))
        }
    }
}

function Show-UdpRequest {
    param($Request)
    $w = $script:Wizard
    $c = $w.Controls
    $w.ShownRequestId = $Request.Id

    if ($Request.Kind -eq 'PickFile') {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = $Request.Title
        if ($Request.FileFilter) { $dialog.Filter = $Request.FileFilter }
        $dialog.InitialDirectory = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        $answer = ''
        if ($dialog.ShowDialog($w.Window)) { $answer = $dialog.FileName }
        Complete-UdpRequest -Answer $answer
        return
    }

    # Fold the log away while a guide or question is shown, so it has room; it comes back afterwards.
    $w.LogWasExpanded = [bool]$c.LogExpander.IsExpanded
    $c.LogExpander.IsExpanded = $false
    $c.OverlayTitle.Text = $Request.Title
    Add-UdpFormattedText -Panel $c.OverlayBody -Text $Request.Body
    $c.OverlayScroll.ScrollToTop()
    $c.OverlayButtons.Children.Clear()
    $ordered = @($Request.Buttons | Where-Object { -not $_.Primary }) + @($Request.Buttons | Where-Object { $_.Primary })
    foreach ($definition in $ordered) {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = $definition.Label
        $button.Tag = $definition.Id
        $styleName = 'SecondaryButton'
        if ($definition.Primary) { $styleName = 'PrimaryButton' }
        $button.Style = [System.Windows.Application]::Current.FindResource($styleName)
        $button.Add_Click({ Complete-UdpRequest -Answer ([string]$this.Tag) })
        [void]$c.OverlayButtons.Children.Add($button)
    }
    $c.Overlay.Visibility = 'Visible'
    $w.Window.Activate() | Out-Null
}

function Show-UdpFinishPage {
    $w = $script:Wizard
    $ctx = $w.Context
    $sync = $ctx.Sync
    $results = @($sync.Results)

    $panel = Get-UdpPageControl 'finish' 'ResultsPanel'
    $panel.Children.Clear()
    foreach ($result in $results) {
        $row = New-UdpStepRow -Id $result.Id -Name $result.Name
        Set-UdpStepRowState -Row $row -Status $result.Status -Message "$($result.Status): $($result.Message)"
        [void]$panel.Children.Add($row.Root)
    }
    if ($sync.FatalError) {
        [void]$panel.Children.Add((New-UdpTextBlock -Text "The run stopped because of an unexpected error: $($sync.FatalError)" -Style 'Body'))
    }

    $failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
    $title = Get-UdpPageControl 'finish' 'FinishTitle'
    $subtitle = Get-UdpPageControl 'finish' 'FinishSubtitle'
    if ($ctx.DryRun) {
        $title.Text = 'Dry run finished'
        $subtitle.Text = 'Nothing was changed. The log shows every action UDP would have taken.'
        (Get-UdpPageControl 'finish' 'RebootPanel').Visibility = 'Collapsed'
    }
    elseif ($failed -gt 0 -or $sync.FatalError) {
        $title.Text = 'Finished with problems'
        $subtitle.Text = "$failed step(s) failed. The log has the details. The restore point lets you undo everything if needed."
    }
    else {
        $title.Text = 'All done'
        $subtitle.Text = 'Every selected step has finished.'
    }
    (Get-UdpPageControl 'finish' 'LogPathText').Text = $ctx.LogFile

    $w.Controls.RunProgress.Visibility = 'Collapsed'
    # Collapse the log so the results and the restart buttons are visible without scrolling.
    $w.Controls.LogExpander.IsExpanded = $false
    $w.Controls.FooterStatus.Text = 'Finished'
    $w.Controls.CancelButton.Content = 'Close'
    Show-UdpPageById -Id 'finish'
}

# Called by the DispatcherTimer: moves log lines to the panel and mirrors the runner's state.
function Update-UdpFromSync {
    $w = $script:Wizard
    $c = $w.Controls
    $sync = $w.Context.Sync

    $item = $null
    $count = 0
    $builder = New-Object System.Text.StringBuilder
    while ($count -lt 500 -and $sync.LogQueue.TryDequeue([ref]$item)) {
        [void]$builder.AppendLine($item.Text)
        $count++
    }
    if ($builder.Length -gt 0) {
        if ($c.LogBox.Text.Length -gt 400000) { $c.LogBox.Text = $c.LogBox.Text.Substring(200000) }
        $c.LogBox.AppendText($builder.ToString())
        $c.LogBox.ScrollToEnd()
    }

    if (-not $w.Running) { return }

    $c.RunProgress.Value = $sync.Progress
    $current = [string]$sync.CurrentStep
    (Get-UdpPageControl 'run' 'CurrentStepText').Text = $current
    $c.FooterStatus.Text = "Running: $current"
    foreach ($id in @($w.StepRows.Keys)) {
        $state = $sync.StepStates[$id]
        if ($state) { Set-UdpStepRowState -Row $w.StepRows[$id] -Status $state.Status -Message $state.Message }
    }

    $request = $sync.Request
    if ($request -and $request.Id -ne $w.ShownRequestId) { Show-UdpRequest -Request $request }

    if ($sync.Finished) {
        $w.Running = $false
        Update-UdpFromSync
        Show-UdpFinishPage
    }
}

# ---------------------------------------------------------------- window

# Builds the window and wires every event. Returns the window without showing it.
function Initialize-UdpWizard {
    param([Parameter(Mandatory)][hashtable]$Context)

    $root = $Context.Root
    Initialize-UdpApplication -Root $root
    $window = Import-UdpXaml -Path (Join-Path $root 'ui\MainWindow.xaml')

    $controls = @{}
    foreach ($name in 'NavList', 'VersionText', 'PageHost', 'Overlay', 'OverlayTitle', 'OverlayBody', 'OverlayScroll', 'OverlayButtons',
        'LogExpander', 'LogBox', 'FooterStatus', 'RunProgress', 'CancelButton', 'BackButton', 'NextButton') {
        $controls[$name] = $window.FindName($name)
    }
    $controls.VersionText.Text = "Version $($Context.Config.project.version)"

    $logoPath = Join-Path $root 'ui\logo.png'
    if (Test-Path -LiteralPath $logoPath) {
        $logo = New-Object System.Windows.Media.Imaging.BitmapImage
        $logo.BeginInit()
        $logo.UriSource = New-Object System.Uri($logoPath)
        $logo.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logo.EndInit()
        $window.Icon = $logo
        $window.FindName('SidebarLogo').Source = $logo
    }

    $pageDefinitions = @(
        @{ Id = 'welcome'; Title = 'Welcome'; File = 'Welcome.xaml'; Visible = { $true } }
        @{ Id = 'win11debloat'; Title = 'Win11Debloat'; File = 'Win11Debloat.xaml'; Visible = { $true } }
        @{ Id = 'shutup10'; Title = 'O&O ShutUp10++'; File = 'ShutUp10.xaml'; Visible = { $true } }
        @{ Id = 'bcu'; Title = 'Bulk Crap Uninstaller'; File = 'Bcu.xaml'; Visible = { $true } }
        @{ Id = 'browser'; Title = 'Browser'; File = 'Browser.xaml'; Visible = { $true } }
        @{ Id = 'edge'; Title = 'Edge removal'; File = 'EdgeRemoval.xaml'; Visible = { $true } }
        @{ Id = 'nvcleanstall'; Title = 'NVCleanstall'; File = 'NVCleanstall.xaml'; Visible = { [bool]$script:Wizard.Context.System.NvidiaGpu } }
        @{ Id = 'autoruns'; Title = 'Autoruns'; File = 'Autoruns.xaml'; Visible = { $true } }
        @{ Id = 'summary'; Title = 'Summary'; File = 'Summary.xaml'; Visible = { $true } }
        @{ Id = 'run'; Title = 'Run'; File = 'Run.xaml'; Visible = { $true } }
        @{ Id = 'finish'; Title = 'Finish'; File = 'Finish.xaml'; Visible = { $true } }
    )
    $pages = @()
    foreach ($definition in $pageDefinitions) {
        $pages += [pscustomobject]@{
            Id      = $definition.Id
            Title   = $definition.Title
            Visible = $definition.Visible
            Root    = Import-UdpXaml -Path (Join-Path $root "ui\Pages\$($definition.File)")
        }
    }

    $script:Wizard = @{
        Context        = $Context
        Window         = $window
        Controls       = $controls
        Pages          = $pages
        Index          = 0
        Selection      = $null
        Runner         = $null
        Running        = $false
        StepRows       = @{}
        ShownRequestId = $null
    }

    Initialize-UdpWelcomePage
    foreach ($pair in @(@('win11debloat', 'win11debloat'), @('shutup10', 'shutup10'), @('bcu', 'bcu'), @('browser', 'browser'),
            @('edge', 'edge'), @('nvcleanstall', 'nvcleanstall'), @('autoruns', 'autoruns'))) {
        Initialize-UdpToolAvailability -PageId $pair[0] -StepId $pair[1]
    }
    Initialize-UdpWin11DebloatPage
    Initialize-UdpShutUp10Page
    Initialize-UdpBcuPage
    Initialize-UdpBrowserPage
    Initialize-UdpEdgePage
    Initialize-UdpNVCleanstallPage

    $controls.NextButton.Add_Click({ Invoke-UdpNext })
    $controls.BackButton.Add_Click({ Invoke-UdpBack })
    $controls.CancelButton.Add_Click({ $script:Wizard.Window.Close() })

    (Get-UdpPageControl 'finish' 'OpenLogButton').Add_Click({
            Start-Process -FilePath explorer.exe -ArgumentList "/select,`"$($script:Wizard.Context.LogFile)`""
        })
    (Get-UdpPageControl 'finish' 'RebootLaterButton').Add_Click({ $script:Wizard.Window.Close() })
    (Get-UdpPageControl 'finish' 'RebootNowButton').Add_Click({
            $answer = [System.Windows.MessageBox]::Show('Restart Windows now? Save your work in other programs first.', 'UDP', 'YesNo', 'Question')
            if ($answer -ne 'Yes') { return }
            Write-UdpLog 'Restart requested by the user.' -Level Info
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList '/r /t 10 /c "UDP: restarting to finish. Run shutdown /a to cancel."' -WindowStyle Hidden
            $script:Wizard.Window.Close()
        })

    $window.Add_Closing({
            param($sender, $eventArgs)
            $w = $script:Wizard
            if (-not $w.Running) { return }
            $answer = [System.Windows.MessageBox]::Show('UDP is still running. If you close it now, the current step may be left half-done. Stop after the current step and close?', 'UDP', 'YesNo', 'Warning')
            if ($answer -ne 'Yes') { $eventArgs.Cancel = $true; return }
            $w.Context.Sync.Aborted = $true
            if ($w.Context.Sync.Request) { Complete-UdpRequest -Answer 'abort' }
        })

    Show-UdpPage -Index 0
    return $window
}

function Show-UdpWizard {
    param([Parameter(Mandatory)][hashtable]$Context)

    $window = Initialize-UdpWizard -Context $Context

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Add_Tick({ Update-UdpFromSync })
    $timer.Start()

    [void]$window.ShowDialog()
    $timer.Stop()

    if ($script:Wizard.Runner) {
        $runner = $script:Wizard.Runner
        if (-not $runner.Handle.IsCompleted) {
            Write-UdpLog 'Window closed while a step was running; the run was stopped.' -Level Warning
            try { [void]$runner.PowerShell.BeginStop($null, $null) } catch { }
        }
        else {
            $runner.PowerShell.Dispose()
            $runner.Runspace.Dispose()
        }
    }
}
