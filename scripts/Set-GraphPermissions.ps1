<#
.SYNOPSIS
    Assigns Microsoft Graph API permissions to the Automation Account Managed Identity.

.DESCRIPTION
    This script must be run AFTER the ARM template deployment to grant the
    Managed Identity the required Microsoft Graph permissions:
    - DeviceManagementManagedDevices.Read.All

.PARAMETER ManagedIdentityObjectId
    The Object ID (Principal ID) of the Automation Account's Managed Identity.
    This is output from the ARM template deployment.

.EXAMPLE
    .\Set-GraphPermissions.ps1 -ManagedIdentityObjectId "12345678-1234-1234-1234-123456789abc"

.NOTES
    Prerequisites:
    - Microsoft.Graph PowerShell module installed
    - User running script needs: Application Administrator or Global Administrator role
    - Or: AppRoleAssignment.ReadWrite.All and Application.Read.All permissions
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The Object ID of the Automation Account Managed Identity")]
    [ValidateNotNullOrEmpty()]
    [string]$ManagedIdentityObjectId
)

# Required Graph permissions for the solution
$RequiredPermissions = @(
    "DeviceManagementManagedDevices.Read.All"
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Microsoft Graph Permissions Assignment" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Check if Microsoft.Graph module is installed
Write-Host "[1/4] Checking Microsoft.Graph module..." -ForegroundColor Yellow
$graphModule = Get-Module -ListAvailable -Name Microsoft.Graph.Applications

if (-not $graphModule) {
    Write-Host "      Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}
else {
    Write-Host "      Microsoft.Graph module found (v$($graphModule.Version))" -ForegroundColor Green
}

# Connect to Microsoft Graph
Write-Host "`n[2/4] Connecting to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome
    Write-Host "      Connected successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# Get the Managed Identity Service Principal
Write-Host "`n[3/4] Retrieving Managed Identity..." -ForegroundColor Yellow
try {
    $ManagedIdentitySP = Get-MgServicePrincipal -Filter "id eq '$ManagedIdentityObjectId'"

    if (-not $ManagedIdentitySP) {
        # Try searching by servicePrincipalId
        $ManagedIdentitySP = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityObjectId
    }

    if (-not $ManagedIdentitySP) {
        Write-Error "Could not find Managed Identity with Object ID: $ManagedIdentityObjectId"
        Write-Host "`nTip: You can find the Object ID in:" -ForegroundColor Yellow
        Write-Host "  - Azure Portal > Automation Account > Identity > System assigned" -ForegroundColor Gray
        Write-Host "  - Or from the ARM template deployment outputs" -ForegroundColor Gray
        exit 1
    }

    Write-Host "      Found: $($ManagedIdentitySP.DisplayName)" -ForegroundColor Green
    Write-Host "      App ID: $($ManagedIdentitySP.AppId)" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to get Managed Identity: $_"
    exit 1
}

# Get Microsoft Graph Service Principal
Write-Host "`n[4/4] Assigning permissions..." -ForegroundColor Yellow
try {
    $GraphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

    if (-not $GraphSP) {
        Write-Error "Could not find Microsoft Graph service principal"
        exit 1
    }

    Write-Host "      Microsoft Graph SP found" -ForegroundColor Green

    # Get existing role assignments
    $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentitySP.Id

    foreach ($permission in $RequiredPermissions) {
        Write-Host ""
        Write-Host "      Processing: $permission" -ForegroundColor Cyan

        # Find the app role
        $appRole = $GraphSP.AppRoles | Where-Object { $_.Value -eq $permission }

        if (-not $appRole) {
            Write-Warning "      Permission '$permission' not found in Microsoft Graph"
            continue
        }

        # Check if already assigned
        $existing = $existingAssignments | Where-Object { $_.AppRoleId -eq $appRole.Id }

        if ($existing) {
            Write-Host "        Already assigned" -ForegroundColor Yellow
            continue
        }

        # Assign the permission
        try {
            $params = @{
                PrincipalId = $ManagedIdentitySP.Id
                ResourceId  = $GraphSP.Id
                AppRoleId   = $appRole.Id
            }

            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentitySP.Id -BodyParameter $params | Out-Null
            Write-Host "        Assigned successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "        Failed to assign: $_"
        }
    }
}
catch {
    Write-Error "Failed to assign permissions: $_"
    exit 1
}

# Disconnect
Disconnect-MgGraph | Out-Null

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Permission assignment complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The Managed Identity now has these permissions:" -ForegroundColor White
foreach ($perm in $RequiredPermissions) {
    Write-Host "  - $perm" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Note: It may take a few minutes for permissions to propagate." -ForegroundColor Yellow
Write-Host "You can now run the runbook manually to test." -ForegroundColor Yellow
