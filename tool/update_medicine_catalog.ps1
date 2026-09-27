$ErrorActionPreference = 'Stop'

$cmedUrl = 'https://dados.anvisa.gov.br/dados/TA_PRECOS_MEDICAMENTOS.csv'
$registryUrl = 'https://dados.anvisa.gov.br/dados/CONSULTAS/PRODUTOS/TA_CONSULTA_MEDICAMENTOS.CSV'
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'remedios-anvisa-catalog'
$outputDirectory = Join-Path $PSScriptRoot '..\assets\data'
$cmedPath = Join-Path $temporaryDirectory 'cmed.csv'
$registryPath = Join-Path $temporaryDirectory 'medicine_registry.csv'
$outputPath = Join-Path $outputDirectory 'medicine_catalog.json'

New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Invoke-WebRequest -Uri $cmedUrl -OutFile $cmedPath -UseBasicParsing
Invoke-WebRequest -Uri $registryUrl -OutFile $registryPath -UseBasicParsing

$registryByNumber = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$aliasesByNumber = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($record in (Import-Csv -LiteralPath $registryPath -Delimiter ';' -Encoding Default)) {
    $registrationNumber = ([string]$record.NU_REGISTRO_PRODUTO) -replace '\D', ''
    if ($record.VALIDADE_SITUACAO -ne 'Ativo' -or -not $registrationNumber) { continue }

    if (-not $registryByNumber.ContainsKey($registrationNumber)) {
        $registryByNumber[$registrationNumber] = $record
        $aliasesByNumber[$registrationNumber] =
            [System.Collections.Generic.List[string]]::new()
    }

    $referenceName = ([string]$record.DS_REFERENCIA).Trim() -replace '\s+', ' '
    if ($referenceName -and
        -not $aliasesByNumber[$registrationNumber].Contains($referenceName)) {
        $aliasesByNumber[$registrationNumber].Add($referenceName)
    }
}

$catalogByKey = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$registrationsWithCmed = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($record in (Import-Csv -LiteralPath $cmedPath -Delimiter ';' -Encoding Default)) {
    $cmedRegistration = ([string]$record.NU_REGISTRO) -replace '\D', ''
    if ($cmedRegistration.Length -le 9) { continue }

    $registrationNumber = $cmedRegistration.Substring(0, 9)
    if (-not $registryByNumber.ContainsKey($registrationNumber)) { continue }

    $productName = ([string]$record.NO_PRODUTO).Trim() -replace '\s+', ' '
    $presentation = ([string]$record.DS_APRESENTACAO).Trim() -replace '\s+', ' '
    if (-not $productName -or -not $presentation) { continue }

    $registryRecord = $registryByNumber[$registrationNumber]
    $activeIngredient =
        ([string]$registryRecord.SUBSTANCIAS_MEDICAMENTOS).Trim() -replace '\s+', ' '
    if (-not $activeIngredient -or $activeIngredient -match '^(?i:NC/NI)$') {
        $activeIngredient = ([string]$record.DS_SUBSTANCIA).Trim() -replace '\s+', ' '
    }
    if ($activeIngredient -match '^(?i:NC/NI)$') { $activeIngredient = '' }

    $key = "$registrationNumber|$productName|$presentation"
    if (-not $catalogByKey.ContainsKey($key)) {
        $catalogByKey[$key] = [ordered]@{
            name = $productName
            activeIngredient = $activeIngredient
            presentation = $presentation
            registrationNumber = $registrationNumber
            aliases = @($aliasesByNumber[$registrationNumber].ToArray())
            eans = [System.Collections.Generic.List[string]]::new()
            requiresManualDetails = $false
        }
    }

    $null = $registrationsWithCmed.Add($registrationNumber)
    $ean = ([string]$record.CO_EAN).Trim()
    if ($ean -match '^\d+$' -and -not $catalogByKey[$key].eans.Contains($ean)) {
        $catalogByKey[$key].eans.Add($ean)
    }
}

foreach ($registrationNumber in $registryByNumber.Keys) {
    if ($registrationsWithCmed.Contains($registrationNumber)) { continue }

    $record = $registryByNumber[$registrationNumber]
    $productName = ([string]$record.NO_PRODUTO).Trim() -replace '\s+', ' '
    if (-not $productName) { continue }

    $activeIngredient =
        ([string]$record.SUBSTANCIAS_MEDICAMENTOS).Trim() -replace '\s+', ' '
    if ($activeIngredient -match '^(?i:NC/NI)$') { $activeIngredient = '' }

    $key = "$registrationNumber|$productName|"
    if (-not $catalogByKey.ContainsKey($key)) {
        $catalogByKey[$key] = [ordered]@{
            name = $productName
            activeIngredient = $activeIngredient
            presentation = ''
            registrationNumber = $registrationNumber
            aliases = @($aliasesByNumber[$registrationNumber].ToArray())
            eans = [System.Collections.Generic.List[string]]::new()
            requiresManualDetails = $true
        }
    }
}

$catalogByKey['manual|Enterogermina'] = [ordered]@{
    name = 'Enterogermina'
    activeIngredient = ''
    presentation = ''
    registrationNumber = ''
    aliases = @()
    eans = [System.Collections.Generic.List[string]]::new()
    requiresManualDetails = $true
}

$items = @(
    $catalogByKey.Values |
        ForEach-Object {
            [ordered]@{
                name = $_.name
                activeIngredient = $_.activeIngredient
                presentation = $_.presentation
                registrationNumber = $_.registrationNumber
                aliases = @($_.aliases)
                eans = @($_.eans.ToArray())
                requiresManualDetails = $_.requiresManualDetails
            }
        } |
        Sort-Object { $_.name.ToLowerInvariant() }, presentation, registrationNumber
)

$catalog = [ordered]@{
    version = 1
    sources = @($registryUrl, $cmedUrl)
    note = 'Active Anvisa records missing CMED presentations have blank presentation fields; Enterogermina is an unverified manual lookup term.'
    generatedAt = (Get-Date).ToString('yyyy-MM-dd')
    count = $items.Count
    items = $items
}
$json = ConvertTo-Json -InputObject $catalog -Depth 5 -Compress
[System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))

$sizeInMegabytes = [Math]::Round((Get-Item -LiteralPath $outputPath).Length / 1MB, 2)
"Generated $($items.Count) active medicine presentations ($sizeInMegabytes MB): $outputPath"