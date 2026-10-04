# =============================================================================
# 01_get_data.R: download the raw indicators and build one tidy panel
#
# Output
#   data/raw/*.csv     untouched downloads (gitignored; re-run to rebuild)
#   data/panel.csv     iso3, country, year, indicator, value, unit, source
#   data/regimes.csv   V-Dem Regimes of the World, used for the stage 1-2 clock
#
# Values are stored as published. Direction ("higher = more strain") is set in
# 02_stages.R so every methodological choice lives in one file.
# =============================================================================

library(tidyverse)
library(jsonlite)
library(WDI)
library(wid)
library(countrycode)
library(vdemdata)

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
yrs <- 1960:2024


# ---- 1. Public debt, % GDP (IMF DataMapper) ---------------------------------
# "d"           Historical Public Debt Database: long history, ends a few years back
# "GGXWDG_NGDP" WEO general government gross debt, 1980+
# Use the historical series where it exists and WEO to fill recent years.
imf_dm <- function(indicator) {
  j <- fromJSON(paste0("https://www.imf.org/external/datamapper/api/v1/", indicator))
  imap_dfr(j$values[[indicator]], \(v, iso) tibble(
    iso3 = iso, year = as.integer(names(v)), value = as.numeric(unlist(v))))
}

debt_hist <- imf_dm("d")
debt_weo  <- imf_dm("GGXWDG_NGDP")
write_csv(debt_hist, "data/raw/imf_debt_hist.csv")
write_csv(debt_weo,  "data/raw/imf_debt_weo.csv")

debt <- full_join(rename(debt_hist, hist = value), rename(debt_weo, weo = value),
                  by = c("iso3", "year")) |>
  transmute(iso3, year, value = coalesce(hist, weo), indicator = "debt_gdp")


# ---- 2. Inequality: top 10% pre-tax income share (WID) ----------------------
# 992j = adults, equal-split. WID reports shares (0.45), stored here as % (45).
wid_raw <- download_wid(indicators = "sptinc", areas = "all",
                        perc = "p90p100", ages = "992", pop = "j")
write_csv(wid_raw, "data/raw/wid_top10.csv")

top10 <- wid_raw |>
  filter(nchar(country) == 2) |>                      # drop sub-national codes (US-CA)
  mutate(iso3 = countrycode(country, "iso2c", "iso3c", warn = FALSE)) |>
  transmute(iso3, year = as.integer(year), value = 100 * value,
            indicator = "top10_share")


# ---- 3. Politics and institutions (V-Dem) -----------------------------------
vd <- vdemdata::vdem |>
  select(iso3 = country_text_id, year, v2x_regime,
         v2cacamps, v2caviol, v2clrspct, v2x_rule)
write_csv(vd, "data/raw/vdem.csv")

vdem_long <- vd |>
  filter(year >= min(yrs)) |>
  select(-v2x_regime) |>
  pivot_longer(-c(iso3, year), names_to = "var", values_to = "value") |>
  mutate(indicator = recode(var,
    v2cacamps = "polarization",
    v2caviol  = "political_violence",
    v2clrspct = "impartial_admin",
    v2x_rule  = "rule_of_law")) |>
  select(-var)

# Full history (not just 1960+) so the "years in current order" clock is right
write_csv(select(vd, iso3, year, v2x_regime), "data/regimes.csv")


# ---- 4. Growth: 10-yr average real GDP per capita growth (World Bank) -------
wdi <- WDI(country = "all", indicator = c(gdppc = "NY.GDP.PCAP.KD"),
           start = 1960, end = max(yrs), extra = TRUE)
write_csv(wdi, "data/raw/wdi_gdppc.csv")

growth <- wdi |>
  filter(region != "Aggregates", !is.na(iso3c)) |>
  arrange(iso3c, year) |>
  group_by(iso3c) |>
  mutate(value = 100 * ((gdppc / lag(gdppc, 10))^(1 / 10) - 1)) |>
  ungroup() |>
  transmute(iso3 = iso3c, year, value, indicator = "gdp_growth_10yr")


# ---- 5. Tidy panel ----------------------------------------------------------
meta <- tribble(
  ~indicator,           ~unit,                       ~source,
  "debt_gdp",           "% of GDP",                  "IMF DataMapper (d, GGXWDG_NGDP)",
  "top10_share",        "% of pre-tax income",       "WID sptinc p90p100 992j",
  "polarization",       "V-Dem index",               "V-Dem v2cacamps",
  "political_violence", "V-Dem index",               "V-Dem v2caviol",
  "impartial_admin",    "V-Dem index",               "V-Dem v2clrspct",
  "rule_of_law",        "V-Dem index (0-1)",         "V-Dem v2x_rule",
  "gdp_growth_10yr",    "10-yr avg annual growth, %", "World Bank WDI NY.GDP.PCAP.KD"
)

panel <- bind_rows(debt, top10, vdem_long, growth) |>
  filter(year %in% yrs, !is.na(value)) |>
  mutate(country = countrycode(iso3, "iso3c", "country.name", warn = FALSE)) |>
  filter(!is.na(country)) |>                          # drops regions and aggregates
  left_join(meta, by = "indicator") |>
  relocate(iso3, country, year, indicator, value)

write_csv(panel, "data/panel.csv")


# ---- 6. Checks --------------------------------------------------------------
# Coverage: countries per indicator per decade
panel |>
  count(indicator, decade = 10 * (year %/% 10)) |>
  pivot_wider(names_from = decade, values_from = n) |>
  print()

# Debt splice: a jump where the historical series ends and WEO starts
# means a definition break, not a real change.
panel |>
  filter(indicator == "debt_gdp", iso3 %in% c("USA", "GBR", "FRA", "DEU", "JPN")) |>
  ggplot(aes(year, value, color = iso3)) +
  geom_line() +
  labs(title = "Debt splice check", y = "% of GDP", x = NULL)
