# R function for downloading data from Microsoft Planner (within
# Microsoft Teams/Groups) using the Microsoft Graph API.
#
# (Note: Run this function via the R CLI/terminal---for some reason,
# the script tends to crash when it is run in the RStudio IDE. Might
# be a libcurl issue? In any case, running via terminal seems to
# avoid the issue entirely.)
#
# 06/01/2025 Update: Manually closing curl connections is probably
#   safest, since the GC won't always clean these up in time (I was
#   getting errors like "all 128 connections in use").
# 
# Code author: Russell A. Edson, AAGI-AU
# Date last modified: 06/01/2025

if (!require(curl)) { install.packages("curl") }
if (!require(jsonlite)) { install.packages("jsonlite") }
if (!require(stringr)) { install.packages("stringr") }

#' Download data from the given Microsoft Planner Team/Group
#'
#' Given a Microsoft Graph API token and the ID for a given
#' Microsoft Planner Team/Group, downloads all of the data for all
#' Planner Tasks (e.g., progress, assigned personnel, labels,
#' dates, checklist and notes) across all Planner Plans.
#' Note that assigned personnel, labels, and checklist items 
#' appear as a single string inside curly braces {...}, which 
#' can be post-processed appropriately.
#'
#' @param api_token A string containing the Microsoft Graph API
#'   token (needed to programmatically access the Planner data).
#' @param group_id A string containing the ID for the Microsoft
#'   Planner Team/Group that should have its Plans downloaded.
#' @param verbose If TRUE, prints to STDOUT the Plan/Bucket/Task 
#'   for every Task downloaded (default=FALSE).
#' @return A data.frame, containing a row for every Task of every
#'   Bucket of every Plan associated with the Team/Group ID.
download_planner_data <- function(api_token, group_id, verbose = FALSE) {
  data <- data.frame(
    `UID` = character(),
    `Plan` = character(),
    `Bucket` = character(),
    `Task` = character(),
    `Progress` = numeric(),
    `Assigned Personnel` = character(),
    `Labels` = character(),
    `Priority` = character(),
    `Start Date` = character(),
    `Due Date` = character(),
    `Completed Date` = character(),
    `Checklist` = character(),
    `Notes` = character(),
    check.names = FALSE
  )
  # 21/11/2024 TODO: We probably want to pull Comments as well.

  # Retrieve list of Team/Group Plans and their IDs
  handle <- curl::new_handle()
  curl::handle_setheaders(handle, "Authorization" = paste("Bearer", api_token))
  connection <- curl::curl(
    paste0(
      "https://graph.microsoft.com/v1.0/groups/",
      group_id,
      "/planner/plans"
    ),
    handle = handle
  )
  json <- jsonlite::fromJSON(readLines(connection, warn = FALSE))
  close(connection)
  plans <- json$value[ , c("title", "id")]
  #TODO: If no Plans at all, return nothing?

  for (plan_index in 1:nrow(plans)) {
    plan <- plans[plan_index, ]
    plan_id <- plan$id
    plan_title <- plan$title
    
    # Retrieve list of Bucket IDs
    connection <- curl::curl(
      paste0(
        "https://graph.microsoft.com/v1.0/planner/plans/",
        plan_id,
        "/buckets?$select=id,name"
      ),
      handle = handle
    )
    json <- jsonlite::fromJSON(readLines(connection, warn = FALSE))
    close(connection)
    buckets <- json$value[ , c("name", "id")]
    
    # Retrieve list of Label category names and IDs
    connection <- curl::curl(
      paste0(
        "https://graph.microsoft.com/v1.0/planner/plans/",
        plan_id,
        "/details?$select=categoryDescriptions"
      ),
      handle = handle
    )
    json <- jsonlite::fromJSON(readLines(connection, warn = FALSE))
    close(connection)
    label_text <- as.character(json$categoryDescriptions)
    label_category <- names(json$categoryDescriptions)
    labels <- data.frame(
      `colour` = c(
        "Pink", "Red", "Yellow", "Green", "Blue", "Purple", "Bronze", "Lime",
        "Aqua", "Grey", "Silver", "Brown", "Cranberry", "Orange", "Peach",
        "Marigold", "Light green", "Dark green", "Teal", "Light blue",
        "Dark blue", "Lavender", "Plum", "Light grey", "Dark grey"
      ),
      `label` = label_text,
      `category` = label_category
    )
    
    # Retrieve main Task details from top-level plan view
    connection <- curl::curl(
      paste0(
        "https://graph.microsoft.com/v1.0/planner/plans/",
        plan_id,
        "/tasks?$select=id,bucketId,title,startDateTime,dueDateTime,",
        "completedDateTime,assignments,priority,appliedCategories,",
        "percentComplete"
      ),
      handle = handle
    )
    json <- jsonlite::fromJSON(readLines(connection, warn = FALSE))
    close(connection)
    tasks <- json$value
    
    if (length(tasks) != 0) {
      for (task_index in 1:nrow(tasks)) {
        task <- tasks[task_index, ]
        task_id <- task$id
        task_bucket <- buckets[which(buckets$id == task$bucketId), "name"]
        task_name <- task$title
        task_progress <- task$percentComplete

        #TODO: May need to do some extra parsing for Priority: at the
        # moment it returns numbers that don't really mean anything.
        # They should map to "Urgent", "Important", "Medium", "Low" in
        # hopefully a one-to-one way. 
        task_priority <- task$priority

        task_startdate <- as.character(as.Date(task$startDateTime))
        task_duedate <- as.character(as.Date(task$dueDateTime))
        task_completeddate <- as.character(as.Date(task$completedDateTime))
        
        # Parse assignments (if any)
        task_assignments <- ""
        if (length(task$assignments) != 0) {
          possible_assignments <- names(task$assignments)
          assignments <- character()
          for (assigned_id in possible_assignments) {
            # There's nothing special about @odata.type here: we just
            # need to check for a non-NA value in the task$assignments
            # object. If Microsoft ever changes it so @odata.type is
            # no longer returned, just replace this with any of the
            # other returned fields and it will still work.
            if (!is.na(task$assignments[assigned_id][[1]]["@odata.type"])) {
              assignments[length(assignments) + 1] <- assigned_id
            }
          }
          task_assignments <- paste(assignments, collapse = ",")
        }
        task_assignments <- paste0("{", task_assignments, "}")
        
        # Parse labels (if any)
        task_labels <- character()
        applied_categories <- task$appliedCategories[
          which(task$appliedCategories == TRUE)
        ]
        if (length(applied_categories) != 0) {
          for (label_index in 1:length(applied_categories)) {
            label <- labels[
              which(
                labels$category == names(applied_categories[label_index])
              ), ]
            task_labels <- append(
              task_labels,
              ifelse(label$label == "NULL", label$colour, label$label)
            )
          }
        }
        task_labels <- paste0(
          "{", 
          paste0(task_labels, collapse = ","),
          "}"
        )
        
        # Retrieve description and checklist info
        #TODO: Also comments, at some point.
        connection <- curl::curl(
          paste0(
            "https://graph.microsoft.com/v1.0/planner/tasks/",
            task_id,
            "/details?$select=description,checklist"
          ),
          handle = handle
        )
        json <- jsonlite::fromJSON(readLines(connection, warn = FALSE))
        close(connection)
        task_details <- json
        task_notes <- ifelse(
          is.null(task_details$description),
          "",
          task_details$description
        )
        
        # Parse checklist items (if any)
        task_checklist <- character()
        for (checklist_item in task_details$checklist) {
          task_checklist <- append(
            task_checklist,
            paste0(
              "{", 
              checklist_item$title,
              ",",
              ifelse(checklist_item$isChecked, "Complete", "Not Complete"),
              "}"
            )
          )
        }
        task_checklist <- paste0(
          "{", 
          paste0(task_checklist, collapse = ","),
          "}"
        )
        
        data[nrow(data) + 1, ] <- c(
          task_id, plan_title, task_bucket, task_name, task_progress,
          task_assignments, task_labels, task_priority, task_startdate,
          task_duedate, task_completeddate, task_checklist, task_notes
        )

        # Add a brief pause of kindness so that we're not repeatedly
        # hitting the MS Teams server with requests. (They do rate 
        # limit this, I'm not sure what the threshold is but we need
        # some sort of pause here for sure.)
        Sys.sleep(0.5)
        if (verbose) {
          cat(
            paste0(
              data[nrow(data), "UID"], "    ",
              data[nrow(data), "Plan"], ":::",
              data[nrow(data), "Bucket"], ":::",
              data[nrow(data), "Task"], "\n"
            )
          )
        }
      }
    }
  }
  
  # Replace user IDs with readable display names
  personnel_ids <- stringr::str_extract(
    data$`Assigned Personnel`,
    "\\{([^}]*)\\}",
    group = 1
  ) |>
    stringr::str_split(",") |>
    unlist() |>
    unique()
  personnel_ids <- personnel_ids[personnel_ids != ""]
  if (length(personnel_ids) > 0) {
    for (personnel_id in personnel_ids) {
      connection <- curl::curl(
        paste0(
          "https://graph.microsoft.com/v1.0/users/",
          personnel_id,
          "?$select=displayName"
        ),
        handle = handle
      )
      json <- jsonlite::fromJSON(readLines(connection, warn = FALSE))
      close(connection)
      personnel_display_name <- json$displayName
      data$`Assigned Personnel` <- stringr::str_replace_all(
        data$`Assigned Personnel`,
        stringr::fixed(personnel_id),
        personnel_display_name
      )
    }
  }

  data
}
