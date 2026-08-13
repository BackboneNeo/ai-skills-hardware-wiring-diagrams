[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SpecPath,
    [Parameter(Mandatory=$true)][string]$NetlistPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$PreviewPng,
    [string]$PreviewPdf,
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
$SpecPath = [IO.Path]::GetFullPath($SpecPath)
$NetlistPath = [IO.Path]::GetFullPath($NetlistPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($PreviewPng) { $PreviewPng = [IO.Path]::GetFullPath($PreviewPng) }
if ($PreviewPdf) { $PreviewPdf = [IO.Path]::GetFullPath($PreviewPdf) }
if ([IO.Path]::GetExtension($OutputPath).ToLowerInvariant() -ne '.vsdx') { throw 'OutputPath must use the .vsdx extension.' }

function Convert-HexToRgbFormula([string]$Color) {
    if ($Color -notmatch '^#?([0-9A-Fa-f]{6})$') { throw "Invalid color: $Color" }
    $hex = $Matches[1]
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)
    return "RGB($r,$g,$b)"
}

function Set-ShapeData($Shape, [string]$Name, [string]$Value) {
    $cellName = "Prop.$Name"
    if ($Shape.SectionExists(243, 0) -eq 0) { [void]$Shape.AddSection(243) }
    if ($Shape.CellExistsU($cellName, 0) -eq 0) { [void]$Shape.AddNamedRow(243, $Name, 0) }
    $escaped = $Value.Replace('"','""')
    $Shape.CellsU($cellName).FormulaU = '="' + $escaped + '"'
}

function Set-CommonStyle($Shape, [string]$Fill, [string]$Line, [string]$TextColor, [double]$FontSize, [bool]$Bold) {
    $Shape.CellsU('FillForegnd').FormulaU = Convert-HexToRgbFormula $Fill
    $Shape.CellsU('FillPattern').FormulaU = '1'
    $Shape.CellsU('LineColor').FormulaU = Convert-HexToRgbFormula $Line
    $Shape.CellsU('LineWeight').FormulaU = '0.8 pt'
    $Shape.CellsU('Char.Color').FormulaU = Convert-HexToRgbFormula $TextColor
    $Shape.CellsU('Char.Size').FormulaU = "$FontSize pt"
    $Shape.CellsU('Char.Style').FormulaU = $(if ($Bold) { '1' } else { '0' })
    $Shape.CellsU('Para.HorzAlign').FormulaU = '1'
    $Shape.CellsU('VerticalAlign').FormulaU = '1'
}

function Draw-BoxTL($Page, [double]$PageHeight, $Item, [string]$DefaultFill, [string]$DefaultLine, [string]$DefaultTextColor) {
    $left = [double]$Item.x
    $right = $left + [double]$Item.width
    $top = $PageHeight - [double]$Item.y
    $bottom = $top - [double]$Item.height
    $shape = $Page.DrawRectangle($left, $bottom, $right, $top)
    $shape.Text = [string]$Item.text
    $fill = if ($Item.PSObject.Properties.Name -contains 'fill') { [string]$Item.fill } else { $DefaultFill }
    $line = if ($Item.PSObject.Properties.Name -contains 'line') { [string]$Item.line } else { $DefaultLine }
    $textColor = if ($Item.PSObject.Properties.Name -contains 'text_color') { [string]$Item.text_color } else { $DefaultTextColor }
    $fontSize = if ($Item.PSObject.Properties.Name -contains 'font_size') { [double]$Item.font_size } else { 9.0 }
    $bold = if ($Item.PSObject.Properties.Name -contains 'bold') { [bool]$Item.bold } else { $false }
    Set-CommonStyle $shape $fill $line $textColor $fontSize $bold
    if ($Item.PSObject.Properties.Name -contains 'hidden' -and [bool]$Item.hidden) {
        $shape.Text = ''
        $shape.CellsU('FillPattern').FormulaU = '0'
        $shape.CellsU('LinePattern').FormulaU = '0'
    }
    Set-ShapeData $shape 'DiagramId' ([string]$Item.id)
    return $shape
}

function Import-VectorSourceTL($Page, [double]$PageHeight, $Item, [string]$SpecDirectory) {
    $source = [string]$Item.path
    if (-not [IO.Path]::IsPathRooted($source)) { $source = Join-Path $SpecDirectory $source }
    $source = [IO.Path]::GetFullPath($source)
    if (-not (Test-Path -LiteralPath $source)) { throw "Vector source not found: $source" }
    $before = @($Page.Shapes | ForEach-Object { $_.ID })
    $shape = $Page.Import($source)
    $shape.CellsU('Width').ResultIU = [double]$Item.width
    $shape.CellsU('Height').ResultIU = [double]$Item.height
    $shape.CellsU('PinX').ResultIU = [double]$Item.x + ([double]$Item.width / 2)
    $shape.CellsU('PinY').ResultIU = $PageHeight - [double]$Item.y - ([double]$Item.height / 2)
    if ($Item.PSObject.Properties.Name -contains 'rotation_deg') {
        $shape.CellsU('Angle').FormulaU = "{0} deg" -f ([double]$Item.rotation_deg)
    }
    [void]$shape.Ungroup()
    $sourceId = [string]$Item.id
    foreach ($child in @($Page.Shapes)) {
        if ($before -notcontains $child.ID) {
            Set-ShapeData $child 'SourceVectorId' $sourceId
            Set-ShapeData $child 'Role' 'editable-vector-source'
            # An imported full-page SVG background is a vector rectangle, not content.
            # Delete it so editability inspection never mistakes it for a page-sized raster.
            try {
                $areaRatio = ($child.CellsU('Width').ResultIU * $child.CellsU('Height').ResultIU) / ([double]$Item.width * [double]$Item.height)
                $childText = [string]$child.Text
                if ($areaRatio -gt 0.95 -and [string]::IsNullOrWhiteSpace($childText)) { $child.Delete() }
            } catch {}
        }
    }
}

function Import-ImageTL($Page, [double]$PageHeight, $Item, [string]$SpecDirectory) {
    $source = [string]$Item.path
    if (-not [IO.Path]::IsPathRooted($source)) { $source = Join-Path $SpecDirectory $source }
    $source = [IO.Path]::GetFullPath($source)
    if (-not (Test-Path -LiteralPath $source)) { throw "Image not found: $source" }
    $shape = $Page.Import($source)
    $shape.CellsU('Width').ResultIU = [double]$Item.width
    $shape.CellsU('Height').ResultIU = [double]$Item.height
    $shape.CellsU('PinX').ResultIU = [double]$Item.x + ([double]$Item.width / 2)
    $shape.CellsU('PinY').ResultIU = $PageHeight - [double]$Item.y - ([double]$Item.height / 2)
    if ($Item.PSObject.Properties.Name -contains 'rotation_deg') {
        $shape.CellsU('Angle').FormulaU = "{0} deg" -f ([double]$Item.rotation_deg)
    }
    Set-ShapeData $shape 'DiagramId' ([string]$Item.id)
    Set-ShapeData $shape 'Role' 'component-image'
    Set-ShapeData $shape 'SourcePath' $source
    return $shape
}

function Draw-DecorationTL($Page, [double]$PageHeight, $Item) {
    $left = [double]$Item.x
    $right = $left + [double]$Item.width
    $top = $PageHeight - [double]$Item.y
    $bottom = $top - [double]$Item.height
    $kind = if ($Item.PSObject.Properties.Name -contains 'kind') { [string]$Item.kind } else { 'rectangle' }
    if ($kind -eq 'ellipse') { $shape = $Page.DrawOval($left, $bottom, $right, $top) }
    elseif ($kind -eq 'rectangle') { $shape = $Page.DrawRectangle($left, $bottom, $right, $top) }
    else { throw "Unsupported decoration kind: $kind" }
    $fill = if ($Item.PSObject.Properties.Name -contains 'fill') { [string]$Item.fill } else { '#eef3f5' }
    $line = if ($Item.PSObject.Properties.Name -contains 'line') { [string]$Item.line } else { '#34434c' }
    $shape.CellsU('FillForegnd').FormulaU = Convert-HexToRgbFormula $fill
    $shape.CellsU('FillPattern').FormulaU = '1'
    $shape.CellsU('LineColor').FormulaU = Convert-HexToRgbFormula $line
    $shape.CellsU('LineWeight').FormulaU = '0.8 pt'
    Set-ShapeData $shape 'DiagramId' ([string]$Item.id)
    Set-ShapeData $shape 'Role' 'decoration'
    return $shape
}

function Add-RouteHelper($Page, [double]$PageHeight, [string]$Id, [double]$X, [double]$Y) {
    $visioY = $PageHeight - $Y
    $shape = $Page.DrawRectangle($X - 0.002, $visioY - 0.002, $X + 0.002, $visioY + 0.002)
    $shape.CellsU('FillPattern').FormulaU = '0'
    $shape.CellsU('LinePattern').FormulaU = '0'
    Set-ShapeData $shape 'DiagramId' $Id
    Set-ShapeData $shape 'Role' 'route-helper'
    return $shape
}

function Connect-Shapes($Page, $Application, $FromShape, $ToShape, [string]$NetId, [int]$SegmentIndex, [string]$Color, [bool]$Arrow, [bool]$Hidden) {
    $connector = $Page.Drop($Application.ConnectorToolDataObject, 0, 0)
    $fromX = [double]$FromShape.CellsU('PinX').ResultIU
    $fromY = [double]$FromShape.CellsU('PinY').ResultIU
    $toX = [double]$ToShape.CellsU('PinX').ResultIU
    $toY = [double]$ToShape.CellsU('PinY').ResultIU
    $dx = $toX - $fromX
    $dy = $toY - $fromY
    if ([Math]::Abs($dx) -ge [Math]::Abs($dy)) {
        $beginXPercent = $(if ($dx -ge 0) { 1.0 } else { 0.0 })
        $beginYPercent = 0.5
        $endXPercent = $(if ($dx -ge 0) { 0.0 } else { 1.0 })
        $endYPercent = 0.5
    }
    else {
        $beginXPercent = 0.5
        $beginYPercent = $(if ($dy -ge 0) { 1.0 } else { 0.0 })
        $endXPercent = 0.5
        $endYPercent = $(if ($dy -ge 0) { 0.0 } else { 1.0 })
    }
    if ($FromShape.CellExistsU('Prop.Role', 0) -ne 0 -and [string]$FromShape.CellsU('Prop.Role').ResultStr('') -eq 'route-helper') {
        $beginXPercent = 0.5
        $beginYPercent = 0.5
    }
    if ($ToShape.CellExistsU('Prop.Role', 0) -ne 0 -and [string]$ToShape.CellsU('Prop.Role').ResultStr('') -eq 'route-helper') {
        $endXPercent = 0.5
        $endYPercent = 0.5
    }
    $connector.CellsU('BeginX').GlueToPos($FromShape, $beginXPercent, $beginYPercent)
    $connector.CellsU('EndX').GlueToPos($ToShape, $endXPercent, $endYPercent)
    $connector.CellsU('LineColor').FormulaU = Convert-HexToRgbFormula $Color
    $connector.CellsU('LineWeight').FormulaU = '1.6 pt'
    if ($Hidden) { $connector.CellsU('LinePattern').FormulaU = '0' }
    if ($connector.CellExistsU('ConLineRouteExt', 0) -ne 0) { $connector.CellsU('ConLineRouteExt').FormulaU = '1' }
    if ($connector.CellExistsU('ShapeRouteStyle', 0) -ne 0) { $connector.CellsU('ShapeRouteStyle').FormulaU = '2' }
    $connector.CellsU('EndArrow').FormulaU = $(if ($Arrow) { '13' } else { '0' })
    Set-ShapeData $connector 'NetId' $NetId
    Set-ShapeData $connector 'SegmentIndex' ([string]$SegmentIndex)
    # Connectors belong below terminals and text so pin labels stay visible.
    $connector.SendToBack()
    return $connector
}

function Set-DynamicConnectorGeometry($Connector, [double]$PageHeight, $FromShape, $ToShape, $Route) {
    # A Dynamic Connector owns one Geometry section. Its MoveTo/LineTo rows are
    # editable route vertices, not separate Visio line shapes. Temporarily pause
    # the routing engine while replacing those rows, then restore connector
    # behavior and freeze the intentional manual route.
    $points = [System.Collections.Generic.List[object]]::new()
    $points.Add(@(
        [double]$FromShape.CellsU('PinX').ResultIU,
        [double]$FromShape.CellsU('PinY').ResultIU
    ))
    if ($null -ne $Route.waypoints) {
        foreach ($point in @($Route.waypoints)) {
            $waypointX = [double]($point[0])
            $waypointY = $PageHeight - [double]($point[1])
            $points.Add(@($waypointX, $waypointY))
        }
    }
    $points.Add(@(
        [double]$ToShape.CellsU('PinX').ResultIU,
        [double]$ToShape.CellsU('PinY').ResultIU
    ))
    if ($points.Count -lt 2) { throw "Route $($Route.id) requires two endpoints." }

    $Connector.CellsU('ConFixedCode').FormulaU = '2'
    $Connector.CellsU('ObjType').FormulaU = '0'
    for ($row = $Connector.RowCount(10) - 1; $row -ge 1; $row--) {
        $Connector.DeleteRow(10, $row)
    }
    foreach ($index in 0..([int]$points.Count - 1)) {
        $tag = if ($index -eq 0) { 138 } else { 139 } # MoveTo / LineTo
        $row = $Connector.AddRow(10, -1, $tag)
        $localX = 0.0
        $localY = 0.0
        $Connector.XYFromPage(
            [double]$points[$index][0],
            [double]$points[$index][1],
            [ref]$localX,
            [ref]$localY
        )
        $Connector.CellsSRC(10, $row, 0).FormulaForceU = ('{0} in' -f $localX.ToString([Globalization.CultureInfo]::InvariantCulture))
        $Connector.CellsSRC(10, $row, 1).FormulaForceU = ('{0} in' -f $localY.ToString([Globalization.CultureInfo]::InvariantCulture))
    }
    $Connector.CellsU('ObjType').FormulaU = '2'
    $Connector.CellsU('ConFixedCode').FormulaU = '2'
}

function Draw-DynamicConnector($Page, $Application, [double]$PageHeight, $FromShape, $ToShape, $Route, $ConnectionsLayer) {
    # Drop the actual built-in Dynamic Connector master. There is exactly one
    # connector object for the complete electrical net; Visio owns its bends.
    $connector = $Page.Drop($Application.ConnectorToolDataObject, 0, 0)
    $connector.CellsU('BeginX').GlueToPos($FromShape, 0.5, 0.5)
    $connector.CellsU('EndX').GlueToPos($ToShape, 0.5, 0.5)

    # Point-to-point glue and native connector properties. Explicit bends are
    # stored in this connector's Geometry rows by Set-DynamicConnectorGeometry.
    $connector.CellsU('ObjType').FormulaU = '2'
    $connector.CellsU('GlueType').FormulaU = '2'
    $connector.CellsU('ConLineRouteExt').FormulaU = '1'
    $connector.CellsU('ShapeRouteStyle').FormulaU = '1'
    $connector.CellsU('ConFixedCode').FormulaU = '2'
    if ($connector.CellExistsU('ShapePermeableX', 0) -ne 0) { $connector.CellsU('ShapePermeableX').FormulaU = '0' }
    if ($connector.CellExistsU('ShapePermeableY', 0) -ne 0) { $connector.CellsU('ShapePermeableY').FormulaU = '0' }
    $connector.CellsU('LineColor').FormulaU = Convert-HexToRgbFormula ([string]$Route.color)
    $lineWeight = if ($Route.PSObject.Properties.Name -contains 'line_weight_pt') { [double]$Route.line_weight_pt } else { 2.3 }
    $connector.CellsU('LineWeight').FormulaU = ("{0} pt" -f $lineWeight.ToString([Globalization.CultureInfo]::InvariantCulture))
    $connector.CellsU('LinePattern').FormulaU = '1'
    $connector.CellsU('EndArrow').FormulaU = $(if ([bool]$Route.arrow) { '13' } else { '0' })
    Set-ShapeData $connector 'DiagramId' ([string]$Route.id)
    Set-ShapeData $connector 'NetId' ([string]$Route.id)
    Set-ShapeData $connector 'ConnectionId' ([string]$Route.id)
    Set-ShapeData $connector 'From' ([string]$Route.from)
    Set-ShapeData $connector 'To' ([string]$Route.to)
    Set-ShapeData $connector 'Role' 'dynamic-electrical-connector'
    Set-ShapeData $connector 'ConnectorMaster' 'Dynamic connector'
    Set-DynamicConnectorGeometry $connector $PageHeight $FromShape $ToShape $Route
    try { $connector.NameU = 'wire__' + (([string]$Route.id) -replace '[^A-Za-z0-9_]', '_') } catch {}
    if ($null -ne $ConnectionsLayer) { [void]$ConnectionsLayer.Add($connector, 0) }
    $connector.SendToBack()
    return $connector
}

function Draw-RoutePolyline($Page, [double]$PageHeight, $FromShape, $ToShape, $Route, $ConnectionsLayer) {
    # A complete electrical connection is one native 1-D Visio shape. This keeps
    # every wire independently selectable while preserving all explicit bends.
    $points = [System.Collections.Generic.List[double]]::new()
    $points.Add([double]$FromShape.CellsU('PinX').ResultIU)
    $points.Add([double]$FromShape.CellsU('PinY').ResultIU)
    if ($null -ne $Route.waypoints) {
        foreach ($point in @($Route.waypoints)) {
            $points.Add([double]$point[0])
            $points.Add($PageHeight - [double]$point[1])
        }
    }
    $points.Add([double]$ToShape.CellsU('PinX').ResultIU)
    $points.Add([double]$ToShape.CellsU('PinY').ResultIU)
    if (($points.Count / 2) -lt 2) { throw "Route $($Route.id) requires at least two distinct points." }

    # visPolyline1D = 8. Unlike a group of straight connector segments, this is
    # a single Visio object with editable vertices and glued electrical ends.
    $polyline = $Page.DrawPolyline([double[]]$points.ToArray(), 8)
    $polyline.CellsU('BeginX').GlueToPos($FromShape, 0.5, 0.5)
    $polyline.CellsU('EndX').GlueToPos($ToShape, 0.5, 0.5)
    $polyline.CellsU('LineColor').FormulaU = Convert-HexToRgbFormula ([string]$Route.color)
    $lineWeight = if ($Route.PSObject.Properties.Name -contains 'line_weight_pt') { [double]$Route.line_weight_pt } else { 2.3 }
    $polyline.CellsU('LineWeight').FormulaU = ("{0} pt" -f $lineWeight.ToString([Globalization.CultureInfo]::InvariantCulture))
    $hidden = ($Route.PSObject.Properties.Name -contains 'hidden' -and [bool]$Route.hidden)
    $polyline.CellsU('LinePattern').FormulaU = $(if ($hidden) { '0' } else { '1' })
    $polyline.CellsU('EndArrow').FormulaU = $(if ([bool]$Route.arrow) { '13' } else { '0' })
    $polyline.CellsU('FillPattern').FormulaU = '0'
    Set-ShapeData $polyline 'DiagramId' ([string]$Route.id)
    Set-ShapeData $polyline 'NetId' ([string]$Route.id)
    Set-ShapeData $polyline 'ConnectionId' ([string]$Route.id)
    Set-ShapeData $polyline 'From' ([string]$Route.from)
    Set-ShapeData $polyline 'To' ([string]$Route.to)
    Set-ShapeData $polyline 'Role' 'electrical-connection'
    try { $polyline.NameU = 'wire__' + (([string]$Route.id) -replace '[^A-Za-z0-9_]', '_') } catch {}
    if ($null -ne $ConnectionsLayer) { [void]$ConnectionsLayer.Add($polyline, 0) }
    $polyline.SendToBack()
    return $polyline
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python is required for Visio specification validation.' }
$validator = Join-Path $PSScriptRoot 'validate_visio_spec.py'
& $python.Source $validator $SpecPath --netlist $NetlistPath
if ($LASTEXITCODE -ne 0) { throw 'Visio specification validation failed.' }

$spec = Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
$netlist = Get-Content -LiteralPath $NetlistPath -Raw -Encoding UTF8 | ConvertFrom-Json
$specDirectory = Split-Path -Parent $SpecPath
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) { [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
if (Test-Path -LiteralPath $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = [IO.Path]::Combine($outputDirectory, ([IO.Path]::GetFileNameWithoutExtension($OutputPath) + ".backup-$stamp.vsdx"))
    Copy-Item -LiteralPath $OutputPath -Destination $backup
}

$application = $null
$document = $null
$completed = $false
try {
    $application = New-Object -ComObject Visio.Application
    $application.Visible = [bool]$Visible
    $application.AlertResponse = 7
    $document = $application.Documents.Add('')
    $page = $application.ActivePage
    $page.Name = [string]$spec.page.name
    $pageWidth = [double]$spec.page.width_in
    $pageHeight = [double]$spec.page.height_in
    $page.PageSheet.CellsU('PageWidth').ResultIU = $pageWidth
    $page.PageSheet.CellsU('PageHeight').ResultIU = $pageHeight
    $crossingPolicy = if ($spec.page.PSObject.Properties.Name -contains 'crossing_policy') { [string]$spec.page.crossing_policy } else { 'forbid' }
    if ($crossingPolicy -eq 'gap') {
        $page.PageSheet.CellsU('LineJumpStyle').FormulaU = '2'
        $page.PageSheet.CellsU('LineJumpCode').FormulaU = '4'
    }
    elseif ($crossingPolicy -eq 'arc') {
        $page.PageSheet.CellsU('LineJumpStyle').FormulaU = '1'
        $page.PageSheet.CellsU('LineJumpCode').FormulaU = '4'
    }
    else {
        $page.PageSheet.CellsU('LineJumpCode').FormulaU = '0'
    }

    $shapes = @{}
    $connectionsLayer = $page.Layers.Add('Electrical connections - one shape per net')
    $application.AutoLayout = $false
    $page.LayoutRoutePassive = $true
    if ($null -ne $spec.vector_sources) {
        foreach ($vectorSource in @($spec.vector_sources)) {
            Import-VectorSourceTL $page $pageHeight $vectorSource $specDirectory
        }
    }
    if ($null -ne $spec.decorations) {
        foreach ($decoration in @($spec.decorations)) {
            $shape = Draw-DecorationTL $page $pageHeight $decoration
            $shapes[[string]$decoration.id] = $shape
        }
    }
    if ($null -ne $spec.images) {
        foreach ($image in @($spec.images)) {
            $shape = Import-ImageTL $page $pageHeight $image $specDirectory
            $shapes[[string]$image.id] = $shape
        }
    }
    if ($null -ne $spec.labels) {
        foreach ($label in @($spec.labels)) {
            $shape = Draw-BoxTL $page $pageHeight $label '#ffffff' '#cbd5db' '#17232d'
            $shapes[[string]$label.id] = $shape
        }
    }
    if ($null -ne $spec.terminals) {
        foreach ($terminal in @($spec.terminals)) {
            $shape = Draw-BoxTL $page $pageHeight $terminal '#eef3f5' '#34434c' '#17232d'
            Set-ShapeData $shape 'TerminalId' ([string]$terminal.id)
            $shapes[[string]$terminal.id] = $shape
        }
    }

    if ($null -ne $spec.routes) { foreach ($route in @($spec.routes)) {
        $from = $shapes[[string]$route.from]
        $to = $shapes[[string]$route.to]
        $routeRenderMode = if ($route.PSObject.Properties.Name -contains 'render_mode') { [string]$route.render_mode } elseif ($spec.page.PSObject.Properties.Name -contains 'route_render_mode') { [string]$spec.page.route_render_mode } else { 'segmented' }
        if ($routeRenderMode -eq 'dynamic_connector') {
            [void](Draw-DynamicConnector $page $application $pageHeight $from $to $route $connectionsLayer)
            continue
        }
        if ($routeRenderMode -eq 'single_polyline') {
            [void](Draw-RoutePolyline $page $pageHeight $from $to $route $connectionsLayer)
            continue
        }
        $nodes = [System.Collections.Generic.List[object]]::new()
        $nodes.Add($from)
        $pointIndex = 0
        if ($null -ne $route.waypoints) {
            foreach ($point in @($route.waypoints)) {
                $helper = Add-RouteHelper $page $pageHeight ("route:{0}:{1}" -f $route.id,$pointIndex) ([double]$point[0]) ([double]$point[1])
                $nodes.Add($helper)
                $pointIndex++
            }
        }
        $nodes.Add($to)
        for ($index = 0; $index -lt $nodes.Count - 1; $index++) {
            $isLast = ($index -eq $nodes.Count - 2)
            $hidden = ($route.PSObject.Properties.Name -contains 'hidden' -and [bool]$route.hidden)
            [void](Connect-Shapes $page $application $nodes[$index] $nodes[$index + 1] ([string]$route.id) $index ([string]$route.color) ([bool]$route.arrow -and $isLast) $hidden)
        }
    } }

    # Native Dynamic Connectors already contain their explicit route vertices.
    # Page-level automatic routing stays passive so it cannot overwrite them.
    [void]$document.SaveAs($OutputPath)
    if ($PreviewPng) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $PreviewPng)) | Out-Null
        [void]$page.Export($PreviewPng)
    }
    if ($PreviewPdf) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $PreviewPdf)) | Out-Null
        [void]$document.ExportAsFixedFormat(1, $PreviewPdf, 1, 0, 1, -1, 0, $true, $true, $true, $false, [Type]::Missing)
    }
    [void]$document.Save()
    $completed = $true
    [pscustomobject]@{
        Status = 'passed'
        Vsdx = $OutputPath
        PreviewPng = $PreviewPng
        PreviewPdf = $PreviewPdf
        Terminals = @($spec.terminals).Count
        Routes = @($spec.routes).Count
    } | ConvertTo-Json -Depth 3
}
finally {
    if ($null -ne $document -and (-not $Visible -or -not $completed)) { try { $document.Close() } catch {} }
    if ($null -ne $application) {
        if (-not $Visible -or -not $completed) { try { $application.Quit() } catch {} }
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
    }
}
