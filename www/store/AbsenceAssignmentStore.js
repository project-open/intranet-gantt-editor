/* 
 * /intranet-gantt-editor/www/store/AbsenceAssignmentStore.js
 *
 * Copyright (C) 2014 ]project-open[
 * All rights reserved. Please see
 * http://www.project-open.com/license/sencha/ for details.
 *
 * A store with the list of absences or assignments of the users
 * in the project.
 */

Ext.define('GanttEditor.store.AbsenceAssignmentModel', {
    extend: 'Ext.data.Model',
    fields: [
	'id',
	'object_id',
	'object_type',
	'user_id',
	'user_name',
	'start_date',
	'end_date',
	'percentage',
	'name',
	'context_id',
	'context'
    ]
});


Ext.define('GanttEditor.store.AbsenceAssignmentStore', {
    storeId:		'absenceAssignmentStore',
    extend:		'Ext.data.Store',
    model: 		'GanttEditor.store.AbsenceAssignmentModel',		// Uses standard Absence as model
    autoLoad:		false,
    remoteFilter:	true,					// Do not filter on the Sencha side
    pageSize:		100000,					// Load all projects, no matter what size(?)
    proxy: {
	type:		'rest',					// Standard ]po[ REST interface for loading
	url:		'/intranet-reporting/view',
	appendId:	true,
	timeout:	300000,
	extraParams: {
	    report_code:	'rest_project_member_assignments_absences',
	    format:		'json',
	    main_project_id:	'0',				// to be overwritten
	    // deref_p:		'1'				// We don't need company_name etc.
	    // This should be overwrittten during load.
	},
	reader: {
	    type:		'json',				// Tell the Proxy Reader to parse JSON
	    root:		'data',				// Where do the data start in the JSON file?
	    totalProperty:	'total'				// Total number of tickets for pagination
	},
	writer: {
	    type:		'json'				// Allow Sencha to write ticket changes
	}
    }
});
