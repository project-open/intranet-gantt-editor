<div id="@gantt_editor_id@" style="overflow: hidden; -webkit-user-select: none; -moz-user-select: none; -khtml-user-select: none; -ms-user-select: none; ">
<script type='text/javascript'>

// Ext.Loader.setConfig({enabled: true});
Ext.Loader.setPath('PO', '/sencha-core');
Ext.Loader.setPath('GanttEditor', '/intranet-gantt-editor');

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
    'PO.store.CategoryStore',
    'PO.store.group.GroupStore',
    'PO.store.timesheet.TaskTreeStore',
    'PO.store.timesheet.TaskStatusStore',
    'PO.store.user.SenchaPreferenceStore',
    'PO.store.user.UserStore',
    'PO.view.field.POComboGrid',
    'PO.view.field.PODateField',						// Custom ]po[ Date editor field
    'PO.view.field.POTaskAssignment',
    'PO.view.gantt.AbstractGanttPanel',
    'PO.view.gantt.GanttTaskPropertyPanel',
    'PO.view.gantt.GanttTreePanel',
    'PO.view.menu.AlphaMenu',
    'PO.view.menu.HelpMenu'
]);

// Global parameters from server-side
var default_material_id = parseInt('@default_material_id@');			// "Default" material
var default_uom_id = parseInt('@default_uom_id@');				// "Hour" default Unit of Measure

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
        slaId: 1478943,					                	// ID of the ]po[ "PD Gantt Editor" project
        ticketStatusId: 30000				                	// "Open" and sub-states
    });

    /* ***********************************************************************
     * Config Menu
     *********************************************************************** */
    var configMenuOnItemCheck = function(item, checked){
        if (me.debug) console.log('configMenuOnItemCheck: item.id='+item.id);
        senchaPreferenceStore.setPreference('@page_url@', item.id, checked);
    }

    var configMenu = Ext.create('Ext.menu.Menu', {
        id: 'configMenu',
        debug: debug,
        style: {overflow: 'visible'},						// For the Combo popup
        items: [{
                text: 'Reset Configuration',
                handler: function() {
                    var me = this;
                    var menu = me.ownerCt;
                    if (menu.debug) console.log('configMenu.OnResetConfiguration');
                    senchaPreferenceStore.each(function(model) {
                        var url = model.get('preference_url');
                        if (url != '@page_url@') { return; }
                        model.destroy();
                    });
                }
        }, '-']
    });

    // Setup the configMenu items
    var confSetupStore = Ext.create('Ext.data.Store', {
        fields: ['key', 'text', 'def'],
        data : [
            {key: 'show_project_dependencies', text: 'Show Project Dependencies', def: true},
            {key: 'show_project_resource_load', text: 'Show Project Assigned Resources', def: true}
//            {key: 'show_dept_assigned_resources', text: 'Show Department Assigned Resources', def: true},
//            {key: 'show_dept_available_resources', text: 'Show Department Available Resources', def: false},
//            {key: 'show_dept_percent_work_load', text: 'Show Department % Work Load', def: true},
//            {key: 'show_dept_accumulated_overload', text: 'Show Department Accumulated Overload', def: false}
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



    /* ***********************************************************************
     * Scheduling Menu
     *********************************************************************** */
    var schedulingMenuOnItemCheck = function(item, checked){
        if (me.debug) console.log('schedulingMenuOnItemCheck: item.id='+item.id);
        senchaPreferenceStore.setPreference('@page_url@', item.id, checked);
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
            { icon: gifPath+'disk.png', tooltip: 'Save the project to the ]po[ backend', id: 'buttonSave', disabled: true}, 
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
	    { text: 'This is Alpha!', icon: gifPath+'bug.png', menu: alphaMenu}
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
        debug: debug
    });
    ganttTreePanelController.init(this);

    

    // Right-hand side Gantt display
    var reportStartTime = PO.Utilities.pgToDate('@report_start_date@').getTime();
    var reportEndTime = PO.Utilities.pgToDate('@report_end_date@').getTime();
    var ganttBarPanel = Ext.create('GanttEditor.view.GanttBarPanel', {
        id: 'ganttBarPanel',
        region: 'center',
        debug: debug,

        axisEndX: 5000,								// Size of the time axis. Always starts with 0.
        axisStartDate: new Date(reportStartTime - 7 * oneDayMiliseconds),
        axisEndDate: new Date(reportEndTime + 1.5 * (reportEndTime - reportStartTime) + 7 * oneDayMiliseconds ),

        overflowX: 'scroll',							// Allows for horizontal scrolling, but not vertical
        scrollFlags: {x: true},

        objectPanel: ganttTreePanel,
        objectStore: taskTreeStore,
        preferenceStore: senchaPreferenceStore,
        gradients: [
            {id:'gradientId', angle:66, stops:{0:{color:'#cdf'}, 100:{color:'#ace'}}},
            {id:'gradientId2', angle:0, stops:{0:{color:'#590'}, 20:{color:'#599'}, 100:{color:'#ddd'}}}
        ]
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
	'renderDiv': renderDiv,
        'outerContainer': ganttPanelContainer
    }).init();
    resizeController.onLaunch(this);
    resizeController.onResize();						// Set the size of the outer GanttButton Panel

    // Controller that deals with button events.
    var ganttButtonController = Ext.create('GanttEditor.controller.GanttButtonController', {
        debug: debug,
        'ganttPanelContainer': ganttPanelContainer,
        'ganttTreePanel': ganttTreePanel,
        'ganttBarPanel': ganttBarPanel,
        'taskTreeStore': taskTreeStore,
	'resizeController': resizeController
    });
    ganttButtonController.init(this).onLaunch(this);

    // Controller for zoom in/out
    var ganttZoomController = Ext.create('GanttEditor.controller.GanttZoomController', {
        debug: debug
    });
    ganttZoomController.init(this);
    ganttZoomController.zoomOnProject();					// ToDo: Remember the user's position. Meanwhile center...

    // Create the panel showing properties of a task,
    // but don't show it yet.
    var taskPropertyPanel = Ext.create("PO.view.gantt.GanttTaskPropertyPanel", {
        debug: debug
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
    var projectMemberStore = Ext.create('PO.store.user.UserStore', {storeId: 'projectMemberStore'});
    var userStore = Ext.create('PO.store.user.UserStore', {storeId: 'userStore'});
    var groupStore = Ext.create('PO.store.group.GroupStore', {storeId: 'groupStore'});

    // Store Coodinator starts app after all stores have been loaded:
    var coordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
        debug: debug,
        stores: [
            'taskTreeStore',
            'taskStatusStore',
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

