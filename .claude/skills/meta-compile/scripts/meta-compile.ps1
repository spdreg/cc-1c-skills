# meta-compile v1.0 — Compile 1C metadata object from JSON
param(
	[Parameter(Mandatory)]
	[string]$JsonPath,

	[Parameter(Mandatory)]
	[string]$OutputDir
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 1. Load and validate JSON ---

if (-not (Test-Path $JsonPath)) {
	Write-Error "File not found: $JsonPath"
	exit 1
}

$json = Get-Content -Raw -Encoding UTF8 $JsonPath
$def = $json | ConvertFrom-Json

# Object type synonyms (Russian → English)
$script:objectTypeSynonyms = @{
	"Справочник"       = "Catalog"
	"Документ"         = "Document"
	"Перечисление"     = "Enum"
	"Константа"        = "Constant"
	"РегистрСведений"  = "InformationRegister"
	"РегистрНакопления"= "AccumulationRegister"
}

if (-not $def.type) {
	Write-Error "JSON must have 'type' field"
	exit 1
}

# Resolve type synonym
$objType = "$($def.type)"
if ($script:objectTypeSynonyms.ContainsKey($objType)) {
	$objType = $script:objectTypeSynonyms[$objType]
}

$validTypes = @("Catalog","Document","Enum","Constant","InformationRegister","AccumulationRegister")
if ($objType -notin $validTypes) {
	Write-Error "Unsupported type: $objType. Valid: $($validTypes -join ', ')"
	exit 1
}

if (-not $def.name) {
	Write-Error "JSON must have 'name' field"
	exit 1
}

$objName = "$($def.name)"

# --- 2. XML helpers ---

$script:xml = New-Object System.Text.StringBuilder 32768

function X {
	param([string]$text)
	$script:xml.AppendLine($text) | Out-Null
}

function Esc-Xml {
	param([string]$s)
	return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

function Emit-MLText {
	param([string]$indent, [string]$tag, [string]$text)
	if (-not $text) {
		X "$indent<$tag/>"
		return
	}
	X "$indent<$tag>"
	X "$indent`t<v8:item>"
	X "$indent`t`t<v8:lang>ru</v8:lang>"
	X "$indent`t`t<v8:content>$(Esc-Xml $text)</v8:content>"
	X "$indent`t</v8:item>"
	X "$indent</$tag>"
}

function New-Guid-String {
	return [System.Guid]::NewGuid().ToString()
}

# --- 3. CamelCase splitter ---

function Split-CamelCase {
	param([string]$name)
	if (-not $name) { return $name }
	# Insert space before uppercase that follows lowercase (Cyrillic + Latin)
	$result = [regex]::Replace($name, '([а-яё])([А-ЯЁ])', '$1 $2')
	$result = [regex]::Replace($result, '([a-z])([A-Z])', '$1 $2')
	# Lowercase all but first character of the result
	if ($result.Length -gt 1) {
		$result = $result.Substring(0,1) + $result.Substring(1).ToLower()
	}
	return $result
}

# Auto-synonym
$synonym = if ($def.synonym) { "$($def.synonym)" } else { Split-CamelCase $objName }
$comment = if ($def.comment) { "$($def.comment)" } else { "" }

# --- 4. Type system ---

$script:typeSynonyms = New-Object System.Collections.Hashtable
$script:typeSynonyms["число"]    = "Number"
$script:typeSynonyms["строка"]   = "String"
$script:typeSynonyms["булево"]   = "Boolean"
$script:typeSynonyms["дата"]     = "Date"
$script:typeSynonyms["датавремя"]= "DateTime"
$script:typeSynonyms["number"]   = "Number"
$script:typeSynonyms["string"]   = "String"
$script:typeSynonyms["boolean"]  = "Boolean"
$script:typeSynonyms["date"]     = "Date"
$script:typeSynonyms["datetime"] = "DateTime"
$script:typeSynonyms["bool"]     = "Boolean"
# Reference synonyms (Russian, lowercase)
$script:typeSynonyms["справочникссылка"]             = "CatalogRef"
$script:typeSynonyms["документссылка"]               = "DocumentRef"
$script:typeSynonyms["перечислениессылка"]            = "EnumRef"
$script:typeSynonyms["плансчетовссылка"]              = "ChartOfAccountsRef"
$script:typeSynonyms["планвидовхарактеристикссылка"]  = "ChartOfCharacteristicTypesRef"
$script:typeSynonyms["определяемыйтип"]              = "DefinedType"
$script:typeSynonyms["definedtype"]                   = "DefinedType"

function Resolve-TypeStr {
	param([string]$typeStr)
	if (-not $typeStr) { return $typeStr }

	# Check for parameterized types: Number(15,2), Строка(100), etc.
	if ($typeStr -match '^([^(]+)\((.+)\)$') {
		$baseName = $Matches[1].Trim()
		$params = $Matches[2]
		$resolved = $script:typeSynonyms[$baseName.ToLower()]
		if ($resolved) { return "$resolved($params)" }
		return $typeStr
	}

	# Check for reference types: СправочникСсылка.Организации → CatalogRef.Организации
	if ($typeStr.Contains('.')) {
		$dotIdx = $typeStr.IndexOf('.')
		$prefix = $typeStr.Substring(0, $dotIdx)
		$suffix = $typeStr.Substring($dotIdx)  # includes the dot
		$resolved = $script:typeSynonyms[$prefix.ToLower()]
		if ($resolved) { return "$resolved$suffix" }
		return $typeStr
	}

	# Simple name lookup
	$resolved = $script:typeSynonyms[$typeStr.ToLower()]
	if ($resolved) { return $resolved }

	return $typeStr
}

function Emit-TypeContent {
	param([string]$indent, [string]$typeStr)
	if (-not $typeStr) { return }

	$typeStr = Resolve-TypeStr $typeStr

	# Boolean
	if ($typeStr -eq "Boolean") {
		X "$indent<v8:Type>xs:boolean</v8:Type>"
		return
	}

	# String or String(N)
	if ($typeStr -match '^String(\((\d+)\))?$') {
		$len = if ($Matches[2]) { $Matches[2] } else { "0" }
		X "$indent<v8:Type>xs:string</v8:Type>"
		X "$indent<v8:StringQualifiers>"
		X "$indent`t<v8:Length>$len</v8:Length>"
		X "$indent`t<v8:AllowedLength>Variable</v8:AllowedLength>"
		X "$indent</v8:StringQualifiers>"
		return
	}

	# Number(D,F) or Number(D,F,nonneg)
	if ($typeStr -match '^Number\((\d+),(\d+)(,nonneg)?\)$') {
		$digits = $Matches[1]
		$fraction = $Matches[2]
		$sign = if ($Matches[3]) { "Nonnegative" } else { "Any" }
		X "$indent<v8:Type>xs:decimal</v8:Type>"
		X "$indent<v8:NumberQualifiers>"
		X "$indent`t<v8:Digits>$digits</v8:Digits>"
		X "$indent`t<v8:FractionDigits>$fraction</v8:FractionDigits>"
		X "$indent`t<v8:AllowedSign>$sign</v8:AllowedSign>"
		X "$indent</v8:NumberQualifiers>"
		return
	}

	# Date / DateTime
	if ($typeStr -eq "Date") {
		X "$indent<v8:Type>xs:dateTime</v8:Type>"
		X "$indent<v8:DateQualifiers>"
		X "$indent`t<v8:DateFractions>Date</v8:DateFractions>"
		X "$indent</v8:DateQualifiers>"
		return
	}
	if ($typeStr -eq "DateTime") {
		X "$indent<v8:Type>xs:dateTime</v8:Type>"
		X "$indent<v8:DateQualifiers>"
		X "$indent`t<v8:DateFractions>DateTime</v8:DateFractions>"
		X "$indent</v8:DateQualifiers>"
		return
	}

	# DefinedType
	if ($typeStr -match '^DefinedType\.(.+)$') {
		$dtName = $Matches[1]
		X "$indent<v8:TypeSet>cfg:DefinedType.$dtName</v8:TypeSet>"
		return
	}

	# Reference types: CatalogRef.XXX, DocumentRef.XXX, etc.
	if ($typeStr -match '^(CatalogRef|DocumentRef|EnumRef|ChartOfAccountsRef|ChartOfCharacteristicTypesRef)\.(.+)$') {
		X "$indent<v8:Type>cfg:$typeStr</v8:Type>"
		return
	}

	# Fallback — emit as-is
	X "$indent<v8:Type>$typeStr</v8:Type>"
}

function Emit-ValueType {
	param([string]$indent, [string]$typeStr)
	X "$indent<Type>"
	Emit-TypeContent "$indent`t" $typeStr
	X "$indent</Type>"
}

function Emit-FillValue {
	param([string]$indent, [string]$typeStr)
	if (-not $typeStr) {
		X "$indent<FillValue xsi:nil=`"true`"/>"
		return
	}

	$typeStr = Resolve-TypeStr $typeStr

	if ($typeStr -eq "Boolean") {
		X "$indent<FillValue xsi:type=`"xs:boolean`">false</FillValue>"
		return
	}
	if ($typeStr -match '^String') {
		X "$indent<FillValue xsi:type=`"xs:string`"/>"
		return
	}
	if ($typeStr -match '^Number') {
		X "$indent<FillValue xsi:type=`"xs:decimal`">0</FillValue>"
		return
	}
	if ($typeStr -match '^(Date|DateTime)$') {
		X "$indent<FillValue xsi:nil=`"true`"/>"
		return
	}
	# References and others
	X "$indent<FillValue xsi:nil=`"true`"/>"
}

# --- 5. Attribute shorthand parser ---

function Parse-AttributeShorthand {
	param($val)

	if ($val -is [string]) {
		$str = "$val"
		$parsed = @{
			name = ""
			type = ""
			synonym = ""
			comment = ""
			flags = @()
		}

		# Split by | for flags
		$parts = $str -split '\|', 2
		$mainPart = $parts[0].Trim()
		if ($parts.Count -gt 1) {
			$flagStr = $parts[1].Trim()
			$parsed.flags = @($flagStr -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
		}

		# Split by : for name and type
		$colonParts = $mainPart -split ':', 2
		$parsed.name = $colonParts[0].Trim()
		if ($colonParts.Count -gt 1) {
			$parsed.type = $colonParts[1].Trim()
		}

		$parsed.synonym = Split-CamelCase $parsed.name
		return $parsed
	}

	# Object form
	$name = "$($val.name)"
	return @{
		name    = $name
		type    = if ($val.type) { "$($val.type)" } else { "" }
		synonym = if ($val.synonym) { "$($val.synonym)" } else { Split-CamelCase $name }
		comment = if ($val.comment) { "$($val.comment)" } else { "" }
		flags   = @(if ($val.flags) { $val.flags } else { @() })
		fillChecking = if ($val.fillChecking) { "$($val.fillChecking)" } else { "" }
		indexing = if ($val.indexing) { "$($val.indexing)" } else { "" }
	}
}

function Parse-EnumValueShorthand {
	param($val)

	if ($val -is [string]) {
		$name = "$val"
		return @{
			name    = $name
			synonym = Split-CamelCase $name
			comment = ""
		}
	}

	$name = "$($val.name)"
	return @{
		name    = $name
		synonym = if ($val.synonym) { "$($val.synonym)" } else { Split-CamelCase $name }
		comment = if ($val.comment) { "$($val.comment)" } else { "" }
	}
}

# --- 6. GeneratedType categories ---

$script:generatedTypes = @{
	"Catalog" = @(
		@{ prefix = "CatalogObject";    category = "Object" }
		@{ prefix = "CatalogRef";       category = "Ref" }
		@{ prefix = "CatalogSelection"; category = "Selection" }
		@{ prefix = "CatalogList";      category = "List" }
		@{ prefix = "CatalogManager";   category = "Manager" }
	)
	"Document" = @(
		@{ prefix = "DocumentObject";    category = "Object" }
		@{ prefix = "DocumentRef";       category = "Ref" }
		@{ prefix = "DocumentSelection"; category = "Selection" }
		@{ prefix = "DocumentList";      category = "List" }
		@{ prefix = "DocumentManager";   category = "Manager" }
	)
	"Enum" = @(
		@{ prefix = "EnumRef";     category = "Ref" }
		@{ prefix = "EnumManager"; category = "Manager" }
		@{ prefix = "EnumList";    category = "List" }
	)
	"Constant" = @(
		@{ prefix = "ConstantManager";      category = "Manager" }
		@{ prefix = "ConstantValueManager"; category = "ValueManager" }
		@{ prefix = "ConstantValueKey";     category = "ValueKey" }
	)
	"InformationRegister" = @(
		@{ prefix = "InformationRegisterRecord";        category = "Record" }
		@{ prefix = "InformationRegisterManager";       category = "Manager" }
		@{ prefix = "InformationRegisterSelection";     category = "Selection" }
		@{ prefix = "InformationRegisterList";          category = "List" }
		@{ prefix = "InformationRegisterRecordSet";     category = "RecordSet" }
		@{ prefix = "InformationRegisterRecordKey";     category = "RecordKey" }
		@{ prefix = "InformationRegisterRecordManager"; category = "RecordManager" }
	)
	"AccumulationRegister" = @(
		@{ prefix = "AccumulationRegisterRecord";    category = "Record" }
		@{ prefix = "AccumulationRegisterManager";   category = "Manager" }
		@{ prefix = "AccumulationRegisterSelection"; category = "Selection" }
		@{ prefix = "AccumulationRegisterList";      category = "List" }
		@{ prefix = "AccumulationRegisterRecordSet"; category = "RecordSet" }
		@{ prefix = "AccumulationRegisterRecordKey"; category = "RecordKey" }
	)
}

function Emit-InternalInfo {
	param([string]$indent, [string]$objectType, [string]$objectName)
	$types = $script:generatedTypes[$objectType]
	if (-not $types) { return }

	X "$indent<InternalInfo>"
	foreach ($gt in $types) {
		$fullName = "$($gt.prefix).$objectName"
		X "$indent`t<xr:GeneratedType name=`"$fullName`" category=`"$($gt.category)`">"
		X "$indent`t`t<xr:TypeId>$(New-Guid-String)</xr:TypeId>"
		X "$indent`t`t<xr:ValueId>$(New-Guid-String)</xr:ValueId>"
		X "$indent`t</xr:GeneratedType>"
	}
	X "$indent</InternalInfo>"
}

# --- 7. StandardAttributes ---

$script:standardAttributesByType = @{
	"Catalog" = @("PredefinedDataName","Predefined","Ref","DeletionMark","IsFolder","Owner","Parent","Description","Code")
	"Document" = @("Posted","Ref","DeletionMark","Date","Number")
	"Enum" = @("Order","Ref")
	"InformationRegister" = @("Active","LineNumber","Recorder","Period")
	"AccumulationRegister" = @("Active","LineNumber","Recorder","Period")
}

function Emit-StandardAttribute {
	param([string]$indent, [string]$attrName)
	X "$indent<xr:StandardAttribute name=`"$attrName`">"
	X "$indent`t<xr:LinkByType/>"
	X "$indent`t<xr:FillChecking>DontCheck</xr:FillChecking>"
	X "$indent`t<xr:MultiLine>false</xr:MultiLine>"
	X "$indent`t<xr:FillFromFillingValue>false</xr:FillFromFillingValue>"
	X "$indent`t<xr:CreateOnInput>Auto</xr:CreateOnInput>"
	X "$indent`t<xr:MaxValue xsi:nil=`"true`"/>"
	X "$indent`t<xr:ToolTip/>"
	X "$indent`t<xr:ExtendedEdit>false</xr:ExtendedEdit>"
	X "$indent`t<xr:Format/>"
	X "$indent`t<xr:ChoiceForm/>"
	X "$indent`t<xr:QuickChoice>Auto</xr:QuickChoice>"
	X "$indent`t<xr:ChoiceHistoryOnInput>Auto</xr:ChoiceHistoryOnInput>"
	X "$indent`t<xr:EditFormat/>"
	X "$indent`t<xr:PasswordMode>false</xr:PasswordMode>"
	X "$indent`t<xr:DataHistory>Use</xr:DataHistory>"
	X "$indent`t<xr:MarkNegatives>false</xr:MarkNegatives>"
	X "$indent`t<xr:MinValue xsi:nil=`"true`"/>"
	X "$indent`t<xr:Synonym/>"
	X "$indent`t<xr:Comment/>"
	X "$indent`t<xr:FullTextSearch>Use</xr:FullTextSearch>"
	X "$indent`t<xr:ChoiceParameterLinks/>"
	X "$indent`t<xr:FillValue xsi:nil=`"true`"/>"
	X "$indent`t<xr:Mask/>"
	X "$indent`t<xr:ChoiceParameters/>"
	X "$indent</xr:StandardAttribute>"
}

function Emit-StandardAttributes {
	param([string]$indent, [string]$objectType)
	$attrs = $script:standardAttributesByType[$objectType]
	if (-not $attrs) { return }
	X "$indent<StandardAttributes>"
	foreach ($a in $attrs) {
		Emit-StandardAttribute "$indent`t" $a
	}
	X "$indent</StandardAttributes>"
}

# TabularSection standard attributes (just LineNumber)
function Emit-TabularStandardAttributes {
	param([string]$indent)
	X "$indent<StandardAttributes>"
	Emit-StandardAttribute "$indent`t" "LineNumber"
	X "$indent</StandardAttributes>"
}

# --- 8. Attribute emitter ---

function Emit-Attribute {
	param([string]$indent, $parsed, [string]$context)
	# $context: "catalog", "document", "tabular", "register"
	$uuid = New-Guid-String
	X "$indent<Attribute uuid=`"$uuid`">"
	X "$indent`t<Properties>"
	X "$indent`t`t<Name>$(Esc-Xml $parsed.name)</Name>"
	Emit-MLText "$indent`t`t" "Synonym" $parsed.synonym
	X "$indent`t`t<Comment/>"

	# Type
	$typeStr = $parsed.type
	if ($typeStr) {
		Emit-ValueType "$indent`t`t" $typeStr
	} else {
		# Default: unqualified string
		X "$indent`t`t<Type>"
		X "$indent`t`t`t<v8:Type>xs:string</v8:Type>"
		X "$indent`t`t</Type>"
	}

	X "$indent`t`t<PasswordMode>false</PasswordMode>"
	X "$indent`t`t<Format/>"
	X "$indent`t`t<EditFormat/>"
	X "$indent`t`t<ToolTip/>"
	X "$indent`t`t<MarkNegatives>false</MarkNegatives>"
	X "$indent`t`t<Mask/>"
	X "$indent`t`t<MultiLine>false</MultiLine>"
	X "$indent`t`t<ExtendedEdit>false</ExtendedEdit>"
	X "$indent`t`t<MinValue xsi:nil=`"true`"/>"
	X "$indent`t`t<MaxValue xsi:nil=`"true`"/>"

	# FillFromFillingValue
	X "$indent`t`t<FillFromFillingValue>false</FillFromFillingValue>"

	# FillValue
	Emit-FillValue "$indent`t`t" $typeStr

	# FillChecking
	$fillChecking = "DontCheck"
	if ($parsed.flags -contains "req") { $fillChecking = "ShowError" }
	if ($parsed.fillChecking) { $fillChecking = $parsed.fillChecking }
	X "$indent`t`t<FillChecking>$fillChecking</FillChecking>"

	X "$indent`t`t<ChoiceFoldersAndItems>Items</ChoiceFoldersAndItems>"
	X "$indent`t`t<ChoiceParameterLinks/>"
	X "$indent`t`t<ChoiceParameters/>"
	X "$indent`t`t<QuickChoice>Auto</QuickChoice>"
	X "$indent`t`t<CreateOnInput>Auto</CreateOnInput>"
	X "$indent`t`t<ChoiceForm/>"
	X "$indent`t`t<LinkByType/>"
	X "$indent`t`t<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"

	# Use — only for catalog/document top-level attributes
	if ($context -eq "catalog" -or $context -eq "document") {
		X "$indent`t`t<Use>ForItem</Use>"
	}

	# Indexing
	$indexing = "DontIndex"
	if ($parsed.flags -contains "index") { $indexing = "Index" }
	if ($parsed.flags -contains "indexadditional") { $indexing = "IndexWithAdditionalOrder" }
	if ($parsed.indexing) { $indexing = $parsed.indexing }
	X "$indent`t`t<Indexing>$indexing</Indexing>"

	X "$indent`t`t<FullTextSearch>Use</FullTextSearch>"
	X "$indent`t`t<DataHistory>Use</DataHistory>"

	X "$indent`t</Properties>"
	X "$indent</Attribute>"
}

# --- 9. TabularSection emitter ---

function Emit-TabularSection {
	param([string]$indent, [string]$tsName, $columns, [string]$objectType, [string]$objectName)
	$uuid = New-Guid-String
	X "$indent<TabularSection uuid=`"$uuid`">"

	# InternalInfo for TabularSection
	$typePrefix = switch ($objectType) {
		"Catalog"  { "CatalogTabularSection" }
		"Document" { "DocumentTabularSection" }
	}
	$rowPrefix = switch ($objectType) {
		"Catalog"  { "CatalogTabularSectionRow" }
		"Document" { "DocumentTabularSectionRow" }
	}

	X "$indent`t<InternalInfo>"
	X "$indent`t`t<xr:GeneratedType name=`"$typePrefix.$objectName.$tsName`" category=`"TabularSection`">"
	X "$indent`t`t`t<xr:TypeId>$(New-Guid-String)</xr:TypeId>"
	X "$indent`t`t`t<xr:ValueId>$(New-Guid-String)</xr:ValueId>"
	X "$indent`t`t</xr:GeneratedType>"
	X "$indent`t`t<xr:GeneratedType name=`"$rowPrefix.$objectName.$tsName`" category=`"TabularSectionRow`">"
	X "$indent`t`t`t<xr:TypeId>$(New-Guid-String)</xr:TypeId>"
	X "$indent`t`t`t<xr:ValueId>$(New-Guid-String)</xr:ValueId>"
	X "$indent`t`t</xr:GeneratedType>"
	X "$indent`t</InternalInfo>"

	$tsSynonym = Split-CamelCase $tsName

	X "$indent`t<Properties>"
	X "$indent`t`t<Name>$(Esc-Xml $tsName)</Name>"
	Emit-MLText "$indent`t`t" "Synonym" $tsSynonym
	X "$indent`t`t<Comment/>"
	X "$indent`t`t<ToolTip/>"
	X "$indent`t`t<FillChecking>DontCheck</FillChecking>"
	Emit-TabularStandardAttributes "$indent`t`t"
	X "$indent`t`t<Use>ForItem</Use>"
	X "$indent`t</Properties>"

	X "$indent`t<ChildObjects>"
	foreach ($col in $columns) {
		$parsed = Parse-AttributeShorthand $col
		Emit-Attribute "$indent`t`t" $parsed "tabular"
	}
	X "$indent`t</ChildObjects>"

	X "$indent</TabularSection>"
}

# --- 10. EnumValue emitter ---

function Emit-EnumValue {
	param([string]$indent, $parsed)
	$uuid = New-Guid-String
	X "$indent<EnumValue uuid=`"$uuid`">"
	X "$indent`t<Properties>"
	X "$indent`t`t<Name>$(Esc-Xml $parsed.name)</Name>"
	Emit-MLText "$indent`t`t" "Synonym" $parsed.synonym
	X "$indent`t`t<Comment/>"
	X "$indent`t</Properties>"
	X "$indent</EnumValue>"
}

# --- 11. Dimension emitter ---

function Emit-Dimension {
	param([string]$indent, $parsed, [string]$registerType)
	# $registerType: "InformationRegister" or "AccumulationRegister"
	$uuid = New-Guid-String
	X "$indent<Dimension uuid=`"$uuid`">"
	X "$indent`t<Properties>"
	X "$indent`t`t<Name>$(Esc-Xml $parsed.name)</Name>"
	Emit-MLText "$indent`t`t" "Synonym" $parsed.synonym
	X "$indent`t`t<Comment/>"

	$typeStr = $parsed.type
	if ($typeStr) {
		Emit-ValueType "$indent`t`t" $typeStr
	} else {
		X "$indent`t`t<Type>"
		X "$indent`t`t`t<v8:Type>xs:string</v8:Type>"
		X "$indent`t`t</Type>"
	}

	X "$indent`t`t<PasswordMode>false</PasswordMode>"
	X "$indent`t`t<Format/>"
	X "$indent`t`t<EditFormat/>"
	X "$indent`t`t<ToolTip/>"
	X "$indent`t`t<MarkNegatives>false</MarkNegatives>"
	X "$indent`t`t<Mask/>"
	X "$indent`t`t<MultiLine>false</MultiLine>"
	X "$indent`t`t<ExtendedEdit>false</ExtendedEdit>"
	X "$indent`t`t<MinValue xsi:nil=`"true`"/>"
	X "$indent`t`t<MaxValue xsi:nil=`"true`"/>"

	# InformationRegister dimensions have FillFromFillingValue
	if ($registerType -eq "InformationRegister") {
		$fillFrom = if ($parsed.flags -contains "master") { "true" } else { "false" }
		X "$indent`t`t<FillFromFillingValue>$fillFrom</FillFromFillingValue>"
		X "$indent`t`t<FillValue xsi:nil=`"true`"/>"
	}

	$fillChecking = "DontCheck"
	if ($parsed.flags -contains "req") { $fillChecking = "ShowError" }
	X "$indent`t`t<FillChecking>$fillChecking</FillChecking>"

	X "$indent`t`t<ChoiceFoldersAndItems>Items</ChoiceFoldersAndItems>"
	X "$indent`t`t<ChoiceParameterLinks/>"
	X "$indent`t`t<ChoiceParameters/>"
	X "$indent`t`t<QuickChoice>Auto</QuickChoice>"
	X "$indent`t`t<CreateOnInput>Auto</CreateOnInput>"
	X "$indent`t`t<ChoiceForm/>"
	X "$indent`t`t<LinkByType/>"
	X "$indent`t`t<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"

	# InformationRegister dimensions: Master, MainFilter, DenyIncompleteValues
	if ($registerType -eq "InformationRegister") {
		$master = if ($parsed.flags -contains "master") { "true" } else { "false" }
		$mainFilter = if ($parsed.flags -contains "mainfilter") { "true" } else { "false" }
		$denyIncomplete = if ($parsed.flags -contains "denyincomplete") { "true" } else { "false" }
		X "$indent`t`t<Master>$master</Master>"
		X "$indent`t`t<MainFilter>$mainFilter</MainFilter>"
		X "$indent`t`t<DenyIncompleteValues>$denyIncomplete</DenyIncompleteValues>"
	}

	# AccumulationRegister dimensions: DenyIncompleteValues
	if ($registerType -eq "AccumulationRegister") {
		$denyIncomplete = if ($parsed.flags -contains "denyincomplete") { "true" } else { "false" }
		X "$indent`t`t<DenyIncompleteValues>$denyIncomplete</DenyIncompleteValues>"
	}

	$indexing = "DontIndex"
	if ($parsed.flags -contains "index") { $indexing = "Index" }
	X "$indent`t`t<Indexing>$indexing</Indexing>"

	X "$indent`t`t<FullTextSearch>Use</FullTextSearch>"

	# AccumulationRegister dimensions: UseInTotals
	if ($registerType -eq "AccumulationRegister") {
		$useInTotals = if ($parsed.flags -contains "nouseintotals") { "false" } else { "true" }
		X "$indent`t`t<UseInTotals>$useInTotals</UseInTotals>"
	}

	# InformationRegister dimensions: DataHistory
	if ($registerType -eq "InformationRegister") {
		X "$indent`t`t<DataHistory>Use</DataHistory>"
	}

	X "$indent`t</Properties>"
	X "$indent</Dimension>"
}

# --- 12. Resource emitter ---

function Emit-Resource {
	param([string]$indent, $parsed, [string]$registerType)
	$uuid = New-Guid-String
	X "$indent<Resource uuid=`"$uuid`">"
	X "$indent`t<Properties>"
	X "$indent`t`t<Name>$(Esc-Xml $parsed.name)</Name>"
	Emit-MLText "$indent`t`t" "Synonym" $parsed.synonym
	X "$indent`t`t<Comment/>"

	$typeStr = $parsed.type
	if ($typeStr) {
		Emit-ValueType "$indent`t`t" $typeStr
	} else {
		X "$indent`t`t<Type>"
		X "$indent`t`t`t<v8:Type>xs:decimal</v8:Type>"
		X "$indent`t`t`t<v8:NumberQualifiers>"
		X "$indent`t`t`t`t<v8:Digits>15</v8:Digits>"
		X "$indent`t`t`t`t<v8:FractionDigits>2</v8:FractionDigits>"
		X "$indent`t`t`t`t<v8:AllowedSign>Any</v8:AllowedSign>"
		X "$indent`t`t`t</v8:NumberQualifiers>"
		X "$indent`t`t</Type>"
	}

	X "$indent`t`t<PasswordMode>false</PasswordMode>"
	X "$indent`t`t<Format/>"
	X "$indent`t`t<EditFormat/>"
	X "$indent`t`t<ToolTip/>"
	X "$indent`t`t<MarkNegatives>false</MarkNegatives>"
	X "$indent`t`t<Mask/>"
	X "$indent`t`t<MultiLine>false</MultiLine>"
	X "$indent`t`t<ExtendedEdit>false</ExtendedEdit>"
	X "$indent`t`t<MinValue xsi:nil=`"true`"/>"
	X "$indent`t`t<MaxValue xsi:nil=`"true`"/>"

	# InformationRegister resources have FillFromFillingValue, FillValue
	if ($registerType -eq "InformationRegister") {
		X "$indent`t`t<FillFromFillingValue>false</FillFromFillingValue>"
		X "$indent`t`t<FillValue xsi:nil=`"true`"/>"
	}

	$fillChecking = "DontCheck"
	if ($parsed.flags -contains "req") { $fillChecking = "ShowError" }
	X "$indent`t`t<FillChecking>$fillChecking</FillChecking>"

	X "$indent`t`t<ChoiceFoldersAndItems>Items</ChoiceFoldersAndItems>"
	X "$indent`t`t<ChoiceParameterLinks/>"
	X "$indent`t`t<ChoiceParameters/>"
	X "$indent`t`t<QuickChoice>Auto</QuickChoice>"
	X "$indent`t`t<CreateOnInput>Auto</CreateOnInput>"
	X "$indent`t`t<ChoiceForm/>"
	X "$indent`t`t<LinkByType/>"
	X "$indent`t`t<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"

	# InformationRegister resources: Indexing, FullTextSearch, DataHistory
	if ($registerType -eq "InformationRegister") {
		X "$indent`t`t<Indexing>DontIndex</Indexing>"
		X "$indent`t`t<FullTextSearch>Use</FullTextSearch>"
		X "$indent`t`t<DataHistory>Use</DataHistory>"
	}

	# AccumulationRegister resources: FullTextSearch (no Indexing, no DataHistory)
	if ($registerType -eq "AccumulationRegister") {
		X "$indent`t`t<FullTextSearch>Use</FullTextSearch>"
	}

	X "$indent`t</Properties>"
	X "$indent</Resource>"
}

# --- 13. Property emitters per type ---

function Emit-CatalogProperties {
	param([string]$indent)
	$i = $indent

	X "$i<Name>$(Esc-Xml $objName)</Name>"
	Emit-MLText $i "Synonym" $synonym
	X "$i<Comment/>"

	$hierarchical = if ($def.hierarchical -eq $true) { "true" } else { "false" }
	$hierarchyType = if ($def.hierarchyType) { "$($def.hierarchyType)" } else { "HierarchyFoldersAndItems" }
	X "$i<Hierarchical>$hierarchical</Hierarchical>"
	X "$i<HierarchyType>$hierarchyType</HierarchyType>"
	X "$i<LimitLevelCount>false</LimitLevelCount>"
	X "$i<LevelCount>2</LevelCount>"
	X "$i<FoldersOnTop>true</FoldersOnTop>"
	X "$i<UseStandardCommands>true</UseStandardCommands>"
	X "$i<Owners/>"
	X "$i<SubordinationUse>ToItems</SubordinationUse>"

	$codeLength = if ($null -ne $def.codeLength) { "$($def.codeLength)" } else { "9" }
	$descriptionLength = if ($null -ne $def.descriptionLength) { "$($def.descriptionLength)" } else { "25" }
	$codeType = if ($def.codeType) { "$($def.codeType)" } else { "String" }
	$codeAllowedLength = if ($def.codeAllowedLength) { "$($def.codeAllowedLength)" } else { "Variable" }
	$autonumbering = if ($def.autonumbering -eq $false) { "false" } else { "true" }
	$checkUnique = if ($def.checkUnique -eq $true) { "true" } else { "false" }

	X "$i<CodeLength>$codeLength</CodeLength>"
	X "$i<DescriptionLength>$descriptionLength</DescriptionLength>"
	X "$i<CodeType>$codeType</CodeType>"
	X "$i<CodeAllowedLength>$codeAllowedLength</CodeAllowedLength>"
	X "$i<CodeSeries>WholeCatalog</CodeSeries>"
	X "$i<CheckUnique>$checkUnique</CheckUnique>"
	X "$i<Autonumbering>$autonumbering</Autonumbering>"

	$defaultPresentation = if ($def.defaultPresentation) { "$($def.defaultPresentation)" } else { "AsDescription" }
	X "$i<DefaultPresentation>$defaultPresentation</DefaultPresentation>"

	Emit-StandardAttributes $i "Catalog"
	X "$i<Characteristics/>"
	X "$i<PredefinedDataUpdate>Auto</PredefinedDataUpdate>"
	X "$i<EditType>InDialog</EditType>"
	X "$i<QuickChoice>true</QuickChoice>"
	X "$i<ChoiceMode>BothWays</ChoiceMode>"
	X "$i<InputByString>"
	X "$i`t<xr:Field>Catalog.$objName.StandardAttribute.Description</xr:Field>"
	X "$i`t<xr:Field>Catalog.$objName.StandardAttribute.Code</xr:Field>"
	X "$i</InputByString>"
	X "$i<SearchStringModeOnInputByString>Begin</SearchStringModeOnInputByString>"
	X "$i<FullTextSearchOnInputByString>DontUse</FullTextSearchOnInputByString>"
	X "$i<ChoiceDataGetModeOnInputByString>Directly</ChoiceDataGetModeOnInputByString>"
	X "$i<DefaultObjectForm/>"
	X "$i<DefaultFolderForm/>"
	X "$i<DefaultListForm/>"
	X "$i<DefaultChoiceForm/>"
	X "$i<DefaultFolderChoiceForm/>"
	X "$i<AuxiliaryObjectForm/>"
	X "$i<AuxiliaryFolderForm/>"
	X "$i<AuxiliaryListForm/>"
	X "$i<AuxiliaryChoiceForm/>"
	X "$i<AuxiliaryFolderChoiceForm/>"
	X "$i<IncludeHelpInContents>false</IncludeHelpInContents>"
	X "$i<BasedOn/>"
	X "$i<DataLockFields/>"

	$dataLockControlMode = if ($def.dataLockControlMode) { "$($def.dataLockControlMode)" } else { "Automatic" }
	X "$i<DataLockControlMode>$dataLockControlMode</DataLockControlMode>"

	$fullTextSearch = if ($def.fullTextSearch) { "$($def.fullTextSearch)" } else { "Use" }
	X "$i<FullTextSearch>$fullTextSearch</FullTextSearch>"

	X "$i<ObjectPresentation/>"
	X "$i<ExtendedObjectPresentation/>"
	X "$i<ListPresentation/>"
	X "$i<ExtendedListPresentation/>"
	X "$i<Explanation/>"
	X "$i<CreateOnInput>DontUse</CreateOnInput>"
	X "$i<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"
	X "$i<DataHistory>DontUse</DataHistory>"
	X "$i<UpdateDataHistoryImmediatelyAfterWrite>false</UpdateDataHistoryImmediatelyAfterWrite>"
	X "$i<ExecuteAfterWriteDataHistoryVersionProcessing>false</ExecuteAfterWriteDataHistoryVersionProcessing>"
}

function Emit-DocumentProperties {
	param([string]$indent)
	$i = $indent

	X "$i<Name>$(Esc-Xml $objName)</Name>"
	Emit-MLText $i "Synonym" $synonym
	X "$i<Comment/>"
	X "$i<UseStandardCommands>true</UseStandardCommands>"
	X "$i<Numerator/>"

	$numberType = if ($def.numberType) { "$($def.numberType)" } else { "String" }
	$numberLength = if ($null -ne $def.numberLength) { "$($def.numberLength)" } else { "11" }
	$numberAllowedLength = if ($def.numberAllowedLength) { "$($def.numberAllowedLength)" } else { "Variable" }
	$numberPeriodicity = if ($def.numberPeriodicity) { "$($def.numberPeriodicity)" } else { "Year" }
	$checkUnique = if ($def.checkUnique -eq $false) { "false" } else { "true" }
	$autonumbering = if ($def.autonumbering -eq $false) { "false" } else { "true" }

	X "$i<NumberType>$numberType</NumberType>"
	X "$i<NumberLength>$numberLength</NumberLength>"
	X "$i<NumberAllowedLength>$numberAllowedLength</NumberAllowedLength>"
	X "$i<NumberPeriodicity>$numberPeriodicity</NumberPeriodicity>"
	X "$i<CheckUnique>$checkUnique</CheckUnique>"
	X "$i<Autonumbering>$autonumbering</Autonumbering>"

	Emit-StandardAttributes $i "Document"
	X "$i<Characteristics/>"

	X "$i<BasedOn/>"
	X "$i<InputByString>"
	X "$i`t<xr:Field>Document.$objName.StandardAttribute.Number</xr:Field>"
	X "$i</InputByString>"
	X "$i<CreateOnInput>DontUse</CreateOnInput>"
	X "$i<SearchStringModeOnInputByString>Begin</SearchStringModeOnInputByString>"
	X "$i<FullTextSearchOnInputByString>DontUse</FullTextSearchOnInputByString>"
	X "$i<ChoiceDataGetModeOnInputByString>Directly</ChoiceDataGetModeOnInputByString>"
	X "$i<DefaultObjectForm/>"
	X "$i<DefaultListForm/>"
	X "$i<DefaultChoiceForm/>"
	X "$i<AuxiliaryObjectForm/>"
	X "$i<AuxiliaryListForm/>"
	X "$i<AuxiliaryChoiceForm/>"

	$posting = if ($def.posting) { "$($def.posting)" } else { "Allow" }
	$realTimePosting = if ($def.realTimePosting) { "$($def.realTimePosting)" } else { "Deny" }
	$registerRecordsDeletion = if ($def.registerRecordsDeletion) { "$($def.registerRecordsDeletion)" } else { "AutoDelete" }
	$registerRecordsWritingOnPost = if ($def.registerRecordsWritingOnPost) { "$($def.registerRecordsWritingOnPost)" } else { "WriteModified" }
	$sequenceFilling = if ($def.sequenceFilling) { "$($def.sequenceFilling)" } else { "AutoFill" }
	$postInPrivilegedMode = if ($def.postInPrivilegedMode -eq $false) { "false" } else { "true" }
	$unpostInPrivilegedMode = if ($def.unpostInPrivilegedMode -eq $false) { "false" } else { "true" }

	X "$i<Posting>$posting</Posting>"
	X "$i<RealTimePosting>$realTimePosting</RealTimePosting>"
	X "$i<RegisterRecordsDeletion>$registerRecordsDeletion</RegisterRecordsDeletion>"
	X "$i<RegisterRecordsWritingOnPost>$registerRecordsWritingOnPost</RegisterRecordsWritingOnPost>"
	X "$i<SequenceFilling>$sequenceFilling</SequenceFilling>"

	# RegisterRecords
	$regRecords = @()
	if ($def.registerRecords) {
		foreach ($rr in $def.registerRecords) {
			$rrStr = "$rr"
			# Resolve Russian synonyms in register records
			if ($rrStr.Contains('.')) {
				$dotIdx = $rrStr.IndexOf('.')
				$rrPrefix = $rrStr.Substring(0, $dotIdx)
				$rrSuffix = $rrStr.Substring($dotIdx + 1)
				if ($script:objectTypeSynonyms.ContainsKey($rrPrefix)) {
					$rrPrefix = $script:objectTypeSynonyms[$rrPrefix]
				}
				$regRecords += "$rrPrefix.$rrSuffix"
			} else {
				$regRecords += $rrStr
			}
		}
	}

	if ($regRecords.Count -gt 0) {
		X "$i<RegisterRecords>"
		foreach ($rr in $regRecords) {
			X "$i`t<xr:Record>$rr</xr:Record>"
		}
		X "$i</RegisterRecords>"
	} else {
		X "$i<RegisterRecords/>"
	}

	X "$i<PostInPrivilegedMode>$postInPrivilegedMode</PostInPrivilegedMode>"
	X "$i<UnpostInPrivilegedMode>$unpostInPrivilegedMode</UnpostInPrivilegedMode>"
	X "$i<IncludeHelpInContents>false</IncludeHelpInContents>"
	X "$i<DataLockFields/>"

	$dataLockControlMode = if ($def.dataLockControlMode) { "$($def.dataLockControlMode)" } else { "Automatic" }
	X "$i<DataLockControlMode>$dataLockControlMode</DataLockControlMode>"

	$fullTextSearch = if ($def.fullTextSearch) { "$($def.fullTextSearch)" } else { "Use" }
	X "$i<FullTextSearch>$fullTextSearch</FullTextSearch>"

	X "$i<ObjectPresentation/>"
	X "$i<ExtendedObjectPresentation/>"
	X "$i<ListPresentation/>"
	X "$i<ExtendedListPresentation/>"
	X "$i<Explanation/>"
	X "$i<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"
	X "$i<DataHistory>DontUse</DataHistory>"
	X "$i<UpdateDataHistoryImmediatelyAfterWrite>false</UpdateDataHistoryImmediatelyAfterWrite>"
	X "$i<ExecuteAfterWriteDataHistoryVersionProcessing>false</ExecuteAfterWriteDataHistoryVersionProcessing>"
}

function Emit-EnumProperties {
	param([string]$indent)
	$i = $indent

	X "$i<Name>$(Esc-Xml $objName)</Name>"
	Emit-MLText $i "Synonym" $synonym
	X "$i<Comment/>"
	X "$i<UseStandardCommands>false</UseStandardCommands>"

	Emit-StandardAttributes $i "Enum"
	X "$i<Characteristics/>"

	X "$i<QuickChoice>true</QuickChoice>"
	X "$i<ChoiceMode>BothWays</ChoiceMode>"
	X "$i<DefaultListForm/>"
	X "$i<DefaultChoiceForm/>"
	X "$i<AuxiliaryListForm/>"
	X "$i<AuxiliaryChoiceForm/>"
	X "$i<ListPresentation/>"
	X "$i<ExtendedListPresentation/>"
	X "$i<Explanation/>"
	X "$i<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"
}

function Emit-ConstantProperties {
	param([string]$indent)
	$i = $indent

	X "$i<Name>$(Esc-Xml $objName)</Name>"
	Emit-MLText $i "Synonym" $synonym
	X "$i<Comment/>"

	# Type
	$valueType = if ($def.valueType) { "$($def.valueType)" } else { "String" }
	Emit-ValueType $i $valueType

	X "$i<UseStandardCommands>true</UseStandardCommands>"
	X "$i<DefaultForm/>"
	X "$i<ExtendedPresentation/>"
	X "$i<Explanation/>"
	X "$i<PasswordMode>false</PasswordMode>"
	X "$i<Format/>"
	X "$i<EditFormat/>"
	X "$i<ToolTip/>"
	X "$i<MarkNegatives>false</MarkNegatives>"
	X "$i<Mask/>"
	X "$i<MultiLine>false</MultiLine>"
	X "$i<ExtendedEdit>false</ExtendedEdit>"
	X "$i<MinValue xsi:nil=`"true`"/>"
	X "$i<MaxValue xsi:nil=`"true`"/>"
	X "$i<FillChecking>DontCheck</FillChecking>"
	X "$i<ChoiceFoldersAndItems>Items</ChoiceFoldersAndItems>"
	X "$i<ChoiceParameterLinks/>"
	X "$i<ChoiceParameters/>"
	X "$i<QuickChoice>Auto</QuickChoice>"
	X "$i<ChoiceForm/>"
	X "$i<LinkByType/>"
	X "$i<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>"

	$dataLockControlMode = if ($def.dataLockControlMode) { "$($def.dataLockControlMode)" } else { "Automatic" }
	X "$i<DataLockControlMode>$dataLockControlMode</DataLockControlMode>"
	X "$i<DataHistory>DontUse</DataHistory>"
	X "$i<UpdateDataHistoryImmediatelyAfterWrite>false</UpdateDataHistoryImmediatelyAfterWrite>"
	X "$i<ExecuteAfterWriteDataHistoryVersionProcessing>false</ExecuteAfterWriteDataHistoryVersionProcessing>"
}

function Emit-InformationRegisterProperties {
	param([string]$indent)
	$i = $indent

	X "$i<Name>$(Esc-Xml $objName)</Name>"
	Emit-MLText $i "Synonym" $synonym
	X "$i<Comment/>"
	X "$i<UseStandardCommands>true</UseStandardCommands>"
	X "$i<EditType>InDialog</EditType>"
	X "$i<DefaultRecordForm/>"
	X "$i<DefaultListForm/>"
	X "$i<AuxiliaryRecordForm/>"
	X "$i<AuxiliaryListForm/>"

	Emit-StandardAttributes $i "InformationRegister"

	$periodicity = if ($def.periodicity) { "$($def.periodicity)" } else { "Nonperiodical" }
	$writeMode = if ($def.writeMode) { "$($def.writeMode)" } else { "Independent" }

	# MainFilterOnPeriod: auto based on periodicity unless explicitly set
	$mainFilterOnPeriod = "false"
	if ($null -ne $def.mainFilterOnPeriod) {
		$mainFilterOnPeriod = if ($def.mainFilterOnPeriod -eq $true) { "true" } else { "false" }
	} elseif ($periodicity -ne "Nonperiodical") {
		$mainFilterOnPeriod = "true"
	}

	X "$i<InformationRegisterPeriodicity>$periodicity</InformationRegisterPeriodicity>"
	X "$i<WriteMode>$writeMode</WriteMode>"
	X "$i<MainFilterOnPeriod>$mainFilterOnPeriod</MainFilterOnPeriod>"
	X "$i<IncludeHelpInContents>false</IncludeHelpInContents>"

	$dataLockControlMode = if ($def.dataLockControlMode) { "$($def.dataLockControlMode)" } else { "Automatic" }
	X "$i<DataLockControlMode>$dataLockControlMode</DataLockControlMode>"

	$fullTextSearch = if ($def.fullTextSearch) { "$($def.fullTextSearch)" } else { "Use" }
	X "$i<FullTextSearch>$fullTextSearch</FullTextSearch>"

	X "$i<EnableTotalsSliceFirst>false</EnableTotalsSliceFirst>"
	X "$i<EnableTotalsSliceLast>false</EnableTotalsSliceLast>"
	X "$i<RecordPresentation/>"
	X "$i<ExtendedRecordPresentation/>"
	X "$i<ListPresentation/>"
	X "$i<ExtendedListPresentation/>"
	X "$i<Explanation/>"
	X "$i<DataHistory>DontUse</DataHistory>"
	X "$i<UpdateDataHistoryImmediatelyAfterWrite>false</UpdateDataHistoryImmediatelyAfterWrite>"
	X "$i<ExecuteAfterWriteDataHistoryVersionProcessing>false</ExecuteAfterWriteDataHistoryVersionProcessing>"
}

function Emit-AccumulationRegisterProperties {
	param([string]$indent)
	$i = $indent

	X "$i<Name>$(Esc-Xml $objName)</Name>"
	Emit-MLText $i "Synonym" $synonym
	X "$i<Comment/>"
	X "$i<UseStandardCommands>true</UseStandardCommands>"
	X "$i<DefaultListForm/>"
	X "$i<AuxiliaryListForm/>"

	$registerType = if ($def.registerType) { "$($def.registerType)" } else { "Balance" }
	X "$i<RegisterType>$registerType</RegisterType>"

	X "$i<IncludeHelpInContents>false</IncludeHelpInContents>"

	Emit-StandardAttributes $i "AccumulationRegister"

	$dataLockControlMode = if ($def.dataLockControlMode) { "$($def.dataLockControlMode)" } else { "Automatic" }
	X "$i<DataLockControlMode>$dataLockControlMode</DataLockControlMode>"

	$fullTextSearch = if ($def.fullTextSearch) { "$($def.fullTextSearch)" } else { "Use" }
	X "$i<FullTextSearch>$fullTextSearch</FullTextSearch>"

	$enableTotalsSplitting = if ($def.enableTotalsSplitting -eq $false) { "false" } else { "true" }
	X "$i<EnableTotalsSplitting>$enableTotalsSplitting</EnableTotalsSplitting>"

	X "$i<ListPresentation/>"
	X "$i<ExtendedListPresentation/>"
	X "$i<Explanation/>"
}

# --- 14. Namespaces ---

$script:xmlnsDecl = 'xmlns="http://v8.1c.ru/8.3/MDClasses" xmlns:app="http://v8.1c.ru/8.2/managed-application/core" xmlns:cfg="http://v8.1c.ru/8.1/data/enterprise/current-config" xmlns:cmi="http://v8.1c.ru/8.2/managed-application/cmi" xmlns:ent="http://v8.1c.ru/8.1/data/enterprise" xmlns:lf="http://v8.1c.ru/8.2/managed-application/logform" xmlns:style="http://v8.1c.ru/8.1/data/ui/style" xmlns:sys="http://v8.1c.ru/8.1/data/ui/fonts/system" xmlns:v8="http://v8.1c.ru/8.1/data/core" xmlns:v8ui="http://v8.1c.ru/8.1/data/ui" xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web" xmlns:win="http://v8.1c.ru/8.1/data/ui/colors/windows" xmlns:xen="http://v8.1c.ru/8.3/xcf/enums" xmlns:xpr="http://v8.1c.ru/8.3/xcf/predef" xmlns:xr="http://v8.1c.ru/8.3/xcf/readable" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'

# --- 15. Main assembler ---

$uuid = New-Guid-String

# XML declaration
X '<?xml version="1.0" encoding="UTF-8"?>'
X "<MetaDataObject $($script:xmlnsDecl) version=`"2.17`">"
X "`t<$objType uuid=`"$uuid`">"

# InternalInfo
Emit-InternalInfo "`t`t" $objType $objName

# Properties
X "`t`t<Properties>"

switch ($objType) {
	"Catalog"              { Emit-CatalogProperties "`t`t`t" }
	"Document"             { Emit-DocumentProperties "`t`t`t" }
	"Enum"                 { Emit-EnumProperties "`t`t`t" }
	"Constant"             { Emit-ConstantProperties "`t`t`t" }
	"InformationRegister"  { Emit-InformationRegisterProperties "`t`t`t" }
	"AccumulationRegister" { Emit-AccumulationRegisterProperties "`t`t`t" }
}

X "`t`t</Properties>"

# ChildObjects
$hasChildren = $false

# Catalog/Document: attributes + tabularSections
if ($objType -in @("Catalog","Document")) {
	$attrs = @()
	if ($def.attributes) {
		foreach ($a in $def.attributes) {
			$attrs += Parse-AttributeShorthand $a
		}
	}
	$tsSections = @{}
	if ($def.tabularSections) {
		$def.tabularSections.PSObject.Properties | ForEach-Object {
			$tsSections[$_.Name] = @($_.Value)
		}
	}

	if ($attrs.Count -gt 0 -or $tsSections.Count -gt 0) {
		$hasChildren = $true
		X "`t`t<ChildObjects>"
		$context = $objType.ToLower()
		foreach ($a in $attrs) {
			Emit-Attribute "`t`t`t" $a $context
		}
		foreach ($tsName in $tsSections.Keys) {
			$columns = $tsSections[$tsName]
			Emit-TabularSection "`t`t`t" $tsName $columns $objType $objName
		}
		X "`t`t</ChildObjects>"
	} else {
		X "`t`t<ChildObjects/>"
	}
}

# Enum: enum values
if ($objType -eq "Enum") {
	$values = @()
	if ($def.values) {
		foreach ($v in $def.values) {
			$values += Parse-EnumValueShorthand $v
		}
	}
	if ($values.Count -gt 0) {
		$hasChildren = $true
		X "`t`t<ChildObjects>"
		foreach ($v in $values) {
			Emit-EnumValue "`t`t`t" $v
		}
		X "`t`t</ChildObjects>"
	} else {
		X "`t`t<ChildObjects/>"
	}
}

# Constant: no ChildObjects element at all

# Registers: dimensions + resources + attributes
if ($objType -in @("InformationRegister","AccumulationRegister")) {
	$dims = @()
	$resources = @()
	$regAttrs = @()
	if ($def.dimensions) {
		foreach ($d in $def.dimensions) {
			$dims += Parse-AttributeShorthand $d
		}
	}
	if ($def.resources) {
		foreach ($r in $def.resources) {
			$resources += Parse-AttributeShorthand $r
		}
	}
	if ($def.attributes) {
		foreach ($a in $def.attributes) {
			$regAttrs += Parse-AttributeShorthand $a
		}
	}

	if ($dims.Count -gt 0 -or $resources.Count -gt 0 -or $regAttrs.Count -gt 0) {
		$hasChildren = $true
		X "`t`t<ChildObjects>"
		foreach ($r in $resources) {
			Emit-Resource "`t`t`t" $r $objType
		}
		foreach ($d in $dims) {
			Emit-Dimension "`t`t`t" $d $objType
		}
		foreach ($a in $regAttrs) {
			Emit-Attribute "`t`t`t" $a "register"
		}
		X "`t`t</ChildObjects>"
	} else {
		X "`t`t<ChildObjects/>"
	}
}

X "`t</$objType>"
X "</MetaDataObject>"

$metadataXml = $script:xml.ToString()

# --- 16. Write files ---

# Type → plural directory mapping
$script:typePluralMap = @{
	"Catalog"              = "Catalogs"
	"Document"             = "Documents"
	"Enum"                 = "Enums"
	"Constant"             = "Constants"
	"InformationRegister"  = "InformationRegisters"
	"AccumulationRegister" = "AccumulationRegisters"
}

$typePlural = $script:typePluralMap[$objType]
$typeDir = Join-Path $OutputDir $typePlural

# Main XML file: {OutputDir}/{TypePlural}/{Name}.xml
$mainXmlPath = Join-Path $typeDir "$objName.xml"

# Object subdirectory: {OutputDir}/{TypePlural}/{Name}/Ext/
$objSubDir = Join-Path $typeDir $objName
$extDir = Join-Path $objSubDir "Ext"

if (-not (Test-Path $typeDir)) {
	New-Item -ItemType Directory -Path $typeDir -Force | Out-Null
}
if (-not (Test-Path $extDir)) {
	New-Item -ItemType Directory -Path $extDir -Force | Out-Null
}

$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($mainXmlPath, $metadataXml, $enc)

# Module files
$moduleCreated = ""
switch ($objType) {
	"Catalog" {
		$modulePath = Join-Path $extDir "ObjectModule.bsl"
		if (-not (Test-Path $modulePath)) {
			[System.IO.File]::WriteAllText($modulePath, "", $enc)
			$moduleCreated = $modulePath
		}
	}
	"Document" {
		$modulePath = Join-Path $extDir "ObjectModule.bsl"
		if (-not (Test-Path $modulePath)) {
			[System.IO.File]::WriteAllText($modulePath, "", $enc)
			$moduleCreated = $modulePath
		}
	}
	"InformationRegister" {
		$modulePath = Join-Path $extDir "RecordSetModule.bsl"
		if (-not (Test-Path $modulePath)) {
			[System.IO.File]::WriteAllText($modulePath, "", $enc)
			$moduleCreated = $modulePath
		}
	}
	"AccumulationRegister" {
		$modulePath = Join-Path $extDir "RecordSetModule.bsl"
		if (-not (Test-Path $modulePath)) {
			[System.IO.File]::WriteAllText($modulePath, "", $enc)
			$moduleCreated = $modulePath
		}
	}
}

# --- 17. Register in Configuration.xml ---

$configXmlPath = Join-Path $OutputDir "Configuration.xml"
$regResult = $null

# XML tag name for Configuration.xml ChildObjects
$childTag = $objType

if (Test-Path $configXmlPath) {
	$configDoc = New-Object System.Xml.XmlDocument
	$configDoc.PreserveWhitespace = $true
	$configDoc.Load($configXmlPath)

	$nsMgr = New-Object System.Xml.XmlNamespaceManager($configDoc.NameTable)
	$nsMgr.AddNamespace("md", "http://v8.1c.ru/8.3/MDClasses")

	$childObjects = $configDoc.SelectSingleNode("//md:Configuration/md:ChildObjects", $nsMgr)
	if ($childObjects) {
		$existing = $childObjects.SelectNodes("md:$childTag", $nsMgr)
		$alreadyExists = $false
		foreach ($e in $existing) {
			if ($e.InnerText -eq $objName) {
				$alreadyExists = $true
				break
			}
		}

		if ($alreadyExists) {
			$regResult = "already"
		} else {
			$newElem = $configDoc.CreateElement($childTag, "http://v8.1c.ru/8.3/MDClasses")
			$newElem.InnerText = $objName

			if ($existing.Count -gt 0) {
				# Insert after last existing element of same type
				$lastElem = $existing[$existing.Count - 1]
				$newWs = $configDoc.CreateWhitespace("`n`t`t`t")
				$childObjects.InsertAfter($newWs, $lastElem) | Out-Null
				$childObjects.InsertAfter($newElem, $newWs) | Out-Null
			} else {
				# No existing elements of this type — insert before closing whitespace
				$lastChild = $childObjects.LastChild
				if ($lastChild.NodeType -eq [System.Xml.XmlNodeType]::Whitespace) {
					$newWs = $configDoc.CreateWhitespace("`n`t`t`t")
					$childObjects.InsertBefore($newWs, $lastChild) | Out-Null
					$childObjects.InsertBefore($newElem, $lastChild) | Out-Null
				} else {
					$childObjects.AppendChild($configDoc.CreateWhitespace("`n`t`t`t")) | Out-Null
					$childObjects.AppendChild($newElem) | Out-Null
					$childObjects.AppendChild($configDoc.CreateWhitespace("`n`t`t")) | Out-Null
				}
			}

			# Save
			$cfgSettings = New-Object System.Xml.XmlWriterSettings
			$cfgSettings.Encoding = New-Object System.Text.UTF8Encoding($true)
			$cfgSettings.Indent = $false
			$stream = New-Object System.IO.FileStream($configXmlPath, [System.IO.FileMode]::Create)
			$writer = [System.Xml.XmlWriter]::Create($stream, $cfgSettings)
			$configDoc.Save($writer)
			$writer.Close()
			$stream.Close()

			$regResult = "added"
		}
	} else {
		$regResult = "no-childobj"
	}
} else {
	$regResult = "no-config"
}

# --- 18. Summary ---

$attrCount = 0
$tsCount = 0
$dimCount = 0
$resCount = 0
$valCount = 0

if ($def.attributes) { $attrCount = @($def.attributes).Count }
if ($def.tabularSections) { $tsCount = @($def.tabularSections.PSObject.Properties).Count }
if ($def.dimensions) { $dimCount = @($def.dimensions).Count }
if ($def.resources) { $resCount = @($def.resources).Count }
if ($def.values) { $valCount = @($def.values).Count }

Write-Host "[OK] $objType '$objName' compiled"
Write-Host "     UUID: $uuid"
Write-Host "     File: $mainXmlPath"

$details = @()
if ($attrCount -gt 0) { $details += "Attributes: $attrCount" }
if ($tsCount -gt 0)   { $details += "TabularSections: $tsCount" }
if ($dimCount -gt 0)  { $details += "Dimensions: $dimCount" }
if ($resCount -gt 0)  { $details += "Resources: $resCount" }
if ($valCount -gt 0)  { $details += "Values: $valCount" }

if ($details.Count -gt 0) {
	Write-Host "     $($details -join ', ')"
}

if ($moduleCreated) {
	Write-Host "     Module: $moduleCreated"
}

switch ($regResult) {
	"added"       { Write-Host "     Configuration.xml: <$childTag>$objName</$childTag> added to ChildObjects" }
	"already"     { Write-Host "     Configuration.xml: <$childTag>$objName</$childTag> already registered" }
	"no-childobj" { Write-Warning "Configuration.xml found but <ChildObjects> not found" }
	"no-config"   { Write-Host "     Configuration.xml: not found at $configXmlPath (register manually)" }
}
