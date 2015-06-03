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
    # Sencha check and permissions
    if {![im_sencha_extjs_installed_p]} { return "" }
    im_sencha_extjs_load_libraries

    set params [list \
                    [list project_id $project_id] \
		    ]

    set result [ad_parse_template -params $params "/packages/intranet-gantt-editor/lib/gantt-editor"]
    return [string trim $result]
}
