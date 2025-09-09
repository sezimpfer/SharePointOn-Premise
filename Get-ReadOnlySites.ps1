<#
.SYNOPSIS
    Gets all SharePoint sites that are set to ReadOnly in SharePoint Server 2016.

.DESCRIPTION
    This script retrieves all site collections and webs in the SharePoint 2016 farm
    that have ReadOnly status enabled. It provides detailed information about each
    ReadOnly site including URL, title, and lock status. The script also provides
    comprehensive summaries for each web application showing ReadOnly, No Access,
    and Not Locked site counts with percentages.

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
$WebAppSummary = @()
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
        
        # Initialize counters for this web application
        $ReadOnlyCount = 0
        $NoAccessCount = 0
        $NotLockedCount = 0
        $TotalSitesCount = 0
        
        # Get all site collections in the web application
        $SiteCollections = Get-SPSite -WebApplication $WebApp -Limit All -ErrorAction Continue
        Write-Host "  Found $($SiteCollections.Count) site collection(s)" -ForegroundColor Gray

        # Check each site collection
        foreach ($SiteCollection in $SiteCollections) {
            try {
                $TotalSitesCount++
                
                # Check if site collection is ReadOnly
                if ($SiteCollection.ReadOnly -eq $true) {
                    Write-Host "  Found ReadOnly Site Collection: $($SiteCollection.Url)" -ForegroundColor Red
                    $ReadOnlyCount++
                    
                    $SiteInfo = New-Object PSObject -Property @{
                        Type = "Site Collection"
                        Url = $SiteCollection.Url
                        Title = $SiteCollection.RootWeb.Title
                        ReadOnly = $SiteCollection.ReadOnly
                        LockIssue = $SiteCollection.LockIssue
                        Owner = $SiteCollection.Owner.LoginName
                        LastModified = $SiteCollection.LastContentModifiedDate
                        WebApplication = $WebApp.Url
                        Status = "ReadOnly"
                    }
                    $ReadOnlySites += $SiteInfo
                } else {
                    # Site collection is not ReadOnly
                    $NotLockedCount++
                }

                # Check all webs within the site collection
                try {
                    $Webs = Get-SPWeb -Site $SiteCollection -Limit All -ErrorAction Stop
                    foreach ($Web in $Webs) {
                        try {
                            $TotalSitesCount++
                            
                            # Check if web is ReadOnly
                            if ($Web.ReadOnlyUI -eq $true -or $Web.AllowUnsafeUpdates -eq $false) {
                                Write-Host "    Found ReadOnly Web: $($Web.Url)" -ForegroundColor Yellow
                                $ReadOnlyCount++
                                
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
                                    Status = "ReadOnly"
                                }
                                $ReadOnlySites += $WebInfo
                            } else {
                                # Web is not ReadOnly
                                $NotLockedCount++
                            }
                        }
                        catch {
                            Write-Warning "Error processing web $($Web.Url): $($_.Exception.Message)"
                            $NoAccessCount++
                        }
                        finally {
                            # Dispose web object to free memory
                            if ($Web -ne $null) { $Web.Dispose() }
                        }
                    }
                }
                catch {
                    Write-Warning "Access denied getting webs for site collection $($SiteCollection.Url): $($_.Exception.Message)"
                    $NoAccessCount++
                }
            }
            catch {
                Write-Warning "Error processing site collection $($SiteCollection.Url): $($_.Exception.Message)"
                $NoAccessCount++
            }
            finally {
                # Dispose site collection object to free memory
                if ($SiteCollection -ne $null) { $SiteCollection.Dispose() }
            }
        }
        
        # Create summary for this web application
        $WebAppSummaryItem = New-Object PSObject -Property @{
            WebApplication = $WebApp.Url
            TotalSites = $TotalSitesCount
            ReadOnlySites = $ReadOnlyCount
            NoAccessSites = $NoAccessCount
            NotLockedSites = $NotLockedCount
            ReadOnlyPercentage = if($TotalSitesCount -gt 0) { [math]::Round(($ReadOnlyCount / $TotalSitesCount) * 100, 2) } else { 0 }
            NoAccessPercentage = if($TotalSitesCount -gt 0) { [math]::Round(($NoAccessCount / $TotalSitesCount) * 100, 2) } else { 0 }
        }
        $WebAppSummary += $WebAppSummaryItem
        
        # Display summary for this web application
        Write-Host ""
        Write-Host "  Web Application Summary:" -ForegroundColor Green
        Write-Host "  ========================" -ForegroundColor Green
        Write-Host "  Total Sites: $TotalSitesCount" -ForegroundColor White
        Write-Host "  ReadOnly Sites: $ReadOnlyCount ($($WebAppSummaryItem.ReadOnlyPercentage)%)" -ForegroundColor Red
        Write-Host "  No Access Sites: $NoAccessCount ($($WebAppSummaryItem.NoAccessPercentage)%)" -ForegroundColor Yellow
        Write-Host "  Not Locked Sites: $NotLockedCount" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host ""
    Write-Host "ReadOnly Sites Discovery Complete!" -ForegroundColor Green
    Write-Host "Total ReadOnly sites found: $($ReadOnlySites.Count)" -ForegroundColor Green

    # Display Web Application Summary
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "          WEB APPLICATION SUMMARY" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    
    if ($WebAppSummary.Count -gt 0) {
        $WebAppSummary | Format-Table -Property @{
            Label="Web Application"; Expression={$_.WebApplication}; Width=40
        }, @{
            Label="Total Sites"; Expression={$_.TotalSites}; Width=12
        }, @{
            Label="ReadOnly"; Expression={"$($_.ReadOnlySites) ($($_.ReadOnlyPercentage)%)"}; Width=18
        }, @{
            Label="No Access"; Expression={"$($_.NoAccessSites) ($($_.NoAccessPercentage)%)"}; Width=18
        }, @{
            Label="Not Locked"; Expression={$_.NotLockedSites}; Width=12
        } -AutoSize
        
        # Calculate farm totals
        $TotalFarmSites = ($WebAppSummary | Measure-Object -Property TotalSites -Sum).Sum
        $TotalReadOnlyFarm = ($WebAppSummary | Measure-Object -Property ReadOnlySites -Sum).Sum
        $TotalNoAccessFarm = ($WebAppSummary | Measure-Object -Property NoAccessSites -Sum).Sum
        $TotalNotLockedFarm = ($WebAppSummary | Measure-Object -Property NotLockedSites -Sum).Sum
        
        Write-Host ""
        Write-Host "FARM TOTALS:" -ForegroundColor Magenta
        Write-Host "============" -ForegroundColor Magenta
        Write-Host "Total Sites in Farm: $TotalFarmSites" -ForegroundColor White
        Write-Host "ReadOnly Sites: $TotalReadOnlyFarm ($([math]::Round(($TotalReadOnlyFarm / $TotalFarmSites) * 100, 2))%)" -ForegroundColor Red
        Write-Host "No Access Sites: $TotalNoAccessFarm ($([math]::Round(($TotalNoAccessFarm / $TotalFarmSites) * 100, 2))%)" -ForegroundColor Yellow
        Write-Host "Not Locked Sites: $TotalNotLockedFarm ($([math]::Round(($TotalNotLockedFarm / $TotalFarmSites) * 100, 2))%)" -ForegroundColor Green
    }

    # Display detailed results for ReadOnly sites
    if ($ReadOnlySites.Count -gt 0) {
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Cyan
        Write-Host "        DETAILED READONLY SITES" -ForegroundColor Cyan
        Write-Host "===============================================" -ForegroundColor Cyan
        
        $ReadOnlySites | Sort-Object Type, Url | Format-Table -Property Type, Url, Title, ReadOnly, LockIssue -AutoSize
        
        # Export to CSV if path specified
        if ($ExportPath) {
            Write-Host "Exporting results to: $ExportPath" -ForegroundColor Yellow
            
            # Export ReadOnly sites details
            $ReadOnlySites | Sort-Object Type, Url | Export-Csv -Path $ExportPath -NoTypeInformation -Force
            
            # Export Web Application Summary to separate CSV
            $SummaryPath = $ExportPath.Replace(".csv", "_Summary.csv")
            $WebAppSummary | Export-Csv -Path $SummaryPath -NoTypeInformation -Force
            
            Write-Host "ReadOnly sites exported to: $ExportPath" -ForegroundColor Green
            Write-Host "Summary exported to: $SummaryPath" -ForegroundColor Green
        }
    } else {
        Write-Host ""
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