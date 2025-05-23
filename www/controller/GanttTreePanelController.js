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

    ganttTreePanel: null,
    senchaPreferenceStore: null,

    init: function() {
        var me = this;
        this.control({
            '#ganttTreePanel': {
                'itemcollapse': this.onItemCollapse,
                'itemexpand': this.onItemExpand
            },
            '#buttonReduceIndentGantt': { click: this.onButtonReduceIndent},
            '#buttonIncreaseIndentGantt': { click: this.onButtonIncreaseIndent},
            '#buttonAddGantt': { click: this.onButtonAdd},
            '#buttonDeleteGantt': { click: this.onButtonDelete},

            // Redraw GanttBars after changing the configuration
            '#config_menu_show_project_dependencies': { click: this.redrawGanttBarPanel},
            '#config_menu_show_project_assigned_resources': { click: this.redrawGanttBarPanel}
        });

        // Listen to drop events from tree drag-and-drop
        if (null != me.ganttTreePanel) {
            var ganttTreeView = me.ganttTreePanel.getView();
            ganttTreeView.on({
                'drop': me.onGanttTreePanelDrop,
                'scope': this
            });;
        }
    },


    /**
     * Show a warning that the GanttEditor is Beta
     */
    readOnlyWarning: function() {
        var me = this;
        console.log('PO.controller.GanttTreePanelController.readOnlyWarning');

        if (0 == write_project_p) {
            Ext.Msg.alert("Read-Only Mode",
                      "<nobr>You don't have write permissions on this project.</nobr><br>"+
                      "<nobr>You won't be able to save your changes.</nobr><br>"+
                      "Please contact the project manager and request write permissions." +
                      "<br>&nbsp;<br>"
            );

        } else {
            Ext.Msg.alert('This software is Beta',
                      '<nobr>This software is in Beta state and contains a number of known</nobr><br>'+
                      'and unknown issues (please see the "This is Beta") menu.<br> ' +
                      '<br>' +
                      'However, many users have asked for this feature and use this<br>' +
                      'Gantt Editor already successfully, working around existing issues.<br> ' +
                      '<br>' +
                      'In order to start working with the Gantt Editor, please uncheck<br>' +
                      'the Configuration -> Read Only option.<br>&nbsp;<br>'
            );
        }
    },

    /**
     * Request a redraw of the Gantt bars
     */
    redrawGanttBarPanel: function() {
        var me = this;
        console.log('PO.controller.GanttTreePanelController.redrawGanttBarPanel');
        var ganttBarPanel = me.getGanttBarPanel();
        ganttBarPanel.needsRedraw = true;
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

        // me.getGanttBarPanel().redraw();
        me.getGanttBarPanel().needsRedraw = true;
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

        me.getGanttBarPanel().needsRedraw = true;					// Force delayed redraw
    },

    /**
     * Move the task more to the right if possible.
     *
     * Take the node just above the selected one and 
     * make this node a child of it.
     */
    onButtonIncreaseIndent: function() {
        var me = this;
        if (me.debug) console.log('GanttTreePanelController.onButtonIncreaseIndent');

        // Check if read-only and abort in this case
        // var readOnly = me.senchaPreferenceStore.getPreferenceBoolean('read_only',true);
        // if (readOnly) { me.readOnlyWarning(); return; }

        var ganttTreePanel = this.getGanttTreePanel();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = lastSelected.parentNode;
        if (null == lastSelectedParent) { return; }					// We can't indent the root element

        var lastSelectedIndex = lastSelectedParent.indexOf(lastSelected);
        var prevNodeIndex = lastSelectedIndex -1;
        if (prevNodeIndex < 0) { return; }						// We can't indent the root element
        var prevNode = lastSelectedParent.getChildAt(prevNodeIndex);

        me.treeRenumberStoreOldValues();     						// Remember the current values of WBS field

        // Add the item as a child of the prevNode
        prevNode.set('leaf', false);
        prevNode.appendChild(lastSelected);						// Add to the previous node as a child
        prevNode.expand();
        var prevNodeId = ""+prevNode.get('id');

        // Set the parent_id of the indented item
        lastSelected.set('parent_id', prevNodeId);					// This should trigger a Gantt re-schedule

        ganttTreePanel.getView().focusNode(lastSelected);				// Focus back on the task for keyboard commands

        me.treeRenumber(); 								// Update the tree's task numbering
        me.getGanttBarPanel().needsRedraw = true;					// Force delayed redraw
        // ToDo: Re-schedule the tree

    },

    /**
     * Move the task more to the left if possible.
     */
    onButtonReduceIndent: function() {
        var me = this;
        if (me.debug) console.log('GanttTreePanelController.onButtonReduceIndent');

        // Check if read-only and abort in this case
        // var readOnly = me.senchaPreferenceStore.getPreferenceBoolean('read_only',true);
        // if (readOnly) { me.readOnlyWarning(); return; }

        var ganttTreePanel = this.getGanttTreePanel();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = lastSelected.parentNode;
        if (null == lastSelectedParent) { return; }					// We can't indent the root element
        var lastSelectedParentParent = lastSelectedParent.parentNode;
        if (null == lastSelectedParentParent) { return; }				// We can't indent the root element
        var lastSelectedParentIndex = lastSelectedParentParent.indexOf(lastSelectedParent);

        // Baseline the old WBS values
        me.treeRenumberStoreOldValues();     						// Remember the current values of WBS field

        // Move the child
        lastSelectedParentParent.insertChild(lastSelectedParentIndex+1, lastSelected);

        // Check if the parent has now become a leaf
        var parentNumChildren = lastSelectedParent.childNodes.length;
        if (0 == parentNumChildren) {
            lastSelectedParent.set('leaf', true);
        }

        ganttTreePanel.getView().focusNode(lastSelected);				// Focus back on the task for keyboard commands

        me.treeRenumber(); 								// Update the tree's task numbering
        me.getGanttBarPanel().needsRedraw = true;					// Force delayed redraw
    },
    
    /**
     * "Add" (+) button pressed.
     * Insert a new task in the position of the last selection.
     */
    onButtonAdd: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttTreePanelController.onButtonAdd: ');

        // Check if read-only and abort in this case
        // var readOnly = me.senchaPreferenceStore.getPreferenceBoolean('read_only',true);
        // if (readOnly) { me.readOnlyWarning(); return; }

        var ganttTreePanel = me.getGanttTreePanel();
        var rowEditing = ganttTreePanel.plugins[0];
        var taskTreeStore = ganttTreePanel.getStore();
        var root = taskTreeStore.getRootNode();
        me.treeRenumberStoreOldValues();     						// Remember the current values of WBS field


        rowEditing.cancelEdit();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = null;

        if (null == lastSelected) {
            lastSelected = root;						// This should be the main project
            lastSelectedParent = root;	 						// This is the "virtual" and invisible root of the tree
        } else {
            lastSelectedParent = lastSelected.parentNode;
        }

        // Create a model instance and decorate with NodeInterface
        var parent_id = lastSelected.get('parent_id');
        if ("" == parent_id) { parent_id = lastSelected.get('id'); }
        var r = Ext.create('PO.model.timesheet.TimesheetTask', {
            parent_id: ""+parent_id,
            company_id: lastSelected.get('company_id'),
            project_status_id: "76",							// Status: Open - status store uses strings!
            project_type_id: "100",							// Type: Gantt Task
            iconCls: 'icon-task',
            assignees: []
        });
        var rNode = root.createNode(r);							// Convert model into tree node
        rNode.set('leaf', true);							// The new task is a leaf (show different icon)

        var appendP = false;
        if (!selectionModel.hasSelection()) { appendP = true; }
        if (root == lastSelected) { appendP = true; }
        if (lastSelected.getDepth() <= 1) { appendP = true; }				// Don't allow to add New Task before the root.
        if (appendP) {
            root.appendChild(rNode);							// Add the task at the end of the root
        } else {
            // lastSelectedParent.insertBefore(rNode, lastSelected);			// Insert into tree
            // lastSelectedParent.appendChild(rNode);           			// Insert into tree
            var index = lastSelectedParent.indexOf(lastSelected);			// Get the index of the last selected 
            lastSelectedParent.insertChild(index+1,rNode);
        }

        r.set('parent_id', ""+parent_id);						// model uses strings!!
        r.set('percent_completed', ""+0);
        r.set('planned_units', ""+0);
        r.set('billable_units', ""+0);
        r.set('material_id', ""+default_material_id);
        r.set('uom_id', ""+default_uom_id);
        r.set('project_name', 'New Task');
        r.set('work', ""+8);								// 8 hours by default

	var nowDate = PO.Utilities.dateToPg(new Date()).substring(0,10);
        r.set('start_date', nowDate+" 00:00:00");	// Indicates start of the day at 00:00:00
        r.set('end_date', nowDate+" 23:59:59"); 	// Same as start_date, but indicates 23:59:59


        r.set('effort_driven_type_id', ""+default_effort_driven_type_id);

        // Get a server-side object_id for the task
        Ext.Ajax.request({
            url: '/intranet-rest/data-source/next-object-id',
            success: function(response){
                var json = Ext.JSON.decode(response.responseText);
                var object_id_string = json.data.object_id;
                var object_id = parseInt(object_id_string);
                r.set('id', object_id);
                r.set('project_id', object_id_string);
                r.set('task_id', object_id_string);
                if ("" == r.get('project_nr')) r.set('project_nr', "task_"+object_id_string);
            },
            failure: function(response){
                Ext.Msg.alert('Error retreiving object_id from server', 
                              'This error may lead to data-loss for your project. Error: '+response.responseText);
            }
        });

        // For first task in project: Update the root
        lastSelectedParent.set('leaf', false);						// Parent is not a leaf anymore
        lastSelectedParent.expand();							// Expand parent if not yet expanded

        // Start the column editor
        selectionModel.deselectAll();
        selectionModel.select([rNode]);
        rowEditing.startEdit(rNode, 0);

        // select/Highlight the name of the newly created task in order to speedup entering new tasks manually
        var columnHeader = rowEditing.context.column;
        var ed = rowEditing.getEditor(rNode, columnHeader);
        var inputEl = ed.field.inputEl;
        inputEl.dom.select();

        me.treeRenumber();								// Update the tree's task numbering
        me.getGanttBarPanel().needsRedraw = true;					// Force delayed redraw
    },

    /**
     * "Delete" (-) button pressed.
     * Delete the currently selected task from the tree.
     */
    onButtonDelete: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttTreePanelController.onButtonDelete: ');

        // Get all the necessary objects around
        var ganttTreePanel = me.getGanttTreePanel();
        var rowEditing = ganttTreePanel.plugins[0];
        var taskTreeStore = ganttTreePanel.getStore();
        var selectionModel = ganttTreePanel.getSelectionModel();
        var rootNode = taskTreeStore.getRootNode();					// Get the absolute root
        var lastSelected = selectionModel.getLastSelected();
        var lastSelectedParent = lastSelected.parentNode;
        var lastSelectedIndex = lastSelectedParent.indexOf(lastSelected);
        var lastSelectedId = lastSelected.get('id');


        // ----------------------------------------------------------
        // Check for dependencies and delete

        // Iterate through all children of the root node and check if they are visible
        if (me.debug) console.log('PO.view.gantt.GanttTreePanelController.onButtonDelete: about to delete taskId='+lastSelectedId+' from tree');
        rootNode.cascadeBy(function(model) {
            var predecessors = model.get('predecessors');
            for (var i = 0; i < predecessors.length; i++) {
                var pred = predecessors[i];
                var predId = pred.id;
                var predPredId = pred.pred_id;
                if (predPredId == lastSelectedId) {
                    predecessors.splice(i,1);
                    if (me.debug) console.log('PO.view.gantt.GanttTreePanelController.onButtonDelete: deleted: '+
                        'lastSelectedId='+lastSelectedId+', predId='+predId+', predPredId='+predPredId);
                }
            };
        });

        // ----------------------------------------------------------
        // Work with selection in the task tree

        me.treeRenumberStoreOldValues();     						// Remember the current values of WBS field
        rowEditing.cancelEdit();							// Just in case the editor was active...
        lastSelected.remove();								// Remove the selected element

        var numChildren = lastSelectedParent.childNodes.length;				// Check if we deleted the last task of a parent.
        if (0 == numChildren) {								// This parent then becomes a normal task again.
            lastSelectedParent.set('leaf', true);					// Parent is not a leaf anymore
        }

        // Select the next node
        var newNode = lastSelectedParent.getChildAt(lastSelectedIndex);
        if (typeof(newNode) == "undefined") {
            lastSelectedIndex = lastSelectedIndex -1;
            if (lastSelectedIndex < 0) { lastSelectedIndex = 0; }
            newNode = lastSelectedParent.getChildAt(lastSelectedIndex);
        }

        // lastSelected was the last child of it's parent, so select the parent.
        if (typeof(newNode) == "undefined") {
            selectionModel.select(lastSelectedParent);
        } else {
            newNode = lastSelectedParent.getChildAt(lastSelectedIndex);
            selectionModel.select(newNode);
        }

        // Redraw, renumber and enable save button
        me.treeRenumber();								// Update the tree's task numbering


        // ----------------------------------------------------------
        // Finish off

        me.getGanttBarPanel().needsRedraw = true;					// Force delayed redraw
        var buttonSave = Ext.getCmp('buttonSaveGantt');
        buttonSave.setDisabled(false);							// Enable "Save" button

    },

    /**
     * The user has clicked below the last task.
     * We will interpret this as the request to create a new task at the end.
     */
    onContainerClick: function() {
        var me = this;
        if (me.debug) console.log('PO.view.gantt.GanttTreePanelController.onContainerClick: ');

        // Clear the selection in order to force adding the task at the bottom
        var ganttTreePanel = me.getGanttTreePanel();
        var selectionModel = ganttTreePanel.getSelectionModel();
        selectionModel.deselectAll();

        me.onButtonAdd();
    },

    /**
     * Drop events inside the task tree.
     * We need to update the parent_id and sort_order of the task.
     */
    onGanttTreePanelDrop: function(node, data, overModel, dropPosition, eOpts) {
        var me = this;
        if (me.debug) console.log('PO.controller.GanttTreePanelController.onGanttTreePanelDrop: Starting');

        var records = data.records; 							// tasks dropped into new position
        var parent = null;
        me.treeRenumberStoreOldValues();     						// Remember the current values of WBS field

        // Update the parent_id of the task
        switch (dropPosition) {
        case "before":
            parent = overModel.parentNode;
            break;
        case "after":
            parent = overModel.parentNode;
            break;
        case "append":
            parent = overModel;
            break;
        default:
            alert("GanttTreePanelController.onGanttTreePanelDrop: Unknown dropPosition="+dropPosition);
            break;
        }
        var parent_id = parent.get('id');
        if (null != parent_id && "" != parent_id) {
            records.forEach(function(record) {
                record.set('parent_id', parent_id);
            });
        }

        me.treeRenumber();								// Update the tree's task numbering
        me.getGanttBarPanel().needsRedraw = true;					// Force delayed redraw

        if (me.debug) console.log('PO.controller.GanttTreePanelController.onGanttTreePanelDrop: Finished');
    },


    /**
     * Before updating the WBS numbers in treeRenumber,
     * we need to store the old values baseline in order
     * to check if they were manually modified.
     */
    treeRenumberStoreOldValues: function() {
        var me = this;
        // if (me.debug) console.log('PO.controller.GanttTreePanelController.treeRenumberStoreOldValues: Starting');

        var ganttTreePanel = me.getGanttTreePanel();
        var taskTreeStore = ganttTreePanel.getStore();
        var rootNode = taskTreeStore.getRootNode();					// Get the absolute root
        var sortOrder = 0;
        var last_wbs = [];

        // Iterate through all children of the root node and check if they are visible
        rootNode.cascadeBy(function(model) {
            
            // Fix the parent_id reference to the tasks's parent node
            var parent = model.parentNode;
            var parent_wbs = "";
            if (!!parent) {
                var parentId = ""+parent.get('id');
                var parent_id = ""+model.get('parent_id');
                if (parentId != parent_id && 0 != sortOrder && "root" != parentId) {
                    model.set('parent_id', parentId);
                }

                // Get the WBS code from the parent node
                parent_wbs = parent.get('project_wbs');
            }

            // Recalculate the WBS code
            var depth = model.getDepth()-1;
            if (depth >= 0) {
                var last_wbs_slice = last_wbs.slice(0,depth+1);
                while (last_wbs_slice.length <= depth) {
                    last_wbs_slice.push(0);
                }
                var last_wbs_digit = last_wbs_slice[depth];
                last_wbs_slice[depth] = last_wbs_digit + 1;
                last_wbs = last_wbs_slice;
                var wbs = last_wbs.join('.');

                // Store this as the old autmatic WBS
                // into a field outside the normal model
                model.data.project_wbs_old_automatic = wbs;
            }

            sortOrder++;
        });


        // if (me.debug) console.log('PO.controller.GanttTreePanelController.treeRenumberStoreOldValues: Finished');
    },

    /**
     * Update the numbering of the Gantt tasks after a 
     * change that affects the ordering including 
     * drag-and-drop events.
     *
     * Please note that this function expects that you
     * run treeRenumberStoreOldValues() before you
     * actually performed a tree change. This is necessary
     * in order to detect manual changes in the WBS,
     * which should be preserved.
     */
    treeRenumber: function() {
        var me = this;
        // if (me.debug) console.log('PO.controller.GanttTreePanelController.treeRenumber: Starting');

        var ganttTreePanel = me.getGanttTreePanel();
        var taskTreeStore = ganttTreePanel.getStore();
        var rootNode = taskTreeStore.getRootNode();					// Get the absolute root
        var sortOrder = 0;
        var duplicateHash = {};
        var last_wbs = [];

        // Iterate through all children of the root node and check if they are visible
        rootNode.cascadeBy(function(model) {
            
            // Check for duplicates
            var name = "" + (model.get('project_name').replace(/\([0-9]+\)/, '')).trim();
            var id = model.get('id');
            var list = duplicateHash[name] || [];
            list.push(model);
            duplicateHash[name] = list;

            // Fix the sort_order sequence of tasks
            var modelSortOrder = model.get('sort_order');
            if (""+modelSortOrder != ""+sortOrder && 0 != sortOrder) {
                model.set('sort_order', ""+sortOrder);
            }

            // Fix the parent_id reference to the tasks's parent node
            var parent = model.parentNode;
            var parent_wbs = "";
            if (!!parent) {
                var parentId = ""+parent.get('id');
                var parent_id = ""+model.get('parent_id');
                if (parentId != parent_id && 0 != sortOrder && "root" != parentId) {
                    model.set('parent_id', parentId);
                }

                // Get the WBS code from the parent node
                parent_wbs = parent.get('project_wbs');
            }

            // Recalculate the WBS code
            var depth = model.getDepth()-1;
            if (depth >= 0) {
                var last_wbs_slice = last_wbs.slice(0,depth+1);
                while (last_wbs_slice.length <= depth) {
                    last_wbs_slice.push(0);
                }
                var last_wbs_digit = last_wbs_slice[depth];
                last_wbs_slice[depth] = last_wbs_digit + 1;
                last_wbs = last_wbs_slice;

                var newWbs = last_wbs.join('.');
                var curWbs = model.get('project_wbs');
                var automaticWbsBeforeAction = model.data.project_wbs_old_automatic;
                if (!automaticWbsBeforeAction) automaticWbsBeforeAction = "";

                // No change? Then just skip...
                if (!(newWbs === curWbs)) {
                    // Preserve manual changes to the WBS. Only update the WBS if the
                    // previous value was generated automatically.
                    var manualChangeP = (curWbs !== automaticWbsBeforeAction);
                    if ("" === curWbs) manualChangeP = false;			// No WBS yet, probably a new task
                    if ("" === automaticWbsBeforeAction) manualChangeP = false;	// Some inconsistency, shouldn't appear...
                    if (!manualChangeP) {
                        model.set('project_wbs', newWbs);
                    }
                }

            }

            sortOrder++;
        });

        // Rename duplicate task names
        Object.keys(duplicateHash).forEach(function(key) {
            var modelList = duplicateHash[key];
            if (modelList.length > 1) {
                // Rename the items
                for (var i = 0; i < modelList.length; i++) {
                    modelList[i].set('project_name', key+" ("+ (i+1) +")");
                }
            }
        });


        // if (me.debug) console.log('PO.controller.GanttTreePanelController.treeRenumber: Finished');
    }
});
