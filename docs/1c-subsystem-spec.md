# Спецификация формата XML подсистем и командного интерфейса 1С

Формат: XML-выгрузка конфигурации 1С:Предприятие 8.3 (Конфигуратор → Конфигурация → Выгрузить конфигурацию в файлы).
Версии формата: `2.17` (платформа 8.3.20–8.3.24), `2.20` (платформа 8.3.27+).

Источники: выгрузки Бухгалтерия предприятия (платформы 8.3.20, 8.3.24, 8.3.27), ERP 2 (8.3.24).

---

## 1. Структура каталогов

### 1.1. Подсистемы (Subsystems)

Подсистемы организуют иерархическое дерево в каталоге `Subsystems/`:

```
Subsystems/
├── ПодсистемаА.xml                       # Определение подсистемы
├── ПодсистемаА/                          # Каталог подсистемы (если есть вложенные или CommandInterface)
│   ├── Ext/
│   │   └── CommandInterface.xml          # Командный интерфейс подсистемы (опционально)
│   └── Subsystems/                       # Вложенные подсистемы (опционально)
│       ├── Дочерняя1.xml
│       ├── Дочерняя1/
│       │   ├── Ext/
│       │   │   └── CommandInterface.xml
│       │   └── Subsystems/
│       │       └── Внучатая1.xml         # Вложенность до 3+ уровней
│       └── Дочерняя2.xml
├── ПодсистемаБ.xml                       # Лист — без каталога
└── ...
```

**Правила:**
- Каждая подсистема имеет файл `<Имя>.xml` (обязательно)
- Каталог `<Имя>/` создаётся только если есть вложенные подсистемы или файл `Ext/CommandInterface.xml`
- Вложенные подсистемы хранятся в `<Имя>/Subsystems/` — рекурсивно повторяя ту же структуру
- Глубина вложенности не ограничена (на практике до 3–4 уровней)

### 1.2. Командный интерфейс конфигурации (корневой)

```
Ext/
└── CommandInterface.xml              # Глобальный командный интерфейс — порядок разделов
```

Корневой `CommandInterface.xml` определяет порядок подсистем верхнего уровня в панели разделов.

---

## 2. Пространства имён XML

### 2.1. Подсистема (файл метаданных)

Корневой элемент — `<MetaDataObject>`, стандартный набор деклараций:

```xml
<MetaDataObject
    xmlns="http://v8.1c.ru/8.3/MDClasses"
    xmlns:app="http://v8.1c.ru/8.2/managed-application/core"
    xmlns:cfg="http://v8.1c.ru/8.1/data/enterprise/current-config"
    xmlns:cmi="http://v8.1c.ru/8.2/managed-application/cmi"
    xmlns:ent="http://v8.1c.ru/8.1/data/enterprise"
    xmlns:lf="http://v8.1c.ru/8.2/managed-application/logform"
    xmlns:style="http://v8.1c.ru/8.1/data/ui/style"
    xmlns:sys="http://v8.1c.ru/8.1/data/ui/fonts/system"
    xmlns:v8="http://v8.1c.ru/8.1/data/core"
    xmlns:v8ui="http://v8.1c.ru/8.1/data/ui"
    xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web"
    xmlns:win="http://v8.1c.ru/8.1/data/ui/colors/windows"
    xmlns:xen="http://v8.1c.ru/8.3/xcf/enums"
    xmlns:xpr="http://v8.1c.ru/8.3/xcf/predef"
    xmlns:xr="http://v8.1c.ru/8.3/xcf/readable"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="2.17">
```

### 2.2. Командный интерфейс (CommandInterface.xml)

Корневой элемент — `<CommandInterface>`:

```xml
<CommandInterface
    xmlns="http://v8.1c.ru/8.3/xcf/extrnprops"
    xmlns:xr="http://v8.1c.ru/8.3/xcf/readable"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="2.17">
```

---

## 3. Формат подсистемы

### 3.1. Общая структура

```xml
<?xml version="1.0" encoding="UTF-8"?>
<MetaDataObject xmlns="..." version="2.17">
    <Subsystem uuid="<UUID>">
        <Properties>
            <Name>ИмяПодсистемы</Name>
            <Synonym>...</Synonym>
            <Comment/>
            <IncludeHelpInContents>true</IncludeHelpInContents>
            <IncludeInCommandInterface>true</IncludeInCommandInterface>
            <UseOneCommand>false</UseOneCommand>
            <Explanation>...</Explanation>
            <Picture>...</Picture>
            <Content>...</Content>
        </Properties>
        <ChildObjects>
            <Subsystem>Дочерняя1</Subsystem>
            <Subsystem>Дочерняя2</Subsystem>
        </ChildObjects>
    </Subsystem>
</MetaDataObject>
```

### 3.2. Свойства (Properties)

| Свойство | Тип | Обязательно | Описание |
|---|---|---|---|
| `Name` | string | да | Программное имя (CamelCase, без пробелов) |
| `Synonym` | LocalString | да | Отображаемое имя (локализованное) |
| `Comment` | string | да | Комментарий. Обычно пустой тег `<Comment/>` |
| `IncludeHelpInContents` | bool | да | Включать справку в содержание |
| `IncludeInCommandInterface` | bool | да | Отображать в командном интерфейсе (`true` — раздел видим) |
| `UseOneCommand` | bool | да | Использовать единственную команду (подсистема-ярлык). `true` — при открытии сразу выполняется единственная команда из Content |
| `Explanation` | LocalString | да | Подсказка при наведении на раздел. Пустой тег если не задана |
| `Picture` | Picture | да | Иконка раздела. Пустой тег `<Picture/>` если не задана |
| `Content` | Content | да | Список включённых объектов метаданных. Пустой тег `<Content/>` если нет |

#### Synonym, Explanation (LocalString)

Локализованная строка с элементами по языкам:

```xml
<Synonym>
    <v8:item>
        <v8:lang>ru</v8:lang>
        <v8:content>Администрирование</v8:content>
    </v8:item>
    <v8:item>
        <v8:lang>en</v8:lang>
        <v8:content>Administration</v8:content>
    </v8:item>
</Synonym>
```

Может быть пустым тегом: `<Explanation/>`

#### Picture

Ссылка на общую картинку конфигурации:

```xml
<Picture>
    <xr:Ref>CommonPicture.Администрирование</xr:Ref>
    <xr:LoadTransparent>false</xr:LoadTransparent>
</Picture>
```

- `xr:Ref` — ссылка на объект `CommonPicture.<Имя>`
- `xr:LoadTransparent` — загружать с прозрачностью (`true`/`false`)
- Пустой тег `<Picture/>` если иконка не задана

#### Content

Список объектов метаданных, включённых в подсистему:

```xml
<Content>
    <xr:Item xsi:type="xr:MDObjectRef">Catalog.Номенклатура</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">Document.РеализацияТоваровУслуг</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">Report.Продажи</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">CommonCommand.Настройки</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">FunctionalOption.ИспользоватьСклады</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">Constant.ИспользоватьСклады</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">CommandGroup.Настройки</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">Role.ПодсистемаПродажи</xr:Item>
</Content>
```

Каждый элемент `<xr:Item>` имеет фиксированный атрибут `xsi:type="xr:MDObjectRef"` и содержит полный путь объекта в формате `<ТипОбъекта>.<Имя>`.

**Встречающиеся типы объектов в Content:**

| Тип | Пример |
|---|---|
| `Catalog` | `Catalog.Номенклатура` |
| `Document` | `Document.РеализацияТоваровУслуг` |
| `Report` | `Report.Продажи` |
| `DataProcessor` | `DataProcessor.ПанельАдминистрирования` |
| `CommonModule` | `CommonModule.МодульОбщий` |
| `CommonCommand` | `CommonCommand.Настройки` |
| `CommonForm` | `CommonForm.ФормаОбщая` |
| `CommonPicture` | `CommonPicture.КартинкаОбщая` |
| `CommandGroup` | `CommandGroup.Настройки` |
| `Constant` | `Constant.ИспользоватьСклады` |
| `FunctionalOption` | `FunctionalOption.ИспользоватьСклады` |
| `Enum` | `Enum.ВидыОпераций` |
| `Role` | `Role.ПодсистемаПродажи` |
| `InformationRegister` | `InformationRegister.КурсыВалют` |
| `AccumulationRegister` | `AccumulationRegister.Продажи` |
| `AccountingRegister` | `AccountingRegister.Хозрасчетный` |
| `ChartOfAccounts` | `ChartOfAccounts.Хозрасчетный` |
| `ChartOfCharacteristicTypes` | `ChartOfCharacteristicTypes.Виды` |
| `ExchangePlan` | `ExchangePlan.ОбменДанными` |
| `DocumentJournal` | `DocumentJournal.Журнал` |
| UUID (ссылка по идентификатору) | `cf4e9dea-4052-4a62-8427-0d37e8c47a23` |

> **UUID-ссылки**: Некоторые элементы Content содержат UUID вместо именованной ссылки. Это ссылки на объекты из расширений или объекты, которые были удалены/переименованы.

Пустой тег `<Content/>` — подсистема не содержит объектов (организующая подсистема).

### 3.3. Дочерние объекты (ChildObjects)

Список вложенных подсистем:

```xml
<ChildObjects>
    <Subsystem>НастройкиПрограммы</Subsystem>
    <Subsystem>Пользователи</Subsystem>
    <Subsystem>ПроведениеДокументов</Subsystem>
</ChildObjects>
```

- Каждый `<Subsystem>` содержит только **имя** дочерней подсистемы (не UUID, не путь)
- Порядок элементов значим — определяет порядок в дереве конфигурации
- Пустой тег `<ChildObjects/>` — лист дерева, нет вложенных подсистем
- Определения дочерних подсистем находятся в `<ИмяРодителя>/Subsystems/<ИмяДочерней>.xml`

### 3.4. Типовые паттерны подсистем

**Организующая подсистема** — содержит только дочерние, без собственных объектов:
```xml
<Content/>
<ChildObjects>
    <Subsystem>Дочерняя1</Subsystem>
    <Subsystem>Дочерняя2</Subsystem>
</ChildObjects>
```

**Листовая подсистема** — содержит объекты, без вложенных:
```xml
<Content>
    <xr:Item xsi:type="xr:MDObjectRef">Catalog.Товары</xr:Item>
</Content>
<ChildObjects/>
```

**Подсистема-ярлык** (`UseOneCommand=true`) — открывает единственную команду:
```xml
<UseOneCommand>true</UseOneCommand>
<Content>
    <xr:Item xsi:type="xr:MDObjectRef">DataProcessor.Помощь</xr:Item>
</Content>
<ChildObjects/>
```

**Смешанная подсистема** — и объекты, и дочерние:
```xml
<Content>
    <xr:Item xsi:type="xr:MDObjectRef">CommonModule.Модуль</xr:Item>
    <xr:Item xsi:type="xr:MDObjectRef">Report.Отчёт</xr:Item>
</Content>
<ChildObjects>
    <Subsystem>Дочерняя1</Subsystem>
</ChildObjects>
```

---

## 4. Формат командного интерфейса (CommandInterface.xml)

### 4.1. Общая структура

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CommandInterface xmlns="http://v8.1c.ru/8.3/xcf/extrnprops"
    xmlns:xr="http://v8.1c.ru/8.3/xcf/readable"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="2.17">
    <CommandsVisibility>...</CommandsVisibility>       <!-- опционально -->
    <CommandsPlacement>...</CommandsPlacement>          <!-- опционально -->
    <CommandsOrder>...</CommandsOrder>                  <!-- опционально -->
    <SubsystemsOrder>...</SubsystemsOrder>             <!-- опционально -->
    <GroupsOrder>...</GroupsOrder>                      <!-- опционально -->
</CommandInterface>
```

Все 5 дочерних элементов опциональны. Порядок фиксирован: `CommandsVisibility` → `CommandsPlacement` → `CommandsOrder` → `SubsystemsOrder` → `GroupsOrder`.

### 4.2. Два уровня CommandInterface

| Уровень | Путь | Типичное содержание |
|---|---|---|
| **Корневой** (конфигурация) | `Ext/CommandInterface.xml` | Только `SubsystemsOrder` — порядок разделов верхнего уровня |
| **Подсистема** | `Subsystems/<Имя>/Ext/CommandInterface.xml` | Любая комбинация из 5 секций |

#### Корневой командный интерфейс

Содержит только порядок подсистем верхнего уровня:

```xml
<CommandInterface xmlns="..." version="2.17">
    <SubsystemsOrder>
        <Subsystem>Subsystem.Руководителю</Subsystem>
        <Subsystem>Subsystem.БанкИКасса</Subsystem>
        <Subsystem>Subsystem.Продажи</Subsystem>
        <Subsystem>Subsystem.Покупки</Subsystem>
        <Subsystem>Subsystem.Администрирование</Subsystem>
    </SubsystemsOrder>
</CommandInterface>
```

### 4.3. CommandsVisibility — видимость команд

Управляет видимостью отдельных команд в разделе:

```xml
<CommandsVisibility>
    <Command name="Catalog.Номенклатура.StandardCommand.OpenList">
        <Visibility>
            <xr:Common>false</xr:Common>
        </Visibility>
    </Command>
    <Command name="Report.Продажи.Command.ПродажиПоКонтрагентам">
        <Visibility>
            <xr:Common>true</xr:Common>
        </Visibility>
    </Command>
</CommandsVisibility>
```

**Элемент `Command`:**
- Атрибут `name` — полный путь команды (см. [формат ссылок на команды](#46-формат-ссылок-на-команды))
- `Visibility` > `xr:Common` — видимость для всех пользователей: `true` (видима) / `false` (скрыта)

> **Семантика**: Определяет какие команды видимы/скрыты **по умолчанию** для всех пользователей в данном разделе. Перечисляются только команды, чья видимость **отличается** от автоматической.

### 4.4. CommandsPlacement — размещение команд в группах

Определяет в какую группу команд помещается команда:

```xml
<CommandsPlacement>
    <Command name="Report.Продажи.Command.ПродажиПоКонтрагентам">
        <CommandGroup>CommandGroup.Отчеты</CommandGroup>
        <Placement>Auto</Placement>
    </Command>
    <Command name="DataProcessor.Настройки.Command.Открыть">
        <CommandGroup>NavigationPanelOrdinary</CommandGroup>
        <Placement>Auto</Placement>
    </Command>
</CommandsPlacement>
```

**Элемент `Command`:**
- `name` — ссылка на команду
- `CommandGroup` — идентификатор группы (см. [стандартные группы](#47-группы-команд))
- `Placement` — стратегия размещения. Единственное наблюдаемое значение: `Auto`

### 4.5. CommandsOrder — порядок команд

Определяет порядок отображения команд внутри групп:

```xml
<CommandsOrder>
    <Command name="Document.СчётНаОплату.StandardCommand.Create">
        <CommandGroup>ActionsPanelCreate</CommandGroup>
    </Command>
    <Command name="Document.Реализация.StandardCommand.Create">
        <CommandGroup>ActionsPanelCreate</CommandGroup>
    </Command>
    <Command name="Report.Продажи.Command.ПродажиПоКонтрагентам">
        <CommandGroup>CommandGroup.Отчеты</CommandGroup>
    </Command>
</CommandsOrder>
```

**Элемент `Command`:**
- `name` — ссылка на команду
- `CommandGroup` — группа, в которой определяется порядок

Команды отображаются в порядке их перечисления в `CommandsOrder`.

### 4.6. SubsystemsOrder — порядок вложенных подсистем

Определяет порядок дочерних подсистем в навигационной панели:

```xml
<SubsystemsOrder>
    <Subsystem>Subsystem.Продажи.Subsystem.ПродажиГлавное</Subsystem>
    <Subsystem>Subsystem.Продажи.Subsystem.РозничныеПродажи</Subsystem>
    <Subsystem>Subsystem.Продажи.Subsystem.РасчетыСКонтрагентами</Subsystem>
</SubsystemsOrder>
```

**Формат пути подсистемы:**
- Корневой уровень: `Subsystem.<Имя>`
- Вложенный уровень: `Subsystem.<Родитель>.Subsystem.<Дочерняя>`
- Глубже: `Subsystem.<A>.Subsystem.<B>.Subsystem.<C>`

> **В корневом CommandInterface** используются пути `Subsystem.<Имя>` (верхний уровень).
> **В CommandInterface подсистемы** используются полные пути от корня: `Subsystem.<Родитель>.Subsystem.<Дочерняя>`.

### 4.7. GroupsOrder — порядок групп команд

Определяет порядок отображения самих групп:

```xml
<GroupsOrder>
    <Group>NavigationPanelOrdinary</Group>
    <Group>CommandGroup.НачальноеЗаполнение</Group>
    <Group>NavigationPanelSeeAlso</Group>
    <Group>ActionsPanelTools</Group>
    <Group>CommandGroup.Отчеты</Group>
    <Group>CommandGroup.Сервис</Group>
    <Group>CommandGroup.Информация</Group>
</GroupsOrder>
```

---

## 5. Формат ссылок на команды

Атрибут `name` в элементах `Command` использует точечную нотацию:

### 5.1. Стандартные команды (StandardCommand)

```
<ТипОбъекта>.<ИмяОбъекта>.StandardCommand.<Операция>
```

| Операция | Назначение |
|---|---|
| `OpenList` | Открыть список |
| `Open` | Открыть (для отчётов, обработок, общих форм) |
| `Create` | Создать новый |
| `CreateFolder` | Создать группу (для иерархических справочников) |

**Примеры:**
- `Catalog.Номенклатура.StandardCommand.OpenList`
- `Document.Реализация.StandardCommand.Create`
- `Report.Продажи.StandardCommand.Open`
- `DataProcessor.Настройки.StandardCommand.Open`
- `CommonForm.ФормаОбщая.StandardCommand.Open`
- `InformationRegister.КурсыВалют.StandardCommand.OpenList`
- `DocumentJournal.ЖурналДокументов.StandardCommand.OpenList`

### 5.2. Пользовательские команды (Command)

```
<ТипОбъекта>.<ИмяОбъекта>.Command.<ИмяКоманды>
```

**Примеры:**
- `Report.Продажи.Command.ПродажиПоКонтрагентам`
- `DataProcessor.Панель.Command.ОткрытьНастройки`
- `Catalog.Оборудование.Command.ОткрытьОборудование`
- `InformationRegister.Настройки.Command.ОбменДанными`
- `ExchangePlan.Мобильное.Command.ОткрытьНастройки`

### 5.3. Общие команды (CommonCommand)

```
CommonCommand.<ИмяКоманды>
```

**Примеры:**
- `CommonCommand.НастройкиСинхронизацииДанных`
- `CommonCommand.ДополнительныеОбработкиПродажи`
- `CommonCommand.ПерсональныеНастройки`

### 5.4. UUID-ссылки

```
0:<UUID>
```

**Пример:** `0:91941f81-07dd-43a0-9baa-f5969b7472db`

Формат `0:<UUID>` используется для команд из расширений или ссылок на объекты, недоступные по имени.

---

## 6. Группы команд (CommandGroup)

### 6.1. Стандартные группы панелей

| Идентификатор | Панель | Описание |
|---|---|---|
| `NavigationPanelImportant` | Навигация | Важные команды (верхняя часть) |
| `NavigationPanelOrdinary` | Навигация | Обычные команды |
| `NavigationPanelSeeAlso` | Навигация | Блок «См. также» (нижняя часть) |
| `ActionsPanelCreate` | Действия | Блок «Создать» |
| `ActionsPanelTools` | Действия | Блок «Сервис» |

### 6.2. Пользовательские группы

```
CommandGroup.<ИмяГруппы>
```

Ссылаются на объекты метаданных `CommandGroup`, определённые в конфигурации (каталог `CommandGroups/`).

**Типичные примеры:**
- `CommandGroup.Настройки`
- `CommandGroup.Отчеты`
- `CommandGroup.Сервис`
- `CommandGroup.Информация`
- `CommandGroup.НачальноеЗаполнение`
- `CommandGroup.НДС`

---

## 7. Различия версий формата

| Аспект | `2.17` (8.3.20–8.3.24) | `2.20` (8.3.27+) |
|---|---|---|
| Атрибут `version` | `2.17` | `2.20` |
| BOM (UTF-8 BOM) | Нет | Да (EF BB BF) |
| Набор элементов | Идентичный | Идентичный |
| Набор свойств подсистемы | Идентичный | Идентичный |
| Секции CommandInterface | Идентичные | Идентичные |

> Между версиями `2.17` и `2.20` структурных различий в формате подсистем и командного интерфейса не обнаружено. Меняется только атрибут `version` и наличие BOM.

---

## 8. Полный пример

### 8.1. Подсистема верхнего уровня (Продажи.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<MetaDataObject xmlns="http://v8.1c.ru/8.3/MDClasses"
    xmlns:v8="http://v8.1c.ru/8.1/data/core"
    xmlns:xr="http://v8.1c.ru/8.3/xcf/readable"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="2.17">
    <Subsystem uuid="2885099a-00f4-481b-8469-faee8a208e7c">
        <Properties>
            <Name>Продажи</Name>
            <Synonym>
                <v8:item>
                    <v8:lang>ru</v8:lang>
                    <v8:content>Продажи</v8:content>
                </v8:item>
            </Synonym>
            <Comment/>
            <IncludeHelpInContents>true</IncludeHelpInContents>
            <IncludeInCommandInterface>true</IncludeInCommandInterface>
            <UseOneCommand>false</UseOneCommand>
            <Explanation/>
            <Picture>
                <xr:Ref>CommonPicture.Продажи</xr:Ref>
                <xr:LoadTransparent>false</xr:LoadTransparent>
            </Picture>
            <Content>
                <xr:Item xsi:type="xr:MDObjectRef">Report.Продажи</xr:Item>
                <xr:Item xsi:type="xr:MDObjectRef">Report.ВаловаяПрибыль</xr:Item>
                <xr:Item xsi:type="xr:MDObjectRef">CommonCommand.ДополнительныеОбработкиПродажи</xr:Item>
                <xr:Item xsi:type="xr:MDObjectRef">CommonCommand.ДополнительныеОтчетыПродажи</xr:Item>
                <xr:Item xsi:type="xr:MDObjectRef">Role.ПодсистемаПродажи</xr:Item>
            </Content>
        </Properties>
        <ChildObjects>
            <Subsystem>ПродажиГлавное</Subsystem>
            <Subsystem>РозничныеПродажи</Subsystem>
            <Subsystem>РасчетыСКонтрагентами</Subsystem>
        </ChildObjects>
    </Subsystem>
</MetaDataObject>
```

### 8.2. CommandInterface подсистемы (Продажи/Ext/CommandInterface.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CommandInterface xmlns="http://v8.1c.ru/8.3/xcf/extrnprops"
    xmlns:xr="http://v8.1c.ru/8.3/xcf/readable"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="2.17">
    <CommandsVisibility>
        <Command name="Report.Продажи.Command.ПродажиПоКонтрагентам">
            <Visibility>
                <xr:Common>true</xr:Common>
            </Visibility>
        </Command>
        <Command name="Report.Продажи.Command.ПродажиПоНоменклатуре">
            <Visibility>
                <xr:Common>true</xr:Common>
            </Visibility>
        </Command>
        <Command name="CommonCommand.ДополнительныеОбработкиПродажи">
            <Visibility>
                <xr:Common>true</xr:Common>
            </Visibility>
        </Command>
    </CommandsVisibility>
    <CommandsPlacement>
        <Command name="Report.Продажи.Command.ПродажиПоКонтрагентам">
            <CommandGroup>CommandGroup.Отчеты</CommandGroup>
            <Placement>Auto</Placement>
        </Command>
        <Command name="CommonCommand.ДополнительныеОбработкиПродажи">
            <CommandGroup>CommandGroup.Сервис</CommandGroup>
            <Placement>Auto</Placement>
        </Command>
    </CommandsPlacement>
    <CommandsOrder>
        <Command name="Report.Продажи.Command.ПродажиПоКонтрагентам">
            <CommandGroup>CommandGroup.Отчеты</CommandGroup>
        </Command>
        <Command name="Report.Продажи.Command.ПродажиПоНоменклатуре">
            <CommandGroup>CommandGroup.Отчеты</CommandGroup>
        </Command>
        <Command name="CommonCommand.ДополнительныеОбработкиПродажи">
            <CommandGroup>CommandGroup.Сервис</CommandGroup>
        </Command>
    </CommandsOrder>
    <SubsystemsOrder>
        <Subsystem>Subsystem.Продажи.Subsystem.ПродажиГлавное</Subsystem>
        <Subsystem>Subsystem.Продажи.Subsystem.РозничныеПродажи</Subsystem>
        <Subsystem>Subsystem.Продажи.Subsystem.РасчетыСКонтрагентами</Subsystem>
    </SubsystemsOrder>
    <GroupsOrder>
        <Group>ActionsPanelTools</Group>
        <Group>CommandGroup.Отчеты</Group>
        <Group>CommandGroup.Сервис</Group>
    </GroupsOrder>
</CommandInterface>
```

### 8.3. Корневой CommandInterface (Ext/CommandInterface.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CommandInterface xmlns="http://v8.1c.ru/8.3/xcf/extrnprops"
    xmlns:xr="http://v8.1c.ru/8.3/xcf/readable"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="2.17">
    <SubsystemsOrder>
        <Subsystem>Subsystem.Руководителю</Subsystem>
        <Subsystem>Subsystem.БанкИКасса</Subsystem>
        <Subsystem>Subsystem.Продажи</Subsystem>
        <Subsystem>Subsystem.Покупки</Subsystem>
        <Subsystem>Subsystem.Администрирование</Subsystem>
    </SubsystemsOrder>
</CommandInterface>
```
