<div id="@gantt_editor_id@" style="overflow: hidden; -webkit-user-select: none; -moz-user-select: none; -khtml-user-select: none; -ms-user-select: none; ">
<script type='text/javascript'>

// Ext.Loader.setConfig({enabled: true});
Ext.Loader.setPath('Ext.ux', '/sencha-v411/examples/ux');
Ext.Loader.setPath('PO.model', '/sencha-core/model');
Ext.Loader.setPath('PO.store', '/sencha-core/store');
Ext.Loader.setPath('PO.class', '/sencha-core/class');
Ext.Loader.setPath('PO.view', '/sencha-core/view');
Ext.Loader.setPath('PO.controller', '/sencha-core/controller');

Ext.require([
    'Ext.data.*',
    'Ext.grid.*',
    'Ext.tree.*',
    'Ext.ux.CheckColumn',
    'PO.class.CategoryStore',
    'PO.controller.StoreLoadCoordinator',
    'PO.model.timesheet.TimesheetTask',
    'PO.store.timesheet.TaskTreeStore',
    'PO.store.user.SenchaPreferenceStore',
    'PO.view.field.PODateField',                      // Custom ]po[ Date editor field
    'PO.view.gantt.AbstractGanttPanel',
    'PO.view.menu.AlphaMenu',
    'PO.view.menu.HelpMenu'
]);


/**
 * Like a chart Series, displays a list of tasks
 * using Gantt bars.
 */
Ext.define('PO.view.gantt_editor.GanttBarPanel', {
    extend: 'PO.view.gantt.AbstractGanttPanel',

    requires: [
        'PO.view.gantt.AbstractGanttPanel',
        'Ext.draw.Component',
        'Ext.draw.Surface',
        'Ext.layout.component.Draw'
    ],

    // Really Necessary???
    taskDependencyStore: null,					// Reference to cost center store, set during init
    preferenceStore: null,

    barHash: {},                                     // Hash array from object_ids -> Start/end point
    taskModelHash: {},						// Start and end date of tasks

    /**
     * Starts the main editor panel as the right-hand side
     * of a project grid and a cost center grid for the departments
     * of the resources used in the projects.
     */
    initComponent: function() {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.initComponent: Starting');
        this.callParent(arguments);

        me.barHeight = 15;
        me.arrowheadSize = 5;

        // Attract events from the TreePanel showing the task names etc.
        me.objectPanel.on({
            'itemexpand': me.onItemExpand,
            'itemcollapse': me.onItemCollapse,
            'itemmove': me.redraw,
            'itemremove': me.redraw,
            'iteminsert': me.redraw,
            'itemappend': me.redraw,
            'resize': me.redraw,
            'columnschanged': me.redraw,
            'scope': this
        });;

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
            'spritednd': me.onSpriteDnD,
            'spriterightclick': me.onSpriteRightClick,
            'resize': me.redraw,
            'scope': this
        });

        // Redraw dependency arrows when loaded
        me.taskDependencyStore.on({
            'load': me.onTaskDependencyStoreChange,
            'scope': this
        });

        // Iterate through all children of the root node and check if they are visible
        me.objectStore.on({
            'datachanged': me.redraw,
            'scope': this
        });

        var rootNode = me.objectStore.getRootNode();
        rootNode.cascadeBy(function(model) {
            var id = model.get('id');
            me.taskModelHash[id] = model;		// Quick storage of models
        });

        this.addEvents('move');

        console.log('PO.view.gantt_editor.GanttBarPanel.initComponent: Finished');
    },

    /**
     * The user has collapsed a super-task in the GanttTreePanel.
     * We now save the 'c'=closed status using a ]po[ URL.
     * These values will appear in the TaskTreeStore.
     */
    onItemCollapse: function(taskModel) {
        alert('onItemCollapse');
        var me = this;
        var object_id = taskModel.get('id');
        Ext.Ajax.request({
            url: '/intranet/biz-object-tree-open-close.tcl',
            params: { 'object_id': object_id, 'open_p': 'c' }
        });

        me.redraw();
    },

   /**
     * The user has expanded a super-task in the GanttTreePanel.
     * Please see onItemCollapse for further documentation.
     */
    onItemExpand: function(taskModel) {
        alert('onItemExpand');
        var me = this;
        console.log('PO.class.GanttDrawComponent.onItemExpand: ');

        // Remember the new state
        var object_id = taskModel.get('id');
        Ext.Ajax.request({
            url: '/intranet/biz-object-tree-open-close.tcl',
            params: { 'object_id': object_id, 'open_p': 'o' }
        });

        me.redraw();
    },

    /**
     * The list of tasks is (finally...) ready to be displayed.
     * We need to wait until this one-time event in in order to
     * set the width of the surface and to perform the first redraw().
     * Write the selection preferences into the SelModel.
     */
    onProjectGridViewReady: function() {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectGridViewReady: Starting');

        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectGridViewReady: Finished');
    },

    onProjectGridSortChange: function(headerContainer, column, direction, eOpts) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectGridSortChange: Starting');
        me.redraw();
        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectGridSortChange: Finished');
    },

    /**
     * The user has right-clicked on a sprite.
     */
    onSpriteRightClick: function(event, sprite) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.onSpriteRightClick: Starting: '+ sprite);
        if (null == sprite) { return; }                     	// Something went completely wrong...

        var className = sprite.model.$className;
        switch(className) {
        case 'PO.model.timesheet.TimesheetTaskDependency': 
            this.onDependencyRightClick(event, sprite);
            break;
        case 'PO.model.project.Project':
            this.onProjectRightClick(event, sprite);
            break;
        default:
            alert('Undefined model class: '+className);
        }
        console.log('PO.view.gantt_editor.GanttBarPanel.onSpriteRightClick: Finished');
    },

    /**
     * The user has right-clicked on a dependency.
     */
    onDependencyRightClick: function(event, sprite) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.onDependencyRightClick: Starting: '+ sprite);
        if (null == sprite) { return; }                     	// Something went completely wrong...
        var dependencyModel = sprite.model;

        // Menu for right-clicking a dependency arrow.
        if (!me.dependencyContextMenu) {
            me.dependencyContextMenu = Ext.create('Ext.menu.Menu', {
                id: 'dependencyContextMenu',
                style: {overflow: 'visible'}, 	// For the Combo popup
                items: [{
                    text: 'Delete Dependency',
                    handler: function() {
                        console.log('dependencyContextMenu.deleteDependency: ');

                        me.taskDependencyStore.remove(dependencyModel);   	// Remove from store
                        dependencyModel.destroy({
                            success: function() {
                                console.log('Dependency destroyed');
                                me.redraw();
                            },
                            failure: function(model, operation) {
                                console.log('Error destroying dependency: '+operation.request.proxy.reader.rawData.message);
                            }
                        });
                    }
                }]
            });
        }
        me.dependencyContextMenu.showAt(event.getXY());
        console.log('PO.view.gantt_editor.GanttBarPanel.onDependencyRightClick: Finished');
    },

    /**
     * The user has right-clicked on a project bar
     */
    onProjectRightClick: function(event, sprite) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectRightClick: '+ sprite);
        if (null == sprite) { return; }                     	// Something went completely wrong...
    },


    /**
     * Deal with a Drag-and-Drop operation
     * and distinguish between the various types.
     */
    onSpriteDnD: function(fromSprite, toSprite, diffPoint) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttBarPanel.onSpriteDnD: Starting: '+
                    fromSprite+' -> '+toSprite+', [' + diffPoint+']');

        if (null == fromSprite) { return; } // Something went completely wrong...
        if (null != toSprite && fromSprite != toSprite) {
            me.onCreateDependency(fromSprite, toSprite);    	// dropped on another sprite - create dependency
        } else {
            me.onProjectMove(fromSprite, diffPoint[0]);    	// Dropped on empty space or on the same bar
        }
        console.log('PO.view.gantt_editor.GanttBarPanel.onSpriteDnD: Finished');
    },

    /**
     * Move the project forward or backward in time.
     * This function is called by onMouseUp as a
     * successful "drop" action of a drag-and-drop.
     */
    onProjectMove: function(projectSprite, xDiff) {
        var me = this;
        var projectModel = projectSprite.model;
        if (!projectModel) return;
        var projectId = projectModel.get('id');
        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectMove: Starting');

        var bBox = me.dndBaseSprite.getBBox();
        var diffTime = Math.floor(1.0 * xDiff * (me.axisEndDate.getTime() - me.axisStartDate.getTime()) / (me.axisEndX - me.axisStartX));

        var startTime = new Date(projectModel.get('start_date')).getTime();
        var endTime = new Date(projectModel.get('end_date')).getTime();

        // Save original start- and end time in non-model variables
        if (!projectModel.orgStartTime) {
            projectModel.orgStartTime = startTime;
            projectModel.orgEndTime = endTime;
        }

        startTime = startTime + diffTime;
        endTime = endTime + diffTime;

        var startDate = new Date(startTime);
        var endDate = new Date(endTime);

        projectModel.set('start_date', startDate.toISOString().substring(0,10));
        projectModel.set('end_date', endDate.toISOString().substring(0,10));

        me.redraw();
        console.log('PO.view.gantt_editor.GanttBarPanel.onProjectMove: Finished');
    },

    /**
     * Create a dependency between two two tasks.
     * This function is called by onMouseUp as a successful 
     * "drop" action if the drop target is another project.
     */
    onCreateDependency: function(fromSprite, toSprite) {
        var me = this;
        var fromTaskModel = fromSprite.model;
        var toTaskModel = toSprite.model;
        if (null == fromTaskModel) return;
        if (null == toTaskModel) return;
        console.log('PO.view.portfolio_planner.PortfolioPlannerTaskPanel.onCreateDependency: Starting: '+fromTaskModel.get('id')+' -> '+toTaskModel.get('id'));

        // Try connecting the two tasks via a task dependency
        var fromTaskId = fromTaskModel.get('task_id');			// String value!
        if (null == fromTaskId) { return; }					// Something went wrong...
        var toTaskId = toTaskModel.get('task_id');			// String value!
        if (null == toTaskId) { return; }					// Something went wrong...

        // Create a new dependency object
        console.log('PO.view.gantt.GanttBarPanel.createDependency: '+fromTaskId+' -> '+toTaskId);
        var dependency = new Ext.create('PO.model.timesheet.TimesheetTaskDependency', {
            task_id_one: fromTaskId,
            task_id_two: toTaskId
        });
        dependency.save({
            success: function(depModel, operation) {
                console.log('PO.view.gantt.GanttBarPanel.createDependency: successfully created dependency');
                
                // Reload the store, because the store gets extra information from the data-source
                me.taskDependencyStore.reload({
                    callback: function(records, operation, result) {
                        console.log('taskDependencyStore.reload');
                        me.redraw();
                    }
                });
            },
            failure: function(depModel, operation) {
                var message = operation.request.scope.reader.jsonData.message;
                Ext.Msg.alert('Error creating dependency', message);
            }
        });
        console.log('PO.view.portfolio_planner.PortfolioPlannerProjectPanel.onCreateDependency: Finished');
    },

    /**
     * Draw all Gantt bars
     */
    redraw: function(a,b,c,d,e) {
        console.log('PO.class.GanttDrawComponent.redraw: Starting');
        var me = this;
        if (undefined === me.surface) { return; }

        var ganttTreeView = me.objectPanel.getView();
        var rootNode = me.objectStore.getRootNode();

        // me.surface.setSize(me.ganttSurfaceWidth, me.surface.height);	// Set the size of the drawing area
        me.surface.removeAll();
        me.drawAxis();                         	// Draw the top axis

        // Iterate through all children of the root node and check if they are visible
        rootNode.cascadeBy(function(model) {
            var viewNode = ganttTreeView.getNode(model);
            if (viewNode == null) { return; }    	// hidden nodes/models don't have a viewNode, so we don't need to draw a bar.
            // if (!model.isVisible()) { return; }
            me.drawProjectBar(model, viewNode);
        });

        // Iterate through all children and draw dependencies
        if (me.preferenceStore.getPreferenceBoolean('show_project_dependencies', true)) {
            rootNode.cascadeBy(function(model) {
                var viewNode = ganttTreeView.getNode(model);
                var dependentTasks = model.get('successors');
                if (dependentTasks instanceof Array) {
                    for (var i = 0, len = dependentTasks.length; i < len; i++) {
                	var depTask = dependentTasks[i];
                	var depNode = me.taskModelHash[depTask];
                	me.drawDependency(model, depNode, model);
                    }
                }
            });
        }
        console.log('PO.class.GanttDrawComponent.redraw: Finished');
    },

    /**
     * Draws a dependency line from one bar to the next one
     */
    drawDependency: function(predecessor, successor, dependencyModel) {
        var me = this;

        if (!predecessor) { 
            console.log('GanttDrawComponent.drawDependency: predecessor is NULL');
            return; 
        }
        if (!successor) { 
            console.log('GanttDrawComponent.drawDependency: successor is NULL');
            return; 
        }

        var from = predecessor.get('id');
        var to = successor.get('id');
        var s = me.arrowheadSize;

        var fromBBox = me.barHash[from];			// We start drawing with the end of the first bar...
        var toBBox = me.barHash[to];			        // .. and draw towards the start of the 2nd bar.
        if (!fromBBox || !toBBox) { return; }

        // Assuming end-to-start dependencies from a earlier task to a later task
        var startX = fromBBox[2];
        var startY = fromBBox[3];
        var endX = toBBox[0];
        var endY = toBBox[1];

        // Color: Arrows are black if dependencies are OK, or red otherwise
        var color = '#222';
        if (endX < startX) { color = 'red'; }

        // Set the vertical start point to Correct the start/end Y position
        // and the direction of the arrow head
        var sDirected = null;
        if (endY > startY) {
            // startY = startY + me.barHeight;
            sDirected = -s;            // Draw "normal" arrowhead pointing downwards
            startY = startY - 2;
            endY = endY + 0;
        } else {
            startY = startY - me.barHeight + 4;
            endY = endY + me.barHeight - 2;
            sDirected = +s;            // Draw arrowhead pointing upward
        }

        // Draw the arrow head (filled)
        var arrowHead = me.surface.add({
            type: 'path',
            stroke: color,
            fill: color,
            'stroke-width': 0.5,
            path: 'M '+ (endX)   + ',' + (endY)            // point of arrow head
                + 'L '+ (endX-s) + ',' + (endY + sDirected)
                + 'L '+ (endX+s) + ',' + (endY + sDirected)
                + 'L '+ (endX)   + ',' + (endY)
        }).show(true);
        arrowHead.model = dependencyModel;

        // Draw the main connection line between start and end.
        var arrowLine = me.surface.add({
            type: 'path',
            stroke: color,
            'shape-rendering': 'crispy-edges',
            'stroke-width': 0.5,
            path: 'M '+ (startX) + ',' + (startY)
                + 'L '+ (startX) + ',' + (startY - sDirected)
                + 'L '+ (endX)   + ',' + (endY + sDirected * 2)
                + 'L '+ (endX)   + ',' + (endY + sDirected)
        }).show(true);
        arrowLine.model = dependencyModel;

        // Add a tool tip to the dependency
        var html = "<b>Project Dependency</b>:<br>" +
            "From task <a href='/intranet/projects/view?project_id=" + dependencyModel.get('task_id_one') + "' target='_blank'>" + dependencyModel.get('task_one_name') + "</a> of " +
            "project <a href='/intranet/projects/view?project_id=" + dependencyModel.get('main_project_id_one') + "' target='_blank'>" + dependencyModel.get('main_project_name_one') + "</a> to " +
            "task <a href='/intranet/projects/view?project_id=" + dependencyModel.get('task_id_two') + "' target='_blank'>" + dependencyModel.get('task_two_name') + "</a> of " +
            "project <a href='/intranet/projects/view?project_id=" + dependencyModel.get('main_project_id_two') + "' target='_blank'>" + dependencyModel.get('main_project_name_two') + "</a>";
        var tip1 = Ext.create("Ext.tip.ToolTip", { target: arrowHead.el, width: 250, html: html, hideDelay: 1000 }); // give 1 second to click on project link
        var tip2 = Ext.create("Ext.tip.ToolTip", { target: arrowLine.el, width: 250, html: html, hideDelay: 1000 });
        console.log('PO.view.portfolio_planner.PortfolioPlannerProjectPanel.drawTaskDependency: Finished');


        return;


        // Draw the main connection line between start and end.
        var line = me.surface.add({
            type: 'path',
            stroke: '#444',
            'shape-rendering': 'crispy-edges',
            'stroke-width': 0.5,
            path: 'M '+ (startX) + ',' + (startY)
                + 'L '+ (endX+s)   + ',' + (startY)
                + 'L '+ (endX+s)   + ',' + (endY)
        }).show(true);


        if (endY > startY) {
            // Draw "normal" arrowhead pointing downwards
            var arrowHead = me.surface.add({
                type: 'path',
                stroke: '#444',
                fill: '#444',
                'stroke-width': 0.5,
                path: 'M '+ (endX+s)   + ',' + (endY)
                    + 'L '+ (endX-s+s) + ',' + (endY-s)
                    + 'L '+ (endX+2*s) + ',' + (endY-s)
                    + 'L '+ (endX+s)   + ',' + (endY)
            }).show(true);
        } else {
            // Draw arrowhead pointing upward
            var arrowHead = me.surface.add({
                type: 'path',
                stroke: '#444',
                fill: '#444',
                'stroke-width': 0.5,
                path: 'M '+ (endX+s)   + ',' + (endY)
                    + 'L '+ (endX-s+s) + ',' + (endY+s)				// +s here on the Y coordinate, so that the arrow...
                    + 'L '+ (endX+2*s) + ',' + (endY+s)				// .. points from bottom up.
                    + 'L '+ (endX+s)   + ',' + (endY)
            }).show(true);
        }
    },

    /**
     * Draw a single bar for a project or task
     */
    drawProjectBar: function(project) {
        var me = this;
        var surface = me.surface;
        var project_name = project.get('project_name');
        var start_date = project.get('start_date');
	start_date = start_date.substring(0,10);
        var end_date = project.get('end_date');
	end_date = end_date.substring(0,10);
        var predecessors = project.get('predecessors');
        var assignees = project.get('assignees');                               // Array of {id,percent,name,email,initials}
        var startTime = new Date(start_date).getTime();
        var endTime = new Date(end_date).getTime() + 1000.0 * 3600 * 24;	// plus one day

        if (me.debug) { console.log('PO.view.gantt_editor.GanttBarPanel.drawProjectBar: project_name='+project_name+', start_date='+start_date+", end_date="+end_date); }

        // Calculate the other coordinates
        var x = me.date2x(startTime);
        var y = me.calcGanttBarYPosition(project);
        var w = Math.floor(me.ganttSurfaceWidth * (endTime - startTime) / (me.axisEndDate.getTime() - me.axisStartDate.getTime()));
        var h = me.ganttBarHeight;						// Height of the bars
        var d = Math.floor(h / 2.0) + 1;					// Size of the indent of the super-project bar


        if (!project.hasChildNodes()) {
            var spriteBar = surface.add({
                type: 'rect', x: x, y: y, width: w, height: h, radius: 3,
                fill: 'url(#gradientId)',
                stroke: 'blue',
                'stroke-width': 0.3,
                listeners: {							// Highlight the sprite on mouse-over
                    mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 2.0}}); },
                    mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
                }
            }).show(true);
        } else {
            var spriteBar = surface.add({
                type: 'path',
                stroke: 'blue',
                'stroke-width': 0.3,
                fill: 'url(#gradientId)',
                path: 'M '+ x + ',' + y
                    + 'L '+ (x+width) + ',' + (y)
                    + 'L '+ (x+width) + ',' + (y+h)
                    + 'L '+ (x+width-d) + ',' + (y+h-d)
                    + 'L '+ (x+d) + ',' + (y+h-d)
                    + 'L '+ (x) + ',' + (y+h)
                    + 'L '+ (x) + ',' + (y),
                listeners: {						// Highlight the sprite on mouse-over
                    mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 2.0}}); },
                    mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
                }
            }).show(true);
        }
        spriteBar.model = project;					// Store the task information for the sprite

        // Convert assignment information into a string
	// and write behind the Gantt bar
        var text = "";
	if ("" != assignees) {
            assignees.forEach(function(assignee) {
		if (0 == assignee.percent) { return; }			// Don't show empty assignments
		if ("" != text) { text = text + ', '; }
		text = text + assignee.initials;
		if (100 != assignee.percent) {
                    text = text + '['+assignee.percent+'%]';
		}
            });
            var axisText = surface.add({type:'text', text:text, x:x+w+2, y:y+d, fill:'#000', font:"10px Arial"}).show(true);
	}

        // Store the start and end points of the bar
        var id = project.get('id');
        me.barHash[id] = [x,y,x+w,y+h];                                  // Move the start of the bar 5px to the right
    },

    onTaskDependencyStoreChange: function() {
        console.log('PO.view.portfolio_planner.PortfolioPlannerProjectPanel.onTaskDependencyStoreChange: Starting/Finished');
    }
});



/**
 * Launch the actual editor
 * This function is called from the Store Coordinator
 * after all essential data have been loaded into the
 * browser.
 */
function launchGanttEditor(){

    var taskTreeStore = Ext.StoreManager.get('taskTreeStore');
    var senchaPreferenceStore = Ext.StoreManager.get('senchaPreferenceStore');
    var taskDependencyStore = Ext.StoreManager.get('timesheetTaskDependencyStore');

    /* ***********************************************************************
     * Help Menu
     *********************************************************************** */
    var helpMenu = Ext.create('PO.view.menu.HelpMenu', {
        id: 'helpMenu',
        style: {overflow: 'visible'},					// For the Combo popup
        store: Ext.create('Ext.data.Store', { fields: ['text', 'url'], data: [
            {text: 'Gantt Editor Home', url: 'http://www.project-open.com/en/page_intranet_gantt_editor_index'},
            {text: '-'},
            {text: 'Only Text'},
            {text: 'Google', url: 'http://www.google.com'}
        ]})
    });

    /* ***********************************************************************
     * Alpha Menu
     *********************************************************************** */

    var alphaMenu = Ext.create('PO.view.menu.AlphaMenu', {
        id: 'alphaMenu',
        style: {overflow: 'visible'},					// For the Combo popup
        slaId: 1478943					                // ID of the ]po[ "PD Gantt Editor" project
    });

    /* ***********************************************************************
     * Config Menu
     *********************************************************************** */

    var configMenuOnItemCheck = function(item, checked){
        console.log('configMenuOnItemCheck: item.id='+item.id);
        senchaPreferenceStore.setPreference('@page_url@', item.id, checked);
        portfolioPlannerProjectPanel.redraw();
        portfolioPlannerCostCenterPanel.redraw();
    }

    var configMenu = Ext.create('Ext.menu.Menu', {
        id: 'configMenu',
        style: {overflow: 'visible'},     // For the Combo popup
        items: [{
                text: 'Reset Configuration',
                handler: function() {
                    console.log('configMenuOnResetConfiguration');
                    senchaPreferenceStore.each(function(model) {
                        var url = model.get('preference_url');
                        if (url != '@page_url@') { return; }
                        model.destroy();
                    });
                    // Reset column configuration
                    projectGridColumnConfig.each(function(model) { 
                	model.destroy({
                	    success: function(model) {
                		console.log('configMenuOnResetConfiguration: Successfully destroyed a CC config');
                		var count = projectGridColumnConfig.count() + costCenterGridColumnConfig.count();
                		if (0 == count) {
                		    // Reload the page. 
                		    var params = Ext.urlDecode(location.search.substring(1));
                		    var url = window.location.pathname + '?' + Ext.Object.toQueryString(params);
                		    window.location = url;
                		}
                	    }
                	}); 
                    });
                    costCenterGridColumnConfig.each(function(model) { 
                	model.destroy({
                	    success: function(model) {
                		console.log('configMenuOnResetConfiguration: Successfully destroyed a CC config');
                		var count = projectGridColumnConfig.count() + costCenterGridColumnConfig.count();
                		if (0 == count) {
                		    // Reload the page. 
                		    var params = Ext.urlDecode(location.search.substring(1));
                		    var url = window.location.pathname + '?' + Ext.Object.toQueryString(params);
                		    window.location = url;
                		}
                	    }
                	}); 
                    });
                }
        }, '-']
    });

    // Setup the configMenu items
    var confSetupStore = Ext.create('Ext.data.Store', {
        fields: ['key', 'text', 'def'],
        data : [
            {key: 'show_project_dependencies', text: 'Show Project Dependencies', def: true},
            {key: 'show_project_resource_load', text: 'Show Project Assigned Resources', def: true},
            {key: 'show_dept_assigned_resources', text: 'Show Department Assigned Resources', def: true},
            {key: 'show_dept_available_resources', text: 'Show Department Available Resources', def: false},
            {key: 'show_dept_percent_work_load', text: 'Show Department % Work Load', def: true},
            {key: 'show_dept_accumulated_overload', text: 'Show Department Accumulated Overload', def: false}
        ]
    });
    confSetupStore.each(function(model) {
        var key = model.get('key');
        var def = model.get('def');
        var checked = senchaPreferenceStore.getPreferenceBoolean(key, def);
        if (!senchaPreferenceStore.existsPreference(key)) {
            senchaPreferenceStore.setPreference('@page_url@', key, checked ? 'true' : 'false');
        }
        var item = Ext.create('Ext.menu.CheckItem', {
            id: key,
            text: model.get('text'),
            checked: checked,
            checkHandler: configMenuOnItemCheck
        });
        configMenu.add(item);
    });


    /**
     * GanttButtonPanel
     */
    Ext.define('PO.view.gantt_editor.GanttButtonPanel', {
        extend: 'Ext.panel.Panel',
        alias: 'ganttButtonPanel',
        width: 900,
        height: 500,
        layout: 'border',
        defaults: {
            collapsible: true,
            split: true,
            bodyPadding: 0
        },
        tbar: [
            {
                text: 'OK',
                icon: '/intranet/images/navbar_default/disk.png',
                tooltip: 'Save the project to the ]po[ back-end',
                id: 'buttonSave'
            }, {
                icon: '/intranet/images/navbar_default/folder_go.png',
                tooltip: 'Load a project from he ]po[ back-end',
                id: 'buttonLoad'
            }, {
                xtype: 'tbseparator' 
            }, {
                icon: '/intranet/images/navbar_default/add.png',
                tooltip: 'Add a new task',
                id: 'buttonAdd'
            }, {
                icon: '/intranet/images/navbar_default/delete.png',
                tooltip: 'Delete a task',
                id: 'buttonDelete'
            }, {
                xtype: 'tbseparator' 
            }, {
                icon: '/intranet/images/navbar_default/arrow_left.png',
                tooltip: 'Reduce Indent',
                id: 'buttonReduceIndent'
            }, {
                icon: '/intranet/images/navbar_default/arrow_right.png',
                tooltip: 'Increase Indent',
                id: 'buttonIncreaseIndent'
            }, {
                xtype: 'tbseparator'
            }, {
                icon: '/intranet/images/navbar_default/link_add.png',
                tooltip: 'Add dependency',
                id: 'buttonAddDependency'
            }, {
                icon: '/intranet/images/navbar_default/link_break.png',
                tooltip: 'Break dependency',
                id: 'buttonBreakDependency'
            }, '->' , {
                icon: '/intranet/images/navbar_default/zoom_in.png',
                tooltip: 'Zoom in time axis',
                id: 'buttonZoomIn'
            }, {
                icon: '/intranet/images/navbar_default/zoom_out.png',
                tooltip: 'Zoom out of time axis',
                id: 'buttonZoomOut'
            }, {
                text: 'Configuration',
                icon: '/intranet/images/navbar_default/wrench.png',
                menu: configMenu
            }, {
                text: 'Help',
                icon: '/intranet/images/navbar_default/help.png',
                menu: helpMenu
            }, {
                text: 'This is Alpha!',
                icon: '/intranet/images/navbar_default/bug.png',
                menu: alphaMenu
            }
        ]
    });

    /*
     * GanttButtonController
     * This controller is only responsible for button actions
     */
    Ext.define('PO.controller.gantt_editor.GanttButtonController', {
        extend: 'Ext.app.Controller',

        // Variables
        debug: false,
        'ganttTreePanel': null,
        'ganttBarPanel': null,

        refs: [
            { ref: 'ganttTreePanel', selector: '#ganttTreePanel' }
        ],
        
        init: function() {
            var me = this;
            if (me.debug) { console.log('PO.controller.gantt_editor.GanttButtonController: init'); }

            this.control({
                '#buttonLoad': { click: this.onButtonLoad },
                '#buttonSave': { click: this.onButtonSave },
                '#buttonAdd': { click: { fn: me.ganttTreePanel.onButtonAdd, scope: me.ganttTreePanel }},
                '#buttonDelete': { click: { fn: me.ganttTreePanel.onButtonDelete, scope: me.ganttTreePanel }},
                '#buttonReduceIndent': { click: { fn: me.ganttTreePanel.onButtonReduceIndent, scope: me.ganttTreePanel }},
                '#buttonIncreaseIndent': { click: { fn: me.ganttTreePanel.onButtonIncreaseIndent, scope: me.ganttTreePanel }},
                '#buttonAddDependency': { click: this.onButton },
                '#buttonBreakDependency': { click: this.onButton },
                '#buttonZoomIn': { click: this.onZoomIn },
                '#buttonZoomOut': { click: this.onZoomOut },
                '#buttonSettings': { click: this.onButton },
                scope: me.ganttTreePanel
            });

            // Listen to changes in the selction model in order to enable/disable the "delete" button.
            me.ganttTreePanel.on('selectionchange', this.onTreePanelSelectionChange, this);

            // Listen to a click into the empty space below the tree in order to add a new task
            me.ganttTreePanel.on('containerclick', me.ganttTreePanel.onContainerClick, me.ganttTreePanel);

            // Listen to special keys
            me.ganttTreePanel.on('cellkeydown', this.onCellKeyDown, me.ganttTreePanel);
            me.ganttTreePanel.on('beforecellkeydown', this.onBeforeCellKeyDown, me.ganttTreePanel);

            return this;
        },

        onButtonLoad: function() {
            console.log('GanttButtonController.ButtonLoad');
        },

        onButtonSave: function() {
            console.log('GanttButtonController.ButtonSave');
            
        },

        onZoomIn: function() {
            console.log('GanttButtonController.onZoomIn');
            this.ganttBarPanel.onZoomIn();
        },

        onZoomOut: function() {
            console.log('GanttButtonController.onZoomOut');
            this.ganttBarPanel.onZoomOut();
        },

        /**
         * Control the enabled/disabled status of the (-) (Delete) button
         */
        onTreePanelSelectionChange: function(view, records) {
            if (this.debug) { console.log('GanttButtonController.onTreePanelSelectionChange'); }
            var buttonDelete = Ext.getCmp('buttonDelete');

            if (1 == records.length) {            // Exactly one record enabled
                var record = records[0];
                buttonDelete.setDisabled(!record.isLeaf());
            } else {                              // Zero or two or more records enabled
                buttonDelete.setDisabled(true);
            }
        },

        /**
         * Disable default tree key actions
         */
        onBeforeCellKeyDown: function(me, htmlTd, cellIndex, record, htmlTr, rowIndex, e, eOpts ) {
            var keyCode = e.getKey();
            var keyCtrl = e.ctrlKey;
            if (this.debug) { console.log('GanttButtonController.onBeforeCellKeyDown: code='+keyCode+', ctrl='+keyCtrl); }
            var panel = this;
            switch (keyCode) {
            case 8: 				// backspace 8
                panel.onButtonDelete();
                break;
            case 37: 				// cursor left
                if (keyCtrl) {
                    panel.onButtonReduceIndent();
                    return false;                   // Disable default action (fold tree)
                }
                break;
            case 39: 				// cursor right
                if (keyCtrl) {
                    panel.onButtonIncreaseIndent();
                    return false;                   // Disable default action (unfold tree)
                }
                break;
            case 45: 				// insert 45
                panel.onButtonAdd();
                break;
            case 46: 				// delete 46
                panel.onButtonDelete();
                break;
            }

            return true;                            // Enable default TreePanel actions for keys
        },

        /**
         * Handle various key actions
         */
        onCellKeyDown: function(table, htmlTd, cellIndex, record, htmlTr, rowIndex, e, eOpts) {
            var keyCode = e.getKey();
            var keyCtrl = e.ctrlKey;
            // console.log('GanttButtonController.onCellKeyDown: code='+keyCode+', ctrl='+keyCtrl);
        }
    });

    /*
     * GanttResizeController
     * This controller is only responsible for editor geometry and resizing:
     * <ul>
     * <li>The boundaries of the outer window
     * <li>The separator between the treePanel and the ganttPanel
     * </ul>
     */
    Ext.define('PO.controller.gantt_editor.GanttResizeController', {
        extend: 'Ext.app.Controller',

        debug: false,
        'ganttButtonPanel': null,			// Defined during initialization
        'ganttTreePanel': null,				// Defined during initialization
        'ganttBarPanel': null,				// Defined during initialization

        refs: [
            { ref: 'ganttTreePanel', selector: '#ganttTreePanel' }
        ],
        
        init: function() {
            var me = this;
            if (me.debug) { console.log('PO.controller.gantt_editor.GanttResizeController: init'); }

            var sideBarTab = Ext.get('sideBarTab');	    // ]po[ side-bar collapses the left-hand menu
            sideBarTab.on('click', me.onSideBarResize, me);	    // Handle collapsable side menu
            Ext.EventManager.onWindowResize(me.onWindowResize, me);    	    // Deal with resizing the main window
            me.ganttButtonPanel.on('resize', me.onGanttButtonPanelResize, me);	    // Deal with resizing the outer boundaries
            return this;
        },

        /**
         * Adapt the size of the ganttButtonPanel (the outer Gantt panel)
         * to the available drawing area.
         * Takes the size of the browser and subtracts the sideBar at the
         * left and the size of the menu on top.
         */
        onResize: function (sideBarWidth) {
            var me = this;
            console.log('PO.controller.gantt_editor.GanttResizeController.onResize: Starting');

            if (undefined === sideBarWidth) {
                sideBarWidth = Ext.get('sidebar').getSize().width;
            }

            var screenSize = Ext.getBody().getViewSize();
            var width = screenSize.width - sideBarWidth - 100;
            var height = screenSize.height - 280;

            me.ganttButtonPanel.setSize(width, height);

            console.log('PO.controller.gantt_editor.GanttResizeController.onResize: Finished');
        },

        /**
         * Clicked on the ]po[ "side menu" bar for showing/hiding the left-menu
         */
        onSideBarResize: function () {
            var me = this;
            console.log('PO.controller.gantt_editor.GanttResizeController.onSidebarResize: Starting');
            var sideBar = Ext.get('sidebar');                               // ]po[ left side bar component
            var sideBarWidth = sideBar.getSize().width;
            // We get the event _before_ the sideBar has changed it's size.
            // So we actually need to the the oposite of the sidebar size:
            if (sideBarWidth > 100) {
                sideBarWidth = 2;                                          // Determines size when Sidebar collapsed
            } else {
                sideBarWidth = 245;                                         // Determines size when Sidebar visible
            }
            me.onResize(sideBarWidth);
            console.log('PO.controller.gantt_editor.GanttResizeController.onSidebarResize: Finished');
        },

        onWindowResize: function () {
            var me = this;
            console.log('PO.controller.gantt_editor.GanttResizeController.onWindowResize: Starting');
            var sideBar = Ext.get('sidebar');                               // ]po[ left side bar component
            var sideBarWidth = sideBar.getSize().width;
            if (sideBarWidth > 100) {
                sideBarWidth = 340;                                         // Determines size when Sidebar visible
            } else {
                sideBarWidth = 85;                                          // Determines size when Sidebar collapsed
            }
            me.onResize(sideBarWidth);
            console.log('PO.controller.gantt_editor.GanttResizeController.onWindowResize: Finished');
        },
        
        /**
         * Manually changed the size of the ganttButtonPanel
         */
        onGanttButtonPanelResize: function () {
            var me = this;
            console.log('PO.controller.gantt_editor.GanttResizeController.onGanttButtonPanelResize: Starting');
            me.ganttBarPanel.redraw();
            console.log('PO.controller.gantt_editor.GanttResizeController.onGanttButtonPanelResize: Finished');
        }
    });

    // Left-hand side task tree
    var ganttTreePanel = Ext.create('PO.view.gantt.GanttTreePanel', {
        width:		800,
        region:		'west',
        store:		taskTreeStore
    });

    // Right-hand side Gantt display
    var ganttBarPanel = Ext.create('PO.view.gantt_editor.GanttBarPanel', {
        region: 'center',
        viewBox: false,
        width: 300,
        height: 300,

        overflowX: 'scroll',                            // Allows for horizontal scrolling, but not vertical
        scrollFlags: {x: true},

        objectPanel: ganttTreePanel,
        objectStore: taskTreeStore,
        taskDependencyStore: taskDependencyStore,
        preferenceStore: senchaPreferenceStore,

        reportStartDate: new Date('@report_start_date@'),
        reportEndDate: new Date('@report_end_date@'),

        gradients: [
            {id:'gradientId', angle:66, stops:{0:{color:'#cdf'}, 100:{color:'#ace'}}}, 
            {id:'gradientId2', angle:0, stops:{0:{color:'#590'}, 20:{color:'#599'}, 100:{color:'#ddd'}}}
        ]
    });

    // Outer Gantt editor jointing the two parts (TreePanel + Draw)
    var ganttButtonPanel = Ext.create('PO.view.gantt_editor.GanttButtonPanel', {
        resizable: true,				// Add handles to the panel, so the user can change size
        items: [
            ganttTreePanel,
            ganttBarPanel
        ],
        renderTo: '@gantt_editor_id@'
    });

    var ganttButtonController = Ext.create('PO.controller.gantt_editor.GanttButtonController', {
        'ganttButtonPanel': ganttButtonPanel,
        'ganttTreePanel': ganttTreePanel,
        'ganttBarPanel': ganttBarPanel
    });
    ganttButtonController.init(this).onLaunch(this);

    // 
    var ganttResizeController = Ext.create('PO.controller.gantt_editor.GanttResizeController', {
        'ganttButtonPanel': ganttButtonPanel,
        'ganttTreePanel': ganttTreePanel,
        'ganttBarPanel': ganttBarPanel
    });
    ganttResizeController.init(this).onLaunch(this);
    ganttResizeController.onResize();    // Set the size of the outer GanttButton Panel

};


/**
 * onReady() - Launch the application
 * Uses StoreCoordinator to load essential data
 * before clling launchGanttEditor() to start the
 * actual applicaiton.
 */
Ext.onReady(function() {
    Ext.QuickTips.init();                                                       // No idea why this is necessary, but it is...

    var taskTreeStore = Ext.create('PO.store.timesheet.TaskTreeStore');
    var senchaPreferenceStore = Ext.create('PO.store.user.SenchaPreferenceStore');
    var taskDependencyStore = Ext.create('PO.store.timesheet.TimesheetTaskDependencyStore');
    var taskStatusStore = Ext.create('PO.store.timesheet.TaskStatusStore');

    // Store Coodinator starts app after all stores have been loaded:
    var coordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
        stores: [
            'taskTreeStore',
            'taskStatusStore',
            'senchaPreferenceStore'
        ],
        listeners: {
            load: function() {
                if ("boolean" == typeof this.loadedP) { return; }        	// Check if the application was launched before
                launchGanttEditor();                                     	// Launch the actual application.
                this.loadedP = true;                                     	// Mark the application as launched
            }
        }
    });

    // Load stores that need parameters
    taskTreeStore.getProxy().extraParams = { project_id: @project_id@ };
    taskTreeStore.load({
        callback: function() {
            console.log('PO.store.timesheet.TaskTreeStore: loaded');
        }
    });

    // User preferences
    senchaPreferenceStore.load({                                         	// Preferences for the GanttEditor
        callback: function() {
            console.log('PO.store.user.SenchaPreferenceStore: loaded');
        }
    });

    // Load dependencies between tasks
    taskDependencyStore.getProxy().url = '/intranet-reporting/view';
    taskDependencyStore.getProxy().extraParams = { 
        format: 'json', 
        report_code: 'rest_intra_project_task_dependencies',
        project_id: @project_id@
    };
    taskDependencyStore.load();

});
</script>
</div>

