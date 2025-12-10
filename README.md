# Intune Administrative Tasks Monitor

Monitor Microsoft Intune administrative tasks and receive real-time notifications via Microsoft Teams when new tasks are created.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FYOUR_USERNAME%2Fintune-admin-tasks-monitor%2Fmain%2Farm-templates%2Fazuredeploy.json)

## Overview

This solution automatically monitors the Microsoft Graph API for new Intune administrative tasks (such as device actions requiring approval) and sends notifications to a Microsoft Teams channel when new tasks are detected.

### Features

- Automated monitoring of Intune administrative tasks
- Microsoft Teams notifications for new tasks
- Serverless architecture using Azure Automation
- Secure storage of task history in Azure Blob Storage
- Easy one-click deployment to Azure
- Uses Managed Identity (no credentials to manage)

### Architecture

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Azure Automation   │────▶│   Microsoft Graph    │     │  Microsoft      │
│  (Scheduled Job)    │     │   Beta API           │     │  Teams          │
└─────────────────────┘     └──────────────────────┘     └─────────────────┘
         │                                                        ▲
         │                                                        │
         ▼                                                        │
┌─────────────────────┐                                          │
│  Azure Blob Storage │                                          │
│  (Task History)     │──────────────────────────────────────────┘
└─────────────────────┘          Webhook Notification
```

## Prerequisites

Before deploying, ensure you have:

1. **Azure Subscription** with permissions to create resources
2. **Microsoft 365 License** with Intune
3. **Microsoft Teams** channel with an Incoming Webhook configured
4. **Azure AD Role**: Application Administrator or Global Administrator (for Graph permissions)

## Quick Start

### Step 1: Create Teams Webhook

1. Open Microsoft Teams
2. Navigate to the channel where you want notifications
3. Click `...` → **Connectors** → **Incoming Webhook**
4. Name it "Intune Admin Tasks" and click **Create**
5. **Copy the webhook URL** - you'll need this for deployment

### Step 2: Deploy to Azure

Click the button below to deploy the solution:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FYOUR_USERNAME%2Fintune-admin-tasks-monitor%2Fmain%2Farm-templates%2Fazuredeploy.json)

Fill in the required parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| **Resource Group** | Create new or use existing | `rg-intune-monitor` |
| **Region** | Azure region | `West Europe` |
| **Automation Account Name** | Name for the Automation Account | `aa-intune-monitor` |
| **Storage Account Name** | Name for Storage (lowercase, max 24 chars) | `stintuneadmintasks` |
| **Teams Webhook URL** | The webhook URL from Step 1 | `https://...webhook.office.com/...` |
| **Schedule Interval** | How often to check (minutes) | `15` |

### Step 3: Assign Graph Permissions (Required!)

After deployment, you **must** assign Microsoft Graph permissions to the Managed Identity.

#### Option A: Using the provided script (Recommended)

```powershell
# Get the Managed Identity Object ID from deployment outputs
# Or find it in: Azure Portal > Automation Account > Identity > Object ID

.\scripts\Set-GraphPermissions.ps1 -ManagedIdentityObjectId "YOUR_OBJECT_ID"
```

#### Option B: Manual assignment via Azure CLI

```bash
# Variables
MANAGED_IDENTITY_ID="<Object ID from deployment>"
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

# Get the app role ID for DeviceManagementManagedDevices.Read.All
ROLE_ID=$(az ad sp show --id $GRAPH_APP_ID --query "appRoles[?value=='DeviceManagementManagedDevices.Read.All'].id" -o tsv)

# Assign the permission
az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MANAGED_IDENTITY_ID/appRoleAssignments" \
  --body "{\"principalId\":\"$MANAGED_IDENTITY_ID\",\"resourceId\":\"$(az ad sp show --id $GRAPH_APP_ID --query id -o tsv)\",\"appRoleId\":\"$ROLE_ID\"}"
```

#### Option C: Manual assignment via Azure Portal

1. Go to **Azure Portal** → **Enterprise Applications**
2. Change filter to **Managed Identities**
3. Find your Automation Account's Managed Identity
4. Go to **Permissions** → **Grant admin consent**
5. Add: `DeviceManagementManagedDevices.Read.All`

### Step 4: Test the Runbook

1. Go to your **Automation Account** in Azure Portal
2. Navigate to **Runbooks** → **Monitor-IntuneAdminTasks**
3. Click **Start** to run manually
4. Check the **Jobs** output for success
5. Verify Teams notification (if there are existing tasks)

## Configuration

### Automation Variables

The solution uses these Automation Account variables (automatically created):

| Variable | Description | Encrypted |
|----------|-------------|-----------|
| `StorageAccountName` | Blob storage account name | No |
| `ContainerName` | Blob container name | No |
| `TeamsWebhookUrl` | Teams webhook URL | Yes |

### Adjusting the Schedule

1. Go to **Automation Account** → **Schedules**
2. Click on `AdminTasksMonitorSchedule`
3. Modify the interval as needed

### Customizing Notifications

Edit the `Send-TeamsNotification` function in the runbook to customize:
- Card colors and branding
- Additional task fields
- Action buttons

## Troubleshooting

### Common Issues

#### "Access Denied" or 403 Error

**Cause**: Missing Graph API permissions

**Solution**: Run the `Set-GraphPermissions.ps1` script or manually assign `DeviceManagementManagedDevices.Read.All`

#### "Failed to get access token"

**Cause**: Managed Identity not enabled or not working

**Solution**:
1. Check Automation Account → Identity → System assigned is **On**
2. Wait 5-10 minutes for propagation after enabling

#### No Teams notification received

**Cause**: Invalid webhook URL or Teams channel issue

**Solution**:
1. Verify webhook URL in Automation Variables
2. Test webhook manually:
   ```powershell
   $body = @{text = "Test message"} | ConvertTo-Json
   Invoke-RestMethod -Uri "YOUR_WEBHOOK_URL" -Method Post -Body $body -ContentType "application/json"
   ```

#### Storage access error

**Cause**: Missing Storage Blob Data Contributor role

**Solution**: The ARM template assigns this automatically. If missing:
```powershell
az role assignment create \
  --assignee "<Managed Identity Object ID>" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage>"
```

### Viewing Logs

1. Go to **Automation Account** → **Jobs**
2. Click on a job to see detailed output
3. Check **All Logs** tab for verbose information

## API Reference

This solution uses the Microsoft Graph Beta API endpoint:

```
GET https://graph.microsoft.com/beta/devicemanagement/administrativetasks
    ?$orderby=createdDateTime desc
    &$top=50
```

### Required Permissions

| Permission | Type | Description |
|------------|------|-------------|
| `DeviceManagementManagedDevices.Read.All` | Application | Read Intune device management data |

## Security Considerations

- **Managed Identity**: No credentials stored or managed
- **Encrypted Variables**: Webhook URL stored encrypted
- **Minimal Permissions**: Only read access to device management
- **Private Storage**: Blob storage has no public access
- **TLS 1.2**: Enforced for all storage connections

## Cost Estimate

Monthly cost estimate (approximate):

| Resource | SKU | Est. Cost |
|----------|-----|-----------|
| Automation Account | Basic | ~$0 (500 min free) |
| Storage Account | Standard LRS | ~$0.02 |
| **Total** | | **~$0.02/month** |

*Assumes default 15-minute schedule (~2,880 runs/month)*

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file

## Resources

- [Microsoft Graph Administrative Tasks API](https://learn.microsoft.com/en-us/graph/api/resources/intune-partnerintegration-deviceappmanagementtask)
- [Azure Automation Documentation](https://learn.microsoft.com/en-us/azure/automation/)
- [Teams Incoming Webhooks](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)
