<#
.SYNOPSIS
    Gets all SharePoint site collections that are set to ReadOnly in SharePoint Server 2016.

.DESCRIPTION
    This script retrieves all site collections in the SharePoint 2016 farm that have ReadOnly status 
    enabled. It provides detailed information about each ReadOnly site collection including URL, title, 
    and lock status. The script also provides comprehensive summaries for each web application showing 
    ReadOnly, No Access, and Not Locked site collection counts with percentages.
    
    The script focuses exclusively on site collections and does not process subsites to avoid 
    permission issues and improve performance.

.PARAMETER WebApplicationUrl
    Optional. Specify a specific web application URL to limit the scope.
    If not provided, the script will check all web applications in the farm.

.PARAMETER ExportPath
    Optional. Specify a path to export the results to a CSV file.
    When specified, two files will be created:
    - Main file: Detailed ReadOnly site collections
    - Summary file: Web application summary statistics

.EXAMPLE
    .\Get-ReadOnlySiteCollections-Final.ps1
    Gets all ReadOnly site collections from all web applications in the farm.

.EXAMPLE
    .\Get-ReadOnlySiteCollections-Final.ps1 -WebApplicationUrl "http://sharepoint.contoso.com"
    Gets ReadOnly site collections from a specific web application.

.EXAMPLE
    .\Get-ReadOnlySiteCollections-Final.ps1 -ExportPath "C:\Reports\ReadOnlySites.csv"
    Gets all ReadOnly site collections and exports results to CSV files.

.NOTES
    SharePoint Version: SharePoint Server 2016
    Requires: SharePoint PowerShell snap-in
    Run as: Farm Administrator or SharePoint Service Account
    
    Author: SharePoint Administrator
    Created: Based on 10 Rules for SharePoint PowerShell Scripts
    
.LINK
    https://docs.microsoft.com/en-us/powershell/module/sharepoint-server/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Specify a web application URL to limit scope")]
    [ValidateNotNullOrEmpty()]
    [string]$WebApplicationUrl,
    
    [Parameter(Mandatory=$false, HelpMessage="Specify path to export results to CSV")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath
)

# Initialize script variables
$ErrorActionPreference = "Stop"
$ReadOnlySiteCollections = @()
$WebAppSummary = @()
$ScriptStartTime = Get-Date

try {
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "  SharePoint ReadOnly Site Collections Script" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "Target Environment: SharePoint Server 2016" -ForegroundColor Yellow
    Write-Host "Script Start Time: $ScriptStartTime" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""

    # Check and load SharePoint PowerShell snap-in
    Write-Host "Initializing SharePoint PowerShell environment..." -ForegroundColor Yellow
    if ((Get-PSSnapin -Name "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
        Write-Host "Loading SharePoint PowerShell snap-in..." -ForegroundColor Yellow
        Add-PSSnapin "Microsoft.SharePoint.PowerShell"
        Write-Host "SharePoint PowerShell snap-in loaded successfully." -ForegroundColor Green
    } else {
        Write-Host "SharePoint PowerShell snap-in already loaded." -ForegroundColor Green
    }

    # Verify SharePoint farm connectivity
    Write-Host "Verifying SharePoint farm connectivity..." -ForegroundColor Yellow
    $Farm = Get-SPFarm -ErrorAction Stop
    if ($Farm -eq $null) {
        throw "Unable to connect to SharePoint farm. Please verify you're running this script on a SharePoint server with appropriate permissions."
    }
    Write-Host "Successfully connected to SharePoint farm: $($Farm.Name)" -ForegroundColor Green
    Write-Host "Farm Build Version: $($Farm.BuildVersion)" -ForegroundColor Gray
    Write-Host ""

    # Determine web applications to process based on parameters
    if ($WebApplicationUrl) {
        Write-Host "Processing specific web application: $WebApplicationUrl" -ForegroundColor Yellow
        $WebApplications = @(Get-SPWebApplication -Identity $WebApplicationUrl -ErrorAction Stop)
        Write-Host "Target web application validated successfully." -ForegroundColor Green
    } else {
        Write-Host "Discovering all web applications in the farm..." -ForegroundColor Yellow
        $WebApplications = @(Get-SPWebApplication -ErrorAction Stop)
        Write-Host "Found $($WebApplications.Count) web application(s) in the farm." -ForegroundColor Green
    }

    if ($WebApplications.Count -eq 0) {
        throw "No web applications found to process."
    }

    Write-Host ""
    Write-Host "Beginning site collection analysis..." -ForegroundColor Cyan
    Write-Host ""

    # Process each web application
    foreach ($WebApp in $WebApplications) {
        Write-Host "Processing Web Application: $($WebApp.Url)" -ForegroundColor Cyan
        Write-Host "Display Name: $($WebApp.DisplayName)" -ForegroundColor Gray
        
        # Initialize counters for current web application
        $ReadOnlyCount = 0
        $NoAccessCount = 0
        $NotLockedCount = 0
        $TotalSiteCollectionsCount = 0
        
        # Get all site collections in the current web application
        Write-Host "Retrieving site collections..." -ForegroundColor Yellow
        $SiteCollections = @(Get-SPSite -WebApplication $WebApp -Limit All -ErrorAction Continue)
        Write-Host "Found $($SiteCollections.Count) site collection(s) to analyze." -ForegroundColor Gray

        # Process each site collection
        foreach ($SiteCollection in $SiteCollections) {
            try {
                $TotalSiteCollectionsCount++
                
                # Check ReadOnly status of the site collection
                if ($SiteCollection.ReadOnly -eq $true) {
                    Write-Host "  [READONLY] Site Collection: $($SiteCollection.Url)" -ForegroundColor Red
                    $ReadOnlyCount++
                    
                    # Create detailed site collection information object
                    $SiteCollectionInfo = New-Object PSObject -Property @{
                        Type = "Site Collection"
                        Url = $SiteCollection.Url
                        Title = $SiteCollection.RootWeb.Title
                        ReadOnly = $SiteCollection.ReadOnly
                        LockIssue = $SiteCollection.LockIssue
                        Owner = if($SiteCollection.Owner) { $SiteCollection.Owner.LoginName } else { "Not Available" }
                        SecondaryOwner = if($SiteCollection.SecondaryContact) { $SiteCollection.SecondaryContact.LoginName } else { "Not Available" }
                        LastContentModified = $SiteCollection.LastContentModifiedDate
                        ContentDatabase = $SiteCollection.ContentDatabase.Name
                        SizeInMB = [math]::Round($SiteCollection.Usage.Storage / 1MB, 2)
                        WebApplication = $WebApp.Url
                        WebApplicationName = $WebApp.DisplayName
                        Status = "ReadOnly"
                    }
                    $ReadOnlySiteCollections += $SiteCollectionInfo
                } else {
                    # Site collection is accessible and not ReadOnly
                    $NotLockedCount++
                    Write-Host "  [OK] Site Collection: $($SiteCollection.Url)" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Access denied or error processing site collection $($SiteCollection.Url): $($_.Exception.Message)"
                $NoAccessCount++
            }
            finally {
                # Proper disposal of site collection object to prevent memory leaks
                if ($SiteCollection -ne $null) { 
                    $SiteCollection.Dispose() 
                }
            }
        }
        
        # Create summary statistics for current web application
        $WebAppSummaryItem = New-Object PSObject -Property @{
            WebApplication = $WebApp.Url
            WebApplicationName = $WebApp.DisplayName
            TotalSiteCollections = $TotalSiteCollectionsCount
            ReadOnlySiteCollections = $ReadOnlyCount
            NoAccessSiteCollections = $NoAccessCount
            NotLockedSiteCollections = $NotLockedCount
            ReadOnlyPercentage = if($TotalSiteCollectionsCount -gt 0) { [math]::Round(($ReadOnlyCount / $TotalSiteCollectionsCount) * 100, 2) } else { 0 }
            NoAccessPercentage = if($TotalSiteCollectionsCount -gt 0) { [math]::Round(($NoAccessCount / $TotalSiteCollectionsCount) * 100, 2) } else { 0 }
            NotLockedPercentage = if($TotalSiteCollectionsCount -gt 0) { [math]::Round(($NotLockedCount / $TotalSiteCollectionsCount) * 100, 2) } else { 0 }
        }
        $WebAppSummary += $WebAppSummaryItem
        
        # Display real-time summary for current web application
        Write-Host ""
        Write-Host "  Web Application Analysis Complete:" -ForegroundColor Green
        Write-Host "  ====================================" -ForegroundColor Green
        Write-Host "  Total Site Collections: $TotalSiteCollectionsCount" -ForegroundColor White
        Write-Host "  ReadOnly Site Collections: $ReadOnlyCount ($($WebAppSummaryItem.ReadOnlyPercentage)%)" -ForegroundColor Red
        Write-Host "  No Access Site Collections: $NoAccessCount ($($WebAppSummaryItem.NoAccessPercentage)%)" -ForegroundColor Yellow
        Write-Host "  Not Locked Site Collections: $NotLockedCount ($($WebAppSummaryItem.NotLockedPercentage)%)" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "Site Collection Analysis Complete!" -ForegroundColor Green
    Write-Host "Total ReadOnly site collections found: $($ReadOnlySiteCollections.Count)" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green

    # Display comprehensive web application summary
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "           WEB APPLICATION SUMMARY" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    
    if ($WebAppSummary.Count -gt 0) {
        $WebAppSummary | Format-Table -Property @{
            Label="Web Application"; Expression={$_.WebApplicationName}; Width=35
        }, @{
            Label="Total Site Collections"; Expression={$_.TotalSiteCollections}; Width=22
        }, @{
            Label="ReadOnly"; Expression={"$($_.ReadOnlySiteCollections) ($($_.ReadOnlyPercentage)%)"}; Width=18
        }, @{
            Label="No Access"; Expression={"$($_.NoAccessSiteCollections) ($($_.NoAccessPercentage)%)"}; Width=18
        }, @{
            Label="Not Locked"; Expression={"$($_.NotLockedSiteCollections) ($($_.NotLockedPercentage)%)"}; Width=15
        } -AutoSize
        
        # Calculate and display farm-level totals
        $TotalFarmSiteCollections = ($WebAppSummary | Measure-Object -Property TotalSiteCollections -Sum).Sum
        $TotalReadOnlyFarm = ($WebAppSummary | Measure-Object -Property ReadOnlySiteCollections -Sum).Sum
        $TotalNoAccessFarm = ($WebAppSummary | Measure-Object -Property NoAccessSiteCollections -Sum).Sum
        $TotalNotLockedFarm = ($WebAppSummary | Measure-Object -Property NotLockedSiteCollections -Sum).Sum
        
        Write-Host ""
        Write-Host "SHAREPOINT FARM TOTALS:" -ForegroundColor Magenta
        Write-Host "========================" -ForegroundColor Magenta
        Write-Host "Total Site Collections in Farm: $TotalFarmSiteCollections" -ForegroundColor White
        Write-Host "ReadOnly Site Collections: $TotalReadOnlyFarm ($([math]::Round(($TotalReadOnlyFarm / $TotalFarmSiteCollections) * 100, 2))%)" -ForegroundColor Red
        Write-Host "No Access Site Collections: $TotalNoAccessFarm ($([math]::Round(($TotalNoAccessFarm / $TotalFarmSiteCollections) * 100, 2))%)" -ForegroundColor Yellow
        Write-Host "Not Locked Site Collections: $TotalNotLockedFarm ($([math]::Round(($TotalNotLockedFarm / $TotalFarmSiteCollections) * 100, 2))%)" -ForegroundColor Green
    }

    # Display detailed ReadOnly site collection information
    if ($ReadOnlySiteCollections.Count -gt 0) {
        Write-Host ""
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "       DETAILED READONLY SITE COLLECTIONS" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        $ReadOnlySiteCollections | Sort-Object WebApplicationName, Url | Format-Table -Property @{
            Label="Site Collection URL"; Expression={$_.Url}; Width=50
        }, @{
            Label="Title"; Expression={$_.Title}; Width=30
        }, @{
            Label="Owner"; Expression={$_.Owner}; Width=25
        }, @{
            Label="Lock Issue"; Expression={$_.LockIssue}; Width=15
        }, @{
            Label="Size (MB)"; Expression={$_.SizeInMB}; Width=10
        } -AutoSize
        
        # Export functionality
        if ($ExportPath) {
            Write-Host ""
            Write-Host "Exporting results to specified location..." -ForegroundColor Yellow
            
            try {
                # Ensure export directory exists
                $ExportDirectory = Split-Path -Path $ExportPath -Parent
                if ($ExportDirectory -and -not (Test-Path -Path $ExportDirectory)) {
                    New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
                }
                
                # Export detailed ReadOnly site collections
                $ReadOnlySiteCollections | Sort-Object WebApplicationName, Url | Export-Csv -Path $ExportPath -NoTypeInformation -Force
                
                # Export web application summary to companion file
                $SummaryPath = $ExportPath.Replace(".csv", "_Summary.csv")
                $WebAppSummary | Export-Csv -Path $SummaryPath -NoTypeInformation -Force
                
                Write-Host "ReadOnly site collections exported to: $ExportPath" -ForegroundColor Green
                Write-Host "Web application summary exported to: $SummaryPath" -ForegroundColor Green
                
                # Display file information
                $DetailFile = Get-Item -Path $ExportPath
                $SummaryFile = Get-Item -Path $SummaryPath
                Write-Host "Detail file size: $([math]::Round($DetailFile.Length / 1KB, 2)) KB" -ForegroundColor Gray
                Write-Host "Summary file size: $([math]::Round($SummaryFile.Length / 1KB, 2)) KB" -ForegroundColor Gray
            }
            catch {
                Write-Warning "Export failed: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host ""
        Write-Host "No ReadOnly site collections found in the specified scope." -ForegroundColor Green
        Write-Host "All site collections are accessible and unlocked." -ForegroundColor Green
    }

}
catch {
    Write-Error "Script execution failed with error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Error Details:" -ForegroundColor Red
    Write-Host "==============" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting Tips:" -ForegroundColor Yellow
    Write-Host "- Ensure you're running as Farm Administrator or SharePoint Service Account" -ForegroundColor Yellow
    Write-Host "- Verify the SharePoint PowerShell snap-in is available" -ForegroundColor Yellow
    Write-Host "- Check that you're running on a SharePoint server" -ForegroundColor Yellow
    Write-Host "- Validate web application URLs if using -WebApplicationUrl parameter" -ForegroundColor Yellow
}
finally {
    # Script completion summary and cleanup
    $ScriptEndTime = Get-Date
    $ScriptDuration = $ScriptEndTime - $ScriptStartTime
    
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "            SCRIPT EXECUTION SUMMARY" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "Script Start Time: $ScriptStartTime" -ForegroundColor Gray
    Write-Host "Script End Time: $ScriptEndTime" -ForegroundColor Gray
    Write-Host "Total Execution Duration: $($ScriptDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    Write-Host "Web Applications Processed: $($WebAppSummary.Count)" -ForegroundColor Gray
    Write-Host "ReadOnly Site Collections Found: $($ReadOnlySiteCollections.Count)" -ForegroundColor Gray
    
    if ($ExportPath -and $ReadOnlySiteCollections.Count -gt 0) {
        Write-Host "Export Files Created: 2 (Detail + Summary)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Script execution completed successfully." -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green
}