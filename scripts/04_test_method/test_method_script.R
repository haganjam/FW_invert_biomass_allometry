
# Test the method for calculating species biomasses

# load the relevant libraries
library(here)
library(dplyr)
library(readr)
library(ggplot2)
library(ggbeeswarm)
library(ggpubr)

# load the use-scripts
source(here("scripts/02_function_plotting_theme.R"))
source(here("scripts/03_use_database/01_search_database.R"))

# check if a figure folder exists
if(! dir.exists(here("figures"))){
  dir.create(here("figures"))
}

# test 1: actual body size data and actual length data from the literature

# load the literature test data
test1 <- readxl::read_xlsx(path = "C:/Users/james/OneDrive/PhD_Gothenburg/Chapter_4_BEF_rockpools_Australia/data/trait_and_allometry_data/allometry_database_ver2/test_data.xlsx")
str(test1)

# convert the lat-lon variables to numeric variables
test1$lat <- as.numeric(test1$lat)
test1$lon <- as.numeric(test1$lon)

# remove cases where life-stages are NA
test1 <- dplyr::filter(test1, !is.na(Life_stage), Life_stage != "NA")

# test the method
test1.output <- 
  Get_Trait_From_Taxon(input_data = test1, 
                       target_taxon = "Taxa", 
                       life_stage = "Life_stage", 
                       body_size = "Length_mm",
                       latitude_dd = "lat", 
                       longitude_dd = "lon",
                       workflow = "workflow2",
                       trait = "equation", 
                       max_tax_dist = 3.5,
                       gen_sp_dist = 0.5
  )

View(test1.output)

# remove rows where the weight is not there
test1.output <- 
  test1.output %>%
  filter(!is.na(weight_mg) )
View(test1.output)

# variable for whether equation is outside the range developed for
test1.output <- 
  test1.output %>% 
  mutate(range_flag = ifelse(is.na(flags), FALSE, TRUE))

# check how many unique taxa are left
length(unique(test1.output$Taxa))


# null model i.e. randomly chosen equations

# load the equation data
equ.dat <- readRDS(file = paste0(here::here("database"), "/", "equation", "_database.rds"))
head(equ.dat)

equ.dat <- 
  equ.dat %>%
  select(equation_id, equation)

equ.null <- 
  lapply(1:1000, function(y) {
  
  sapply(test1.output$Length_mm, function(x) {
    
    var1 <- x
    equ <- equ.dat[sample(1:nrow(equ.dat), 1),][["equation"]]
    
    eval(parse(text = equ))
    
  })
  
})  

# combine into a matrix
equ.null.m <- do.call("rbind", equ.null)

# calculate percentile intervals
equ.null.m <- apply(equ.null.m, 2, function(x) quantile(x = x, c(0.025, 0.975)) )

# add the percentile intervals to the test data
test1.output$lower_PI <- apply(equ.null.m, 2, function(x) x[1] )
test1.output$upper_PI <- apply(equ.null.m, 2, function(x) x[2] )

# check the data
View(test1.output)

# plot dry weight inferred versus actual dry weight
p1 <- 
  ggplot() +
  geom_ribbon(data = test1.output,
              mapping = aes(x = log10(Dry_weight_mg),
                            ymin = log10(lower_PI),
                            ymax = log10(upper_PI) ),
              alpha = 0.1) +
  geom_point(data = test1.output,
             mapping = aes(x = log10(Dry_weight_mg), y = log10(weight_mg)),
             alpha = 0.2) +
  ylab("Estimated dry biomass (mg, log10)") +
  xlab("Measured dry biomass (mg, log10)") +
  geom_abline(intercept = 0, slope = 1, 
              colour = "#ec7853", linetype = "dashed", size = 1) +
  theme_meta()
plot(p1)

# observed correlation
cor.test(test1.output$Dry_weight_mg, test1.output$weight_mg)

# null correlations
null_cor <- sapply(equ.null, function(x) cor(test1.output$Dry_weight_mg, x) )
quantile(null_cor, c(0.025, 0.975))

# calculate percentage
test1.output <- 
  test1.output %>%
  mutate(error_perc = (abs(Dry_weight_mg - weight_mg)/Dry_weight_mg)*100 )

# calculate the error for each randomisation
equ.null.error <- 
  
  lapply(equ.null, function(x) {
  
  (abs(test1.output$Dry_weight_mg - x)/test1.output$Dry_weight_mg)*100
  
} )

# unlist all randomisations
equ.null.error <- unlist(equ.null.error)

# plot the distributions of the true error and the randomised error
error_hist <- bind_rows(tibble(Method = "FreshInvTraitR",
                               error_perc = test1.output$error_perc),
                        tibble(Method = "Random",
                               error_perc = equ.null.error))

# get the 90 % quantiles of the error for both
p2 <- 
  error_hist %>%
  group_by(Method) %>%
  mutate(low_PI = quantile(error_perc, 0.025),
         upper_PI = quantile(error_perc, 0.975)) %>%
  filter(error_perc > low_PI, error_perc < upper_PI) %>%
  
  ggplot(data = .,
       mapping = aes(x = log( error_perc ), colour = Method, fill = Method)) +
  geom_density(alpha = 0.6) +
  scale_colour_manual(values = c("#0c1787", "#fadb25")) +
  scale_fill_manual(values = c("#0c1787", "#fadb25")) +
  xlab("Absolute deviation (%, loge)") +
  ylab(NULL) +
  geom_vline(xintercept = mean( log( test1.output$error_perc) ), 
             linetype = "dashed", size = 0.5,
             colour = "#0c1787") +
  geom_vline(xintercept = mean(log(equ.null.error) ), 
             linetype = "dashed", size = 0.5,
             colour = "#fadb25") +
  theme_meta()
plot(p2)


p12 <- ggarrange(p1, p2, ncol = 2,nrow = 1,
                 labels = c("a", "b"),
                 widths = c(1, 1.1),
                 font.label = list(size = 11, color = "black", face = "plain")
                 )
plot(p12)

# export Fig. 4
ggsave(filename = here("figures/fig_4.pdf"), plot = p12, 
       units = "cm", width = 20, height = 10, dpi = 300)

# what is this like on an absolute scale? Ten-fold difference in average error
mean(test1.output$error_perc)
sd(test1.output$error_perc)
mean(equ.null.error)
sd(equ.null.error)

# plot how the error changes with taxonomic distance
test1.eplot <- 
  test1.output %>% 
  filter(error_perc < 1000)

test1.eplot.s <- 
  test1.eplot %>%
  group_by(tax_distance) %>%
  summarise(mean_error = mean(error_perc, na.rm = TRUE),
            sd_error = sd(error_perc, na.rm = TRUE))

test1.eplot %>%
  filter(tax_distance <= 1) %>%
  summarise(mean_error = mean(error_perc),
            sd_error = sd(error_perc), 
            n = length(unique(Taxa)))

# replot without the major outliers
p3 <- 
  ggplot() +
  ylab("Absolute deviation (%)") +
  xlab("Taxonomic distance") +
  geom_quasirandom(data = test1.eplot,
              mapping = aes(x = tax_distance, y = (error_perc) ), 
              width = 0.15, alpha = 0.15) +
  geom_point(data = test1.eplot.s,
             mapping = aes(x = tax_distance, y = mean_error),
             colour = "black", size = 2.5) +
  geom_errorbar(data = test1.eplot.s,
                mapping = aes(x = tax_distance, 
                              ymin = mean_error - sd_error,
                              ymax = mean_error + sd_error),
                width = 0.1, colour = "black") +
  theme_meta()

# export Fig. 5
ggsave(filename = here("figures/fig_5.pdf"), plot = p3, 
       units = "cm", width = 10, height = 10, dpi = 300)


# test 2: equations selected by expert

# load data compiled by Vincent
test2 <- read_csv("C:/Users/james/OneDrive/PhD_Gothenburg/Chapter_4_BEF_rockpools_Australia/data/trait_and_allometry_data/allometry_database_ver2/test_data_vincent.csv")
test2$lat <- NA
test2$lon <- NA

# view the data
View(test2)

# test the method
test2.output <- 
  Get_Trait_From_Taxon(input_data = test2, 
                       target_taxon = "Focal_taxon", 
                       life_stage = "Life_stage", 
                       body_size = "length_mm",
                       latitude_dd = "lat", 
                       longitude_dd = "lon",
                       trait = "equation", 
                       workflow = "workflow2",
                       max_tax_dist = 3,
                       gen_sp_dist = 0.5
  )

# remove rows where the weight is not there
test2.output <- 
  test2.output %>%
  filter(!is.na(weight_mg) )
names(test2.output)

test2.output <- 
  test2.output %>%
  select(Focal_taxon, life_stage, length_mm, scientificName, db.scientificName, 
         tax_distance, id,
         Biomass_mg, weight_mg, life_stage_match) %>%
  mutate(weight_mg = round(weight_mg, 3),
         error_perc = (abs(Biomass_mg - weight_mg)/Biomass_mg)*100)

# check how many unique taxa there are
length(unique(test2.output$Focal_taxon))

p4 <- 
  ggplot(data = test2.output,
       mapping = aes(x = log10(Biomass_mg), y = log10(weight_mg)) ) +
  geom_point() +
  ylab("Estimated dry biomass (mg, log10)") +
  xlab("Expert dry biomass (mg, log10)") +
  geom_abline(intercept = 0, slope = 1, 
              colour = "#ec7853", linetype = "dashed", size = 1) +
  theme_meta() +
  theme(legend.position = "bottom")
plot(p4)

ggsave(filename = here("figures/fig_6.pdf"), plot = p4, 
       units = "cm", width = 10, height = 10, dpi = 300)

cor.test(log10(test2.output$Biomass_mg), log10(test2.output$weight_mg) )

# what about the error?
mean(test2.output$error_perc)
sd(test2.output$error_perc)

test2.output %>%
  filter(error_perc > 500) %>% 
  pull(error_perc)

test2.output %>%
  filter(error_perc < 500) %>%
  summarise(mean = mean(error_perc),
            sd = sd(error_perc))

### END
