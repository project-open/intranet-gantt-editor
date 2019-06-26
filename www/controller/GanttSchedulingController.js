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

        // Tell the GanttBarPanel about this controller
        me.ganttBarPanel.ganttSchedulingController = me;

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

        me.suspendEvents(false);
        treeStore.suspendEvents(false);
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
                    dirty = true;
                    break;
                case "end_date":
                    dirty = true;
                    break;
                case "planned_units":
                    me.onPlannedUnitsChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
                case "billable_units":
                    me.onBillableUnitsChanged(treeStore, model, operation, event);
                    dirty = true;
                    break;
                case "parent_id":
                    // Task has new parent - indentation or un-indentation
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
        treeStore.resumeEvents();
        me.resumeEvents();

        if (dirty) {
            me.ganttBarPanel.needsRedraw = true;					// Force a redraw

            var buttonSave = Ext.getCmp('buttonSave');
            buttonSave.setDisabled(false);						// Enable "Save" button
        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Finished');
    },

    /**
     * The user changed the planned units of an task.
     * We now need to re-calculate the planned units towards the
     * root of the tree.
     */
    onPlannedUnitsChanged: function(treeStore, model) {
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
            parent.set('planned_units', ""+plannedUnits);

            // We now need to call onPlannedUnitsChanged recursively
            // because we have disabled the events on the tree store
            me.onPlannedUnitsChanged(treeStore, parent);

        }
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onPlannedUnitsChanged: Finished');
    },


    /**
     * The user changed the billable units of an task.
     * We now need to re-calculate the billable units towards the
     * root of the tree.
     */
    onBillableUnitsChanged: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onBillableUnitsChanged: Starting');

        var parent = model.parentNode;
        if (!parent) return;

        // Calculate the sum of billable units of all nodes below parent
        var billableUnits = 0.0;
        parent.eachChild(function(sibling) {
            var siblingBillableUnits = parseFloat(sibling.get('billable_units'));
            if (!isNaN(siblingBillableUnits)) {
                billableUnits = billableUnits + siblingBillableUnits;
            }
        });

        // Check if we have to update the parent
        if (parseFloat(parent.get('billable_units')) != billableUnits) {
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onBillableUnitsChanged: Setting parent.billable_units='+billableUnits);
            parent.set('billable_units', ""+billableUnits);

            // We now need to call onBillableUnitsChanged recursively
            // because we have disabled the events on the tree store
            me.onBillableUnitsChanged(treeStore, parent);

        }
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onBillableUnitsChanged: Finished');
    },


    /**
     * The assignees of a task has changed.
     * Check if the length of the task is still valid.
     *
     * Returns true if we changed the model, false otherwise
     */
    onAssigneesChanged: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onAssigneesChanged: Starting');
        var result = false;

        var effortDrivenType = parseInt(model.get('effort_driven_type_id'));
        if (isNaN(effortDrivenType)) {
            effortDrivenType = parseInt(default_effort_driven_type_id);    // Default is "Fixed Work" = 9722
        }
        if (isNaN(effortDrivenType)) effortDrivenType = 9722;    // Default is "Fixed Work" = 9722

        switch (effortDrivenType) {
        case 9720:     // Fixed Units
            result = me.checkTaskLength(treeStore, model);            // adjust the length of the task
            break;
        case 9721:     // Fixed Duration
            result = me.checkAssignedResources(treeStore, model);                 // adjust the percentage of the assigned resources
            break;
        case 9722:     // Fixed Work
            result = me.checkTaskLength(treeStore, model);            // adjust the length of the task
            break;
        }

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onAssigneesChanged: Finished');
        return result;
    },


    /**
     * The assignees of a task has changed.
     * Check if the length of the task is still valid.
     */
    onCreateDependency: function(dependencyModel) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onCreateDependency: Starting');

        // sched initiated by next redraw()

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onCreateDependency: Finished');
    },


    /**
     * Check the planned units vs. assigned resources percentage.
     * Then follow the ResourceCalendar to calculate the new end_date.
     *
     * This function should only be called after changing work, 
     * assignments or duration of the task, not as part of the
     * sched.
     *
     * Returns true if we had to modify the task, false otherwise
     */
    checkTaskLength: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: Starting');
        
        var previousStartDate = PO.Utilities.pgToDate(model.get('start_date')); if (!previousStartDate) { return false; }
        previousStartDate.setHours(0,0,0,0);
        var previousEndDate = PO.Utilities.pgToDate(model.get('end_date')); if (!previousEndDate) { return false; }
        var previousEndTime = previousEndDate.getTime();
        var assignees = model.get('assignees');
        var plannedUnits = model.get('planned_units');
        if (0 == plannedUnits) { return false; }					// No units - no duration...
        if (!plannedUnits) { return false; }						// No units - no duration...

        // Calculate the percent assigned in total
        var assignedPercent = 0.0
        assignees.forEach(function(assig) {
            assignedPercent = assignedPercent + assig.percent
        });
        if (0 == assignedPercent) { return false; }					// No assignments - "manually sched" task

        var durationHours = plannedUnits * 100.0 / assignedPercent;			// Calculate the duration of the task in hours
        
        // Adjust the time period, so that the effective hours >= durationHours
        var startTime = previousStartDate.getTime();
        var endTime = startTime;
        var hours = 0.0;								// we start at 23:59 of the startDay...
        while (hours < durationHours) {
            var day = new Date(endTime);
            var dayOfWeek = day.getDay();
            if (dayOfWeek == 6 || dayOfWeek == 0) { 
                // Weekend - just skip the day
            } else {
                hours = hours + 8;							// Weekday - add hours
            }
            endTime = endTime + 1000 * 3600 * 24;
        }
        endTime = endTime - 1000 * 3600 * 24;						// ]po[ sematics: zero time => 1 day

        if (endTime == previousEndTime) return false;					// skip if no change

        // Write the new endDate into model
        endDate = new Date(endTime);
        endDateString = PO.Utilities.dateToPg(endDate);
        endDateString = endDateString.substring(0,10) + ' 23:59:59';
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: end_date='+endDateString);
        model.set('end_date', endDateString);

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: Finished');
        return true;
    },


    /**
     * Check that the assigned resources correspond to duration and planned units.
     * Then adapt assignment percentage uniformly.
     */
    checkAssignedResources: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkAssignedResources: Starting');
        
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

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkAssignedResources: Finished');
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
     * Called by GanttTreePanel.redraw() before performing a redraw.
     * Allows us to check the tree structure for sanity.
     */
    onRedraw: function(ganttBarPanel) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onRedraw: Starting');

        var fixP = true;				// Yes, fix any issue
        me.checkCyclicDependenciesInit(fixP);		// Initialize directPreds, directSuccs and transParents
        me.checkCyclicDependenciesParents(fixP);	// Check for invalid parents being part of direct preds or succs
        me.schedule();					// Fix schedule constraints

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onRedraw: Finished');
    },


    /* **************************************************************************************
        Check Cyclic Dependencies
    ************************************************************************************** */

    /**
     * Initialize data structures for cyclic dependency check of the project plan.
     *
     * This function initializes direct successors and predecessors
     * data-structures needed for checking for cyclic dependencies
     * plus calculate the transitive parents.
     * <ul>
     * <li>directSuccs: direct successors
     * <li>directPred: direct predecessors
     * <li>transParents: transitive parents
     * </ul>.
     */
    checkCyclicDependenciesInit: function(fixP) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesInit: Starting');

        // Iterate through all nodes
        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();

        // --------------------------------------------------------------------------------
        // Initialize entire tree data-structures
        rootNode.cascadeBy(function(task) {
            task.directPreds = {};
            task.directSuccs = {};
            task.transParents = {};
            delete task.transPreds;
            delete task.transSuccs;
        });

        // --------------------------------------------------------------------------------
        // Loop through all tasks and create direct preds and succs hashes
        rootNode.cascadeBy(function(task) {

            // Calculate transitive parents
            var parentModel = task.parentNode;
            while (parentModel) {
                var parentId = ''+parentModel.get('id');
                task.transParents[parentId] = parentModel;
                parentModel = parentModel.parentNode;		// Move up one level...
            }

            // Initialize with the list of direct predecessors
            var repeatP = true;
            while (repeatP) {
                repeatP = false;
                var predecessors = task.get('predecessors');
                if (!predecessors instanceof Array) return;
                for (var i = 0, len = predecessors.length; i < len; i++) {
                    var dependencyModel = predecessors[i];

                    var dependencyTypeId = dependencyModel.type_id;		// an integer!

                    var predId = ''+dependencyModel.pred_id;		// a string!
                    var predModel = me.findNodeBy(rootNode, function() {return (''+this.get('id') === predId);}, null);
                    if (!predModel) { 
                        alert("PredModel not found for: "+predId); 
                    }

                    var succId = ''+dependencyModel.succ_id;		// a string!
                    var succModel = me.findNodeBy(rootNode, function() { return (''+this.get('id') === succId);}, null);
                    if (!succModel) { 
                        alert("SuccModel not found for: "+succId); 
                    }

                    succModel.directPreds[predId] = {predModel: predModel, depModel: dependencyModel};
                    predModel.directSuccs[succId] = {succModel: succModel, depModel: dependencyModel};
                }
            }
        });

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesInit: Finished');
        return false;
    },

    /**
     * Check for parents being in the direct preds or succs.
     * Returns true if it finds violating parents and deletes them.
     */
    checkCyclicDependenciesParents: function(fixP) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesParents: Starting');
        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();
        var cyclicP = false;

        // --------------------------------------------------------------------------------
        // Loop through all tasks and check direct preds and succs for being in the node's parents
        rootNode.cascadeBy(function(task) {
            var taskId = ''+task.get('id');
            for (var predId in task.directPreds) {
                if (task.transParents[predId]) {
                    // alert('found pred in partnets');
                    me.checkCyclicDependenciesDelete(fixP, predId, taskId);	    // Delete the offending dependency
                    var cyclicP = true;
                }
            }
            for (var succId in task.directSuccs) {
                if (task.transParents[succId]) {
                    // alert('found succ in partnets');
                    me.checkCyclicDependenciesDelete(fixP, taskId, succId);	    // Delete the offending dependency
                    var cyclicP = true;
                }
            }
        });

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesParents: Finished');
        return cyclicP;
    },

    /**
     * Delete a pred-succ relationship anywhere in the project hierarchy.
     *
     */
    checkCyclicDependenciesDelete: function(fixP, predId, succId) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesDelete: Starting');

        if (!fixP) return false;

        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();

        // --------------------------------------------------------------------------------
        // Search for dependencies from predId to succId and delete
        rootNode.cascadeBy(function(task) {
            var taskId = ''+task.get('id');
            var predecessors = task.get('predecessors');
            if (!predecessors instanceof Array) return;

            var repeatP = true;
            while (repeatP) {
                repeatP = false;
                for (var i = 0, len = predecessors.length; i < len; i++) {
                    var dependencyModel = predecessors[i];
                    var pred_id = ''+dependencyModel.pred_id;
                    var succ_id = ''+dependencyModel.succ_id;
                    if (''+predId === ''+pred_id && ''+succId === ''+succ_id) {
                        predecessors.splice(i,1);				// Remove dependency
                        task.set('predecessors', predecessors);		// Update task
                        console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesDelete: '+
                                    'Deleting predecessor on task='+taskId+': '+predId+' -> '+succId);
                        repeatP = true;
                        break;
                    }
                }
            }
        });

        // --------------------------------------------------------------------------------
        // Delete from direct and trans preds and succs
        var predModel = me.findNodeBy(rootNode, function() {return (''+this.get('id') === ''+predId);}, null);
        if (!predModel) { 
            alert("PredModel not found for: "+predId); 
            return;
        }
        
        var succModel = me.findNodeBy(rootNode, function() { return (''+this.get('id') === ''+succId);}, null);
        if (!succModel) { 
            alert("SuccModel not found for: "+succId); 
            return;
        }

        delete predModel.directSuccs[succId];
        if (predModel.transSuccs) delete predModel.transSuccs[succId];
        delete succModel.directPreds[predId];
        if (succModel.transPreds) delete succModel.transPreds[predId];

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesDelete: Finished');
        return false;
    },


    /**
     * Calculate transitive preds and succs and check for
     * cyclic loops in dependencies.
     *
     * Expects the transPreds and transSuccs to be initialized
     * with direct succs/preds.
     */
    checkCyclicDependenciesTransClosure: function(fixP) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesTransClosure: Starting');
        var cyclicP = false;
        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();

        // --------------------------------------------------------------------------------
        // Copy the direct preds/succs to the transitive preds/succs data structures
        rootNode.cascadeBy(function(task) {
            task.transPreds = {};
            for (var predId in task.directPreds) 
                task.transPreds[predId] = task.directPreds[predId];

            task.transSuccs = {};
            for (var succId in task.directSuccs) 
                task.transSuccs[succId] = task.directSuccs[succId];
        });


        // Calculate the transitive predecessors:
        // Loop through all tasks and add the predecessors of their predecessors to the hashes
        var loopP = true;
        while (loopP && !cyclicP) {
            loopP = false;
            rootNode.cascadeBy(function(task) {             // Loop throught all nodes in the tree (tasks)
                var taskId = ''+task.get('id');
                var transPreds = task.transPreds;
                for (var id in transPreds) {
                    // Loop through the prececessors preds and add them to the task's preds
                    var predModel = transPreds[id];
                    var predPreds = predModel.transPreds;
                    for (var predPredId in predPreds) {
                        if (!transPreds[predPredId]) {		// check if the attribute already exists
                            loopP = true;			// keep on looping...
                            var predPredModel = predPreds[predPredId];
                            transPreds[predPredId] = predPredModel;
                            // Found the ID of the object in the list of it's predecessors?
                            if (taskId === predPredId) cyclicP = true;
                        }
                    }
                }
            });
        }

        // Calculate the transitive successors:
        // Loop through all tasks and add the successors of their successors
        var loopP = true;
        while (loopP && !cyclicP) {
            loopP = false;
            rootNode.cascadeBy(function(task) {            // Loop throught all nodes in the tree (tasks)
                var taskId = ''+task.get('id');
                var transSuccs = task.transSuccs;
                for (var id in transSuccs) {                // Loop through all succecessors of the node
                    // Loop through the successors succs and add them to the task's succs
                    var succModel = transSuccs[id];
                    if (!succModel) {
                        alert('checkCyclicDependenciesTransClosure: succModel not found for Id='+id);
                        return;                                 // This happens when linking to a summary task
                    }

                    var succSuccs = succModel.transSuccs;
                    for (var succSuccId in succSuccs) {
                        if (!transSuccs[succSuccId]) {		// check if the attribute already exists
                            loopP = true;			// keep on looping...
                            var succSuccModel = succSuccs[succSuccId];
                            transSuccs[succSuccId] = succSuccModel;
                            // Found the ID of the object in the list of it's succecessors?
                            if (taskId === succSuccId) cyclicP = true;
                        }
                    }
                }
            });
        }
        
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesTransClosure: Finished');
        return cyclicP;
    },

    /**
     * Check for cyclic dependencies in the project plan.
     * First initialize transPreds and transSuccs hashes
     * of transitive predecessors and successors with the
     * direct preds/succs of the project task.
     *
     * Then use an iterative search to find the successors
     * of successors and predecessors of preds etc.
     */
    checkCyclicDependencies: function(fixP) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependencies: Starting');
        var startTime = new Date().getTime();
        var cyclicP = false;
        
        // Initialize transPreds, transSuccs and transParents
        cyclicP = cyclicP || me.checkCyclicDependenciesInit(fixP);

        // Check for invalid parents being part of direct preds or succs
        cyclicP = cyclicP || me.checkCyclicDependenciesParents(fixP);

        // Check for invalid parents being part of direct preds or succs
        cyclicP = cyclicP || me.checkCyclicDependenciesTransClosure(fixP);

        var endTime = new Date().getTime();
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependencies: Finished in '+(endTime-startTime));
        return cyclicP;
    },


    /* **************************************************************************************

        Scheduling

    ************************************************************************************** */


    /**
     * Check the planned units vs. assigned resources percentage.
     * Then follow the ResourceCalendar to calculate the new end_date.
     *
     * Returns an array of changed nodes.
     */
    scheduleTaskDuration: function(treeStore, model) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskDuration: Starting');
        if (model.hasChildNodes()) { return []; }

        var previousStartDate = PO.Utilities.pgToDate(model.get('start_date')); if (!previousStartDate) { return []; }
        previousStartDate.setHours(0,0,0,0);
        var previousEndDate = PO.Utilities.pgToDate(model.get('end_date')); if (!previousEndDate) { return []; }
        var previousEndTime = previousEndDate.getTime();
        var assignees = model.get('assignees');
        var plannedUnits = model.get('planned_units');
        if (0 == plannedUnits) { return []; }					// No units - no duration...
        if (!plannedUnits) { return []; }						// No units - no duration...

        // Calculate the percent assigned in total
        var assignedPercent = 0.0
        assignees.forEach(function(assig) {
            assignedPercent = assignedPercent + assig.percent
        });
        if (0 == assignedPercent) { return []; }					// No assignments - "manually scheduled" task

        var durationHours = plannedUnits * 100.0 / assignedPercent;			// Calculate the duration of the task in hours
        
        // Adjust the time period, so that the effective hours >= durationHours
        var startTime = previousStartDate.getTime();
        var endTime = startTime;
        var hours = 0.0;								// we start at 23:59 of the startDay...
        while (hours < durationHours) {
            var day = new Date(endTime);
            var dayOfWeek = day.getDay();
            if (dayOfWeek == 6 || dayOfWeek == 0) { 
                // Weekend - just skip the day
            } else {
                hours = hours + 8;							// Weekday - add hours
            }
            endTime = endTime + 1000 * 3600 * 24;
        }
        endTime = endTime - 1000 * 3600 * 24;						// ]po[ sematics: zero time => 1 day

        if (endTime == previousEndTime) return [];					// skip if no change

        // Write the new endDate into model
        endDate = new Date(endTime);
        endDateString = PO.Utilities.dateToPg(endDate);
        endDateString = endDateString.substring(0,10) + ' 23:59:59';
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskDuration: end_date='+endDateString);
        model.set('end_date', endDateString);

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskDuration: Finished');
        return [model];
    },

    /**
     * Check that the dependency constraint "dep" is met with pred and succ.
     * Otherwise shift the start_date of succ.
     *
     * Returns an array of changed nodes.
     */
    scheduleTaskToTask: function(treeStore, pred, succ, dep) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskToTask: Starting');

        var predStartDate = PO.Utilities.pgToDate(pred.get('start_date')); if (!predStartDate) { return false; }
        var predEndDate = PO.Utilities.pgToDate(pred.get('end_date'));  if (!predEndDate) { return false; }
        var succStartDate = PO.Utilities.pgToDate(succ.get('start_date')); if (!succStartDate) { return false; }
        var succEndDate = PO.Utilities.pgToDate(succ.get('end_date')); if (!succEndDate) { return false; }

        var dependencyTypeId = dep.type_id;			       	  		// 9660=FF, 9662=FS, 9664=SF, 9666=SS 

        // If the start of succ is before the end of pred...
        var changedNodes = [];

        switch (dependencyTypeId) {
        case 9660:	// Finish-to-Finish
            var diff = predEndDate.getTime() - succEndDate.getTime();
            break;
        case 9662:	// Finish-to-Start
            var diff = predEndDate.getTime() - succStartDate.getTime();
            break;
        case 9664:	// Start-to-Finish
            var diff = predStartDate.getTime() - succEndDate.getTime();
            break;
        case 9666:	// Start-to-Start
            var diff = predStartDate.getTime() - succStartDate.getTime();
            break;
        default:
            alert('scheduleTaskToTask: found dependencyTypeId='+dependencyTypeId+': undefined dependency type');
            return;
        }

        if (diff > 0) {
            // Round the diff to the next hour and check if the difference is max. 1 minute
            var diffRoundedByHour = Math.round(diff / (3600.0 * 1000.0)) * (3600.0 * 1000.0);
            if (Math.abs(diff - diffRoundedByHour) <= 60.0 * 1000.0) {
                diff = diffRoundedByHour;						// The difference is less then a minute
            }

            var newSuccStartDate = new Date(succStartDate.getTime() + diff);		// Add diff to the start and end of succ
            var newSuccEndDate = new Date(succEndDate.getTime() + diff);

            // Write the new dates to succ
            var startDateString = PO.Utilities.dateToPg(newSuccStartDate);
            var endDateString = PO.Utilities.dateToPg(newSuccEndDate);
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskToTask: start_date='+startDateString+', end_date='+endDateString);
            succ.set('start_date', startDateString);
            succ.set('end_date', endDateString);
            changedNodes.push(succ);
        }

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskToTask: Finished');
        return changedNodes;
    },



    /**
     * Make sure a task or summary is moved correctly after a pred task or summary.
     *
     * Returns an array of changed nodes.
     */
    scheduleXToY: function(treeStore, pred, succ, dep) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleAfter: Starting');

        var changedNodes = [];
        pred.cascadeBy(function(predChild) {
            if (predChild.hasChildNodes()) return;				// only relation between leaf tasks
            succ.cascadeBy(function(succChild) {
                if (succChild.hasChildNodes()) return;				// only relation between leaf tasks
                var nodes = me.scheduleTaskToTask(treeStore, predChild, succChild, dep);
                for (var i = 0; i < nodes.length; i++) changedNodes.push(nodes[i]);

            });
        });

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleAfter: Finished');
        return changedNodes;
    },

    /**
     * Fix constraints in the schedule
     *
     * - Tasks with work and assignees need to have matching duration.
     * - Parents start and end with their first and last task respectively
     * - Tasks with a predecessors start after the end of the predecessor,
     *   if the dependency is end-to-start. Otherwise we ignore the dependency.
     *
     * Constraints:
     * Instead of "scheduling", we really just check that no constraints
     * are broken and adjust the network:
     * - Finish-to-End relationships between tasks of various levels
     * - Summary vs. sub-task. 
     * - what about dependency from sub-task to summary=?
     *
     */
    schedule: function() {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.schedule: Starting');
        var startTime = new Date().getTime();

        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();
        me.suspendEvents(false);
        treeStore.suspendEvents(false);

        // Initialize with the list of all tasks in the tree
        var changedNodes = [];
        rootNode.cascadeBy(function(task) { changedNodes.push(task); });

        // Iterate through all nodes until we reach the end of successor chains
        var iterationCount = 0;
        while (changedNodes.length > 0) {
            iterationCount++;
            var changedNode = changedNodes.shift();					// Get and remove the first element from stack
            var nodeId = ''+changedNode.get('id');
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.schedule: '+
                'Iteration='+iterationCount+': Checking id='+nodeId+', name='+changedNode.get('project_name'));

            // Perform basic check on the new node
            me.scheduleTaskDuration(treeStore, changedNode);		// adjust the length of the task

            // Loop through all direct successors
            var directSuccs = changedNode.directSuccs;
            for (var succId in directSuccs) {
                var succModel = directSuccs[succId].succModel;
                var depModel = directSuccs[succId].depModel;
                nodes = me.scheduleXToY(treeStore, changedNode, succModel, depModel);
                for (var i = 0; i < nodes.length; i++) changedNodes.push(nodes[i]);
            }
        }

        // Move summary.start_date and summary.end_date to fit children.
        // This is necessary because the algorithm above only checks for hard constraints.
        rootNode.cascadeBy(function(summary) {				// Loop throught all children
            if (!summary.hasChildNodes()) return;			// Skip if not a summary
            var summaryStartDate = PO.Utilities.pgToDate(summary.get('start_date')); if (!summaryStartDate) { return false; }
            var summaryStartTime = summaryStartDate.getTime();
            var summaryEndDate = PO.Utilities.pgToDate(summary.get('end_date')); if (!summaryEndDate) { return false; }
            var summaryEndTime = summaryEndDate.getTime();
            
            var minChildStartTime = new Date('2099-12-31').getTime();	// Initiate with maximum values
            var maxChildEndTime = new Date('2000-01-01').getTime();
            summary.cascadeBy(function(child) {
                if (child.get('id') == summary.get('id')) return;	// Skip if it's the same object

                var childStartDate = PO.Utilities.pgToDate(child.get('start_date')); if (!childStartDate) { return false; }
                var childStartTime = childStartDate.getTime();
                if (childStartTime < minChildStartTime) minChildStartTime = childStartTime;

                var childEndDate = PO.Utilities.pgToDate(child.get('end_date')); if (!childEndDate) { return false; }
                var childEndTime = childEndDate.getTime();
                if (childEndTime > maxChildEndTime) maxChildEndTime = childEndTime;
            });

            if (minChildStartTime != summaryStartTime) {		// Update summary to fit children
                var summary_start_date = PO.Utilities.dateToPg(new Date(minChildStartTime));
                summary.set('start_date', summary_start_date);
            }

            if (maxChildEndTime != summaryEndTime) {		// Update summary to fit children
                var summary_end_date = PO.Utilities.dateToPg(new Date(maxChildEndTime));
                summary.set('end_date', summary_end_date);
            }
        });

        treeStore.resumeEvents();
        me.resumeEvents();

        var endTime = new Date().getTime();
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.schedule: '+
                        'Finished in '+(endTime-startTime));
    }

});
