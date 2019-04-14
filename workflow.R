# The dataset pipeline

## List of required files not included in the Github repository due to their size:
# "Mark_Westoby_Organism_Metadata_Export_02152018.txt" (goes in "data/gold/")
# "taxonomy_names.csv" (goes in "output/")
# "taxonomy_nodes.csv" (goes in "output/")
# "ncbi_taxmap.csv" (goes in "output/taxmaps/")
# "genome_metadata.txt" (goes in "data/raw/patric/")


# Check for and install necessary packages
source("R/packages.R")

# Load global functions
source("R/functions.R")

# Load global settings
source("R/settings.R")

# Load raw NCBI taxonomy table if not already loaded; takes a while but only done once
if(!exists('nam') || !is.data.frame(get('nam'))) {
  nam <- read.csv("output/taxonomy/taxonomy_names.csv", as.is=TRUE)
}

# Load NCBI archaea and bacteria tax_id, species_tax_id and taxonomy hierarchy if not already loaded
if(!exists('tax') || !is.data.frame(get('tax'))) {
  tax <- read.csv("output/taxonomy/ncbi_taxmap.csv", as.is=TRUE)
  tax <- unique(tax[, names(tax)])
}

# 1. Preparing original datasets
# Refer to README.md files in each of the original dataset directories for more information.

source("R/preparation/corkrey.R")
source("R/preparation/edwards.R")
source("R/preparation/engqvist.R")
source("R/preparation/fierer.R")
source("R/preparation/genbank.R")
source("R/preparation/jemma-refseq.R")
source("R/preparation/gold.R")
source("R/preparation/kegg.R")
source("R/preparation/kremer.R")
source("R/preparation/masonmm.R")
source("R/preparation/mediadb.R")
source("R/preparation/metanogen.R")
source("R/preparation/microbe-directory.R")
source("R/preparation/patric.R")
source("R/preparation/prochlorococcus.R")
source("R/preparation/protraits.R")
source("R/preparation/rrndb.R")
source("R/preparation/silva.R")

# 2. Merging

source("R/condense_traits.R")
source("R/condense_species.R")
