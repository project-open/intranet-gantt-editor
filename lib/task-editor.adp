<div id=@task_editor_id@>
<script type='text/javascript'>

// Ext.Loader.setConfig({enabled: true});
Ext.Loader.setPath('Ext.ux', '/sencha-v411/examples/ux');
Ext.Loader.setPath('PO.model', '/sencha-core/model');
Ext.Loader.setPath('PO.store', '/sencha-core/store');
Ext.Loader.setPath('PO.class', '/sencha-core/class');
Ext.Loader.setPath('PO.controller', '/sencha-core/controller');

Ext.require([
    'Ext.data.*',
    'Ext.grid.*',
    'Ext.tree.*',
    'Ext.ux.CheckColumn',
    'PO.store.CategoryStore',
    'PO.model.timesheet.TimesheetTask',
    'PO.controller.StoreLoadCoordinator',
    'PO.store.timesheet.TaskStatusStore',
    'PO.store.timesheet.TaskTreeStore'
]);


function launchTaskEditorTreePanel(){

    var taskTreeStore = Ext.StoreManager.get('taskTreeStore');
    var taskStatusStore = Ext.StoreManager.get('taskStatusStore');

    var rowEditing = Ext.create('Ext.grid.plugin.RowEditing', {
	clicksToMoveEditor:		2,
	autoCancel:			false
    });

    var tree = Ext.create('Ext.tree.Panel', {
	title:				'Core Team Projects',
	width:				500,
	height:				300,
	renderTo:			'@task_editor_id@',
	collapsible:			true,
	useArrows:			true,
	rootVisible:			false,
	store:				taskTreeStore,
	multiSelect:			true,
	singleExpand:			false,

	// Enable in-line row editing.
	plugins:			[rowEditing],

	// Enabled drag-and-drop for the tree. Yes, that's all...
        viewConfig: {
            plugins: {
                ptype: 'treeviewdragdrop',
                containerScroll: true
            }
        },

	// the 'columns' property is now 'headers'
	columns: [{
	    xtype:			'treecolumn', //this is so we know which column will show the tree
	    text:			'Task',
	    flex:			2,
	    sortable:			true,
	    dataIndex:			'project_name',
	    editor: {
		allowBlank:		false
	    }
	},{
	    text:			'Assigned To',
	    flex:			1,
	    dataIndex:			'user',
	    sortable:			true,
	    editor: {
		allowBlank:		true
	    }
	},{
	    text:			'Start',
	    xtype:			'datecolumn',
	    format:			'Y-m-d',
	    // format:			'Y-m-d H:i:s',				// 2000-01-01 00:00:00+01
	    flex:			1,
	    dataIndex:			'start_date',
	    sortable:			true,
	    editor: {
		allowBlank:		false
	    }
	},{
	    text:			'End',
	    xtype:			'datecolumn',
	    format:			'Y-m-d',
	    flex:			1,
	    dataIndex:			'end_date_date',
	    sortable:			true,
	    editor:	{
		allowBlank:		false
	    }
	},{
	    text:			'Status',
	    flex:			1,
	    dataIndex:			'project_status_id',
	    sortable:			true,
	    renderer: function(value){
		var model = taskStatusStore.getById(value);
		var result = model.get('category');
		return result;
	    },
	    editor: {
		xtype:			'combo',
		store:			taskStatusStore,
		displayField:		'category',
		valueField:		'category_id',
	    }
	}, {
	    xtype:			'checkcolumn',
	    header:			'Done',
	    dataIndex:			'done',
	    width:			40,
	    stopSelection:		false,
	    editor: {
		xtype:			'checkbox',
		cls:			'x-grid-checkheader-editor'
	    }
	}],

	listeners: {
	    'selectionchange': function(view, records) {
		if (1 == records.length) {
		    // Exactly one record enabled
		    var record = records[0];
		    tree.down('#removeTask').setDisabled(!record.isLeaf());
		} else {
		    // Zero or two or more records enabled
		    tree.down('#removeTask').setDisabled(true);
		}
	    }
	},

	// Toolbar for adding and deleting tasks
	tbar: [{
	    text:			'Add Task',
	    iconCls:			'task-add',
	    handler : function() {
		rowEditing.cancelEdit();

		// Create a model instance
		var r = Ext.create('PO.model.timesheet.TimesheetTask', {
		    project_name: "New Task",
		    project_nr: "task_0018",
		    parent_id: "709261",
		    company_id: "500633",
		    start_date: "2013-09-19 12:00:00+02",
		    end_date: "2013-09-20 12:00:00+02",
		    percent_completed: "0",
		    project_status_id: "76",
		    project_type_id: "100"
		});

		taskTreeStore.sync();
		var selectionModel = tree.getSelectionModel();
		var lastSelected = selectionModel.getLastSelected();

		// ToDo: Appending the new task at the lastSelected does't work for some reasons.
		// Also, the newly added task should be a "task" and not a folder.
		var root = taskTreeStore.getRootNode();
		// root.appendChild(r);
		lastSelected.appendChild(r);
	    }
	}, {
	    itemId:			'removeTask',
	    text:			'Remove Task',
	    iconCls:			'task-remove',
	    handler: function() {
		rowEditing.cancelEdit();
		var selectionModel = tree.getSelectionModel();
		var lastSelected = selectionModel.getLastSelected();
		var parent = lastSelected.parentNode;
		var lastSelectedIndex = parent.indexOf(lastSelected);

		// Remove the selected element
		lastSelected.remove();

		var newNode = parent.getChildAt(lastSelectedIndex);
		if (typeof(newNode) == "undefined") {
		    lastSelectedIndex = lastSelectedIndex -1;
		    if (lastSelectedIndex < 0) { lastSelectedIndex = 0; }
		    newNode = parent.getChildAt(lastSelectedIndex);
		}

		if (typeof(newNode) == "undefined") {
		    // lastSelected was the last child of it's parent, so select the parent.
                    selectionModel.select(parent);
		} else {
		    newNode = parent.getChildAt(lastSelectedIndex);
		    selectionModel.select(newNode);
		}

	    },
	    disabled:			true
	}]
    });
};



Ext.onReady(function() {
    Ext.QuickTips.init();

    var taskStatusStore = Ext.create('PO.store.timesheet.TaskStatusStore');
    var taskTreeStore = Ext.create('PO.store.timesheet.TaskTreeStore');

    // Use a "store coodinator" in order to launchTaskEditorTreePanel() only
    // if all stores have been loaded:
    var coordinatior = Ext.create('PO.controller.StoreLoadCoordinator', {
	stores:			[
	    'taskStatusStore', 
	    'taskTreeStore'
	],
	listeners: {
	    load: function() {
		// Launch the actual application.
		launchTaskEditorTreePanel();
	    }
	}
    });

    // Load stores that need parameters
    taskTreeStore.getProxy().extraParams = { project_id: @project_id@ };
    taskTreeStore.load();
});
</script>
</div>

<if "" ne @data_list@>
</if>
