# /packages/sencha-task-editor/lib/task-editor.tcl
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

set data_list {}

# project_id may be overwritten by SQLs below
set main_project_id $project_id

# Create a random ID for the task_editor
set task_editor_rand [expr round(rand() * 100000000.0)]
set task_editor_id "task_editor_$task_editor_rand"


