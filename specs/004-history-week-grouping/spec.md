# Feature Specification: History Weekly Grouping & Calorie Color Scale

**Feature Branch**: `004-history-week-grouping`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: "Quiero que en la pestana de historial, la lista tiene que estar agrupada. Para la semana en curso(lun-dom o para americano dom sabado, etc) mostrar una pequena cabecera encima de las capturas escaneadas en ese rango que diga: Semana actual(traducir tambien en ingles). Para la semana anterior a la actual, la cabecera ha de ser 'Semana anterior', y para las otras semanas poner el rango de fechas que empeizan y acaban, ejemplo 1 'Febrero - 7 Febrero' y asi con las anteriores. Todo esto en caso de que haya capturas anteriores o existentes. Ademas, en la fecha de cada item de la lista, ha de aparecer en formato 'Vie. 25 Jul, 16:40'. Ademas, dentro de cada grupo de semana, se ha de pintar el color del numero las calorias en un rango de colores entre verde, amarillo, naranja y rojo. En ese orden, siendo verde el que menos calorias y rojo el que mas."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Meals grouped by week with meaningful headers (Priority: P1)

As someone reviewing what I've eaten, I want my history list broken into weeks with a
small header above each block, so I can immediately tell which meals belong to this
week, last week, or an earlier week without reading every date.

The History tab groups saved meals by the calendar week they were taken in. Above
each block of meals sits a small header: **"Semana actual" / "This week"** for the
week currently in progress, **"Semana anterior" / "Last week"** for the week before
it, and the week's date range (e.g. *"1 Febrero - 7 Febrero"*) for every older week.
Groups are ordered most-recent week first, and meals inside a group keep the
most-recent-first ordering. Weeks with no meals produce no header.

**Why this priority**: Grouping is the core of the request and the change that makes
a growing history scannable. Everything else in this feature refines rows inside
those groups.

**Independent Test**: With meals saved across this week, last week, and at least one
older week, open the History tab and confirm three headers appear in that order with
the correct labels, each followed only by the meals belonging to that week.

**Acceptance Scenarios**:

1. **Given** meals taken during the week currently in progress, **When** the History
   tab is shown, **Then** those meals appear under a header reading "Semana actual"
   (Spanish) / "This week" (English).
2. **Given** meals taken during the week immediately before the current one, **When**
   the list is shown, **Then** they appear under a header reading "Semana anterior" /
   "Last week".
3. **Given** meals taken two or more weeks ago, **When** the list is shown, **Then**
   each such week has a header showing that week's start and end dates (e.g. "1
   Febrero - 7 Febrero").
4. **Given** meals from several weeks, **When** the list is shown, **Then** the week
   groups are ordered newest week first and meals within each group are ordered
   newest first.
5. **Given** a week with no saved meals, **When** the list is shown, **Then** no
   header or empty block is rendered for that week.
6. **Given** no saved meals at all, **When** the History tab is shown, **Then** the
   existing empty state is shown with no headers.
7. **Given** the device is configured for a locale whose week starts on Sunday,
   **When** meals are grouped, **Then** week boundaries run Sunday–Saturday; for a
   locale whose week starts on Monday, they run Monday–Sunday.

---

### User Story 2 - Readable day-and-time stamp on every meal (Priority: P2)

As a user scanning my history, I want each meal's timestamp to show the weekday, day,
month and time, so I can tell at a glance which day and roughly what time of day I ate
it without doing date math.

Each row's date is displayed as an abbreviated weekday, day, abbreviated month and
time — e.g. **"Vie. 25 Jul, 16:40"** in Spanish, with the equivalent abbreviations in
English.

**Why this priority**: It makes individual rows readable, which matters most once
grouping (US1) has already established the week context.

**Independent Test**: Open the History tab with saved meals and confirm every row's
timestamp follows the weekday/day/month/time pattern in the device language.

**Acceptance Scenarios**:

1. **Given** a meal taken on Friday 25 July at 16:40 with the app in Spanish,
   **When** its row is shown, **Then** the date reads "Vie. 25 Jul, 16:40".
2. **Given** the same meal with the app in English, **When** its row is shown,
   **Then** the date uses the English weekday and month abbreviations in the same
   pattern.
3. **Given** a device configured for 12-hour time, **When** a row is shown, **Then**
   the time portion follows the device's 12-hour convention.
4. **Given** any saved meal, **When** its row is shown, **Then** the timestamp
   reflects the moment the photo was analyzed, in the device's current time zone.

---

### User Story 3 - Calorie figures colored from green to red within each week (Priority: P3)

As a user, I want the calorie number on each meal to be colored on a green → yellow →
orange → red scale relative to the other meals in that same week, so I can spot my
heaviest and lightest meals of the week instantly.

Within each week group, the meal with the lowest calorie total is shown in green and
the one with the highest in red, with the meals in between falling on a
green/yellow/orange/red scale according to where their total sits between that week's
lowest and highest. The scale is computed independently per week group, so each week
is judged against itself.

**Why this priority**: A visual cue that adds scanning value on top of an already
grouped, readable list; the list is useful without it.

**Independent Test**: With several meals of clearly different calorie totals in one
week, open the History tab and confirm the lowest total is green, the highest is red,
and intermediate totals take yellow/orange in ascending order.

**Acceptance Scenarios**:

1. **Given** a week group with meals of differing calorie totals, **When** the list is
   shown, **Then** the lowest total is colored green and the highest red.
2. **Given** a week group with meals spread across the range, **When** the list is
   shown, **Then** a meal with a higher total is never colored "cooler" (further
   toward green) than a meal with a lower total in the same group.
3. **Given** two week groups, **When** both are shown, **Then** each group's coloring
   is computed from its own lowest/highest totals and not influenced by the other
   group.
4. **Given** a week group containing exactly one meal, **When** it is shown, **Then**
   its calorie number is colored green.
5. **Given** a week group where every meal has the same calorie total, **When** it is
   shown, **Then** all of those numbers share the same color (green).
6. **Given** any colored calorie number, **When** shown in light or dark appearance,
   **Then** it remains legible against the row background.

---

### Edge Cases

- **No saved meals**: the existing empty state is shown; no group headers appear.
- **Only current-week meals**: a single "Semana actual" group is shown; no "Semana
  anterior" or dated headers.
- **Gap weeks**: weeks with no meals are skipped entirely — headers only exist for
  weeks that contain meals.
- **Week spanning two months**: the range header shows each end with its own month
  (e.g. "29 Enero - 4 Febrero").
- **Week in a previous year**: the range header disambiguates the year so an old week
  is not mistaken for a recent one.
- **Week boundary crossed while the app is open**: when the current week rolls over,
  the group that was "Semana actual" becomes "Semana anterior" the next time the list
  is presented.
- **Time-zone or device-clock change**: grouping and timestamps follow the device's
  current calendar and time zone.
- **Locale/language change**: headers, weekday and month names, and the time format
  follow the device's current settings without requiring a reinstall.
- **Single meal in a group / all totals equal**: coloring degenerates to green rather
  than producing an arbitrary red (see US3).
- **Large history**: grouping many weeks of meals must not degrade list scrolling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The History tab MUST group saved meals into calendar-week groups based
  on when each meal was taken.
- **FR-002**: Week boundaries MUST follow the device's regional calendar settings
  (e.g. Monday–Sunday where the week starts on Monday, Sunday–Saturday where it starts
  on Sunday).
- **FR-003**: The group containing the week currently in progress MUST show a header
  labelled "Semana actual" (Spanish) / "This week" (English).
- **FR-004**: The group for the week immediately preceding the current one MUST show a
  header labelled "Semana anterior" (Spanish) / "Last week" (English).
- **FR-005**: Every older week group MUST show a header with that week's start and end
  dates as a day-and-month range (e.g. "1 Febrero - 7 Febrero"), localized in both
  languages.
- **FR-006**: A week-range header MUST make the year unambiguous when the week does
  not fall in the current year.
- **FR-007**: Week groups MUST be ordered most-recent week first, and meals within a
  group MUST remain ordered most-recent first.
- **FR-008**: Weeks containing no saved meals MUST NOT produce a header or an empty
  group.
- **FR-009**: When there are no saved meals at all, the History tab MUST show the
  existing empty state and no group headers.
- **FR-010**: Each meal row MUST display its timestamp as abbreviated weekday, day,
  abbreviated month and time — matching the pattern "Vie. 25 Jul, 16:40" — using the
  device's language and time-format (12/24-hour) conventions.
- **FR-011**: Within each week group, each meal's total-calorie number MUST be colored
  on an ordered green → yellow → orange → red scale determined by where that meal's
  total sits between the lowest and highest totals in that same group.
- **FR-012**: The color scale MUST be computed per week group, independently of other
  groups.
- **FR-013**: The color assignment MUST be monotonic: within a group, a higher calorie
  total never receives a color earlier in the green → yellow → orange → red order than
  a lower total.
- **FR-014**: When a group contains a single meal, or all its meals share the same
  total, those calorie numbers MUST all use the green (lowest) color.
- **FR-015**: All colors used MUST come from the design-system palette and MUST remain
  legible in both light and dark appearances.
- **FR-016**: All new user-facing text (group headers, date formats) MUST be localized
  in English and Spanish.
- **FR-017**: Grouping, date formatting, and color assignment MUST NOT make the
  History tab slower to open or less smooth to scroll than it is today.
- **FR-018**: This feature MUST NOT change which meals are saved, their stored data, or
  the meal details screen — it changes only how the History list is presented.
- **FR-019**: The grouped list and its headers MUST support Dynamic Type and be
  reachable via VoiceOver, with each header announced as the section it introduces.

### Key Entities *(include if data involved)*

- **Week group**: a presentation-level grouping of meal history entries that fall in
  the same calendar week — its start and end dates, its header label (current /
  previous / date range), the meals it contains, and the lowest and highest calorie
  totals among them (used for the color scale).
- **Meal history entry**: unchanged from feature 003 — the saved analysis with its
  photo, foods, total calories, and date/time taken. This feature reads its
  date/time (for grouping and the row timestamp) and its total calories (for the
  color scale).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of saved meals appear under exactly one week group header, with no
  meal shown outside a group and no empty group rendered.
- **SC-002**: A user can identify which meals are from this week versus last week in
  under 3 seconds of opening the History tab, without reading individual dates.
- **SC-003**: Every row's timestamp shows weekday, day, month and time in the device
  language, with 0 rows falling back to an unlocalized or raw date.
- **SC-004**: Within any week group, the lowest-calorie meal is green and the
  highest-calorie meal is red, with 0 cases where a higher total appears greener than
  a lower one in the same group.
- **SC-005**: The History tab renders its groups within 1 second and continues to
  scroll smoothly with at least 1,000 saved meals spanning 52+ weeks.
- **SC-006**: Headers, dates, and calorie colors are correct and legible in both
  English and Spanish and in both light and dark appearance (0 illegible or
  untranslated elements).

## Assumptions

- **Builds on feature 003**: meal entries, their stored date/time and total calories,
  the row layout, and the empty state already exist; this feature restructures the
  History list's presentation only.
- **Relative, per-week color scale**: the user asked for the scale "dentro de cada
  grupo de semana", so coloring is *relative* to each week's own lowest and highest
  totals rather than against fixed calorie thresholds or a daily goal. A consequence
  is that a week of uniformly light meals still shows a red item (its own heaviest).
  Switching to absolute thresholds or a goal-relative scale would be a separate change.
- **Four discrete colors**: the scale uses the four named steps (green, yellow, orange,
  red) rather than a continuous gradient; a meal's step is chosen by where its total
  falls within the group's lowest-to-highest span, split into four equal bands.
- **Palette mapping**: green/orange/red map to the existing `success`, `warning`, and
  `danger` design tokens; a yellow token is added to the palette if none suits the
  middle step (colors are never inlined as literals).
- **Week definition follows the device**: the first day of the week comes from the
  device's regional settings rather than an in-app preference; no setting is added.
- **"Current week" is the week in progress**, i.e. the week containing today, not a
  rolling last-7-days window. "Previous week" is the single week immediately before it.
- **Range header separator**: older-week headers use the "start - end" form shown in
  the request, with each end as day + month name, localized per language.
- **Date/time source**: the timestamp shown is the entry's existing recorded date/time
  (when the analysis was saved), rendered in the device's current time zone.
- **Scope limited to the History list**: the meal details screen, saving behavior,
  sorting rules, and the Progress tab are unchanged. Filtering, per-week totals or
  summaries, and collapsing/expanding groups are out of scope.
