---
name: meta-compile
description: Компиляция объекта метаданных 1С (Справочник, Документ, Перечисление, Константа, Регистр) из компактного JSON-определения
argument-hint: <JsonPath> <OutputDir>
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
---

# /meta-compile — генерация объектов метаданных из JSON DSL

Принимает JSON-определение объекта метаданных → генерирует XML + модули в структуре выгрузки конфигурации + регистрирует в Configuration.xml.

## Параметры и команда

| Параметр | Описание |
|----------|----------|
| `JsonPath` | Путь к JSON-определению объекта |
| `OutputDir` | Корневая директория выгрузки конфигурации (где `Catalogs/`, `Documents/` и т.д.) |

```powershell
powershell.exe -NoProfile -File .claude\skills\meta-compile\scripts\meta-compile.ps1 -JsonPath "<json>" -OutputDir "<ConfigDir>"
```

`OutputDir` — директория, содержащая подпапки `Catalogs/`, `Documents/`, `Enums/`, `Constants/`, `InformationRegisters/`, `AccumulationRegisters/`, а также `Configuration.xml`.

## Поддерживаемые типы

Catalog (Справочник), Document (Документ), Enum (Перечисление), Constant (Константа), InformationRegister (РегистрСведений), AccumulationRegister (РегистрНакопления).

## JSON DSL — краткий справочник

Полная спецификация: `docs/meta-dsl-spec.md`.

### Корневая структура

```json
{
  "type": "Catalog",
  "name": "Номенклатура",
  "synonym": "авто из name",
  ...type-specific...,
  "attributes": [...],
  "tabularSections": {...}
}
```

### Реквизиты — shorthand

```
"ИмяРеквизита"                     — String без квалификаторов
"ИмяРеквизита: Тип"                — с типом
"ИмяРеквизита: Тип | req, index"  — с флагами
```

Типы: `String(100)`, `Number(15,2)`, `Boolean`, `Date`, `DateTime`, `CatalogRef.Xxx`, `DocumentRef.Xxx`, `EnumRef.Xxx`, `DefinedType.Xxx`. Русские синонимы: `Строка(100)`, `Число(15,2)`, `Булево`, `Дата`, `СправочникСсылка.Xxx`.

Флаги: `req` (обязательное), `index`, `indexAdditional`, `nonneg`, `master`, `mainFilter`, `denyIncomplete`, `useInTotals`.

### Табличные части (Catalog, Document)

```json
"tabularSections": {
  "Товары": ["Номенклатура: CatalogRef.Xxx | req", "Количество: Number(10,3)"]
}
```

### Перечисления

```json
"values": ["Приход", "Расход", { "name": "НДС20", "synonym": "НДС 20%" }]
```

### Измерения и ресурсы (регистры)

```json
"dimensions": ["Организация: CatalogRef.Xxx | master, mainFilter"],
"resources": ["Количество: Number(15,3)"]
```

## Примеры

### Минимальный справочник

```json
{ "type": "Catalog", "name": "Валюты" }
```

### Перечисление

```json
{ "type": "Enum", "name": "Статусы", "values": ["Новый", "Закрыт"] }
```

### Константа

```json
{ "type": "Constant", "name": "ОсновнаяВалюта", "valueType": "CatalogRef.Валюты" }
```

### Регистр сведений

```json
{
  "type": "InformationRegister",
  "name": "КурсыВалют",
  "periodicity": "Day",
  "dimensions": ["Валюта: CatalogRef.Валюты | master, mainFilter, denyIncomplete"],
  "resources": ["Курс: Number(15,4)", "Кратность: Number(10,0)"]
}
```

## Что генерируется

- `{OutputDir}/{TypePlural}/{Name}.xml` — метаданные объекта
- `{OutputDir}/{TypePlural}/{Name}/Ext/ObjectModule.bsl` — пустой модуль (Catalog, Document)
- `{OutputDir}/{TypePlural}/{Name}/Ext/RecordSetModule.bsl` — пустой модуль (регистры)
- `Configuration.xml` — автоматическая регистрация в `<ChildObjects>`

## Верификация

```
/meta-info <OutputDir>/<TypePlural>/<Name>.xml    — проверка структуры
```
