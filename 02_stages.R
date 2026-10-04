# =============================================================================
# 02_stages.R: turn the panel into a strain score and a Dalio stage
#
# Input   data/panel.csv, data/regimes.csv  (from 01_get_data.R)
# Output  data/stages.csv   one row per country-year: percentiles, sub-scores,
#                            strain score and assigned stage
#
# Method (every choice is in this file; change it and re-run)
#   1. Orient each indicator so higher = more strain
#   2. Convert to a percentile across all countries and all years 1960-2024
#   3. Strain score = mean of available percentiles
#   4. Stage = first rule in `assign_stage()` that matches
# =============================================================================

library(tidyverse)

panel   <- read_csv("data/panel.csv", show_col_types = FALSE)
regimes <- read_csv("data/regimes.csv", show_col_types = FALSE)


# ---- 1. Orient: higher = more strain ----------------------------------------
# +1 keeps the sign, -1 flips it. V-Dem scale direction varies by variable, so
# the two ambiguous ones are checked against anchor cases below.
direction <- c(
  debt_gdp           = +1,   # more debt
  top10_share        = +1,   # bigger wealth gap
  polarization       = -1,   # v2cacamps: verify with check below
  political_violence = -1,   # v2caviol:  verify with check below
  impartial_admin    = -1,   # less impartial bureaucracy
  rule_of_law        = -1,   # weaker rule of law
  gdp_growth_10yr    = -1    # slower growth = lost opportunity
)

strain <- panel |>
  mutate(value = value * direction[indicator])

# Anchor check: the "worse" case should score higher than the "better" case.
anchors <- tribble(
  ~indicator,           ~worse_iso, ~better_iso, ~year,
  "polarization",       "VEN",      "NOR",       2017,
  "political_violence", "SYR",      "NOR",       2013
)
anchors |>
  left_join(select(strain, indicator, iso3, year, worse = value),
            by = c("indicator", "worse_iso" = "iso3", "year")) |>
  left_join(select(strain, indicator, iso3, year, better = value),
            by = c("indicator", "better_iso" = "iso3", "year")) |>
  mutate(ok = worse > better) |>
  print()
# If any `ok` is FALSE, flip that indicator's sign in `direction`.


# ---- 2. Percentiles, pooled across countries and years ----------------------
# Pooling means a score of 0.8 = "worse than 80% of all country-years since 1960".
pct <- strain |>
  group_by(indicator) |>
  mutate(pct = percent_rank(value)) |>
  ungroup() |>
  select(iso3, country, year, indicator, pct) |>
  pivot_wider(names_from = indicator, values_from = pct)

indicators <- names(direction)


# ---- 3. Years in current order (for stages 1-2) -----------------------------
# Proxy for "a new order began": the last year V-Dem's Regimes of the World
# classification (v2x_regime: closed autocracy ... liberal democracy) changed.
# Countries with no change since data begins get NA and skip stages 1-2.
order_clock <- regimes |>
  arrange(iso3, year) |>
  group_by(iso3) |>
  mutate(changed = !is.na(v2x_regime) & v2x_regime != lag(v2x_regime),
         order_start = if_else(changed, year, NA_real_)) |>
  fill(order_start) |>
  ungroup() |>
  transmute(iso3, year, years_in_order = year - order_start)


# ---- 4. Strain score, sub-scores, stage -------------------------------------
assign_stage <- function(n_ind, strain, s4, s5, s6, political_violence, years_in_order) {
  case_when(
    n_ind < 4                                    ~ NA_integer_,  # too little data
    s6 > 0.75 & political_violence > 0.80        ~ 6L,  # civil war / revolution
    s5 > 0.65 & strain > 0.50                    ~ 5L,  # bad finances + intense conflict
    !is.na(years_in_order) & years_in_order < 5  ~ 1L,  # new order, consolidating
    !is.na(years_in_order) & years_in_order < 20 ~ 2L,  # building institutions
    s4 > 0.60                                    ~ 4L,  # excess: debt, gaps, slowing growth
    strain < 0.50                                ~ 3L,  # peace & prosperity
    .default                                     = NA_integer_   # unclassified
  )
}

stages <- pct |>
  left_join(order_clock, by = c("iso3", "year")) |>
  mutate(
    n_ind  = rowSums(!is.na(across(all_of(indicators)))),
    strain = rowMeans(across(all_of(indicators)), na.rm = TRUE),
    s4 = rowMeans(across(c(debt_gdp, top10_share, gdp_growth_10yr)), na.rm = TRUE),
    s5 = rowMeans(across(c(debt_gdp, polarization)), na.rm = TRUE),
    s6 = rowMeans(across(c(political_violence, rule_of_law, polarization)), na.rm = TRUE),
    stage = assign_stage(n_ind, strain, s4, s5, s6, political_violence, years_in_order)
  ) |>
  mutate(across(where(is.double), \(x) if_else(is.nan(x), NA_real_, x)))

write_csv(stages, "data/stages.csv")


# ---- 5. Checks --------------------------------------------------------------
# Share of country-years in each stage, and how many fall through the rules
count(stages, stage) |> mutate(share = n / sum(n)) |> print()

# Spot-check cases you have priors on
stages |>
  filter(iso3 == "USA", year %in% seq(1960, 2024, 8)) |>
  select(year, stage, strain, s4, s5, s6, years_in_order) |>
  print()
