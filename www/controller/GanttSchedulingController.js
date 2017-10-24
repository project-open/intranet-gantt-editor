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

    /**
     * Some function has changed the TreeStore:
     * Make sure to propagate the changes along dependencies
     */
    onTreeStoreUpdate: function(treeStore, model, operation, fieldsChanged, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Starting');

        var dirty = false;
        if (null != fieldsChanged) {
            fieldsChanged.forEach(function(fieldName) {
                if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Field changed='+fieldName);
                switch (fieldName) {
                case "start_date":
                    me.onStartDateChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
                case "end_date":
                    me.onEndDateChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
                case "planned_units":
                    me.onPlannedUnitsChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
                case "parent_id":
                    // Task has new parent - indentation or un-indentation
                    me.onStartDateChanged(treeStore, model, operation, event);
                    me.onEndDateChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
                case "leaf":
                    // A task has changed from leaf to tree or reverse:
                    // Don't do anything, this is handled with the "parent_id" field anyway
                    dirty = true;
                    break;
                }
            });
        }

        if (dirty) {
            me.ganttBarPanel.needsRedraw = true;					// Force a redraw
            var buttonSave = Ext.getCmp('buttonSave');
            buttonSave.setDisabled(false);						// Enable "Save" button
        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Finished');
    },

    /**
     * The user changed the planned units of a leave task.
     * We now need to re-calculate the planned units towards the
     * root of the tree.
     */
    onPlannedUnitsChanged: function(treeStore, model, operation, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onPlannedUnitsChanged: Starting');
        var parent = model.parentNode;
        if (!parent) return;

        // Calculate the sum of planned units of all nodes below parent
        var plannedUnits = 0.0;
        parent.eachChild(function(sibling) {
            var siblingPlannedUnits = parseFloat(sibling.get('planned_units'));
            if (!isNaN(siblingPlannedUnits)) {
                plannedUnits = plannedUnits + siblingPlannedUnits;
            }
        });

        // Check if we have to update the parent
        if (parseFloat(parent.get('planned_units')) != plannedUnits) {
            parent.set('planned_units', ""+plannedUnits);	                    // This will call this event recursively
        }
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onPlannedUnitsChanged: Finished');
    },


    /**
     * The start_date of a task has changed.
     * Check if this new date is before the start_date of it's parent.
     * In this case we need to adjust the parent.
     */
    onStartDateChanged: function(treeStore, model, operation, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Starting');

        // Check for manually entered date. startDates start at 00:00:00 at night:
        var myStartDate = model.get('start_date');
        if (myStartDate.length == 10) { model.set('start_date', myStartDate + " 00:00:00"); }

        var parent = model.parentNode;						// 
        if (!parent) return;
        var parent_start_date = parent.get('start_date');
        if ("" == parent_start_date) return;
        var parentStartDate = PO.Utilities.pgToDate(parent_start_date);

        // Calculate the minimum start date of all siblings
        var minStartDate = PO.Utilities.pgToDate('2099-12-31');
        parent.eachChild(function(sibling) {
            var siblingStartDate = PO.Utilities.pgToDate(sibling.get('start_date'));
            if (!isNaN(siblingStartDate) && siblingStartDate.getTime() < minStartDate.getTime()) {
                minStartDate = siblingStartDate;
            }
        });

        // Check if we have to update the parent
        if (parentStartDate.getTime() != minStartDate.getTime()) {
            // The siblings start different than the parent - update the parent.
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Updating parent at level='+parent.getDepth());
            parent.set('start_date', PO.Utilities.dateToPg(minStartDate));	// This will call this event recursively
        }

        me.checkStartEndDateConstraint(treeStore, model);			// check start < end constraint

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

        // Check for manually entered date. endDates end at 23:59:59 at night:
        var myStartDate = model.get('start_date');
        if (myStartDate.length == 10) { model.set('start_date', myStartDate + " 23:59:59"); }

        var parent = model.parentNode;
        if (!parent) return;
        var parent_end_date = parent.get('end_date');
        if ("" == parent_end_date) return;
        var parentEndDate = PO.Utilities.pgToDate(parent_end_date);

        // Calculate the maximum end date of all siblings
        var maxEndDate = PO.Utilities.pgToDate('2000-01-01');
        parent.eachChild(function(sibling) {
            var siblingEndDate = PO.Utilities.pgToDate(sibling.get('end_date'));
            if (!isNaN(siblingEndDate) && siblingEndDate.getTime() > maxEndDate.getTime()) {
                maxEndDate = siblingEndDate;
            }
        });

        // Check if we have to update the parent
        if (parentEndDate.getTime() != maxEndDate.getTime()) {
            // The siblings end different than the parent - update the parent.
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Updating parent at level='+parent.getDepth());
            parent.set('end_date', PO.Utilities.dateToPg(maxEndDate));		// This will call this event recursively
        }

        me.checkStartEndDateConstraint(treeStore, model);			// check start < end constraint

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Finished');
    },

    /**
     * Make sure endDate is after startDate
     */
    checkStartEndDateConstraint: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkStartEndDateConstraint: Starting');
        
        var startDate = PO.Utilities.pgToDate(model.get('start_date'));
        var endDate = PO.Utilities.pgToDate(model.get('end_date'));

        if (startDate && endDate) {
            var startTime = startDate.getTime();
            var endTime = endDate.getTime();
            if (startTime > endTime) {
                // The user has entered inconsistent start/end dates
                endTime = startTime + 1000 * 3600 * 24;
                endDate = new Date(endTime);
                endDateString = endDate.toISOString().substring(0,10);
                model.set('end_date', endDateString);
            }
        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkStartEndDateConstraint: Finished');
    }

});
