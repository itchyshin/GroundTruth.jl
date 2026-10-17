#!/usr/bin/env Rscript
# Base-R graphics only: no package or model engine is loaded.
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]], mustWork = TRUE) else getwd()
x <- read.csv(file.path(root, "tables", "stratum-map.csv"), stringsAsFactors = FALSE)
cells <- unique(x$cell)
engines <- c("lme4", "MixedModels")
cols <- c(lme4 = "#0072B2", MixedModels = "#D55E00")
markers <- c(lme4 = 16L, MixedModels = 15L)
labels <- x$scenario[match(cells, x$cell)]
labels <- gsub(", ICC", " / ICC", labels, fixed = TRUE)
labels <- sub("20 unequal groups", "20 unequal groups (n=114)", labels, fixed = TRUE)
labels[grepl("few_groups_", cells)] <- paste0(labels[grepl("few_groups_", cells)], " (n=12)")
out <- file.path(root, "figures")
dir.create(out, showWarnings = FALSE)
draw <- function() {
  old <- par(no.readonly = TRUE)
  on.exit(par(old), add = TRUE)
  layout(matrix(1:3, nrow = 1), widths = c(1.12, 1, 1))
  par(oma = c(4, 17, 5, 1), mar = c(3, 0.4, 2.3, 1.1),
      family = "sans", cex = 0.86, mgp = c(1.7, 0.5, 0), tcl = -0.22)
  for (panel in 1:3) {
    target <- c("fit", "alpha", "beta")[[panel]]
    limits <- if (panel == 1L) c(0.925, 1.005) else c(0.75, 1.005)
    plot(NA_real_, NA_real_, type = "n", xlim = limits, ylim = c(length(cells) + .5, .4),
         xaxs = "i", yaxs = "i", axes = FALSE, xlab = "", ylab = "")
    for (j in seq_along(cells)) {
      if (j %% 2L == 1L) rect(limits[[1L]], j - .48, limits[[2L]], j + .48,
                            col = "#F2F5F7", border = NA)
    }
    ticks <- if (panel == 1L) c(.94, .96, .98, 1) else seq(.8, 1, .05)
    abline(v = ticks, col = "#DCE2E6", lwd = .7)
    axis(1, at = ticks, labels = formatC(ticks, format = "f", digits = 2),
         col = "#9CA6AF", col.axis = "#343B42")
    if (panel > 1L) abline(v = .95, lty = 2, col = "#535C64", lwd = 1)
    for (e in seq_along(engines)) {
      engine <- engines[[e]]
      s <- x[match(paste(cells, engine), paste(x$cell, x$engine)), ]
      yy <- seq_along(cells) + c(-.13, .13)[[e]]
      if (panel == 1L) {
        value <- s$fit_rate; lower <- s$fit_rate_wilson95_lower; upper <- s$fit_rate_wilson95_upper
      } else {
        value <- s[[paste0(target, "_95_conditional_coverage")]]
        lower <- s[[paste0(target, "_95_conditional_wilson95_lower")]]
        upper <- s[[paste0(target, "_95_conditional_wilson95_upper")]]
      }
      segments(lower, yy, upper, yy, col = cols[[engine]], lwd = 1.1)
      segments(lower, yy - .055, lower, yy + .055, col = cols[[engine]], lwd = 1.1)
      segments(upper, yy - .055, upper, yy + .055, col = cols[[engine]], lwd = 1.1)
      points(value, yy, pch = markers[[engine]], col = cols[[engine]], cex = .75)
    }
    if (panel == 1L) axis(2, at = seq_along(cells), labels = labels, las = 1,
                          tick = FALSE, line = 0.35, cex.axis = .83, col.axis = "#232A30")
    title(main = c("A  Fit acceptance", "B  Intercept coverage", "C  Slope coverage")[[panel]],
          adj = 0, cex.main = 1.02, line = .7)
    mtext(if (panel == 1L) "Accepted / 2,000 scheduled fits" else "Covered / usable 95% intervals",
          side = 1, line = 2.0, cex = .83)
  }
  mtext("Gaussian random-intercept ML: acceptance and interval coverage",
        side = 3, outer = TRUE, line = 3.4, adj = 0, font = 2, cex = 1.28)
  mtext("R / lme4 (circles)     Julia / MixedModels (squares)",
        side = 3, outer = TRUE, line = 1.6, adj = 1, cex = .88)
  mtext("2,000 shared datasets per scenario. Bars: 95% Wilson Monte Carlo intervals.",
        side = 1, outer = TRUE, line = 1.0, adj = 0, cex = .88)
  mtext("Coverage is conditional on a usable interval; failures remain in scheduled denominators. Companion tables give covered per attempt.",
        side = 1, outer = TRUE, line = 2.3, adj = 0, cex = .85)
}
svg(file.path(out, "reliability-map.svg"), width = 14, height = 8.7, family = "sans")
draw(); invisible(dev.off())
cairo_pdf(file.path(out, "reliability-map.pdf"), width = 14, height = 8.7, family = "sans")
draw(); invisible(dev.off())
png(file.path(out, "reliability-map.png"), width = 2520, height = 1566, res = 180, type = "cairo")
draw(); invisible(dev.off())
cat("RELIABILITY_FIGURE_EXPORTED_SVG_PDF_PNG\n")
