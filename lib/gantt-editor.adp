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
    'PO.model.timesheet.TimesheetTask',
    'PO.controller.StoreLoadCoordinator',
    'PO.store.project.ProjectStatusStore',
    'PO.store.timesheet.TaskTreeStore',
    'PO.view.gantt.AbstractGanttPanel'
]);


/**
 * Like a chart Series, displays a list of projects
 * using Gantt bars.
 */
Ext.define('PO.view.gantt_editor.GanttTaskPanel', {
    extend: 'PO.view.gantt.AbstractGanttPanel',

    requires: [
	'PO.view.gantt.AbstractGanttPanel',
        'Ext.draw.Component',
        'Ext.draw.Surface',
        'Ext.layout.component.Draw'
    ],

    // Really Necessary???
    projectResourceLoadStore: null,
    costCenterResourceLoadStore: null,				// Reference to cost center store, set during init
    taskDependencyStore: null,				// Reference to cost center store, set during init
    skipGridSelectionChange: false,				// Temporaritly disable updates
    dependencyContextMenu: null,
    preferenceStore: null,

    /**
     * Starts the main editor panel as the right-hand side
     * of a project grid and a cost center grid for the departments
     * of the resources used in the projects.
     */
    initComponent: function() {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.initComponent: Starting');
        this.callParent(arguments);

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
            'selectionchange': me.onProjectGridSelectionChange,
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
        console.log('PO.view.gantt_editor.GanttTaskPanel.initComponent: Finished');
    },

    /**
     * The user has collapsed a super-task in the GanttTreePanel.
     * We now save the 'c'=closed status using a ]po[ URL.
     * These values will appear in the TaskTreeStore.
     */
    onItemCollapse: function(taskModel) {
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
     * The list of projects is (finally...) ready to be displayed.
     * We need to wait until this one-time event in in order to
     * set the width of the surface and to perform the first redraw().
     * Write the selection preferences into the SelModel.
     */
    onProjectGridViewReady: function() {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectGridViewReady: Starting');
        var selModel = me.objectPanel.getSelectionModel();

        var atLeastOneProjectSelected = false
        me.objectStore.each(function(model) {
            var projectId = model.get('project_id');
            var sel = me.preferenceStore.getPreferenceBoolean('project_selected.' + projectId, true);
            if (sel) {
                me.skipGridSelectionChange = true;
                selModel.select(model, true);
                me.skipGridSelectionChange = false;
                atLeastOneProjectSelected = true;
            }
        });

        if (!atLeastOneProjectSelected) {
            // This will also update the preferences(??)
            selModel.selectAll(true);
        }

        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectGridViewReady: Finished');
    },

    onProjectGridSortChange: function(headerContainer, column, direction, eOpts) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectGridSortChange: Starting');
        me.redraw();
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectGridSortChange: Finished');
    },

    onProjectGridSelectionChange: function(selModel, models, eOpts) {
        var me = this;
        if (me.skipGridSelectionChange) { return; }
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectGridSelectionChange: Starting');

        me.objectStore.each(function(model) {
            var projectId = model.get('project_id');
            var prefSelected = me.preferenceStore.getPreferenceBoolean('project_selected.' + projectId, true);
            if (selModel.isSelected(model)) {
                model.set('projectGridSelected', 1);
                if (!prefSelected) {
                    me.preferenceStore.setPreference('@page_url@', 'project_selected.' + projectId, 'true');
                }
            } else {
                model.set('projectGridSelected', 0);
                if (prefSelected) {
                    me.preferenceStore.setPreference('@page_url@', 'project_selected.' + projectId, 'false');
                }
            }
        });

        // Reload the Cost Center Resource Load Store with the new selected/changed projects
        me.costCenterResourceLoadStore.loadWithProjectData(me.objectStore, me.preferenceStore);

        me.redraw();
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectGridSelectionChange: Finished');
    },


    /**
     * The user has right-clicked on a sprite.
     */
    onSpriteRightClick: function(event, sprite) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.onSpriteRightClick: Starting: '+ sprite);
        if (null == sprite) { return; }                             // Something went completely wrong...

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
        console.log('PO.view.gantt_editor.GanttTaskPanel.onSpriteRightClick: Finished');
    },

    /**
     * The user has right-clicked on a dependency.
     */
    onDependencyRightClick: function(event, sprite) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.onDependencyRightClick: Starting: '+ sprite);
        if (null == sprite) { return; }                             // Something went completely wrong...
        var dependencyModel = sprite.model;

        // Menu for right-clicking a dependency arrow.
        if (!me.dependencyContextMenu) {
            me.dependencyContextMenu = Ext.create('Ext.menu.Menu', {
                id: 'dependencyContextMenu',
                style: {overflow: 'visible'},     // For the Combo popup
                items: [{
                    text: 'Delete Dependency',
                    handler: function() {
                        console.log('dependencyContextMenu.deleteDependency: ');

                        me.taskDependencyStore.remove(dependencyModel);           // Remove from store
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
        console.log('PO.view.gantt_editor.GanttTaskPanel.onDependencyRightClick: Finished');
    },

    /**
     * The user has right-clicked on a project bar
     */
    onProjectRightClick: function(event, sprite) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectRightClick: '+ sprite);
        if (null == sprite) { return; }                             // Something went completely wrong...
    },


    /**
     * Deal with a Drag-and-Drop operation
     * and distinguish between the various types.
     */
    onSpriteDnD: function(fromSprite, toSprite, diffPoint) {
        var me = this;
        console.log('PO.view.gantt_editor.GanttTaskPanel.onSpriteDnD: Starting: '+
                    fromSprite+' -> '+toSprite+', [' + diffPoint+']');

        if (null == fromSprite) { return; } // Something went completely wrong...
        if (null != toSprite && fromSprite != toSprite) {
            me.onCreateDependency(fromSprite, toSprite);            // dropped on another sprite - create dependency
        } else {
            me.onProjectMove(fromSprite, diffPoint[0]);            // Dropped on empty space or on the same bar
        }
        console.log('PO.view.gantt_editor.GanttTaskPanel.onSpriteDnD: Finished');
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
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectMove: Starting');

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
        console.log('PO.view.gantt_editor.GanttTaskPanel.onProjectMove: Finished');
    },

    /**
     * Draw all Gantt bars
     */
    redraw: function(a,b,c,d,e) {
        console.log('PO.class.GanttDrawComponent.redraw: Starting');
        var me = this;
        if (undefined === me.surface) { return; }

        var ganttTreeStore = me.ganttTreePanel.store;
        var ganttTreeView = me.ganttTreePanel.getView();
        var rootNode = ganttTreeStore.getRootNode();

        me.surface.removeAll();
        // me.surface.setSize(me.ganttSurfaceWidth, me.surface.height);	// Set the size of the drawing area
        me.drawAxis();        // Draw the top axis

        // Iterate through all children of the root node and check if they are visible
        rootNode.cascadeBy(function(model) {
            var viewNode = ganttTreeView.getNode(model);

            // hidden nodes/models don't have a viewNode, so we don't need to draw a bar.
            if (viewNode == null) { return; }
            if (!model.isVisible()) { return; }
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
			me.drawDependency(model, depNode);
                    }
		}
            });
	}
        console.log('PO.class.GanttDrawComponent.redraw: Finished');
    },

    /**
     * Draws a dependency line from one bar to the next one
     */
    drawDependency: function(predecessor, successor) {
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

        var startPoint = me.barEndHash[from];             // We start drawing with the end of the first bar...
        var endPoint = me.barStartHash[to];               // .. and draw towards the start of the 2nd bar.
        if (!startPoint || !endPoint) { return; }
        // console.log('Dependency: '+from+' -> '+to+': '+startPoint+' -> '+endPoint);

        // Point arithmetics
        var startX = startPoint[0];
        var startY = startPoint[1];
        var endX = endPoint[0];
        var endY = endPoint[1];
        startY = startY - (me.barHeight/2);   // Start off in the middle of the first bar
        if (endY < startY) {                  // Drawing from a lower bar to a bar further up
            endY = endY + me.barHeight;       // Draw to the bottom of the bar
        }

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
                    + 'L '+ (endX-s+s) + ',' + (endY+s)     // +s here on the Y coordinate, so that the arrow...
                    + 'L '+ (endX+2*s) + ',' + (endY+s)     // .. points from bottom up.
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
        var start_date = project.get('start_date').substring(0,10);
        var end_date = project.get('end_date').substring(0,10);
        var startTime = new Date(start_date).getTime();
        var endTime = new Date(end_date).getTime() + 1000.0 * 3600 * 24;	// plus one day

        if (me.debug) { console.log('PO.view.gantt_editor.GanttTaskPanel.drawProjectBar: project_name='+project_name+', start_date='+start_date+", end_date="+end_date); }

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
                listeners: {						// Highlight the sprite on mouse-over
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
        spriteBar.model = project;                                      // Store the task information for the sprite

        // Store the start and end points of the bar
        var id = project.get('id');
        me.barStartHash[id] = [x,y];                                  // Move the start of the bar 5px to the right
        me.barEndHash[id] = [x+w, y+h];                             // End of the bar is in the middle of the bar

        // Draw availability percentage
        if (me.preferenceStore.getPreferenceBoolean('show_project_resource_load', true)) {
            var assignedDays = project.get('assigned_days');
            var colorConf = 'blue';
            var template = new Ext.Template("<div><b>Project Assignment</b>:<br>There are {value} resources assigned to project '{project_name}' and it's subprojects between {startDate} and {endDate}.<br></div>");
            me.graphOnGanttBar(spriteBar, project, assignedDays, null, new Date(startTime), colorConf, template);
        }
        if (me.debug) { console.log('PO.view.gantt_editor.GanttTaskPanel.drawProjectBar: Finished'); }
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



    /* ***********************************************************************
     * Help Menu
     *********************************************************************** */
    var helpMenu = Ext.create('Ext.menu.Menu', {
        id: 'helpMenu',
        style: {overflow: 'visible'},     // For the Combo popup
        items: [{
            text: 'Portfolio Editor Home',
            href: 'http://www.project-open.org/en/page_intranet_portfolio_planner_index',
            hrefTarget: '_blank'
        }, '-', {
            text: 'Configuration',
            href: 'http://www.project-open.org/en/page_intranet_portfolio_planner_index#configuration',
            hrefTarget: '_blank'
        }, {
            text: 'Project Dependencies',
            href: 'http://www.project-open.org/en/page_intranet_portfolio_planner_index#dependencies',
            hrefTarget: '_blank'
        }, {
            text: 'Column Configuration',
            href: 'http://www.project-open.org/en/page_intranet_portfolio_planner_index#column_configuration',
            hrefTarget: '_blank'
        }]
    });
  

    /* ***********************************************************************
     * Alpha Menu
     *********************************************************************** */
    var betaMenu = Ext.create('Ext.menu.Menu', {
        id: 'betaMenu',
        style: {overflow: 'visible'},     // For the Combo popup
        items: [{
            text: '<b>This is Experimental and "Alpha" Software</b> - Please see known issues below',
            href: 'http://www.project-open.org/en/page_intranet_portfolio_planner_index',
            hrefTarget: '_blank'
        }, '-']
    });
    
    var issues = [
        "Bug: Show red dependency arrows if somebody disables a referenced project",
        "Ext: Show Save only if something has changed (project store)",
        "Bug: Firefox doesn't show cost centers when the ExtJS page is longer than the browser page",
        "Bug: Don't show SLAs and similar projects",
        "Ext: Exclude certain other (small) projects? How?",
        "Ext: Allow some form of left/right scrolling. Arrow in date bar?",
        "Ext: Should enable/disable change the project status? Or just notify PMs?",
        "Ext: Add Columns: Show sums",
        "Ext: Show departments hierarchy",
        "Ext: Show unassigned users",
        "Ext: Reset Configuration should also reset stored status",
        "Bug: Reset Configuration doesn't work anymore"
    ];
    for (var i = 0; i < issues.length; i++) {
        var item = Ext.create('Ext.menu.Item', {
            text: issues[i]
        });
        betaMenu.add(item);
    }

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
        console.log('confSetupStore: '+model);
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
            menu: betaMenu
	}
    ]
});


    var ganttTreePanel = Ext.create('PO.view.gantt.GanttTreePanel', {
        width:		300,
        region:		'west',
    });

    var ganttDrawComponent = Ext.create('PO.view.gantt.GanttDrawComponent', {
        ganttTreePanel: ganttTreePanel,
        region: 'center',
        viewBox: false,
        gradients: [{
            id: 'gradientId',
            angle: 66,
            stops: {
                0: { color: '#cdf' },
                100: { color: '#ace' }
            }
        }, {
            id: 'gradientId2',
            angle: 0,
            stops: {
                0: { color: '#590' },
                20: { color: '#599' },
                100: { color: '#ddd' }
            }
        }]
    });

    var ganttRightSide = Ext.create('Ext.panel.Panel', {
        title: false,
        layout: 'border',
        region: 'center',
        collapsible: false,
        width: 300,
        height: 300,
        defaults: {                                                  // These defaults produce a bar to resize the timeline
            collapsible: true,
            split: true,
            bodyPadding: 0
        },
        items: [
            ganttDrawComponent
        ]
    });


    // Outer Gantt editor jointing the two parts (TreePanel + Draw)
    var screenSize = Ext.getBody().getViewSize();    // Size calculation based on specific ]po[ layout
    var sideBarSize = Ext.get('sidebar').getSize();
    var width = screenSize.width - sideBarSize.width - 95;
    var height = screenSize.height - 280;
    var ganttEditor = Ext.create('PO.view.gantt_editor.GanttButtonPanel', {
        width: width,
        height: height,
        resizable: true,				// Add handles to the panel, so the user can change size
        items: [
            ganttRightSide,
            ganttTreePanel
        ],
        renderTo: '@gantt_editor_id@'
    });

    // Initiate controller
    var sideBarTab = Ext.get('sideBarTab');
    var renderDiv = Ext.get('@gantt_editor_id@');
    var ganttButtonController = Ext.create('PO.controller.gantt.GanttButtonController', {
        'renderDiv': renderDiv,
        'ganttEditor': ganttEditor,
        'ganttButtonController': ganttButtonController,
        'ganttTreePanel': ganttTreePanel,
        'ganttDrawComponent': ganttDrawComponent
    });
    ganttButtonController.init(this).onLaunch(this);

    // Handle collapsable side menu
    sideBarTab.on('click', ganttButtonController.onSideBarResize, ganttButtonController);
    Ext.EventManager.onWindowResize(ganttButtonController.onWindowsResize, ganttButtonController);    // Deal with resizing the main window

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

    // Store Coodinator starts app after all stores have been loaded:
    var coordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
        stores: [
            'taskTreeStore',
	    'senchaPreferenceStore'
        ],
        listeners: {
            load: function() {
                if ("boolean" == typeof this.loadedP) { return; }                // Check if the application was launched before
                launchGanttEditor();                                             // Launch the actual application.
                this.loadedP = true;                                             // Mark the application as launched
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

    senchaPreferenceStore.load({                                                 // Preferences for the GanttEditor
        callback: function() {
            console.log('PO.store.user.SenchaPreferenceStore: loaded');
        }
    });

});
</script>
</div>

