# Feature Specification: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Feature Branch**: `005-progress-stats-widgets`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: "Dar contenido real a la pestaña de Progreso (hoy es un placeholder vacío). Dos widgets, construidos SOLO con los datos que ya existen. NO se añade objetivo/meta de calorías: la pestaña es descriptiva y comparativa contra el propio historial. Widget 1 — Resumen de la semana actual: total de kcal registradas, media por día CON registro, número de comidas registradas, y el día más alto; con delta comparado con la semana anterior. Widget 2 — Barras de calorías por día de los últimos 7 días, con línea de media; los días SIN registro no son cero y no cuentan para la media; barras coloreadas con la escala verde → amarillo → naranja → rojo del historial. Estado vacío claro, estados parciales sensatos, cifras siempre descritas como 'kcal registradas' y nunca como la ingesta real, EN+ES, colores tokenizados, cálculos en tipos puros y testeables, sin modificar el modelo persistido ni el historial."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See this week at a glance, compared to last week (Priority: P1)

As someone logging meals, I want the Progress tab to summarize the week I'm in and tell me
how it compares to the week before, so I can tell whether my logged intake is trending up
or down without doing arithmetic.

The Progress tab shows a summary of the current week containing: the total calories logged
this week, the average per **day that has at least one log**, the number of meals logged,
and which day of the week was the highest (with its total). Alongside the total and the
average, a comparison against the previous week shows direction and percentage (e.g.
↑12%). To keep that comparison fair while the week is still in progress, it covers the
**same elapsed portion** of the previous week rather than the previous week in full. When
there is no previous-week data to compare against, no comparison is shown at all.

**Why this priority**: This is the widget that answers the question a user actually opens
the tab to ask — "am I doing better or worse than last week?" — and it reuses the weekly
grouping the History tab already established.

**Independent Test**: With meals logged across the current week and the previous week, open
the Progress tab and confirm the four figures are correct and the comparison shows the right
direction and percentage; then with only current-week data, confirm no comparison appears.

**Acceptance Scenarios**:

1. **Given** meals logged in the current week, **When** the Progress tab is shown, **Then**
   it displays the week's total logged calories, the average per logged day, the count of
   logged meals, and the highest day with its total.
2. **Given** meals in both the current and previous week, **When** the summary is shown,
   **Then** the total and the average each show a comparison with direction (up/down) and a
   percentage relative to the previous week.
3. **Given** the current week is still in progress (e.g. it is Wednesday), **When** the
   total comparison is computed, **Then** it compares against the same elapsed portion of
   the previous week, not the previous week's full total.
4. **Given** no meals logged in the previous week, **When** the summary is shown, **Then**
   no comparison is displayed for any figure.
5. **Given** the current week has days with no logs, **When** the average is computed,
   **Then** those days are excluded from the divisor (average is per logged day).
6. **Given** a week where two days tie for the highest total, **When** the highest day is
   shown, **Then** one is shown deterministically (the most recent of the tied days).
7. **Given** the device region starts weeks on Sunday, **When** the week is determined,
   **Then** it runs Sunday–Saturday, matching the History tab.
8. **Given** the summary is shown, **When** any figure is labelled, **Then** it is described
   as calories *logged*, never as the user's actual intake.

---

### User Story 2 - See the last 7 days as a chart (Priority: P2)

As a user, I want a small bar chart of the last 7 days of logged calories with my average
marked on it, so I can spot patterns and outliers at a glance.

The Progress tab shows a bar per day for the last 7 days (ending today), each bar's height
being that day's total logged calories, with an indicator for the average. Days with **no
logs at all** are visually distinct from days with logs — they are not drawn as zero — and
they do not contribute to the average. Each bar is colored on the same green → yellow →
orange → red scale the History tab uses, relative to the range of the days shown.

**Why this priority**: The chart adds pattern-spotting on top of the summary's single
snapshot, but the summary (US1) already delivers the core value.

**Independent Test**: With meals logged on some of the last 7 days and none on others, open
the Progress tab and confirm one bar per day, the days without logs rendered distinctly
rather than as zero, the average reflecting only logged days, and the colors ascending from
green to red with the day totals.

**Acceptance Scenarios**:

1. **Given** meals logged over the last week, **When** the chart is shown, **Then** it shows
   exactly 7 day slots, ending with today, each labelled with its day.
2. **Given** a day within the window with no logs, **When** the chart is shown, **Then** that
   day is rendered in a visually distinct way that reads as "no data", not as a zero-height
   bar.
3. **Given** days with and without logs, **When** the average indicator is drawn, **Then** it
   reflects only the days that have logs.
4. **Given** several logged days with differing totals, **When** the bars are colored,
   **Then** the lowest is green and the highest red, with intermediate days on the
   yellow/orange steps, and a higher total is never colored cooler than a lower one.
5. **Given** only one day in the window has logs, **When** that bar is colored, **Then** it
   uses the lowest (green) step.
6. **Given** the chart is shown, **When** compared with the weekly summary, **Then** each is
   clearly labelled with the period it covers, so the different figures are self-explanatory.
7. **Given** the chart is shown in either appearance, **When** bars and the average indicator
   are drawn, **Then** all remain legible.

---

### User Story 3 - Trustworthy empty and sparse states (Priority: P3)

As a new user, or one who has logged very little, I want the Progress tab to tell me clearly
that there isn't enough data yet rather than showing misleading or broken-looking figures,
so I trust the numbers when they do appear.

When nothing has been logged, the tab shows a clear empty state explaining that logging
meals will populate it. When there is very little data (a single meal, a single day), the
widgets still render sensibly: figures that cannot be computed are omitted rather than shown
as zero or as a placeholder dash with no explanation.

**Why this priority**: Correctness at the edges protects the credibility of the whole tab,
but the tab has to exist first (US1/US2).

**Independent Test**: On a fresh install open the Progress tab and confirm a clear empty
state with no figures or chart; then log one meal and confirm both widgets render without
any misleading zeros or broken comparisons.

**Acceptance Scenarios**:

1. **Given** no meals have ever been logged, **When** the Progress tab is shown, **Then** a
   clear empty state is displayed and neither widget shows figures or an empty chart frame.
2. **Given** exactly one logged meal, **When** the tab is shown, **Then** the total, average
   and meal count are shown for that single day, the highest day is that day, and no
   comparison is shown.
3. **Given** data exists but none of it falls in the current week, **When** the summary is
   shown, **Then** it communicates that there is nothing logged this week rather than showing
   zeros as if the user had eaten nothing.
4. **Given** sparse data, **When** any figure cannot be meaningfully computed, **Then** it is
   omitted or explicitly marked as unavailable, never rendered as a bare `0`.

---

### Edge Cases

- **No data at all**: clear empty state; no widget frames, no zeroed figures.
- **Nothing logged this week, data in earlier weeks**: the summary says so explicitly; the
  chart still renders its 7 day slots as "no data".
- **Current week is its first day**: the summary covers one day; the total comparison uses
  only the matching first day of the previous week.
- **No previous-week data**: comparisons are hidden entirely, not shown as ↑100% or ↑∞%.
- **Previous week total of zero for the compared portion**: a percentage change from zero is
  undefined; the comparison is suppressed rather than shown as an infinite increase.
- **All logged days in the 7-day window have the same total**: the color scale degenerates to
  green for all, matching History's behavior.
- **Only one logged day in the window**: green, and the average equals that day's total.
- **Tie for highest day**: resolved deterministically (most recent of the tied days).
- **Week rollover / day rollover while the app is open**: figures re-resolve the next time the
  tab is presented.
- **Region or time-zone change**: week boundaries and day bucketing follow the device's
  current settings, consistent with the History tab.
- **Very large totals**: figures remain readable without overflowing their widget.
- **Two widgets covering different periods**: the current-week summary and the rolling 7-day
  chart will often disagree; each must be labelled so this reads as intentional.

## Requirements *(mandatory)*

### Functional Requirements

#### Weekly summary (US1)

- **FR-001**: The Progress tab MUST show a summary of the week currently in progress,
  containing the total calories logged, the average per logged day, the number of meals
  logged, and the highest day with its total.
- **FR-002**: The week MUST follow the device's regional first-day-of-week, consistent with
  the History tab.
- **FR-003**: The average MUST be computed over days that have at least one logged meal, not
  over all calendar days in the week.
- **FR-004**: The total and the average MUST each display a comparison against the previous
  week, showing direction (increase/decrease) and a percentage.
- **FR-005**: The total's comparison MUST cover the same elapsed portion of the previous week
  as has elapsed in the current week, so a partial week is never compared against a full one.
- **FR-006**: When the previous week has no logged data for the compared portion, all
  comparisons MUST be hidden rather than displayed as a zero, infinite, or undefined change.
- **FR-007**: When a change is exactly zero, it MUST be shown as unchanged rather than as an
  increase or a decrease.
- **FR-008**: A tie for the highest day MUST resolve deterministically to the most recent of
  the tied days.
- **FR-009**: The summary MUST NOT display a comparison for the meal count or the highest day
  — those are descriptive figures only.

#### 7-day chart (US2)

- **FR-010**: The Progress tab MUST show a bar chart covering the last 7 days, ending with the
  current day, with one slot per day, each identifiable by its day.
- **FR-011**: Each bar's magnitude MUST be that day's total logged calories.
- **FR-012**: Days with no logged meals MUST be rendered visually distinct from logged days
  and MUST NOT be drawn as a zero-value bar.
- **FR-013**: Days with no logged meals MUST be excluded from the average.
- **FR-014**: The chart MUST show an indicator for the average across the logged days in the
  window.
- **FR-015**: Each bar MUST be colored on the same ordered green → yellow → orange → red
  scale used by the History tab, relative to the lowest and highest totals among the logged
  days in the window.
- **FR-016**: The color assignment MUST be monotonic — a higher daily total never receives a
  color earlier in the scale order than a lower one.
- **FR-017**: When the window contains a single logged day, or all logged days share the same
  total, those bars MUST use the lowest (green) step.

#### Empty & sparse states (US3)

- **FR-018**: When no meals have ever been logged, the tab MUST show a clear empty state and
  MUST NOT render either widget's figures or chart frame.
- **FR-019**: When data exists but nothing falls in the current week, the summary MUST state
  that explicitly rather than presenting zeros as if nothing had been eaten.
- **FR-020**: Any figure that cannot be meaningfully computed MUST be omitted or explicitly
  marked unavailable, never rendered as a bare zero.

#### Cross-cutting

- **FR-021**: Every figure MUST be labelled as calories *logged* (or equivalent wording),
  never as the user's actual or total intake.
- **FR-022**: Each widget MUST be labelled with the period it covers, so the current-week
  summary and the rolling 7-day chart are not mistaken for the same window.
- **FR-023**: All aggregation (totals, averages, comparisons, per-day bucketing, highest day)
  MUST be verifiable independently of the screen that displays it, so each figure can be
  checked against known input data without going through the user interface.
- **FR-024**: All user-facing text MUST be localized in English and Spanish.
- **FR-025**: All colors MUST come from the design-system palette and MUST remain legible in
  both light and dark appearances.
- **FR-026**: The tab MUST read existing saved meals only — it MUST NOT change the stored
  meal data, the History tab, or the photo-analysis flow.
- **FR-027**: Opening the Progress tab MUST NOT feel slower than the app's other tabs, and
  its figures MUST stay responsive as saved meals accumulate.
- **FR-028**: Both widgets MUST support Dynamic Type and be usable with VoiceOver, with chart
  values available to assistive technology rather than conveyed by bar height and color alone.

### Key Entities *(include if data involved)*

- **Daily tally**: one calendar day in a window — the day itself, the total calories logged
  that day, how many meals were logged, and whether it has any log at all (the flag that
  separates "no data" from a genuine zero).
- **Week summary**: the figures for one week — total logged calories, average per logged day,
  meal count, the highest daily tally, and the comparisons against the previous week.
- **Comparison**: a change between two periods — its direction (up / down / unchanged) and its
  percentage magnitude. Absent when the baseline period has no data.
- **Meal history entry**: unchanged from feature 003 — read-only input here. This feature uses
  its date/time (for day and week bucketing) and its total calories.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can tell whether this week's logged calories are up or down versus last
  week within 5 seconds of opening the Progress tab, without reading any other screen.
- **SC-002**: Every figure shown matches the saved meals it summarizes exactly — 0 discrepancies
  between the weekly total and the sum of that week's logged meals.
- **SC-003**: Days without logs are never counted as zero: for any window containing unlogged
  days, the average equals the mean over logged days only (0 cases of calendar-day averaging).
- **SC-004**: Within the 7-day window, the lowest logged day is green and the highest red, with
  0 cases where a higher total appears cooler than a lower one.
- **SC-005**: With no data, 100% of users see an explanatory empty state rather than zeros, an
  empty chart frame, or a blank screen.
- **SC-006**: No comparison is ever displayed as an infinite, undefined, or 0-baseline
  percentage (0 occurrences).
- **SC-007**: The Progress tab presents its widgets within 1 second and stays responsive with
  at least 1,000 saved meals spanning 52+ weeks.
- **SC-008**: All figures, labels, and colors are correct and legible in both English and
  Spanish and in both light and dark appearance (0 untranslated or illegible elements).

## Assumptions

- **Builds on features 003 and 004**: saved meals with their date and total calories already
  exist, as does region-aware weekly grouping and the four-step calorie color scale. This
  feature reads them; it adds no stored data.
- **No calorie goal — explicitly out of scope.** This was a deliberate product decision: the
  tab is descriptive and compares the user against their own history, not against a target.
  Consequently there is no ring/gauge, no "remaining today", and no "within goal" status. A
  daily goal would be a separate feature, and it is what would later unlock those.
- **Two different periods, deliberately.** The summary covers the **current calendar week**
  (1–7 days depending on the day) while the chart covers a **rolling last 7 days**. Their
  totals will usually differ. This is intentional per the request, and FR-022 requires each
  widget to state its period so the difference does not read as a bug. If it still confuses
  users in practice, aligning both to the calendar week is the fallback.
- **Partial-week comparison is elapsed-aligned.** Comparing a Wednesday-so-far total against
  a full previous week would always show a decline, which would be actively misleading. The
  total's comparison therefore covers the same elapsed portion of the previous week. The
  average per logged day is naturally comparable and needs no alignment.
- **Comparisons limited to total and average**: meal count and highest day are shown without a
  comparison, to keep the widget legible (FR-009).
- **"Average per logged day"** means total logged calories divided by the number of days with
  at least one logged meal in the period.
- **Logging is partial by nature**: the user photographs some meals, not all, so every figure
  is framed as "logged" (FR-021). No figure claims to represent actual intake.
- **Macros are not used in this feature.** They are optional per meal, so a macro breakdown
  needs its own partial-data design; the macro donut and food ranking discussed during
  planning are deferred to a later feature.
- **Delete/edit still out of scope**: meals cannot be removed (per feature 003), so figures
  only ever grow.
- **No new tab or navigation**: this fills the existing Progress tab, replacing its
  placeholder. Drill-down from a widget into the underlying meals is out of scope.
- **Scope is these two widgets only**: the hour-of-day pattern, calendar heatmap, logging
  streak, and hero "heaviest meal" card discussed during planning are all explicitly deferred.
