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
    $visibleConnectors = 0
    $connectionShapeIds = @()
    $dynamicConnectorIds = @()
    $dynamicConnectorSettings = @()
    $componentImageIds = @()
    $pageArea = $page.PageSheet.CellsU('PageWidth').ResultIU * $page.PageSheet.CellsU('PageHeight').ResultIU
    foreach ($shape in @($page.Shapes)) {
        if ($shape.OneD -ne 0) {
            $connectors++
            if ([int]$shape.CellsU('LinePattern').ResultIU -ne 0) { $visibleConnectors++ }
            $begin = [string]$shape.CellsU('BeginX').FormulaU
            $end = [string]$shape.CellsU('EndX').FormulaU
            if ($begin -match 'Sheet\.' -and $end -match 'Sheet\.') { $glued++ } else { $unglued += $shape.ID }
            if ($shape.CellExistsU('Prop.NetId', 0) -ne 0) { $netIds += [string]$shape.CellsU('Prop.NetId').ResultStr('') }
            if ($shape.CellExistsU('Prop.ConnectionId', 0) -ne 0) { $connectionShapeIds += [string]$shape.CellsU('Prop.ConnectionId').ResultStr('') }
            try {
                if ($null -ne $shape.Master -and [string]$shape.Master.NameU -eq 'Dynamic connector' -and $shape.CellExistsU('Prop.ConnectionId', 0) -ne 0) {
                    $dynamicId = [string]$shape.CellsU('Prop.ConnectionId').ResultStr('')
                    $dynamicConnectorIds += $dynamicId
                    $dynamicConnectorSettings += [ordered]@{
                        id = $dynamicId
                        master = [string]$shape.Master.NameU
                        one_d = [int]$shape.OneD
                        object_type = [int]$shape.CellsU('ObjType').ResultIU
                        glue_type = [int]$shape.CellsU('GlueType').ResultIU
                        connector_style = [int]$shape.CellsU('ConLineRouteExt').ResultIU
                        route_style = [int]$shape.CellsU('ShapeRouteStyle').ResultIU
                        reroute_policy = [int]$shape.CellsU('ConFixedCode').ResultIU
                        geometry_rows = [int]$shape.RowCount(10)
                    }
                }
            } catch {}
        }
        else {
            $native2D++
            if ($shape.CellExistsU('Prop.TerminalId', 0) -ne 0) { $terminalIds += [string]$shape.CellsU('Prop.TerminalId').ResultStr('') }
            if ($shape.CellExistsU('Prop.Role', 0) -ne 0 -and [string]$shape.CellsU('Prop.Role').ResultStr('') -eq 'component-image' -and $shape.CellExistsU('Prop.DiagramId', 0) -ne 0) {
                $componentImageIds += [string]$shape.CellsU('Prop.DiagramId').ResultStr('')
            }
            try {
                if ($shape.ForeignType -eq 1 -or $shape.ForeignType -eq 4) {
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
        foreach ($route in @($spec.routes)) {
            $routeRenderMode = if ($route.PSObject.Properties.Name -contains 'render_mode') { [string]$route.render_mode } elseif ($spec.page.PSObject.Properties.Name -contains 'route_render_mode') { [string]$spec.page.route_render_mode } else { 'segmented' }
            if ($routeRenderMode -eq 'single_polyline' -or $routeRenderMode -eq 'dynamic_connector') { $expectedSegments += 1 }
            else { $expectedSegments += @($route.waypoints).Count + 1 }
        }
        if (@(Compare-Object $expectedTerminals $actualTerminals).Count -ne 0) { $errors += 'terminal IDs do not match the Visio specification' }
        if (@(Compare-Object $expectedNets $actualNets).Count -ne 0) { $errors += 'net IDs do not match the Visio specification' }
        if ($connectors -ne $expectedSegments) { $errors += "native connector count $connectors does not match expected segment count $expectedSegments" }
        if ($spec.page.PSObject.Properties.Name -contains 'route_render_mode' -and [string]$spec.page.route_render_mode -eq 'dynamic_connector') {
            if (@($dynamicConnectorIds | Sort-Object -Unique).Count -ne $expectedNets.Count) { $errors += 'one or more electrical nets are not built from the Dynamic connector master' }
            if (@(Compare-Object $expectedNets @($connectionShapeIds | Sort-Object -Unique)).Count -ne 0) { $errors += 'independently selectable connection IDs do not match the Visio specification' }
            if ($visibleConnectors -ne $expectedNets.Count) { $errors += 'one or more Dynamic Connectors are not visible' }
            foreach ($setting in @($dynamicConnectorSettings)) {
                if ($setting.one_d -ne -1 -or $setting.object_type -ne 2 -or $setting.glue_type -ne 2 -or $setting.reroute_policy -ne 2 -or $setting.geometry_rows -lt 3) {
                    $errors += "Dynamic Connector $($setting.id) has invalid native connector settings"
                }
            }
        }
        $expectedImages = if ($null -ne $spec.images) { @($spec.images | ForEach-Object { [string]$_.id } | Sort-Object -Unique) } else { @() }
        $actualImages = @($componentImageIds | Sort-Object -Unique)
        if (@(Compare-Object @($expectedImages) @($actualImages)).Count -ne 0) { $errors += 'component image IDs do not match the Visio specification' }
    }
    $report = [ordered]@{
        status = $(if ($errors.Count -eq 0) { 'passed' } else { 'failed' })
        vsdx = $VsdxPath
        page = [string]$page.Name
        native_2d_shapes = $native2D
        native_connectors = $connectors
        glued_connectors = $glued
        visible_connectors = $visibleConnectors
        independently_selectable_connection_ids = @($connectionShapeIds | Sort-Object -Unique)
        dynamic_connector_master_ids = @($dynamicConnectorIds | Sort-Object -Unique)
        dynamic_connector_settings = $dynamicConnectorSettings
        component_image_ids = @($componentImageIds | Sort-Object -Unique)
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
