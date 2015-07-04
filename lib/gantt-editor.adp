<div id="@gantt_editor_id@" style="overflow: hidden; -webkit-user-select: none; -moz-user-select: none; -khtml-user-select: none; -ms-user-select: none; ">
<script type='text/javascript'>

// Ext.Loader.setConfig({enabled: true});
Ext.Loader.setPath('PO', '/sencha-core');

Ext.require([
    'Ext.data.*',
    'Ext.grid.*',
    'Ext.tree.*',
    'Ext.ux.CheckColumn',
    'PO.Utilities',
    'PO.class.CategoryStore',
    'PO.controller.StoreLoadCoordinator',
    'PO.store.timesheet.TaskTreeStore',
    'PO.store.timesheet.TaskStatusStore',
    'PO.model.timesheet.TimesheetTask',
    'PO.store.user.SenchaPreferenceStore',
    'PO.store.user.UserStore',
    'PO.view.field.POComboGrid',
    'PO.view.field.PODateField',						// Custom ]po[ Date editor field
    'PO.view.field.POTaskAssignment',
    'PO.view.gantt.AbstractGanttPanel',
    'PO.view.gantt.GanttBarPanel',
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
        slaId: 1478943					                	// ID of the ]po[ "PD Gantt Editor" project
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
     * GanttPanelContainer
     */
    Ext.define('PO.view.gantt_editor.GanttPanelContainer', {
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
        debug: true,
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

            // Listen to any changes in store records
            me.taskTreeStore.on({'update': me.onTaskTreeStoreUpdate, 'scope': this});

            return this;
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
            if (me.debug) console.log('GanttButtonController.onTaskTreeStoreUpdate');
            var me = this;
            var buttonSave = Ext.getCmp('buttonSave');
            buttonSave.setDisabled(false);					// Allow to "save" changes

            me.ganttBarPanel.redraw();
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
	        
	    ganttResizeController.onSwitchToFullScreen();
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

            ganttResizeController.onSwitchBackFromFullScreen();
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
                    panel.onButtonReduceIndent();
                    return false;						// Disable default action (fold tree)
                }
                break;
            case 39:								// Cursor right
                if (keyCtrl) {
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

    /*
     * GanttResizeController
     * This controller is responsible for editor geometry and resizing:
     * <ul>
     * <li>The boundaries of the outer window
     * <li>The separator between the treePanel and the ganttPanel
     * </ul>
     */
    Ext.define('PO.controller.gantt_editor.GanttResizeController', {
        extend: 'Ext.app.Controller',
        debug: false,
        'ganttPanelContainer': null,						// Defined during initialization
        'ganttTreePanel': null,							// Defined during initialization
        'ganttBarPanel': null,							// Defined during initialization

        refs: [
            { ref: 'ganttTreePanel', selector: '#ganttTreePanel' }
        ],

        init: function() {
            var me = this;
            if (me.debug) { if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController: init'); }

            var sideBarTab = Ext.get('sideBarTab');	    			// ]po[ side-bar collapses the left-hand menu
            sideBarTab.on('click', me.onSideBarResize, me);			// Handle collapsable side menu
            Ext.EventManager.onWindowResize(me.onWindowResize, me);		// Deal with resizing the main window
            me.ganttPanelContainer.on('resize', me.onGanttPanelContainerResize, me);	// Deal with resizing the outer boundaries
            return this;
        },

        /**
         * Adapt the size of the ganttPanelContainer (the outer Gantt panel)
         * to the available drawing area.
         * Takes the size of the browser and subtracts the sideBar at the
         * left and the size of the menu on top.
         */
        onResize: function (sideBarWidth) {
            var me = this;
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onResize: Starting');
            var sideBar = Ext.get('sidebar');					// ]po[ left side bar component

            if (undefined === sideBarWidth) {
                sideBarWidth = sideBar.getSize().width;
            }

            var screenSize = Ext.getBody().getViewSize();			// Total browser size
            var width = screenSize.width - sideBarWidth - 100;			// What's left after ]po[ side borders
            var height = screenSize.height - 280;	  			// What's left after ]po[ menu bar on top
            me.ganttPanelContainer.setSize(width, height);
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onResize: Finished');
        },

        /**
         * Clicked on the ]po[ "side menu" bar for showing/hiding the left-menu
         */
        onSideBarResize: function () {
            var me = this;
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onSidebarResize: Starting');
            var sideBar = Ext.get('sidebar');					// ]po[ left side bar component
            var sideBarWidth = sideBar.getSize().width;
            // We get the event _before_ the sideBar has changed it's size.
            // So we actually need to the the oposite of the sidebar size:
            if (sideBarWidth > 100) {
                sideBarWidth = 2;						// Determines size when Sidebar collapsed
            } else {
                sideBarWidth = 245;						// Determines size when Sidebar visible
            }
            me.onResize(sideBarWidth);						// Perform actual resize
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onSidebarResize: Finished');
        },

        /**
         * The user changed the size of the browser window
         */
        onWindowResize: function () {
            var me = this;
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onWindowResize: Starting');

	    if (!me.fullScreenP) {
		var sideBar = Ext.get('sidebar');// ]po[ left side bar component
		var sideBarWidth = sideBar.getSize().width;
		if (sideBarWidth > 100) {
		    sideBarWidth = 340;// Determines size when Sidebar visible
		} else {
		    sideBarWidth = 85;// Determines size when Sidebar collapsed
		}
		me.onResize(sideBarWidth);
	    } else {
		me.onSwitchToFullScreen();
	    }
	        
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onWindowResize: Finished');
        },

        /**
         * Manually changed the size of the ganttPanelContainer
         */
        onGanttPanelContainerResize: function () {
            var me = this;
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onGanttPanelContainerResize: Starting');
            me.ganttBarPanel.redraw();						// Perform actual resize
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onGanttPanelContainerResize: Finished');
        },

	onSwitchToFullScreen: function () {
            var me = this;
	    me.fullScreenP = true; 
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onSwitchToFullScreen: Starting');
	    me.ganttPanelContainer.setSize(Ext.getBody().getViewSize().width, Ext.getBody().getViewSize().height);
	    me.ganttBarPanel.setSize(Ext.getBody().getViewSize().width, Ext.getBody().getViewSize().height);
            me.ganttBarPanel.redraw();
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onSwitchToFullScreen: Finished');
        },

        onSwitchBackFromFullScreen: function () {
            var me = this;
	    me.fullScreenP = false; 
	        
            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onSwitchBackFromFullScreen: Starting');
	        
            var sideBar = Ext.get('sidebar');                                   // ]po[ left side bar component
            var sideBarWidth = sideBar.getSize().width;
	        
            if (undefined === sideBarWidth) {
                sideBarWidth = Ext.get('sidebar').getSize().width;
            }
	        
            var screenSize = Ext.getBody().getViewSize();
            var width = screenSize.width - sideBarWidth - 100;
            var height = screenSize.height - 280;
	        
            me.ganttPanelContainer.setSize(width, height);

            if (me.debug) console.log('PO.controller.gantt_editor.GanttResizeController.onSwitchBackFromFullScreen: Finished');
        }
    });

    /*
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
    Ext.define('PO.controller.gantt_editor.GanttSchedulingController', {
        extend: 'Ext.app.Controller',
        debug: false,
        'ganttTreePanel': null,							// Defined during initialization
        'taskTreeStore': null,							// Defined during initialization
        init: function() {
            var me = this;
            if (me.debug) { if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.init: Starting'); }

            me.taskTreeStore.on({
                'update': me.onTreeStoreUpdate,					// Listen to any changes in store records
                'scope': this
            });

            if (me.debug) { if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.init: Finished'); }
            return this;
        },

        onTreeStoreUpdate: function(treeStore, model, operation, fieldsChanged, event) {
            var me = this;
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Starting');
            fieldsChanged.forEach(function(fieldName) {
                if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Field changed='+fieldName);
                switch (fieldName) {
                case "start_date":
                    me.onStartDateChanged(treeStore, model, operation, event);
                    break;
                case "end_date":
                    me.onEndDateChanged(treeStore, model, operation, event);
                    break;
                }
            });
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onTreeStoreUpdate: Finished');
        },

        /**
         * The start_date of a task has changed.
         * Check if this new date is before the start_date of it's parent.
         * In this case we need to adjust the parent.
         */
        onStartDateChanged: function(treeStore, model, operation, event) {
            var me = this;
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Starting');
            var parent = model.parentNode;					// 
            if (!parent) return;
	    var parent_start_date = parent.get('start_date');
	    if ("" == parent_start_date) return;
            var parentStartDate = PO.Utilities.pgToDate(parent_start_date);

            // Calculate the minimum start date of all siblings
            var minStartDate = PO.Utilities.pgToDate('2099-12-31');
            parent.eachChild(function(sibling) {
                var siblingStartDate = PO.Utilities.pgToDate(sibling.get('start_date'));
                if (siblingStartDate.getTime() < minStartDate.getTime()) {
                    minStartDate = siblingStartDate;
                }
            });

            // Check if we have to update the parent
            if (parentStartDate.getTime() != minStartDate.getTime()) {
                // The siblings start different than the parent - update the parent.
                if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onStartDateChanged: Updating parent at level='+parent.getDepth());
                parent.set('start_date', PO.Utilities.dateToPg(minStartDate));				// This will call this event recursively
            }
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

            var parent = model.parentNode;
            if (!parent) return;
            var parent_end_date = parent.get('end_date');
	    if ("" == parent_end_date) return;
            var parentEndDate = PO.Utilities.pgToDate(parent_end_date);

            // Calculate the maximum end date of all siblings
            var maxEndDate = PO.Utilities.pgToDate('2000-01-01');
            parent.eachChild(function(sibling) {
                var siblingEndDate = PO.Utilities.pgToDate(sibling.get('end_date'));
                if (siblingEndDate.getTime() > maxEndDate.getTime()) {
                    maxEndDate = siblingEndDate;
                }
            });

            // Check if we have to update the parent
            if (parentEndDate.getTime() != maxEndDate.getTime()) {
                // The siblings end different than the parent - update the parent.
                if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Updating parent at level='+parent.getDepth());
                parent.set('end_date', PO.Utilities.dateToPg(maxEndDate));					// This will call this event recursively
            }
            if (me.debug) console.log('PO.controller.gantt_editor.GanttSchedulingController.onEndDateChanged: Finished');
        },
    });

    // Left-hand side task tree
    var ganttTreePanel = Ext.create('PO.view.gantt.GanttTreePanel', {
	debug: debug,
        width:		500,
        region:		'west',
        store:		taskTreeStore
    });

    // Right-hand side Gantt display
    var reportStartTime = PO.Utilities.pgToDate('@report_start_date@').getTime();
    var reportEndTime = PO.Utilities.pgToDate('@report_end_date@').getTime();
    var ganttBarPanel = Ext.create('PO.view.gantt.GanttBarPanel', {
        region: 'center',
        viewBox: false,
        width: 600,
        height: 500,

	debug: debug,
	axisEndX: 2000,
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
    var ganttPanelContainer = Ext.create('PO.view.gantt_editor.GanttPanelContainer', {
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
    var ganttResizeController = Ext.create('PO.controller.gantt_editor.GanttResizeController', {
	debug: debug,
        'ganttPanelContainer': ganttPanelContainer,
        'ganttTreePanel': ganttTreePanel,
        'ganttBarPanel': ganttBarPanel
    });
    ganttResizeController.init(this).onLaunch(this);
    ganttResizeController.onResize();						// Set the size of the outer GanttButton Panel

    // Create the panel showing properties of a task,
    // but don't show it yet.
    var taskPropertyPanel = Ext.create("PO.view.gantt.GanttTaskPropertyPanel", {
	debug: debug
    });
    taskPropertyPanel.hide();

    // Deal with changes of Gantt data and perform scheduling
    var ganttSchedulingController = Ext.create('PO.controller.gantt_editor.GanttSchedulingController', {
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

