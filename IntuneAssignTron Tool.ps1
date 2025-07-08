<#
.SYNOPSIS
    Intune Assignment Tool – fetches and visualizes assignments for various Intune entities via Microsoft Graph.

.DESCRIPTION
    This PowerShell script connects to Microsoft Graph using the Microsoft.Graph module to retrieve assignments for:
      • Configuration Profiles
      • Compliance Policies
      • Mobile Applications
      • Remediation (Device Health) Scripts
      • Platform Scripts
      • macOS Shell Scripts
      • App Protection Policies
    Results are returned as objects indicating the assignment mode (Included/Excluded), target group, and assignment type. The tool supports:
      • Exporting individual or all assignment sets to CSV files.
      • An interactive HTML network graph (Option 9) visualizing relationships between Intune objects and their target groups using PSWriteHTML.

.PARAMETER Group.Read.All
    Required Graph permission to read Azure AD group memberships and details.
.PARAMETER DeviceManagement*.*
    Required Graph permissions to read Intune device and policy configurations.

.NOTES
    - Interactive authentication via Connect-MgGraph is used; no credentials are hard-coded.
    - Local output is written to C:\Temp\AssignTron and should be gitignored if needed.
    - Option 9 regenerates a master CSV and launches an HTML diagram in the default browser.
#>

# Ensure AssignTron output folder exists
$assignTronPath = "C:\Temp\AssignTron"
if (-not (Test-Path -Path $assignTronPath)) {
    Write-Host "Creating folder $assignTronPath" -ForegroundColor Yellow
    New-Item -Path $assignTronPath -ItemType Directory | Out-Null
}

# Check if the Microsoft.Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph -Force -AllowClobber
} else {
    Write-Host "Microsoft.Graph module is already installed." -ForegroundColor Green
}

# Authenticate to Microsoft Graph
Write-Host "Authenticating to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -Scopes Group.Read.All,DeviceManagementManagedDevices.Read.All,DeviceManagementServiceConfig.Read.All,DeviceManagementApps.Read.All,DeviceManagementConfiguration.Read.All,DeviceManagementConfiguration.ReadWrite.All,DeviceManagementApps.ReadWrite.All
    Write-Host "Authentication successful!" -ForegroundColor Green
} catch {
    Write-Host "Error during authentication: $_" -ForegroundColor Red
    exit
}

<#
.SYNOPSIS
Fetches all configuration profiles and their assigned groups, including handling built-in groups like "All Devices" and "All Users".
#>
function Get-AllConfigurationProfilesAndAssignedGroups {
    Write-Host ">> Starting Get-AllConfigurationProfilesAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all Configuration Profiles and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $urls = @(
            "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments",
            "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments",
            "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=assignments"
        )
        $profileAssignments = @()
        foreach ($url in $urls) {
            Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
            $profiles = Invoke-MgGraphRequest -Uri $url
            foreach ($profile in $profiles.value) {
                $profileName = if ($profile.displayName) { $profile.displayName } else { $profile.Name }
                Write-Host "   • Processing profile: $profileName" -ForegroundColor Yellow
                foreach ($assignment in $profile.assignments) {
                    $odataType      = $assignment.target.'@odata.type'
                    $assignmentMode = 'Included'
                    switch ($odataType) {
                        "#microsoft.graph.allDevicesAssignmentTarget" {
                            $groupName = "All Devices"; $groupId = $null
                        }
                        "#microsoft.graph.allLicensedUsersAssignmentTarget" {
                            $groupName = "All Users"; $groupId = $null
                        }
                        "#microsoft.graph.exclusionGroupAssignmentTarget" {
                            $assignmentMode = 'Excluded'
                            $groupId        = $assignment.target.groupId
                            Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                            $group         = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName     = $group.displayName
                        }
                        Default {
                            $groupId    = $assignment.target.groupId
                            Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                            $group      = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName  = $group.displayName
                        }
                    }
                    Write-Host "      -> Adding [$assignmentMode] $profileName -> $groupName" -ForegroundColor Green
                    $profileAssignments += [PSCustomObject]@{
                        Name                = $profileName
                        AssignmentTarget    = $groupId
                        AssignmentGroupName = $groupName
                        AssignmentType      = "Configuration Profile"
                        AssignmentMode      = $assignmentMode
                    }
                }
            }
        }
        Write-Host ">> Completed Get-AllConfigurationProfilesAndAssignedGroups (`"$($profileAssignments.Count)`" items)" -ForegroundColor Cyan
        return $profileAssignments
    } catch {
        Write-Host "Error fetching Configuration Profiles: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all compliance policies and their assigned groups.
#>
function Get-AllCompliancePoliciesAndAssignedGroups {
    Write-Host ">> Starting Get-AllCompliancePoliciesAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all Compliance Policies and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=Assignments"
        Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
        $policies = Invoke-MgGraphRequest -Uri $url
        $complianceAssignments = @()
        foreach ($policy in $policies.value) {
            $policyName = if ($policy.displayName) { $policy.displayName } else { $policy.Name }
            Write-Host "   • Processing policy: $policyName" -ForegroundColor Yellow
            foreach ($assignment in $policy.assignments) {
                $odataType      = $assignment.target.'@odata.type'
                $assignmentMode = 'Included'
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
                    $assignmentMode = 'Excluded'
                    $groupId        = $assignment.target.groupId
                    Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                else {
                    $groupId   = $assignment.target.groupId
                    Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                Write-Host "      -> Adding [$assignmentMode] $policyName -> $groupName" -ForegroundColor Green
                $complianceAssignments += [PSCustomObject]@{
                    Name                = $policyName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Compliance Policy"
                    AssignmentMode      = $assignmentMode
                }
            }
        }
        Write-Host ">> Completed Get-AllCompliancePoliciesAndAssignedGroups (`"$($complianceAssignments.Count)`" items)" -ForegroundColor Cyan
        return $complianceAssignments
    } catch {
        Write-Host "Error fetching Compliance Policies: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all applications and their assigned groups.
#>
function Get-AllApplicationsAndAssignedGroups {
    Write-Host ">> Starting Get-AllApplicationsAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all Applications and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=Assignments"
        Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
        $apps = Invoke-MgGraphRequest -Uri $url
        $appAssignments = @()
        foreach ($app in $apps.value) {
            $appName = if ($app.displayName) { $app.displayName } else { $app.Name }
            Write-Host "   • Processing app: $appName" -ForegroundColor Yellow
            foreach ($assignment in $app.assignments) {
                $odataType      = $assignment.target.'@odata.type'
                $assignmentMode = 'Included'
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
                    $assignmentMode = 'Excluded'
                    $groupId        = $assignment.target.groupId
                    Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                else {
                    $groupId   = $assignment.target.groupId
                    Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                Write-Host "      -> Adding [$assignmentMode] $appName -> $groupName" -ForegroundColor Green
                $appAssignments += [PSCustomObject]@{
                    Name                = $appName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Application"
                    AssignmentMode      = $assignmentMode
                }
            }
        }
        Write-Host ">> Completed Get-AllApplicationsAndAssignedGroups (`"$($appAssignments.Count)`" items)" -ForegroundColor Cyan
        return $appAssignments
    } catch {
        Write-Host "Error fetching Applications: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all remediation (device health) scripts and their assigned groups.
#>
function Get-AllRemediationScriptsAndAssignedGroups {
    Write-Host ">> Starting Get-AllRemediationScriptsAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all Remediation Scripts and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?`$expand=Assignments"
        Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
        $scripts = Invoke-MgGraphRequest -Uri $url
        $remediationAssignments = @()
        foreach ($script in $scripts.value) {
            $scriptName = if ($script.displayName) { $script.displayName } else { $script.Name }
            Write-Host "   • Processing script: $scriptName" -ForegroundColor Yellow
            foreach ($assignment in $script.assignments) {
                $odataType      = $assignment.target.'@odata.type'
                $assignmentMode = 'Included'
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
                    $assignmentMode = 'Excluded'
                    $groupId        = $assignment.target.groupId
                    Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                else {
                    $groupId   = $assignment.target.groupId
                    Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                Write-Host "      -> Adding [$assignmentMode] $scriptName -> $groupName" -ForegroundColor Green
                $remediationAssignments += [PSCustomObject]@{
                    Name                = $scriptName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Remediation Script"
                    AssignmentMode      = $assignmentMode
                }
            }
        }
        Write-Host ">> Completed Get-AllRemediationScriptsAndAssignedGroups (`"$($remediationAssignments.Count)`" items)" -ForegroundColor Cyan
        return $remediationAssignments
    } catch {
        Write-Host "Error fetching Remediation Scripts: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all platform scripts and their assigned groups.
#>
function Get-AllPlatformScriptsAndAssignedGroups {
    Write-Host ">> Starting Get-AllPlatformScriptsAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all Platform Scripts and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?`$expand=assignments"
        Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
        $scripts = Invoke-MgGraphRequest -Uri $url
        $platformAssignments = @()
        foreach ($script in $scripts.value) {
            $scriptName = if ($script.displayName) { $script.displayName } else { $script.Name }
            Write-Host "   • Processing script: $scriptName" -ForegroundColor Yellow
            foreach ($assignment in $script.assignments) {
                $odataType      = $assignment.target.'@odata.type'
                $assignmentMode = 'Included'
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
                    $assignmentMode = 'Excluded'
                    $groupId        = $assignment.target.groupId
                    Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                else {
                    $groupId   = $assignment.target.groupId
                    Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                Write-Host "      -> Adding [$assignmentMode] $scriptName -> $groupName" -ForegroundColor Green
                $platformAssignments += [PSCustomObject]@{
                    Name                = $scriptName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Platform Script"
                    AssignmentMode      = $assignmentMode
                }
            }
        }
        Write-Host ">> Completed Get-AllPlatformScriptsAndAssignedGroups (`"$($platformAssignments.Count)`" items)" -ForegroundColor Cyan
        return $platformAssignments
    } catch {
        Write-Host "Error fetching Platform Scripts: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all macOS shell scripts and their assigned groups.
#>
function Get-AllMacOSShellScriptsAndAssignedGroups {
    Write-Host ">> Starting Get-AllMacOSShellScriptsAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all macOS Shell Scripts and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?`$expand=assignments"
        Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
        $scripts = Invoke-MgGraphRequest -Uri $url
        $macosShellAssignments = @()
        foreach ($script in $scripts.value) {
            $scriptName = if ($script.displayName) { $script.displayName } else { $script.Name }
            Write-Host "   • Processing script: $scriptName" -ForegroundColor Yellow
            foreach ($assignment in $script.assignments) {
                $odataType      = $assignment.target.'@odata.type'
                $assignmentMode = 'Included'
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"; $groupId = $null
                }
                elseif ($odataType -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
                    $assignmentMode = 'Excluded'
                    $groupId        = $assignment.target.groupId
                    Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                else {
                    $groupId   = $assignment.target.groupId
                    Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                    $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                }
                Write-Host "      -> Adding [$assignmentMode] $scriptName -> $groupName" -ForegroundColor Green
                $macosShellAssignments += [PSCustomObject]@{
                    Name                = $scriptName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "macOS Shell Script"
                    AssignmentMode      = $assignmentMode
                }
            }
        }
        Write-Host ">> Completed Get-AllMacOSShellScriptsAndAssignedGroups (`"$($macosShellAssignments.Count)`" items)" -ForegroundColor Cyan
        return $macosShellAssignments
    } catch {
        Write-Host "Error fetching macOS Shell Scripts: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all App Protection Policies and their assigned groups.
#>
function Get-AllAppProtectionPoliciesAndAssignedGroups {
    Write-Host ">> Starting Get-AllAppProtectionPoliciesAndAssignedGroups" -ForegroundColor Cyan
    Write-Host "Fetching all App Protection Policies and their Assigned Groups..." -ForegroundColor Yellow
    try {
        $urls = @(
            "https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections?`$expand=assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections?`$expand=assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/windowsManagedAppProtections?`$expand=assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies?`$expand=assignments"
        )
        $appProtectionAssignments = @()
        foreach ($url in $urls) {
            Write-Host "-> Querying endpoint: $url" -ForegroundColor DarkYellow
            $appProtections = Invoke-MgGraphRequest -Uri $url
            foreach ($appProtection in $appProtections.value) {
                $appProtectionName = if ($appProtection.displayName) { $appProtection.displayName } else { $appProtection.Name }
                Write-Host "   • Processing App Protection Policy: $appProtectionName" -ForegroundColor Yellow
                foreach ($assignment in $appProtection.assignments) {
                    $odataType      = $assignment.target.'@odata.type'
                    $assignmentMode = 'Included'
                    if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                        $groupName = "All Devices"; $groupId = $null
                    }
                    elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                        $groupName = "All Users"; $groupId = $null
                    }
                    elseif ($odataType -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
                        $assignmentMode = 'Excluded'
                        $groupId        = $assignment.target.groupId
                        Write-Host "      – Excluded target, fetching group $groupId" -ForegroundColor Magenta
                        $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    }
                    else {
                        $groupId   = $assignment.target.groupId
                        Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                        $group     = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    }
                    Write-Host "      -> Adding [$assignmentMode] $appProtectionName -> $groupName" -ForegroundColor Green
                    $appProtectionAssignments += [PSCustomObject]@{
                        Name                = $appProtectionName
                        AssignmentTarget    = $groupId
                        AssignmentGroupName = $groupName
                        AssignmentType      = "App Protection Policy"
                        AssignmentMode      = $assignmentMode
                    }
                }
            }
        }
        Write-Host ">> Completed Get-AllAppProtectionPoliciesAndAssignedGroups (`"$($appProtectionAssignments.Count)`" items)" -ForegroundColor Cyan
        return $appProtectionAssignments
    } catch {
        Write-Host "Error fetching App Protection Policies: $_" -ForegroundColor Red
    }
}

## MAIN SCRIPT ##

Write-Host "====================================="
Write-Host "Welcome to the Intune Assignment Tool"
Write-Host "====================================="
Write-Host ""
Write-Host "This tool helps you retrieve and view the assignments for various Intune configurations."
Write-Host ""
Write-Host "Select the operation you want to run:"
Write-Host "====================================="
Write-Host "1: Fetch Configuration Profiles and Their Assigned Groups"
Write-Host "2: Fetch Compliance Policies and Their Assigned Groups"
Write-Host "3: Fetch Applications and Their Assigned Groups"
Write-Host "4: Fetch Remediation Scripts and Their Assigned Groups"
Write-Host "5: Fetch Platform Scripts and Their Assigned Groups"
Write-Host "6: Fetch macOS Shell Scripts and Their Assigned Groups"
Write-Host "7: Fetch App Protection Policies and Their Assigned Groups"
Write-Host "8: Fetch *All* Assignments and Export to Single CSV"
Write-Host "9: Create & Open Interactive Network Graph"
Write-Host "0: Exit"
Write-Host ""

do {
    $userChoice = Read-Host "Choose the number of the operation you want to run"

    switch ($userChoice) {
        1 {
            Write-Host "You selected: Fetch Configuration Profiles and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllConfigurationProfilesAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllConfigurationProfilesAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        2 {
            Write-Host "You selected: Fetch Compliance Policies and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllCompliancePoliciesAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllCompliancePoliciesAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        3 {
            Write-Host "You selected: Fetch Applications and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllApplicationsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllApplicationsAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        4 {
            Write-Host "You selected: Fetch Remediation Scripts and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllRemediationScriptsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllRemediationScriptsAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        5 {
            Write-Host "You selected: Fetch Platform Scripts and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllPlatformScriptsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllPlatformScriptsAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        6 {
            Write-Host "You selected: Fetch macOS Shell Scripts and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllMacOSShellScriptsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllMacOSShellScriptsAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        7 {
            Write-Host "You selected: Fetch App Protection Policies and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllAppProtectionPoliciesAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv "$assignTronPath\AllAppProtectionPoliciesAndAssignedGroups.csv" -Encoding UTF8 -NoTypeInformation
        }
        8 {
            Write-Host "You selected: Fetch *All* Assignments and Export to Single CSV" -ForegroundColor Green
            $allAssignments = @()
            $allAssignments += Get-AllConfigurationProfilesAndAssignedGroups
            $allAssignments += Get-AllCompliancePoliciesAndAssignedGroups
            $allAssignments += Get-AllApplicationsAndAssignedGroups
            $allAssignments += Get-AllRemediationScriptsAndAssignedGroups
            $allAssignments += Get-AllPlatformScriptsAndAssignedGroups
            $allAssignments += Get-AllMacOSShellScriptsAndAssignedGroups
            $allAssignments += Get-AllAppProtectionPoliciesAndAssignedGroups
            $allAssignments | Out-Host
            $csvPath = "$assignTronPath\AllIntuneAssignments.csv"
            $allAssignments | Export-Csv $csvPath -Encoding UTF8 -NoTypeInformation
            Write-Host "All assignments exported to $csvPath" -ForegroundColor Cyan
        }
        9 {
            Write-Host "You selected: Create & Open Interactive Network Graph" -ForegroundColor Green

            # 1) Ensure the master CSV is fresh:
            $csvPath = "$assignTronPath\AllIntuneAssignments.csv"
            if (Test-Path $csvPath) {
                Write-Host "Existing CSV found—removing $csvPath" -ForegroundColor Yellow
                Remove-Item $csvPath -Force
            }

            Write-Host "Regenerating assignments CSV via option 8 logic..." -ForegroundColor Yellow
            $allAssignments = @()
            $allAssignments += Get-AllConfigurationProfilesAndAssignedGroups
            $allAssignments += Get-AllCompliancePoliciesAndAssignedGroups
            $allAssignments += Get-AllApplicationsAndAssignedGroups
            $allAssignments += Get-AllRemediationScriptsAndAssignedGroups
            $allAssignments += Get-AllPlatformScriptsAndAssignedGroups
            $allAssignments += Get-AllMacOSShellScriptsAndAssignedGroups
            $allAssignments += Get-AllAppProtectionPoliciesAndAssignedGroups

            $allAssignments | Export-Csv $csvPath -Encoding UTF8 -NoTypeInformation
            Write-Host "New CSV written to $csvPath" -ForegroundColor Green

            # 2) Build & show the graph:
            Import-Module PSWriteHTML
            Write-Host "Reading CSV from $csvPath" -ForegroundColor Yellow
            $data     = Import-Csv -Path $csvPath
            $profiles = $data | Select-Object -ExpandProperty Name              | Sort-Object -Unique
            $groups   = $data | Select-Object -ExpandProperty AssignmentGroupName | Sort-Object -Unique

            $htmlPath = "$assignTronPath\IntuneAssignmentsNetwork.html"
            Write-Host "Generating HTML graph at $htmlPath" -ForegroundColor Yellow

            New-HTML -TitleText 'Intune Assignments Network' `
                     -Online `
                     -FilePath  $htmlPath {
                New-HTMLSection -HeaderText 'Network Graph' {
                    New-HTMLPanel {
                        New-HTMLDiagram -Height '800px' -Width '100%' {
                            New-DiagramOptionsInteraction -Hover $true
                            New-DiagramOptionsPhysics

                            foreach ($p in $profiles) {
                                New-DiagramNode -Id $p `
                                                -Label $p `
                                                -Shape dot `
                                                -ColorBackground skyblue
                            }
                            foreach ($g in $groups) {
                                New-DiagramNode -Id $g `
                                                -Label $g `
                                                -Shape square `
                                                -ColorBackground salmon
                            }
                            foreach ($row in $data) {
                                New-DiagramLink -From  $row.Name `
                                                -To    $row.AssignmentGroupName `
                                                -Label $row.AssignmentMode `
                                                -ArrowsToEnabled `
                                                -Color '#888888'
                            }
                        }
                    }
                }
            } -ShowHTML

            Write-Host "Launched graph in default browser." -ForegroundColor Green
        }
        0 {
            Write-Host "Exiting the tool. Goodbye!" -ForegroundColor Cyan
            break
        }
        Default {
            Write-Host "Invalid selection. Please choose a number from 0 to 9." -ForegroundColor Red
        }
    }

    if ($userChoice -ne 0) {
        $continueChoice = Read-Host "Do you want to perform another operation? (Y/N)"
        if ($continueChoice -notin 'Y','y') {
            Write-Host "Exiting the tool. Goodbye!" -ForegroundColor Cyan
            break
        }
        Write-Host "====================================="
        Write-Host "Select the operation you want to run:"
        Write-Host "====================================="
        Write-Host "1: Fetch Configuration Profiles and Their Assigned Groups"
        Write-Host "2: Fetch Compliance Policies and Their Assigned Groups"
        Write-Host "3: Fetch Applications and Their Assigned Groups"
        Write-Host "4: Fetch Remediation Scripts and Their Assigned Groups"
        Write-Host "5: Fetch Platform Scripts and Their Assigned Groups"
        Write-Host "6: Fetch macOS Shell Scripts and Their Assigned Groups"
        Write-Host "7: Fetch App Protection Policies and Their Assigned Groups"
        Write-Host "8: Fetch *All* Assignments and Export to Single CSV"
        Write-Host "9: Create & Open Interactive Network Graph"
        Write-Host "0: Exit"
    }
} while ($true)
