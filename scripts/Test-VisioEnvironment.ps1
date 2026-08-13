[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$application = $null
try {
    $application = New-Object -ComObject Visio.Application
    $application.Visible = $false
    $executable = Join-Path ([string]$application.Path) 'VISIO.EXE'
    [pscustomobject]@{
        Status = 'passed'
        Version = [string]$application.Version
        Executable = $(if (Test-Path -LiteralPath $executable) { $executable } else { [string]$application.Path })
        ConnectorToolAvailable = ($null -ne $application.ConnectorToolDataObject)
    } | ConvertTo-Json -Depth 3
    exit 0
}
catch {
    [pscustomobject]@{
        Status = 'failed'
        Error = $_.Exception.Message
    } | ConvertTo-Json -Depth 3
    exit 1
}
finally {
    if ($null -ne $application) {
        try { $application.Quit() } catch {}
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
    }
}
