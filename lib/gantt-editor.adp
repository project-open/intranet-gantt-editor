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

<script type='text/javascript' <if @::__csp_nonce@ not nil>nonce="@::__csp_nonce;literal@"</if>>
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
    'GanttEditor.controller.GanttConfigController',
    'GanttEditor.controller.GanttTreePanelController',
    'GanttEditor.controller.GanttZoomController',
    'GanttEditor.controller.GanttSchedulingController',
    'GanttEditor.view.GanttBarPanel',
    'GanttEditor.view.GanttDependencyPropertyPanel',
    'GanttEditor.store.AbsenceAssignmentStore',
    'PO.Utilities',
    'PO.class.PreferenceStateProvider',
    'PO.controller.ResizeController',
    'PO.controller.StoreLoadCoordinator',
    'PO.model.timesheet.TimesheetTask',
    'PO.model.timesheet.Material',
    'PO.model.finance.CostCenter',
    'PO.model.user.SenchaPreference',
    'PO.model.user.User',
    'PO.store.CategoryStore',
    'PO.store.group.GroupStore',
    'PO.store.project.BaselineStore',
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
var default_effort_driven_type_id = parseInt('@default_effort_driven_type_id@'); // "Fixed Effort" as default
var write_project_p = parseInt('@write_p@');					// 0 or 1
var baseline_p = parseInt('@baseline_p@');                                      // is the im_baselines table installed?


/**
 * Launch the actual editor
 * This function is called from the Store Coordinator
 * after all essential data have been loaded into the
 * browser.
 */
function launchGanttEditor(debug){

    // Deal with state
    var stateProvider = Ext.create('PO.class.PreferenceStateProvider', {
        debug: getDebug('stateProvider'),
        url: window.location.pathname + window.location.search
    });
    Ext.state.Manager.setProvider(stateProvider);
    // Ext.state.Manager.setProvider(new Ext.state.CookieProvider());
    // Ext.state.Manager.setProvider(new Ext.state.LocalStorageProvider());

    var baselineStore = Ext.StoreManager.get('baselineStore');
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
        debug: getDebug('helpMenu'),
        style: {overflow: 'visible'},						// For the Combo popup
        store: Ext.create('Ext.data.Store', { fields: ['text', 'url'], data: [
            {text: 'Gantt Editor Home', url: 'https://www.project-open.com/en/package-intranet-gantt-editor'}
//            {text: '-'},
//            {text: 'Only Text'},
//            {text: 'Google', url: 'https://www.google.com'}
        ]})
    });

    /* ***********************************************************************
     * Alpha Menu
     *********************************************************************** */
    var alphaMenu = Ext.create('PO.view.menu.AlphaMenu', {
        id: 'alphaMenu',
        alphaComponent: 'Gantt Editor',
        debug: getDebug('alphaMenu'),
        style: {overflow: 'visible'},						// For the Combo popup
        slaId: 1478943,					        		// ID of the ]po[ "PD Gantt Editor" project
        ticketStatusId: 30000							// "Open" and sub-states
    });

    /* ***********************************************************************
     * Config Menu
     *********************************************************************** */

    var baselineComboBox = null;
    if (baseline_p > 0) {
        baselineComboBox = new Ext.form.ComboBox({
            fieldLabel: 'Baseline',
            labelWidth: 50,
            emptyText: 'Select a baseline',
	    allowBlank: true,
            store: baselineStore,
            displayField: 'baseline_name',
            idField: 'baseline_id',
            queryMode: 'local',
            // triggerAction: 'all',
            selectOnFocus: true,
            // getListParent: function() { return this.el.up('.x-menu'); },
            id: 'config_menu_show_project_baseline',
            key: 'show_project_baseline',
            iconCls: 'no-icon'
        });
        var baselineId = senchaPreferenceStore.getPreference(baselineComboBox.key, "");
        var baselineModel = baselineComboBox.findRecord('baseline_id', baselineId);
        if (baselineModel) {
            baselineComboBox.setValue(baselineModel.get('baseline_name'));
        }
        baselineComboBox.on('change', function(combo, value) {
            var records = baselineComboBox.findRecord('baseline_name', value);
            if (!records) return;
            var record = records;
            if (records['$className'] != 'PO.model.project.Baseline') {
                var record = records[0];
            }
            if (!record) return;
            var id = record.get('id');
            senchaPreferenceStore.setPreference(baselineComboBox.key, id);
            ganttBarPanel.needsRedraw = true;
        });
    }

    var configMenuGanttEditor = Ext.create('PO.view.menu.ConfigMenu', {
        debug: getDebug('configMenuGanttEditor'),
        id: 'configMenuGanttEditor',
        senchaPreferenceStore: senchaPreferenceStore,
        items: [
        {
            id: 'config_menu_show_cross_project_overassignments',
            key: 'show_project_cross_project_overassignments', 
            text: 'Show Cross-Project Overassignments', 
            checked: @default_cross_project_overassignments@
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
        },  {
            id: 'config_menu_show_percent_done_bar',
            key: 'show_percent_done_bar', 
            text: 'Show "Done %" Gantt Bars', 
            checked: true
        },  {
            id: 'config_menu_show_logged_hours_bar',
            key: 'show_logged_hours_bar', 
            text: 'Show "Logged Hours %" on Gantt Bars', 
            checked: true
        },
            baselineComboBox,
        {
            id: 'config_menu_show_project_findocs',
            key: 'show_project_findocs', 
            text: 'Show Project Financial Documents', 
            checked: true
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
            { icon: gifPath+'lock.png', tooltip: 'Read-only - you can not save changes', id: 'buttonLockGantt', disabled: true}, 
            { icon: gifPath+'disk.png', tooltip: '<nobr>Save the project to the &#93;po&#91; backend</nobr>', id: 'buttonSaveGantt', disabled: true}, 
            // { icon: gifPath+'arrow_refresh.png', tooltip: 'Reload project data from ]po[ backend, discarding changes', id: 'buttonReloadGantt'}, 
            { icon: gifPath+'arrow_out.png', tooltip: 'Maximize the editor &nbsp;', id: 'buttonMaximizeGantt'}, 
            { icon: gifPath+'arrow_in.png', tooltip: 'Restore default editor size &nbsp;', id: 'buttonMinimizeGantt', hidden: true},
            { xtype: 'tbseparator' }, 
            { icon: gifPath+'add.png', tooltip: 'Add a new task', id: 'buttonAddGantt'}, 
            { icon: gifPath+'delete.png', tooltip: 'Delete a task', id: 'buttonDeleteGantt'}, 
            { xtype: 'tbseparator' }, 
            // Event captured and handled by GanttTreePanelController 
            { icon: gifPath+'arrow_left.png', tooltip: 'Reduce Indent', id: 'buttonReduceIndentGantt'}, 
            // Event captured and handled by GanttTreePanelController 
            { icon: gifPath+'arrow_right.png', tooltip: 'Increase Indent', id: 'buttonIncreaseIndentGantt'},
            { xtype: 'tbseparator'}, 
            { icon: gifPath+'link_add.png', tooltip: 'Add dependency', id: 'buttonAddDependencyGantt', hidden: true}, 
            { icon: gifPath+'link_break.png', tooltip: 'Break dependency', id: 'buttonBreakDependencyGantt', hidden: true}, 
            '->', 
            { icon: gifPath+'resultset_previous.png', tooltip: 'Zoom in time axis', id: 'buttonZoomLeftGantt'},
            { icon: gifPath+'zoom_in.png', tooltip: 'Zoom in time axis', id: 'buttonZoomInGantt'}, 
            { icon: gifPath+'zoom.png', tooltip: 'Center', id: 'buttonZoomCenterGantt'},
            { icon: gifPath+'zoom_out.png', tooltip: 'Zoom out of time axis', id: 'buttonZoomOutGantt'},
            { icon: gifPath+'resultset_next.png', tooltip: 'Zoom in time axis', id: 'buttonZoomRightGantt'}, 
            '->', 
            { text: 'Configuration', icon: gifPath+'wrench.png', menu: configMenuGanttEditor}, 
            { text: 'Help', icon: gifPath+'help.png', menu: helpMenu}
            //,{ text: 'This is Beta!', icon: gifPath+'bug.png', menu: alphaMenu}
        ]
    });

    // Left-hand side task tree
    var ganttTreePanel = Ext.create('PO.view.gantt.GanttTreePanel', {
        id: 'ganttTreePanel',
        debug: getDebug('ganttTreePanel'),
        width: 500,
        region: 'west',
        store: taskTreeStore
    });
    // Work around columns messed up after state change
    ganttTreePanel.headerCt.onColumnsChanged();
    ganttTreePanel.view.refresh();

    var ganttTreePanelController = Ext.create('GanttEditor.controller.GanttTreePanelController', {
        ganttTreePanel: ganttTreePanel,
        senchaPreferenceStore: senchaPreferenceStore,
        debug: getDebug('ganttTreePanelController')
    });
    ganttTreePanelController.init(this);


    // Right-hand side Gantt display
    var reportStartDate = PO.Utilities.pgToDate('@report_start_date@');
    var reportEndDate = PO.Utilities.pgToDate('@report_end_date@');
    var ganttBarPanel = Ext.create('GanttEditor.view.GanttBarPanel', {
        id: 'ganttBarPanel',
        cls: 'extjs-panel',
        region: 'center',
        debug: getDebug('ganttBarPanel'),
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
        debug: getDebug('ganttPanelContainer'),
        resizable: true,							// Add handles to the panel, so the user can change size
        items: [
            ganttTreePanel,
            ganttBarPanel
        ],
        renderTo: renderDiv
    });

    // Contoller to handle size and resizing related events
    var resizeController = Ext.create('PO.controller.ResizeController', {
        debug: getDebug('resizeController'),
        redrawPanel: ganttBarPanel,						// panel with redraw() function and needsRedraw variable
        renderDiv: renderDiv,							// container of outerContainer
        outerContainer: ganttPanelContainer					// outermost panel with resize border
    }).init();
    resizeController.onLaunch(this);
    resizeController.onResize();						// Set the size of the outer GanttButton Panel

    // Controller that deals with button events.
    var ganttButtonController = Ext.create('GanttEditor.controller.GanttButtonController', {
        debug: getDebug('ganttButtonController'),
        ganttPanelContainer: ganttPanelContainer,
        ganttTreePanel: ganttTreePanel,
        ganttBarPanel: ganttBarPanel,
        taskTreeStore: taskTreeStore,
        resizeController: resizeController,
        senchaPreferenceStore: senchaPreferenceStore,
        ganttTreePanelController: ganttTreePanelController
    });
    ganttButtonController.init(this).onLaunch(this);

    // Controller for handling configuration options
    var ganttConfigController = Ext.create('GanttEditor.controller.GanttConfigController', {
        debug: getDebug('ganttConfigController'),
        configMenuGanttEditor: configMenuGanttEditor,
        senchaPreferenceStore: senchaPreferenceStore,
        ganttBarPanel: ganttBarPanel
    });
    ganttConfigController.init(this);


    // Controller for Zoom in/out, scrolling and  centering
    var ganttZoomController = Ext.create('GanttEditor.controller.GanttZoomController', {
        debug: getDebug('ganttZoomController'),
        senchaPreferenceStore: senchaPreferenceStore
    });
    ganttZoomController.init(this);
    resizeController.ganttZoomController = ganttZoomController;

    // Create the panel showing properties of a task, but don't show it yet.
    var taskPropertyPanel = Ext.create("PO.view.gantt.GanttTaskPropertyPanel", {
        debug: getDebug('taskPropertyPanel'),
        senchaPreferenceStore: senchaPreferenceStore,
        ganttTreePanelController: ganttTreePanelController
    });
    taskPropertyPanel.hide();

    // Create the panel showing properties of a dependency, but don't show it yet.
    var dependencyPropertyPanel = Ext.create('GanttEditor.view.GanttDependencyPropertyPanel', {
        debug: getDebug('dependencyPropertyPanel'),
        ganttBarPanel: ganttBarPanel,
        senchaPreferenceStore: senchaPreferenceStore,
        ganttTreePanelController: ganttTreePanelController,
        ganttSchedulingController: null                         // set further below
    });
    dependencyPropertyPanel.hide();


    // Deal with changes of Gantt data and perform scheduling
    var ganttSchedulingController = Ext.create('GanttEditor.controller.GanttSchedulingController', {
        debug: getDebug('ganttSchedulingController'),
        'taskTreeStore': taskTreeStore,
        'ganttBarPanel': ganttBarPanel,
        'ganttTreePanel': ganttTreePanel,
	'dependencyPropertyPanel': dependencyPropertyPanel
    });
    ganttBarPanel.ganttSchedulingController = ganttSchedulingController;
    ganttSchedulingController.init(this).onLaunch(this);
    dependencyPropertyPanel.ganttSchedulingController = ganttSchedulingController;

    // Create a warning if there are no tasks in the project
    setTimeout(function() {
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
        };
    }, 2);

    // Work around Chrome bug showing a 15px white space between GanttBarPanel DIV and SVG:
    setTimeout(function() {
        var svgStyle = document.getElementById("ganttBarPanel").firstChild.style;
        svgStyle.minHeight = "0px";
    }, 1);
};


var debugHash = @debug_json;noquote@;
function getDebug(id) {
    // Check for a debug setting for the specific Id
    var debug = parseInt(debugHash[id]);
    if (!isNaN(debug)) return debug;

    // Use the default debug
    debug = parseInt(debugHash['default']);
    if (!isNaN(debug)) return debug;

    // invalid configuration - enable debug
    return 1;
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
    var debug = getDebug('default');

    /* ***********************************************************************
     * 
     *********************************************************************** */

    var taskTreeStore = Ext.create('PO.store.timesheet.TaskTreeStore');
    var taskStatusStore = Ext.create('PO.store.timesheet.TaskStatusStore');
    var taskMaterialStore = Ext.create('PO.store.timesheet.TaskMaterialStore');
    var taskCostCenterStore = Ext.create('PO.store.timesheet.TaskCostCenterStore');
    var projectMemberStore = Ext.create('PO.store.user.UserStore', {storeId: 'projectMemberStore'});
    var userStore = Ext.create('PO.store.user.UserStore', {storeId: 'userStore'});
    var groupStore = Ext.create('PO.store.group.GroupStore', {storeId: 'groupStore'});
    var baselineStore = Ext.create('PO.store.project.BaselineStore', {storeId: 'baselineStore'});
    var absenceAssignmentStore = Ext.create('GanttEditor.store.AbsenceAssignmentStore', {storeId: 'absenceAssignmentStore'});

    var senchaPreferenceStore = Ext.StoreManager.get('senchaPreferenceStore');
    if (!senchaPreferenceStore) {
        senchaPreferenceStore = Ext.create('PO.store.user.SenchaPreferenceStore');
    } else {
	senchaPreferenceStore.loaded = true;
    }
    
    // Store Coodinator starts app after all stores have been loaded:
    var ganttCoordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
        debug: getDebug('storeLoadCoordinator'),
        stores: [
            'taskTreeStore',
            'taskStatusStore',
            'taskMaterialStore',
            'taskCostCenterStore',
            'senchaPreferenceStore',
            'projectMemberStore',
            'groupStore',
            'absenceAssignmentStore'
        ],
        listeners: {
            load: function() {
                if ("boolean" == typeof this.loadedP) { return; }		// Check if the application was launched before
                launchGanttEditor(debug);					// Launch the actual application.
                this.loadedP = true;						// Mark the application as launched
            }
        }
    });

    taskStatusStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("TaskStatusStore", op); }});
    taskMaterialStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("TaskMaterialStore", op); }});
    taskCostCenterStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("TaskCostCenterStore", op); }});
    groupStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("GroupStore", op); }});

    // Load a store with user absences and assignments to other projects
    absenceAssignmentStore.getProxy().extraParams = { 
        report_code: 'rest_project_member_assignments_absences',
        format: 'json',
        main_project_id: @project_id@
    };
    absenceAssignmentStore.load({callback: function(r, op, success) { 
        if (!success) 
            PO.Utilities.reportStoreError("AbsenceAssignmentStore", op); }
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
    projectMemberStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("ProjectMemberStore", op); }});


    // Baselines is an enterprise feature, so it may not be installed
    if (@baseline_p@ > 0) {
	ganttCoordinator.stores.push('baselineStore');
   
	// Get the list of baselines of the main project
	baselineStore.getProxy().extraParams = {
            format: 'json',
            query: "baseline_project_id = @project_id@"
	};

	// add a blank option to store every time it is loaded
	baselineStore.on('load', function(r, op, success) {
	    baselineStore.insert(0, [{'baseline_id': '0', 'baseline_name': 'none'}]);
	});
			 
	baselineStore.load({callback: function(r, op, success) {
	    if (!success) PO.Utilities.reportStoreError("BaselineStore", op);
	}});
    }
    
    // Load stores that need parameters
    taskTreeStore.getProxy().extraParams = { project_id: @project_id@ };
    taskTreeStore.load({
        callback: function(records, operation, success) {
            var me = this;
            if (debug) console.log('PO.store.timesheet.TaskTreeStore: loaded');

            if (!success) {
                PO.Utilities.reportStoreError("TaskTreeStore", operation);
                return;
            }

            var mainProjectNode = records[0];
            mainProjectNode.set('sort_order','0');
            me.setRootNode(mainProjectNode);
        }
    });

    // User preferences
    if (!senchaPreferenceStore.loaded)
        senchaPreferenceStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("UserPreferenceStore", op); }});


    // User store - load last, because this can take some while. Load only Employees.
    userStore.getProxy().extraParams = { 
        format: 'json',
        query: "user_id in (select object_id_two from acs_rels where object_id_one in (select group_id from groups where group_name = 'Employees'))"
    };
    userStore.load({callback: function(r, op, success) { if (!success) PO.Utilities.reportStoreError("UserStore", op); }});
   
});
</script>
</div>
</if>
<else>
<if "" ne @main_project_parent_id@>
Project #@project_id@ is a sub-project, so we can't show a Gantt Editor for it.
</if>
</else>

