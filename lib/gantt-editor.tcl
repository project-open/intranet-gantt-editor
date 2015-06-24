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

# project_id may be overwritten by SQLs below
set main_project_id $project_id

# Create a random ID for the gantt editor
set gantt_editor_rand [expr round(rand() * 100000000.0)]
set gantt_editor_id "gantt_editor_$gantt_editor_rand"


db_1row project_info "
select	max(end_date) + '7 days'::interval as report_end_date,
	min(start_date) - '7 days'::interval as report_start_date
from	(
	select	sub_p.start_date,
		sub_p.end_date
	from	im_projects sub_p,
		im_projects main_p
	where	sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
		main_p.project_id = :project_id
	) t
"
