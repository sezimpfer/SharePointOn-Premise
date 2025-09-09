<#
.SYNOPSIS
    Gets all SharePoint sites that are set to ReadOnly in SharePoint Server 2016.

.DESCRIPTION
    This script retrieves all site collections and webs in the SharePoint 2016 farm
    that have ReadOnly status enabled. It provides detailed information about each
    ReadOnly site including URL, title, and lock status.

.PARAMETER WebApplicationUrl
    Optional. Specify a specific web application URL to limit the scope.
    If not provided, the script will check all web applications in the farm.

.PARAMETER ExportPath
    Optional. Specify a path to export the results to a CSV file.

.EXAMPLE
    .\Get-ReadOnlySites.ps1
    Gets all ReadOnly sites from all web applications in the farm.

.EXAMPLE
    .\Get-ReadOnlySites.ps1 -WebApplicationUrl "http://sharepoint.contoso.com"
    Gets ReadOnly sites from a specific web application.

.EXAMPLE
    .\Get-ReadOnlySites.ps1 -ExportPath "C:\Reports\ReadOnlySites.csv"
    Gets all ReadOnly sites and exports results to CSV file.

.NOTES
    SharePoint Version: SharePoint Server 2016
    Requires: SharePoint PowerShell snap-in
    Run as: Farm Administrator
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$WebApplicationUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath
)

# Initialize variables
$ErrorActionPreference = "Stop"
$ReadOnlySites = @()
$ScriptStartTime = Get-Date

try {
    Write-Host "Starting ReadOnly Sites Discovery Script..." -ForegroundColor Green
    Write-Host "Target: SharePoint Server 2016" -ForegroundColor Yellow
    Write-Host "Start Time: $ScriptStartTime" -ForegroundColor Yellow
    Write-Host ""

    # Check and add SharePoint PowerShell snap-in
    Write-Host "Checking SharePoint PowerShell snap-in..." -ForegroundColor Yellow
    if ((Get-PSSnapin -Name "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
        Write-Host "Adding SharePoint PowerShell snap-in..." -ForegroundColor Yellow
        Add-PSSnapin "Microsoft.SharePoint.PowerShell"
        Write-Host "SharePoint PowerShell snap-in loaded successfully." -ForegroundColor Green
    } else {
        Write-Host "SharePoint PowerShell snap-in already loaded." -ForegroundColor Green
    }

    # Verify we can connect to the SharePoint farm
    Write-Host "Verifying connection to SharePoint farm..." -ForegroundColor Yellow
    $Farm = Get-SPFarm -ErrorAction Stop
    if ($Farm -eq $null) {
        throw "Unable to connect to SharePoint farm. Please verify you're running this script on a SharePoint server."
    }
    Write-Host "Successfully connected to SharePoint farm: $($Farm.Name)" -ForegroundColor Green
    Write-Host ""

    # Get web applications to process
    if ($WebApplicationUrl) {
        Write-Host "Processing specific web application: $WebApplicationUrl" -ForegroundColor Yellow
        $WebApplications = Get-SPWebApplication -Identity $WebApplicationUrl -ErrorAction Stop
    } else {
        Write-Host "Getting all web applications in the farm..." -ForegroundColor Yellow
        $WebApplications = Get-SPWebApplication -ErrorAction Stop
    }

    Write-Host "Found $($WebApplications.Count) web application(s) to process." -ForegroundColor Green
    Write-Host ""

    # Process each web application
    foreach ($WebApp in $WebApplications) {
        Write-Host "Processing Web Application: $($WebApp.Url)" -ForegroundColor Cyan
        
        # Get all site collections in the web application
        $SiteCollections = Get-SPSite -WebApplication $WebApp -Limit All -ErrorAction Continue
        Write-Host "  Found $($SiteCollections.Count) site collection(s)" -ForegroundColor Gray

        # Check each site collection
        foreach ($SiteCollection in $SiteCollections) {
            try {
                # Check if site collection is ReadOnly
                if ($SiteCollection.ReadOnly -eq $true) {
                    Write-Host "  Found ReadOnly Site Collection: $($SiteCollection.Url)" -ForegroundColor Red
                    
                    $SiteInfo = New-Object PSObject -Property @{
                        Type = "Site Collection"
                        Url = $SiteCollection.Url
                        Title = $SiteCollection.RootWeb.Title
                        ReadOnly = $SiteCollection.ReadOnly
                        LockIssue = $SiteCollection.LockIssue
                        Owner = $SiteCollection.Owner.LoginName
                        LastModified = $SiteCollection.LastContentModifiedDate
                        WebApplication = $WebApp.Url
                    }
                    $ReadOnlySites += $SiteInfo
                }

                # Check all webs within the site collection
                $Webs = Get-SPWeb -Site $SiteCollection -Limit All -ErrorAction Continue
                foreach ($Web in $Webs) {
                    try {
                        # Check if web is ReadOnly
                        if ($Web.ReadOnlyUI -eq $true -or $Web.AllowUnsafeUpdates -eq $false) {
                            Write-Host "    Found ReadOnly Web: $($Web.Url)" -ForegroundColor Yellow
                            
                            $WebInfo = New-Object PSObject -Property @{
                                Type = "Web"
                                Url = $Web.Url
                                Title = $Web.Title
                                ReadOnly = $Web.ReadOnlyUI
                                AllowUnsafeUpdates = $Web.AllowUnsafeUpdates
                                LockIssue = "N/A"
                                Owner = if($Web.HasUniqueRoleAssignments) { "Unique Permissions" } else { "Inherited" }
                                LastModified = $Web.LastItemModifiedDate
                                WebApplication = $WebApp.Url
                            }
                            $ReadOnlySites += $WebInfo
                        }
                    }
                    catch {
                        Write-Warning "Error processing web $($Web.Url): $($_.Exception.Message)"
                    }
                    finally {
                        # Dispose web object to free memory
                        if ($Web -ne $null) { $Web.Dispose() }
                    }
                }
            }
            catch {
                Write-Warning "Error processing site collection $($SiteCollection.Url): $($_.Exception.Message)"
            }
            finally {
                # Dispose site collection object to free memory
                if ($SiteCollection -ne $null) { $SiteCollection.Dispose() }
            }
        }
    }

    Write-Host ""
    Write-Host "ReadOnly Sites Discovery Complete!" -ForegroundColor Green
    Write-Host "Total ReadOnly sites found: $($ReadOnlySites.Count)" -ForegroundColor Green

    # Display results
    if ($ReadOnlySites.Count -gt 0) {
        Write-Host ""
        Write-Host "ReadOnly Sites Summary:" -ForegroundColor Cyan
        Write-Host "========================" -ForegroundColor Cyan
        
        $ReadOnlySites | Sort-Object Type, Url | Format-Table -Property Type, Url, Title, ReadOnly, LockIssue -AutoSize
        
        # Export to CSV if path specified
        if ($ExportPath) {
            Write-Host "Exporting results to: $ExportPath" -ForegroundColor Yellow
            $ReadOnlySites | Sort-Object Type, Url | Export-Csv -Path $ExportPath -NoTypeInformation -Force
            Write-Host "Export completed successfully." -ForegroundColor Green
        }
    } else {
        Write-Host "No ReadOnly sites found in the farm." -ForegroundColor Green
    }

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Error Details: $($_.Exception.ToString())" -ForegroundColor Red
}
finally {
    # Cleanup and final summary
    $ScriptEndTime = Get-Date
    $Duration = $ScriptEndTime - $ScriptStartTime
    
    Write-Host ""
    Write-Host "Script Execution Summary:" -ForegroundColor Cyan
    Write-Host "Start Time: $ScriptStartTime" -ForegroundColor Gray
    Write-Host "End Time: $ScriptEndTime" -ForegroundColor Gray
    Write-Host "Duration: $($Duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    Write-Host "Web Applications Processed: $($WebAppSummary.Count)" -ForegroundColor Gray
    Write-Host "ReadOnly Sites Found: $($ReadOnlySites.Count)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Script completed." -ForegroundColor Green
}