/*
 * GanttTreePanelController.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/**
 * Deal with collapsible tree nodes, keyboard commands
 * and the interaction with the GanttBarPanel.
 */
Ext.define('GanttEditor.controller.GanttButtonController', {
    extend: 'Ext.app.Controller',
    debug: true,
    'ganttTreePanel': null,						// Set during init: left-hand task tree panel
    'ganttBarPanel': null,						// Set during init: right-hand surface with Gantt sprites
    'taskTreeStore': null,						// Set during init: treeStore with task data
    'ganttPanelContainer': null,
    'resizeController': null,

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
        // if (me.debug) console.log('GanttButtonController.onTreePanelScroll: Starting: '+scroll.top);
        var ganttBarScrollableEl = ganttBarPanel.getEl();                       // Ext.dom.Element that enables scrolling
        ganttBarScrollableEl.setScrollTop(scroll.top);
        // if (me.debug) console.log('GanttButtonController.onTreePanelScroll: Finished');
    },

    /**
     * The user has reloaded the project data and therefore
     * discarded any browser-side changes. So disable the 
     * "Save" button now.
     */
    onButtonReload: function() {
        var me = this;
        if (me.debug) console.log('GanttButtonController.ButtonReload');
        var buttonSave = Ext.getCmp('buttonSave');
        buttonSave.setDisabled(true);
    },

    /**
     * The user has pressed the "Save" button - save and report
     * any error messages
     */
    onButtonSave: function() {
        var me = this;
        if (me.debug) console.log('GanttButtonController.ButtonSave');
        me.taskTreeStore.save({
	    failure: function(batch, context) { 
		var msg = batch.proxy.reader.jsonData.message;
		if (!msg) msg = 'undefined error';
		// Ext.MessageBox.minWidth = 500;

		var msgBox = Ext.create('Ext.window.MessageBox');
		msgBox.show({
		    title: 'Server Error', 
		    msg: "Error saving data on the server side.<br>&nbsp;<br>"+
			"Send error message to ]project-open[ for incident reporting?<br>"+
			"Please see our <a href='http://www.project-open.com/en/company/project-open-privacy.html'>privacy statementy</a> "+
			"for details.<br><pre>" + msg+"</pre>",
		    minWidth: 500,
		    buttonText: { yes: "Report this Error" },
		    icon: Ext.Msg.QUESTION,
		    fn: function(text) {
			if (text == 'yes') {
			    Ext.Ajax.request({
				url: "http://www.project-open.net/intranet-forum/new-system-incident",
				method: 'POST',
				headers: { 
				    'Content-Type': 'multipart/form-data',
				    'Access-Control-Allow-Origin': '*'
				},
				params : {
				    privacy_statement_p: 't', no_master_p: '1', error_info: msg,
				    error_url: '@error_url;noquote@', error_location: '@error_location@',
				    error_type: '@error_type@', report_url: '@report_url@',system_url: '@system_url@',
				    error_first_names: '@first_names@', error_last_name: '@last_name@',  error_email: '@email@',
				    username: '@username@',
				    publisher_name: '@publisher_name@',
				    package_versions: '@package_versions@',
				    system_id: '@system_id@', hardware_id: '@hardware_id@',
				    platform: '@platform@', os: '@os@', os_version: '@os_version@'
				},
				success: function(response) {
				    var text = response.responseText;
				    Ext.Msg.alert('Successfully reported', text);
				},
				failure: function(response) {
				    var text = response.responseText;
				    Ext.Msg.alert('Error reporting incident', 'Error reporting incident.<br>'+text);
				},
			    });
			}
		    }
		});
	    }
	});
        // Now block the "Save" button, unless some data are changed.
        var buttonSave = Ext.getCmp('buttonSave');
//        buttonSave.setDisabled(true);
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

        me.ganttBarPanel.needsRedraw = true;				// Tell the ganttBarPanel to redraw with the next frame
    },

    /**
     * Maximize Button: Expand the editor DIV, so that
     * it fills the entire browser screen.
     */
    onButtonMaximize: function() {
        var me = this;
        var buttonMaximize = Ext.getCmp('buttonMaximize');
        var buttonMinimize = Ext.getCmp('buttonMinimize');
        buttonMaximize.setVisible(false);
        buttonMinimize.setVisible(true);
        me.resizeController.onSwitchToFullScreen();
    },

    onButtonMinimize: function() {
        var me = this;
        var buttonMaximize = Ext.getCmp('buttonMaximize');
        var buttonMinimize = Ext.getCmp('buttonMinimize');
        buttonMaximize.setVisible(true);
        buttonMinimize.setVisible(false);
        me.resizeController.onSwitchBackFromFullScreen();
    },

    onZoomIn: function() {
        var me = this;
	alert('GanttButtonController.onZoomIn: ToDo: remove');
        if (me.debug) console.log('GanttButtonController.onZoomIn');
        this.ganttBarPanel.onZoomIn();
    },

    onZoomOut: function() {
        var me = this;
	alert('GanttButtonController.onZoomOut: ToDo: remove');
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
        var me = this;
        var keyCode = e.getKey();
        var keyCtrl = e.ctrlKey;
        // if (me.debug) console.log('GanttButtonController.onCellKeyDown: code='+keyCode+', ctrl='+keyCtrl);
    }
});
