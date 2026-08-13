[CmdletBinding(DefaultParameterSetName='File')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='File')][string]$StencilPath,
    [Parameter(Mandatory=$true, ParameterSetName='BuiltIn')]
    [ValidateSet('Backgrounds','Borders','Containers','Callouts','Legends')]
    [string]$BuiltIn,
    [string]$Pattern = '*',
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$application = $null
$stencil = $null
try {
    $application = New-Object -ComObject Visio.Application
    $application.Visible = $false
    $application.AlertResponse = 7
    if ($PSCmdlet.ParameterSetName -eq 'BuiltIn') {
        $types = @{ Backgrounds = 0; Borders = 1; Containers = 2; Callouts = 3; Legends = 4 }
        $StencilPath = [string]$application.GetBuiltInStencilFile($types[$BuiltIn], 0)
    }
    $StencilPath = [IO.Path]::GetFullPath($StencilPath)
    if (-not (Test-Path -LiteralPath $StencilPath)) { throw "Stencil not found: $StencilPath" }
    # Read-only, hidden, excluded from MRU, and macros disabled.
    $stencil = $application.Documents.OpenEx($StencilPath, 202)
    $masters = @()
    foreach ($master in @($stencil.Masters)) {
        if ([string]$master.NameU -like $Pattern -or [string]$master.Name -like $Pattern) {
            $masters += [ordered]@{
                name = [string]$master.Name
                name_u = [string]$master.NameU
                id = [int]$master.ID
                base_id = [string]$master.BaseID
                unique_id = [string]$master.UniqueID
            }
        }
    }
    $report = [ordered]@{
        status = 'passed'
        stencil = $StencilPath
        pattern = $Pattern
        count = $masters.Count
        masters = $masters
    }
    $json = $report | ConvertTo-Json -Depth 6
    if ($ReportPath) {
        $ReportPath = [IO.Path]::GetFullPath($ReportPath)
        [IO.File]::WriteAllText($ReportPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
    $json
}
finally {
    if ($null -ne $stencil) { try { $stencil.Close() } catch {} }
    if ($null -ne $application) {
        try { $application.Quit() } catch {}
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
    }
}
