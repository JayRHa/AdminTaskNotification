<#
.SYNOPSIS
    Monitors Microsoft Graph for new Intune administrative tasks and sends Teams notifications.

.DESCRIPTION
    This Azure Automation runbook:
    - Fetches administrative tasks from Microsoft Graph beta endpoint
    - Compares against known task IDs stored in Azure Blob Storage
    - Sends Microsoft Teams webhook notifications for new tasks
    - Updates the known task IDs in blob storage

.NOTES
    Author: Intune Admin Tasks Monitor
    Version: 1.0.0

    Prerequisites:
    - Azure Automation Account with System Assigned Managed Identity
    - Managed Identity needs: DeviceManagementManagedDevices.Read.All
    - Azure Storage Account with blob container
    - Managed Identity needs: Storage Blob Data Contributor role
    - Teams Incoming Webhook URL (stored as encrypted Automation variable)

.LINK
    https://github.com/yourrepo/intune-admin-tasks-monitor
#>

#region Configuration

# Get variables from Automation Account
$StorageAccountName = Get-AutomationVariable -Name 'StorageAccountName'
$ContainerName = Get-AutomationVariable -Name 'ContainerName'
$TeamsWebhookUrl = Get-AutomationVariable -Name 'TeamsWebhookUrl'

# Validate required variables
if ([string]::IsNullOrEmpty($StorageAccountName)) {
    throw "StorageAccountName automation variable is not set"
}
if ([string]::IsNullOrEmpty($ContainerName)) {
    throw "ContainerName automation variable is not set"
}
if ([string]::IsNullOrEmpty($TeamsWebhookUrl)) {
    throw "TeamsWebhookUrl automation variable is not set"
}

#endregion Configuration

#region Functions

function Get-ManagedIdentityToken {
    <#
    .SYNOPSIS
        Gets an access token using Managed Identity
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource
    )

    try {
        $tokenAuthUri = "$($env:IDENTITY_ENDPOINT)?resource=$Resource&api-version=2019-08-01"
        $response = Invoke-RestMethod -Uri $tokenAuthUri -Method Get -Headers @{
            "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER
        }
        return $response.access_token
    }
    catch {
        Write-Error "Failed to get access token for $Resource : $_"
        throw
    }
}

function Get-AdministrativeTasks {
    <#
    .SYNOPSIS
        Retrieves administrative tasks from Microsoft Graph
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    $uri = "https://graph.microsoft.com/beta/devicemanagement/administrativetasks?`$orderby=createdDateTime%20desc&`$top=50"

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response.value
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Error "Access denied. Ensure the Managed Identity has 'DeviceManagementManagedDevices.Read.All' permission."
        }
        Write-Error "Failed to get administrative tasks: $_"
        throw
    }
}

function Get-KnownTaskIds {
    <#
    .SYNOPSIS
        Retrieves known task IDs from Azure Blob Storage
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    $blobName = "known-task-ids.json"
    $uri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$blobName"

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "x-ms-version"  = "2020-04-08"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

        if ($response -is [string]) {
            $data = $response | ConvertFrom-Json
        }
        else {
            $data = $response
        }

        return @{
            TaskIds     = @($data.TaskIds)
            LastUpdated = $data.LastUpdated
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Output "No existing known tasks file found. This appears to be the first run."
            return @{
                TaskIds     = @()
                LastUpdated = $null
                IsFirstRun  = $true
            }
        }
        Write-Error "Failed to get known task IDs: $_"
        throw
    }
}

function Save-KnownTaskIds {
    <#
    .SYNOPSIS
        Saves known task IDs to Azure Blob Storage
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [array]$TaskIds
    )

    $blobName = "known-task-ids.json"
    $uri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$blobName"

    $data = @{
        TaskIds     = $TaskIds
        LastUpdated = (Get-Date -Format "o")
        Version     = "1.0"
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "Authorization"  = "Bearer $AccessToken"
        "x-ms-version"   = "2020-04-08"
        "x-ms-blob-type" = "BlockBlob"
        "Content-Type"   = "application/json"
    }

    try {
        Invoke-RestMethod -Uri $uri -Headers $headers -Method Put -Body $data
        Write-Output "Successfully saved $($TaskIds.Count) known task IDs to blob storage."
    }
    catch {
        Write-Error "Failed to save known task IDs: $_"
        throw
    }
}

function Send-TeamsNotification {
    <#
    .SYNOPSIS
        Sends a notification to Microsoft Teams via webhook
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$NewTasks,

        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl
    )

    # Build sections for each task
    $taskSections = @()

    foreach ($task in $NewTasks) {
        $facts = @(
            @{ name = "Task ID"; value = $task.id }
            @{ name = "Created"; value = $task.createdDateTime }
        )

        if ($task.status) {
            $facts += @{ name = "Status"; value = $task.status }
        }
        if ($task.requestorId) {
            $facts += @{ name = "Requestor"; value = $task.requestorId }
        }

        $taskSections += @{
            activityTitle    = "Task: $($task.displayName)"
            activitySubtitle = "Category: $($task.category)"
            facts            = $facts
            markdown         = $true
        }
    }

    $card = @{
        "@type"    = "MessageCard"
        "@context" = "http://schema.org/extensions"
        themeColor = "0078D4"
        summary    = "New Intune Administrative Tasks Detected"
        sections   = @(
            @{
                activityTitle    = "New Administrative Tasks Detected"
                activitySubtitle = "Detected at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
                activityImage    = "https://img.icons8.com/fluency/96/microsoft-intune.png"
                facts            = @(
                    @{ name = "New Tasks"; value = "$($NewTasks.Count)" }
                    @{ name = "Environment"; value = "Production" }
                )
                markdown         = $true
            }
        ) + $taskSections
        potentialAction = @(
            @{
                "@type"  = "OpenUri"
                name     = "Open Intune Portal"
                targets  = @(
                    @{
                        os  = "default"
                        uri = "https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/adminTasks"
                    }
                )
            }
            @{
                "@type"  = "OpenUri"
                name     = "View All Devices"
                targets  = @(
                    @{
                        os  = "default"
                        uri = "https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/overview"
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 20

    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $card -ContentType "application/json"
        Write-Output "Teams notification sent successfully."
        return $true
    }
    catch {
        Write-Error "Failed to send Teams notification: $_"
        return $false
    }
}

#endregion Functions

#region Main Script

Write-Output "=============================================="
Write-Output "  Intune Administrative Tasks Monitor"
Write-Output "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Write-Output "=============================================="

try {
    # Step 1: Get access tokens
    Write-Output "`n[1/5] Obtaining access tokens..."
    $graphToken = Get-ManagedIdentityToken -Resource "https://graph.microsoft.com"
    $storageToken = Get-ManagedIdentityToken -Resource "https://storage.azure.com"
    Write-Output "      Access tokens obtained successfully."

    # Step 2: Fetch current administrative tasks
    Write-Output "`n[2/5] Fetching administrative tasks from Microsoft Graph..."
    $currentTasks = Get-AdministrativeTasks -AccessToken $graphToken

    if ($null -eq $currentTasks -or $currentTasks.Count -eq 0) {
        Write-Output "      No administrative tasks found in Intune."
        Write-Output "`n=============================================="
        Write-Output "  Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
        Write-Output "=============================================="
        return
    }

    Write-Output "      Retrieved $($currentTasks.Count) administrative task(s)."

    # Step 3: Get known task IDs from storage
    Write-Output "`n[3/5] Retrieving known task IDs from storage..."
    $knownData = Get-KnownTaskIds -StorageAccountName $StorageAccountName `
                                   -ContainerName $ContainerName `
                                   -AccessToken $storageToken

    $knownTaskIds = @($knownData.TaskIds)
    $isFirstRun = $knownData.IsFirstRun -eq $true

    Write-Output "      Found $($knownTaskIds.Count) previously known task ID(s)."

    # Step 4: Identify new tasks
    Write-Output "`n[4/5] Analyzing tasks..."
    $currentTaskIds = @($currentTasks | Select-Object -ExpandProperty id)
    $newTaskIds = @($currentTaskIds | Where-Object { $_ -notin $knownTaskIds })
    $newTasks = @($currentTasks | Where-Object { $_.id -in $newTaskIds })

    if ($isFirstRun) {
        Write-Output "      First run detected - storing current tasks as baseline."
        Write-Output "      $($currentTasks.Count) task(s) will be tracked from now on."
    }
    elseif ($newTasks.Count -gt 0) {
        Write-Output "      Found $($newTasks.Count) NEW task(s):"
        foreach ($task in $newTasks) {
            Write-Output "        - [$($task.category)] $($task.displayName)"
        }

        # Send Teams notification
        Write-Output "`n[4a/5] Sending Teams notification..."
        $notificationSent = Send-TeamsNotification -NewTasks $newTasks -WebhookUrl $TeamsWebhookUrl

        if (-not $notificationSent) {
            Write-Warning "      Teams notification may have failed. Check webhook URL."
        }
    }
    else {
        Write-Output "      No new tasks detected since last check."
    }

    # Step 5: Update known task IDs
    Write-Output "`n[5/5] Updating known task IDs in storage..."

    # Combine and deduplicate, keep last 500 to prevent unlimited growth
    $allKnownIds = @($knownTaskIds) + @($currentTaskIds) | Select-Object -Unique
    if ($allKnownIds.Count -gt 500) {
        $allKnownIds = $allKnownIds | Select-Object -Last 500
    }

    Save-KnownTaskIds -StorageAccountName $StorageAccountName `
                      -ContainerName $ContainerName `
                      -AccessToken $storageToken `
                      -TaskIds $allKnownIds

    Write-Output "`n=============================================="
    Write-Output "  Summary"
    Write-Output "  - Tasks checked: $($currentTasks.Count)"
    Write-Output "  - New tasks: $($newTasks.Count)"
    Write-Output "  - Total tracked: $($allKnownIds.Count)"
    Write-Output "  Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
    Write-Output "=============================================="
}
catch {
    Write-Error "`nScript failed with error:"
    Write-Error $_.Exception.Message
    Write-Error $_.ScriptStackTrace
    throw
}

#endregion Main Script
