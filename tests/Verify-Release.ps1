param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$RoundTrip,
    [Parameter(Mandatory)][string]$AnalysisReport,
    [Parameter(Mandatory)][string]$Cfe
)

$ErrorActionPreference = 'Stop'
$passed = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $passed.Add($Name)
}

function Normalize-Module([string]$Text) {
    return $Text.TrimStart([char]0xFEFF).Replace("`r`n", "`n").TrimEnd("`r", "`n")
}

$relative = 'DataProcessor\Расш1_АудитСебестоимости\Form\Форма'
$module = Get-Content -LiteralPath (Join-Path $Source "$relative\Form.obj.bsl") -Raw -Encoding UTF8
$decoded = Get-Content -LiteralPath (Join-Path $RoundTrip "$relative\Form.obj.bsl") -Raw -Encoding UTF8
Check ((Normalize-Module $module) -ceq (Normalize-Module $decoded)) 'BSL module round-trip equality'

$cfg = Get-Content -LiteralPath (Join-Path $RoundTrip 'ConfigurationExtension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($cfg.name -eq 'АудитСебестоимости') 'Extension name'
Check ($cfg.name2.ru -eq 'Аудит и восстановление себестоимости') 'Extension synonym'
Check ($cfg.compatibility_version -eq '80327') 'Compatibility 8.3.27'

$version = (Get-Content -LiteralPath (Join-Path $RoundTrip 'version.bin') -Raw -Encoding UTF8).Trim()
Check ($version -eq '1.1.1') 'Binary version 1.1.1'

$dirs = @(Get-ChildItem -LiteralPath $RoundTrip -Directory | Select-Object -ExpandProperty Name | Sort-Object)
Check (($dirs -join ',') -eq 'DataProcessor,Language,Role,Subsystem') 'Only required metadata types'

$donorObjectIds = @(
    '5894f78d-06e4-4efa-a434-8249ee145f9c',
    '5c502eb0-fddb-4ba6-9654-2c2c832f68f0',
    'a971f25c-c762-4551-81de-8bab0bc1ecfb',
    'd3e3a709-95be-499e-9160-d0d41a422460',
    '7c9d1558-8b59-45b9-ba29-72c9350a907a',
    '24b5fee9-7c0b-4874-ab19-405c4d3ad268',
    '24a9487c-c049-40d8-a73a-67db0fcf17cc',
    'aade49fa-01c9-422f-b0af-d06300293814',
    '795bdcdf-9ec7-42f4-a039-696f545a4325',
    'f3c0a6fd-4fed-48b3-a163-164c26562f55',
    'c8acae32-1a10-4c64-8ea7-93d28f02ac1b',
    'f820ba17-b7aa-4c0c-ba99-4a12ada02636',
    'f037fe3e-c909-4ce8-abcc-f5b4b93f5510',
    '02a28e38-fab1-4276-b639-107c1073b335',
    'b37b70a6-fcec-48f1-965f-e0e242605014',
    '9438968a-c7a1-4293-8caf-85c926497f2d',
    'e7d5b7ad-bebc-4d06-b2af-ad27026fed82',
    '02023637-7868-4a5f-8576-835a76e0c9ba'
)
$roundTripText = (Get-ChildItem -LiteralPath $RoundTrip -Recurse -File |
    Where-Object Extension -in '.json', '.c1brace' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
Check (-not ($donorObjectIds | Where-Object { $roundTripText.Contains($_) })) 'No object or internal UUID collisions with donor extension'

$objectIds = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath $RoundTrip -Recurse -Filter '*.id.json' -File | ForEach-Object {
    $idObject = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $idObject.PSObject.Properties | Where-Object Name -like '*uuid*' | ForEach-Object {
        $objectIds.Add([string]$_.Value)
    }
}
Check ($objectIds.Count -eq @($objectIds | Sort-Object -Unique).Count) 'Extension object UUIDs are unique'

$processor = Get-Content -LiteralPath (Join-Path $RoundTrip 'DataProcessor\Расш1_АудитСебестоимости\DataProcessor.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($processor.name -eq 'Расш1_АудитСебестоимости') 'Data processor uses extension prefix'
$subsystem = Get-Content -LiteralPath (Join-Path $RoundTrip 'Subsystem\Расш1_АудитСебестоимости\Subsystem.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($subsystem.name2.ru -eq 'Аудит себестоимости') 'Subsystem presentation'

$form = Get-Content -LiteralPath (Join-Path $RoundTrip "$relative\Form.elem.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($form.props.Count -eq 1 -and $form.props[0].name -eq 'Объект') 'No legacy form attributes'
Check ($form.commands.Count -eq 0 -and $form.tree.Count -eq 0) 'Form UI is generated consistently at runtime'

Check ($module.Contains('ВыполнитьАудитНаСервере')) 'Detailed audit command'
Check ($module.Contains('ПроверитьОстаткиНаНачало')) 'Opening balance audit'
Check ($module.Contains('ПроверитьДвиженияЗапасов')) 'Inventory movement audit'
Check ($module.Contains('ПроверитьПродажи')) 'Sales cost audit'
Check ($module.Contains('Повторные проблемы одной позиции не скрываются')) 'Repeated issues are preserved'
Check ($module.Contains('АС_Номенклатура')) 'Optional item filter'
Check ($module.Contains('ПроверитьСтруктуруНаСервере')) 'UNF metadata diagnostics'

Check ($module.Contains('Документы.Проведен = ИСТИНА')) 'Plan contains posted documents'
Check ($module.Contains('Для Каждого МетаДокумента Из Метаданные.Документы')) 'Plan covers every document type'
Check ($module.Contains('ТаблицаПлана.Сортировать("Момент Возр")')) 'Plan is chronological by moment in time'
Check ($module.Contains('РежимПроведенияДокумента.Неоперативный')) 'Non-operational reposting'
Check ($module.Contains('ПерепровестиПакетНаСервере(АдресПлана, СостояниеПерепроведения.Индекс, 10)')) 'Batch size 10'
Check ($module.Contains('ИндексВозобновления')) 'Stop and resume checkpoint'
Check ($module.Contains('АС_РезервнаяКопия')) 'Backup confirmation gate'
Check ($module.Contains('типовое закрытие месяцев')) 'Mandatory month-close instruction'
Check ($module.Contains('Контроль после исправления')) 'Post-repair control'
Check ($module.Contains('ЗаписьЖурналаРегистрации')) 'Registration log integration'

Check (-not $module.Contains('УстановитьПривилегированныйРежим')) 'No privilege elevation'
Check (-not $module.Contains('УдалитьОбъекты')) 'No bulk object deletion'
Check (-not $module.Contains('HTTPСоединение')) 'No network requests'
Check (-not $module.Contains('ЗапуститьПриложение')) 'No external process launch'
Check (-not $module.Contains('Распределение оплат')) 'No donor payment logic remains'

$report = Get-Content -LiteralPath $AnalysisReport -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = @($report.fileinfos.diagnostics | Where-Object severity -eq 'Error')
Check ($errors.Count -eq 0) 'BSL Language Server: zero Error diagnostics'

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Cfe).Path)
Check ($bytes.Length -gt 1000) 'Non-empty CFE'

[pscustomobject]@{
    Status = 'PASS'
    Checks = $passed.Count
    Version = $version
    Compatibility = $cfg.compatibility_version
    Bytes = $bytes.Length
    SHA256 = (Get-FileHash -LiteralPath $Cfe -Algorithm SHA256).Hash
    AnalyzerErrors = $errors.Count
    AnalyzerWarnings = @($report.fileinfos.diagnostics | Where-Object severity -eq 'Warning').Count
    NotExecuted = '1C Designer compilation, managed form runtime, UNF reposting and register reconciliation'
} | ConvertTo-Json
