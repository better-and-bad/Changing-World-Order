# Changing World Order

Where is every country in Ray Dalio's six-stage cycle of internal order? This repo scores 180+ countries from 1960 to 2024 on debt, inequality, growth, polarization, political violence and institutional quality, then assigns each country-year a stage.

Built by [better&bad](https://betterandbad.com). The charts in `output/` are the ones used in the post.

![Stage timeline](output/stage_timeline.png)

## The six stages

From Dalio's *Principles for Dealing with the Changing World Order*:

| Stage | Description |
|---|---|
| 1 | New order begins; new leadership consolidates power |
| 2 | Leadership builds the institutions and bureaucracy |
| 3 | Peace and prosperity |
| 4 | Excess: high debt, widening wealth gaps, slowing growth |
| 5 | Bad financial conditions plus intense political conflict |
| 6 | Civil war or revolution |

Dalio describes these qualitatively. Turning them into numbers takes judgment calls, and every one of them lives in `02_stages.R` so you can change it and re-run.

## Method

1. **Indicators.** Seven series per country-year (see sources below).
2. **Orientation.** Each indicator is signed so higher = more strain (more debt, bigger top-10% share, slower growth, weaker rule of law, etc.).
3. **Percentiles.** Each indicator becomes a percentile pooled across all countries and all years since 1960. A score of 0.8 means "worse than 80% of country-years in the data."
4. **Scores.**
   - `strain`: mean of all available percentiles
   - `s4` (excess): debt, top-10% share, growth
   - `s5` (finances + conflict): debt, polarization
   - `s6` (breakdown): political violence, rule of law, polarization
5. **Stage.** Rules are checked in this order; the first match wins:

| Rule | Stage |
|---|---|
| Fewer than 4 indicators available | unclassified |
| `s6 > 0.75` and political violence > 0.80 | 6 |
| `s5 > 0.65` and `strain > 0.50` | 5 |
| Regime type changed < 5 years ago | 1 |
| Regime type changed 5–19 years ago | 2 |
| `s4 > 0.60` | 4 |
| `strain < 0.50` | 3 |
| Anything else | unclassified |

"A new order began" is proxied by the last year V-Dem's Regimes of the World classification changed (e.g. electoral autocracy → electoral democracy). Countries with no regime change in the data skip stages 1–2.

## Data sources

| Indicator | Source | Series |
|---|---|---|
| Government debt, % GDP | IMF DataMapper | Historical Public Debt (`d`), filled with WEO (`GGXWDG_NGDP`) |
| Top 10% pre-tax income share | World Inequality Database | `sptinc` p90p100, adults, equal-split |
| Polarization | V-Dem | `v2cacamps` |
| Political violence | V-Dem | `v2caviol` |
| Impartial public administration | V-Dem | `v2clrspct` |
| Rule of law | V-Dem | `v2x_rule` |
| 10-yr avg real GDP per capita growth | World Bank WDI | `NY.GDP.PCAP.KD` |
| Regime type (stage 1–2 clock) | V-Dem | `v2x_regime` |

All data is downloaded fresh by `01_get_data.R`; none of it is stored in the repo.

## How to run

Requires R 4.1+ (uses the native `|>` pipe and `\(x)` lambdas). Open the folder in RStudio (or `setwd()` to the repo root), then:

```r
source("00_setup.R")      # install packages, once
source("01_get_data.R")   # download data, build data/panel.csv (~5 min)
source("02_stages.R")     # build data/stages.csv
source("03_charts.R")     # write PNGs to output/
```

For the animated MP4s, set `ANIMATE <- TRUE` at the top of `03_charts.R`. It takes a few minutes.

## Outputs

| File | What it is |
|---|---|
| `data/panel.csv` | Tidy panel: `iso3, country, year, indicator, value, unit, source` |
| `data/stages.csv` | One row per country-year: percentiles, sub-scores, strain score, stage |
| `output/stage_timeline.png` | Stage by year for 10 large economies |
| `output/world_map_latest.png` | Latest stage for every country |
| `output/us_indicators.png` | US debt, inequality, polarization, political violence since 1960 |
| `output/*.mp4` | Animated versions of the timeline and map |

## Caveats

- **This is an estimate, not Dalio's own classification.** He hasn't published country-by-country stage assignments; the thresholds here are mine.
- **V-Dem sign direction.** Some V-Dem indices run "higher = better," others don't. `02_stages.R` prints an anchor check (Venezuela vs. Norway, Syria vs. Norway). If any row shows `ok = FALSE`, flip that indicator's sign in `direction`.
- **Debt splice.** Debt combines two IMF series. `01_get_data.R` plots a splice check for five large economies; a jump where one series hands off to the other is a definition break, not a real change.
- **Pooled percentiles** compare every country to all of history, so a 2024 country is judged against the 1970s as much as against its peers.
- **Coverage varies.** WID and IMF debt are thin for many countries before 1980, so early years have more unclassified rows.

## Repo structure

```
├── 00_setup.R        install packages
├── 01_get_data.R     download and tidy the indicators
├── 02_stages.R       percentiles, scores, stage rules
├── 03_charts.R       charts and animations
├── R/theme.R         better&bad ggplot theme and stage colors
├── data/             generated, gitignored
└── output/           charts
```

## License

Code is MIT licensed (see `LICENSE`). The underlying data belongs to its publishers; check each source's terms before redistributing it. If you use the charts, credit better&bad.
