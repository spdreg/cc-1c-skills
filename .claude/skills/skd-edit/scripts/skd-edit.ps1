param(
	[Parameter(Mandatory)]
	[string]$TemplatePath,

	[Parameter(Mandatory)]
	[ValidateSet(
		"add-field","add-total","add-calculated-field","add-parameter","add-filter",
		"add-dataParameter","add-order","add-selection",
		"set-query","set-outputParameter",
		"remove-field","remove-total","remove-calculated-field","remove-parameter","remove-filter")]
	[string]$Operation,

	[Parameter(Mandatory)]
	[string]$Value,

	[string]$DataSet,
	[string]$Variant,
	[switch]$NoSelection
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 1. Resolve path ---

if (-not $TemplatePath.EndsWith(".xml")) {
	$candidate = Join-Path (Join-Path $TemplatePath "Ext") "Template.xml"
	if (Test-Path $candidate) {
		$TemplatePath = $candidate
	}
}

if (-not (Test-Path $TemplatePath)) {
	Write-Error "File not found: $TemplatePath"
	exit 1
}

$resolvedPath = (Resolve-Path $TemplatePath).Path

function Esc-Xml {
	param([string]$s)
	return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

# --- 2. Type system (copied from skd-compile) ---

$script:typeSynonyms = New-Object System.Collections.Hashtable
$script:typeSynonyms["число"] = "decimal"
$script:typeSynonyms["строка"] = "string"
$script:typeSynonyms["булево"] = "boolean"
$script:typeSynonyms["дата"] = "date"
$script:typeSynonyms["датавремя"] = "dateTime"
$script:typeSynonyms["стандартныйпериод"] = "StandardPeriod"
$script:typeSynonyms["bool"] = "boolean"
$script:typeSynonyms["str"] = "string"
$script:typeSynonyms["int"] = "decimal"
$script:typeSynonyms["integer"] = "decimal"
$script:typeSynonyms["number"] = "decimal"
$script:typeSynonyms["num"] = "decimal"
$script:typeSynonyms["справочникссылка"] = "CatalogRef"
$script:typeSynonyms["документссылка"] = "DocumentRef"
$script:typeSynonyms["перечислениессылка"] = "EnumRef"
$script:typeSynonyms["плансчетовссылка"] = "ChartOfAccountsRef"
$script:typeSynonyms["планвидовхарактеристикссылка"] = "ChartOfCharacteristicTypesRef"

$script:outputParamTypes = @{
	"Заголовок" = "mltext"
	"ВыводитьЗаголовок" = "dcsset:DataCompositionTextOutputType"
	"ВыводитьПараметрыДанных" = "dcsset:DataCompositionTextOutputType"
	"ВыводитьОтбор" = "dcsset:DataCompositionTextOutputType"
	"МакетОформления" = "xs:string"
	"РасположениеПолейГруппировки" = "dcsset:DataCompositionGroupFieldsPlacement"
	"РасположениеРеквизитов" = "dcsset:DataCompositionAttributesPlacement"
	"ГоризонтальноеРасположениеОбщихИтогов" = "dcscor:DataCompositionTotalPlacement"
	"ВертикальноеРасположениеОбщихИтогов" = "dcscor:DataCompositionTotalPlacement"
}

function Resolve-TypeStr {
	param([string]$typeStr)
	if (-not $typeStr) { return $typeStr }

	if ($typeStr -match '^([^(]+)\((.+)\)$') {
		$baseName = $Matches[1].Trim()
		$params = $Matches[2]
		$resolved = $script:typeSynonyms[$baseName.ToLower()]
		if ($resolved) { return "$resolved($params)" }
		return $typeStr
	}

	if ($typeStr.Contains('.')) {
		$dotIdx = $typeStr.IndexOf('.')
		$prefix = $typeStr.Substring(0, $dotIdx)
		$suffix = $typeStr.Substring($dotIdx)
		$resolved = $script:typeSynonyms[$prefix.ToLower()]
		if ($resolved) { return "$resolved$suffix" }
		return $typeStr
	}

	$resolved = $script:typeSynonyms[$typeStr.ToLower()]
	if ($resolved) { return $resolved }
	return $typeStr
}

# --- 3. Parsers ---

function Parse-FieldShorthand {
	param([string]$s)

	$result = @{
		dataPath = ""; field = ""; title = ""; type = ""
		roles = @(); restrict = @()
	}

	# Extract [Title]
	if ($s -match '\[([^\]]+)\]') {
		$result.title = $Matches[1]
		$s = $s -replace '\s*\[[^\]]+\]', ''
	}

	# Extract @roles
	$roleMatches = [regex]::Matches($s, '@(\w+)')
	foreach ($m in $roleMatches) {
		$result.roles += $m.Groups[1].Value
	}
	$s = [regex]::Replace($s, '\s*@\w+', '')

	# Extract #restrictions
	$restrictMatches = [regex]::Matches($s, '#(\w+)')
	foreach ($m in $restrictMatches) {
		$result.restrict += $m.Groups[1].Value
	}
	$s = [regex]::Replace($s, '\s*#\w+', '')

	# Split name: type
	$s = $s.Trim()
	if ($s.Contains(':')) {
		$parts = $s -split ':', 2
		$result.dataPath = $parts[0].Trim()
		$result.type = Resolve-TypeStr ($parts[1].Trim())
	} else {
		$result.dataPath = $s
	}

	$result.field = $result.dataPath
	return $result
}

function Parse-TotalShorthand {
	param([string]$s)

	$parts = $s -split ':', 2
	$dataPath = $parts[0].Trim()
	$funcPart = $parts[1].Trim()

	if ($funcPart -match '^\w+\(') {
		return @{ dataPath = $dataPath; expression = $funcPart }
	} else {
		return @{ dataPath = $dataPath; expression = "$funcPart($dataPath)" }
	}
}

function Parse-CalcShorthand {
	param([string]$s)

	$title = ""
	# Extract [Title] first
	if ($s -match '\[([^\]]+)\]') {
		$title = $Matches[1]
		$s = $s -replace '\s*\[[^\]]+\]', ''
	}

	# Support "Name: Type = Expression" and "Name = Expression"
	$eqIdx = $s.IndexOf('=')
	if ($eqIdx -gt 0) {
		$left = $s.Substring(0, $eqIdx).Trim()
		$expression = $s.Substring($eqIdx + 1).Trim()

		if ($left.Contains(':')) {
			$colonIdx = $left.IndexOf(':')
			$dataPath = $left.Substring(0, $colonIdx).Trim()
			$type = Resolve-TypeStr ($left.Substring($colonIdx + 1).Trim())
			return @{ dataPath = $dataPath; expression = $expression; type = $type; title = $title }
		}
		return @{ dataPath = $left; expression = $expression; type = ""; title = $title }
	}
	return @{ dataPath = $s.Trim(); expression = ""; type = ""; title = $title }
}

function Parse-ParamShorthand {
	param([string]$s)

	$result = @{ name = ""; type = ""; value = $null; autoDates = $false }

	if ($s -match '@autoDates') {
		$result.autoDates = $true
		$s = $s -replace '\s*@autoDates', ''
	}

	if ($s -match '^([^:]+):\s*(\S+)(\s*=\s*(.+))?$') {
		$result.name = $Matches[1].Trim()
		$result.type = Resolve-TypeStr ($Matches[2].Trim())
		if ($Matches[4]) {
			$result.value = $Matches[4].Trim()
		}
	} else {
		$result.name = $s.Trim()
	}

	return $result
}

function Parse-FilterShorthand {
	param([string]$s)

	$result = @{ field = ""; op = "Equal"; value = $null; use = $true; userSettingID = $null; viewMode = $null }

	if ($s -match '@user') {
		$result.userSettingID = "auto"
		$s = $s -replace '\s*@user', ''
	}
	if ($s -match '@off') {
		$result.use = $false
		$s = $s -replace '\s*@off', ''
	}
	if ($s -match '@quickAccess') {
		$result.viewMode = "QuickAccess"
		$s = $s -replace '\s*@quickAccess', ''
	}
	if ($s -match '@normal') {
		$result.viewMode = "Normal"
		$s = $s -replace '\s*@normal', ''
	}
	if ($s -match '@inaccessible') {
		$result.viewMode = "Inaccessible"
		$s = $s -replace '\s*@inaccessible', ''
	}

	$s = $s.Trim()

	$opPatterns = @('<>', '>=', '<=', '=', '>', '<',
		'notIn\b', 'in\b', 'inHierarchy\b', 'inListByHierarchy\b',
		'notContains\b', 'contains\b', 'notBeginsWith\b', 'beginsWith\b',
		'notFilled\b', 'filled\b')
	$opJoined = $opPatterns -join '|'

	if ($s -match "^(.+?)\s+($opJoined)\s*(.*)?$") {
		$result.field = $Matches[1].Trim()
		$opRaw = $Matches[2].Trim()
		$valPart = if ($Matches[3]) { $Matches[3].Trim() } else { "" }

		$opMap = @{
			"=" = "Equal"; "<>" = "NotEqual"; ">" = "Greater"; ">=" = "GreaterOrEqual"
			"<" = "Less"; "<=" = "LessOrEqual"; "in" = "InList"; "notIn" = "NotInList"
			"inHierarchy" = "InHierarchy"; "inListByHierarchy" = "InListByHierarchy"
			"contains" = "Contains"; "notContains" = "NotContains"
			"beginsWith" = "BeginsWith"; "notBeginsWith" = "NotBeginsWith"
			"filled" = "Filled"; "notFilled" = "NotFilled"
		}
		$mapped = $opMap[$opRaw]
		if ($mapped) { $result.op = $mapped } else { $result.op = $opRaw }

		if ($valPart -and $valPart -ne "_") {
			if ($valPart -eq "true" -or $valPart -eq "false") {
				$result.value = $valPart
				$result["valueType"] = "xs:boolean"
			} elseif ($valPart -match '^\d{4}-\d{2}-\d{2}T') {
				$result.value = $valPart
				$result["valueType"] = "xs:dateTime"
			} elseif ($valPart -match '^\d+(\.\d+)?$') {
				$result.value = $valPart
				$result["valueType"] = "xs:decimal"
			} else {
				$result.value = $valPart
				$result["valueType"] = "xs:string"
			}
		}
	} else {
		$result.field = $s
	}

	return $result
}

function Parse-DataParamShorthand {
	param([string]$s)

	$result = @{ parameter = ""; value = $null; use = $true; userSettingID = $null; viewMode = $null }

	if ($s -match '@user') {
		$result.userSettingID = "auto"
		$s = $s -replace '\s*@user', ''
	}
	if ($s -match '@off') {
		$result.use = $false
		$s = $s -replace '\s*@off', ''
	}
	if ($s -match '@quickAccess') {
		$result.viewMode = "QuickAccess"
		$s = $s -replace '\s*@quickAccess', ''
	}
	if ($s -match '@normal') {
		$result.viewMode = "Normal"
		$s = $s -replace '\s*@normal', ''
	}

	$s = $s.Trim()

	if ($s -match '^([^=]+)=\s*(.+)$') {
		$result.parameter = $Matches[1].Trim()
		$valStr = $Matches[2].Trim()

		$periodVariants = @("Custom","Today","ThisWeek","ThisTenDays","ThisMonth","ThisQuarter","ThisHalfYear","ThisYear","FromBeginningOfThisWeek","FromBeginningOfThisTenDays","FromBeginningOfThisMonth","FromBeginningOfThisQuarter","FromBeginningOfThisHalfYear","FromBeginningOfThisYear","LastWeek","LastTenDays","LastMonth","LastQuarter","LastHalfYear","LastYear","NextDay","NextWeek","NextTenDays","NextMonth","NextQuarter","NextHalfYear","NextYear","TillEndOfThisWeek","TillEndOfThisTenDays","TillEndOfThisMonth","TillEndOfThisQuarter","TillEndOfThisHalfYear","TillEndOfThisYear")
		if ($periodVariants -contains $valStr) {
			$result.value = @{ variant = $valStr }
		} elseif ($valStr -match '^\d{4}-\d{2}-\d{2}T') {
			$result.value = $valStr
		} elseif ($valStr -eq "true" -or $valStr -eq "false") {
			$result.value = $valStr
		} else {
			$result.value = $valStr
		}
	} else {
		$result.parameter = $s
	}

	return $result
}

function Parse-OrderShorthand {
	param([string]$s)
	$s = $s.Trim()
	if ($s -eq "Auto") {
		return @{ field = "Auto"; direction = "" }
	}
	$parts = $s -split '\s+', 2
	$field = $parts[0]
	$dir = "Asc"
	if ($parts.Count -gt 1 -and $parts[1] -match '(?i)^desc$') { $dir = "Desc" }
	return @{ field = $field; direction = $dir }
}

function Parse-OutputParamShorthand {
	param([string]$s)
	$idx = $s.IndexOf('=')
	if ($idx -gt 0) {
		return @{
			key = $s.Substring(0, $idx).Trim()
			value = $s.Substring($idx + 1).Trim()
		}
	}
	return @{ key = $s.Trim(); value = "" }
}

# --- 4. Build-* functions (XML fragment generators) ---

function Build-ValueTypeXml {
	param([string]$typeStr, [string]$indent)

	if (-not $typeStr) { return "" }
	$typeStr = Resolve-TypeStr $typeStr
	$lines = @()

	if ($typeStr -eq "boolean") {
		$lines += "$indent<v8:Type>xs:boolean</v8:Type>"
		return $lines -join "`r`n"
	}

	if ($typeStr -match '^string(\((\d+)\))?$') {
		$len = if ($Matches[2]) { $Matches[2] } else { "0" }
		$lines += "$indent<v8:Type>xs:string</v8:Type>"
		$lines += "$indent<v8:StringQualifiers>"
		$lines += "$indent`t<v8:Length>$len</v8:Length>"
		$lines += "$indent`t<v8:AllowedLength>Variable</v8:AllowedLength>"
		$lines += "$indent</v8:StringQualifiers>"
		return $lines -join "`r`n"
	}

	if ($typeStr -match '^decimal\((\d+),(\d+)(,nonneg)?\)$') {
		$digits = $Matches[1]
		$fraction = $Matches[2]
		$sign = if ($Matches[3]) { "Nonnegative" } else { "Any" }
		$lines += "$indent<v8:Type>xs:decimal</v8:Type>"
		$lines += "$indent<v8:NumberQualifiers>"
		$lines += "$indent`t<v8:Digits>$digits</v8:Digits>"
		$lines += "$indent`t<v8:FractionDigits>$fraction</v8:FractionDigits>"
		$lines += "$indent`t<v8:AllowedSign>$sign</v8:AllowedSign>"
		$lines += "$indent</v8:NumberQualifiers>"
		return $lines -join "`r`n"
	}

	if ($typeStr -match '^(date|dateTime)$') {
		$fractions = switch ($typeStr) {
			"date"     { "Date" }
			"dateTime" { "DateTime" }
		}
		$lines += "$indent<v8:Type>xs:dateTime</v8:Type>"
		$lines += "$indent<v8:DateQualifiers>"
		$lines += "$indent`t<v8:DateFractions>$fractions</v8:DateFractions>"
		$lines += "$indent</v8:DateQualifiers>"
		return $lines -join "`r`n"
	}

	if ($typeStr -eq "StandardPeriod") {
		$lines += "$indent<v8:Type>v8:StandardPeriod</v8:Type>"
		return $lines -join "`r`n"
	}

	if ($typeStr -match '^(CatalogRef|DocumentRef|EnumRef|ChartOfAccountsRef|ChartOfCharacteristicTypesRef)\.') {
		$lines += "$indent<v8:Type xmlns:d5p1=`"http://v8.1c.ru/8.1/data/enterprise/current-config`">d5p1:$(Esc-Xml $typeStr)</v8:Type>"
		return $lines -join "`r`n"
	}

	if ($typeStr.Contains('.')) {
		$lines += "$indent<v8:Type xmlns:d5p1=`"http://v8.1c.ru/8.1/data/enterprise/current-config`">d5p1:$(Esc-Xml $typeStr)</v8:Type>"
		return $lines -join "`r`n"
	}

	$lines += "$indent<v8:Type>$(Esc-Xml $typeStr)</v8:Type>"
	return $lines -join "`r`n"
}

function Build-MLTextXml {
	param([string]$tag, [string]$text, [string]$indent)
	$lines = @()
	$lines += "$indent<$tag xsi:type=`"v8:LocalStringType`">"
	$lines += "$indent`t<v8:item>"
	$lines += "$indent`t`t<v8:lang>ru</v8:lang>"
	$lines += "$indent`t`t<v8:content>$(Esc-Xml $text)</v8:content>"
	$lines += "$indent`t</v8:item>"
	$lines += "$indent</$tag>"
	return $lines -join "`r`n"
}

function Build-RoleXml {
	param([string[]]$roles, [string]$indent)

	if (-not $roles -or $roles.Count -eq 0) { return "" }

	$lines = @()
	$lines += "$indent<role>"
	foreach ($role in $roles) {
		if ($role -eq "period") {
			$lines += "$indent`t<dcscom:periodNumber>1</dcscom:periodNumber>"
			$lines += "$indent`t<dcscom:periodType>Main</dcscom:periodType>"
		} else {
			$lines += "$indent`t<dcscom:$role>true</dcscom:$role>"
		}
	}
	$lines += "$indent</role>"
	return $lines -join "`r`n"
}

function Build-RestrictionXml {
	param([string[]]$restrict, [string]$indent)

	if (-not $restrict -or $restrict.Count -eq 0) { return "" }

	$restrictMap = @{
		"noField" = "field"; "noFilter" = "condition"; "noCondition" = "condition"
		"noGroup" = "group"; "noOrder" = "order"
	}

	$lines = @()
	$lines += "$indent<useRestriction>"
	foreach ($r in $restrict) {
		$xmlName = $restrictMap["$r"]
		if ($xmlName) {
			$lines += "$indent`t<$xmlName>true</$xmlName>"
		}
	}
	$lines += "$indent</useRestriction>"
	return $lines -join "`r`n"
}

function Build-FieldFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$lines = @()
	$lines += "$i<field xsi:type=`"DataSetFieldField`">"
	$lines += "$i`t<dataPath>$(Esc-Xml $parsed.dataPath)</dataPath>"
	$lines += "$i`t<field>$(Esc-Xml $parsed.field)</field>"

	if ($parsed.title) {
		$lines += (Build-MLTextXml -tag "title" -text $parsed.title -indent "$i`t")
	}

	if ($parsed.restrict -and $parsed.restrict.Count -gt 0) {
		$lines += (Build-RestrictionXml -restrict $parsed.restrict -indent "$i`t")
	}

	$roleXml = Build-RoleXml -roles $parsed.roles -indent "$i`t"
	if ($roleXml) { $lines += $roleXml }

	if ($parsed.type) {
		$lines += "$i`t<valueType>"
		$lines += (Build-ValueTypeXml -typeStr $parsed.type -indent "$i`t`t")
		$lines += "$i`t</valueType>"
	}

	$lines += "$i</field>"
	return $lines -join "`r`n"
}

function Build-TotalFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$lines = @()
	$lines += "$i<totalField>"
	$lines += "$i`t<dataPath>$(Esc-Xml $parsed.dataPath)</dataPath>"
	$lines += "$i`t<expression>$(Esc-Xml $parsed.expression)</expression>"
	$lines += "$i</totalField>"
	return $lines -join "`r`n"
}

function Build-CalcFieldFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$lines = @()
	$lines += "$i<calculatedField>"
	$lines += "$i`t<dataPath>$(Esc-Xml $parsed.dataPath)</dataPath>"
	$lines += "$i`t<expression>$(Esc-Xml $parsed.expression)</expression>"

	if ($parsed.title) {
		$lines += (Build-MLTextXml -tag "title" -text $parsed.title -indent "$i`t")
	}

	if ($parsed.type) {
		$lines += "$i`t<valueType>"
		$lines += (Build-ValueTypeXml -typeStr $parsed.type -indent "$i`t`t")
		$lines += "$i`t</valueType>"
	}

	$lines += "$i</calculatedField>"
	return $lines -join "`r`n"
}

function Build-ParamFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$fragments = @()

	$lines = @()
	$lines += "$i<parameter>"
	$lines += "$i`t<name>$(Esc-Xml $parsed.name)</name>"

	if ($parsed.type) {
		$lines += "$i`t<valueType>"
		$lines += (Build-ValueTypeXml -typeStr $parsed.type -indent "$i`t`t")
		$lines += "$i`t</valueType>"
	}

	if ($null -ne $parsed.value) {
		$valStr = "$($parsed.value)"
		if ($parsed.type -eq "StandardPeriod") {
			$lines += "$i`t<value xsi:type=`"v8:StandardPeriod`">"
			$lines += "$i`t`t<v8:variant xsi:type=`"v8:StandardPeriodVariant`">$(Esc-Xml $valStr)</v8:variant>"
			$lines += "$i`t</value>"
		} elseif ($parsed.type -match '^date') {
			$lines += "$i`t<value xsi:type=`"xs:dateTime`">$(Esc-Xml $valStr)</value>"
		} elseif ($parsed.type -eq "boolean") {
			$lines += "$i`t<value xsi:type=`"xs:boolean`">$(Esc-Xml $valStr)</value>"
		} elseif ($parsed.type -match '^decimal') {
			$lines += "$i`t<value xsi:type=`"xs:decimal`">$(Esc-Xml $valStr)</value>"
		} else {
			$lines += "$i`t<value xsi:type=`"xs:string`">$(Esc-Xml $valStr)</value>"
		}
	}

	$lines += "$i</parameter>"
	$fragments += ($lines -join "`r`n")

	if ($parsed.autoDates) {
		$paramName = $parsed.name

		$bLines = @()
		$bLines += "$i<parameter>"
		$bLines += "$i`t<name>ДатаНачала</name>"
		$bLines += "$i`t<valueType>"
		$bLines += (Build-ValueTypeXml -typeStr "date" -indent "$i`t`t")
		$bLines += "$i`t</valueType>"
		$bLines += "$i`t<expression>$(Esc-Xml "&$paramName.ДатаНачала")</expression>"
		$bLines += "$i`t<availableAsField>false</availableAsField>"
		$bLines += "$i</parameter>"
		$fragments += ($bLines -join "`r`n")

		$eLines = @()
		$eLines += "$i<parameter>"
		$eLines += "$i`t<name>ДатаОкончания</name>"
		$eLines += "$i`t<valueType>"
		$eLines += (Build-ValueTypeXml -typeStr "date" -indent "$i`t`t")
		$eLines += "$i`t</valueType>"
		$eLines += "$i`t<expression>$(Esc-Xml "&$paramName.ДатаОкончания")</expression>"
		$eLines += "$i`t<availableAsField>false</availableAsField>"
		$eLines += "$i</parameter>"
		$fragments += ($eLines -join "`r`n")
	}

	return ,$fragments
}

function Build-FilterItemFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$lines = @()
	$lines += "$i<dcsset:item xsi:type=`"dcsset:FilterItemComparison`">"

	if ($parsed.use -eq $false) {
		$lines += "$i`t<dcsset:use>false</dcsset:use>"
	}

	$lines += "$i`t<dcsset:left xsi:type=`"dcscor:Field`">$(Esc-Xml $parsed.field)</dcsset:left>"
	$lines += "$i`t<dcsset:comparisonType>$(Esc-Xml $parsed.op)</dcsset:comparisonType>"

	if ($null -ne $parsed.value) {
		$vt = if ($parsed["valueType"]) { $parsed["valueType"] } else { "xs:string" }
		$lines += "$i`t<dcsset:right xsi:type=`"$vt`">$(Esc-Xml "$($parsed.value)")</dcsset:right>"
	}

	if ($parsed.viewMode) {
		$lines += "$i`t<dcsset:viewMode>$(Esc-Xml $parsed.viewMode)</dcsset:viewMode>"
	}

	if ($parsed.userSettingID) {
		$uid = if ($parsed.userSettingID -eq "auto") { [System.Guid]::NewGuid().ToString() } else { $parsed.userSettingID }
		$lines += "$i`t<dcsset:userSettingID>$(Esc-Xml $uid)</dcsset:userSettingID>"
	}

	$lines += "$i</dcsset:item>"
	return $lines -join "`r`n"
}

function Build-SelectionItemFragment {
	param([string]$fieldName, [string]$indent)

	$i = $indent
	$lines = @()
	if ($fieldName -eq "Auto") {
		$lines += "$i<dcsset:item xsi:type=`"dcsset:SelectedItemAuto`"/>"
	} else {
		$lines += "$i<dcsset:item xsi:type=`"dcsset:SelectedItemField`">"
		$lines += "$i`t<dcsset:field>$(Esc-Xml $fieldName)</dcsset:field>"
		$lines += "$i</dcsset:item>"
	}
	return $lines -join "`r`n"
}

function Build-DataParamFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$lines = @()
	$lines += "$i<dcscor:item xsi:type=`"dcsset:SettingsParameterValue`">"

	if ($parsed.use -eq $false) {
		$lines += "$i`t<dcscor:use>false</dcscor:use>"
	}

	$lines += "$i`t<dcscor:parameter>$(Esc-Xml $parsed.parameter)</dcscor:parameter>"

	if ($null -ne $parsed.value) {
		if ($parsed.value -is [hashtable] -and $parsed.value.variant) {
			$lines += "$i`t<dcscor:value xsi:type=`"v8:StandardPeriod`">"
			$lines += "$i`t`t<v8:variant xsi:type=`"v8:StandardPeriodVariant`">$(Esc-Xml $parsed.value.variant)</v8:variant>"
			$lines += "$i`t</dcscor:value>"
		} elseif ("$($parsed.value)" -match '^\d{4}-\d{2}-\d{2}T') {
			$lines += "$i`t<dcscor:value xsi:type=`"xs:dateTime`">$(Esc-Xml "$($parsed.value)")</dcscor:value>"
		} elseif ("$($parsed.value)" -eq "true" -or "$($parsed.value)" -eq "false") {
			$lines += "$i`t<dcscor:value xsi:type=`"xs:boolean`">$(Esc-Xml "$($parsed.value)")</dcscor:value>"
		} else {
			$lines += "$i`t<dcscor:value xsi:type=`"xs:string`">$(Esc-Xml "$($parsed.value)")</dcscor:value>"
		}
	}

	if ($parsed.viewMode) {
		$lines += "$i`t<dcsset:viewMode>$(Esc-Xml $parsed.viewMode)</dcsset:viewMode>"
	}

	if ($parsed.userSettingID) {
		$uid = if ($parsed.userSettingID -eq "auto") { [System.Guid]::NewGuid().ToString() } else { $parsed.userSettingID }
		$lines += "$i`t<dcsset:userSettingID>$(Esc-Xml $uid)</dcsset:userSettingID>"
	}

	$lines += "$i</dcscor:item>"
	return $lines -join "`r`n"
}

function Build-OrderItemFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$lines = @()
	if ($parsed.field -eq "Auto") {
		$lines += "$i<dcsset:item xsi:type=`"dcsset:OrderItemAuto`"/>"
	} else {
		$lines += "$i<dcsset:item xsi:type=`"dcsset:OrderItemField`">"
		$lines += "$i`t<dcsset:field>$(Esc-Xml $parsed.field)</dcsset:field>"
		$lines += "$i`t<dcsset:orderType>$($parsed.direction)</dcsset:orderType>"
		$lines += "$i</dcsset:item>"
	}
	return $lines -join "`r`n"
}

function Build-OutputParamFragment {
	param($parsed, [string]$indent)

	$i = $indent
	$key = $parsed.key
	$val = $parsed.value
	$ptype = $script:outputParamTypes[$key]
	if (-not $ptype) { $ptype = "xs:string" }

	$lines = @()
	$lines += "$i<dcscor:item xsi:type=`"dcsset:SettingsParameterValue`">"
	$lines += "$i`t<dcscor:parameter>$(Esc-Xml $key)</dcscor:parameter>"

	if ($ptype -eq "mltext") {
		$lines += "$i`t<dcscor:value xsi:type=`"v8:LocalStringType`">"
		$lines += "$i`t`t<v8:item>"
		$lines += "$i`t`t`t<v8:lang>ru</v8:lang>"
		$lines += "$i`t`t`t<v8:content>$(Esc-Xml $val)</v8:content>"
		$lines += "$i`t`t</v8:item>"
		$lines += "$i`t</dcscor:value>"
	} else {
		$lines += "$i`t<dcscor:value xsi:type=`"$ptype`">$(Esc-Xml $val)</dcscor:value>"
	}

	$lines += "$i</dcscor:item>"
	return $lines -join "`r`n"
}

# --- 5. XML helpers ---

function Import-Fragment($doc, [string]$xmlString) {
	$wrapper = @"
<_W xmlns="http://v8.1c.ru/8.1/data-composition-system/schema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:v8="http://v8.1c.ru/8.1/data/core"
    xmlns:dcscom="http://v8.1c.ru/8.1/data-composition-system/common"
    xmlns:dcscor="http://v8.1c.ru/8.1/data-composition-system/core"
    xmlns:dcsset="http://v8.1c.ru/8.1/data-composition-system/settings"
    xmlns:v8ui="http://v8.1c.ru/8.1/data/ui">$xmlString</_W>
"@
	$frag = New-Object System.Xml.XmlDocument
	$frag.PreserveWhitespace = $true
	$frag.LoadXml($wrapper)
	$nodes = @()
	foreach ($child in $frag.DocumentElement.ChildNodes) {
		if ($child.NodeType -eq 'Element') {
			$nodes += $doc.ImportNode($child, $true)
		}
	}
	return ,$nodes
}

function Get-ChildIndent($container) {
	foreach ($child in $container.ChildNodes) {
		if ($child.NodeType -eq 'Whitespace' -or $child.NodeType -eq 'SignificantWhitespace') {
			$text = $child.Value
			if ($text -match '^\r?\n(\t+)$') { return $Matches[1] }
			if ($text -match '^\r?\n(\t+)') { return $Matches[1] }
		}
	}
	$depth = 0
	$current = $container
	while ($current -and $current -ne $xmlDoc.DocumentElement) {
		$depth++
		$current = $current.ParentNode
	}
	return "`t" * ($depth + 1)
}

function Insert-BeforeElement($container, $newNode, $refNode, $childIndent) {
	$ws = $xmlDoc.CreateWhitespace("`r`n$childIndent")
	if ($refNode) {
		$container.InsertBefore($ws, $refNode) | Out-Null
		$container.InsertBefore($newNode, $ws) | Out-Null
	} else {
		$trailing = $container.LastChild
		if ($trailing -and ($trailing.NodeType -eq 'Whitespace' -or $trailing.NodeType -eq 'SignificantWhitespace')) {
			$container.InsertBefore($ws, $trailing) | Out-Null
			$container.InsertBefore($newNode, $ws) | Out-Null
		} else {
			$container.AppendChild($ws) | Out-Null
			$container.AppendChild($newNode) | Out-Null
			$parentIndent = if ($childIndent.Length -gt 1) { $childIndent.Substring(0, $childIndent.Length - 1) } else { "" }
			$closeWs = $xmlDoc.CreateWhitespace("`r`n$parentIndent")
			$container.AppendChild($closeWs) | Out-Null
		}
	}
}

function Remove-NodeWithWhitespace($node) {
	$parent = $node.ParentNode
	$prev = $node.PreviousSibling
	$next = $node.NextSibling

	if ($prev -and ($prev.NodeType -eq 'Whitespace' -or $prev.NodeType -eq 'SignificantWhitespace')) {
		$parent.RemoveChild($prev) | Out-Null
	} elseif ($next -and ($next.NodeType -eq 'Whitespace' -or $next.NodeType -eq 'SignificantWhitespace')) {
		$parent.RemoveChild($next) | Out-Null
	}
	$parent.RemoveChild($node) | Out-Null
}

function Find-FirstElement($container, [string[]]$localNames, [string]$nsUri) {
	foreach ($child in $container.ChildNodes) {
		if ($child.NodeType -eq 'Element') {
			foreach ($name in $localNames) {
				if ($child.LocalName -eq $name) {
					if (-not $nsUri -or $child.NamespaceURI -eq $nsUri) {
						return $child
					}
				}
			}
		}
	}
	return $null
}

function Find-LastElement($container, [string]$localName, [string]$nsUri) {
	$last = $null
	foreach ($child in $container.ChildNodes) {
		if ($child.NodeType -eq 'Element' -and $child.LocalName -eq $localName) {
			if (-not $nsUri -or $child.NamespaceURI -eq $nsUri) {
				$last = $child
			}
		}
	}
	return $last
}

function Find-ElementByChildValue($container, [string]$elemName, [string]$childName, [string]$childValue, [string]$nsUri) {
	foreach ($child in $container.ChildNodes) {
		if ($child.NodeType -ne 'Element') { continue }
		if ($child.LocalName -ne $elemName) { continue }
		if ($nsUri -and $child.NamespaceURI -ne $nsUri) { continue }

		foreach ($gc in $child.ChildNodes) {
			if ($gc.NodeType -eq 'Element' -and $gc.LocalName -eq $childName -and $gc.InnerText.Trim() -eq $childValue) {
				return $child
			}
		}
	}
	return $null
}

function Resolve-DataSet {
	$schNs = "http://v8.1c.ru/8.1/data-composition-system/schema"
	$root = $xmlDoc.DocumentElement

	if ($DataSet) {
		foreach ($child in $root.ChildNodes) {
			if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'dataSet' -and $child.NamespaceURI -eq $schNs) {
				$nameEl = $null
				foreach ($gc in $child.ChildNodes) {
					if ($gc.NodeType -eq 'Element' -and $gc.LocalName -eq 'name' -and $gc.NamespaceURI -eq $schNs) {
						$nameEl = $gc
						break
					}
				}
				if ($nameEl -and $nameEl.InnerText -eq $DataSet) {
					return $child
				}
			}
		}
		Write-Error "DataSet '$DataSet' not found"
		exit 1
	}

	foreach ($child in $root.ChildNodes) {
		if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'dataSet' -and $child.NamespaceURI -eq $schNs) {
			return $child
		}
	}
	Write-Error "No dataSet found in DCS"
	exit 1
}

function Resolve-VariantSettings {
	$schNs = "http://v8.1c.ru/8.1/data-composition-system/schema"
	$setNs = "http://v8.1c.ru/8.1/data-composition-system/settings"
	$root = $xmlDoc.DocumentElement

	$sv = $null
	if ($Variant) {
		foreach ($child in $root.ChildNodes) {
			if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'settingsVariant' -and $child.NamespaceURI -eq $schNs) {
				$nameEl = $null
				foreach ($gc in $child.ChildNodes) {
					if ($gc.NodeType -eq 'Element' -and $gc.LocalName -eq 'name' -and $gc.NamespaceURI -eq $setNs) {
						$nameEl = $gc
						break
					}
				}
				if ($nameEl -and $nameEl.InnerText -eq $Variant) {
					$sv = $child
					break
				}
			}
		}
		if (-not $sv) {
			Write-Error "Variant '$Variant' not found"
			exit 1
		}
	} else {
		foreach ($child in $root.ChildNodes) {
			if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'settingsVariant' -and $child.NamespaceURI -eq $schNs) {
				$sv = $child
				break
			}
		}
		if (-not $sv) {
			Write-Error "No settingsVariant found in DCS"
			exit 1
		}
	}

	foreach ($gc in $sv.ChildNodes) {
		if ($gc.NodeType -eq 'Element' -and $gc.LocalName -eq 'settings' -and $gc.NamespaceURI -eq $setNs) {
			return $gc
		}
	}

	Write-Error "No <dcsset:settings> found in variant"
	exit 1
}

function Ensure-SettingsChild($settings, [string]$childName, [string[]]$afterSiblings) {
	$el = Find-FirstElement $settings @($childName) $setNs
	if ($el) { return $el }

	$indent = Get-ChildIndent $settings
	$fragXml = "$indent<dcsset:$childName/>"
	$nodes = Import-Fragment $xmlDoc $fragXml

	$refNode = $null
	foreach ($sibName in $afterSiblings) {
		$sib = Find-FirstElement $settings @($sibName) $setNs
		if ($sib) {
			$refNode = $sib.NextSibling
			while ($refNode -and ($refNode.NodeType -eq 'Whitespace' -or $refNode.NodeType -eq 'SignificantWhitespace')) {
				$refNode = $refNode.NextSibling
			}
			break
		}
	}

	foreach ($node in $nodes) {
		Insert-BeforeElement $settings $node $refNode $indent
	}

	return Find-FirstElement $settings @($childName) $setNs
}

function Get-VariantName {
	$schNs = "http://v8.1c.ru/8.1/data-composition-system/schema"
	$setNs = "http://v8.1c.ru/8.1/data-composition-system/settings"
	$root = $xmlDoc.DocumentElement

	if ($Variant) { return $Variant }

	foreach ($child in $root.ChildNodes) {
		if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'settingsVariant' -and $child.NamespaceURI -eq $schNs) {
			foreach ($gc in $child.ChildNodes) {
				if ($gc.NodeType -eq 'Element' -and $gc.LocalName -eq 'name' -and $gc.NamespaceURI -eq $setNs) {
					return $gc.InnerText
				}
			}
		}
	}
	return "(unknown)"
}

function Get-DataSetName($dsNode) {
	$schNs = "http://v8.1c.ru/8.1/data-composition-system/schema"
	foreach ($gc in $dsNode.ChildNodes) {
		if ($gc.NodeType -eq 'Element' -and $gc.LocalName -eq 'name' -and $gc.NamespaceURI -eq $schNs) {
			return $gc.InnerText
		}
	}
	return "(unknown)"
}

function Get-ContainerChildIndent($container) {
	$ci = Get-ChildIndent $container
	if (-not $container.HasChildNodes) {
		$settingsIndent = Get-ChildIndent $container.ParentNode
		$ci = $settingsIndent + "`t"
	}
	return $ci
}

# --- 6. Load XML ---

$xmlDoc = New-Object System.Xml.XmlDocument
$xmlDoc.PreserveWhitespace = $true
$xmlDoc.Load($resolvedPath)

$schNs = "http://v8.1c.ru/8.1/data-composition-system/schema"
$setNs = "http://v8.1c.ru/8.1/data-composition-system/settings"
$corNs = "http://v8.1c.ru/8.1/data-composition-system/core"

# --- 7. Batch value splitting ---

if ($Operation -eq "set-query") {
	$values = @($Value)
} else {
	$values = @($Value -split ';;' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# --- 8. Main logic ---

switch ($Operation) {
	"add-field" {
		$dsNode = Resolve-DataSet
		$dsName = Get-DataSetName $dsNode

		foreach ($val in $values) {
			$parsed = Parse-FieldShorthand $val
			$childIndent = Get-ChildIndent $dsNode

			# Duplicate check
			$existing = Find-ElementByChildValue $dsNode "field" "dataPath" $parsed.dataPath $schNs
			if ($existing) {
				Write-Host "[WARN] Field `"$($parsed.dataPath)`" already exists in dataset `"$dsName`" — skipped"
				continue
			}

			$fragXml = Build-FieldFragment -parsed $parsed -indent $childIndent
			$nodes = Import-Fragment $xmlDoc $fragXml

			$refNode = Find-FirstElement $dsNode @("dataSource") $schNs
			foreach ($node in $nodes) {
				Insert-BeforeElement $dsNode $node $refNode $childIndent
			}

			Write-Host "[OK] Field `"$($parsed.dataPath)`" added to dataset `"$dsName`""

			if (-not $NoSelection) {
				$settings = Resolve-VariantSettings
				$varName = Get-VariantName
				$selection = Ensure-SettingsChild $settings "selection" @()
				$selIndent = Get-ContainerChildIndent $selection
				$selXml = Build-SelectionItemFragment -fieldName $parsed.dataPath -indent $selIndent
				$selNodes = Import-Fragment $xmlDoc $selXml
				foreach ($node in $selNodes) {
					Insert-BeforeElement $selection $node $null $selIndent
				}
				Write-Host "[OK] Field `"$($parsed.dataPath)`" added to selection of variant `"$varName`""
			}
		}
	}

	"add-total" {
		foreach ($val in $values) {
			$parsed = Parse-TotalShorthand $val
			$childIndent = Get-ChildIndent $xmlDoc.DocumentElement

			# Duplicate check
			$existing = Find-ElementByChildValue $xmlDoc.DocumentElement "totalField" "dataPath" $parsed.dataPath $schNs
			if ($existing) {
				Write-Host "[WARN] TotalField `"$($parsed.dataPath)`" already exists — skipped"
				continue
			}

			$fragXml = Build-TotalFragment -parsed $parsed -indent $childIndent
			$nodes = Import-Fragment $xmlDoc $fragXml

			$root = $xmlDoc.DocumentElement
			$lastTotal = Find-LastElement $root "totalField" $schNs
			if ($lastTotal) {
				$refNode = $lastTotal.NextSibling
				while ($refNode -and ($refNode.NodeType -eq 'Whitespace' -or $refNode.NodeType -eq 'SignificantWhitespace')) {
					$refNode = $refNode.NextSibling
				}
			} else {
				$refNode = Find-FirstElement $root @("parameter","template","groupTemplate","settingsVariant") $schNs
			}

			foreach ($node in $nodes) {
				Insert-BeforeElement $root $node $refNode $childIndent
			}

			Write-Host "[OK] TotalField `"$($parsed.dataPath)`" = $($parsed.expression) added"
		}
	}

	"add-calculated-field" {
		foreach ($val in $values) {
			$parsed = Parse-CalcShorthand $val
			$childIndent = Get-ChildIndent $xmlDoc.DocumentElement

			# Duplicate check
			$existing = Find-ElementByChildValue $xmlDoc.DocumentElement "calculatedField" "dataPath" $parsed.dataPath $schNs
			if ($existing) {
				Write-Host "[WARN] CalculatedField `"$($parsed.dataPath)`" already exists — skipped"
				continue
			}

			$fragXml = Build-CalcFieldFragment -parsed $parsed -indent $childIndent
			$nodes = Import-Fragment $xmlDoc $fragXml

			$root = $xmlDoc.DocumentElement
			$lastCalc = Find-LastElement $root "calculatedField" $schNs
			if ($lastCalc) {
				$refNode = $lastCalc.NextSibling
				while ($refNode -and ($refNode.NodeType -eq 'Whitespace' -or $refNode.NodeType -eq 'SignificantWhitespace')) {
					$refNode = $refNode.NextSibling
				}
			} else {
				$refNode = Find-FirstElement $root @("totalField","parameter","template","groupTemplate","settingsVariant") $schNs
			}

			foreach ($node in $nodes) {
				Insert-BeforeElement $root $node $refNode $childIndent
			}

			Write-Host "[OK] CalculatedField `"$($parsed.dataPath)`" = $($parsed.expression) added"

			if (-not $NoSelection) {
				$settings = Resolve-VariantSettings
				$varName = Get-VariantName
				$selection = Ensure-SettingsChild $settings "selection" @()
				$selIndent = Get-ContainerChildIndent $selection
				$selXml = Build-SelectionItemFragment -fieldName $parsed.dataPath -indent $selIndent
				$selNodes = Import-Fragment $xmlDoc $selXml
				foreach ($node in $selNodes) {
					Insert-BeforeElement $selection $node $null $selIndent
				}
				Write-Host "[OK] Field `"$($parsed.dataPath)`" added to selection of variant `"$varName`""
			}
		}
	}

	"add-parameter" {
		foreach ($val in $values) {
			$parsed = Parse-ParamShorthand $val
			$childIndent = Get-ChildIndent $xmlDoc.DocumentElement

			# Duplicate check
			$existing = Find-ElementByChildValue $xmlDoc.DocumentElement "parameter" "name" $parsed.name $schNs
			if ($existing) {
				Write-Host "[WARN] Parameter `"$($parsed.name)`" already exists — skipped"
				continue
			}

			$fragments = Build-ParamFragment -parsed $parsed -indent $childIndent

			$root = $xmlDoc.DocumentElement
			$lastParam = Find-LastElement $root "parameter" $schNs
			if ($lastParam) {
				$refNode = $lastParam.NextSibling
				while ($refNode -and ($refNode.NodeType -eq 'Whitespace' -or $refNode.NodeType -eq 'SignificantWhitespace')) {
					$refNode = $refNode.NextSibling
				}
			} else {
				$refNode = Find-FirstElement $root @("template","groupTemplate","settingsVariant") $schNs
			}

			foreach ($fragXml in $fragments) {
				$nodes = Import-Fragment $xmlDoc $fragXml
				foreach ($node in $nodes) {
					Insert-BeforeElement $root $node $refNode $childIndent
				}
			}

			Write-Host "[OK] Parameter `"$($parsed.name)`" added"
			if ($parsed.autoDates) {
				Write-Host "[OK] Auto-parameters `"ДатаНачала`", `"ДатаОкончания`" added"
			}
		}
	}

	"add-filter" {
		$settings = Resolve-VariantSettings
		$varName = Get-VariantName

		foreach ($val in $values) {
			$parsed = Parse-FilterShorthand $val

			$filterEl = Ensure-SettingsChild $settings "filter" @("selection")
			$filterIndent = Get-ContainerChildIndent $filterEl

			$fragXml = Build-FilterItemFragment -parsed $parsed -indent $filterIndent
			$nodes = Import-Fragment $xmlDoc $fragXml
			foreach ($node in $nodes) {
				Insert-BeforeElement $filterEl $node $null $filterIndent
			}

			Write-Host "[OK] Filter `"$($parsed.field) $($parsed.op)`" added to variant `"$varName`""
		}
	}

	"add-dataParameter" {
		$settings = Resolve-VariantSettings
		$varName = Get-VariantName

		foreach ($val in $values) {
			$parsed = Parse-DataParamShorthand $val

			$dpEl = Ensure-SettingsChild $settings "dataParameters" @("outputParameters","conditionalAppearance","order","filter","selection")
			$dpIndent = Get-ContainerChildIndent $dpEl

			$fragXml = Build-DataParamFragment -parsed $parsed -indent $dpIndent
			$nodes = Import-Fragment $xmlDoc $fragXml
			foreach ($node in $nodes) {
				Insert-BeforeElement $dpEl $node $null $dpIndent
			}

			Write-Host "[OK] DataParameter `"$($parsed.parameter)`" added to variant `"$varName`""
		}
	}

	"add-order" {
		$settings = Resolve-VariantSettings
		$varName = Get-VariantName

		foreach ($val in $values) {
			$parsed = Parse-OrderShorthand $val

			$orderEl = Ensure-SettingsChild $settings "order" @("filter","selection")
			$orderIndent = Get-ContainerChildIndent $orderEl

			$fragXml = Build-OrderItemFragment -parsed $parsed -indent $orderIndent
			$nodes = Import-Fragment $xmlDoc $fragXml
			foreach ($node in $nodes) {
				Insert-BeforeElement $orderEl $node $null $orderIndent
			}

			$desc = if ($parsed.field -eq "Auto") { "Auto" } else { "$($parsed.field) $($parsed.direction)" }
			Write-Host "[OK] Order `"$desc`" added to variant `"$varName`""
		}
	}

	"add-selection" {
		$settings = Resolve-VariantSettings
		$varName = Get-VariantName

		foreach ($val in $values) {
			$fieldName = $val.Trim()

			$selection = Ensure-SettingsChild $settings "selection" @()
			$selIndent = Get-ContainerChildIndent $selection

			$selXml = Build-SelectionItemFragment -fieldName $fieldName -indent $selIndent
			$selNodes = Import-Fragment $xmlDoc $selXml
			foreach ($node in $selNodes) {
				Insert-BeforeElement $selection $node $null $selIndent
			}

			Write-Host "[OK] Selection `"$fieldName`" added to variant `"$varName`""
		}
	}

	"set-query" {
		$dsNode = Resolve-DataSet
		$dsName = Get-DataSetName $dsNode

		$queryEl = Find-FirstElement $dsNode @("query") $schNs
		if (-not $queryEl) {
			Write-Error "No <query> element found in dataset '$dsName'"
			exit 1
		}

		# InnerText setter handles XML escaping automatically
		$queryEl.InnerText = $Value

		Write-Host "[OK] Query replaced in dataset `"$dsName`""
	}

	"set-outputParameter" {
		$settings = Resolve-VariantSettings
		$varName = Get-VariantName

		foreach ($val in $values) {
			$parsed = Parse-OutputParamShorthand $val

			$outputEl = Ensure-SettingsChild $settings "outputParameters" @("conditionalAppearance","order","filter","selection")
			$outputIndent = Get-ContainerChildIndent $outputEl

			# Remove existing parameter with same key if present
			$existingParam = Find-ElementByChildValue $outputEl "item" "parameter" $parsed.key $corNs
			if ($existingParam) {
				Remove-NodeWithWhitespace $existingParam
				Write-Host "[OK] Replaced outputParameter `"$($parsed.key)`" in variant `"$varName`""
			} else {
				Write-Host "[OK] OutputParameter `"$($parsed.key)`" added to variant `"$varName`""
			}

			$fragXml = Build-OutputParamFragment -parsed $parsed -indent $outputIndent
			$nodes = Import-Fragment $xmlDoc $fragXml
			foreach ($node in $nodes) {
				Insert-BeforeElement $outputEl $node $null $outputIndent
			}
		}
	}

	"remove-field" {
		$dsNode = Resolve-DataSet
		$dsName = Get-DataSetName $dsNode

		foreach ($val in $values) {
			$fieldName = $val.Trim()

			$fieldEl = Find-ElementByChildValue $dsNode "field" "dataPath" $fieldName $schNs
			if (-not $fieldEl) {
				Write-Host "[WARN] Field `"$fieldName`" not found in dataset `"$dsName`""
				continue
			}

			Remove-NodeWithWhitespace $fieldEl
			Write-Host "[OK] Field `"$fieldName`" removed from dataset `"$dsName`""

			# Also remove from selection in variant
			try {
				$settings = Resolve-VariantSettings
				$varName = Get-VariantName
				$selection = Find-FirstElement $settings @("selection") $setNs
				if ($selection) {
					$selItem = Find-ElementByChildValue $selection "item" "field" $fieldName $setNs
					if ($selItem) {
						Remove-NodeWithWhitespace $selItem
						Write-Host "[OK] Field `"$fieldName`" removed from selection of variant `"$varName`""
					}
				}
			} catch {
				# No variant — that's fine
			}
		}
	}

	"remove-total" {
		foreach ($val in $values) {
			$dataPath = $val.Trim()
			$root = $xmlDoc.DocumentElement

			$totalEl = Find-ElementByChildValue $root "totalField" "dataPath" $dataPath $schNs
			if (-not $totalEl) {
				Write-Host "[WARN] TotalField `"$dataPath`" not found"
				continue
			}

			Remove-NodeWithWhitespace $totalEl
			Write-Host "[OK] TotalField `"$dataPath`" removed"
		}
	}

	"remove-calculated-field" {
		foreach ($val in $values) {
			$dataPath = $val.Trim()
			$root = $xmlDoc.DocumentElement

			$calcEl = Find-ElementByChildValue $root "calculatedField" "dataPath" $dataPath $schNs
			if (-not $calcEl) {
				Write-Host "[WARN] CalculatedField `"$dataPath`" not found"
				continue
			}

			Remove-NodeWithWhitespace $calcEl
			Write-Host "[OK] CalculatedField `"$dataPath`" removed"

			# Also remove from selection
			try {
				$settings = Resolve-VariantSettings
				$varName = Get-VariantName
				$selection = Find-FirstElement $settings @("selection") $setNs
				if ($selection) {
					$selItem = Find-ElementByChildValue $selection "item" "field" $dataPath $setNs
					if ($selItem) {
						Remove-NodeWithWhitespace $selItem
						Write-Host "[OK] Field `"$dataPath`" removed from selection of variant `"$varName`""
					}
				}
			} catch { }
		}
	}

	"remove-parameter" {
		foreach ($val in $values) {
			$paramName = $val.Trim()
			$root = $xmlDoc.DocumentElement

			$paramEl = Find-ElementByChildValue $root "parameter" "name" $paramName $schNs
			if (-not $paramEl) {
				Write-Host "[WARN] Parameter `"$paramName`" not found"
				continue
			}

			Remove-NodeWithWhitespace $paramEl
			Write-Host "[OK] Parameter `"$paramName`" removed"
		}
	}

	"remove-filter" {
		$settings = Resolve-VariantSettings
		$varName = Get-VariantName

		foreach ($val in $values) {
			$fieldName = $val.Trim()

			$filterEl = Find-FirstElement $settings @("filter") $setNs
			if (-not $filterEl) {
				Write-Host "[WARN] No filter section in variant `"$varName`""
				continue
			}

			$filterItem = Find-ElementByChildValue $filterEl "item" "left" $fieldName $setNs
			if (-not $filterItem) {
				Write-Host "[WARN] Filter for `"$fieldName`" not found in variant `"$varName`""
				continue
			}

			Remove-NodeWithWhitespace $filterItem
			Write-Host "[OK] Filter for `"$fieldName`" removed from variant `"$varName`""
		}
	}
}

# --- 9. Save ---

$content = $xmlDoc.OuterXml
$content = $content -replace '(?<=<\?xml[^?]*encoding=")utf-8(?=")', 'UTF-8'
$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($resolvedPath, $content, $enc)

Write-Host "[OK] Saved $resolvedPath"
