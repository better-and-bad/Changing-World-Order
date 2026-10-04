# =============================================================================
# 03_charts.R: draw the charts
#
# Input   data/panel.csv, data/stages.csv
# Output  output/stage_timeline.png    10 big economies, stage by year
#         output/world_map_latest.png  latest stage, every country
#         output/us_indicators.png     the four US warning lights
#         output/*.mp4                 animated versions (set ANIMATE <- TRUE)
# =============================================================================

library(tidyverse)
library(countrycode)
source("R/theme.R")

dir.create("output", showWarnings = FALSE)
ANIMATE <- FALSE    # TRUE needs gganimate + av, and takes a few minutes

panel  <- read_csv("data/panel.csv",  show_col_types = FALSE)
stages <- read_csv("data/stages.csv", show_col_types = FALSE) |>
  mutate(stage = factor(stage, levels = 1:6))

caption <- "better&bad estimate based on Ray Dalio's six-stage framework\nSources: IMF, WID, V-Dem, World Bank"
focus   <- c("USA", "GBR", "FRA", "DEU", "JPN", "RUS", "CHN", "IND", "BRA", "ARG")


# ---- 1. Stage timeline: 10 big economies ------------------------------------
timeline_df <- stages |>
  filter(iso3 %in% focus, !is.na(stage)) |>
  mutate(iso3 = factor(iso3, levels = rev(focus)))

latest <- slice_max(timeline_df, year, n = 1, by = iso3)

timeline <- ggplot(timeline_df, aes(year, iso3, fill = stage)) +
  geom_tile(height = 0.72, width = 1) +
  geom_text(data = latest, aes(x = year + 1.5, label = stage),
            hjust = 0, family = bb_font, fontface = "bold",
            size = 4, color = bb_colors$text) +
  scale_fill_manual(values = stage_cols, labels = stage_labels, drop = FALSE) +
  scale_x_continuous(breaks = seq(1960, 2020, 20), expand = expansion(add = c(0, 3))) +
  coord_cartesian(clip = "off") +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
  labs(title = "6 Stages of Internal Order", caption = caption, x = NULL, y = NULL) +
  theme_betterandbad()

ggsave("output/stage_timeline.png", timeline, device = ragg::agg_png,
       width = 1080, height = 1350, units = "px", dpi = 150)


# ---- 2. World map -----------------------------------------------------------
world <- map_data("world") |>
  filter(region != "Antarctica") |>
  mutate(iso3 = countrycode(region, "country.name", "iso3c",
                            custom_match = c(Kosovo = "XKX"), warn = FALSE))

draw_map <- function(stage_data) {
  ggplot() +
    geom_polygon(data = world, aes(long, lat, group = group),             # grey base
                 fill = bb_colors$grid, color = bb_colors$bg, linewidth = 0.15) +
    geom_polygon(data = inner_join(world, stage_data, by = "iso3",
                                   relationship = "many-to-many"),
                 aes(long, lat, group = group, fill = stage),
                 color = bb_colors$bg, linewidth = 0.15) +
    scale_fill_manual(values = stage_cols, labels = stage_labels, drop = FALSE,
                      na.value = bb_colors$grid, na.translate = FALSE) +
    coord_fixed(1.3) +
    guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
    labs(title = "It's a Late Stage World",
         subtitle = "Internal order by country, Dalio's six-stage cycle",
         caption = caption) +
    theme_betterandbad_map()
}

map_year <- max(stages$year[!is.na(stages$stage)])
world_map <- draw_map(filter(stages, year == map_year, !is.na(stage))) +
  labs(subtitle = paste0("Internal order by country, ", map_year))

ggsave("output/world_map_latest.png", world_map, device = ragg::agg_png,
       width = 1600, height = 1000, units = "px", dpi = 150)


# ---- 3. US warning lights ---------------------------------------------------
ind_labels <- c(
  debt_gdp           = "Government debt, % of GDP",
  top10_share        = "Top 10% income share, %",
  polarization       = "Political polarization",
  political_violence = "Political violence"
)

us_df <- panel |>
  filter(iso3 == "USA", indicator %in% names(ind_labels)) |>
  mutate(indicator = factor(indicator, levels = names(ind_labels)))

us_last <- us_df |>
  slice_max(year, n = 1, by = indicator) |>
  mutate(lab = if_else(indicator %in% c("debt_gdp", "top10_share"),
                       paste0(round(value), "%"), sprintf("%.1f", value)))

us_plot <- ggplot(us_df, aes(year, value)) +
  geom_line(color = bb_colors$policy, linewidth = 1.1) +
  geom_point(data = us_last, color = bb_colors$policy, size = 2.5) +
  geom_text(data = us_last, aes(label = lab), hjust = -0.25,
            family = bb_font, fontface = "bold", size = 3, color = bb_colors$text) +
  facet_wrap(~indicator, ncol = 2, scales = "free_y",
             labeller = as_labeller(ind_labels)) +
  scale_x_continuous(breaks = seq(1960, 2020, 20), expand = expansion(add = c(1, 7))) +
  coord_cartesian(clip = "off") +
  labs(title = "Four Warning Lights", subtitle = "United States, 1960-2024",
       caption = "V-Dem indices shown on their published scale (check sign in the codebook)\nSources: IMF, WID, V-Dem",
       x = NULL, y = NULL) +
  theme_betterandbad() +
  theme(panel.spacing = unit(1.2, "lines"), panel.grid.major.x = element_blank())

ggsave("output/us_indicators.png", us_plot, device = ragg::agg_png,
       width = 1000, height = 1550, units = "px", dpi = 200)


# ---- 4. Animations (optional) -----------------------------------------------
if (ANIMATE) {
  library(gganimate)

  anim_opts <- list(fps = 10, end_pause = 20, width = 1080, height = 1350,
                    units = "px", res = 150, device = "ragg_png")

  do.call(animate, c(list(timeline + transition_manual(year, cumulative = TRUE),
                          renderer = av_renderer("output/stage_timeline.mp4")),
                     anim_opts))

  map_frames <- stages |>
    filter(iso3 %in% world$iso3) |>
    complete(iso3, year)                         # keep every country in every frame
  do.call(animate, c(list(draw_map(map_frames) +
                            labs(subtitle = "Internal order by country, {current_frame}") +
                            transition_manual(year),
                          renderer = av_renderer("output/world_map.mp4")),
                     anim_opts))
}
