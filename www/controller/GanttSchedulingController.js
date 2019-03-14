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

	// Check for loops in the dependencies
	// me.checkCyclicDependencies();

        // me.suspendEvents();
        var dirty = false;
        if (null != fieldsChanged) {
            fieldsChanged.forEach(function(fieldName) {
                if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Field changed='+fieldName);
                switch (fieldName) {
                case "assignees":
                    me.onAssigneesChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
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

        // me.resumeEvents();

        if (dirty) {
            me.checkBrokenDependencies();

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

        // Check planned units vs. assigned resources
        me.checkTaskLength(treeStore, model);


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
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onPlannedUnitsChanged: Setting parent.planned_units='+plannedUnits);
            parent.set('planned_units', ""+plannedUnits);	                    // This will call this event recursively
        }
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onPlannedUnitsChanged: Finished');
    },


    /**
     * The assignees of a task has changed.
     * Check if the length of the task is still valid.
     */
    onAssigneesChanged: function(treeStore, model, operation, event) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onAssigneesChanged: Starting');

        var effortDrivenType = parseInt(model.get('effort_driven_type_id'));
        if (isNaN(effortDrivenType)) {
	    effortDrivenType = parseInt(default_effort_driven_type_id);    // Default is "Fixed Work" = 9722
	}
        if (isNaN(effortDrivenType)) effortDrivenType = 9722;    // Default is "Fixed Work" = 9722

        switch (effortDrivenType) {
        case 9720:     // Fixed Units
            me.checkTaskLength(treeStore, model);            // adjust the length of the task
            break;
        case 9721:     // Fixed Duration
            me.checkAssignedResources(treeStore, model);                 // adjust the percentage of the assigned resources
            break;
        case 9722:     // Fixed Work
            me.checkTaskLength(treeStore, model);            // adjust the length of the task
            break;
        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onAssigneesChanged: Finished');
    },


    /**
     * The assignees of a task has changed.
     * Check if the length of the task is still valid.
     */
    onCreateDependency: function(dependencyModel) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onCreateDependency: Starting');

        me.checkBrokenDependencies();

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onCreateDependency: Finished');
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
        if (myStartDate.length == 10) { 
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Adding " 00:00:00" to start_date='+myStartDate);
            model.set('start_date', myStartDate + " 00:00:00"); 
        }

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

        // Check planned units vs. assigned resources
        me.checkTaskLength(treeStore, model);

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
        var myEndDate = model.get('end_date');
        if (myEndDate.length == 10) { 
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Adding " 00:00:00" to end_date='+myEndDate);
            model.set('end_date', myEndDate + " 23:59:59"); 
        }

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
     * Check if there are dependencies in the tree which are broken.
     */
    checkBrokenDependencies: function() {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkBrokenDependencies: Starting');
        var treeStore = me.taskTreeStore;

        // Iterate through all children and draw dependencies
        var rootNode = treeStore.getRootNode();
        rootNode.cascadeBy(function(project) {
            var predecessors = project.get('predecessors');
            if (!predecessors instanceof Array) return;
            for (var i = 0, len = predecessors.length; i < len; i++) {
                var dependencyModel = predecessors[i];
                me.checkBrokenDependency(dependencyModel);
            }
        });
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkBrokenDependencies: Finished');
    },

    /**
     * Check if a dependency is broken.
     */
    checkBrokenDependency: function(dependencyModel) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkBrokenDependency: Starting');

        var treeStore = me.taskTreeStore;
        var taskModelHash = me.ganttBarPanel.taskModelHash;

        var fromId = dependencyModel.pred_id;
        var fromModel = taskModelHash[fromId];
        var toId = dependencyModel.succ_id;
        var toModel = taskModelHash[toId];

        // We can get dependencies from other projects.
        // These are not in the taskModelHash, so just skip these
        if (undefined === fromModel || undefined === toModel) { 
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkBrokenDependency: Dependency from other project: Skipping');
            return; 
        }

        var fromEndDate = fromModel.get('end_date');
        var toStartDate = toModel.get('start_date');
        var predEndDate = PO.Utilities.pgToDate(fromEndDate);
        var succStartDate = PO.Utilities.pgToDate(toStartDate);

        if ("" != fromEndDate && "" != toStartDate && predEndDate.getTime() > succStartDate.getTime()) {
            // Broken end-start constraint

            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkBrokenDependency: Setting start_date of successor: '+predEndDate);

            var endDatePG = new Date(predEndDate.getTime());
            endDatePG.setHours(0,0,0,0);
            var endTimePG = endDatePG.getTime() + 1000 * 3600 * 24;
            endDatePG = new Date(endTimePG);
            toModel.set('start_date', PO.Utilities.dateToPg(endDatePG));

        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkBrokenDependency: Finished');
    },

    /**
     * Check the planned units vs. assigned resources percentage.
     * Then follow the ResourceCalendar to calculate the new end_date
     */
    checkTaskLength: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength:: Starting');
        
        var startDate = PO.Utilities.pgToDate(model.get('start_date'));
        if (!startDate) { return; }						// No date - no duration...
        startDate.setHours(0,0,0,0);
        var endDate = PO.Utilities.pgToDate(model.get('end_date'));
        if (!endDate) { return; }						// No date - no duration...
        var assignees = model.get('assignees');
        var plannedUnits = model.get('planned_units');
        if (0 == plannedUnits) { return; }					// No units - no duration...
        if (!plannedUnits) { return; }						// No units - no duration...

        // Calculate the percent assigned in total
        var assignedPercent = 0.0
        assignees.forEach(function(assig) {
            assignedPercent = assignedPercent + assig.percent
        });
        if (0 == assignedPercent) { return; }					// No assignments - "manually scheduled" task

        // Calculate the duration of the task in hours
        var durationHours = plannedUnits * 100.0 / assignedPercent;
        
        // Adjust the time period, so that the effective hours >= durationHours
        var startTime = startDate.getTime();
        var endTime = startTime;
        var hours = 0.0;							// we start at 23:59 of the startDay...
        while (hours < durationHours) {
            var day = new Date(endTime);
            var dayOfWeek = day.getDay();
            if (dayOfWeek == 6 || dayOfWeek == 0) { 
                // Weekend - just skip the day
            } else {
                // Weekday - add hours
                hours = hours + 8;
            }
            endTime = endTime + 1000 * 3600 * 24;
        }

        endDate = new Date(endTime - 1000 * 3600 * 24);
        endDateString = PO.Utilities.dateToPg(endDate);
        endDateString = endDateString.substring(0,10) + ' 23:59:59';
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: end_date='+endDateString);
        model.set('end_date', endDateString);

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: Finished');
    },


    /**
     * Check that the assigned resources correspond to duration and planned units.
     * Then adapt assignment percentage uniformly.
     */
    checkAssignedResources: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength:: Starting');
        
        var startDate = PO.Utilities.pgToDate(model.get('start_date')); if (!startDate) return; // No date - no duration...
        startDate.setHours(0,0,0,0);
        var endDate = PO.Utilities.pgToDate(model.get('end_date')); if (!endDate) return;	// No date - no duration...
        var assignees = model.get('assignees');
        var plannedUnits = model.get('planned_units'); if (!plannedUnits || 0 == plannedUnits) return;  // No units - no duration...

        // Calculate the percent assigned in total
        var assignedPercent = 0.0
        assignees.forEach(function(assig) {
            assignedPercent = assignedPercent + assig.percent
        });
        if (0 == assignedPercent) { return; }					// No assignments - nothing to fix

        // Calculate the number of working time between start- and end-date
        var startTime = startDate.getTime();
        var endTime = endDate.getTime();
        var workHours = 0.0;							// we start at 23:59 of the startDay...
        var now = startTime;
        while (now < endTime) {
            var day = new Date(now);
            var dayOfWeek = day.getDay();
            if (dayOfWeek == 6 || dayOfWeek == 0) { 
                // Weekend - just skip the day
            } else {
                // Weekday - add hours
                workHours = workHours + 8;
            }
            now = now + 1000 * 3600 * 24;
        }

        // Calculate the total resources that need to be assigned
        var assignedPercentNew = 100.0 * plannedUnits / workHours;
        var assignmentFactor = assignedPercentNew / assignedPercent;

        // Fix each assignment by the same factor
        assignees.forEach(function(assig) {
            assig.percent = Math.round(10.0 * assig.percent * assignmentFactor) / 10.0;
        });

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: Finished');
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
                if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkStartEndDateConstraint: end_date=' + endDateString + ' - making sure end_date is after startDate');
                model.set('end_date', endDateString);
            }
        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkStartEndDateConstraint: Finished');
    },


    /**
     * Finds a node in a tree by a custom function.
     * @param {Object} node The node to start searching.
     * @param {Function} fn A function which must return true if the passed Node is the required Node.
     * @param {Object} [scope] The scope (this reference) in which the function is executed. Defaults to the Node being tested.
     * @return {Ext.data.NodeInterface} The found child or null if none was found
     */
    findNodeBy : function(node, fn, scope) {
        // Check if the result is the node itself
        var n = node;
        if (fn.call(scope || n, n) === true) { return n; }

        // Search the children
        var me = this;
        var cs = node.childNodes,
        len = cs.length,
        i = 0, res;
        
        for (; i < len; i++) {
            n = cs[i];
            res = me.findNodeBy(n, fn, scope);
            if (res !== null) { return res; }
        }        
        return null;
    },


    /**
     * Check for cyclic dependencies in the project plan.
     * First initialize transPreds and transSuccs hashes
     * of transitive predecessors and successors with the
     * direct preds/succs of the project activity.
     *
     * Then use an iterative search to find the successors
     * of successors and predecessors of preds etc.
     */
    checkCyclicDependencies: function() {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependencies: Starting');

        // Iterate through all nodes
        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();

        // Loop through all activities and create a transPreds transitive predecessors hash
        rootNode.cascadeBy(function(project) {
            var predecessors = project.get('predecessors');
            if (!predecessors instanceof Array) return;

            // Initialize with the list of direct predecessors
            for (var i = 0, len = predecessors.length; i < len; i++) {
                var dependencyModel = predecessors[i];

                var predId = ''+dependencyModel.pred_id;		// a string!
                var predModel = me.findNodeBy(rootNode, function() {return (''+this.get('id') === predId);}, null);
                if (!predModel) { alert("PredModel not found for: "+predId); }

                var succId = ''+dependencyModel.succ_id;		// a string!
                var succModel = me.findNodeBy(rootNode, function() { return (''+this.get('id') === succId);}, null);
                if (!succModel) { alert("SuccModel not found for: "+succId); }

                var transPreds = succModel.transPreds;
                if (!transPreds) {
                    transPreds = {};
                    succModel.transPreds = transPreds;
                }
                transPreds[predId] = predModel;

                var transSuccs = predModel.transSuccs;
                if (!transSuccs) {
                    transSuccs = {};
                    predModel.transSuccs = transSuccs;
                }
                transSuccs[succId] = succModel;
            }
        });


        // Calculate the transitive predecessors:
        // Loop through all activities and add the predecessors of their predecessors to the hash.
        var loopP = true;
        var cyclicLoopP = false;
        while (loopP && !cyclicLoopP) {
            loopP = false;

            // Loop throught all nodes in the tree (activities)
            rootNode.cascadeBy(function(project) {
                var projectId = ''+project.get('id');

                if ("18233" === projectId || "18234" === projectId || "18235" === projectId || "18236" === projectId || "18237" === projectId || "18238" === projectId) {
                    console.log('found');
                }

                // Loop through all predecessors of the node
                var transPreds = project.transPreds;
                for (var id in transPreds) {

                    // Now loop through the prececessors preds
                    // and add them to the project's preds
                    var predModel = transPreds[id];
                    var predPreds = predModel.transPreds;
                    for (var predPredId in predPreds) {
                        if (!transPreds[predPredId]) {		// check if the attribute already exists
                            loopP = true;			// keep on looping...
                            var predPredModel = predPreds[predPredId];
                            transPreds[predPredId] = predPredModel;
                            if (projectId === predPredId) {
                                // We've found a loop. We found the ID of the object
                                // itself in the list of it's predecessors
                                alert('Cyclic dependency with '+predPredId);
                                cyclicLoopP = true;
                            }
                        }
                    }
                }
            });
        }


        // Calculate the transitive successors:
        // Loop through all activities and add the successors of their successors
        var loopP = true;
        var cyclicLoopP = false;
        while (loopP && !cyclicLoopP) {
            loopP = false;

            // Loop throught all nodes in the tree (activities)
            rootNode.cascadeBy(function(project) {
                var projectId = ''+project.get('id');

                if ("18233" === projectId || "18234" === projectId || "18235" === projectId || "18236" === projectId || "18237" === projectId || "18238" === projectId) {
                    console.log('found');
                }

                // Loop through all succecessors of the node
                var transSuccs = project.transSuccs;
                for (var id in transSuccs) {

                    // Now loop through the successors succs
                    // and add them to the project's succs
                    var succModel = transSuccs[id];
                    var succSuccs = succModel.transSuccs;
                    for (var succSuccId in succSuccs) {
                        if (!transSuccs[succSuccId]) {		// check if the attribute already exists
                            loopP = true;			// keep on looping...
                            var succSuccModel = succSuccs[succSuccId];
                            transSuccs[succSuccId] = succSuccModel;
                            if (projectId === succSuccId) {
                                // We've found a loop. We found the ID of the object
                                // itself in the list of it's succecessors
                                alert('Cyclic dependency with '+succSuccId);
                                cyclicLoopP = true;
                            }
                        }
                    }
                }
            });
        }


        // Loop through all nodes and check for parents in the list of prececessors
        rootNode.cascadeBy(function(project) {
            var transPreds = project.transPreds;
            var transSuccs = project.transSuccs;
            var parentNode = project.parentNode;
            if (!parentNode) return;
            var parentId = ''+parentNode.get('id');
            if ("root" === parentId) return;

            // Check all predecessors if we can find a parent in it
            for (predId in transPreds) {
                if (predId === parentId) {
                    alert('Found parentId='+parentId+' in predecessors of id='+project.get('id'));
                }
            }

            // Check all successors if we can find a parent in it
            for (succId in transSuccs) {
                if (succId === parentId) {
                    alert('Found parentId='+parentId+' in succecessors of id='+project.get('id'));
                }
            }

        });

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependencies: Finished');
    }


});
