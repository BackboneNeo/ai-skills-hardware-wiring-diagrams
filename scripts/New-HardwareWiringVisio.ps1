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
    Set-ShapeData $shape 'DiagramId' ([string]$Item.id)
    return $shape
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
    Set-ShapeData $shape 'DiagramId' ([string]$Item.id)
    Set-ShapeData $shape 'Role' 'component-image'
    Set-ShapeData $shape 'SourcePath' $source
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

function Connect-Shapes($Page, $Application, $FromShape, $ToShape, [string]$NetId, [int]$SegmentIndex, [string]$Color, [bool]$Arrow) {
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
    if ($connector.CellExistsU('ConLineRouteExt', 0) -ne 0) { $connector.CellsU('ConLineRouteExt').FormulaU = '1' }
    if ($connector.CellExistsU('ShapeRouteStyle', 0) -ne 0) { $connector.CellsU('ShapeRouteStyle').FormulaU = '2' }
    $connector.CellsU('EndArrow').FormulaU = $(if ($Arrow) { '13' } else { '0' })
    Set-ShapeData $connector 'NetId' $NetId
    Set-ShapeData $connector 'SegmentIndex' ([string]$SegmentIndex)
    # Connectors belong below terminals and text so pin labels stay visible.
    $connector.SendToBack()
    return $connector
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
            [void](Connect-Shapes $page $application $nodes[$index] $nodes[$index + 1] ([string]$route.id) $index ([string]$route.color) ([bool]$route.arrow -and $isLast))
        }
    } }

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
