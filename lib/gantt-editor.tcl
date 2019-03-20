# /packages/intranet-gantt-editor/lib/task-editor.tcl
#
# Copyright (C) 2012 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

# ----------------------------------------------------------------------
# 
# ---------------------------------------------------------------------

# The following variables are expected in the environment
# defined by the calling /tcl/*.tcl libary:
#	project_id


set page_url [im_url_with_query]
set current_user_id [auth::require_login]
set main_project_id $project_id; # project_id may be overwritten by SQLs below
set main_project_parent_id [db_string mppi "select parent_id from im_projects where project_id = :main_project_id" -default ""]
if {"" ne $main_project_parent_id} { set main_project_id "" }

# Create a debug JSON object that controls logging verbosity
set debug_default "default 0 ganttTreePanel 1 ganttSchedulingController 1"
set debug_list [parameter::get_from_package_key -package_key "intranet-gantt-editor" -parameter DebugHash -default $debug_default]
array set debug_hash $debug_list
set debug_json_list {}
foreach id [array names debug_hash] { lappend debug_json_list "'$id': $debug_hash($id)" }
set debug_json "{\n\t[join $debug_json_list ",\n\t"]\n}"


# Determine the permission of the user
im_project_permissions $current_user_id $main_project_id view_p read_p write_p admin_p

# Create a random ID for the gantt editor
set gantt_editor_rand [expr {round(rand() * 100000000.0)}]
set gantt_editor_id "gantt_editor_$gantt_editor_rand"

# Limit the size of a project to 20 years, in order to avoid performance
# issues that can break the entire system...
set max_project_years [parameter::get_from_package_key -package_key "intranet-gantt-editor" -parameter MaxProjectYears -default "20"]


db_1row project_info "
	select	least(max(end_date), min(start_date + '$max_project_years years'::interval)) as report_end_date,
		min(start_date) as report_start_date,
		(select parent_id from im_projects where project_id = :project_id) as main_parent_id
	from	(
		select	sub_p.start_date,
			sub_p.end_date
		from	im_projects sub_p,
			im_projects main_p
		where	sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
			main_p.project_id = :project_id
		) t
"

# Default material and Unit of Measure: "Default" and "Hour"
set default_material_id [im_material_default_material_id]
set default_cost_center_id [im_cost_center_company]
set default_uom_id [im_uom_hour]

# 9722 = 'Fixed Work' is the default effort_driven_type
set default_effort_driven_type_id [parameter::get_from_package_key -package_key "intranet-ganttproject" -parameter "DefaultEffortDrivenTypeId" -default "9722"]
