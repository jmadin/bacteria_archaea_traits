################
# PREPARE DATA #
################

# In this step all data sources are loaded, with each column labeled according to 
# its data source to avoid clashes between data sets.
# Then the data is merged into one big data frame (no row or column matching)
# Finally, 


###########################
# Create list of datasets #
###########################

#Get list of files in data directory
files <- list.files(path=CONSTANT_DATA_PATH)

#Remove any files set to be exluded in the settings file
files <- files[!files %in% CONSTANT_EXCLUDED_DATASETS]

#Load each data frame, prepare and save in list
dat<- vector("list",length(files))

i <- 1
while(i <= length(files)) {
  print(sprintf("Loading: %s",files[i]))
  dat[[i]] <- prepare_datasets(files[i])
  i<-i+1
}

rm(files)

####################
# Combine datasets #
####################

# Combine all data frames using row bind (no row or column merging will take place)
df <- bind_rows(dat)

# Remove redundant list
rm(dat)


#########################
# Combine data columns  #
#########################

# Data from all columns with same specific names are combined into one column 
# and the original columns removed 
# (i.e. [source1.metabolism] and [source2.metabolism] -> [metabolism])
# The columns/data for which this is done is defined in the settings file

#List of new columns to create to hold the combined trait values
trc <- c("tax_id","org_name",CONSTANT_ALL_DATA_COLUMNS,"reference","ref_type")

#Go through each, create column and combine data
i <- 1
while(i <= length(trc)) {
  
  print(sprintf("Merging trait: %s",trc[i]))
  
  # Initialise new trait column
  df[,trc[i]] <- NA
  
  # Get each relevant column
  cols <- names(df[,grepl(trc[i], names(df))])
  # Move data from each column into new column
  for(a in 1:length(cols)) {
    df[!is.na(df[,cols[a]]),trc[i]] <- df[!is.na(df[,cols[a]]),cols[a]]
  }
  # Remove original columns
  df <- df[, !grepl(sprintf(".%s",trc[i]), names(df))]
  
  # Ensure correct data type for new columns
  if(trc[i] %in% c(CONSTANT_CONTINOUS_DATA_COLUMNS,"tax_id")) {
    df[,trc[i]] <- as.numeric(df[,trc[i]])
  } else {
    df[,trc[i]] <- as.character(df[,trc[i]])
  }
  
  #go to next column
  i <- i+1
}

rm(trc,cols)

############
# clean up #
############

# Remove any rows with no NCBI taxonomy id
df <- df[!is.na(df$tax_id),]

#Change all -inf to NA
df[df == "-Inf"] <- NA

#Copy original df (for original trouble shooting)
df2 <- df


#######################
# TRANSLATE VARIABLES #
#######################

# Translate variables to common terminology using translation tables
# The columns/data for which this is done is defined in the settings file

i<-1 
while(i <= length(CONSTANT_DATA_FOR_RENAMING)) {
  #Create file name
  file <- sprintf("renaming_%s.csv",CONSTANT_DATA_FOR_RENAMING[i])
  
  print(sprintf("Translating %s using file %s",CONSTANT_DATA_FOR_RENAMING[i],file))
  
  #Get file
  look <- read.csv(sprintf("%s/%s",CONSTANT_LOOKUP_TABLE_PATH ,file), as.is=TRUE)
  if(nrow(look)>0) {
    df2[,CONSTANT_DATA_FOR_RENAMING[i]] <- look$New[match(unlist(df2[,CONSTANT_DATA_FOR_RENAMING[i]]), look$Original)]
  } else {
    print(sprintf("Issue with lookup table for %s",CONSTANT_DATA_FOR_RENAMING[i]))
  }
  
  i<-i+1
}

# Remove isolation_source type "Unclassified"
df2[!is.na(df2$isolation_source) & df2$isolation_source == "unclassified", "isolation_source"] <- NA

rm(look,file,i)

################
# Map taxonomy #
################

# Map full NCBI taxonomy onto each column
# Since ncbi_taxmap only contains prokaryotes, this process also removes any non-prokaryotic organisms

df3 <- inner_join(df2, tax, by = "tax_id")


####################
# Data corrections #
####################

# Correct identified data value errors

# Load corrections from table
co <- read.csv("data/conversion_tables/data_corrections.csv", as.is=TRUE)

print("DATA CORRECTIONS:")

for(i in 1:nrow(co)) {
    
    #Find value to replace in specific column
    if(any(!is.na(df3[df3$data_source == co$data_source[i] & 
                  df3$tax_id == co$tax_id[i] & 
                  !is.na(df3[,co$column[i]]) & 
                  df3[,co$column[i]] == co$org_value[i], 
                  co$column[i]]))) {
      
      #Ensure data type integrity
      if(is.numeric(co$new_value[i])) {
        #This value is numeric
        new_value <- as.numeric(co$new_value[i])
      } else if(is.character(co$new_value[i])) {
        #This is a character string
        new_value <- as.character(co$new_value[i])
      } else {
        new_value <- NA
      }
      
      #Count number of rows found that match the search criteria
      count <- nrow(df3[df3$data_source == co$data_source[i] &
                          df3$tax_id == co$tax_id[i] &
                          !is.na(df3[,co$column[i]]) & 
                          df3[,co$column[i]] == co$org_value[i],])
      
      #Fix some text for output
      if(count > 1) {
        match_txt <- "matches"
      } else {
        match_txt <- "match"
      }
      count_output <- sprintf("%s %s",count,match_txt)
      
      #Update data value
      df3[df3$data_source == co$data_source[i] &
            df3$tax_id == co$tax_id[i] &
            !is.na(df3[,co$column[i]]) & 
            df3[,co$column[i]] == co$org_value[i], 
          co$column[i]] <- new_value
      
      #Print outcome
      print(sprintf("correction: [%s;%s;%s] %s -> %s    [%s]",co$data_source[i],co$org_name[i],co$column[i],co$org_value[i],new_value,count_output))
    }
}

rm(co,new_value,count_output,match_txt)

###########################
# Additional calculations #
###########################

# Here we place any scripts that adds new columns with values
# calculated based on raw data in the table

# Calculate temperature normalised growth rates

# Note: the temperature normalised growth rate is calculated based on the actual 
# growth temperature (growth_tmp) for which the growth rate were measured. If this value is 
# not available, the optimum temperature (optimum_tmp) is assumed and used for calculation

# Create new data column
df3$doubling_h_norm <- as.numeric(NA)

# Create temporary temperature column
df3$tmp_tmp <- NA

# Populate temporary column with growth temperatures and fill with optimum temperatures
df3$tmp_tmp <- df3$growth_tmp
df3$tmp_tmp[is.na(df3$tmp_tmp) & !is.na(df3$optimum_tmp)] <- df3$optimum_tmp[is.na(df3$tmp_tmp) & !is.na(df3$optimum_tmp)]

# Calculate rates for each row based on temperature value in temporary table
df3$doubling_h_norm[!is.na(df3$doubling_h) & !is.na(df3$tmp_tmp)] <- apply(df3[!is.na(df3$doubling_h) & !is.na(df3$tmp_tmp), c("tmp_tmp","doubling_h")],1 , function(x) temp_adjust_doubling_h(x['doubling_h'], x['tmp_tmp'], CONSTANT_GROWTH_RATE_ADJUSTMENT_FINAL_TMP, CONSTANT_GROWTH_RATE_ADJUSTMENT_Q10))

# Remove temporary temperature column
df3 <- subset(df3, select = -c(tmp_tmp))


####

# Ensure coccus shaped cells (round) also have a length value (d2) if no length is supplied
df3$d2_lo[!is.na(df3$cell_shape) & df3$cell_shape == "coccus" & !is.na(df3$d1_lo) & is.na(df3$d2_lo)] <- as.double(df3$d1_lo[!is.na(df3$cell_shape) & df3$cell_shape == "coccus" & !is.na(df3$d1_lo) & is.na(df3$d2_lo)])
df3$d2_up[!is.na(df3$cell_shape) & df3$cell_shape == "coccus" & !is.na(df3$d1_up) & is.na(df3$d2_up)] <- as.double(df3$d1_up[!is.na(df3$cell_shape) & df3$cell_shape == "coccus" & !is.na(df3$d1_up) & is.na(df3$d2_up)])


##########################
# Create reference table #
##########################

# This table holds all reference information (any type)

# Copy all reference information into new table
ref <- df3[!is.na(df3$reference) & !duplicated(df3$reference),c("reference","ref_type")]
# Rename columns
names(ref) <- c("org_ref","ref_type")
# Copy original reference information into a new table
ref$new_ref <- ref$org_ref

# Go through each reference and split any multi-references (separated by comma)
for(i in 1:nrow(ref)) {

  if(grepl(',',ref$org_ref[i]) & !(ref$ref_type[i] == "full_text")) {

    list <- unlist(strsplit(ref$org_ref[i],","))

    if(length(list) > 1) {
      # Insert each item as a new row
      for(a in 1:length(list)) {
        new_ref <- list[a]
        thisRowData <- c(ref$org_ref[i],ref$ref_type[i],new_ref)
        ref[nrow(ref)+1,] <- thisRowData
      }
      #Remove original reference
      ref <- ref[!(ref$new_ref == ref$org_ref[i]), ]
    }
  } else {
    #just copy original single ref into new column
    ref$new_ref <- ref$org_ref
  }
}

# Remove any duplicated rows
ref <- unique(ref[, names(ref)])

# Get list of unique ids
ref_ids <- unique(ref[,c("ref_type","new_ref")])
# Create new column for ref_id
ref_ids$ref_id <- NA

# Create a unique id for each row using row_number
ref_ids <- ref_ids %>% mutate(ref_id = row_number()) 

# merge new reference id back onto reference data frame
ref <- ref %>% left_join(ref_ids, by = c("ref_type","new_ref"))

# Assign new reference ids to main data frame based on original reference
# Note: The new_ref column may be a subset of the original reference text 
# and thus cannot be used to merge back into the original data frame
df4 <- df3 %>% left_join(ref, by = c("reference"="org_ref","ref_type"))

# Remove redundant reference columns from main data frame
df4 <- subset(df4, select = -c(reference,ref_type,new_ref))

#Save reference table (remove original reference column)
ref <- ref[c("ref_id", "ref_type", "new_ref")]
names(ref) <- c("ref_id", "ref_type", "reference")
write.csv(ref, "output/prepared_references/references.csv", row.names=FALSE)

rm(ref,ref_ids)


############
# Clean up #
############

# Keep only required columns (defined in settings)
df5 <- df4[,CONSTANT_FINAL_COLUMNS]

#Convert any blank fields into NA
df5[df5 == ""] <- NA
df5[df5 == " "] <- NA

# Remove rows with no data in selected columns
df6 <- df5[rowSums(is.na(df5[CONSTANT_ALL_DATA_COLUMNS])) != length(CONSTANT_ALL_DATA_COLUMNS), ]

# Remove redundant data frames (keep for trouble shooting)
rm(df,df2,df3,df4,df5)


#############
# Save data #
#############

#Save main data frame
write.csv(df6, "output/condensed_traits.csv", row.names=FALSE)

rm(df6)
