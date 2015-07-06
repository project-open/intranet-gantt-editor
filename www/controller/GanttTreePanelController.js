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
Ext.define('GanttEditor.controller.GanttTreePanelController', {
    extend: 'Ext.app.Controller',
    requires: ['Ext.app.Controller'],
    refs: [
	{ref: 'ganttBarPanel', selector: '#ganttBarPanel'},
	{ref: 'ganttTreePanel', selector: '#ganttTreePanel'}
    ],

    init: function() {
	this.control({
	    '#ganttTreePanel': {
		'itemcollapse': this.onItemCollapse,
		'itemexpand': this.onItemExpand
	    },
	    '#buttonReduceIndent': { click: this.onButtonReduceIndent},
            '#buttonIncreaseIndent': { click: this.onButtonIncreaseIndent},
            '#buttonAdd': { click: this.onButtonAdd},
            '#buttonDelete': { click: this.onButtonDelete}
	});
    },

    redrawGanttBarPanel: function() {
	console.log('PO.controller.GanttTreePanelController.redrawGanttBarPanel');
	var ganttBarPanel = this.getGanttBarPanel();
	ganttBarPanel.redraw();
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

        me.getGanttBarPanel().redraw();
    },

    /**
     * The user has expanded a super-task in the GanttTreePanel.
     * Please see onItemCollapse for further documentation.
     */
    onItemExpand: function(taskModel) {
        var me = this;
        if (me.debug) console.log('PO.class.GanttDrawComponent.onItemExpand: ');

        // Remember the new state
        var object_id = taskModel.get('id');
        Ext.Ajax.request({
            url: '/intranet/biz-object-tree-open-close.tcl',
            params: { 'object_id': object_id, 'open_p': 'o' }
        });
        me.getGanttBarPanel().redraw();
    },

    /**
     * Move the task more to the right if possible.
     *
     * Take the node just above the selected one and 
     * make this node a child of it.
     */
    onButtonIncreaseIndent: function() {
	var me = this;
        if (me.debug) console.log('GanttTreePanel.onButtonIncreaseIndent');
	var ganttTreePanel = this.getGanttTreePanel();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = lastSelected.parentNode;
        if (null == lastSelectedParent) { return; }					// We can't indent the root element

        var lastSelectedIndex = lastSelectedParent.indexOf(lastSelected);
        var prevNodeIndex = lastSelectedIndex -1;
        if (prevNodeIndex < 0) { return; }						// We can't indent the root element

        var prevNode = lastSelectedParent.getChildAt(prevNodeIndex);

        // Remove the item from the tree
        prevNode.set('leaf', false);
        prevNode.appendChild(lastSelected);			// Add to the previous node as a child
        prevNode.expand();

        ganttTreePanel.getView().focusNode(lastSelected);        // Focus back on the task, so that it will accept the next keyboard commands

        // ToDo: It seems the TreePanel looses focus here
        // selectionModel.select(lastSelected);
        // selectionModel.setLastFocused(lastSelected);
    },

    /**
     * Move the task more to the left if possible.
     */
    onButtonReduceIndent: function() {
	var me = this;
        if (me.debug) console.log('GanttTreePanel.onButtonReduceIndent');

	var ganttTreePanel = this.getGanttTreePanel();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = lastSelected.parentNode;
        if (null == lastSelectedParent) { return; }					// We can't indent the root element
        var lastSelectedParentParent = lastSelectedParent.parentNode;
        if (null == lastSelectedParentParent) { return; }				// We can't indent the root element
        var lastSelectedParentIndex = lastSelectedParentParent.indexOf(lastSelectedParent);
        lastSelectedParentParent.insertChild(lastSelectedParentIndex+1, lastSelected);

        // Check if the parent has now become a leaf
        var parentNumChildren = lastSelectedParent.childNodes.length;
        if (0 == parentNumChildren) {
            lastSelectedParent.set('leaf', true);
        }

        ganttTreePanel.getView().focusNode(lastSelected);        // Focus back on the task, so that it will accept the next keyboard commands
    },
    
    /**
     * "Add" (+) button pressed.
     * Insert a new task in the position of the last selection.
     */
    onButtonAdd: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttTreePanel.onButtonAdd: ');
	var ganttTreePanel = me.getGanttTreePanel();
        var rowEditing = ganttTreePanel.plugins[0];
        var taskTreeStore = ganttTreePanel.getStore();
        var root = taskTreeStore.getRootNode();

        rowEditing.cancelEdit();
        taskTreeStore.sync();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = null;

        if (null == lastSelected) {
            lastSelected = root;	 			// Use the root as the last selected node
            lastSelectedParent = root;
        } else {
            lastSelectedParent = lastSelected.parentNode;
        }

	// Create a model instance and decorate with NodeInterface
        var r = Ext.create('PO.model.timesheet.TimesheetTask', {
            project_name: "New Task",
            project_nr: "task_0018",
            parent_id: lastSelected.get('parent_id'),
            company_id: lastSelected.get('company_id'),
            start_date: new Date().toISOString().substring(0,10),
            end_date: new Date().toISOString().substring(0,10),
            percent_completed: '0',
            project_status_id: '76',
            project_type_id: '100',
	    assignees: []
        });
        var rNode = root.createNode(r);
        rNode.set('leaf', true);					// Leafs show a different icon than folders

        var appendP = false;
        if (!selectionModel.hasSelection()) { appendP = true; }
        if (root == lastSelected) { appendP = true; }
        if (lastSelected.getDepth() <= 1) { appendP = true; }			// Don't allow to add New Task before the root.
        if (appendP) {
            root.appendChild(rNode);	 				// Add the task at the end of the root
        } else {
            lastSelectedParent.insertBefore(rNode, lastSelected);	    // Insert into tree
        }

        // Start the column editor
        selectionModel.deselectAll();
        selectionModel.select([rNode]);
        rowEditing.startEdit(rNode, 0);
    },

    /**
     * "Delete" (-) button pressed.
     * Delete the currently selected task from the tree.
     */
    onButtonDelete: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttTreePanel.onButtonDelete: ');

	var ganttTreePanel = me.getGanttTreePanel();
        var rowEditing = ganttTreePanel.plugins[0];
        var taskTreeStore = ganttTreePanel.getStore();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = lastSelected.parentNode;
        var lastSelectedIndex = lastSelectedParent.indexOf(lastSelected);

        rowEditing.cancelEdit();

        // Remove the selected element
        lastSelected.remove();

        // Select the next node
        var newNode = lastSelectedParent.getChildAt(lastSelectedIndex);
        if (typeof(newNode) == "undefined") {
            lastSelectedIndex = lastSelectedIndex -1;
            if (lastSelectedIndex < 0) { lastSelectedIndex = 0; }
            newNode = lastSelectedParent.getChildAt(lastSelectedIndex);
        }

        if (typeof(newNode) == "undefined") {
            // lastSelected was the last child of it's parent, so select the parent.
            selectionModel.select(lastSelectedParent);
        } else {
            newNode = lastSelectedParent.getChildAt(lastSelectedIndex);
            selectionModel.select(newNode);
        }
        
    },

    /**
     * The user has clicked below the last task.
     * We will interpret this as the request to create a new task at the end.
     */
    onContainerClick: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttTreePanel.onContainerClick: ');

        // Clear the selection in order to force adding the task at the bottom
	var ganttTreePanel = me.getGanttTreePanel();
        var selectionModel = ganttTreePanel.getSelectionModel();
        selectionModel.deselectAll();

        me.onButtonAdd();
    }

});
