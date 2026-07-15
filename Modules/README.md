# Modules

This directory is populated automatically during CI/CD deployment and is **not stored in Git**.

## How it works

Module names and pinned versions are declared in [`modules.json`](../modules.json) at the repo root.
The GitHub Actions workflow runs a `Save-Module` step before packaging the Function App,
which downloads each module from the [PowerShell Gallery](https://www.powershellgallery.com/)
into this folder using the standard `ModuleName/Version/` layout that Azure Functions expects.

## Adding or updating a module

1. Edit `modules.json` in the repo root — bump the version or add a new entry.
2. Push to `main`. The workflow will download the updated module set on the next deployment.

## Local development

When running functions locally you need the modules present. Run the following once from the
repo root in a PowerShell terminal:

```powershell
$manifest = Get-Content './modules.json' | ConvertFrom-Json
foreach ($mod in $manifest) {
    Save-Module -Name $mod.Name -RequiredVersion $mod.RequiredVersion -Path './Modules' -Force -AcceptLicense
}
```
