# Meta DSL — спецификация JSON-формата для объектов метаданных 1С

Версия: 1.0

## Обзор

JSON DSL для описания объектов метаданных конфигурации 1С. Компактный формат компилируется в полноценный XML, совместимый с выгрузкой конфигурации 1С:Предприятие 8.3.

Поддерживаемые типы (Фаза 1): **Catalog**, **Document**, **Enum**, **Constant**, **InformationRegister**, **AccumulationRegister**.

---

## 1. Корневая структура

```json
{
  "type": "Catalog",
  "name": "Номенклатура",
  "synonym": "авто из name",
  "comment": "",
  ...type-specific properties...,
  "attributes": [...],
  "tabularSections": {...}
}
```

| Поле | Тип | Обязательное | Описание |
|------|-----|-------------|----------|
| `type` | string | да | Тип объекта (см. §8) |
| `name` | string | да | Имя объекта (идентификатор 1С) |
| `synonym` | string | нет | Синоним; если не указан — авто из CamelCase (§2) |
| `comment` | string | нет | Комментарий |

Дополнительные поля зависят от типа (§7).

---

## 2. Автогенерация синонима (CamelCase → слова)

Если `synonym` не указан, имя автоматически разбивается на слова:

| Вход | Результат |
|------|-----------|
| `АвансовыйОтчет` | `Авансовый отчет` |
| `ОсновнаяВалюта` | `Основная валюта` |
| `НДС20` | `НДС20` |
| `IncomingDocument` | `Incoming document` |

Правила:
- Граница на переходе `[а-яё][А-ЯЁ]` и `[a-z][A-Z]`
- Первое слово сохраняет заглавную, остальные — строчные
- Явный `synonym` перекрывает автогенерацию

---

## 3. Система типов

Совместима с skd-compile.

### 3.1 Примитивные типы

| DSL | XML |
|-----|-----|
| `String` или `String(100)` | `xs:string` + StringQualifiers |
| `Number(15,2)` | `xs:decimal` + NumberQualifiers |
| `Number(10,0,nonneg)` | `xs:decimal` + AllowedSign=Nonnegative |
| `Boolean` | `xs:boolean` |
| `Date` | `xs:dateTime` + DateFractions=Date |
| `DateTime` | `xs:dateTime` + DateFractions=DateTime |

### 3.2 Ссылочные типы

| DSL | XML |
|-----|-----|
| `CatalogRef.Xxx` | `cfg:CatalogRef.Xxx` |
| `DocumentRef.Xxx` | `cfg:DocumentRef.Xxx` |
| `EnumRef.Xxx` | `cfg:EnumRef.Xxx` |
| `ChartOfAccountsRef.Xxx` | `cfg:ChartOfAccountsRef.Xxx` |
| `DefinedType.Xxx` | `cfg:DefinedType.Xxx` (через `v8:TypeSet`) |

### 3.3 Русские синонимы типов

| Русский | Канонический |
|---------|-------------|
| `Строка(100)` | `String(100)` |
| `Число(15,2)` | `Number(15,2)` |
| `Булево` | `Boolean` |
| `Дата` | `Date` |
| `ДатаВремя` | `DateTime` |
| `СправочникСсылка.Xxx` | `CatalogRef.Xxx` |
| `ДокументСсылка.Xxx` | `DocumentRef.Xxx` |
| `ПеречислениеСсылка.Xxx` | `EnumRef.Xxx` |
| `ПланСчетовСсылка.Xxx` | `ChartOfAccountsRef.Xxx` |
| `ОпределяемыйТип.Xxx` | `DefinedType.Xxx` |

Регистронезависимые.

---

## 4. Сокращённая запись реквизитов

### 4.1 Строковая форма

```
"ИмяРеквизита"                              → String (без квалификаторов)
"ИмяРеквизита: Тип"                         → с типом
"ИмяРеквизита: Тип | req, index"           → с флагами
```

### 4.2 Объектная форма

```json
{
  "name": "Имя",
  "type": "String(100)",
  "synonym": "Мой синоним",
  "comment": "Комментарий",
  "fillChecking": "ShowError",
  "indexing": "Index"
}
```

### 4.3 Флаги

| Флаг | Действие | Применимость |
|------|---------|-------------|
| `req` | FillChecking = ShowError | attributes, dimensions, resources |
| `index` | Indexing = Index | attributes, dimensions |
| `indexAdditional` | Indexing = IndexWithAdditionalOrder | attributes |
| `nonneg` | MinValue = 0 (+ nonneg для Number) | attributes, resources |
| `master` | Master = true | dimensions (РС) |
| `mainFilter` | MainFilter = true | dimensions (РС) |
| `denyIncomplete` | DenyIncompleteValues = true | dimensions |
| `useInTotals` | UseInTotals = true | dimensions (РН) |

Флаги разделяются запятой после `|`.

---

## 5. Табличные части

Только для Catalog и Document.

```json
"tabularSections": {
  "Товары": [
    "Номенклатура: CatalogRef.Номенклатура | req",
    "Количество: Number(10,3)",
    "Цена: Number(15,2)",
    "Сумма: Number(15,2)"
  ],
  "Услуги": [
    "Описание: String(200)"
  ]
}
```

Ключ — имя табличной части, значение — массив реквизитов (в строковой или объектной форме).

---

## 6. Значения перечислений

Только для Enum.

```json
"values": [
  "Приход",
  "Расход",
  { "name": "НДС20", "synonym": "НДС 20%" }
]
```

Строка — имя (синоним авто из CamelCase). Объект — полная форма.

---

## 7. Свойства по типам

### 7.1 Catalog

| Поле JSON | Умолчание | XML элемент |
|-----------|----------|-------------|
| `hierarchical` | `false` | Hierarchical |
| `hierarchyType` | `HierarchyFoldersAndItems` | HierarchyType |
| `codeLength` | `9` | CodeLength |
| `codeType` | `String` | CodeType |
| `codeAllowedLength` | `Variable` | CodeAllowedLength |
| `descriptionLength` | `25` | DescriptionLength |
| `autonumbering` | `true` | Autonumbering |
| `checkUnique` | `false` | CheckUnique |
| `defaultPresentation` | `AsDescription` | DefaultPresentation |
| `dataLockControlMode` | `Automatic` | DataLockControlMode |
| `fullTextSearch` | `Use` | FullTextSearch |
| `owners` | `[]` | Owners |
| `attributes` | `[]` | → Attribute в ChildObjects |
| `tabularSections` | `{}` | → TabularSection в ChildObjects |

### 7.2 Document

| Поле JSON | Умолчание | XML элемент |
|-----------|----------|-------------|
| `numberType` | `String` | NumberType |
| `numberLength` | `11` | NumberLength |
| `numberAllowedLength` | `Variable` | NumberAllowedLength |
| `numberPeriodicity` | `Year` | NumberPeriodicity |
| `checkUnique` | `true` | CheckUnique |
| `autonumbering` | `true` | Autonumbering |
| `posting` | `Allow` | Posting |
| `realTimePosting` | `Deny` | RealTimePosting |
| `registerRecordsDeletion` | `AutoDelete` | RegisterRecordsDeletion |
| `registerRecordsWritingOnPost` | `WriteModified` | RegisterRecordsWritingOnPost |
| `postInPrivilegedMode` | `true` | PostInPrivilegedMode |
| `unpostInPrivilegedMode` | `true` | UnpostInPrivilegedMode |
| `dataLockControlMode` | `Automatic` | DataLockControlMode |
| `fullTextSearch` | `Use` | FullTextSearch |
| `registerRecords` | `[]` | RegisterRecords |
| `attributes` | `[]` | → Attribute в ChildObjects |
| `tabularSections` | `{}` | → TabularSection в ChildObjects |

### 7.3 Enum

| Поле JSON | Умолчание | XML элемент |
|-----------|----------|-------------|
| `values` | `[]` | → EnumValue в ChildObjects |

Других настраиваемых свойств нет — все дефолтные.

### 7.4 Constant

| Поле JSON | Умолчание | XML элемент |
|-----------|----------|-------------|
| `valueType` | `String` | Type |
| `dataLockControlMode` | `Automatic` | DataLockControlMode |

### 7.5 InformationRegister

| Поле JSON | Умолчание | XML элемент |
|-----------|----------|-------------|
| `writeMode` | `Independent` | WriteMode |
| `periodicity` | `Nonperiodical` | InformationRegisterPeriodicity |
| `mainFilterOnPeriod` | авто* | MainFilterOnPeriod |
| `dataLockControlMode` | `Automatic` | DataLockControlMode |
| `fullTextSearch` | `Use` | FullTextSearch |
| `dimensions` | `[]` | → Dimension в ChildObjects |
| `resources` | `[]` | → Resource в ChildObjects |
| `attributes` | `[]` | → Attribute в ChildObjects |

\* `mainFilterOnPeriod` = `true` если `periodicity` != `Nonperiodical`, иначе `false`.

### 7.6 AccumulationRegister

| Поле JSON | Умолчание | XML элемент |
|-----------|----------|-------------|
| `registerType` | `Balance` | RegisterType |
| `enableTotalsSplitting` | `true` | EnableTotalsSplitting |
| `dataLockControlMode` | `Automatic` | DataLockControlMode |
| `fullTextSearch` | `Use` | FullTextSearch |
| `dimensions` | `[]` | → Dimension в ChildObjects |
| `resources` | `[]` | → Resource в ChildObjects |
| `attributes` | `[]` | → Attribute в ChildObjects |

---

## 8. Русские синонимы типов объектов

| Русский | Канонический |
|---------|-------------|
| `Справочник` | `Catalog` |
| `Документ` | `Document` |
| `Перечисление` | `Enum` |
| `Константа` | `Constant` |
| `РегистрСведений` | `InformationRegister` |
| `РегистрНакопления` | `AccumulationRegister` |

---

## 9. RegisterRecords для документов

```json
"registerRecords": [
  "AccumulationRegister.Продажи",
  "InformationRegister.Цены"
]
```

Или с русскими синонимами: `"РегистрНакопления.Продажи"`.

---

## 10. Измерения и ресурсы регистров

Синтаксис аналогичен реквизитам (§4), но с дополнительными флагами:

### Измерения (dimensions)

```json
"dimensions": [
  "Организация: CatalogRef.Организации | master, mainFilter, denyIncomplete",
  "Номенклатура: CatalogRef.Номенклатура"
]
```

### Ресурсы (resources)

```json
"resources": [
  "Количество: Number(15,3)",
  "Сумма: Number(15,2)"
]
```

Флаг `useInTotals` — только для измерений AccumulationRegister (по умолчанию `true`).

---

## 11. Примеры

### Минимальные

```json
{ "type": "Catalog", "name": "Валюты" }
```

```json
{ "type": "Enum", "name": "Статусы", "values": ["Новый", "Закрыт"] }
```

```json
{ "type": "Constant", "name": "ОсновнаяВалюта", "valueType": "CatalogRef.Валюты" }
```

### Справочник с реквизитами и табличной частью

```json
{
  "type": "Catalog",
  "name": "Номенклатура",
  "codeLength": 11,
  "descriptionLength": 100,
  "hierarchical": true,
  "attributes": [
    "Артикул: String(25)",
    "ЕдиницаИзмерения: CatalogRef.ЕдиницыИзмерения | req",
    "ВидНоменклатуры: EnumRef.ВидыНоменклатуры",
    "Цена: Number(15,2)"
  ],
  "tabularSections": {
    "Штрихкоды": [
      "Штрихкод: String(200) | req, index"
    ]
  }
}
```

### Документ с движениями

```json
{
  "type": "Document",
  "name": "РеализацияТоваров",
  "posting": "Allow",
  "registerRecords": ["AccumulationRegister.Продажи"],
  "attributes": [
    "Организация: CatalogRef.Организации | req",
    "Контрагент: CatalogRef.Контрагенты | req",
    "Склад: CatalogRef.Склады"
  ],
  "tabularSections": {
    "Товары": [
      "Номенклатура: CatalogRef.Номенклатура | req",
      "Количество: Number(15,3)",
      "Цена: Number(15,2)",
      "Сумма: Number(15,2)"
    ]
  }
}
```

### Регистр сведений с периодичностью

```json
{
  "type": "InformationRegister",
  "name": "КурсыВалют",
  "periodicity": "Day",
  "dimensions": [
    "Валюта: CatalogRef.Валюты | master, mainFilter, denyIncomplete"
  ],
  "resources": [
    "Курс: Number(15,4)",
    "Кратность: Number(10,0)"
  ]
}
```

### Регистр накопления

```json
{
  "type": "AccumulationRegister",
  "name": "ОстаткиТоваров",
  "registerType": "Balance",
  "dimensions": [
    "Номенклатура: CatalogRef.Номенклатура",
    "Склад: CatalogRef.Склады"
  ],
  "resources": [
    "Количество: Number(15,3)"
  ]
}
```
