---
name: role-compile
description: Создание роли 1С — метаданные и Rights.xml из описания прав
argument-hint: <JsonPath> <RolesDir>
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
---

# /role-compile — генерация роли 1С из JSON DSL

Принимает компактное JSON-определение роли и генерирует два файла: метаданные (`Roles/Имя.xml`) и права (`Roles/Имя/Ext/Rights.xml`). UUID генерируется автоматически.

## Использование

```
/role-compile <JsonPath> <RolesDir>
```

## Параметры

| Параметр | Обязательный | Описание |
|----------|:------------:|----------|
| JsonPath | да | Путь к JSON-определению роли |
| RolesDir | да | Каталог `Roles/` в исходниках конфигурации |

## Команда

```powershell
powershell.exe -NoProfile -File .claude\skills\role-compile\scripts\role-compile.ps1 -JsonPath "<json>" -OutputDir "<RolesDir>"
```

## Выходные файлы

```
RolesDir/
  ИмяРоли.xml              ← метаданные (uuid, имя, синоним)
  ИмяРоли/
    Ext/
      Rights.xml            ← определение прав
```

После генерации: добавить `<Role>ИмяРоли</Role>` в `<ChildObjects>` файла `Configuration.xml`.

## JSON DSL — справка

### Структура верхнего уровня

```json
{
  "name": "ИмяРоли",
  "synonym": "Отображаемое имя роли",
  "comment": "",
  "setForNewObjects": false,
  "setForAttributesByDefault": true,
  "independentRightsOfChildObjects": false,
  "objects": [ ... ],
  "templates": [ ... ]
}
```

- `name` — программное имя роли (обязательно)
- `synonym` — отображаемое имя (по умолчанию = name)
- `comment` — комментарий (по умолчанию пусто)
- Глобальные флаги — по умолчанию `false`, `true`, `false`

### Объекты: два формата

Массив `objects` принимает строки (shorthand) и объекты (полная форма).

#### Строковый shorthand

```
"ОбъектМетаданных: @пресет"
"ОбъектМетаданных: Право1, Право2"
```

Примеры:
```json
"objects": [
  "Catalog.Номенклатура: @view",
  "Document.Реализация: @edit",
  "InformationRegister.Цены: Read, Update",
  "DataProcessor.Загрузка: @use"
]
```

#### Объектная форма (для RLS и переопределений)

```json
{
  "name": "Document.Реализация",
  "preset": "view",
  "rights": { "Delete": false },
  "rls": { "Read": "#ДляОбъекта(\"\")" }
}
```

- `preset` — базовый набор прав (`"view"`, `"edit"`, `"use"`)
- `rights` — переопределения: dict `{"Right": true/false}` или массив `["Right1", "Right2"]`
- `rls` — RLS-ограничения: `{"ИмяПрава": "текст условия"}`

### Пресеты (`@view`, `@edit`, `@use`)

Пресеты обозначаются `@` в строковом формате. В объектной форме ключ `preset` без `@`.

#### `@view` — просмотр

| Тип объекта | Права |
|-------------|-------|
| Catalog, ExchangePlan, Document, ChartOfAccounts, ChartOfCharacteristicTypes, ChartOfCalculationTypes, BusinessProcess, Task | Read, View, InputByString |
| InformationRegister, AccumulationRegister, AccountingRegister, CalculationRegister, Constant, DocumentJournal | Read, View |
| Sequence | Read |
| CommonForm, CommonCommand, Subsystem, FilterCriterion, CommonAttribute | View |
| SessionParameter | Get |
| Configuration | ThinClient, WebClient, Output, SaveUserData, MainWindowModeNormal |

#### `@edit` — полное редактирование

| Тип объекта | Права |
|-------------|-------|
| Catalog, ExchangePlan, ChartOfAccounts, ChartOfCharacteristicTypes, ChartOfCalculationTypes | Read, Insert, Update, Delete, View, Edit, InputByString, InteractiveInsert, InteractiveSetDeletionMark, InteractiveClearDeletionMark |
| Document | Read, Insert, Update, Delete, View, Edit, InputByString, Posting, UndoPosting, InteractiveInsert, InteractiveSetDeletionMark, InteractiveClearDeletionMark, InteractivePosting, InteractivePostingRegular, InteractiveUndoPosting, InteractiveChangeOfPosted |
| BusinessProcess | Read, Insert, Update, Delete, View, Edit, InputByString, Start, InteractiveInsert, InteractiveSetDeletionMark, InteractiveClearDeletionMark, InteractiveActivate, InteractiveStart |
| Task | Read, Insert, Update, Delete, View, Edit, InputByString, Execute, InteractiveInsert, InteractiveSetDeletionMark, InteractiveClearDeletionMark, InteractiveActivate, InteractiveExecute |
| InformationRegister, AccumulationRegister, AccountingRegister, Constant | Read, Update, View, Edit |
| DocumentJournal | Read, View |
| Sequence | Read, Update |
| SessionParameter | Get, Set |
| CommonAttribute | View, Edit |

#### `@use` — использование

| Тип объекта | Права |
|-------------|-------|
| DataProcessor, Report | Use, View |
| CommonForm, CommonCommand, Subsystem | View |
| WebService, HTTPService, IntegrationService | Use |

Если пресет не определён для типа объекта — предупреждение с подсказкой доступных.

### Русские синонимы

Скрипт автоматически транслирует русские имена в английские. Можно смешивать: `"Справочник.Контрагенты: Чтение, View"` — работает.

**Типы объектов:**

| Русский | English |
|---------|---------|
| `Справочник` | Catalog |
| `Документ` | Document |
| `РегистрСведений` | InformationRegister |
| `РегистрНакопления` | AccumulationRegister |
| `РегистрБухгалтерии` | AccountingRegister |
| `РегистрРасчета` | CalculationRegister |
| `Константа` | Constant |
| `ПланСчетов` | ChartOfAccounts |
| `ПланВидовХарактеристик` | ChartOfCharacteristicTypes |
| `ПланВидовРасчета` | ChartOfCalculationTypes |
| `ПланОбмена` | ExchangePlan |
| `БизнесПроцесс` | BusinessProcess |
| `Задача` | Task |
| `Обработка` | DataProcessor |
| `Отчет` | Report |
| `ОбщаяФорма` | CommonForm |
| `ОбщаяКоманда` | CommonCommand |
| `Подсистема` | Subsystem |
| `КритерийОтбора` | FilterCriterion |
| `ЖурналДокументов` | DocumentJournal |
| `Последовательность` | Sequence |
| `ВебСервис` | WebService |
| `HTTPСервис` | HTTPService |
| `СервисИнтеграции` | IntegrationService |
| `ПараметрСеанса` | SessionParameter |
| `ОбщийРеквизит` | CommonAttribute |
| `Конфигурация` | Configuration |
| `Перечисление` | Enum |

Вложенные типы: `Реквизит` → Attribute, `СтандартныйРеквизит` → StandardAttribute, `ТабличнаяЧасть` → TabularSection, `Измерение` → Dimension, `Ресурс` → Resource, `Команда` → Command, `РеквизитАдресации` → AddressingAttribute.

**Права (основные):**

| Русский | English |
|---------|---------|
| `Чтение` | Read |
| `Добавление` | Insert |
| `Изменение` | Update |
| `Удаление` | Delete |
| `Просмотр` | View |
| `Редактирование` | Edit |
| `ВводПоСтроке` | InputByString |
| `Проведение` | Posting |
| `ОтменаПроведения` | UndoPosting |
| `Использование` | Use |
| `Получение` | Get |
| `Установка` | Set |
| `Старт` | Start |
| `Выполнение` | Execute |
| `УправлениеИтогами` | TotalsControl |

**Права (интерактивные):**

| Русский | English |
|---------|---------|
| `ИнтерактивноеДобавление` | InteractiveInsert |
| `ИнтерактивнаяПометкаУдаления` | InteractiveSetDeletionMark |
| `ИнтерактивноеСнятиеПометкиУдаления` | InteractiveClearDeletionMark |
| `ИнтерактивноеУдаление` | InteractiveDelete |
| `ИнтерактивноеУдалениеПомеченных` | InteractiveDeleteMarked |
| `ИнтерактивноеПроведение` | InteractivePosting |
| `ИнтерактивноеПроведениеНеоперативное` | InteractivePostingRegular |
| `ИнтерактивнаяОтменаПроведения` | InteractiveUndoPosting |
| `ИнтерактивноеИзменениеПроведенных` | InteractiveChangeOfPosted |
| `ИнтерактивныйСтарт` | InteractiveStart |
| `ИнтерактивнаяАктивация` | InteractiveActivate |
| `ИнтерактивноеВыполнение` | InteractiveExecute |

**Права (конфигурация):**

| Русский | English |
|---------|---------|
| `Администрирование` | Administration |
| `АдминистрированиеДанных` | DataAdministration |
| `ТонкийКлиент` | ThinClient |
| `ТолстыйКлиент` | ThickClient |
| `ВебКлиент` | WebClient |
| `МобильныйКлиент` | MobileClient |
| `ВнешнееСоединение` | ExternalConnection |
| `Вывод` | Output |
| `СохранениеДанныхПользователя` | SaveUserData |

### Шаблоны ограничений (RLS templates)

```json
"templates": [
  {
    "name": "ДляОбъекта(Модификатор)",
    "condition": "// текст шаблона\nГДЕ 1=1\n&Модификатор"
  }
]
```

`&` в условии автоматически экранируется в `&amp;` в XML.

## Примеры

### Простая роль (только пресеты)

```json
{
  "name": "ЧтениеНоменклатуры",
  "synonym": "Чтение номенклатуры",
  "objects": [
    "Catalog.Номенклатура: @view",
    "Catalog.Контрагенты: @view",
    "DataProcessor.Загрузка: @use"
  ]
}
```

### Роль для регламентного задания

```json
{
  "name": "ОбновлениеЦен",
  "synonym": "Обновление цен номенклатуры",
  "objects": [
    "Catalog.Номенклатура: Read",
    "Catalog.Валюты: Read",
    "InformationRegister.ЦеныНоменклатуры: Read, Update",
    "Constant.ОсновнаяВалюта: Read"
  ]
}
```

### Роль с RLS

```json
{
  "name": "ЧтениеДокументовПоОрганизации",
  "synonym": "Чтение документов (ограничение по организации)",
  "objects": [
    "Catalog.Организации: @view",
    {
      "name": "Document.РеализацияТоваровУслуг",
      "preset": "view",
      "rls": {
        "Read": "#ДляОбъекта(\"\")"
      }
    }
  ],
  "templates": [
    {
      "name": "ДляОбъекта(Модификатор)",
      "condition": "ГДЕ Организация = &ТекущаяОрганизация"
    }
  ]
}
```

### Роль с русскими синонимами

```json
{
  "name": "ПросмотрДанных",
  "synonym": "Просмотр данных",
  "objects": [
    "Справочник.Контрагенты: @view",
    "Документ.Реализация: Чтение, Просмотр",
    "РегистрСведений.Цены: @edit",
    "Обработка.ЗагрузкаДанных: @use"
  ]
}
```

### Роль с переопределением прав из пресета

```json
{
  "name": "ОграниченноеРедактирование",
  "synonym": "Редактирование без удаления",
  "objects": [
    {
      "name": "Catalog.Контрагенты",
      "preset": "edit",
      "rights": { "Delete": false }
    }
  ]
}
```

## Верификация

```
/role-validate <RightsPath> [MetadataPath]  — проверка корректности XML, прав, RLS
/role-info <RightsPath>                     — визуальная сводка структуры
```
