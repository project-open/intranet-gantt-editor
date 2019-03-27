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
            // me.schedule();
            // Schedule is initiated by next redraw

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

        // me.schedule();
        // schedule is initiated by next redraw()

        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onCreateDependency: Finished');
    },


    /**
     * Check the planned units vs. assigned resources percentage.
     * Then follow the ResourceCalendar to calculate the new end_date.
     *
     * Returns true if we had to modify the task, false otherwise
     */
    checkTaskLength: function(treeStore, model) {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.checkTaskLength: Starting');
        
        var previousStartDate = PO.Utilities.pgToDate(model.get('start_date')); if (!previousStartDate) { return false; }
        previousStartDate.setHours(0,0,0,0);
        var previousEndDate = PO.Utilities.pgToDate(model.get('end_date')); if (!previousEndDate) { return false; }
        var assignees = model.get('assignees');
        var plannedUnits = model.get('planned_units');
        if (0 == plannedUnits) { return false; }					// No units - no duration...
        if (!plannedUnits) { return false; }						// No units - no duration...

        // Calculate the percent assigned in total
        var assignedPercent = 0.0
        assignees.forEach(function(assig) {
            assignedPercent = assignedPercent + assig.percent
        });
        if (0 == assignedPercent) { return false; }					// No assignments - "manually scheduled" task

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
                // Weekday - add hours
                hours = hours + 8;
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
        var cyclicP = false;
        
        // Initialize directPreds, directSuccs and transParents
        cyclicP = cyclicP || me.checkCyclicDependenciesInit(fixP);

        // Check for invalid parents being part of direct preds or succs
        cyclicP = cyclicP || me.checkCyclicDependenciesParents(fixP);

        // Don't check for transitive closures, because this
        // causes an infinite loop - Check for invalid parents being part of direct preds or succs
        // cyclicP = cyclicP || me.checkCyclicDependenciesTransClosure(fixP);

        // Fix schedule constraints
        me.schedule();


        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onRedraw: Finished');
        return cyclicP;
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
        rootNode.cascadeBy(function(project) {
            project.directPreds = {};
            project.directSuccs = {};
            project.transParents = {};
            delete project.transPreds;
            delete project.transSuccs;
        });

        // --------------------------------------------------------------------------------
        // Loop through all activities and create direct preds and succs hashes
        rootNode.cascadeBy(function(project) {

            // Calculate transitive parents
            var parentModel = project.parentNode;
            while (parentModel) {
                var parentId = ''+parentModel.get('id');
                project.transParents[parentId] = parentModel;
                parentModel = parentModel.parentNode;		// Move up one level...
            }

            // Initialize with the list of direct predecessors
            var repeatP = true;
            while (repeatP) {
                repeatP = false;
                var predecessors = project.get('predecessors');
                if (!predecessors instanceof Array) return;
                for (var i = 0, len = predecessors.length; i < len; i++) {
                    var dependencyModel = predecessors[i];

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

                    succModel.directPreds[predId] = predModel;
                    predModel.directSuccs[succId] = succModel;
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
        // Loop through all activities and check direct preds and succs for being in the node's parents
        rootNode.cascadeBy(function(project) {
            var projectId = ''+project.get('id');
            for (var predId in project.directPreds) {
                if (project.transParents[predId]) {
                    // alert('found pred in partnets');
                    me.checkCyclicDependenciesDelete(fixP, predId, projectId);	    // Delete the offending dependency
                    var cyclicP = true;
                }
            }
            for (var succId in project.directSuccs) {
                if (project.transParents[succId]) {
                    // alert('found succ in partnets');
                    me.checkCyclicDependenciesDelete(fixP, projectId, succId);	    // Delete the offending dependency
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
        rootNode.cascadeBy(function(project) {
            var projectId = ''+project.get('id');
            var predecessors = project.get('predecessors');
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
                        project.set('predecessors', predecessors);		// Update project
                        console.log('PO.controller.gantt_editor.GanttSchedulingController.checkCyclicDependenciesDelete: '+
                                    'Deleting predecessor on project='+projectId+': '+predId+' -> '+succId);
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
        rootNode.cascadeBy(function(project) {
            project.transPreds = {};
            for (var pred in project.directPreds) project.transPreds[pred] = project.directPreds[pred];

            project.transSuccs = {};
            for (var succ in project.directSuccs) project.transSuccs[succ] = project.directSuccs[succ];
        });


        // Calculate the transitive predecessors:
        // Loop through all activities and add the predecessors of their predecessors to the hashes
        var loopP = true;
        while (loopP && !cyclicP) {
            loopP = false;
            rootNode.cascadeBy(function(project) {             // Loop throught all nodes in the tree (activities)
                var projectId = ''+project.get('id');
                var transPreds = project.transPreds;
                for (var id in transPreds) {
                    // Loop through the prececessors preds and add them to the project's preds
                    var predModel = transPreds[id];
                    var predPreds = predModel.transPreds;
                    for (var predPredId in predPreds) {
                        if (!transPreds[predPredId]) {		// check if the attribute already exists
                            loopP = true;			// keep on looping...
                            var predPredModel = predPreds[predPredId];
                            transPreds[predPredId] = predPredModel;
                            // Found the ID of the object in the list of it's predecessors?
                            if (projectId === predPredId) cyclicP = true;
                        }
                    }
                }
            });
        }

        // Calculate the transitive successors:
        // Loop through all activities and add the successors of their successors
        var loopP = true;
        while (loopP && !cyclicP) {
            loopP = false;
            rootNode.cascadeBy(function(project) {            // Loop throught all nodes in the tree (activities)
                var projectId = ''+project.get('id');
                var transSuccs = project.transSuccs;
                for (var id in transSuccs) {                // Loop through all succecessors of the node
                    // Loop through the successors succs and add them to the project's succs
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
                            if (projectId === succSuccId) cyclicP = true;
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
     * Get the list of all leaf activities that have no predecessors.
     * (Should we exclude non-Gantt activities like tickets or SCRUM phases?)
     */
    scheduleStartList: function() {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleStartList: Starting');
        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();

        var startActivities = [];
        rootNode.cascadeBy(function(project) {             // Loop throught all nodes in the tree (activities)
            var projectId = ''+project.get('id');
            var leafP = !project.hasChildNodes();
            var predecessors = project.get('predecessors');
            if (!predecessors instanceof Array) return;
            var projectTypeId = parseInt(project.get('project_type_id'));
            var taskP = (projectTypeId == 100 || projectTypeId == 2501);	// Task or GanttProject

                startActivities.push(project);
            if (taskP && leafP && 0 == predecessors.length) {
            }
        });

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleStartList: Finished');
        return startActivities;
    },



    /**
     * Check the planned units vs. assigned resources percentage.
     * Then follow the ResourceCalendar to calculate the new end_date.
     *
     * Returns true if we had to modify the task, false otherwise
     */
    scheduleTaskDuration: function(treeStore, model) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskDuration: Starting');
        if (model.hasChildNodes()) { alert('scheduleTaskDuration: Called with summary task'); return; }

        var previousStartDate = PO.Utilities.pgToDate(model.get('start_date')); if (!previousStartDate) { return false; }
        previousStartDate.setHours(0,0,0,0);
        var previousEndDate = PO.Utilities.pgToDate(model.get('end_date')); if (!previousEndDate) { return false; }
        var assignees = model.get('assignees');
        var plannedUnits = model.get('planned_units');
        if (0 == plannedUnits) { return false; }					// No units - no duration...
        if (!plannedUnits) { return false; }						// No units - no duration...

        // Calculate the percent assigned in total
        var assignedPercent = 0.0
        assignees.forEach(function(assig) {
            assignedPercent = assignedPercent + assig.percent
        });
        if (0 == assignedPercent) { return false; }					// No assignments - "manually scheduled" task

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
                // Weekday - add hours
                hours = hours + 8;
            }
            endTime = endTime + 1000 * 3600 * 24;
        }
        endTime = endTime - 1000 * 3600 * 24;						// ]po[ sematics: zero time => 1 day

        if (endTime == previousEndTime) return false;					// skip if no change

        // Write the new endDate into model
        endDate = new Date(endTime);
        endDateString = PO.Utilities.dateToPg(endDate);
        endDateString = endDateString.substring(0,10) + ' 23:59:59';
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskDuration: end_date='+endDateString);
        model.set('end_date', endDateString);

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskDuration: Finished');
        return true;
    },


    /**
     * Make sure task or summary is moved correctly after a pred.
     */
    scheduleAfter: function(treeStore, pred, succ) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleAfter: Starting');

	var changedP = false;
	if (succ.hasChildren()) {
	    changedP = scheduleSummaryAfter(treeStore, pred, succ);
	} else {
	    changedP = scheduleTaskAfter(treeStore, pred, succ);
	}

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleAfter: Finished');
        return changedP;
    },


    /**
     * Check that node is after the pred.
     * Otherwise set the start_date of node to the end_date of pred.
     */
    scheduleTaskAfter: function(treeStore, pred, succ) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskAfter: Starting');

        var predStartDate = PO.Utilities.pgToDate(pred.get('start_date')); if (!predStartDate) { return false; }
        var predEndDate = PO.Utilities.pgToDate(pred.get('end_date'));  if (!predEndDate) { return false; }
        var succStartDate = PO.Utilities.pgToDate(succ.get('start_date')); if (!succStartDate) { return false; }
        var succEndDate = PO.Utilities.pgToDate(succ.get('end_date')); if (!succEndDate) { return false; }

        // If the start of succ is before the end of pred...
        var changedP = false;
        var diff = predEndDate.getTime() - succStartDate.getTime();			// start of succ earlier than end of pred
        if (diff > 0) {
            var newStartDate = new Date(succStartDate.getTime() + diff);		// Add diff to the start and end of succ
            var newEndDate = new Date(succEndDate.getTime() + diff);

            // Write the new dates to succ
            var startDateString = PO.Utilities.dateToPg(newStartDate);
            var endDateString = PO.Utilities.dateToPg(newEndDate);
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskAfter: start_date='+startDateString+', end_date='+endDateString);
            succ.set('start_date', startDateString);
            succ.set('end_date', endDateString);
            var changedP = true
        }

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskAfter: Finished');
        return changedP;
    },


    /**
     * Check that summary.start_date is after pred.end_date
     */
    scheduleSummaryAfter: function(treeStore, pred, succSummary) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskAfter: Starting');

        var predEndDate = PO.Utilities.pgToDate(pred.get('end_date'));  if (!predEndDate) { return false; }
        var succSummaryStartDate = PO.Utilities.pgToDate(succSummary.get('start_date')); if (!succSummaryStartDate) { return false; }

        var changedP = false;
        var diff = predEndDate.getTime() - succSummaryStartDate.getTime();
        if (diff > 0) {
            var newStartDate = new Date(succSummaryStartDate.getTime() + diff);
            // don't move the succSummary.end_date. That's done by it's sub-tasks.

            // Write the new dates to succSummary
            var startDateString = PO.Utilities.dateToPg(newStartDate);
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskAfter: start_date='+startDateString);
            succSummary.set('start_date', startDateString);
            var changedP = true
        }

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleTaskAfter: Finished');
        return changedP;
    },


    /**
     * Check that all children of a summary task start after the summary's start_date
     */
    scheduleChildAfterSummaryStartDate: function(treeStore, summary, child) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleChildAfterSummaryStartDate: Starting');

        var summaryStartDate = PO.Utilities.pgToDate(summary.get('start_date')); if (!summaryStartDate) { return false; }
        var childStartDate = PO.Utilities.pgToDate(child.get('start_date')); if (!childStartDate) { return false; }
        var childEndDate = PO.Utilities.pgToDate(child.get('end_date')); if (!childEndDate) { return false; }

        // If the start of child is before the end of summary...
        var changedP = false;
        var diff = summaryStartDate.getTime() - childStartDate.getTime();			// start of child earlier than end of summary
        if (diff > 0) {
            var newStartDate = new Date(childStartDate.getTime() + diff);		// Add diff to the start and end of child
            var newEndDate = new Date(childEndDate.getTime() + diff);

            // Write the new dates to child
            var startDateString = PO.Utilities.dateToPg(newStartDate);
            var endDateString = PO.Utilities.dateToPg(newEndDate);
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleChildAfterSummaryStartDate: start_date='+startDateString+', end_date='+endDateString);
            child.set('start_date', startDateString);
            child.set('end_date', endDateString);
            var changedP = true
        }

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleChildAfterSummaryStartDate: Finished');
        return changedP;
    },


    /**
     * Make sure the end_date of a summary task is after the last child.
     */
    scheduleSummaryTaskEndAfterChild: function(treeStore, pred, summary) {
        var me = this;
        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleSummaryTaskEndAfterChild: Starting');

        var predEndDate = PO.Utilities.pgToDate(pred.get('end_date')); if (!predEndDate) { return false; }
        var summaryEndDate = PO.Utilities.pgToDate(summary.get('end_date')); if (!summaryEndDate) { return false; }

        // If the start of node is before the end of pred...
        var changedP = false;
        var diff = predEndDate.getTime() - summaryEndDate.getTime();			// start of node earlier than end of pred
        if (diff > 0) {
            var newEndDate = predEndDate;
            var endDateString = PO.Utilities.dateToPg(newEndDate);
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleSummaryTaskEndAfterChild: '+
                        'end_date='+endDateString);
            summary.set('end_date', endDateString);
            changedP = true;
        }

        if (me.debug > 1) console.log('PO.controller.gantt_editor.GanttSchedulingController.scheduleSummaryTaskEndAfterChild: Finished');
        return changedP;
    },

    /**
     * Fix constraints in the schedule
     *
     * - Activities with work and assignees set need to have matching
     *   duration and assignments.
     * - Parents start and end with their first and last task respectively
     * - Activities with a predecessors start after the end of the predecessor
     *
     * Constraints:
     * Instead of "scheduling", we really just check that no constraints
     * are broken and adjust the network:
     * - Finish-End relationships between activities of various levels
     * - Summary vs. sub-task. 
     * - !! what about dependency from sub-task to summary=?
     *
     * Algorithm:
     * - Start off with a list of unconstraint leaf activities
     * - Iterate through the list and follow the direct successors of each task:
     *     - !!
     */
    schedule: function() {
        var me = this;
        if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.schedule: Starting');
        var startTime = new Date().getTime();

        // Initialize cyclic dependencies
        me.checkCyclicDependenciesInit();

        var treeStore = me.taskTreeStore;
        var rootNode = treeStore.getRootNode();
        me.suspendEvents(false);
        treeStore.suspendEvents(false);

        // Get the list of all leaf activities that have no predecessors
        var nodes = me.scheduleStartList();
        console.log(nodes);

        // Iterate through all nodes until we reach the end of successor chains
        var iterationCount = 0;
        while (nodes.length > 0 && iterationCount < 100) {
            iterationCount++;
            var nodeModel = nodes.shift();					// Get and remove the first element from stack
            var nodeId = ''+nodeModel.get('id');
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.schedule: '+
                'Iteration='+iterationCount+': Checking id='+nodeId+', name='+nodeModel.get('project_name'));

            // --------------------------------------------------------
            // Perform basic checks on the new node
            //
            var changedP = false;
            if (!nodeModel.hasChildNodes()) {
                // A leaf "basic" task
                // Check for formula: Duration = Work / Assignments
                changedP = me.scheduleTaskDuration(treeStore, nodeModel);		// adjust the length of the task
                
            } else {
                // A summary task with children
                // Summary activities don't need to be checked for duration...
                // However, we need to make sure that all child.start_date are after the start of the summary task
                nodeModel.cascadeBy(function(child) {				// Loop throught all children
                    // Move child after node.start_date
                    var childChangedP = me.scheduleChildAfterSummaryStartDate(treeStore, nodeModel, child);
                    if (childChangedP) 
                        nodes.push(child);				// check all children
                });
            }

            // --------------------------------------------------------
            // Ensure the end-date of parent summary tasks
            // Only execute if changedP?
            var parentModel = nodeModel.parentNode;
            while (parentModel) {
                // Make sure summary end_date after child end_date
                var changedP = me.scheduleSummaryTaskEndAfterChild(treeStore, nodeModel, parentModel);
                if (changedP) 
                    nodes.push(parentModel);
                parentModel = parentModel.parentNode;		// Move up one level...
            }
            
            // --------------------------------------------------------
            // Loop through all direct successors
            var directSuccs = nodeModel.directSuccs;
            for (var succId in directSuccs) {
                var succModel = directSuccs[succId];

                if (!succModel.hasChildNodes()) {				// Check if this is a summary task
                    // This is a leaf task
                    changedP = me.scheduleTaskAfter(treeStore, nodeModel, succModel);	// make sure succModel is after nodeModel
                    if (changedP) 
                        nodes.push(succModel);			// continue scheduling with this task
                } else {
                    // This is a summary task
                    succModel.cascadeBy(function(succChildModel) {		// Loop throught all children
                        changedP = me.scheduleSummaryAfter(treeStore, nodeModel, succChildModel); // make sure succModel is after nodeModel
                        if (changedP) {
			    me.scheduleAfter(treeStore, nodeModel, succModel);
                            nodes.push(succChildModel);		// continue scheduling with this task
			}
                    });
                }
            }

            // me.ganttBarPanel.undrawProjectBar(nodeModel);
            // me.ganttBarPanel.drawProjectBar(nodeModel);

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
