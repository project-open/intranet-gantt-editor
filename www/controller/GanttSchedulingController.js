/*
 * GanttTreePanelController.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */


/**
 * GanttSchedulingController
 * Reacts to changes of start_date, end_date, work, assignments and possibly other 
 * task fields and modifies other tasks according to the specified scheduling type:
 * <ul>
 * <li>No scheduling
 * <li>Manually scheduled tasks
 * <li>Single project scheduling
 * <li>Multiproject scheduling
 * </ul>
 */
Ext.define('GanttEditor.controller.GanttSchedulingController', {
    extend: 'Ext.app.Controller',
    debug: false,
    'ganttTreePanel': null,							// Defined during initialization
    'taskTreeStore': null,							// Defined during initialization
    init: function() {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.init: Starting');

        me.taskTreeStore.on({
            'update': me.onTreeStoreUpdate,					// Listen to any changes in store records
            'scope': this
        });

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.init: Finished');
        return this;
    },

    onTreeStoreUpdate: function(treeStore, model, operation, fieldsChanged, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Starting');
        fieldsChanged.forEach(function(fieldName) {
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Field changed='+fieldName);
            switch (fieldName) {
            case "start_date":
                me.onStartDateChanged(treeStore, model, operation, event);
                break;
            case "end_date":
                me.onEndDateChanged(treeStore, model, operation, event);
                break;
            }
        });
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Finished');
    },

    /**
     * The start_date of a task has changed.
     * Check if this new date is before the start_date of it's parent.
     * In this case we need to adjust the parent.
     */
    onStartDateChanged: function(treeStore, model, operation, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Starting');
        var parent = model.parentNode;					// 
        if (!parent) return;
	var parent_start_date = parent.get('start_date');
	if ("" == parent_start_date) return;
        var parentStartDate = PO.Utilities.pgToDate(parent_start_date);

        // Calculate the minimum start date of all siblings
        var minStartDate = PO.Utilities.pgToDate('2099-12-31');
        parent.eachChild(function(sibling) {
            var siblingStartDate = PO.Utilities.pgToDate(sibling.get('start_date'));
            if (siblingStartDate.getTime() < minStartDate.getTime()) {
                minStartDate = siblingStartDate;
            }
        });

        // Check if we have to update the parent
        if (parentStartDate.getTime() != minStartDate.getTime()) {
            // The siblings start different than the parent - update the parent.
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Updating parent at level='+parent.getDepth());
            parent.set('start_date', PO.Utilities.dateToPg(minStartDate));				// This will call this event recursively
        }
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Finished');
    },

    /**
     * The end_date of a task has changed.
     * Check if this new date is after the end_date of it's parent.
     * In this case we need to adjust the parent.
     */
    onEndDateChanged: function(treeStore, model, operation, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Starting');

        var parent = model.parentNode;
        if (!parent) return;
        var parent_end_date = parent.get('end_date');
	if ("" == parent_end_date) return;
        var parentEndDate = PO.Utilities.pgToDate(parent_end_date);

        // Calculate the maximum end date of all siblings
        var maxEndDate = PO.Utilities.pgToDate('2000-01-01');
        parent.eachChild(function(sibling) {
            var siblingEndDate = PO.Utilities.pgToDate(sibling.get('end_date'));
            if (siblingEndDate.getTime() > maxEndDate.getTime()) {
                maxEndDate = siblingEndDate;
            }
        });

        // Check if we have to update the parent
        if (parentEndDate.getTime() != maxEndDate.getTime()) {
            // The siblings end different than the parent - update the parent.
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Updating parent at level='+parent.getDepth());
            parent.set('end_date', PO.Utilities.dateToPg(maxEndDate));					// This will call this event recursively
        }
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Finished');
    },
});
