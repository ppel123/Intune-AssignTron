# Check if the Microsoft.Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph -Force -AllowClobber
} else {
    Write-Host "Microsoft.Graph module is already installed." -ForegroundColor Green
}

# Import the Microsoft.Graph module
# Import-Module Microsoft.Graph

# Authenticate to Microsoft Graph
Write-Host "Authenticating to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -scopes Group.Read.All, DeviceManagementManagedDevices.Read.All, DeviceManagementServiceConfig.Read.All, DeviceManagementApps.Read.All, DeviceManagementApps.Read.All, DeviceManagementConfiguration.Read.All, DeviceManagementConfiguration.ReadWrite.All, DeviceManagementApps.ReadWrite.All
    Write-Host "Authentication successful!" -ForegroundColor Green
} catch {
    Write-Host "Error during authentication: $_" -ForegroundColor Red
    exit
}

<#
.SYNOPSIS
Fetches all configuration profiles and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all configuration profiles from Intune, including configuration policies, device configurations, group policy configurations, and mobile app configurations. 
It checks each profile's assignment to determine which group it is assigned to, and handles built-in groups like "All Devices" and "All Users" by using special identifiers. 
The function processes multiple group assignments for each profile and returns a list of profiles and their assigned groups.

.EXAMPLE
$profileAssignments = Get-AllConfigurationProfilesAndAssignedGroups
This example retrieves all configuration profiles and their assigned groups, and stores the results in the `$profileAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch configuration profiles and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceManagementConfiguration.Read.All`, `Group.Read.All`) to run this function.
#>
function Get-AllConfigurationProfilesAndAssignedGroups {
    Write-Host "Fetching all Configuration Profiles and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoints for different types of configuration profiles
        $urls = @(
            "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=Assignments",
            "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=Assignments",
            "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=Assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=Assignments"
        )

        $profileAssignments = @()

        # Loop through each endpoint and fetch the data
        foreach ($url in $urls) {
            $profiles = Invoke-MgGraphRequest -Uri $url

            foreach ($profile in $profiles.value) {
                $profileName = if ($profile.displayName) { $profile.displayName } else { $profile.Name }
                Write-Host "Processing profile: $profileName" -ForegroundColor Yellow

                # Fetch the assignments for each profile
                foreach ($assignment in $profile.assignments) {
                    $odataType = $assignment.target.'@odata.type'              

                    # Determine the group name based on the @odata.type
                    if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                        $groupName = "All Devices"
                    } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                        $groupName = "All Users"
                    } else {
                        $groupId = $assignment.target.groupId
                        # Fetch group details for other groups
                        try {
                            $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName = $group.displayName
                        } catch {
                            Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                            continue
                        }
                    }

                    # Add the assignment to the results
                    $profileAssignments += [PSCustomObject]@{
                        Name                = $profileName
                        AssignmentTarget    = $groupId
                        AssignmentGroupName = $groupName
                        AssignmentType      = "Configuration Profile"
                    }
                }
            }
        }

        Write-Host "Finished fetching Configuration Profiles and their assigned groups." -ForegroundColor Green
        return $profileAssignments
    } catch {
        Write-Host "Error fetching Configuration Profiles and Assignments: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all compliance policies and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all compliance policies from Intune, including device compliance policies. It checks each policy’s assignment to determine which group it is assigned to, and handles built-in groups like "All Devices" and "All Users" by using special identifiers. The function processes multiple group assignments for each policy and returns a list of policies and their assigned groups.

.EXAMPLE
$complianceAssignments = Get-AllCompliancePoliciesAndAssignedGroups
This example retrieves all compliance policies and their assigned groups, and stores the results in the `$complianceAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch compliance policies and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceManagementDeviceCompliancePolicy.Read.All`, `Group.Read.All`) to run this function.
#>

function Get-AllCompliancePoliciesAndAssignedGroups {
    Write-Host "Fetching all Compliance Policies and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoint for Device Compliance Policies
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=Assignments"
        $complianceAssignments = @()

        # Fetch the compliance policies
        $policies = Invoke-MgGraphRequest -Uri $url

        foreach ($policy in $policies.value) {
            $policyName = if ($policy.displayName) { $policy.displayName } else { $policy.Name }
            Write-Host "Processing policy: $policyName" -ForegroundColor Yellow

            # Fetch the assignments for each policy
            foreach ($assignment in $policy.assignments) {
                $groupId = $assignment.target.groupId
                $odataType = $assignment.target.'@odata.type'

                # Determine the group name based on the @odata.type
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"
                } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"
                } elseif ($groupId) {
                    # Fetch group details for other groups
                    try {
                        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    } catch {
                        Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                        continue
                    }
                } else {
                    Write-Host "No valid GroupId or @odata.type for policy: $policyName" -ForegroundColor Red
                    continue
                }

                # Add the assignment to the results (one entry per group assignment)
                $complianceAssignments += [PSCustomObject]@{
                    Name                = $policyName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Compliance Policy"
                }
            }
        }

        Write-Host "Finished fetching Compliance Policies and their assigned groups." -ForegroundColor Green
        return $complianceAssignments
    } catch {
        Write-Host "Error fetching Compliance Policies and Assignments: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all applications in Intune and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all mobile applications from Intune and their assigned groups. It checks each application’s assignment to determine which group it is assigned to and handles built-in groups like "All Devices" and "All Users" by using special identifiers. The function processes multiple group assignments for each application and returns a list of applications and their assigned groups.

.EXAMPLE
$applicationAssignments = Get-AllApplicationsAndAssignedGroups
This example retrieves all applications and their assigned groups, and stores the results in the `$applicationAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch mobile applications and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceManagementApps.Read.All`, `Group.Read.All`) to run this function.
#>

function Get-AllApplicationsAndAssignedGroups {
    Write-Host "Fetching all Applications and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoint for Mobile Applications
        $url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=Assignments"
        $appAssignments = @()

        # Fetch the mobile apps
        $apps = Invoke-MgGraphRequest -Uri $url

        foreach ($app in $apps.value) {
            $appName = if ($app.displayName) { $app.displayName } else { $app.Name }
            Write-Host "Processing app: $appName" -ForegroundColor Yellow

            # Fetch the assignments for each app
            foreach ($assignment in $app.assignments) {
                $groupId = $assignment.target.groupId
                $odataType = $assignment.target.'@odata.type'

                # Determine the group name based on the @odata.type
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"
                } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"
                } elseif ($groupId) {
                    # Fetch group details for other groups
                    try {
                        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    } catch {
                        Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                        continue
                    }
                } else {
                    Write-Host "No valid GroupId or @odata.type for app: $appName" -ForegroundColor Red
                    continue
                }

                # Add the assignment to the results (one entry per group assignment)
                $appAssignments += [PSCustomObject]@{
                    Name                = $appName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Application"
                }
            }
        }

        Write-Host "Finished fetching Applications and their assigned groups." -ForegroundColor Green
        return $appAssignments
    } catch {
        Write-Host "Error fetching Applications and Assignments: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all remediation scripts and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all remediation scripts (device health scripts) from Intune and their assigned groups. It checks each script's assignment to determine which group it is assigned to, and handles built-in groups like "All Devices" and "All Users" by using special identifiers. The function processes multiple group assignments for each script and returns a list of scripts and their assigned groups.

.EXAMPLE
$remediationAssignments = Get-AllRemediationScriptsAndAssignedGroups
This example retrieves all remediation scripts and their assigned groups, and stores the results in the `$remediationAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch remediation scripts and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceManagementDeviceHealthScript.Read.All`, `Group.Read.All`) to run this function.
#>

function Get-AllRemediationScriptsAndAssignedGroups {
    Write-Host "Fetching all Remediation Scripts and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoint for Device Health Scripts (Remediation Scripts)
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?`$expand=Assignments"
        $remediationAssignments = @()

        # Fetch the remediation scripts
        $scripts = Invoke-MgGraphRequest -Uri $url

        foreach ($script in $scripts.value) {
            $scriptName = if ($script.displayName) { $script.displayName } else { $script.Name }
            Write-Host "Processing script: $scriptName" -ForegroundColor Yellow

            # Fetch the assignments for each script
            foreach ($assignment in $script.assignments) {
                $groupId = $assignment.target.groupId
                $odataType = $assignment.target.'@odata.type'

                # Determine the group name based on the @odata.type
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"
                } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"
                } elseif ($groupId) {
                    # Fetch group details for other groups
                    try {
                        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    } catch {
                        Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                        continue
                    }
                } else {
                    Write-Host "No valid GroupId or @odata.type for script: $scriptName" -ForegroundColor Red
                    continue
                }

                # Add the assignment to the results (one entry per group assignment)
                $remediationAssignments += [PSCustomObject]@{
                    Name                = $scriptName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Remediation Script"
                }
            }
        }

        Write-Host "Finished fetching Remediation Scripts and their assigned groups." -ForegroundColor Green
        return $remediationAssignments
    } catch {
        Write-Host "Error fetching Remediation Scripts and Assignments: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all platform scripts (device management scripts) and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all platform scripts (device management scripts) from Intune and their assigned groups. It checks each script's assignment to determine which group it is assigned to, and handles built-in groups like "All Devices" and "All Users" by using special identifiers. The function processes multiple group assignments for each platform script and returns a list of scripts and their assigned groups.

.EXAMPLE
$platformAssignments = Get-AllPlatformScriptsAndAssignedGroups
This example retrieves all platform scripts and their assigned groups, and stores the results in the `$platformAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch platform scripts and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceManagementDeviceManagementScript.Read.All`, `Group.Read.All`) to run this function.
#>

function Get-AllPlatformScriptsAndAssignedGroups {
    Write-Host "Fetching all Platform Scripts and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoint for Device Management Scripts (Platform Scripts)
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?`$expand=Assignments"
        $platformAssignments = @()

        # Fetch the platform scripts
        $scripts = Invoke-MgGraphRequest -Uri $url

        foreach ($script in $scripts.value) {
            $scriptName = if ($script.displayName) { $script.displayName } else { $script.Name }
            Write-Host "Processing script: $scriptName" -ForegroundColor Yellow

            # Fetch the assignments for each script
            foreach ($assignment in $script.assignments) {
                $groupId = $assignment.target.groupId
                $odataType = $assignment.target.'@odata.type'

                # Determine the group name based on the @odata.type
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"
                } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"
                } elseif ($groupId) {
                    # Fetch group details for other groups
                    try {
                        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    } catch {
                        Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                        continue
                    }
                } else {
                    Write-Host "No valid GroupId or @odata.type for script: $scriptName" -ForegroundColor Red
                    continue
                }

                # Add the assignment to the results (one entry per group assignment)
                $platformAssignments += [PSCustomObject]@{
                    Name                = $scriptName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "Platform Script"
                }
            }
        }

        Write-Host "Finished fetching Platform Scripts and their assigned groups." -ForegroundColor Green
        return $platformAssignments
    } catch {
        Write-Host "Error fetching Platform Scripts and Assignments: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all macOS Shell Scripts and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all macOS shell scripts from Intune and their assigned groups. It checks each script's assignment to determine which group it is assigned to, and handles built-in groups like "All Devices" and "All Users" by using special identifiers. The function processes multiple group assignments for each script and returns a list of scripts and their assigned groups.

.EXAMPLE
$macosShellAssignments = Get-AllMacOSShellScriptsAndAssignedGroups
This example retrieves all macOS Shell Scripts and their assigned groups, and stores the results in the `$macosShellAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch macOS Shell Scripts and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceManagementDeviceShellScript.Read.All`, `Group.Read.All`) to run this function.
#>

function Get-AllMacOSShellScriptsAndAssignedGroups {
    Write-Host "Fetching all macOS Shell Scripts and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoint for macOS Shell Scripts
        $url = "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?`$expand=assignments"
        $macosShellAssignments = @()

        # Fetch the macOS shell scripts
        $scripts = Invoke-MgGraphRequest -Uri $url

        foreach ($script in $scripts.value) {
            $scriptName = if ($script.displayName) { $script.displayName } else { $script.Name }
            Write-Host "Processing script: $scriptName" -ForegroundColor Yellow

            # Fetch the assignments for each script
            foreach ($assignment in $script.assignments) {
                $groupId = $assignment.target.groupId
                $odataType = $assignment.target.'@odata.type'

                # Determine the group name based on the @odata.type
                if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                    $groupName = "All Devices"
                } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                    $groupName = "All Users"
                } elseif ($groupId) {
                    # Fetch group details for other groups
                    try {
                        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                        $groupName = $group.displayName
                    } catch {
                        Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                        continue
                    }
                } else {
                    Write-Host "No valid GroupId or @odata.type for script: $scriptName" -ForegroundColor Red
                    continue
                }

                # Add the assignment to the results (one entry per group assignment)
                $macosShellAssignments += [PSCustomObject]@{
                    Name                = $scriptName
                    AssignmentTarget    = $groupId
                    AssignmentGroupName = $groupName
                    AssignmentType      = "macOS Shell Script"
                }
            }
        }

        Write-Host "Finished fetching macOS Shell Scripts and their assigned groups." -ForegroundColor Green
        return $macosShellAssignments
    } catch {
        Write-Host "Error fetching macOS Shell Scripts and Assignments: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
Fetches all App Protection Policies and their assigned groups, including handling built-in groups like "All Devices" and "All Users".

.DESCRIPTION
This function retrieves all app protection policies (iOS, Android, Windows, and MDM Windows Information Protection) from Intune and their assigned groups. It checks each policy's assignment to determine which group it is assigned to, and handles built-in groups like "All Devices" and "All Users" by using special identifiers. The function processes multiple group assignments for each policy and returns a list of policies and their assigned groups.

.EXAMPLE
$appProtectionAssignments = Get-AllAppProtectionPoliciesAndAssignedGroups
This example retrieves all App Protection Policies and their assigned groups, and stores the results in the `$appProtectionAssignments` variable.

.NOTES
The function uses the Microsoft Graph API to fetch app protection policies and assignments. It handles both standard and built-in Intune groups.
Ensure that you have the necessary permissions (e.g., `DeviceAppManagement.Read.All`, `Group.Read.All`) to run this function.
#>

function Get-AllAppProtectionPoliciesAndAssignedGroups {
    Write-Host "Fetching all App Protection Policies and their Assigned Groups..." -ForegroundColor Yellow
    try {
        # Define the endpoints for App Protection Policies
        $urls = @(
            "https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections?`$expand=Assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections?`$expand=Assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/windowsManagedAppProtections?`$expand=Assignments",
            "https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies?`$expand=Assignments"
        )

        $appProtectionAssignments = @()

        # Loop through each endpoint and fetch the data
        foreach ($url in $urls) {
            $appProtections = Invoke-MgGraphRequest -Uri $url

            foreach ($appProtection in $appProtections.value) {
                $appProtectionName = if ($appProtection.displayName) { $appProtection.displayName } else { $appProtection.Name }
                Write-Host "Processing App Protection Policy: $appProtectionName" -ForegroundColor Yellow

                # Fetch the assignments for each policy
                foreach ($assignment in $appProtection.assignments) {
                    $groupId = $assignment.target.groupId
                    $odataType = $assignment.target.'@odata.type'

                    # Determine the group name based on the @odata.type
                    if ($odataType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                        $groupName = "All Devices"
                    } elseif ($odataType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                        $groupName = "All Users"
                    } elseif ($groupId) {
                        # Fetch group details for other groups
                        try {
                            $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName = $group.displayName
                        } catch {
                            Write-Host "Error fetching group details for GroupId: $groupId" -ForegroundColor Red
                            continue
                        }
                    } else {
                        Write-Host "No valid GroupId or @odata.type for app protection policy: $appProtectionName" -ForegroundColor Red
                        continue
                    }

                    # Add the assignment to the results (one entry per group assignment)
                    $appProtectionAssignments += [PSCustomObject]@{
                        Name                = $appProtectionName
                        AssignmentTarget    = $groupId
                        AssignmentGroupName = $groupName
                        AssignmentType      = "App Protection Policy"
                    }
                }
            }
        }

        Write-Host "Finished fetching App Protection Policies and their assigned groups." -ForegroundColor Green
        return $appProtectionAssignments
    } catch {
        Write-Host "Error fetching App Protection Policies and Assignments: $_" -ForegroundColor Red
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

# Loop to keep prompting for input
do {
    $userChoice = Read-Host "Choose the number of the operation you want to run"

    switch ($userChoice) {
        1 {
            Write-Host "You selected: Fetch Configuration Profiles and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllConfigurationProfilesAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv C:\Temp\AllConfigurationProfilesAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        2 {
            Write-Host "You selected: Fetch Compliance Policies and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllCompliancePoliciesAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv AllCompliancePoliciesAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        3 {
            Write-Host "You selected: Fetch Applications and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllApplicationsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv AllApplicationsAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        4 {
            Write-Host "You selected: Fetch Remediation Scripts and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllRemediationScriptsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv AllRemediationScriptsAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        5 {
            Write-Host "You selected: Fetch Platform Scripts and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllPlatformScriptsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv AllPlatformScriptsAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        6 {
            Write-Host "You selected: Fetch macOS Shell Scripts and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllMacOSShellScriptsAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv AllMacOSShellScriptsAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        7 {
            Write-Host "You selected: Fetch App Protection Policies and Their Assigned Groups" -ForegroundColor Green
            $result = Get-AllAppProtectionPoliciesAndAssignedGroups
            $result | Out-Host
            $result | Export-Csv AllAppProtectionPoliciesAndAssignedGroups.csv -Encoding UTF8 -NoTypeInformation
        }
        8 {
            Write-Host "You selected: Fetch *All* Assignments and Export to Single CSV" -ForegroundColor Green

            # 1. Gather all assignments
            $allAssignments = @()
            $allAssignments += Get-AllConfigurationProfilesAndAssignedGroups
            $allAssignments += Get-AllCompliancePoliciesAndAssignedGroups
            $allAssignments += Get-AllApplicationsAndAssignedGroups
            $allAssignments += Get-AllRemediationScriptsAndAssignedGroups
            $allAssignments += Get-AllPlatformScriptsAndAssignedGroups
            $allAssignments += Get-AllMacOSShellScriptsAndAssignedGroups
            $allAssignments += Get-AllAppProtectionPoliciesAndAssignedGroups

            # 2. Output to console
            $allAssignments | Out-Host

            # 3. Export to CSV
            $csvPath = "C:\Temp\AllIntuneAssignments.csv"
            $allAssignments | Export-Csv $csvPath -Encoding UTF8 -NoTypeInformation

            Write-Host "All assignments exported to $csvPath" -ForegroundColor Cyan
        }
        0 {
            Write-Host "Exiting the tool. Goodbye!" -ForegroundColor Cyan
        }
        default {
            Write-Host "Invalid selection. Please choose a number from 0 to 7." -ForegroundColor Red
        }
    }

    if ($userChoice -ne 9) {
        $continueChoice = Read-Host "Do you want to perform another operation? (Y/N)"
        if ($continueChoice -ne 'Y' -and $continueChoice -ne 'y') {
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
} while ($userChoice -ne 0)
