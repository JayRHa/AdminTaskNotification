<!-- jr-brand:start -->
<div align="center">
  <a href="https://jannikreinhard.com/">
    <img src="https://raw.githubusercontent.com/JayRHa/.github/main/assets/readme/tool.svg" alt="Jannik Reinhard — Driving AI with passion" width="100%">
  </a>
  <h1>Admin Task Notification</h1>
  <p><strong>Notification system for administrative tasks and alerts in endpoint management environments.</strong></p>
  <p>
  <a href="https://jannikreinhard.com/"><img src="https://img.shields.io/badge/Website-146CDD?style=flat-square&amp;logo=wordpress&amp;logoColor=white" alt="Website"></a>
  <a href="https://github.com/JayRHa"><img src="https://img.shields.io/badge/GitHub-081427?style=flat-square&amp;logo=github&amp;logoColor=white" alt="GitHub"></a>
  <a href="https://www.linkedin.com/in/jannik-r/"><img src="https://img.shields.io/badge/LinkedIn-0795FF?style=flat-square&amp;logo=linkedin&amp;logoColor=white" alt="LinkedIn"></a>
  <a href="https://x.com/jannik_reinhard"><img src="https://img.shields.io/badge/X-081427?style=flat-square&amp;logo=x&amp;logoColor=white" alt="X"></a>
  <a href="https://www.youtube.com/@jannikreinhard"><img src="https://img.shields.io/badge/YouTube-146CDD?style=flat-square&amp;logo=youtube&amp;logoColor=white" alt="YouTube"></a>
  </p>
  <p><sub>Driving AI with passion · Microsoft Foundry · Intune · Azure</sub></p>
</div>
<!-- jr-brand:end -->

## Overview

This solution deploys an Azure Logic App that:
- Periodically checks for new Intune administrative tasks via Microsoft Graph API
- Sends notifications to a specified Microsoft Teams channel when new tasks are detected
- Tracks known tasks in Azure Blob Storage to avoid duplicate notifications

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FJayRHa%2FAdminTaskNotification%2Fmain%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FJayRHa%2FAdminTaskNotification%2Fmain%2Fazuredeploy.json)

> **Note:** After clicking "Deploy to Azure", wait a few seconds for the custom deployment page to load. If nothing happens, try opening the link in a new incognito/private browser window.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| **logicAppName** | Name of the Logic App | `intune-admin-task-monitor` |
| **teamsGroupId** | Teams Group ID for notifications | *Required* |
| **teamsChannelId** | Teams Channel ID for notifications | *Required* |
| **recurrenceInterval** | How often to check for new tasks (in minutes) | `5` |

> **Note:** Storage Account Name and Location are automatically configured based on the Resource Group.

### How to find Teams Group ID and Channel ID

1. Open **Microsoft Teams**
2. Right-click on the **Team** → "Get link to team"
3. The URL contains: `groupId=<YOUR-GROUP-ID>`
4. Right-click on the **Channel** → "Get link to channel"
5. The URL contains the Channel ID (starts with `19:...`)

## Post-Deployment Steps

### 1. Authorize API Connections

After deployment, you need to authorize the API connections:

1. Navigate to your Resource Group in the Azure Portal
2. Open the **Teams** connection and click "Edit API connection" → "Authorize"
3. Sign in with your Microsoft 365 account

### 2. Assign Graph API Permissions

The Logic App uses a Managed Identity to access Microsoft Graph. Grant the required permission:

```powershell
# Install Microsoft Graph PowerShell module if not already installed
Install-Module Microsoft.Graph -Scope CurrentUser

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All"

# Get the Logic App's Managed Identity Principal ID (from deployment output)
$principalId = "<Logic-App-Managed-Identity-Principal-ID>"

# Get Microsoft Graph Service Principal
$graphApp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Get the DeviceManagementManagedDevices.Read.All permission
$permission = $graphApp.AppRoles | Where-Object { $_.Value -eq "DeviceManagementManagedDevices.Read.All" }

# Assign the permission
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $principalId -PrincipalId $principalId -ResourceId $graphApp.Id -AppRoleId $permission.Id
```

### 3. Get Teams Group and Channel IDs

To find your Teams Group ID and Channel ID:

1. Open Microsoft Teams
2. Navigate to the desired channel
3. Click "..." → "Get link to channel"
4. The link contains both IDs in the format:
   - Group ID: `groupId=<GUID>`
   - Channel ID: `tenantId=...&groupId=...&parentMessageId=...&teamId=...&channelId=<channel-id>`

Alternatively, use Graph Explorer or PowerShell to retrieve the IDs.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Recurrence    │────▶│   Logic App      │────▶│  Teams Channel  │
│   Trigger       │     │   (MSI Auth)     │     │  Notification   │
└─────────────────┘     └────────┬─────────┘     └─────────────────┘
                                 │
                        ┌────────▼─────────┐
                        │  Microsoft Graph │
                        │  (Admin Tasks)   │
                        └────────┬─────────┘
                                 │
                        ┌────────▼─────────┐
                        │  Blob Storage    │
                        │  (Task Tracking) │
                        └──────────────────┘
```

## Required Permissions

- **DeviceManagementManagedDevices.Read.All** - Required for reading administrative tasks from Intune

## License

MIT License

<!-- jr-brand-footer:start -->

---

<div align="center">
  <p><sub>Built and maintained by <a href="https://jannikreinhard.com/">Jannik Reinhard</a> · Microsoft MVP for Security and AI Platform.</sub></p>
  <p><a href="https://www.buymeacoffee.com/jannikreinf">Support the open-source work</a></p>
  <p><strong>Stay healthy, Cheers Jannik</strong></p>
</div>

<!-- jr-brand-footer:end -->
