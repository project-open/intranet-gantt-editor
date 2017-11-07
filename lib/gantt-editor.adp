<if "" eq @main_parent_id@ and "1" eq @read_p@>
<div id="@gantt_editor_id@" style="height: 600px; overflow: hidden; -webkit-user-select: none; -moz-user-select: none; -khtml-user-select: none; -ms-user-select: none; ">
<!-- define the icons for the various sub-types of projects in the tree -->
<style type="text/css">
    .icon-task      { background-image: url("/intranet/images/navbar_default/cog_go.png") !important; }
    .icon-project   { background-image: url("/intranet/images/navbar_default/cog.png") !important; }
    .icon-ticket    { background-image: url("/intranet/images/navbar_default/tag_blue.png") !important; }
    .icon-milestone { background-image: url("/intranet/images/navbar_default/milestone.png") !important; }
    .icon-sla       { background-image: url("/intranet/images/navbar_default/tag_blue_add.png") !important; }
    .icon-program   { background-image: url("/intranet/images/navbar_default/tag_blue_add.png") !important; }
    .icon-release   { background-image: url("/intranet/images/navbar_default/arrow_rotate_clockwise.png") !important; }
    .icon-release-item { background-image: url("/intranet/images/navbar_default/arrow_right.png") !important; }
    .icon-crm       { background-image: url("/intranet/images/navbar_default/group.png") !important; }
</style>

<script type='text/javascript'>
// Ext.Loader.setConfig({enabled: true});
Ext.Loader.setPath('PO', '/sencha-core');
Ext.Loader.setPath('GanttEditor', '/intranet-gantt-editor');

// Disable the ?_dc=123456789 parameter from loader
Ext.Loader.setConfig({disableCaching: false});

Ext.require([
    'Ext.data.*',
    'Ext.grid.*',
    'Ext.tree.*',
    'Ext.ux.CheckColumn',
    'GanttEditor.controller.GanttButtonController',
    'GanttEditor.controller.GanttTreePanelController',
    'GanttEditor.controller.GanttZoomController',
    'GanttEditor.controller.GanttSchedulingController',
    'GanttEditor.view.GanttBarPanel',
    'PO.Utilities',
    'PO.class.PreferenceStateProvider',
    'PO.controller.ResizeController',
    'PO.controller.StoreLoadCoordinator',
    'PO.model.timesheet.TimesheetTask',
    'PO.model.timesheet.Material',
    'PO.model.timesheet.CostCenter',
    'PO.store.CategoryStore',
    'PO.store.group.GroupStore',
    'PO.store.timesheet.TaskTreeStore',
    'PO.store.timesheet.TaskStatusStore',
    'PO.store.timesheet.TaskMaterialStore',
    'PO.store.timesheet.TaskCostCenterStore',
    'PO.store.user.SenchaPreferenceStore',
    'PO.store.user.UserStore',
    'PO.view.field.POComboGrid',
    'PO.view.field.PODateField',						// Custom ]po[ Date editor field
    'PO.view.field.POTaskAssignment',
    'PO.view.gantt.AbstractGanttPanel',
    'PO.view.gantt.GanttTaskPropertyPanel',
    'PO.view.gantt.GanttTreePanel',
    'PO.view.menu.AlphaMenu',
    'PO.view.menu.ConfigMenu',
    'PO.view.menu.HelpMenu'
]);

// Global parameters from server-side
var default_material_id = parseInt('@default_material_id@');			// "Default" material
var default_cost_center_id = parseInt('@default_cost_center_id@');		// "The Company" cost-center
var default_uom_id = parseInt('@default_uom_id@');				// "Hour" default Unit of Measure
var write_project_p = parseInt('@write_p@');					// 0 or 1


/**
 * Launch the actual editor
 * This function is called from the Store Coordinator
 * after all essential data have been loaded into the
 * browser.
 */
function launchGanttEditor(debug){
    var taskTreeStore = Ext.StoreManager.get('taskTreeStore');
    var senchaPreferenceStore = Ext.StoreManager.get('senchaPreferenceStore');
    var oneDayMiliseconds = 24 * 3600 * 1000;
    var renderDiv = Ext.get("@gantt_editor_id@");
    var gifPath = "/intranet/images/navbar_default/";

    /* ***********************************************************************
     * Help Menu
     *********************************************************************** */
    var helpMenu = Ext.create('PO.view.menu.HelpMenu', {
        id: 'helpMenu',
        debug: debug,
        style: {overflow: 'visible'},						// For the Combo popup
        store: Ext.create('Ext.data.Store', { fields: ['text', 'url'], data: [
            {text: 'Gantt Editor Home', url: 'http://www.project-open.com/en/package-intranet-gantt-editor'}
//            {text: '-'},
//            {text: 'Only Text'},
//            {text: 'Google', url: 'http://www.google.com'}
        ]})
    });

    /* ***********************************************************************
     * Alpha Menu
     *********************************************************************** */
    var alphaMenu = Ext.create('PO.view.menu.AlphaMenu', {
        id: 'alphaMenu',
        alphaComponent: 'Gantt Editor',
        debug: debug,
        style: {overflow: 'visible'},						// For the Combo popup
        slaId: 1478943,					        		// ID of the ]po[ "PD Gantt Editor" project
        ticketStatusId: 30000							// "Open" and sub-states
    });

    /* ***********************************************************************
     * Config Menu
     *********************************************************************** */
    var configMenu = Ext.create('PO.view.menu.ConfigMenu', {
        debug: debug,
        id: 'configMenu',
	senchaPreferenceStore: senchaPreferenceStore,
        items: [{
            key: 'read_only',
            text: 'Read Only (Beta version - use with caution!)',
            checked: false
        }, {
	    id: 'config_menu_show_project_dependencies',
            key: 'show_project_dependencies', 
            text: 'Show Project Dependencies', 
            checked: true
        },  {
	    id: 'config_menu_show_project_assigned_resources',
            key: 'show_project_assigned_resources', 
            text: 'Show Project Assigned Resources', 
            checked: true
        }]
    });

    /* ***********************************************************************
     * Scheduling Menu
     *********************************************************************** */
    var schedulingMenuOnItemCheck = function(item, checked){
        if (me.debug) console.log('schedulingMenuOnItemCheck: item.id='+item.id);
        senchaPreferenceStore.setPreference(item.id, checked);
    }

    var schedulingMenu = Ext.create('Ext.menu.Menu', {
        id: 'schedulingMenu',
        debug: debug,
        style: {overflow: 'visible'},						// For the Combo popup
        items: [{
            xtype: 'menucheckitem',
            text: 'Manual Scheduling',
            checked: true,
            handler: function(a,b,c) {
                if (this.checked) { return; }
                this.setChecked(true);
            }
        }, {
            xtype: 'menucheckitem',
            text: 'Single-Project Scheduling',
            disabled: true,
            checked: false,
            handler: function() { }
        }, {
            xtype: 'menucheckitem',
            text: 'Multi-Project Scheduling',
            disabled: true,
            checked: false,
            handler: function() { }
        }]
    });


    /**
     * GanttButtonPanel
     */
    Ext.define('PO.view.gantt_editor.GanttButtonPanel', {
        extend: 'Ext.panel.Panel',
        alias: 'ganttPanelContainer',
        layout: 'border',
        defaults: {
            collapsible: true,
            split: true,
            bodyPadding: 0
        },
        tbar: [
            { icon: gifPath+'lock.png', tooltip: 'Read-only - you can not save changes', id: 'buttonLock', disabled: true}, 
            { icon: gifPath+'disk.png', tooltip: '<nobr>Save the project to the &#93;po&#91; backend</nobr>', id: 'buttonSave', disabled: true}, 
            { icon: gifPath+'arrow_refresh.png', tooltip: 'Reload project data from ]po[ backend, discarding changes', id: 'buttonReload'}, 
            { icon: gifPath+'arrow_out.png', tooltip: 'Maximize the editor &nbsp;', id: 'buttonMaximize'}, 
            { icon: gifPath+'arrow_in.png', tooltip: 'Restore default editor size &nbsp;', id: 'buttonMinimize', hidden: true},
            { xtype: 'tbseparator' }, 
            { icon: gifPath+'add.png', tooltip: 'Add a new task', id: 'buttonAdd'}, 
            { icon: gifPath+'delete.png', tooltip: 'Delete a task', id: 'buttonDelete'}, 
            { xtype: 'tbseparator' }, 
            // Event captured and handled by GanttTreePanelController 
            { icon: gifPath+'arrow_left.png', tooltip: 'Reduce Indent', id: 'buttonReduceIndent'}, 
            // Event captured and handled by GanttTreePanelController 
            { icon: gifPath+'arrow_right.png', tooltip: 'Increase Indent', id: 'buttonIncreaseIndent'}, 
            { xtype: 'tbseparator'}, 
            { icon: gifPath+'link_add.png', tooltip: 'Add dependency', id: 'buttonAddDependency', hidden: true}, 
            { icon: gifPath+'link_break.png', tooltip: 'Break dependency', id: 'buttonBreakDependency', hidden: true}, 
            '->', 
            { icon: gifPath+'zoom_in.png', tooltip: 'Zoom in time axis', id: 'buttonZoomIn'}, 
            { icon: gifPath+'zoom.png', tooltip: 'Center', id: 'buttonZoomCenter'}, 
            { icon: gifPath+'zoom_out.png', tooltip: 'Zoom out of time axis', id: 'buttonZoomOut'}, 
            '->', 
            { text: 'Scheduling', icon: gifPath+'clock.png', menu: schedulingMenu}, 
            { text: 'Configuration', icon: gifPath+'wrench.png', menu: configMenu}, 
            { text: 'Help', icon: gifPath+'help.png', menu: helpMenu}, 
            { text: 'This is Beta!', icon: gifPath+'bug.png', menu: alphaMenu}
        ]
    });

    // Left-hand side task tree
    var ganttTreePanel = Ext.create('PO.view.gantt.GanttTreePanel', {
        id: 'ganttTreePanel',
        debug: debug,
        width: 500,
        region: 'west',
        store: taskTreeStore
    });

    var ganttTreePanelController = Ext.create('GanttEditor.controller.GanttTreePanelController', {
        ganttTreePanel: ganttTreePanel,
        senchaPreferenceStore: senchaPreferenceStore,
        debug: debug
    });
    ganttTreePanelController.init(this);


    // Right-hand side Gantt display
    var reportStartDate = PO.Utilities.pgToDate('@report_start_date@');
    var reportEndDate = PO.Utilities.pgToDate('@report_end_date@');
    var ganttBarPanel = Ext.create('GanttEditor.view.GanttBarPanel', {
        id: 'ganttBarPanel',
        cls: 'extjs-panel',
        region: 'center',
        debug: false,
        reportStartDate: reportStartDate,					// start and end of first and last task in the project
        reportEndDate: reportEndDate,
        overflowX: 'scroll',							// Allows for horizontal scrolling, but not vertical
        scrollFlags: { x: true },
        gradients: [
            {id:'gradientId', angle:66, stops:{0:{color:'#99b2cc'}, 100:{color:'#ace'}}},
            {id:'gradientId2', angle:0, stops:{0:{color:'#590'}, 20:{color:'#599'}, 100:{color:'#ddd'}}}
        ],

        objectPanel: ganttTreePanel,
        objectStore: taskTreeStore,
        preferenceStore: senchaPreferenceStore
    });

    // Outer Gantt editor jointing the two parts (TreePanel + Draw)
    var ganttPanelContainer = Ext.create('PO.view.gantt_editor.GanttButtonPanel', {
        debug: debug,
        resizable: true,							// Add handles to the panel, so the user can change size
        items: [
            ganttTreePanel,
            ganttBarPanel
        ],
        renderTo: renderDiv
    });

    // Contoller to handle size and resizing related events
    var resizeController = Ext.create('PO.controller.ResizeController', {
        debug: debug,
        redrawPanel: ganttBarPanel,						// panel with redraw() function and needsRedraw variable
        renderDiv: renderDiv,							// container of outerContainer
        outerContainer: ganttPanelContainer					// outermost panel with resize border
    }).init();
    resizeController.onLaunch(this);
    resizeController.onResize();						// Set the size of the outer GanttButton Panel

    // Controller that deals with button events.
    var ganttButtonController = Ext.create('GanttEditor.controller.GanttButtonController', {
        debug: debug,
        ganttPanelContainer: ganttPanelContainer,
        ganttTreePanel: ganttTreePanel,
        ganttBarPanel: ganttBarPanel,
        taskTreeStore: taskTreeStore,
        resizeController: resizeController,
        senchaPreferenceStore: senchaPreferenceStore,
        ganttTreePanelController: ganttTreePanelController
    });
    ganttButtonController.init(this).onLaunch(this);

    // Controller for Zoom in/out, scrolling and  centering
    var ganttZoomController = Ext.create('GanttEditor.controller.GanttZoomController', {
        debug: debug,
        senchaPreferenceStore: senchaPreferenceStore
    });
    ganttZoomController.init(this);
    resizeController.ganttZoomController = ganttZoomController;

    // Create the panel showing properties of a task, but don't show it yet.
    var taskPropertyPanel = Ext.create("PO.view.gantt.GanttTaskPropertyPanel", {
        debug: true,
	senchaPreferenceStore: senchaPreferenceStore,
	ganttTreePanelController: ganttTreePanelController
    });
    taskPropertyPanel.hide();

    // Deal with changes of Gantt data and perform scheduling
    var ganttSchedulingController = Ext.create('GanttEditor.controller.GanttSchedulingController', {
        debug: debug,
        'taskTreeStore': taskTreeStore,
        'ganttBarPanel': ganttBarPanel,
        'ganttTreePanel': ganttTreePanel
    });
    ganttSchedulingController.init(this).onLaunch(this);

    
    // Create a warning if there are no tasks in the project
    var numTasks = 0;
    taskTreeStore.tree.root.eachChild(function() { numTasks = numTasks + 1; });
    if (0 == numTasks) {
	Ext.Msg.show({
	    title: 'No tasks created yet',
	    msg: 'Please click on the <img src="/intranet/images/navbar_default/add.png"> button above<br>in order to add a first task to your project.',
	    height: 120, width: 400,
	    buttons: Ext.Msg.OK,
	    icon: Ext.Msg.INFO,
	    modal: false
	});
    }

};


/**
 * onReady() - Launch the application
 * Uses StoreCoordinator to load essential data
 * before clling launchGanttEditor() to start the
 * actual applicaiton.
 */
Ext.onReady(function() {
    Ext.QuickTips.init();							// No idea why this is necessary, but it is...
    Ext.getDoc().on('contextmenu', function(ev) { ev.preventDefault(); });  // Disable Right-click context menu on browser background
    var debug = true;

    /* ***********************************************************************
     * State
     *********************************************************************** */
    // Deal with state
    Ext.state.Manager.setProvider(new Ext.state.CookieProvider());
    var taskTreeStore = Ext.create('PO.store.timesheet.TaskTreeStore');
    var senchaPreferenceStore = Ext.create('PO.store.user.SenchaPreferenceStore');
    var taskStatusStore = Ext.create('PO.store.timesheet.TaskStatusStore');
    var taskMaterialStore = Ext.create('PO.store.timesheet.TaskMaterialStore');
    var taskCostCenterStore = Ext.create('PO.store.timesheet.TaskCostCenterStore');
    var projectMemberStore = Ext.create('PO.store.user.UserStore', {storeId: 'projectMemberStore'});
    var userStore = Ext.create('PO.store.user.UserStore', {storeId: 'userStore'});
    var groupStore = Ext.create('PO.store.group.GroupStore', {storeId: 'groupStore'});

    // Store Coodinator starts app after all stores have been loaded:
    var coordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
        debug: debug,
        stores: [
            'taskTreeStore',
            'taskStatusStore',
            'taskMaterialStore',
            'taskCostCenterStore',
            'senchaPreferenceStore',
            'projectMemberStore',
            'groupStore'
        ],
        listeners: {
            load: function() {
                if ("boolean" == typeof this.loadedP) { return; }		// Check if the application was launched before
                launchGanttEditor(debug);					// Launch the actual application.
                this.loadedP = true;						// Mark the application as launched
            }
        }
    });

    taskStatusStore.load();
    taskMaterialStore.load();
    taskCostCenterStore.load();

    groupStore.load({								// Just the list of groups
        callback: function() {
            if (debug) console.log('PO.store.group.GroupStore: loaded');
        }
    });

    // Get the list of users assigned to the main project
    // or any of it's tasks or tickets
    projectMemberStore.getProxy().extraParams = { 
        format: 'json',
        query: "user_id in (					\
                select	r.object_id_two				\
                from	acs_rels r,				\
                        im_projects main_p,			\
                        im_projects sub_p			\
                where	main_p.project_id = @project_id@ and	\
                        sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and \
                        r.object_id_one = sub_p.project_id	\
        )"
    };
    projectMemberStore.load();

    // Load stores that need parameters
    taskTreeStore.getProxy().extraParams = { project_id: @project_id@ };
    taskTreeStore.load({
        callback: function(records, operation, success) {
            var me = this;
            if (debug) console.log('PO.store.timesheet.TaskTreeStore: loaded');

            var mainProjectNode = records[0];
            me.setRootNode(mainProjectNode);
        }
    });

    // User preferences
    senchaPreferenceStore.load({						// Preferences for the GanttEditor
        callback: function() {
            if (debug) console.log('PO.store.user.SenchaPreferenceStore: loaded');
        }
    });

    // User store - load last, because this can take some while. Load only Employees.
    userStore.getProxy().extraParams = { 
        format: 'json',
        query: "user_id in (select object_id_two from acs_rels where object_id_one in (select group_id from groups where group_name = 'Employees'))"
    };
    userStore.load();
   
});
</script>
</div>
</if>
<else>
<if "" ne @main_project_parent_id@>
Project #@project_id@ is a sub-project, so we can't show a Gantt Editor for it.
</if>
</else>

