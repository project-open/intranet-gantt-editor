/*
 * GanttBarPanel.js
 *
 * Copyright (c) 2011 - 2015 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/**
 * Gantt panel for GanttEditor, displaying the list of 
 * Gantt task of a single project.
 * Relies on GanttTreePanel for the Y position of the Gantt bars.
 */
Ext.define('GanttEditor.view.GanttBarPanel', {
    extend: 'PO.view.gantt.AbstractGanttPanel',
    requires: [
        'PO.view.gantt.AbstractGanttPanel',
        'Ext.draw.Component',
        'Ext.draw.Surface',
        'Ext.layout.component.Draw'
    ],

    ganttSchedulingController: null,						// set later

    debug: false,
    taskBBoxHash: {},								// Hash array from object_ids -> Start/end point
    taskModelHash: {},								// Start and end date of tasks
    preferenceStore: null,
    arrowheadSize: 5,

    needsRedraw: false,								// Set this instead of initiating a redraw()
    needsReschedule: false,							// Set this instead of initiating a schedule()
    
    /**
     * Starts the main editor panel as the right-hand side
     * of a project grid and a cost center grid for the departments
     * of the resources used in the projects.
     */
    initComponent: function() {
        var me = this;

        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.initComponent: Starting');
        this.callParent(arguments);

        // Catch the moment when the "view" of the Project grid
        // is ready in order to draw the GanttBars for the first time.
        // The view seems to take a while...
        me.objectPanel.on({
            'viewready': me.onProjectGridViewReady,
            'sortchange': me.onProjectGridSortChange,
            'scope': this
        });

        // Catch the event that the object got moved
        me.on({
            'spriterightclick': me.onSpriteRightClick,
            'resize': me.redraw,
            'scope': this
        });

        // Redraw GanttBars when all events are handled
        Ext.globalEvents.on("idle", this.onIdle, me);				// Fires before return to browser

        // Iterate through all children of the root node and check if they are visible

        me.objectStore.on({
            'datachanged': me.onObjectStoreDataChanged,
            'scope': this
        });

        var rootNode = me.objectStore.getRootNode();
        rootNode.cascadeBy(function(model) {
            var id = model.get('id');
            me.taskModelHash[id] = model;					// Quick storage of models
        });

        this.addEvents('move');

        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.initComponent: Finished');
    },


    /**
     * Called before passing control back to the Browser.
     * Used to initiate a redraw() if necessary.
     * No logging, because this routine is called so frequently.
     */
    onIdle: function() {
        var me = this;
        if (me.needsRedraw) {
            me.redraw();
            me.needsRedraw = false;						// mark the "dirty" flat as cleaned
        }
    },

    /**
     * Some data in the object store have changed.
     * Normally we need to redraw here.
     */
    onObjectStoreDataChanged: function(event, eOpts) {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onObjectStoreDataChanged: Starting');

        // Modified, removed and new records in the store
        var modRec = event.getModifiedRecords();
        var remRec = event.getRemovedRecords();
        var newRec = event.getNewRecords();

        // Redraw for collapse/expand is handled explicitly
        // in onItemCollapse/onItemExpand.
        // Optimization: Don't redraw in these cases.
        if (0 == remRec.length + newRec.length + modRec.length) { return; }
        if (0 == remRec.length + newRec.length && 1 == modRec.length) {
            var mod = modRec[0].modified;
            if ('expanded' in mod) { return; }
        }

        me.needsRedraw = true;

        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onObjectStoreDataChanged: Finished');
    },

    /**
     * The list of tasks is (finally...) ready to be displayed.
     * We need to wait until this one-time event in in order to
     * set the width of the surface and to perform the first redraw().
     * Write the selection preferences into the SelModel.
     */
    onProjectGridViewReady: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectGridViewReady: Starting');

        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectGridViewReady: Finished');
    },

    onProjectGridSortChange: function(headerContainer, column, direction, eOpts) {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectGridSortChange: Starting');
        me.needsRedraw = true;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectGridSortChange: Finished');
    },

    /**
     * The user has right-clicked on a sprite.
     */
    onSpriteRightClick: function(event, sprite) {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onSpriteRightClick: Starting: '+ sprite);
        if (null == sprite) { return; }     				    	// Something went completely wrong...

        var dndConfig = sprite.dndConfig;
        if (!!dndConfig) {
            this.onProjectRightClick(event, sprite);
            return;
        }

        var dependencyModel = sprite.dependencyModel;
        if (!!dependencyModel) {
            this.onDependencyRightClick(event, sprite);
            return;
        }
        if (me.debug) { console.log('PO.view.gantt.GanttBarPanel.onSpriteRightClick: Unknown sprite:'); console.log(sprite); }
    },

    /**
     * The user has right-clicked on a dependency.
     */
    onDependencyRightClick: function(event, sprite) {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onDependencyRightClick: Starting: '+ sprite);
        if (null == sprite) { return; }     					// Something went completely wrong...

        // Menu for right-clicking a dependency arrow.
        if (!me.dependencyContextMenu) {
            me.dependencyContextMenu = Ext.create('Ext.menu.Menu', {
                id: 'dependencyContextMenu',
                style: {overflow: 'visible'},					// For the Combo popup
                dependencyModel: sprite.dependencyModel,
                items: [{
                    text: '@edit_dependency_l10n@',
                    handler: function() {
                        if (me.debug) console.log('dependencyContextMenu.editDependency: ');

                        var dependencyModel = this.ownerCt.dependencyModel;
                        var succId = dependencyModel.succ_id;
                        var succModel = me.taskModelHash[succId];		// Dependencies are stored as succModel.predecessors
                        var dependencyPropertyPanel = Ext.getCmp('ganttDependencyPropertyPanel');

                        dependencyPropertyPanel.setValue(dependencyModel, succModel);

                        dependencyPropertyPanel.setActiveTab('dependencyPropertyFormGeneral');
                        dependencyPropertyPanel.show();

                    }
                }, {
                    text: '@delete_dependency_l10n@',
                    handler: function() {
                        if (me.debug) console.log('dependencyContextMenu.deleteDependency: ');
                        var dependencyModel = this.ownerCt.dependencyModel;
                        var predId = dependencyModel.pred_id;
                        var succId = dependencyModel.succ_id;
                        var predModel = me.taskModelHash[predId];		// This should be empty!!
                        var succModel = me.taskModelHash[succId];		// Dependencies are stored as succModel.predecessors

                        var predecessors = succModel.get('predecessors');
                        var orgPredecessorsLen = predecessors.length
                        for (i = 0; i < predecessors.length; i++) {
                            var el = predecessors[i];
                            if (el.pred_id == predId) {
                                predecessors.splice(i,1);
                            }
                        }
                        if (predecessors.length != orgPredecessorsLen) { me.needsRedraw = true; }
                        succModel.set('predecessors',predecessors);

                        // Move the task to now()
                        succModel.setDirty();				// set(...) may not set dirty 
                        var oldStartDate = PO.Utilities.pgToDate(succModel.get('start_date'));
                        var oldEndDate =   PO.Utilities.pgToDate(succModel.get('end_date'));
                        var oldDateDiff = Math.abs(oldEndDate.getTime() - oldStartDate.getTime());

                        var newStartDate = new Date();
                        var newEndDate = new Date(newStartDate.getTime() + oldDateDiff);

                        me.needsRedraw = true;

                        // set the new dates
                        succModel.set('start_date', PO.Utilities.dateToPg(newStartDate));
                        succModel.set('end_date', PO.Utilities.dateToPg(newEndDate));
                    }
		}]
            });
        }
        me.dependencyContextMenu.dependencyModel = sprite.dependencyModel;      // context menu may be executed more than once with different deps
        me.dependencyContextMenu.showAt(event.getXY());
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onDependencyRightClick: Finished');
    },

    /**
     * The user has right-clicked on a project bar
     */
    onProjectRightClick: function(event, sprite) {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectRightClick: '+ sprite);
        if (null == sprite) { return; }     					// Something went completely wrong...
    },

    /**
     * Move the project forward or backward in time.
     * This function is called by onMouseUp as a
     * successful "drop" action of a drag-and-drop.
     */
    onProjectMove: function(projectSprite, xDiff) {
        var me = this;
        var projectModel = projectSprite.dndConfig.model;
        if (!projectModel) return;
        var projectId = projectModel.get('id');
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectMove: Starting');

        var bBox = me.dndBaseSprite.getBBox();					// Get the current coordinates of the moved Gantt bar
        var diffTime = xDiff * (me.axisEndDate.getTime() - me.axisStartDate.getTime()) / (me.axisEndX - me.axisStartX);
        var diffDays = Math.round(diffTime / 24.0 / 3600.0 / 1000.0);

        var startDate = PO.Utilities.pgToDate(projectModel.get('start_date')); 	if (!startDate) startDate = new Date();
        var endDate = PO.Utilities.pgToDate(projectModel.get('end_date')); if (!endDate) endDate = new Date();
        var startTime = startDate.getTime();
        var endTime = endDate.getTime();

        // Save original start- and end time in non-model variables
        if (!projectModel.orgStartTime) {
            projectModel.orgStartTime = startTime;
            projectModel.orgEndTime = endTime;
        }

        startTime = startTime + diffDays * 24.0 * 3600 * 1000;
        endTime = endTime + diffDays * 24.0 * 3600 * 1000;

        var newStartDate = new Date(startTime);
        var newEndDate = new Date(endTime);

        // projectModel.set('start_date', PO.Utilities.dateToPg(newStartDate));
        // projectModel.set('end_date', PO.Utilities.dateToPg(newEndDate));
        projectModel.set({
            'start_date': PO.Utilities.dateToPg(newStartDate),
            'end_date': PO.Utilities.dateToPg(newEndDate)
        });

        me.needsRedraw = true;

        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectMove: Finished');
    },

    /**
     * Move the end-date of the project forward or backward in time.
     * This function is called after a successful drag-and-drop operation
     * of the "resize handle" of the bar.
     */
    onProjectResize: function(projectSprite, xDiff) {
        var me = this;
        var projectModel = projectSprite.dndConfig.model;
        if (!projectModel) return;
        var projectId = projectModel.get('id');
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectResize: Starting');

        var bBox = me.dndBaseSprite.getBBox();
        var diffTime = Math.floor(1.0 * xDiff * (me.axisEndDate.getTime() - me.axisStartDate.getTime()) / (me.axisEndX - me.axisStartX));
        var endTime = PO.Utilities.pgToDate(projectModel.get('end_date')).getTime();

        // Save original start- and end time in non-model variables
        if (!projectModel.orgEndTime) {
            projectModel.orgEndTime = endTime;
        }
        endTime = endTime + diffTime;
        var endDate = new Date(endTime);
        projectModel.set('end_date', PO.Utilities.dateToPg(endDate));

        me.needsRedraw = true;

        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectResize: Finished');
    },

    /**
     * Move the end of the percent_completed bar according to mouse-up position.
     */
    onProjectPercentResize: function(projectSprite, percentSprite) {
        var me = this;
        var projectModel = projectSprite.dndConfig.model;
        if (!projectModel) return;
        var projectId = projectModel.get('id');
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectPercentResize: Starting');

        var projectBBox = projectSprite.getBBox();
        var percentBBox = percentSprite.getBBox();

        var projectWidth = projectBBox.width;
        if (0 == projectWidth) projectWidth = projectWidth + 1;			// Avoid division by zero.
        var percent = Math.floor(100.0 * percentBBox.width / projectWidth);
        if (percent > 100.0) percent = 100;
        if (percent < 0) percent = 0;
        projectModel.set('percent_completed', ""+percent);			// Write to project model and update tree via events
        me.needsRedraw = true;		      					// redraw the entire Gantt editor surface.
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onProjectPercentResize: Finished');
    },

    /**
     * Create a dependency between two two tasks.
     * This function is called by onMouseUp as a successful 
     * "drop" action if the drop target is another project.
     */
    onCreateDependency: function(fromSprite, toSprite) {
        var me = this;
        var fromTaskModel = fromSprite.dndConfig.model;
        var toTaskModel = toSprite.dndConfig.model;
        if (null == fromTaskModel) return;
        if (null == toTaskModel) return;
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.onCreateDependency: Starting: '+fromTaskModel.get('id')+' -> '+toTaskModel.get('id'));

        // Try connecting the two tasks via a task dependency
        var fromTaskId = fromTaskModel.get('id');				// String value!
        if (null == fromTaskId) return;						// Something went wrong...
        var toTaskId = toTaskModel.get('id');					// String value!
        if (null == toTaskId) return; 						// Something went wrong...
        if (fromTaskId == toTaskId) return;					// No dependency on itself...

        // Create a new dependency object
        if (me.debug) console.log('PO.view.gantt.GanttBarPanel.createDependency: '+fromTaskId+' -> '+toTaskId);
        var dependency = {
            pred_id: parseInt(fromTaskId),
            succ_id: parseInt(toTaskId),
            type_id: 9662,							// "End-to-Start", please see im_categories.category_id
            diff: 0.0
        };
        var dependencies = toTaskModel.get('predecessors');
        if ("" == dependencies) { dependencies = []; }
        dependencies.push(dependency);
        toTaskModel.set('predecessors', dependencies);

        // Check for cyclic dependencies with new dependency
        var cyclicP = me.ganttSchedulingController.checkCyclicDependencies(false);	// Check for cyclic dependencies
        if (cyclicP) {
            // Found cyclic structure: Delete the new dependency again
            me.ganttSchedulingController.checkCyclicDependenciesDelete(true, fromTaskId, toTaskId);
            me.ganttSchedulingController.checkCyclicDependencies(true);	     		// Fix internal vars
            alert('onCreateDependency: You are not allowed to create a cyclic dependency');    
        }

        toTaskModel.setDirty();							// above just modified array, so we need to notify
        me.needsRedraw = true;
        me.ganttSchedulingController.onCreateDependency(dependency);

        if (me.debug) console.log('GanttEditor.view.GanttBarPanel.onCreateDependency: Finished');
    },

    /**
     * Draw all Gantt bars
     */
    redraw: function(a, b, c, d, e) {
        var me = this;
        if (me.debug) console.log('PO.class.GanttDrawComponent.redraw: Starting');

        if (!me.needsRedraw) { return; }					// Lazy redraw: set only if a redraw is really necessary
        if (undefined === me.surface) { return; }				// Don't redraw when still initializing

        var sched = me.ganttSchedulingController;
        if (!!sched) {
            sched.onRedraw(me);							// Cleanup cyclic dependencies
        }

        // Get the root of the ganttTree
        var ganttTreeView = me.objectPanel.getView();
        var rootNode = me.objectStore.getRootNode();
        var numNodes = me.nodesInTree(rootNode);
        var surfaceYSize = numNodes * 20 + 50;					// +50 offset for the column bar on in TreePanel
        if (me.debug) console.log('PO.class.GanttDrawComponent.redraw: numNodes='+numNodes);
        var panelWidth = me.getBox().width;
        if (panelWidth > me.axisEndX) me.axisEndX = panelWidth;			// Resize the surface after a user panel resize

        me.surface.removeAll();
        me.surface.setSize(me.axisEndX, surfaceYSize);				// Set the size of the drawing area
        me.drawAxisAuto();							// Draw the top axis
        if (me.scrollX) {							// Deferred scrolling - only here we've got a scrollableEl...
            var scrollableEl = me.getEl();					// Ext.dom.Element that enables scrolling
            scrollableEl.setScrollLeft(me.scrollX);
            delete me.scrollX;							// Remove the attribute - scroll only once...
        }

	// Calculate the per-user hash of assignments of a user to other tasks
	me.setupOverassignments();

        // Iterate through all children of the root node and check if they are visible
        rootNode.cascadeBy(function(model) {
            var viewNode = ganttTreeView.getNode(model);
            if (viewNode == null) { return; }					// Hidden nodes have no viewNode -> no bar
            me.drawProjectBar(model);
        });

        // Iterate through all children and draw dependencies
        rootNode.cascadeBy(function(model) {
            var viewNode = ganttTreeView.getNode(model);
            if (viewNode == null) { return; }					// Hidden nodes have no viewNode -> no bar
            me.drawProjectDependencies(model);
        });

        if (me.debug) console.log('PO.class.GanttDrawComponent.redraw: Finished');
    },

    /**
     * Compile overassignment information in a hash of hashes
     * in order to speed-up lookup during redraw per task
     */
    setupOverassignments() {
        var me = this;
        var drawOverassignments = me.preferenceStore.getPreferenceBoolean('show_project_cross_project_overassignments', true);
        if (!drawOverassignments) return;
        if (me.debug) { if (me.debug) console.log('PO.view.gantt.GanttBarPanel.setupOverassignments: Starting'); }

        var absenceAssignmentStore = Ext.StoreManager.get('absenceAssignmentStore');
        var projectMemberStore = Ext.StoreManager.get('projectMemberStore');
        var overHash = {};

        absenceAssignmentStore.each(function(absence) {
            var userId = parseInt(absence.get('user_id'));
            var objectId = parseInt(absence.get('object_id'));
            var objectName = absence.get('name');
            var startDate = absence.get('start_date').substring(0,10);
            var endDate = absence.get('end_date').substring(0,10);
            var startX = me.date2x(new Date(startDate)); if (!startX) return;
            var endX = me.date2x(new Date(endDate)); if (!endX) return;
            var type = absence.get('object_type');
            var user_id = absence.get('user_id');
            var user_name = absence.get('user_name');
            var context_id = absence.get('context_id');
            var context = absence.get('context');

            // Write to hash
            var userHash = overHash[userId];
            if (!userHash) { 
                userHash = {};
                overHash[userId] = userHash;
            }
            userHash[objectId] = {startX: startX, endX: endX, name: objectName, type: type, userName: user_name, contextId: context_id, context: context};
        });

        // Iterate through all children of the root node and check if they are visible
        var rootNode = me.objectStore.getRootNode();
        rootNode.cascadeBy(function(task) {

	    // Skip summary activities (tasks with children)
	    var children = task.childNodes;
	    if (Array.isArray(children)) {
		var numChildren = children.length;
		if (numChildren > 0) return;
	    }
	    
            var task_id = task.get('id');
            var taskId = parseInt(task_id); if (!taskId) return;
            var taskName = task.get('project_name');
            var assignees = task.get('assignees');					// Array of {id, percent, name, email, initials}
            var startDate, endDate;

            // Get start- and end date (look at parents if necessary...)
            var p = task;
            while ("" == (startDate = p.get('start_date')) && !!p.parentNode) { p = p.parentNode;}
            var p = task;
            while ("" == (endDate = p.get('end_date')) && !!p.parentNode) { p = p.parentNode; }
            if ("" == startDate || "" == endDate) { return; }

            var startDate = PO.Utilities.pgToDate(startDate);
            var endDate = PO.Utilities.pgToDate(endDate);
            if (!startDate) return;							// skip if invalid for some reason...
            if (!endDate) return;
            var startTime = startDate.getTime();
            var endTime = endDate.getTime();
            var startX = me.date2x(startTime);						// X position based on time scale
            var endX = me.date2x(endTime);						// X position based on time scale

            assignees.forEach(function(assignee) {
                if (0 == assignee.percent) { return; }					// Don't show empty assignments
                var userId = assignee.user_id;
                var userModel = projectMemberStore.getById(""+assignee.user_id);
                if (!userModel) return;
                var userName = userModel.get('name');
                var userHash = overHash[userId];					// Write to hash
                if (!userHash) { 
                    userHash = {};
                    overHash[userId] = userHash;
                }
                userHash[taskId] = {startX: startX, endX: endX, name: taskName, type: 'im_project', userName: userName, contextId: taskId, context: taskName};
            });
        });

        me.overassignmentHash = overHash;

        if (me.debug) { if (me.debug) console.log('PO.view.gantt.GanttBarPanel.setupOverassignments: Finished'); }
    },



    /**
     * Delete bar from surface
     */
    undrawProjectBar: function(project) {
        var me = this;

        var surface = me.surface;

    },

    /**
     * Draw a single bar for a project or task
     */
    drawProjectBar: function(project) {
        var me = this;
        // if (me.debug) { if (me.debug) console.log('PO.view.gantt.GanttBarPanel.drawProjectBar: Starting'); }

        var surface = me.surface;
        var taskName = project.get('project_name');
        var percentCompleted = parseFloat(project.get('percent_completed')); if (isNaN(percentCompleted)) percentCompleted = 0.0;
        var predecessors = project.get('predecessors');
        var assignees = project.get('assignees');				// Array of {id, percent, name, email, initials}
        var baselines = project.get('baselines'); 				// Array of {id, percent, name, email, initials}
        var absenceAssignmentStore = Ext.StoreManager.get('absenceAssignmentStore');
        var plannedHours = parseFloat(project.get('planned_units')).toFixed(1); if (isNaN(plannedHours)) plannedHours = 0.0;
        var loggedHours = parseFloat(project.get('reported_hours_cache')).toFixed(1); if (isNaN(loggedHours)) loggedHours = 0.0;
        var percentLogged = 0; if (plannedHours > 0) percentLogged = (100.0 * loggedHours / plannedHours).toFixed(1);
        var workDone = (plannedHours * percentCompleted / 100.0).toFixed(1);

        var startDate, endDate;

        // Get start- and end date (look at parents if necessary...)
        var p = project;
        while ("" == (startDate = p.get('start_date')) && !!p.parentNode) { p = p.parentNode;}
        var p = project;
        while ("" == (endDate = p.get('end_date')) && !!p.parentNode) { p = p.parentNode; }
        if ("" == startDate || "" == endDate) { return; }

        var startDate = PO.Utilities.pgToDate(startDate);
        var endDate = PO.Utilities.pgToDate(endDate);
        if (!startDate) return; 						// skip if invalid for some reason...
        if (!endDate) return;
        var startTime = startDate.getTime();
        var endTime = endDate.getTime();

        var x = me.date2x(startTime);						// X position based on time scale
        var y = me.calcGanttBarYPosition(project);				// Y position based on TreePanel y position of task.
        var w = Math.floor(me.axisEndX * (endTime - startTime) / (me.axisEndDate.getTime() - me.axisStartDate.getTime()));
        if (w < 2) { w = 2; }	       	 	    	       	 		// Start/end are completely wrong (probably end < start..)
        var h = me.ganttBarHeight;						// Constant determines height of the bar
        var d = Math.floor(h / 2.0) + 1;					// Size of the indent of the super-project bar

        // Store the start and end points of the Gantt bar
        var id = project.get('id');
        me.taskBBoxHash[id] = {x: x, y: y, width: w, height: h};		// Remember the outer dimensions of box for dependencies
        me.taskModelHash[id] = project;						// Remember the models per ID
        var drawn = null;

        // ---------------------------------------------------------------
        // Task with zero length: Draw a milestone
        if (!drawn && project.isMilestone()) {					// either explicitely marked or zero duration
            drawn = "milestone";
            var m = h/2;							// Half the size of the bar height
            var spriteBar = surface.add({
                type: 'path',
                stroke: 'black',
                'stroke-width': 0.3,
                fill: 'black',
                zIndex: 0,
                path: 'M '+ (x-m) + ', ' + (y+m)
                    + 'L '+ (x) + ', ' + (y)
                    + 'L '+ (x+m) + ', ' + (y+m)
                    + 'L '+ (x) + ', ' + (y+h)
                    + 'L '+ (x-m) + ', ' + (y+m),
                listeners: {							// Highlight the sprite on mouse-over
                    mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 2.0}}); },
                    mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
                }
            }).show(true);
        }

        // ---------------------------------------------------------------
        // Draw a standard Gantt bar if the task is a leaf (has no children)
        if (!drawn && !project.hasChildNodes()) {				// Parent tasks don't have DnD and look different
            drawn = "bar";
            // The main Gantt bar with Drag-and-Drop configuration
            var spriteBar = surface.add({
                type: 'rect', x: x, y: y, width: w, height: h, radius: 3,
                fill: 'url(#gradientId)',
                stroke: 'blue',
                'stroke-width': 0.3,
                zIndex: -100,							// Neutral zIndex - in the middle
                listeners: {							// Highlight the sprite on mouse-over
                    mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 0.5}}); },
                    mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
                }
            }).show(true);

            // Resize-Handle of the Gantt Bar: This is an invisible box at the right end of the bar
            // used to change the cursor and to initiate a specific resizing DnD operation.
            var spriteBarHandle = surface.add({
                type: 'rect', x: x+w+2, y: y, width: 3, height: h,		// Located at the right edge of spriteBar.
                stroke: 'red',	 	      	     				// For debugging - not visible
                fill: 'red',							// Need to be filled for cursor display
                opacity: 0,							// Invisible
                zIndex: 50,							// At the very top of the z-stack
                style: { cursor: 'e-resize' }					// Shows a horizontal arrow cursor
            }).show(true);

            spriteBarHandle.dndConfig = {
                model: project,							// Store the task information for the sprite
                baseSprite: spriteBar,
                dragAction: function(panel, e, diff, dndConfig) {
                    if (me.debug) console.log('PO.view.gantt.GanttBarPanel.drawProjectBar.spriteBarHandle.dragAction:');
                    var baseBBox = panel.dndBaseSprite.getBBox();
                    var shadow = panel.dndShadowSprite;
                    var width = baseBBox.width + diff[0];
                    if (width < 0) width = 0;
                    shadow.setAttributes({width: width}).show(true);
                },
                dropAction: function(panel, e, diff, dndConfig) {
                    if (me.debug) console.log('PO.view.gantt.GanttBarPanel.drawProjectBar.spriteBarHandle.dropAction:');
                    me.onProjectResize(panel.dndBaseSprite, diff[0]);		// Changing end-date to match x coo
                }
            };

            var tooltipBaseHtml = ""+
                "<table cellspacing=0 cellpadding=1>"+
                "<tr><td>Work planned:</td><td colspan=2>"+plannedHours.toLocaleString('en-US')+" hours</td></tr>"+
                "<tr><td>Work done:</td><td>"+workDone.toLocaleString('en-US')+" hours</td><td>= "+percentCompleted.toLocaleString('en-US')+"%</td></tr>"+
                "<tr><td>Hours logged:</td><td>"+loggedHours.toLocaleString('en-US')+" hours</td><td>= "+percentLogged.toLocaleString('en-US')+"%</td></tr>"+
                "</table>";

            // Percent_complete bar on top of the Gantt bar:
            // Allows for special DnD affecting only %done.
            var drawPercentCompleted = me.preferenceStore.getPreferenceBoolean('show_percent_done_bar', true);
            if (drawPercentCompleted) {
                var opacity = 0.0;
                if (isNaN(percentCompleted)) percentCompleted = 0;
                if (percentCompleted > 0.0) opacity = 1.0;
                var percentW = w*percentCompleted/100;
                if (percentW < 2) percentW = 2;

                var spriteBarPercent = surface.add({
                    type: 'rect', x: x, y: y+2, width: percentW, height: (h-6)/2,
                    stroke: 'black',
                    fill: 'black',
                    'stroke-width': 0.0,
                    zIndex: 20,
                    opacity: opacity
                }).show(true);

                var tooltipHtml = "<b>Work Done: "+percentCompleted+"%</b>"+tooltipBaseHtml;
                Ext.create("Ext.tip.ToolTip", { target: spriteBarPercent.el, width: 300, html: tooltipHtml, hideDelay: 5000 });

            } // end drawPercentCompleted

            // Percent_complete bar on top of the Gantt bar:
            // Allows for special DnD affecting only %done.
            var drawLoggedHoursBar = me.preferenceStore.getPreferenceBoolean('show_logged_hours_bar', true);
            if (drawLoggedHoursBar) {
                var opacity = 0.0;
                if (percentLogged > 0.0) opacity = 1.0;
                var percentW = w*percentLogged/100;
                if (percentW < 2) percentW = 2;
                var color = 'blue';
                if (percentLogged > percentCompleted) 
                    color = 'red';

                var spriteBarLoggedHours = surface.add({
                    type: 'rect', x: x, y: y+2+(h-6)/2+2, width: percentW, height: (h-6)/2,
                    stroke: color,
                    fill: color,
                    'stroke-width': 0.0,
                    zIndex: 20,
                    opacity: opacity
                }).show(true);

                var tooltipHtml = "<b>Hours Logged: "+loggedHours+" hours</b>"+tooltipBaseHtml;
                Ext.create("Ext.tip.ToolTip", { target: spriteBarLoggedHours.el, width: 300, html: tooltipHtml, hideDelay: 5000 });
            }

        }

        // ---------------------------------------------------------------
        // Draw a Gantt container task if the task has children
        if (!drawn && project.hasChildNodes()) {				// Parent tasks don't have DnD and look different
            drawn = "supertask";
            var spriteBar = surface.add({
                type: 'path',
                stroke: 'blue',
                'stroke-width': 0.3,
                fill: 'url(#gradientId)',
                zIndex: 0,
                path: 'M '+ x + ', ' + y
                    + 'L '+ (x+w) + ', ' + (y)
                    + 'L '+ (x+w) + ', ' + (y+h)
                    + 'L '+ (x+w-d) + ', ' + (y+h-d)
                    + 'L '+ (x+d) + ', ' + (y+h-d)
                    + 'L '+ (x) + ', ' + (y+h)
                    + 'L '+ (x) + ', ' + (y),
                listeners: {							// Highlight the sprite on mouse-over
                    mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 2.0}}); },
                    mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
                }
            }).show(true);
        }
        if (!drawn) { alert('GanttBarPanel.drawProjectBar: not drawn for some reason'); }


        // ---------------------------------------------------------------
        // Draw baselines
        var drawBaseline = me.preferenceStore.getPreference('show_project_baseline', false);
	console.log('PO.view.gantt.GanttBarPanel.drawProjectBar.baselines: drawBaseline='+drawBaseline);

        if (drawBaseline) {
            if (baselines && "" != baselines) {
                var baseline = baselines[drawBaseline];
                if (baseline && "" != baseline) {
                    
                    var baselineStart = baseline.start_date;
                    var baselineEnd = baseline.end_date;
                    if (!!baselineStart && !!baselineEnd) {
                        var baselineStartDate = PO.Utilities.pgToDate(baselineStart);
                        var baselineEndDate = PO.Utilities.pgToDate(baselineEnd);
                        var startX = me.date2x(baselineStartDate);				// X position based on time scale
                        var endX = me.date2x(baselineEndDate);				// X position based on time scale
                        
                        // A baseline shadow
                        var baselineSpriteBar = surface.add({
                            type: 'rect', x: startX, y: y, width: endX - startX, height: h, radius: 3,
                            stroke: 'red',
                            'stroke-width': 0.3,
                            zIndex: -200,							// In the background
                        }).show(true);
                        // 2021-08-24 fraber: Tooltips don't show because the stroke is so thin.
                        // Ext.create("Ext.tip.ToolTip", { target: spriteBar.el, width: 250, html: tooltipHtml, hideDelay: 2000 });
                    }
                }
            }
        }
        
        // ---------------------------------------------------------------
        // Draw assignee initials behind the Gantt bar.
        var drawAssignees = me.preferenceStore.getPreferenceBoolean('show_project_assigned_resources', true);
        if (drawAssignees) {
            var projectMemberStore = Ext.StoreManager.get('projectMemberStore');
            var text = "";
            if ("" != assignees) {
                assignees.forEach(function(assignee) {
                    if (0 == assignee.percent) { return; }				// Don't show empty assignments
                    var userModel = projectMemberStore.getById(""+assignee.user_id);
                    if (!userModel) return;
                    if ("" != text) { text = text + ', '; }
                    text = text + userModel.get('initials');
                    if (100 != assignee.percent) {
                        text = text + '['+assignee.percent+'%]';
                    }
                });

                var xOffset = w + 4;						// Default: Start directly behind the bar
                switch (drawn) {
                case 'milestone': xOffset = 8;					// Milestone: Ignore bar width, but add some extra space
                }

                var axisText = surface.add({type:'text', text:text, x:x+xOffset, y:y+d, fill:'#000', font:"10px Arial"}).show(true);
            }
        }


        // ---------------------------------------------------------------
        // Draw indication of user absence or assignment

        var drawOverassignments = me.preferenceStore.getPreferenceBoolean('show_project_cross_project_overassignments', true);
        if (drawOverassignments && !project.isMilestone() && !project.hasChildNodes()) {
            assignees.forEach(function(assigneeModel) {
                var assigneeId = assigneeModel.user_id;
                var assigneeHash = me.overassignmentHash[assigneeId];
                if (!assigneeHash) return;
                for (var object_id in assigneeHash) {
                    var objectId = parseInt(object_id);
                    if (objectId == id) continue;			// Don't show overallocation with the task itself :-)
                    var absenceHash = assigneeHash[objectId];
                    var startX = absenceHash.startX;
                    var endX = absenceHash.endX;

                    // Skip if not overlapping with Gantt bar
                    if (startX > x + w) continue;				// starts after the end of the Gantt bar
                    if (endX < x) continue				// ends before the start of the Gantt bar

                    // Limit red bar to the Gantt bar size
                    if (startX < x) { startX = x; }			// starts before Gantt bar => set to start of Gantt bar
                    if (endX > x + w) { endX = x + w; }			// ends after Gantt bar end => set end to end of Gantt bar
                    if (startX < 0) { startX = 1; }
                    var width = endX - startX;
                    if (width < 1) { width = 1; }

                    var assigneeBar = surface.add({
                        type: 'rect', x: startX, y: y-4, width: width, height: h+8, radius: 0,
                        fill: 'red',
                        opacity: 0.1,
                        'stroke-width': 1,
                        zIndex: -1000						// Neutral zIndex - in the middle
                    }).show(true);

                    var type = absenceHash.type;
                    var name = absenceHash.name;
                    var absenceHtml = "";
                    var user_name = absenceHash.userName;
                    var context_id = absenceHash.contextId;
                    var context = absenceHash.context;
                    switch (type) {
                    case "im_project":
                        absenceHtml = '<b>Overassignment</b><br>'+
                            'User: <a href=/intranet/users/view?user_id='+ assigneeId + ' target=_blank>' + user_name + '</a><br>' +
                            'has already been assigned<br>' +
                            'to Task: <a href=/intranet-timesheet2-tasks/new?task_id=' + objectId + ' target=_blank>' + name + '</a><br>' +
                            'of Project: <a href=/intranet/projects/view?project_id='+ context_id + ' target=_blank>' + context + '</a>';
                        break;
                    case "im_user_absence":
                        absenceHtml = '<b>Assignment during absence</b><br>'+
                            'User: <a href=/intranet/users/view?user_id='+ assigneeId + ' target=_blank>' + user_name + '</a><br>' +
                            'has been assigned while absent due to<br>' +
                            'Absence: ' + name + '<br>';
                        break;
                    default:
                        alert('GanttBarPanel.drawProjectBar: Found unknown Vacation or Absence type: '+type);
                    }
                    Ext.create("Ext.tip.ToolTip", { 
                        target: assigneeBar.el, 
                        width: 250, 
                        html: absenceHtml,
                        hideDelay: 2000 
                    });
                }
            });    
        }

        // ---------------------------------------------------------------
        // Draw financial documents above Gantt bar
        var drawFinDocs = me.preferenceStore.getPreferenceBoolean('show_project_findocs', true);
        if (drawFinDocs) {
            var invoices = project.get('invoices'); 				// Array of {id, cost_name, cost_type_id, cost_type}
            if (!!invoices && invoices instanceof Array && invoices.length > 0) {
                var imageWidth = 19;
                var busyX = {};
                invoices.forEach(function(invoice) {
                    var prefix = invoice.cost_type.substring(0,1).toLowerCase();
                    var effectiveDate = new Date(invoice.effective_date);
                    var invoiceX = me.date2x(effectiveDate);
        	    if (!invoiceX) return;

                    // Make sure multiple invoices appear beside each other
                    var pos = Math.round(invoiceX / imageWidth);
                    while (pos in busyX) {
                	invoiceX = invoiceX + imageWidth;
                	var pos = Math.round(invoiceX / imageWidth);
                    }
                    busyX[pos] = pos;						// mark as busy

                    var invoiceBar = surface.add({
                	type: 'image', x: invoiceX, y: y-h, width: imageWidth, height: 13,
                	src: "/intranet/images/"+prefix+".gif",
                	listeners: { mousedown: function() { window.open('/intranet-invoices/view?invoice_id='+invoice.id); } }
                    }).show(true);
                });
            }
        }

        // Add a drag-and-drop configuration to all spriteBars (bar, supertask and milestone)
        // in order to allow them to act as both source and target of inter-task dependencies.
        spriteBar.dndConfig = {							// Drag-and-drop configuration
            model: project,							// Store the task information for the sprite
            baseSprite: spriteBar,						// "Base" sprite for the DnD action
            dragAction: function(panel, e, diff, dndConfig) {			// Executed onMouseMove in AbstractGanttPanel
                var shadow = panel.dndShadowSprite;				// Sprite "shadow" (copy of baseSprite) to move around
                var linkSprite = panel.dndLinkSprite;
                if ( diff[1] > 10 || diff[1] < -10 ) {
                    shadow.hide(true);
                    linkSprite.show(true);
                    var point = me.getMousePoint(e);
                    linkSprite.setAttributes( {x: point[0], y: point[1] - 5}, true);
                } else {
                    shadow.show(true);
                    shadow.setAttributes({translate: {x: diff[0], y: 0}}, true); // Move shadow according to mouse position
                    linkSprite.hide(true);
                };
            },
            dropAction: function(panel, e, diff, dndConfig) {			// Executed onMouseUp in AbastractGanttPanel
                if (me.debug) console.log('PO.view.gantt.GanttBarPanel.drawProjectBar.spriteBar.dropAction:');
                panel.dndLinkSprite.destroy();					// Hide Link graphic
                var point = me.getMousePoint(e);				// Corrected mouse coordinates
                var baseSprite = panel.dndBaseSprite;				// spriteBar to be affected by DnD
                if (!baseSprite) { return; }					// Something went completely wrong...
                var dropSprite = panel.getSpriteForPoint(point);		// Check where the user has dropped the shadow
                if (baseSprite == dropSprite) { dropSprite = null; }		// Dropped on same sprite? => normal drop
                if (0 == Math.abs(diff[0]) + Math.abs(diff[1])) {  		// Same point as before?
                    return;							// Drag-start == drag-end or single-click
                }
                if (null != dropSprite) {
                    me.onCreateDependency(baseSprite, dropSprite);		// Dropped on another sprite - create dependency
                } else {
                    me.onProjectMove(baseSprite, diff[0]);			// Dropped on empty space or on the same bar
                }
            }
        };

        spriteBar.mode = project;

        // if (me.debug) { if (me.debug) console.log('PO.view.gantt.GanttBarPanel.drawProjectBar: Finished'); }
    },

    /**
     * Iterate throught all successors of a Gantt bar
     * and draw dependencies.
     */
    drawProjectDependencies: function(project) {
        var me = this;

        var predecessors = project.get('predecessors');
        if (!predecessors instanceof Array) return;
        if (!me.preferenceStore.getPreferenceBoolean('show_project_dependencies', true)) return;

        for (var i = 0, len = predecessors.length; i < len; i++) {
            var dependencyModel = predecessors[i];
            me.drawDependency(dependencyModel);					// Draw a dependency arrow between Gantt bars
        }
    },

    /**
     * Draws a dependency line from one bar to the next one
     */
    drawDependency: function(dependencyModel) {
        var me = this;
        // if (me.debug) console.log('GanttEditor.view.GanttBarPanel.drawTaskDependency: Starting');

        var fromId = dependencyModel.pred_id;
        var fromModel = me.taskModelHash[fromId]
        var toId = dependencyModel.succ_id;
        var toModel = me.taskModelHash[toId]

        // We can get dependencies from other projects.
        // These are not in the taskModelHash, so just skip these
        // ToDo: Show dependencies from other projects
        if (undefined === fromModel || undefined === toModel) { 
            if (me.debug) console.log('GanttEditor.view.GanttBarPanel.drawTaskDependency: Dependency from other project: Skipping');
            return; 
        }

        var depName = 'Task dependency';
        var depTypeId = dependencyModel.type_id;
	if (depTypeId == 9650) depTypeId = 9662;					// compatibility
        switch (depTypeId) {
        case 9660: depName = '@finish_to_finish_l10n@'; break;
        case 9662: depName = '@finish_to_start_l10n@'; break;
        case 9664: depName = '@start_to_finish_l10n@'; break;
        case 9666: depName = '@start_to_start_l10n@'; break;
        default:
            alert('drawDependency: found undefined dependencyTypeId='+depTypeId);
            return;
        }

        // Text for dependency tool tip
        var html = "<b>"+depName+"</b>:<br>" +
            "From <a href='/intranet/projects/view?project_id=" + fromId + "' target='_blank'>" + fromModel.get('project_name') + "</a> " +
            "to <a href='/intranet/projects/view?project_id=" + toId + "' target='_blank'>" + toModel.get('project_name') + "</a>";

        me.drawDependencyMsp(dependencyModel,html);

        // if (me.debug) console.log('GanttEditor.view.GanttBarPanel.drawTaskDependency: Finished');
    },

    /**
     * Draws a dependency line from one bar to the next one.
     * 
     * ToDo: Also draw start-end-start and other dependency types apart from end-to-start
     */
    drawDependencyMsp: function(dependencyModel, tooltipHtml) {
        var me = this;
        var s, color, startX, startY, endX, endY;
        var objectPanelView = me.objectPanel.getView();			 // The "view" for the GridPanel with HTML elements

        var fromId = dependencyModel.pred_id;
        var fromBBox = me.taskBBoxHash[fromId];					// We start drawing with the end of the first bar...
        var fromModel = me.taskModelHash[fromId]

        var toId = dependencyModel.succ_id;
        var toBBox = me.taskBBoxHash[toId];					// .. and draw towards the start of the 2nd bar.
        var toModel = me.taskModelHash[toId]
        if (!fromBBox || !toBBox) { return; }

        // Double check for nodes that are in the cache, but that have just been hidden
        // ToDo: Delete nodes from the cache when hiding branches in the tree
        var fromNode = objectPanelView.getNode(fromModel);
        var toNode = objectPanelView.getNode(toModel);
        if (!fromNode || !toNode) { return; }

        s = me.arrowheadSize;
        startY = fromBBox.y + fromBBox.height/2;				// vertical start point is always the middle of the bar

        var depTypeId = dependencyModel.type_id;
	if (depTypeId == 9650) depTypeId = 9662;				// compatibility: Depends -> Finish-to-Start
        switch (depTypeId) {
        case 9660: 
            // finish_to_finish - draw from pred right center to the right, down to succ and left back to the right side of the bar.

            startX = fromBBox.x + fromBBox.width;				// Right side of the fromBBox
            endX = toBBox.x + toBBox.width;					// right of the toBBox
            endY = toBBox.y + toBBox.height/2;			    	     	// End at the center of the toBBox
            color = '#222';		  		  			// dark grey color

            // Go from startX to the left, then down and then back to the right to endX
	    var rightMaxX = Math.max(startX, endX) + fromBBox.height;
            var arrowLine = me.surface.add({
		type: 'path',
		stroke: color,
		'shape-rendering': 'crispy-edges',
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (startX)    + ', ' + (startY)
                    + 'L '+ (rightMaxX) + ', ' + (startY)
                    + 'L '+ (rightMaxX) + ', ' + (endY)
                    + 'L '+ (endX)      + ', ' + (endY)
            }).show(true);
            arrowLine.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowLine.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            // Draw the arrow head (filled)
            var arrowHead = me.surface.add({
		type: 'path',
		stroke: color,
		fill: color,
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (endX)   + ', ' + (endY)				// Point of arrow head
                    + 'L '+ (endX+s) + ', ' + (endY-s)
                    + 'L '+ (endX+s) + ', ' + (endY+s)
                    + 'L '+ (endX)   + ', ' + (endY)
            }).show(true);
            arrowHead.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowHead.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            break;
        case 9662: 
            // finish_to_start - start off at the center right of the task and point down on the top of the successor

            startX = fromBBox.x + fromBBox.width;				// End-to-start dep starts at the right side of the fromBBox
            color = '#222';		  		  			// dark grey color
            if (toBBox.x < fromBBox.x + fromBBox.width) {			// Inverse dep starts at the left side of the fromBBox
        	color = 'red'; 
        	startX = fromBBox.x;						
            }

            endX = toBBox.x + s;						// Slightly to the right of the start of the task
            if (toModel.isMilestone()) { endX = toBBox.x; }			// Point directly to the start of the milestone

            if (toBBox.y >= fromBBox.y + fromBBox.height) {			// "normal" dependency from a task higher up to a task further down
        	endY = toBBox.y;
            } else {								// "inverse" dependency from a lower task to a task higher up
        	endY = toBBox.y + toBBox.height;
        	s = -s;								// Draw the dependency arrow from bottom to top
            }

            // Draw the main connection line between start and end.
            var arrowLine = me.surface.add({
		type: 'path',
		stroke: color,
		'shape-rendering': 'crispy-edges',
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (startX)    + ', ' + (startY)
                    + 'L '+ (endX)      + ', ' + (startY)
                    + 'L '+ (endX)      + ', ' + (endY)
            }).show(true);
            arrowLine.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowLine.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            // Draw the arrow head (filled)
            var arrowHead = me.surface.add({
		type: 'path',
		stroke: color,
		fill: color,
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (endX)   + ', ' + (endY)				// Point of arrow head
                    + 'L '+ (endX-s) + ', ' + (endY-s)
                    + 'L '+ (endX+s) + ', ' + (endY-s)
                    + 'L '+ (endX)   + ', ' + (endY)
            }).show(true);
            arrowHead.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowHead.el, width: 250, html: tooltipHtml, hideDelay: 2000 });


            break;
        case 9664: 
            // start_to_finish

            startX = fromBBox.x;						// Right side of the fromBBox
            endX = toBBox.x + toBBox.width;					// right of the toBBox
            endY = toBBox.y + toBBox.height/2;			    	     	// End at the center of the toBBox
            color = '#222';		  		  			// dark grey color

            // Go from startX to the left, then down and then back to the right to endX
            var arrowLine = me.surface.add({
		type: 'path',
		stroke: color,
		'shape-rendering': 'crispy-edges',
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (startX)                 + ', ' + (startY)
                    + 'L '+ (startX - toBBox.height) + ', ' + (startY)
                    + 'L '+ (startX - toBBox.height) + ', ' + ((startY+endY)/2)
                    + 'L '+ (endX + toBBox.height)   + ', ' + ((startY+endY)/2)
                    + 'L '+ (endX + toBBox.height)   + ', ' + (endY)
                    + 'L '+ (endX)                   + ', ' + (endY)
            }).show(true);
            arrowLine.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowLine.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            // Draw the arrow head (filled)
            var arrowHead = me.surface.add({
		type: 'path',
		stroke: color,
		fill: color,
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (endX)   + ', ' + (endY)				// Point of arrow head
                    + 'L '+ (endX+s) + ', ' + (endY-s)
                    + 'L '+ (endX+s) + ', ' + (endY+s)
                    + 'L '+ (endX)   + ', ' + (endY)
            }).show(true);
            arrowHead.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowHead.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            break;
        case 9666: 
            // start_to_start - from left center of the pred bar to the left center of the succ

            startX = fromBBox.x;				    	     	// start at the left side of the fromBBox
            endX = toBBox.x;							// left of the toBBox
            endY = toBBox.y + toBBox.height/2;			    	     	// start at the left side of the fromBBox
            color = '#222';		  		  			// dark grey color

            // Go from startX to the left, then down and then back to the right to endX
	    var leftMinX = Math.min(startX, endX) - fromBBox.height;
            var arrowLine = me.surface.add({
		type: 'path',
		stroke: color,
		'shape-rendering': 'crispy-edges',
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (startX)    + ', ' + (startY)
                    + 'L '+ (leftMinX)  + ', ' + (startY)
                    + 'L '+ (leftMinX)  + ', ' + (endY)
                    + 'L '+ (endX)      + ', ' + (endY)
            }).show(true);
            arrowLine.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowLine.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            // Draw the arrow head (filled)
            var arrowHead = me.surface.add({
		type: 'path',
		stroke: color,
		fill: color,
		'stroke-width': 0.5,
		zIndex: -100,							// -100
		path: 'M '+ (endX)   + ', ' + (endY)				// Point of arrow head
                    + 'L '+ (endX-s) + ', ' + (endY-s)
                    + 'L '+ (endX-s) + ', ' + (endY+s)
                    + 'L '+ (endX)   + ', ' + (endY)
            }).show(true);
            arrowHead.dependencyModel = dependencyModel;
            Ext.create("Ext.tip.ToolTip", { target: arrowHead.el, width: 250, html: tooltipHtml, hideDelay: 2000 });

            break;
        default:
            alert('drawDependencyMsp: found undefined dependencyTypeId='+depTypeId);
            return;
        }


        if (me.debug) console.log('GanttEditor.view.GanttBarPanel.drawTaskDependency: Finished');
        return;
    }
});

