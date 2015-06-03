<div id=@gantt_editor_id@>
<script type='text/javascript'>


// Ext.Loader.setConfig({enabled: true});
Ext.Loader.setPath('Ext.ux', '/sencha-v411/examples/ux');
Ext.Loader.setPath('PO.model', '/sencha-core/model');
Ext.Loader.setPath('PO.store', '/sencha-core/store');
Ext.Loader.setPath('PO.class', '/sencha-core/class');
Ext.Loader.setPath('PO.view.gantt', '/sencha-core/view/gantt');
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
    'PO.store.timesheet.TaskTreeStore'
]);


function launchGanttEditor(){

    var taskTreeStore = Ext.StoreManager.get('taskTreeStore');
    var statusStore = Ext.StoreManager.get('projectStatusStore');
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
                0: { color: '#ddf' },
                100: { color: '#00A' }
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

    var ganttTimeline = Ext.create('PO.view.gantt.GanttTimeline', {
        ganttTreePanel: ganttTreePanel,
        title: false,
        layout: 'border',
        region: 'south',
        width: 300,
        height: 50
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
            ganttDrawComponent,
            ganttTimeline
        ]
    });


    // Outer Gantt editor jointing the two parts (TreePanel + Draw)
    var screenSize = Ext.getBody().getViewSize();    // Size calculation based on specific ]po[ layout
    var sideBarSize = Ext.get('sidebar').getSize();
    var width = screenSize.width - sideBarSize.width - 95;
    var height = screenSize.height - 280;
    var ganttEditor = Ext.create('PO.view.gantt.GanttButtonPanel', {
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
        'ganttDrawComponent': ganttDrawComponent,
        'ganttTimeline': ganttTimeline
    });
    ganttButtonController.init(this).onLaunch(this);

    // Handle collapsable side menu
    sideBarTab.on('click', ganttButtonController.onSideBarResize, ganttButtonController);
    Ext.EventManager.onWindowResize(ganttButtonController.onWindowsResize, ganttButtonController);    // Deal with resizing the main window

};



Ext.onReady(function() {
    Ext.QuickTips.init();

    var statusStore = Ext.create('PO.store.project.ProjectStatusStore');
    var taskTreeStore = Ext.create('PO.store.timesheet.TaskTreeStore');

    // Use a "store coodinator" in order to launchGanttEditor() only
    // if all stores have been loaded:
    var coordinator = Ext.create('PO.controller.StoreLoadCoordinator', {
        stores:			[
            'projectStatusStore', 
            'taskTreeStore'
        ],
        listeners: {
            load: function() {
                // Check if the application was launched before
                if ("boolean" == typeof this.loadedP) { return; }
                // Launch the actual application.
                launchGanttEditor();
                // Mark the application as launched
                this.loadedP = true;
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

});
</script>
</div>

