# /packages/intranet-gantt-editor/tcl/intranet-gantt-editor.tcl
#
# Copyright (C) 2010-2013 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    Gantt Editor library.
    @author frank.bergmann@project-open.com
}

ad_proc -public gantt_editor_portlet {
    -project_id:required
} {
    Returns a HTML code with a Gantt editor for the project.
} {
    # Only show for GanttProjects
    if {[im_security_alert_check_integer -location "im_ganttproject_gantt_component" -value $project_id]} { return "" }
    set project_type_id [util_memoize [list db_string project_type "select project_type_id from im_projects where project_id = $project_id" -default ""]]
    if {![im_category_is_a $project_type_id [im_project_type_gantt]]} { 

	# Check if this is run from a tab in a non-Gantt project
	# In this case we need to show an error message instead of a blank screen.
	set plugin_id [im_opt_val plugin_id]
	if {"" ne $plugin_id} {
	    return "<p>This project is not a Gantt project, but of type '[im_category_from_id $project_type_id]'. 
            <br>Such projects don't have Gantt charts.</p>"
	} else {
	    return "" 
	}
    }

    # Sencha check and permissions
    if {![im_sencha_extjs_installed_p]} { return "" }
    im_sencha_extjs_load_libraries

    set params [list \
                    [list project_id $project_id] \
		    ]

    set result [ad_parse_template -params $params "/packages/intranet-gantt-editor/lib/gantt-editor"]
    return [string trim $result]
}
