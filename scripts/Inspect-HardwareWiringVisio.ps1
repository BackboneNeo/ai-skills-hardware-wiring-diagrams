[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$VsdxPath,
    [string]$SpecPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$VsdxPath = [IO.Path]::GetFullPath($VsdxPath)
$application = $null
$document = $null
try {
    $application = New-Object -ComObject Visio.Application
    $application.Visible = $false
    $application.AlertResponse = 7
    $document = $application.Documents.Open($VsdxPath)
    $page = $document.Pages.Item(1)
    $native2D = 0
    $connectors = 0
    $glued = 0
    $unglued = @()
    $terminalIds = @()
    $netIds = @()
    $pageSizedRaster = @()
    $pageArea = $page.PageSheet.CellsU('PageWidth').ResultIU * $page.PageSheet.CellsU('PageHeight').ResultIU
    foreach ($shape in @($page.Shapes)) {
        if ($shape.OneD -ne 0) {
            $connectors++
            $begin = [string]$shape.CellsU('BeginX').FormulaU
            $end = [string]$shape.CellsU('EndX').FormulaU
            if ($begin -match 'Sheet\.' -and $end -match 'Sheet\.') { $glued++ } else { $unglued += $shape.ID }
            if ($shape.CellExistsU('Prop.NetId', 0) -ne 0) { $netIds += [string]$shape.CellsU('Prop.NetId').ResultStr('') }
        }
        else {
            $native2D++
            if ($shape.CellExistsU('Prop.TerminalId', 0) -ne 0) { $terminalIds += [string]$shape.CellsU('Prop.TerminalId').ResultStr('') }
            try {
                if ($shape.ForeignType -ne 0) {
                    $area = $shape.CellsU('Width').ResultIU * $shape.CellsU('Height').ResultIU
                    if ($pageArea -gt 0 -and ($area / $pageArea) -gt 0.75) { $pageSizedRaster += $shape.ID }
                }
            } catch {}
        }
    }
    $errors = @()
    if ($connectors -eq 0) { $errors += 'no native 1-D connectors' }
    if ($glued -ne $connectors) { $errors += 'one or more connector endpoints are not glued' }
    if ($terminalIds.Count -eq 0) { $errors += 'no native terminal shapes with Prop.TerminalId' }
    if ($pageSizedRaster.Count -gt 0) { $errors += 'page-sized raster image detected' }
    if ($SpecPath) {
        $SpecPath = [IO.Path]::GetFullPath($SpecPath)
        $spec = Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedTerminals = @($spec.terminals | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
        $actualTerminals = @($terminalIds | Sort-Object -Unique)
        $expectedNets = @($spec.routes | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
        $actualNets = @($netIds | Sort-Object -Unique)
        $expectedSegments = 0
        foreach ($route in @($spec.routes)) { $expectedSegments += @($route.waypoints).Count + 1 }
        if (@(Compare-Object $expectedTerminals $actualTerminals).Count -ne 0) { $errors += 'terminal IDs do not match the Visio specification' }
        if (@(Compare-Object $expectedNets $actualNets).Count -ne 0) { $errors += 'net IDs do not match the Visio specification' }
        if ($connectors -ne $expectedSegments) { $errors += "native connector count $connectors does not match expected segment count $expectedSegments" }
    }
    $report = [ordered]@{
        status = $(if ($errors.Count -eq 0) { 'passed' } else { 'failed' })
        vsdx = $VsdxPath
        page = [string]$page.Name
        native_2d_shapes = $native2D
        native_connectors = $connectors
        glued_connectors = $glued
        terminal_ids = @($terminalIds | Sort-Object -Unique)
        net_ids = @($netIds | Sort-Object -Unique)
        unglued_shape_ids = $unglued
        page_sized_raster_shape_ids = $pageSizedRaster
        errors = $errors
    }
    $json = $report | ConvertTo-Json -Depth 6
    if ($ReportPath) {
        $ReportPath = [IO.Path]::GetFullPath($ReportPath)
        [IO.File]::WriteAllText($ReportPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
    $json
    if ($errors.Count -gt 0) { exit 1 }
}
finally {
    if ($null -ne $document) { try { $document.Close() } catch {} }
    if ($null -ne $application) {
        try { $application.Quit() } catch {}
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
    }
}
