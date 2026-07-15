# PlugEvents Tools — Azure Function App

Azure Function App (PowerShell) that exposes data from [plug.events](https://plug.events/) and generates personalised event-agenda emails.

## Functions

### `UmbrellaEvents` — GET
Returns all events under a plug.events umbrella organisation for a given date range.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Umbrella` | string | ✓ | Slug of the umbrella org (e.g. `balfolk-nl`) |
| `StartDate` | string | ✓ | Start of window (`YYYY-MM-DD`) |
| `EndDate` | string | ✓ | End of window (`YYYY-MM-DD`) |
| `Top` | integer | | Maximum results (default 999) |
| `Format` | string | | `JSON` (default) or `CSV` |

---

### `PlugEventOrgs` — GET
Searches plug.events organisations by name or filter.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Top` | integer | | Maximum results |
| `Filter` | string | | Free-text name filter |

---

### `Agenda` — POST (`function` auth level)
Generates a personalised HTML email body listing upcoming events for an umbrella org,
with an embedded map and unsubscribe link. Called by a Logic App that handles the
actual email delivery via Azure Communication Services.

**Request body (JSON):**

| Field | Type | Required | Description |
|---|---|---|---|
| `RowKey` | string | ✓ | Subscriber identifier (base64url-encoded in the unsubscribe link) |
| `RemoveKey` | string | ✓ | 6-digit code used in the unsubscribe link |
| `Umbrella` | string | ✓ | Slug of the umbrella org |
| `Weeks` | integer | ✓ | How many weeks ahead to show |
| `Lat` | float | | Requestor latitude — adds a driving-distance column |
| `Lon` | float | | Requestor longitude — adds a driving-distance column |

**Response (JSON):**

```json
{
  "html":     "<full HTML email body>",
  "mapImage": "<base64-encoded PNG, or null>"
}
```

The Logic App uses `html` as the email body and attaches `mapImage` as an inline CID
attachment (`contentId: mapimage`) so it renders inside the email without external links.

Map images are cached on the `/MapCache` Azure Files mount (keyed by umbrella + weeks)
for up to 1 hour to avoid exhausting the Geoapify API quota.

---

## Deployment

Deployment is fully automated via GitHub Actions on every push to `main`.

### Workflow (`.github/workflows/main_plugeventsexport.yml`)

1. **Checkout** — checks out the repository.
2. **Download PowerShell Modules** — reads `modules.json` and runs `Save-Module` for each
   entry, populating the `Modules/` directory. The module files are **not** stored in Git.
3. **Deploy** — packages the Function App (including the freshly downloaded modules) and
   deploys to Azure using OIDC federated credentials (no long-lived secrets).

### Module management

Module versions are pinned in [`modules.json`](./modules.json).
To upgrade a module, bump the version there and push.

### Environment variables (Application Settings in Azure)

| Name | Used by | Description |
|---|---|---|
| `GEOAPIFY_API_KEY` | Agenda | API key for the Geoapify static-map endpoint |

### Azure Files mount

| Mount path | Purpose |
|---|---|
| `/MapCache` | Read/write Azure Files (SMB) share used to cache generated map images |

### Local development

Install the modules locally before running `func start`:

```powershell
$manifest = Get-Content './modules.json' | ConvertFrom-Json
foreach ($mod in $manifest) {
    Save-Module -Name $mod.Name -RequiredVersion $mod.RequiredVersion -Path './Modules' -Force -AcceptLicense
}
```
