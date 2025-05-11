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

.DESCRIPTION
This function retrieves all configuration profiles from Intune, including configuration policies, device configurations,
group policy configurations, and mobile app configurations. It checks each profile's assignments to determine
which group it is assigned to, handles built-in assignment targets ("All Devices", "All Users"), and also processes
exclusion assignments. Returns a list of profiles with their assigned group names and modes.

.EXAMPLE
$profileAssignments = Get-AllConfigurationProfilesAndAssignedGroups
This example retrieves all configuration profiles and their assigned groups, storing the results in `$profileAssignments`.

.NOTES
Requires permissions: DeviceManagementConfiguration.Read.All, DeviceManagementConfiguration.ReadWrite.All, Group.Read.All.
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
                            $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName = $group.displayName
                        }
                        Default {
                            $groupId  = $assignment.target.groupId
                            Write-Host "      – Fetching group details for $groupId" -ForegroundColor Gray
                            $group    = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName = $group.displayName
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
Fetches all compliance policies and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
Retrieves all device compliance policies from Intune, checks each policy’s assignments (including all-devices,
all-users, exclusions), and returns a list of policies with their assigned group names and modes.

.EXAMPLE
$complianceAssignments = Get-AllCompliancePoliciesAndAssignedGroups
This example retrieves all compliance policies and their assigned groups into `$complianceAssignments`.

.NOTES
Requires permissions: DeviceManagementDeviceCompliancePolicy.Read.All, Group.Read.All.
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
                    $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
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
Fetches all mobile applications and their assigned groups in Intune.

.DESCRIPTION
Retrieves every mobile app configured in Intune, examines each assignment target (including all-devices, all-users,
and exclusions), and returns a list of apps with assigned group names and modes.

.EXAMPLE
$appAssignments = Get-AllApplicationsAndAssignedGroups
Stores all app-to-group assignments in `$appAssignments`.

.NOTES
Requires permissions: DeviceManagementApps.Read.All, Group.Read.All.
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
                    $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
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

.DESCRIPTION
Retrieves every remediation (device health) script configured in Intune, examines each assignment
(including all-devices, all-users, exclusions), and returns a list of scripts with assigned group names and modes.

.EXAMPLE
$remediationAssignments = Get-AllRemediationScriptsAndAssignedGroups
Stores all remediation script assignments in `$remediationAssignments`.

.NOTES
Requires permissions: DeviceManagementDeviceHealthScript.Read.All, Group.Read.All.
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
                    $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
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
Fetches all device management (platform) scripts and their assigned groups.

.DESCRIPTION
Retrieves every device management script configured in Intune, checks assignments (all-devices,
all-users, exclusions), and returns a list of scripts with assigned group names and modes.

.EXAMPLE
$platformAssignments = Get-AllPlatformScriptsAndAssignedGroups
Stores all platform script assignments in `$platformAssignments`.

.NOTES
Requires permissions: DeviceManagementDeviceManagementScript.Read.All, Group.Read.All.
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
                    $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
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

.DESCRIPTION
Retrieves every macOS shell script configured in Intune, checks assignments (all-devices,
all-users, exclusions), and returns a list of scripts with assigned group names and modes.

.EXAMPLE
$macosShellAssignments = Get-AllMacOSShellScriptsAndAssignedGroups
Stores all macOS shell script assignments in `$macosShellAssignments`.

.NOTES
Requires permissions: DeviceManagementDeviceShellScript.Read.All, Group.Read.All.
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
                    $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
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
Fetches all App Protection Policies and their assigned groups, including multiple platforms.

.DESCRIPTION
Retrieves App Protection policies (iOS, Android, Windows, WIP) from Intune, examines each assignment
(all-devices, all-users, exclusions), and returns a consolidated list of policies with group names and modes.

.EXAMPLE
$appProtectionAssignments = Get-AllAppProtectionPoliciesAndAssignedGroups
Stores all app protection policy assignments in `$appProtectionAssignments`.

.NOTES
Requires permissions: DeviceAppManagement.Read.All, DeviceAppManagement.ReadWrite.All, Group.Read.All.
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
                        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
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

# Introductory Message
Write-Host "====================================="
Write-Host "Welcome to the Intune Assignment Tool"
Write-Host "====================================="
Write-Host ""
Write-Host "This tool helps you retrieve and view the assignments for various Intune configurations."
Write-Host "You can use this tool to fetch assignments for configuration profiles, compliance policies, applications, remediation scripts, platform scripts, macOS shell scripts, app configuration policies, and app protection policies."
Write-Host "Each operation will display the profile/policy/script name along with the assigned group(s)."
Write-Host "You can easily retrieve and review group assignments for multiple resources in Intune."
Write-Host ""
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
        0 {
            Write-Host "Exiting the tool. Goodbye!" -ForegroundColor Cyan
        }
        Default {
            Write-Host "Invalid selection. Please choose a number from 0 to 8." -ForegroundColor Red
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
        Write-Host "0: Exit"
    }
} while ($true)
