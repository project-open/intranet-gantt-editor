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
    'GanttEditor.controller.GanttTreePanelController',
    'GanttEditor.controller.GanttBarPanelController',
    'GanttEditor.controller.GanttSchedulingController',
    'GanttEditor.view.GanttBarPanel',
    'PO.Utilities',
    'PO.class.PreferenceStateProvider',
    'PO.controller.StoreLoadCoordinator',
    'PO.controller.ResizeController',
    'PO.model.timesheet.TimesheetTask',
    'PO.store.CategoryStore',
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


    /* ***********************************************************************
     * State
     *********************************************************************** */
    Ext.state.Manager.setProvider(new PO.class.PreferenceStateProvider({
	url: '/intranet-gantt-editor/lib/gantt-editor'
    }));

    /* ***********************************************************************
     * Help Menu
     *********************************************************************** */
    var helpMenu = Ext.create('PO.view.menu.HelpMenu', {
        id: 'helpMenu',
	debug: debug,
        style: {overflow: 'visible'},						// For the Combo popup
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
        portfolioPlannerProjectPanel.redraw();
        portfolioPlannerCostCenterPanel.redraw();
    }

    var configMenu = Ext.create('Ext.menu.Menu', {
        id: 'configMenu',
	debug: debug,
        style: {overflow: 'visible'},						// For the Combo popup
        items: [{
                text: 'Reset Configuration',
                handler: function() {
                    if (me.debug) console.log('configMenuOnResetConfiguration');
                    senchaPreferenceStore.each(function(model) {
                        var url = model.get('preference_url');
                        if (url != '@page_url@') { return; }
                        model.destroy();
                    });
                    // Reset column configuration
                    projectGridColumnConfig.each(function(model) { 
                        model.destroy({
                            success: function(model) {
                                if (me.debug) console.log('configMenuOnResetConfiguration: Successfully destroyed a CC config');
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
                                if (me.debug) console.log('configMenuOnResetConfiguration: Successfully destroyed a CC config');
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
        alias: 'ganttPanelContainer',
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
                icon: '/intranet/images/navbar_default/disk.png',
                tooltip: 'Save the project to the ]po[ backend',
                id: 'buttonSave',
                disabled: true
            }, {
                icon: '/intranet/images/navbar_default/arrow_refresh.png',
                tooltip: 'Reload project data from ]po[ backend, discarding changes',
                id: 'buttonReload'
            }, {
                icon: '/intranet/images/navbar_default/arrow_out.png',
                tooltip: 'Maximize the editor &nbsp;',
                id: 'buttonMaximize'
            }, {
                icon: '/intranet/images/navbar_default/arrow_in.png',
                tooltip: 'Restore default editor size &nbsp;',
                id: 'buttonMinimize',
                hidden: true
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
		// Event captured and handled by GanttTreePanelController
                icon: '/intranet/images/navbar_default/arrow_left.png',
                tooltip: 'Reduce Indent',
                id: 'buttonReduceIndent'
            }, {
		// Event captured and handled by GanttTreePanelController
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
            }, '->', {
                icon: '/intranet/images/navbar_default/zoom_in.png',
                tooltip: 'Zoom in time axis',
                id: 'buttonZoomIn'
            }, {
                icon: '/intranet/images/navbar_default/zoom.png',
                tooltip: 'Center',
                id: 'buttonZoomCenter'
            }, {
                icon: '/intranet/images/navbar_default/zoom_out.png',
                tooltip: 'Zoom out of time axis',
                id: 'buttonZoomOut'
            }, '->', {
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
        debug: debug,
        'ganttTreePanel': null,						// Set during init: left-hand task tree panel
        'ganttBarPanel': null,						// Set during init: right-hand surface with Gantt sprites
        'taskTreeStore': null,						// Set during init: treeStore with task data
        refs: [
            { ref: 'ganttTreePanel', selector: '#ganttTreePanel' }
        ],
        init: function() {
            var me = this;
            if (me.debug) { if (me.debug) console.log('PO.controller.gantt_editor.GanttButtonController: init'); }

            // Listen to button press events
            this.control({
                '#buttonReload': { click: this.onButtonReload },
                '#buttonSave': { click: this.onButtonSave },
                '#buttonMaximize': { click: this.onButtonMaximize },
                '#buttonMinimize': { click: this.onButtonMinimize },
                '#buttonAddDependency': { click: this.onButton },
                '#buttonBreakDependency': { click: this.onButton },
//                '#buttonZoomIn': { click: this.onZoomIn },
//                '#buttonZoomOut': { click: this.onZoomOut },
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



	    // Listen to vertical scroll events 
	    var view = me.ganttTreePanel.getView();
	    view.on('bodyscroll',this.onTreePanelScroll, me);

            // Listen to any changes in store records
            me.taskTreeStore.on({'update': me.onTaskTreeStoreUpdate, 'scope': this});

            return this;
        },

	/**
	 * The user moves the scroll bar of the treePanel.
	 * Now scroll the ganttBarPanel in the same way.
	 */
	onTreePanelScroll: function(event, treeview) {
	    var me = this;
	    var ganttTreePanel = me.ganttTreePanel;
	    var ganttBarPanel = me.ganttBarPanel;
	    var view = ganttTreePanel.getView();
	    var scroll = view.getEl().getScroll();
            if (me.debug) console.log('GanttButtonController.onTreePanelScroll: Starting: '+scroll.top);

	    var scrollableEl = ganttBarPanel.getEl();                       // Ext.dom.Element that enables scrolling
	    scrollableEl.setScrollTop(scroll.top);

            if (me.debug) console.log('GanttButtonController.onTreePanelScroll: Finished');
	},

        /**
         * The user has reloaded the project data and therefore
         * discarded any browser-side changes. So disable the 
         * "Save" button now.
         */
        onButtonReload: function() {
            if (me.debug) console.log('GanttButtonController.ButtonReload');
            var buttonSave = Ext.getCmp('buttonSave');
            buttonSave.setDisabled(true);
        },

        onButtonSave: function() {
            if (me.debug) console.log('GanttButtonController.ButtonSave');
            var me = this;
            me.taskTreeStore.save();
            // Now block the "Save" button, unless some data are changed.
            var buttonSave = Ext.getCmp('buttonSave');
            buttonSave.setDisabled(true);
        },

        /**
         * Some record of the taskTreeStore has changed.
         * Enable the "Save" button to save these changes.
         */
        onTaskTreeStoreUpdate: function() {
	    var me = this;
            // if (me.debug) console.log('GanttButtonController.onTaskTreeStoreUpdate');
            var me = this;
            var buttonSave = Ext.getCmp('buttonSave');
            buttonSave.setDisabled(false);					// Allow to "save" changes

	    // fraber 150730: Disabled. This will probably cause trouble
	    // However, we need to add the redraws() at the topmost level.
            // me.ganttBarPanel.redraw();
        },

        onButtonMaximize: function() {
	    var me = this;
            if (me.debug) console.log('GanttButtonController.onButtonMaximize');
            var buttonMaximize = Ext.getCmp('buttonMaximize');
            var buttonMinimize = Ext.getCmp('buttonMinimize');
            buttonMaximize.setVisible(false);
            buttonMinimize.setVisible(true);

            var renderDiv = Ext.get("@gantt_editor_id@");
            renderDiv.setWidth('100%');
            renderDiv.setHeight('100%');
	    renderDiv.applyStyles({ 
		'position':'absolute',
		'z-index': '2000',
		'left': '0',
		'top': '0'
	    });
	        
	    resizeController.onSwitchToFullScreen();
        },

        onButtonMinimize: function() {
	    var me = this;
            if (me.debug) console.log('GanttButtonController.onButtonMinimize');
            var buttonMaximize = Ext.getCmp('buttonMaximize');
            var buttonMinimize = Ext.getCmp('buttonMinimize');
            buttonMaximize.setVisible(true);
            buttonMinimize.setVisible(false);

            var renderDiv = Ext.get("@gantt_editor_id@");
            renderDiv.setWidth('auto');
            renderDiv.setHeight('auto');
            renderDiv.applyStyles({
                'position':'relative',
                'z-index': '0',
            });

            resizeController.onSwitchBackFromFullScreen();
        },

        onZoomIn: function() {
            if (me.debug) console.log('GanttButtonController.onZoomIn');
            this.ganttBarPanel.onZoomIn();
        },

        onZoomOut: function() {
            if (me.debug) console.log('GanttButtonController.onZoomOut');
            this.ganttBarPanel.onZoomOut();
        },

        /**
         * Control the enabled/disabled status of the (-) (Delete) button
         */
        onTreePanelSelectionChange: function(view, records) {
	    var me = this;
            if (me.debug) console.log('GanttButtonController.onTreePanelSelectionChange');
            var buttonDelete = Ext.getCmp('buttonDelete');

            if (1 == records.length) {						// Exactly one record enabled
                var record = records[0];
                buttonDelete.setDisabled(!record.isLeaf());
            } else {								// Zero or two or more records enabled
                buttonDelete.setDisabled(true);
            }
        },

        /**
         * Disable default tree key actions
         */
        onBeforeCellKeyDown: function(me, htmlTd, cellIndex, record, htmlTr, rowIndex, e, eOpts ) {
	    var me = this;
            var keyCode = e.getKey();
            var keyCtrl = e.ctrlKey;
            if (me.debug) console.log('GanttButtonController.onBeforeCellKeyDown: code='+keyCode+', ctrl='+keyCtrl);
            var panel = this;
            switch (keyCode) {
            case 8:								// Backspace 8
                panel.onButtonDelete();
                break;
            case 37:								// Cursor left
                if (keyCtrl) {
		    // ToDo: moved to GanttTreePanelController
                    panel.onButtonReduceIndent();
                    return false;						// Disable default action (fold tree)
                }
                break;
            case 39:								// Cursor right
                if (keyCtrl) {
		    // ToDo: moved to GanttTreePanelController
                    panel.onButtonIncreaseIndent();
                    return false;						// Disable default action (unfold tree)
                }
                break;
            case 45:								// Insert 45
                panel.onButtonAdd();
                break;
            case 46:								// Delete 46
                panel.onButtonDelete();
                break;
            }
            return true;							// Enable default TreePanel actions for keys
        },

        /**
         * Handle various key actions
         */
        onCellKeyDown: function(table, htmlTd, cellIndex, record, htmlTr, rowIndex, e, eOpts) {
            var keyCode = e.getKey();
            var keyCtrl = e.ctrlKey;
            // if (me.debug) console.log('GanttButtonController.onCellKeyDown: code='+keyCode+', ctrl='+keyCtrl);
        }
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
    var ganttBarPanelController = Ext.create('GanttEditor.controller.GanttBarPanelController', {
	debug: debug
    });
    ganttBarPanelController.init(this);

    // Outer Gantt editor jointing the two parts (TreePanel + Draw)
    var ganttPanelContainer = Ext.create('PO.view.gantt_editor.GanttButtonPanel', {
	debug: debug,
        resizable: true,							// Add handles to the panel, so the user can change size
        items: [
            ganttTreePanel,
            ganttBarPanel
        ],
        renderTo: '@gantt_editor_id@'
    });

    // Controller that deals with button events.
    var ganttButtonController = Ext.create('PO.controller.gantt_editor.GanttButtonController', {
	debug: debug,
        'ganttPanelContainer': ganttPanelContainer,
        'ganttTreePanel': ganttTreePanel,
        'ganttBarPanel': ganttBarPanel,
        'taskTreeStore': taskTreeStore
    });
    ganttButtonController.init(this).onLaunch(this);

    // Contoller to handle size and resizing related events
    var resizeController = Ext.create('PO.controller.ResizeController', {
	debug: debug,
        'ganttPanelContainer': ganttPanelContainer,
        'ganttTreePanel': ganttTreePanel,
        'ganttBarPanel': ganttBarPanel
    });
    resizeController.init(this).onLaunch(this);
    resizeController.onResize();						// Set the size of the outer GanttButton Panel

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
        'ganttTreePanel': ganttTreePanel
    });
    ganttSchedulingController.init(this).onLaunch(this);

    /*
    // Open the TaskPropertyPanel in order to speedup debugging
    var root = taskTreeStore.getRootNode();
    var mainProject = root.childNodes[0];
    var firstTask = mainProject.childNodes[1];
    taskPropertyPanel.setValue(firstTask);
    taskPropertyPanel.setActiveTab('taskPropertyAssignments');
    taskPropertyPanel.show();
    */
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
    // Ext.get("@gantt_editor_id@").on('contextmenu', function(ev) { ev.preventDefault(); });  // Disable Right-click context menu on browser background
    var debug = true;

    var taskTreeStore = Ext.create('PO.store.timesheet.TaskTreeStore');
    var senchaPreferenceStore = Ext.create('PO.store.user.SenchaPreferenceStore');
    var taskStatusStore = Ext.create('PO.store.timesheet.TaskStatusStore');
    var projectMemberStore = Ext.create('PO.store.user.UserStore', {storeId: 'projectMemberStore'});
    var userStore = Ext.create('PO.store.user.UserStore', {storeId: 'userStore'});

    // Store Coodinator starts app after all stores have been loaded:
    var coordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
	debug: debug,
        stores: [
            'taskTreeStore',
            'taskStatusStore',
            'senchaPreferenceStore',
            'projectMemberStore'
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

    // Get the list of users assigned to this project
    projectMemberStore.getProxy().extraParams = { 
        format: 'json',
        query: 'user_id in (select object_id_two from acs_rels where object_id_one = @project_id@)'
    };
    projectMemberStore.load();

    // Load stores that need parameters
    taskTreeStore.getProxy().extraParams = { project_id: @project_id@ };
    taskTreeStore.load({
        callback: function() {
	    if (debug) console.log('PO.store.timesheet.TaskTreeStore: loaded');
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

