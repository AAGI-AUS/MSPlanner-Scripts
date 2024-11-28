# Quick example R script to demonstrate how to use the
# download_planner_data() function to pull Planner information
# using the Microsoft Graph API and write the results to a CSV.
#
# (Note: If you get strange libcurl errors or crashes when running
# this from the RStudio IDE on particularly large download jobs,
# try running from a vanilla R session or via the terminal.)
#
# Code author: Russell A. Edson, AAGI-AU
# Date last modified: 28/11/2024

# Make sure that download_planner_data.R is in your working directory
source("download_planner_data.R")

# Insert your Microsoft Graph API token here
api_token <- ""

# Insert the Microsoft Group ID for the Group/Team to download here
group_id <- ""

planner_data <- download_planner_data(api_token, group_id, verbose = TRUE)
write.csv(planner_data, file = "my_planner_data.csv", row.names = FALSE)

